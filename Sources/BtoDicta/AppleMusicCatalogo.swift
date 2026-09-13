import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Catálogo público de Apple → aplicación Música. No usa credenciales ni una
/// API privada: la búsqueda sale por HTTPS al Search API oficial y la selección
/// se realiza en la interfaz visible de Música, protegida por el permiso normal
/// de Accesibilidad. Solo declara éxito después de comprobar título y artista.
enum AppleMusicCatalogo {
    struct Cancion: Equatable {
        let id: String
        let titulo: String
        let artista: String
        let url: URL
    }

    struct Resultado {
        let ok: Bool
        let titulo: String
        let artista: String
        let motivo: String
    }

    private static func diagnostico(_ texto: String) {
        let env = ProcessInfo.processInfo.environment
        guard env["BTODICTA_MUSICTEST"] != nil || env["BTODICTA_MUSICFLOWTEST"] != nil else { return }
        print("MUSICAX \(texto)"); fflush(stdout)
    }

    static func urlBusqueda(_ consulta: String, pais: String? = nil) -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/search")
        let region = (pais ?? Locale.current.region?.identifier ?? "EC").uppercased()
        c?.queryItems = [
            URLQueryItem(name: "term", value: consulta),
            URLQueryItem(name: "country", value: region.count == 2 ? region : "EC"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let u = c?.url, u.scheme == "https", u.host == "itunes.apple.com" else { return nil }
        return u
    }

    static func decodificar(_ data: Data) -> Cancion? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultados = j["results"] as? [[String: Any]], let primero = resultados.first,
              let id = primero["trackId"],
              let titulo = primero["trackName"] as? String,
              let artista = primero["artistName"] as? String,
              let raw = primero["trackViewUrl"] as? String,
              let web = URL(string: raw), web.scheme == "https", web.host == "music.apple.com",
              var c = URLComponents(url: web, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = "music"
        guard let u = c.url else { return nil }
        return Cancion(id: String(describing: id), titulo: titulo, artista: artista, url: u)
    }

    static func coincide(_ cancion: Cancion, titulo: String, artista: String) -> Bool {
        let esperadoT = PerfilAgente.normalizar(cancion.titulo)
        let esperadoA = PerfilAgente.normalizar(cancion.artista)
        let actualT = PerfilAgente.normalizar(titulo)
        let actualA = PerfilAgente.normalizar(artista)
        guard !esperadoT.isEmpty, !actualT.isEmpty,
              actualT.contains(esperadoT) || esperadoT.contains(actualT) else { return false }
        return esperadoA.isEmpty || actualA.contains(esperadoA) || esperadoA.contains(actualA)
    }

    static func reproducirPrimera(_ consulta: String,
                                  completion: @escaping (Resultado) -> Void) {
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Config.musicaCatalogoAutomatico(), q.count >= 2, q.count <= 300,
              let u = urlBusqueda(q) else {
            completion(.init(ok: false, titulo: "", artista: "",
                             motivo: "La reproducción de catálogo está desactivada o la consulta no es válida."))
            return
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6; cfg.timeoutIntervalForResource = 8
        let sesion = URLSession(configuration: cfg)
        var req = URLRequest(url: u); req.setValue("close", forHTTPHeaderField: "Connection")
        sesion.dataTask(with: req) { data, response, error in
            defer { sesion.invalidateAndCancel() }
            guard error == nil, let h = response as? HTTPURLResponse, h.statusCode == 200,
                  let data, let cancion = decodificar(data) else {
                DispatchQueue.main.async {
                    completion(.init(ok: false, titulo: "", artista: "",
                                     motivo: "Apple no devolvió una canción verificable para «\(q)»."))
                }
                return
            }
            DispatchQueue.main.async { abrirYReproducir(cancion, completion: completion) }
        }.resume()
    }

    private static func abrirYReproducir(_ cancion: Cancion,
                                         completion: @escaping (Resultado) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(.init(ok: false, titulo: cancion.titulo, artista: cancion.artista,
                             motivo: "Accesibilidad no está autorizada para reproducir el resultado de Apple Music."))
            return
        }
        let esperas: [TimeInterval] = [0.8, 0.9, 1.1, 1.4, 1.8]
        func buscar(_ intento: Int, ronda: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + esperas[intento]) {
                guard let app = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.Music").first else {
                    terminar(false, cancion, "La aplicación Música no llegó a abrir.", completion); return
                }
                app.activate(options: [.activateAllWindows])
                // `activate` es asíncrono. Sin esta espera el clic puede caer en
                // la app que estaba al frente (p. ej. BtoDicta/Terminal).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard app.isActive || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Music" else {
                        if intento + 1 < esperas.count { buscar(intento + 1, ronda: ronda) }
                        else { terminar(false, cancion, "Apple Music no obtuvo el foco para reproducir.", completion) }
                        return
                    }
                    if let elemento = elementoPista(pid: app.processIdentifier, id: cancion.id,
                                                     titulo: cancion.titulo),
                       dobleClick(elemento) {
                        verificar(cancion, intento: 0,
                                   reintentar: ronda == 0 ? { buscar(0, ronda: 1) } : nil,
                                   completion: completion)
                        return
                    }
                    if intento + 1 < esperas.count { buscar(intento + 1, ronda: ronda) }
                    else if ronda == 0 {
                        diagnostico("resultado no visible; recargando una vez")
                        _ = NSWorkspace.shared.open(cancion.url)
                        buscar(0, ronda: 1)
                    } else {
                        terminar(false, cancion, "Apple Music abrió el resultado, pero no expuso una pista seleccionable.", completion)
                    }
                }
            }
        }
        // Music procesa `play item` de forma asíncrona. Si justo antes se pidió
        // una pista aleatoria, abrir otro resultado durante esa transición deja
        // `current track` vacío varios segundos aunque el doble clic sí llegue.
        // Pausar primero serializa el cambio y evita esa carrera.
        pausarParaCambio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard NSWorkspace.shared.open(cancion.url) else {
                completion(.init(ok: false, titulo: cancion.titulo, artista: cancion.artista,
                                 motivo: "No pude abrir el resultado en Apple Music."))
                return
            }
            buscar(0)
        }
    }

    private static func pausarParaCambio() {
        let s = #"tell application "Music" to if player state is playing then pause"#
        var error: NSDictionary?
        _ = NSAppleScript(source: s)?.executeAndReturnError(&error)
        diagnostico(error == nil ? "pista anterior pausada" : "no se pudo pausar la pista anterior")
    }

    private static func elementoPista(pid: pid_t, id: String, titulo: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var cola: [AXUIElement] = [app]
        var vistos = Set<CFHashCode>()
        var i = 0
        let tituloNormal = PerfilAgente.normalizar(titulo)
        while i < cola.count, i < 3_500 {
            let e = cola[i]; i += 1
            guard vistos.insert(CFHash(e)).inserted else { continue }
            if let identificador: String = atributo(e, kAXIdentifierAttribute as CFString),
               identificador.contains("-\(id),") || identificador.contains("=\(id),") {
                guard estaVisible(e, en: app, id: id) else {
                    diagnostico("descartado id no visible=\(identificador)")
                    continue
                }
                let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? "?"
                var acciones: CFArray?
                _ = AXUIElementCopyActionNames(e, &acciones)
                diagnostico("match id=\(identificador) rol=\(rol) acciones=\((acciones as? [String]) ?? [])")
                return e
            }
            // Algunas versiones de Música no exponen AXIdentifier al cliente,
            // pero sí Description/Value. El título exacto sigue siendo seguro
            // porque ya proviene del resultado oficial que acabamos de abrir.
            let textos: [String] = [
                atributo(e, kAXDescriptionAttribute as CFString),
                atributo(e, kAXTitleAttribute as CFString),
                atributo(e, kAXValueAttribute as CFString),
            ].compactMap { $0 }
            if !tituloNormal.isEmpty,
               textos.contains(where: { PerfilAgente.normalizar($0) == tituloNormal }),
               atributo(e, kAXPositionAttribute as CFString) as AXValue? != nil,
               estaVisible(e, en: app, id: id) {
                let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? "?"
                var acciones: CFArray?
                _ = AXUIElementCopyActionNames(e, &acciones)
                diagnostico("match titulo=\(textos) rol=\(rol) acciones=\((acciones as? [String]) ?? [])")
                return e
            }
            for nombre in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXRowsAttribute] {
                if let hijos: [AXUIElement] = atributo(e, nombre as CFString) {
                    cola.append(contentsOf: hijos.prefix(300))
                }
            }
        }
        return nil
    }

    /// Un AXIdentifier puede permanecer en el árbol de Music aunque su página
    /// ya no esté visible. Confirmamos que el centro del elemento realmente
    /// golpea al mismo control (o a uno de sus hijos) antes de mover el ratón.
    private static func estaVisible(_ e: AXUIElement, en app: AXUIElement, id: String) -> Bool {
        var p = CGPoint.zero, s = CGSize.zero
        guard let vp: AXValue = atributo(e, kAXPositionAttribute as CFString),
              let vs: AXValue = atributo(e, kAXSizeAttribute as CFString),
              AXValueGetValue(vp, .cgPoint, &p), AXValueGetValue(vs, .cgSize, &s),
              s.width > 1, s.height > 1 else { return false }
        let centro = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
        var golpe: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(centro.x), Float(centro.y), &golpe) == .success,
              var actual = golpe else { return false }
        for _ in 0..<16 {
            if CFEqual(actual, e) { return true }
            if let identificador: String = atributo(actual, kAXIdentifierAttribute as CFString),
               identificador.contains("-\(id),") || identificador.contains("=\(id),") {
                return true
            }
            guard let padre: AXUIElement = atributo(actual, kAXParentAttribute as CFString) else { break }
            actual = padre
        }
        return false
    }

    /// Music cambia el control de la fila exacta de “Reproducir” a “Pausar”
    /// en cuanto esa pista comienza. Es una prueba local, inmediata y ligada al
    /// trackId correcto; no depende de que MediaRemote responda bajo carga alta.
    private static func pistaVisibleReproduciendo(_ cancion: Cancion) -> Bool {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music").first,
              let pista = elementoPista(pid: app.processIdentifier, id: cancion.id,
                                        titulo: cancion.titulo) else { return false }
        var cola: [AXUIElement] = [pista]
        var vistos = Set<CFHashCode>()
        var i = 0
        while i < cola.count, i < 80 {
            let e = cola[i]; i += 1
            guard vistos.insert(CFHash(e)).inserted else { continue }
            let descripcion: String = atributo(e, kAXDescriptionAttribute as CFString) ?? ""
            let d = PerfilAgente.normalizar(descripcion)
            if ["pausar", "pause"].contains(d) {
                diagnostico("fila exacta expone control \(descripcion)")
                return true
            }
            if let hijos: [AXUIElement] = atributo(e, kAXChildrenAttribute as CFString) {
                cola.append(contentsOf: hijos.prefix(30))
            }
        }
        return false
    }

    private static func atributo<T>(_ e: AXUIElement, _ nombre: CFString) -> T? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, nombre, &valor) == .success else { return nil }
        return valor as? T
    }

    private static func dobleClick(_ e: AXUIElement) -> Bool {
        var p = CGPoint.zero, s = CGSize.zero
        if let vp: AXValue = atributo(e, kAXPositionAttribute as CFString),
           let vs: AXValue = atributo(e, kAXSizeAttribute as CFString),
           AXValueGetValue(vp, .cgPoint, &p), AXValueGetValue(vs, .cgSize, &s),
           s.width > 0, s.height > 0 {
            // En Music, AXPress sobre AlbumTrackLockup solo selecciona/abre el
            // elemento. Un doble clic físico sobre el mismo grupo sí inicia la
            // reproducción, que luego verificamos por título y artista.
            let centro = CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
            guard let mover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                      mouseCursorPosition: centro, mouseButton: .left),
                  let d1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                   mouseCursorPosition: centro, mouseButton: .left),
                  let u1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: centro, mouseButton: .left),
                  let d2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                   mouseCursorPosition: centro, mouseButton: .left),
                  let u2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                   mouseCursorPosition: centro, mouseButton: .left) else { return false }
            d1.setIntegerValueField(.mouseEventClickState, value: 1)
            u1.setIntegerValueField(.mouseEventClickState, value: 1)
            d2.setIntegerValueField(.mouseEventClickState, value: 2)
            u2.setIntegerValueField(.mouseEventClickState, value: 2)
            mover.post(tap: .cghidEventTap)
            usleep(70_000)
            d1.post(tap: .cghidEventTap); u1.post(tap: .cghidEventTap)
            usleep(120_000)
            d2.post(tap: .cghidEventTap); u2.post(tap: .cghidEventTap)
            diagnostico("doble click coordenadas x=\(centro.x) y=\(centro.y)")
            return true
        }
        var acciones: CFArray?
        guard AXUIElementCopyActionNames(e, &acciones) == .success,
              let nombres = acciones as? [String], nombres.contains(kAXPressAction as String) else {
            return false
        }
        let r = AXUIElementPerformAction(e, kAXPressAction as CFString)
        diagnostico("AXPress respaldo r=\(r.rawValue)")
        return r == .success
    }

    private static func verificar(_ cancion: Cancion, intento: Int,
                                  reintentar: (() -> Void)? = nil,
                                  completion: @escaping (Resultado) -> Void) {
        let esperas: [TimeInterval] = reintentar == nil
            ? [0.7]
            : [0.6]
        DispatchQueue.main.asyncAfter(deadline: .now() + esperas[min(intento, esperas.count - 1)]) {
            if pistaVisibleReproduciendo(cancion) {
                terminar(true, cancion,
                         "Reproduciendo «\(cancion.titulo)» — \(cancion.artista).", completion)
                return
            }
            // El adapter puede tardar >3 s cuando Piper usa CPU. Lo leemos en
            // segundo plano con un límite propio para no congelar el notch.
            DispatchQueue.global(qos: .userInitiated).async {
                let remoto = MediaControl.estadoActual(timeout: 12)
                DispatchQueue.main.async {
                    let estado = remoto ?? estadoActualAppleScript()
                    diagnostico("verificar intento=\(intento) play=\(estado.reproduciendo) id=\(estado.id ?? "-") título=\(estado.titulo)")
                    let idExacto = estado.id == cancion.id
                    if estado.reproduciendo,
                       idExacto || coincide(cancion, titulo: estado.titulo, artista: estado.artista) {
                        let titulo = estado.titulo.isEmpty ? cancion.titulo : estado.titulo
                        let artista = estado.artista.isEmpty ? cancion.artista : estado.artista
                        terminar(true, cancion, "Reproduciendo «\(titulo)» — \(artista).", completion)
                    } else if intento + 1 < esperas.count {
                        verificar(cancion, intento: intento + 1,
                                   reintentar: reintentar, completion: completion)
                    } else if let reintentar {
                        diagnostico("primer doble clic sin resultado; reintentando una vez")
                        reintentar()
                    } else {
                        terminar(false, cancion, "No pude verificar que Apple Music reprodujera «\(cancion.titulo)».", completion)
                    }
                }
            }
        }
    }

    /// Búsqueda visible dentro de la app Música. Evita el pseudo-enlace
    /// `music://.../search`, que en algunas versiones crea una pista fantasma
    /// llamada “AutoPlay”. No inicia reproducción ni altera la cola actual.
    @discardableResult
    static func abrirBusqueda(_ consulta: String) -> Bool {
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AXIsProcessTrusted(), !q.isEmpty,
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") != nil else {
            return false
        }
        let yaAbierta = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music").isEmpty
        if !yaAbierta, let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (yaAbierta ? 0.15 : 0.9)) {
            guard let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.Music").first else { return }
            app.activate(options: [.activateAllWindows])
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                pasteText(q)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { presionarRetorno(shift: false) }
            }
        }
        return true
    }

    private static func estadoActualAppleScript() -> (reproduciendo: Bool, titulo: String,
                                                      artista: String, id: String?) {
        let s = """
        tell application "Music"
            set tocando to (player state is playing)
            set titulo to ""
            set artista to ""
            try
                set titulo to name of current track
                set artista to artist of current track
            end try
            return (tocando as string) & linefeed & titulo & linefeed & artista
        end tell
        """
        var error: NSDictionary?
        let r = NSAppleScript(source: s)?.executeAndReturnError(&error).stringValue ?? ""
        guard error == nil else { return (false, "", "", nil) }
        let l = r.components(separatedBy: .newlines)
        return (l.first?.lowercased() == "true", l.count > 1 ? l[1] : "",
                l.count > 2 ? l[2] : "", nil)
    }

    private static func terminar(_ ok: Bool, _ c: Cancion, _ motivo: String,
                                 _ completion: @escaping (Resultado) -> Void) {
        AgenteLog.registrar("musica_catalogo", ["ok": ok, "id": c.id,
                                                  "titulo": c.titulo, "artista": c.artista,
                                                  "motivo": motivo])
        completion(.init(ok: ok, titulo: c.titulo, artista: c.artista, motivo: motivo))
    }
}
