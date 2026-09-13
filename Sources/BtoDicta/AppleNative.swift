import AppKit
import EventKit
import Foundation

struct ResultadoHerramientaApple {
    let ok: Bool
    let mensaje: String
    /// Evidencia estructurada y breve para logs/Atajo universal. Nunca contiene
    /// credenciales; los valores se limitan antes de persistirlos.
    let evidencia: [String: String]

    init(ok: Bool, mensaje: String, evidencia: [String: String] = [:]) {
        self.ok = ok; self.mensaje = mensaje; self.evidencia = evidencia
    }
}

// MARK: - Recordatorios y Calendario mediante EventKit

enum AppleAgenda {
    private struct FechaTexto {
        let fecha: Date?
        let titulo: String
        let error: String?
    }

    static func estadoEventos() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }
    static func estadoRecordatorios() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    static func nombreEstado(_ estado: EKAuthorizationStatus) -> String {
        switch estado {
        case .fullAccess, .authorized: return "Permitido"
        case .writeOnly: return "Solo escritura"
        case .denied: return "Denegado"
        case .restricted: return "Restringido"
        case .notDetermined: return "Se pedirá al usarlo"
        @unknown default: return "Desconocido"
        }
    }

    static func solicitarEventos(completion: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        pedir(.event, store: store) { ok, _ in DispatchQueue.main.async { completion(ok) } }
    }

    static func solicitarRecordatorios(completion: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        pedir(.reminder, store: store) { ok, _ in DispatchQueue.main.async { completion(ok) } }
    }

    private static func pedir(_ tipo: EKEntityType, store: EKEventStore,
                              completion: @escaping (Bool, Error?) -> Void) {
        if tipo == .event {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestFullAccessToReminders(completion: completion)
        }
    }

    private static let patronHoraConIntro =
        #"(?:\ba\s+las?\s+)(\d{1,2})(?::(\d{2}))?(?:\s*(am|pm))?(?:\s+de\s+la\s+(ma[nñ]ana|tarde|noche))?"#
    private static let patronHoraDirecta =
        #"\b(\d{1,2}):(\d{2})(?:\s*(am|pm))?(?:\s+de\s+la\s+(ma[nñ]ana|tarde|noche))?\b"#

    /// Apple Speech puede escribir «p.m.», «p. m.» o usar espacios Unicode.
    /// Internamente lo llevamos a «pm»/«am» antes de interpretar y limpiar.
    private static func normalizarMeridiano(_ texto: String) -> String {
        var t = texto
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
        t = t.replacingOccurrences(of: #"\ba\s*\.?\s*m\b\s*\.?"#, with: "am",
                                   options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\bp\s*\.?\s*m\b\s*\.?"#, with: "pm",
                                   options: [.regularExpression, .caseInsensitive])
        return t
    }

    /// `encontro` distingue «no se dijo hora» de «se dijo una hora inválida».
    /// La segunda jamás debe degradar silenciosamente a medianoche.
    private static func parsearHora(_ texto: String, en dia: Date) -> (fecha: Date?, encontro: Bool) {
        let patrones = [patronHoraConIntro, patronHoraDirecta]
        for patron in patrones {
            guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let ns = texto as NSString
            guard let m = re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges >= 2 else { continue }
            guard var h = Int(ns.substring(with: m.range(at: 1))) else { return (nil, true) }
            let minuto = m.numberOfRanges > 2 && m.range(at: 2).location != NSNotFound
                ? (Int(ns.substring(with: m.range(at: 2))) ?? 0) : 0
            let ap = m.numberOfRanges > 3 && m.range(at: 3).location != NSNotFound
                ? ns.substring(with: m.range(at: 3)).lowercased() : ""
            let franja = m.numberOfRanges > 4 && m.range(at: 4).location != NSNotFound
                ? PerfilAgente.normalizar(ns.substring(with: m.range(at: 4))) : ""
            let meridiano = !ap.isEmpty ? ap
                : (["tarde", "noche"].contains(franja) ? "pm" : (franja == "manana" ? "am" : ""))
            guard (0...59).contains(minuto) else { return (nil, true) }
            if meridiano.isEmpty {
                guard (0...23).contains(h) else { return (nil, true) }
            } else {
                guard (1...12).contains(h) else { return (nil, true) }
                if meridiano == "pm", h < 12 { h += 12 }
                if meridiano == "am", h == 12 { h = 0 }
            }
            let fecha = Calendar.current.date(bySettingHour: h, minute: minuto,
                                               second: 0, of: dia)
            return (fecha, true)
        }
        return (nil, false)
    }

    private static func limpiarTituloRelativo(_ texto: String) -> String {
        var titulo = texto
        let patrones = [#"\bpasado\s+ma[nñ]ana\b"#, #"\bma[nñ]ana\b"#, #"\bhoy\b"#,
                        patronHoraConIntro, patronHoraDirecta,
                        #"\ben\s+(?:el\s+)?calendario\b"#]
        for patron in patrones {
            titulo = titulo.replacingOccurrences(of: patron, with: " ",
                                                  options: [.regularExpression, .caseInsensitive])
        }
        titulo = titulo.replacingOccurrences(of: #"^\s*(?:para|que)\b[\s,;:—-]*"#, with: "",
                                              options: [.regularExpression, .caseInsensitive])
        titulo = titulo.replacingOccurrences(of: #"[\s,;:—-]*\bpara\s*$"#, with: "",
                                              options: [.regularExpression, .caseInsensitive])
        titulo = titulo.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return titulo.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;—-"))
    }

    private static func interpretar(_ texto: String, ahora: Date = Date()) -> FechaTexto {
        let original = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else {
            return FechaTexto(fecha: nil, titulo: "", error: "Dime qué quieres recordar o agendar.")
        }
        let t = normalizarMeridiano(original)
        let ns = t as NSString
        let normal = PerfilAgente.normalizar(t)
        var dia: Date?
        if normal.contains("pasado manana") { dia = Calendar.current.date(byAdding: .day, value: 2, to: ahora) }
        else if normal.contains("manana") { dia = Calendar.current.date(byAdding: .day, value: 1, to: ahora) }
        else if normal.contains("hoy") { dia = ahora }
        if let dia {
            let hora = parsearHora(t, en: dia)
            if hora.encontro, hora.fecha == nil {
                return FechaTexto(fecha: nil, titulo: original,
                    error: "No reconocí bien la hora. Repítela, por ejemplo: mañana a las 8:00 p.m.")
            }
            let fecha = hora.fecha
                ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dia)
            let titulo = limpiarTituloRelativo(t)
            guard !titulo.isEmpty else {
                return FechaTexto(fecha: nil, titulo: "",
                    error: "Entendí la fecha y la hora, pero falta lo que quieres recordar o agendar.")
            }
            return FechaTexto(fecha: fecha, titulo: titulo, error: nil)
        }

        // Barrera adicional: un fragmento como «00 p.m.» no puede llegar al
        // detector flexible de Apple, que podría convertirlo en medianoche.
        let horaAislada = parsearHora(t, en: ahora)
        if horaAislada.encontro, horaAislada.fecha == nil {
            return FechaTexto(fecha: nil, titulo: original,
                error: "No reconocí bien la hora. Repítela con fecha y hora completas.")
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let m = detector.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
           let fecha = m.date {
            var titulo = ns.replacingCharacters(in: m.range, with: "")
            titulo = titulo.replacingOccurrences(of: #"^\s*(?:para|que)\b[\s,;:—-]*"#, with: "",
                                                  options: [.regularExpression, .caseInsensitive])
            titulo = titulo.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;—-"))
            guard !titulo.isEmpty else {
                return FechaTexto(fecha: nil, titulo: "",
                    error: "Entendí la fecha y la hora, pero falta lo que quieres recordar o agendar.")
            }
            return FechaTexto(fecha: fecha, titulo: titulo, error: nil)
        }
        return FechaTexto(fecha: nil, titulo: original, error: nil)
    }

    /// Vista previa pura para QA/UI; no pide permisos ni escribe en EventKit.
    static func previsualizar(_ texto: String, ahora: Date = Date())
        -> (titulo: String, fecha: Date?, error: String?) {
        let p = interpretar(texto, ahora: ahora); return (p.titulo, p.fecha, p.error)
    }

    static func crearRecordatorio(_ texto: String,
                                   completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let p = interpretar(texto)
        if let error = p.error {
            AgenteLog.registrar("agenda_fecha_invalida", ["tipo": "recordatorio",
                                                           "texto": String(texto.prefix(300)),
                                                           "error": error])
            DispatchQueue.main.async { completion(.init(ok: false, mensaje: error)) }
            return
        }
        let store = EKEventStore()
        pedir(.reminder, store: store) { permitido, error in
            guard permitido else {
                DispatchQueue.main.async { completion(.init(ok: false,
                    mensaje: error == nil ? "Activa Recordatorios para BtoDicta en Privacidad y seguridad." : "No pude acceder a Recordatorios: \(error!.localizedDescription)")) }
                return
            }
            guard !p.titulo.isEmpty, let cal = store.defaultCalendarForNewReminders() else {
                DispatchQueue.main.async { completion(.init(ok: false, mensaje: "No hay una lista de Recordatorios disponible.")) }
                return
            }
            let r = EKReminder(eventStore: store); r.calendar = cal; r.title = p.titulo
            if let f = p.fecha {
                r.dueDateComponents = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: f)
            }
            do {
                try store.save(r, commit: true)
                let cuando = p.fecha.map { " para \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
                var datos: [String: Any] = ["titulo": p.titulo]
                if let fecha = p.fecha { datos["fecha"] = fecha.timeIntervalSince1970 }
                AgenteLog.registrar("recordatorio_creado", datos)
                DispatchQueue.main.async { completion(.init(ok: true, mensaje: "Creé el recordatorio «\(p.titulo)»\(cuando).")) }
            } catch {
                DispatchQueue.main.async { completion(.init(ok: false, mensaje: "No pude guardar el recordatorio: \(error.localizedDescription)")) }
            }
        }
    }

    static func crearEvento(_ texto: String,
                            completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let p = interpretar(texto)
        if let error = p.error {
            AgenteLog.registrar("agenda_fecha_invalida", ["tipo": "calendario",
                                                           "texto": String(texto.prefix(300)),
                                                           "error": error])
            DispatchQueue.main.async { completion(.init(ok: false, mensaje: error)) }
            return
        }
        let store = EKEventStore()
        pedir(.event, store: store) { permitido, error in
            guard permitido else {
                DispatchQueue.main.async { completion(.init(ok: false,
                    mensaje: error == nil ? "Activa Calendario para BtoDicta en Privacidad y seguridad." : "No pude acceder a Calendario: \(error!.localizedDescription)")) }
                return
            }
            guard !p.titulo.isEmpty, let cal = store.defaultCalendarForNewEvents else {
                DispatchQueue.main.async { completion(.init(ok: false, mensaje: "No hay un calendario predeterminado disponible.")) }
                return
            }
            let inicio = p.fecha ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
            let e = EKEvent(eventStore: store); e.calendar = cal; e.title = p.titulo
            e.startDate = inicio; e.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: inicio)
            do {
                try store.save(e, span: .thisEvent, commit: true)
                AgenteLog.registrar("evento_creado", ["titulo": p.titulo, "fecha": inicio.timeIntervalSince1970])
                DispatchQueue.main.async { completion(.init(ok: true,
                    mensaje: "Creé «\(p.titulo)» en Calendario para \(inicio.formatted(date: .abbreviated, time: .shortened)).")) }
            } catch {
                DispatchQueue.main.async { completion(.init(ok: false, mensaje: "No pude guardar el evento: \(error.localizedDescription)")) }
            }
        }
    }
}

