import AppKit
import ApplicationServices
import Foundation

/// Búsqueda y reproducción verificadas para YouTube Music.
///
/// Prefiere una app/PWA instalada con ese nombre y no depende de Brave, Chrome
/// ni de un bundle concreto. Si no existe, abre la búsqueda HTTPS en el
/// navegador predeterminado. Para una orden `reproducir`, pulsa únicamente un
/// botón AX etiquetado con el resultado y comprueba que la barra del reproductor
/// de ESA ventana cambió a «Pausar» y corresponde a la consulta/resultados.
enum YouTubeMusicControl {
    struct Resultado {
        let ok: Bool
        let reproduciendo: Bool
        let via: String
        let detalle: String
    }

    private struct EstadoPlayer {
        let reproduciendo: Bool
        let titulo: String
        let contexto: String
    }

    private struct Candidato {
        let elemento: AXUIElement
        let descripcion: String
        let posicion: CGPoint
    }

    private static let limiteElementos = 5_500
    private static let navegadores: Set<String> = [
        "com.apple.safari", "com.google.chrome", "com.google.chrome.beta",
        "com.microsoft.edgemac", "com.brave.browser", "org.mozilla.firefox",
        "company.thebrowser.browser", "com.vivaldi.vivaldi", "com.operasoftware.opera",
        "org.chromium.chromium", "com.kagi.kagimacos"
    ]

    private static func traza(_ etapa: String, _ campos: [String: Any] = [:]) {
        var datos = campos
        datos["etapa"] = etapa
        AgenteLog.registrar("youtube_music_control", datos)
        if ProcessInfo.processInfo.environment["BTODICTA_MUSICFLOWTEST"] != nil {
            print("YTMUSICTRACE \(etapa) \(campos)")
            fflush(stdout)
        }
    }

