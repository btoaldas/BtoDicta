import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Control verificado de Spotify Desktop para una orden de REPRODUCIR.
/// Spotify permite abrir una búsqueda con su esquema oficial, pero no expone
/// búsqueda por AppleScript. Después de abrirla, identificamos el primer botón
/// visible «Reproducir» mediante Accesibilidad, lo pulsamos y comprobamos el
/// estado real del reproductor antes de anunciar éxito.
enum SpotifyControl {
    struct Resultado {
        let ok: Bool
        let detalle: String
    }

    private struct Estado {
        let reproduciendo: Bool
        let titulo: String
        let artista: String
        let uri: String
    }

    private static func atributo<T>(_ elemento: AXUIElement, _ nombre: CFString) -> T? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, nombre, &valor) == .success else {
            return nil
        }
        return valor as? T
    }

    static func esBotonReproducir(rol: String, descripcion: String, titulo: String) -> Bool {
        guard rol == kAXButtonRole as String else { return false }
        let etiqueta = PerfilAgente.normalizar(descripcion.isEmpty ? titulo : descripcion)
        return etiqueta == "reproducir" || etiqueta == "play"
    }

    private static func urlBusqueda(_ consulta: String) -> URL? {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "+&=?#")
        guard let q = consulta.addingPercentEncoding(withAllowedCharacters: permitidos) else {
            return nil
        }
        return URL(string: "spotify:search:\(q)")
    }

    private static func estado() -> Estado {
        let fuente = """
        tell application id "com.spotify.client"
            set estadoBeto to (player state as string)
            set tituloBeto to ""
            set artistaBeto to ""
            set uriBeto to ""
            try
                set tituloBeto to name of current track as string
                set artistaBeto to artist of current track as string
                set uriBeto to spotify url of current track as string
            end try
            return estadoBeto & linefeed & tituloBeto & linefeed & artistaBeto & linefeed & uriBeto
        end tell
        """
        var error: NSDictionary?
        let salida = NSAppleScript(source: fuente)?.executeAndReturnError(&error).stringValue ?? ""
        guard error == nil else { return .init(reproduciendo: false, titulo: "", artista: "", uri: "") }
        let lineas = salida.components(separatedBy: .newlines)
        return .init(reproduciendo: lineas.first?.lowercased() == "playing",
                     titulo: lineas.count > 1 ? lineas[1] : "",
                     artista: lineas.count > 2 ? lineas[2] : "",
                     uri: lineas.count > 3 ? lineas[3] : "")
    }

    private static func pausarSiHaceFalta() {
        let fuente = #"tell application id "com.spotify.client" to if player state is playing then pause"#
        var error: NSDictionary?
        _ = NSAppleScript(source: fuente)?.executeAndReturnError(&error)
    }

    /// Spotify (Electron) no publica su árbol web hasta que un cliente AX
    /// solicita accesibilidad manual. Después, AXElementAtPosition identifica
    /// correctamente el botón verde por su rol y etiqueta, sin depender de una
    /// coordenada fija ni del tamaño de la ventana.
    private static func primerBotonReproducir(_ app: NSRunningApplication) -> AXUIElement? {
        let raiz = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(raiz, "AXEnhancedUserInterface" as CFString,
                                         kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(raiz, "AXManualAccessibility" as CFString,
                                         kCFBooleanTrue)
        guard let ventanas: [AXUIElement] = atributo(raiz, kAXWindowsAttribute as CFString) else {
            return nil
        }
        for ventana in ventanas {
            var origen = CGPoint.zero, tamano = CGSize.zero
            guard let posicion: AXValue = atributo(ventana, kAXPositionAttribute as CFString),
                  let dimensiones: AXValue = atributo(ventana, kAXSizeAttribute as CFString),
                  AXValueGetValue(posicion, .cgPoint, &origen),
                  AXValueGetValue(dimensiones, .cgSize, &tamano),
                  tamano.width >= 400, tamano.height >= 350 else { continue }

            // Excluye barra lateral y reproductor inferior. Recorre de arriba
            // hacia abajo y de derecha a izquierda: el primero encontrado es el
            // botón principal del primer resultado visible.
            let xMin = origen.x + max(210, tamano.width * 0.34)
            let xMax = origen.x + tamano.width - 18
            let yMin = origen.y + 68
            let yMax = origen.y + tamano.height - 108
            guard xMin < xMax, yMin < yMax else { continue }
            var y = yMin
            while y <= yMax {
                var x = xMax
                while x >= xMin {
                    var golpe: AXUIElement?
                    if AXUIElementCopyElementAtPosition(raiz, Float(x), Float(y), &golpe) == .success,
                       let elemento = golpe {
                        let rol: String = atributo(elemento, kAXRoleAttribute as CFString) ?? ""
                        let descripcion: String = atributo(elemento, kAXDescriptionAttribute as CFString) ?? ""
                        let titulo: String = atributo(elemento, kAXTitleAttribute as CFString) ?? ""
                        if esBotonReproducir(rol: rol, descripcion: descripcion, titulo: titulo) {
                            return elemento
                        }
                    }
                    x -= 14
                }
                y += 14
            }
        }
        return nil
    }

    /// Respaldo visual seguro para Spotify/Electron: algunas versiones exponen
    /// el botón con AXElementAtPosition pero no lo enumeran en el árbol. Si el
    /// usuario ya concedió Grabación de pantalla, capturamos SOLO la ventana de
    /// Spotify y buscamos el componente grande del verde oficial. La ubicación
    /// se deriva de la ventana real; no hay coordenadas fijas.
    private static func centroBotonVerde(en imagen: CGImage, marco: CGRect) -> CGPoint? {
        let ancho = imagen.width, alto = imagen.height
        guard ancho >= 300, alto >= 250 else { return nil }
        var pixeles = [UInt8](repeating: 0, count: ancho * alto * 4)
        guard let contexto = CGContext(data: &pixeles, width: ancho, height: alto,
                                       bitsPerComponent: 8, bytesPerRow: ancho * 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        contexto.draw(imagen, in: CGRect(x: 0, y: 0, width: ancho, height: alto))

        var mascara = [UInt8](repeating: 0, count: ancho * alto)
        let xInicio = ancho / 4
        let yInicio = alto / 7       // excluye controles del reproductor inferior
        let yFin = alto * 19 / 20
        for y in yInicio..<yFin {
            for x in xInicio..<ancho {
                let p = (y * ancho + x) * 4
                let r = Int(pixeles[p]), g = Int(pixeles[p + 1]), b = Int(pixeles[p + 2])
                // Spotify green #1ED760, tolerando conversión de color/premultiplicado.
                if r >= 5, r <= 105, g >= 145, g <= 255, b >= 25, b <= 165,
                   g > r * 2, g * 5 > b * 7 {
                    mascara[y * ancho + x] = 1
                }
            }
        }

        var mejor: (cantidad: Int, minX: Int, maxX: Int, minY: Int, maxY: Int)?
        var pila: [Int] = []
        for y in yInicio..<yFin {
            for x in xInicio..<ancho {
                let semilla = y * ancho + x
                guard mascara[semilla] == 1 else { continue }
                mascara[semilla] = 2; pila.removeAll(keepingCapacity: true); pila.append(semilla)
                var cantidad = 0, minX = x, maxX = x, minY = y, maxY = y
                while let indice = pila.popLast() {
                    let px = indice % ancho, py = indice / ancho
                    cantidad += 1
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                    if px > xInicio {
                        let n = indice - 1
                        if mascara[n] == 1 { mascara[n] = 2; pila.append(n) }
                    }
                    if px + 1 < ancho {
                        let n = indice + 1
                        if mascara[n] == 1 { mascara[n] = 2; pila.append(n) }
                    }
                    if py > yInicio {
                        let n = indice - ancho
                        if mascara[n] == 1 { mascara[n] = 2; pila.append(n) }
                    }
                    if py + 1 < yFin {
                        let n = indice + ancho
                        if mascara[n] == 1 { mascara[n] = 2; pila.append(n) }
                    }
                }
                let w = CGFloat(maxX - minX + 1) / CGFloat(ancho) * marco.width
                let h = CGFloat(maxY - minY + 1) / CGFloat(alto) * marco.height
                let proporcion = h > 0 ? w / h : 0
                guard cantidad >= 90, w >= 28, w <= 92, h >= 28, h <= 92,
                      proporcion >= 0.65, proporcion <= 1.35 else { continue }
                if mejor == nil || cantidad > mejor!.cantidad {
                    mejor = (cantidad, minX, maxX, minY, maxY)
                }
            }
        }
        guard let c = mejor else { return nil }
        let cx = CGFloat(c.minX + c.maxX) / 2 / CGFloat(ancho)
        // SCScreenshotManager entrega las filas del bitmap desde la parte
        // superior de la ventana, igual que el sistema de coordenadas AX.
        let cyDesdeArriba = CGFloat(c.minY + c.maxY) / 2 / CGFloat(alto)
        return CGPoint(x: marco.minX + cx * marco.width,
                       y: marco.minY + cyDesdeArriba * marco.height)
    }

    private static func localizarBotonVisual(
        _ app: NSRunningApplication,
        completion: @escaping (CGPoint?) -> Void
    ) {
        guard CGPreflightScreenCaptureAccess() else { completion(nil); return }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) {
            contenido, _ in
            guard let ventana = contenido?.windows.first(where: {
                $0.owningApplication?.bundleIdentifier == "com.spotify.client"
                    && $0.frame.width >= 400 && $0.frame.height >= 350
            }) else { DispatchQueue.main.async { completion(nil) }; return }
            let configuracion = SCStreamConfiguration()
            configuracion.width = Int(ventana.frame.width * 2)
            configuracion.height = Int(ventana.frame.height * 2)
            configuracion.showsCursor = false
            configuracion.ignoreShadowsSingleWindow = true
            let filtro = SCContentFilter(desktopIndependentWindow: ventana)
            SCScreenshotManager.captureImage(contentFilter: filtro,
                                             configuration: configuracion) { imagen, _ in
                let punto = imagen.flatMap { centroBotonVerde(en: $0, marco: ventana.frame) }
                DispatchQueue.main.async { completion(punto) }
            }
        }
    }

    private static func clickSeguro(en punto: CGPoint, app: NSRunningApplication) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.spotify.client",
              let mover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: punto, mouseButton: .left),
              let bajar = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                  mouseCursorPosition: punto, mouseButton: .left),
              let subir = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                  mouseCursorPosition: punto, mouseButton: .left) else { return false }
        AgenteLog.registrar("spotify_control", ["ruta": "visual", "x": punto.x, "y": punto.y])
        mover.post(tap: .cghidEventTap)
        bajar.post(tap: .cghidEventTap); subir.post(tap: .cghidEventTap)
        return true
    }

    private static func verificar(_ intento: Int, completion: @escaping (Resultado) -> Void) {
        let esperas: [TimeInterval] = [0.45, 0.75, 1.1, 1.5]
        DispatchQueue.main.asyncAfter(deadline: .now() + esperas[min(intento, esperas.count - 1)]) {
            let actual = estado()
            if actual.reproduciendo {
                let pista = [actual.titulo, actual.artista].filter { !$0.isEmpty }.joined(separator: " — ")
                completion(.init(ok: true,
                                 detalle: pista.isEmpty ? "Spotify está reproduciendo." : "Reproduciendo «\(pista)» en Spotify."))
            } else if intento + 1 < esperas.count {
                verificar(intento + 1, completion: completion)
            } else {
                completion(.init(ok: false,
                                 detalle: "Spotify abrió la búsqueda, pero no confirmó la reproducción."))
            }
        }
    }

    static func reproducirPrimera(_ consulta: String,
                                  completion: @escaping (Resultado) -> Void) {
        let trabajo = {
            let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2, q.count <= 300,
                  AXIsProcessTrusted(),
                  NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.spotify.client") != nil,
                  let url = urlBusqueda(q) else {
                completion(.init(ok: false,
                                 detalle: "Spotify no está disponible o falta permiso de Accesibilidad."))
                return
            }
            pausarSiHaceFalta()
            guard NSWorkspace.shared.open(url) else {
                completion(.init(ok: false, detalle: "No pude abrir la búsqueda en Spotify."))
                return
            }

            let esperas: [TimeInterval] = [0.55, 0.75, 0.95, 1.2, 1.55, 1.9]
            func buscar(_ intento: Int) {
                DispatchQueue.main.asyncAfter(deadline: .now() + esperas[intento]) {
                    guard let app = NSRunningApplication.runningApplications(
                        withBundleIdentifier: "com.spotify.client").first else {
                        if intento + 1 < esperas.count { buscar(intento + 1) }
                        else { completion(.init(ok: false, detalle: "Spotify no llegó a abrir.")) }
                        return
                    }
                    app.activate(options: [.activateAllWindows])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        if let boton = primerBotonReproducir(app),
                           AXUIElementPerformAction(boton, kAXPressAction as CFString) == .success {
                            verificar(0, completion: completion)
                            return
                        }
                        // Electron puede ocultar el árbol web, pero la ventana
                        // capturada sigue siendo verificable. El clic solo se
                        // permite sobre el componente verde detectado y mientras
                        // Spotify sigue al frente.
                        localizarBotonVisual(app) { punto in
                            if let punto, clickSeguro(en: punto, app: app) {
                                verificar(0, completion: completion)
                            } else if intento + 1 < esperas.count {
                                buscar(intento + 1)
                            } else {
                                completion(.init(ok: false,
                                    detalle: "Spotify abrió la búsqueda, pero no expuso un primer resultado reproducible."))
                            }
                        }
                    }
                }
            }
            buscar(0)
        }
        if Thread.isMainThread { trabajo() } else { DispatchQueue.main.async(execute: trabajo) }
    }
}