// MARK: - Archivos mediante Spotlight (solo lectura + abrir)

struct SolicitudBusquedaArchivo {
    let consulta: String
    let mostrarEnFinder: Bool
}

enum ArchivosMac {
    private static let palabrasVaciasNombre: Set<String> = [
        "el", "la", "los", "las", "un", "una", "de", "del", "en", "para",
        "archivo", "documento", "carpeta"
    ]

    /// Separa la consulta de la instrucción visual. Funciona tanto con el texto
    /// ya recortado por Modos ("informe final y muéstralo en Finder") como con
    /// una orden completa usada por rutinas o QA.
    static func interpretarSolicitud(_ texto: String,
                                     forzarFinder: Bool = false) -> SolicitudBusquedaArchivo {
        let original = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let normal = PerfilAgente.normalizar(original)
        let palabras = Set(normal.split(separator: " ").map(String.init))
        let verbosMostrar: Set<String> = [
            "muestra", "muestrame", "muestralo", "mostrar", "ver",
            "ensena", "ensename", "ensenalo", "revela", "revelame", "revelalo"
        ]
        let mencionaFinder = palabras.contains("finder")
        let pideMostrar = !palabras.isDisjoint(with: verbosMostrar)
            || normal.range(of: #"\ben\s+(?:el\s+)?finder\b"#,
                            options: .regularExpression) != nil
        let mostrar = forzarFinder || (mencionaFinder && pideMostrar)

        var q = original
        let patrones = [
            #"^\s*(?:por\s+favor[,;:]?\s*)?(?:muestra|mu[eé]strame|mu[eé]stralo|mostrar|ver|ense[nñ]a|ens[eé]ñame|ens[eé]ñalo|revela|rev[eé]lame|rev[eé]lalo)\s+(?:los\s+resultados?\s+)?(?:en\s+(?:el\s+)?)?finder\b[\s,:;—-]*"#,
            #"\s*[,;]?\s*(?:y\s+)?(?:muestra|mu[eé]strame|mu[eé]stralo|mostrar|ver|ense[nñ]a|ens[eé]ñame|ens[eé]ñalo|revela|rev[eé]lame|rev[eé]lalo)\s+(?:los\s+resultados?\s+)?en\s+(?:el\s+)?finder\b.*$"#,
            #"\s+en\s+(?:el\s+)?finder\s*[.!?…]*$"#,
            #"^\s*(?:por\s+favor[,;:]?\s*)?(?:busca|b[uú]scame|buscar|encuentra|encu[eé]ntrame|encontrar|abre|abrir)\s+(?:(?:el|la|un|una)\s+)?(?:archivo|documento|carpeta)\s+"#,
            #"^\s*(?:(?:el|la|un|una)\s+)?(?:archivo|documento|carpeta)\s+"#
        ]
        for patron in patrones {
            q = q.replacingOccurrences(of: patron, with: "",
                                       options: [.regularExpression, .caseInsensitive])
        }
        q = q.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"“”«»'.,;:!?¿¡—"))
        return SolicitudBusquedaArchivo(consulta: q, mostrarEnFinder: mostrar)
    }

    /// Abre una ventana de Finder con una búsqueda Spotlight real: conserva la
    /// consulta visible y deja al usuario ordenar, filtrar y abrir cualquiera de
    /// todos los resultados. No necesita Accesibilidad ni simula teclado.
    static func mostrarBusquedaEnFinder(_ consulta: String) -> Bool {
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.count <= 300 else { return false }
        let abrir = { NSWorkspace.shared.showSearchResults(forQueryString: q) }
        let ok: Bool
        if Thread.isMainThread { ok = abrir() }
        else { ok = DispatchQueue.main.sync(execute: abrir) }
        AgenteLog.registrar("archivo_busqueda_finder", ["consulta": q, "ok": ok])
        return ok
    }

    /// Guardado local explícito: BtoDicta propone nombre/formato, pero el usuario
    /// elige la ubicación y confirma con el panel nativo. Nunca sobrescribe en
    /// silencio ni interpreta rutas dictadas.
    static func crearBorrador(_ texto: String, nombreSugerido: String?,
                              completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                crearBorrador(texto, nombreSugerido: nombreSugerido, completion: completion)
            }
            return
        }
        let limpio = (nombreSugerido ?? "Borrador BtoDicta")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nombre = (limpio.isEmpty ? "Borrador BtoDicta" : limpio)
            + ((limpio as NSString).pathExtension.isEmpty ? ".txt" : "")
        let panel = NSSavePanel()
        panel.title = "Guardar borrador de BtoDicta"
        panel.nameFieldStringValue = nombre
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            completion(.init(ok: false, mensaje: "No guardé el archivo porque cerraste el selector.")); return
        }
        do {
            try Data(texto.utf8).write(to: url, options: .atomic)
            AgenteLog.registrar("archivo_creado", ["nombre": url.lastPathComponent,
                                                     "bytes": texto.utf8.count])
            completion(.init(ok: true, mensaje: "Guardé «\(url.lastPathComponent)»."))
        } catch {
            completion(.init(ok: false, mensaje: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
    }

    /// Ordena y FILTRA candidatos por el nombre visible del archivo. Spotlight
    /// también encuentra palabras dentro del contenido; esos resultados no deben
    /// ocupar el modal como si su nombre coincidiera con la consulta.
    static func ordenarCoincidenciasPorNombre(_ urls: [URL], consulta: String) -> [URL] {
        let q = PerfilAgente.normalizar(consulta)
        let terminos = q.split(separator: " ").map(String.init).filter {
            $0.count >= 2 && !palabrasVaciasNombre.contains($0)
        }
        guard !q.isEmpty, !terminos.isEmpty else { return [] }

        func puntaje(_ url: URL) -> Int {
            let nombre = PerfilAgente.normalizar(url.deletingPathExtension().lastPathComponent)
            guard !nombre.isEmpty else { return 0 }
            if nombre == q { return 10_000 }
            var score = nombre.contains(q) ? 7_000 : 0
            let palabrasNombre = nombre.split(separator: " ").map(String.init)
            var fuertes = 0
            var exactas = 0
            for termino in terminos {
                let mejor = palabrasNombre.map { ModoFuzzy.similitud(termino, $0) }.max() ?? 0
                if mejor >= 0.82 { fuertes += 1 }
                if palabrasNombre.contains(termino) { exactas += 1 }
            }
            // Para consultas cortas como "informe final" deben coincidir TODAS
            // las ideas del nombre. En nombres largos toleramos una palabra de
            // enlace perdida, pero nunca candidatos solo por contenido.
            let requeridas = terminos.count <= 3 ? terminos.count
                : max(2, Int(ceil(Double(terminos.count) * 0.7)))
            guard fuertes >= requeridas else { return 0 }
            score += fuertes * 600 + exactas * 250
            if nombre.hasPrefix(terminos[0]) { score += 180 }
            return score
        }

        return urls.compactMap { u -> (URL, Int)? in
            let p = puntaje(u); return p > 0 ? (u, p) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.path.count < $1.0.path.count
        }.map(\.0)
    }

    /// Predicado Spotlight limitado al NOMBRE. No usa shell y escapa la sintaxis
    /// del predicado; la búsqueda general por contenido queda para la ventana
    /// nativa de Finder cuando no existe una coincidencia clara por nombre.
    private static func predicadoNombre(_ consulta: String) -> String? {
        let terminos = PerfilAgente.normalizar(consulta).split(separator: " ").map(String.init).filter {
            $0.count >= 2 && !palabrasVaciasNombre.contains($0)
        }
        guard !terminos.isEmpty else { return nil }
        return terminos.map { termino in
            let seguro = termino.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "kMDItemFSName == \"*\(seguro)*\"cd"
        }.joined(separator: " && ")
    }

    static func buscar(_ consulta: String, completion: @escaping ([URL]) -> Void) {
        let q = interpretarSolicitud(consulta).consulta
        guard !q.isEmpty, q.count <= 300, let predicado = predicadoNombre(q) else {
            completion([]); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            p.arguments = [predicado]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { DispatchQueue.main.async { completion([]) }; return }
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let out = String(data: d, encoding: .utf8) ?? ""
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            var vistos = Set<String>()
            let urls = out.split(separator: "\n").prefix(100).compactMap { linea -> URL? in
                let u = URL(fileURLWithPath: String(linea)).standardizedFileURL
                guard u.path.hasPrefix(home + "/"), !u.lastPathComponent.hasPrefix("."),
                      vistos.insert(u.path).inserted else { return nil }
                return u
            }
            let orden = ordenarCoincidenciasPorNombre(urls, consulta: q)
            AgenteLog.registrar("archivo_ranking", [
                "consulta": q, "candidatos_spotlight": urls.count,
                "coincidencias_nombre": orden.count,
            ])
            DispatchQueue.main.async { completion(Array(orden.prefix(12))) }
        }
    }
}

// MARK: - Pasarela inversa Siri/Atajos → BtoDicta

/// Siri solo ejecuta Atajos por su nombre. Este puente no suplanta a Siri ni
/// mantiene otro micrófono: el Atajo abre una URL local, y la app inicia un
/// turno Agente limpio con el nombre/configuración vigentes.
enum PasarelaSiriBeto {
    static func urlEscuchar(token: String = Config.agentePasarelaSiriToken()) -> URL {
        var componentes = URLComponents()
        componentes.scheme = "btodicta"
        componentes.host = "agente"
        componentes.path = "/escuchar"
        componentes.queryItems = [URLQueryItem(name: "t", value: token)]
        return componentes.url!
    }

    static func nombreSugerido(_ nombreAgente: String) -> String {
        let limpio = String(nombreAgente.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        return limpio.isEmpty ? "BtoDicta" : limpio
    }

    /// Frases deliberadas para el caso en que BtoDicta ya posee el micrófono
    /// y el detector nativo de Siri no puede adelantarse. Siempre se derivan del
    /// nombre configurado; nunca hay nombres de personas hardcodeados.
    static func activadoresLocales(nombreAgente: String) -> [String] {
        let nombre = nombreSugerido(nombreAgente)
        return FrasesConfigurables.activadoresSeguros([
            "oye siri \(nombre)",
            "oye siri dile a \(nombre)",
            "oye siri envia a \(nombre)",
            "oye siri abre \(nombre)",
        ])
    }

    static func esActivadorLocal(_ frase: String, nombreAgente: String) -> Bool {
        let normal = PerfilAgente.normalizar(frase)
        return activadoresLocales(nombreAgente: nombreAgente)
            .contains { PerfilAgente.normalizar($0) == normal }
    }

    static func esOrdenEscuchar(_ url: URL,
                                tokenEsperado: String = Config.agentePasarelaSiriToken()) -> Bool {
        guard url.scheme?.lowercased() == "btodicta",
              url.host?.lowercased() == "agente",
              url.path.lowercased() == "/escuchar",
              url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil,
              let componentes = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = componentes.queryItems, items.count == 1,
              items[0].name == "t", items[0].value == tokenEsperado else { return false }
        return true
    }

    /// Abre el instalador firmado que viaja en el bundle. El Atajo consulta la
    /// capacidad local en tiempo de ejecución, así que el paquete es portable y
    /// no contiene el token de esta Mac. Apple conserva la confirmación visible.
    static func preparar(nombreAgente: String) -> ResultadoHerramientaApple {
        AtajosIncluidos.instalar(.asistente, nombreAgente: nombreAgente)
    }

    static func probar() -> ResultadoHerramientaApple {
        guard NSWorkspace.shared.open(urlEscuchar()) else {
            return .init(ok: false, mensaje: "No pude abrir la pasarela local de BtoDicta.")
        }
        return .init(ok: true, mensaje: "Pasarela enviada a BtoDicta.")
    }
}

// MARK: - Pasarela oficial de Atajos (herramienta Apple/Siri)

enum AppleAtajos {
    static let nombreMusicaIncluido = "BtoDicta · Reproducir música"
    static var disponible: Bool { FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts") }

    /// El paquete viaja dentro de BtoDicta. macOS exige que el usuario confirme
    /// su importación una vez; la app nunca modifica silenciosamente su biblioteca
    /// de Atajos.
    static func paqueteMusicaIncluido() -> URL? {
        AtajosIncluidos.paquete(.musica)
    }

    static func instalarMusicaIncluido() -> ResultadoHerramientaApple {
        AtajosIncluidos.instalar(.musica, nombreAgente: Config.agenteNombre())
    }

    static func listar(completion: @escaping ([String]) -> Void) {
        guard disponible else { completion([]); return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["list"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { DispatchQueue.main.async { completion([]) }; return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let s = String(data: data, encoding: .utf8) ?? ""
            let lista = s.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
            DispatchQueue.main.async { completion(lista) }
        }
    }

    private static func enc(_ s: String) -> String {
        var c = CharacterSet.urlQueryAllowed; c.remove(charactersIn: "&=+#")
        return s.addingPercentEncoding(withAllowedCharacters: c) ?? s
    }

    static func url(nombre: String, texto: String) -> URL? {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let raw = "shortcuts://run-shortcut?name=\(enc(n))&input=text&text=\(enc(texto))"
        return URL(string: raw)
    }

    static func ejecutar(nombre: String, texto: String) -> ResultadoHerramientaApple {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return .init(ok: false, mensaje: "Configura primero el Atajo Apple que recibirá el texto.") }
        guard let url = url(nombre: n, texto: texto), NSWorkspace.shared.open(url) else {
            return .init(ok: false, mensaje: "No pude abrir el atajo «\(n)».")
        }
        AgenteLog.registrar("atajo_apple", ["atajo": n, "texto": texto, "ok": true])
        return .init(ok: true, mensaje: "Entregué el pedido al atajo «\(n)».")
    }

    private struct EstadoMusica {
        let reproduciendo: Bool
        let titulo: String
        let artista: String

        var firma: String { PerfilAgente.normalizar(titulo + " " + artista) }
    }

    /// Lee evidencia real de Music. Que macOS acepte la URL del Atajo no garantiza
    /// que haya encontrado ni reproducido lo pedido.
    private static func estadoMusica() -> EstadoMusica {
        // Consultar Music con AppleScript la abriría incluso antes de ejecutar
        // el Atajo. Si aún no está viva, el estado anterior es simplemente vacío.
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music").isEmpty else {
            return .init(reproduciendo: false, titulo: "", artista: "")
        }
        let script = """
        tell application "Music"
            set estaReproduciendo to (player state is playing)
            set nombrePista to ""
            set artistaPista to ""
            try
                set nombrePista to name of current track
                set artistaPista to artist of current track
            end try
            return (estaReproduciendo as string) & linefeed & nombrePista & linefeed & artistaPista
        end tell
        """
        var error: NSDictionary?
        let salida = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? ""
        guard error == nil else { return .init(reproduciendo: false, titulo: "", artista: "") }
        let lineas = salida.components(separatedBy: .newlines)
        return .init(reproduciendo: lineas.first?.lowercased() == "true",
                     titulo: lineas.count > 1 ? lineas[1] : "",
                     artista: lineas.count > 2 ? lineas[2] : "")
    }

    /// Visible para QA: la consulta debe aparecer realmente en título o artista.
    /// Se comparan palabras normalizadas para tolerar tildes y puntuación, pero no
    /// se acepta una pista cualquiera como éxito.
    static func coincideMusica(consulta: String, titulo: String, artista: String) -> Bool {
        let q = PerfilAgente.normalizar(consulta)
        guard !q.isEmpty else { return true }
        let campos = [PerfilAgente.normalizar(titulo), PerfilAgente.normalizar(artista)]
        if campos.contains(where: { !$0.isEmpty && ($0.contains(q) || q.contains($0)) }) { return true }
        let palabras = q.split(separator: " ").filter { $0.count >= 3 }
        guard !palabras.isEmpty else { return false }
        return campos.contains { campo in
            !campo.isEmpty && palabras.allSatisfy { campo.contains($0) }
        }
    }

    private static func pausarMusica() {
        var error: NSDictionary?
        _ = NSAppleScript(source: "tell application \"Music\" to pause")?
            .executeAndReturnError(&error)
    }

    /// Ejecuta el Atajo mediante el esquema público de macOS, que sí entrega la
    /// consulta como texto. Verifica después la pista real con intentos finitos.
    /// Nunca confía en que abrir la URL equivalga a haber reproducido lo pedido.
    static func ejecutarMusica(nombre: String, texto: String,
                               completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard disponible, !n.isEmpty, !q.isEmpty, q.count <= 500,
              let atajoURL = url(nombre: n, texto: q) else {
            completion(.init(ok: false, mensaje: "El Atajo de música no está disponible.")); return
        }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                ejecutarMusica(nombre: n, texto: q, completion: completion)
            }
            return
        }
        let anterior = estadoMusica()
        guard NSWorkspace.shared.open(atajoURL) else {
            completion(.init(ok: false, mensaje: "No pude abrir el Atajo «\(n)».")); return
        }

        // El primer control suele bastar; los demás cubren Music en arranque frío.
        // La espera máxima es finita y no bloquea ningún hilo.
        let esperas: [TimeInterval] = [0.45, 0.75, 1.1, 1.7]
        func comprobar(_ indice: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + esperas[indice]) {
                let despues = estadoMusica()
                if despues.reproduciendo,
                   coincideMusica(consulta: q, titulo: despues.titulo, artista: despues.artista) {
                    let detalle = despues.artista.isEmpty
                        ? "Reproduciendo «\(despues.titulo)»."
                        : "Reproduciendo «\(despues.titulo)» — \(despues.artista)."
                    completion(.init(ok: true, mensaje: detalle)); return
                }

                let cambioEquivocado = despues.reproduciendo
                    && (!anterior.reproduciendo || despues.firma != anterior.firma)
                if cambioEquivocado {
                    pausarMusica()
                    completion(.init(ok: false,
                        mensaje: "El Atajo reprodujo una pista distinta de «\(q)»; la pausé y continuaré por el failover."))
                    return
                }
                if indice + 1 < esperas.count { comprobar(indice + 1); return }
                completion(.init(ok: false,
                    mensaje: "El Atajo no encontró una coincidencia verificable para «\(q)»."))
            }
        }
        comprobar(0)
    }
}