    private static func atributo<T>(_ elemento: AXUIElement, _ nombre: CFString) -> T? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, nombre, &valor) == .success else {
            return nil
        }
        return valor as? T
    }

    private static func elementos(_ raiz: AXUIElement, limite: Int = limiteElementos)
        -> [AXUIElement] {
        var cola = [raiz]
        var salida: [AXUIElement] = []
        var vistos = Set<CFHashCode>()
        var indice = 0
        while indice < cola.count, salida.count < limite {
            let elemento = cola[indice]
            indice += 1
            guard vistos.insert(CFHash(elemento)).inserted else { continue }
            salida.append(elemento)
            if let hijos: [AXUIElement] = atributo(elemento, kAXChildrenAttribute as CFString) {
                cola.append(contentsOf: hijos.prefix(900))
            }
        }
        return salida
    }

    private static func texto(_ elemento: AXUIElement) -> String {
        let titulo: String = atributo(elemento, kAXTitleAttribute as CFString) ?? ""
        let descripcion: String = atributo(elemento, kAXDescriptionAttribute as CFString) ?? ""
        let valor: String = atributo(elemento, kAXValueAttribute as CFString) ?? ""
        return [descripcion, titulo, valor].first { !$0.isEmpty } ?? ""
    }

    private static func punto(_ elemento: AXUIElement) -> CGPoint? {
        var origen = CGPoint.zero
        var tamano = CGSize.zero
        guard let p: AXValue = atributo(elemento, kAXPositionAttribute as CFString),
              let s: AXValue = atributo(elemento, kAXSizeAttribute as CFString),
              AXValueGetValue(p, .cgPoint, &origen),
              AXValueGetValue(s, .cgSize, &tamano),
              tamano.width >= 2, tamano.height >= 2 else { return nil }
        return CGPoint(x: origen.x + tamano.width / 2, y: origen.y + tamano.height / 2)
    }

    private static func raizVisible(_ app: NSRunningApplication) -> AXUIElement {
        let raiz = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(raiz, "AXEnhancedUserInterface" as CFString,
                                         kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(raiz, "AXManualAccessibility" as CFString,
                                         kCFBooleanTrue)
        let ventana: AXUIElement? = atributo(raiz, kAXFocusedWindowAttribute as CFString)
            ?? atributo(raiz, kAXMainWindowAttribute as CFString)
        return ventana ?? raiz
    }

    private static func tieneVentanaUtil(_ app: NSRunningApplication) -> Bool {
        let raiz = AXUIElementCreateApplication(app.processIdentifier)
        guard let ventanas: [AXUIElement] = atributo(raiz, kAXWindowsAttribute as CFString) else {
            return false
        }
        return ventanas.contains { ventana in
            var tamano = CGSize.zero
            guard let valor: AXValue = atributo(ventana, kAXSizeAttribute as CFString),
                  AXValueGetValue(valor, .cgSize, &tamano) else { return false }
            return tamano.width >= 360 && tamano.height >= 280
        }
    }

    private static func aplicacionActual(_ original: NSRunningApplication) -> NSRunningApplication {
        guard let bundle = original.bundleIdentifier, !bundle.isEmpty else { return original }
        let candidatas = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .filter { !$0.isTerminated }
        return candidatas.first(where: tieneVentanaUtil) ?? candidatas.first ?? original
    }

    private static func normalizar(_ texto: String) -> String {
        AplicacionesMac.normalizar(texto)
    }

    private static let vacias: Set<String> = [
        "a", "al", "de", "del", "el", "en", "la", "las", "lo", "los", "para", "por",
        "un", "una", "unos", "unas", "y", "musica", "music", "cancion", "canciones",
        "song", "songs", "tema", "playlist", "reproducir", "play"
    ]

    private static func claves(_ texto: String) -> Set<String> {
        let todas = normalizar(texto).split(separator: " ").map(String.init)
        let utiles = todas.filter { $0.count >= 2 && !vacias.contains($0) }
        return Set((utiles.isEmpty ? todas : utiles).map { palabra in
            palabra.count >= 5 && palabra.hasSuffix("s") ? String(palabra.dropLast()) : palabra
        })
    }

    /// Función pura para QA: evita aceptar una pista anterior que ya estaba
    /// sonando. Con palabras genéricas fuera, al menos la mitad de la consulta
    /// debe aparecer en el título/artista/álbum verificado.
    static func coincide(consulta: String, contexto: String) -> Bool {
        let q = claves(consulta)
        guard !q.isEmpty else { return true }
        let c = claves(contexto)
        let aciertos = q.intersection(c).count
        return aciertos > 0 && Double(aciertos) / Double(q.count) >= 0.5
    }

    static func esBotonResultado(rol: String, descripcion: String) -> Bool {
        guard rol == kAXButtonRole as String else { return false }
        let d = normalizar(descripcion)
        return (d.hasPrefix("reproducir ") && d.count > "reproducir ".count)
            || (d.hasPrefix("play ") && d.count > "play ".count)
    }

    /// Descubre PWAs y apps nativas por nombre/alias. El hash del PWA de Brave
    /// no está inyectado: una instalación de Chrome/Edge funciona igual.
    static func aplicacionInstalada(en apps: [AplicacionMac] = AplicacionesMac.todas())
        -> AplicacionMac? {
        apps.first { app in
            normalizar(app.nombre) == "youtube music"
                || app.alias.contains(where: { normalizar($0) == "youtube music" })
        }
    }

    private static func campoBusqueda(en raiz: AXUIElement) -> AXUIElement? {
        let campos = elementos(raiz).compactMap { e -> (AXUIElement, CGPoint)? in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            guard [kAXComboBoxRole as String, kAXTextFieldRole as String, "AXSearchField"]
                .contains(rol), let ubicacion = punto(e) else { return nil }
            var editable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString,
                                                 &editable) == .success,
                  editable.boolValue else { return nil }
            return (e, ubicacion)
        }
        let ordenados = campos.sorted { izquierda, derecha in
            if izquierda.1.y == derecha.1.y { return izquierda.1.x < derecha.1.x }
            return izquierda.1.y < derecha.1.y
        }
        return ordenados.first?.0
    }

    private static func botonBuscar(en raiz: AXUIElement) -> AXUIElement? {
        elementos(raiz).first { e in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            guard rol == kAXButtonRole as String else { return false }
            let t = normalizar(texto(e))
            return ["iniciar busqueda", "buscar", "start search", "search"].contains(t)
        }
    }

    private static func primerResultado(en raiz: AXUIElement) -> Candidato? {
        elementos(raiz).compactMap { e -> Candidato? in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            let descripcion = texto(e)
            guard esBotonResultado(rol: rol, descripcion: descripcion),
                  let posicion = punto(e) else { return nil }
            return Candidato(elemento: e, descripcion: descripcion, posicion: posicion)
        }.sorted {
            $0.posicion.y == $1.posicion.y
                ? $0.posicion.x < $1.posicion.x
                : $0.posicion.y < $1.posicion.y
        }.first
    }

    private static func estadoPlayer(en raiz: AXUIElement) -> EstadoPlayer {
        guard let barra = elementos(raiz).first(where: { e in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            let d = normalizar(texto(e))
            return rol == kAXToolbarRole as String
                && (d.contains("barra del reproductor") || d.contains("player bar")
                    || d.contains("player controls"))
        }) else { return .init(reproduciendo: false, titulo: "", contexto: "") }

        let hijos = elementos(barra, limite: 450)
        let reproduciendo = hijos.contains { e in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            let d = normalizar(texto(e))
            return rol == kAXButtonRole as String && ["pausar", "pause"].contains(d)
        }
        let titulo = hijos.compactMap { e -> String? in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            guard rol == kAXHeadingRole as String else { return nil }
            let t = texto(e).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }.first ?? ""
        let contexto = hijos.compactMap { e -> String? in
            let t = texto(e).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }.joined(separator: " · ")
        return .init(reproduciendo: reproduciendo, titulo: titulo, contexto: contexto)
    }

    private static func paginaLista(_ raiz: AXUIElement, consulta: String) -> Bool {
        let todos = elementos(raiz)
        let q = normalizar(consulta)
        let campoOK = todos.contains { e in
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            guard [kAXComboBoxRole as String, kAXTextFieldRole as String, "AXSearchField"]
                .contains(rol) else { return false }
            let valor: String = atributo(e, kAXValueAttribute as CFString) ?? ""
            return normalizar(valor).contains(q)
        }
        let marcador = todos.contains { e in
            let t = normalizar(texto(e))
            return t.contains("se muestran resultados") || t.contains("showing results")
                || t.contains("resultados de") || t.contains("search results")
        }
        return campoOK && (marcador || primerResultado(en: raiz) != nil)
    }

    private static func clickSeguro(_ elemento: AXUIElement, app: NSRunningApplication,
                                    completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted(), let centro = punto(elemento) else {
            completion(false); return
        }
        activarFrente(app) { activada in
            guard activada,
                  let mover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                      mouseCursorPosition: centro, mouseButton: .left),
                  let bajar = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                      mouseCursorPosition: centro, mouseButton: .left),
                  let subir = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                      mouseCursorPosition: centro, mouseButton: .left) else {
                completion(false); return
            }
            mover.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                        == app.processIdentifier else { completion(false); return }
                bajar.post(tap: .cghidEventTap)
                subir.post(tap: .cghidEventTap)
                completion(true)
            }
        }
    }

    private static func activarFrente(_ app: NSRunningApplication,
                                      completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            completion(true); return
        }
        _ = app.unhide()
        _ = app.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                completion(true); return
            }
            guard let url = app.bundleURL else { completion(false); return }
            let configuracion = NSWorkspace.OpenConfiguration()
            configuracion.activates = true
            configuracion.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuracion) {
                _, error in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    let ok = error == nil
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier
                            == app.processIdentifier
                    traza("activar_launchservices", ["ok": ok,
                        "bundle": app.bundleIdentifier ?? "",
                        "front": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""])
                    completion(ok)
                }
            }
        }
    }

    private static func pulsarEnter(app: NSRunningApplication) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let bajar = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let subir = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else {
            return false
        }
        bajar.post(tap: .cghidEventTap); subir.post(tap: .cghidEventTap)
        return true
    }

    private static func prepararBusqueda(_ consulta: String, app: NSRunningApplication,
                                         intento: Int = 0,
                                         completion: @escaping (Bool) -> Void) {
        guard intento < 7 else { completion(false); return }
        let actual = aplicacionActual(app)
        if actual.processIdentifier != app.processIdentifier {
            traza("proceso_pwa_actualizado", ["antes": app.processIdentifier,
                                               "ahora": actual.processIdentifier])
        }
        let raiz = raizVisible(actual)
        if let campo = campoBusqueda(en: raiz) {
            let rol: String = atributo(campo, kAXRoleAttribute as CFString) ?? ""
            traza("campo_busqueda", ["intento": intento, "rol": rol,
                                      "valor": texto(campo)])
            _ = AXUIElementSetAttributeValue(campo, kAXFocusedAttribute as CFString,
                                             kCFBooleanTrue)
            let r = AXUIElementSetAttributeValue(campo, kAXValueAttribute as CFString,
                                                 consulta as CFString)
            guard r == .success else {
                traza("campo_no_editable", ["intento": intento, "error": r.rawValue])
                completion(false); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                let enter = pulsarEnter(app: actual)
                traza("consulta_enviada", ["intento": intento, "enter": enter])
                completion(enter)
            }
            return
        }
        if let boton = botonBuscar(en: raiz) {
            traza("boton_busqueda", ["intento": intento, "texto": texto(boton),
                                      "front": NSWorkspace.shared.frontmostApplication?
                                        .bundleIdentifier ?? ""])
            clickSeguro(boton, app: actual) { ok in
                traza("boton_busqueda_click", ["intento": intento, "ok": ok])
                DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 0.34 : 0.20)) {
                    prepararBusqueda(consulta, app: actual, intento: intento + 1,
                                     completion: completion)
                }
            }
            return
        }
        traza("sin_control_busqueda", ["intento": intento,
                                        "front": NSWorkspace.shared.frontmostApplication?
                                            .bundleIdentifier ?? ""])
        let espera = min(0.80, 0.25 + Double(intento) * 0.09)
        DispatchQueue.main.asyncAfter(deadline: .now() + espera) {
            prepararBusqueda(consulta, app: actual, intento: intento + 1, completion: completion)
        }
    }

    private static func esperarResultados(_ consulta: String, app: NSRunningApplication,
                                          reproducir: Bool, via: String, intento: Int = 0,
                                          completion: @escaping (Resultado) -> Void) {
        let esperas: [TimeInterval] = [0.45, 0.55, 0.70, 0.90, 1.10, 1.35, 1.60]
        guard intento < esperas.count else {
            completion(.init(ok: false, reproduciendo: false, via: via,
                             detalle: "YouTube Music no terminó de cargar los resultados."))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + esperas[intento]) {
            let actual = aplicacionActual(app)
            let raiz = raizVisible(actual)
            guard paginaLista(raiz, consulta: consulta) else {
                traza("esperando_resultados", ["via": via, "intento": intento])
                esperarResultados(consulta, app: actual, reproducir: reproducir, via: via,
                                  intento: intento + 1, completion: completion)
                return
            }
            guard reproducir else {
                completion(.init(ok: true, reproduciendo: false, via: via,
                                 detalle: "Abrí la búsqueda de «\(consulta)» en YouTube Music."))
                return
            }
            guard let candidato = primerResultado(en: raiz) else {
                completion(.init(ok: true, reproduciendo: false, via: via,
                                 detalle: "YouTube Music mostró la búsqueda, pero no expuso un resultado reproducible."))
                return
            }
            traza("candidato", ["via": via, "descripcion": candidato.descripcion])
            let estadoAntes = estadoPlayer(en: raiz)
            clickSeguro(candidato.elemento, app: actual) { clickOK in
                guard clickOK else {
                    completion(.init(ok: true, reproduciendo: false, via: via,
                                     detalle: "YouTube Music mostró la búsqueda, pero no pude activar el primer resultado."))
                    return
                }
                verificarReproduccion(consulta, candidato: candidato.descripcion, app: actual,
                                      via: via, antes: estadoAntes, completion: completion)
            }
        }
    }

    private static func verificarReproduccion(_ consulta: String, candidato: String,
                                              app: NSRunningApplication, via: String,
                                              antes: EstadoPlayer,
                                              intento: Int = 0,
                                              completion: @escaping (Resultado) -> Void) {
        let esperas: [TimeInterval] = [0.45, 0.70, 1.0, 1.35, 1.70]
        guard intento < esperas.count else {
            completion(.init(ok: true, reproduciendo: false, via: via,
                             detalle: "YouTube Music abrió la búsqueda, pero no confirmó la reproducción."))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + esperas[intento]) {
            let actual = aplicacionActual(app)
            let estado = estadoPlayer(en: raizVisible(actual))
            let contexto = "\(estado.titulo) \(estado.contexto)"
            let coincideConsulta = coincide(consulta: consulta, contexto: contexto)
            let coincideCandidato = coincide(consulta: candidato, contexto: contexto)
            let cambioReal = !antes.reproduciendo
                || estado.titulo != antes.titulo || estado.contexto != antes.contexto
            traza("verificar", ["via": via, "intento": intento,
                                 "reproduciendo": estado.reproduciendo,
                                 "titulo": estado.titulo,
                                 "cambio": cambioReal,
                                 "consulta_ok": coincideConsulta,
                                 "candidato_ok": coincideCandidato])
            if estado.reproduciendo, cambioReal || coincideConsulta || coincideCandidato {
                let pista = estado.titulo.isEmpty ? candidato : estado.titulo
                completion(.init(ok: true, reproduciendo: true, via: via,
                                 detalle: "Reproduciendo «\(pista)» en YouTube Music."))
            } else {
                verificarReproduccion(consulta, candidato: candidato, app: actual, via: via,
                                      antes: antes, intento: intento + 1, completion: completion)
            }
        }
    }

    private static func urlWeb(_ consulta: String) -> URL? {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "+&=?#")
        guard let q = consulta.addingPercentEncoding(withAllowedCharacters: permitidos) else {
            return nil
        }
        return URL(string: "https://music.youtube.com/search?q=\(q)")
    }

    private static func abrirWeb(_ consulta: String, reproducir: Bool,
                                 completion: @escaping (Resultado) -> Void) {
        traza("abrir_web", ["consulta": consulta, "reproducir": reproducir,
                             "ax": AXIsProcessTrusted()])
        guard let url = urlWeb(consulta), NSWorkspace.shared.open(url) else {
            completion(.init(ok: false, reproduciendo: false, via: "web",
                             detalle: "No pude abrir YouTube Music en la web."))
            return
        }
        guard AXIsProcessTrusted(), reproducir else {
            completion(.init(ok: true, reproduciendo: false, via: "web",
                             detalle: "Abrí la búsqueda de «\(consulta)» en YouTube Music web."))
            return
        }

        func encontrarNavegador(_ intento: Int) {
            guard intento < 9 else {
                completion(.init(ok: true, reproduciendo: false, via: "web",
                                 detalle: "Abrí YouTube Music web, pero el navegador no quedó disponible para reproducir."))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (0.35 + Double(intento) * 0.16)) {
                guard let app = NSWorkspace.shared.frontmostApplication else {
                    encontrarNavegador(intento + 1); return
                }
                let bundle = app.bundleIdentifier?.lowercased() ?? ""
                guard navegadores.contains(bundle) || app.localizedName?.lowercased()
                    .contains("browser") == true else {
                    encontrarNavegador(intento + 1); return
                }
                traza("navegador", ["bundle": bundle, "nombre": app.localizedName ?? ""])
                esperarResultados(consulta, app: app, reproducir: true, via: "web",
                                  completion: completion)
            }
        }
        encontrarNavegador(0)
    }

    private static func abrirApp(_ app: AplicacionMac, consulta: String, reproducir: Bool,
                                 completion: @escaping (Resultado) -> Void) {
        guard AXIsProcessTrusted() else {
            traza("app_sin_ax", ["bundle": app.bundleId])
            abrirWeb(consulta, reproducir: reproducir, completion: completion)
            return
        }
        traza("abrir_app", ["bundle": app.bundleId, "ruta": app.ruta])
        let arrancar: (NSRunningApplication, TimeInterval) -> Void = { running, esperaInicial in
            activarFrente(running) { activada in
                traza("activar_app", ["ok": activada, "bundle": app.bundleId])
                DispatchQueue.main.asyncAfter(deadline: .now() + esperaInicial) {
                    prepararBusqueda(consulta, app: running) { ok in
                        traza("busqueda_preparada", ["ok": ok, "bundle": app.bundleId])
                        guard ok else {
                            abrirWeb(consulta, reproducir: reproducir, completion: completion)
                            return
                        }
                        esperarResultados(consulta, app: running, reproducir: reproducir,
                                          via: "app", completion: { resultado in
                            if reproducir, !resultado.reproduciendo {
                                abrirWeb(consulta, reproducir: true, completion: completion)
                            } else {
                                completion(resultado)
                            }
                        })
                    }
                }
            }
        }
        func lanzar() {
            NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) {
                running, error in
                DispatchQueue.main.async {
                    if let running, error == nil { arrancar(running, 1.0) }
                    else { abrirWeb(consulta, reproducir: reproducir, completion: completion) }
                }
            }
        }
        let procesos = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId)
            .filter { !$0.isTerminated }
        if let visible = procesos.first(where: tieneVentanaUtil) {
            arrancar(visible, 0.45)
        } else if let running = procesos.first {
            // Las PWAs de Chromium pueden dejar un app_mode_loader vivo
            // después de cerrar su última ventana. LaunchServices lo toma
            // por “abierto” y no recrea nada. Cerramos solo ese proceso sin
            // ventana (nunca el navegador principal) y lo relanzamos.
            traza("reiniciar_app_sin_ventana", ["bundle": app.bundleId,
                                                 "pid": running.processIdentifier])
            guard running.terminate() else {
                abrirWeb(consulta, reproducir: reproducir, completion: completion)
                return
            }
            func esperarSalida(_ intento: Int) {
                let sigue = !NSRunningApplication.runningApplications(
                    withBundleIdentifier: app.bundleId).isEmpty
                if !sigue || running.isTerminated {
                    lanzar()
                } else if intento < 8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                        esperarSalida(intento + 1)
                    }
                } else {
                    abrirWeb(consulta, reproducir: reproducir, completion: completion)
                }
            }
            esperarSalida(0)
        } else {
            traza("abrir_app_nueva", ["bundle": app.bundleId])
            lanzar()
        }
    }

    static func ejecutar(_ consulta: String, reproducir: Bool,
                         completion: @escaping (Resultado) -> Void) {
        let trabajo = {
            let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2, q.count <= 300 else {
                completion(.init(ok: false, reproduciendo: false, via: "",
                                 detalle: "Falta una consulta válida para YouTube Music."))
                return
            }
            let forzarWeb = ProcessInfo.processInfo.environment[
                "BTODICTA_YTMUSIC_FORCE_WEB"] == "1"
            if !forzarWeb, let app = aplicacionInstalada() {
                traza("inicio", ["via": "app", "consulta": q,
                                  "reproducir": reproducir, "ax": AXIsProcessTrusted(),
                                  "bundle": app.bundleId])
                abrirApp(app, consulta: q, reproducir: reproducir, completion: completion)
            } else {
                traza("inicio", ["via": "web", "consulta": q,
                                  "reproducir": reproducir, "ax": AXIsProcessTrusted(),
                                  "forzada": forzarWeb])
                abrirWeb(q, reproducir: reproducir, completion: completion)
            }
        }
        if Thread.isMainThread { trabajo() } else { DispatchQueue.main.async(execute: trabajo) }
    }
}
