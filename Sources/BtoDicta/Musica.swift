import AppKit
import Foundation

// MARK: - Modo Música con cascada
//
// No promete controlar catálogos privados. Primero intenta la app elegida; si no
// existe o el enlace falla, salta al siguiente proveedor y termina en web. Apple
// Music y Spotify pueden reproducir un primer resultado verificable mediante sus
// interfaces de automatización/Accesibilidad; nunca basta con abrir y asumir éxito.

struct ProveedorMusica: Identifiable, Hashable {
    let id: String
    let nombre: String
    let bundle: String
    let plantilla: String
    let esWeb: Bool
}

struct ResultadoMusica {
    let ok: Bool
    let proveedor: String
    let mensaje: String
    let estado: EstadoMusica
}

enum EstadoMusica: String {
    case reproduciendo, pausado, detenido, busqueda, abierto, fallo
}

enum IntencionMusica: String {
    case reproducir, buscar
}

enum ComandoMusica: String {
    case reproducir, buscar, pausar, reanudar, detener, siguiente, anterior
    case aleatorio, cerrar, pantallaCompleta = "pantalla_completa", compacto

    var intencion: IntencionMusica? {
        switch self {
        case .reproducir: .reproducir
        case .buscar: .buscar
        default: nil
        }
    }
}

/// Foto mínima de una sesión musical. Mantiene la decisión de enrutamiento
/// separada de AppKit/MediaRemote para poder probarla sin abrir reproductores.
struct EstadoControlMusica: Equatable {
    let reproduciendo: Bool
    let tieneContenido: Bool
    let tieneCola: Bool
    let interfazVisible: Bool
    let puedeAleatorio: Bool

    init(reproduciendo: Bool, tieneContenido: Bool, tieneCola: Bool,
         interfazVisible: Bool, puedeAleatorio: Bool? = nil) {
        self.reproduciendo = reproduciendo; self.tieneContenido = tieneContenido
        self.tieneCola = tieneCola; self.interfazVisible = interfazVisible
        self.puedeAleatorio = puedeAleatorio ?? tieneCola
    }

    static let vacio = EstadoControlMusica(reproduciendo: false,
                                           tieneContenido: false,
                                           tieneCola: false,
                                           interfazVisible: false)
}

extension ComandoMusica {
    /// Un control solo es una acción cuando existe algo real sobre lo cual actuar.
    /// Reproducir/buscar crean una sesión nueva y por eso no pasan por esta puerta.
    func esAplicable(en estado: EstadoControlMusica) -> Bool {
        switch self {
        case .pausar, .detener:
            return estado.reproduciendo
        case .reanudar:
            return estado.tieneContenido && !estado.reproduciendo
        case .siguiente, .anterior:
            return estado.tieneCola
        case .aleatorio:
            return estado.puedeAleatorio
        case .cerrar, .pantallaCompleta, .compacto:
            return estado.interfazVisible
        case .reproducir, .buscar:
            return true
        }
    }
}

enum Musica {
    static let base: [ProveedorMusica] = [
        ProveedorMusica(id: "apple_music", nombre: "Apple Music", bundle: "com.apple.Music",
                        plantilla: "music://music.apple.com/search?term={q}", esWeb: false),
        ProveedorMusica(id: "spotify", nombre: "Spotify", bundle: "com.spotify.client",
                        plantilla: "spotify:search:{q}", esWeb: false),
        ProveedorMusica(id: "btodicta_youtube", nombre: "BtoDicta · YouTube", bundle: "",
                        plantilla: "https://www.youtube.com/results?search_query={q}", esWeb: false),
        ProveedorMusica(id: "youtube_music", nombre: "YouTube Music", bundle: "",
                        plantilla: "https://music.youtube.com/search?q={q}", esWeb: true),
        ProveedorMusica(id: "youtube", nombre: "YouTube", bundle: "",
                        plantilla: "https://www.youtube.com/results?search_query={q}", esWeb: true),
        ProveedorMusica(id: "soundcloud", nombre: "SoundCloud", bundle: "",
                        plantilla: "https://soundcloud.com/search?q={q}", esWeb: true),
        ProveedorMusica(id: "bandcamp", nombre: "Bandcamp", bundle: "",
                        plantilla: "https://bandcamp.com/search?q={q}", esWeb: true),
    ]

    static func personales() -> [ProveedorMusica] {
        Config.musicaProveedoresPersonales().compactMap { d in
            guard let nombre = d["nombre"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = d["url"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !nombre.isEmpty, plantillaSegura(url) else { return nil }
            let firma = PerfilAgente.normalizar(nombre).replacingOccurrences(of: " ", with: "-")
            return ProveedorMusica(id: "personal:\(firma)", nombre: nombre, bundle: "",
                                   plantilla: url, esWeb: true)
        }
    }

    /// Los proveedores propios nunca reciben credenciales, pero aun así evitamos
    /// esquemas ejecutables. HTTP solo se acepta en loopback para un servicio local.
    static func plantillaSegura(_ plantilla: String) -> Bool {
        guard plantilla.contains("{q}"),
              let u = URL(string: plantilla.replacingOccurrences(of: "{q}", with: "prueba")),
              let esquema = u.scheme?.lowercased(), let host = u.host?.lowercased() else { return false }
        if esquema == "https" { return true }
        return esquema == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    static func catalogo() -> [ProveedorMusica] { base + personales() }
    static func proveedor(_ id: String) -> ProveedorMusica? { catalogo().first { $0.id == id } }
    static func nombre(_ id: String) -> String {
        proveedor(id)?.nombre ?? (["", "auto"].contains(id) ? "Automático" : id)
    }

    static func disponible(_ p: ProveedorMusica) -> Bool {
        p.esWeb || p.bundle.isEmpty
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundle) != nil
    }

    static func reconocerProveedor(en texto: String) -> String? {
        let s = PerfilAgente.normalizar(texto)
        if s == "interno" { return "btodicta_youtube" }
        let alias: [(String, String)] = [
            ("reproductor interno", "btodicta_youtube"),
            ("youtube interno", "btodicta_youtube"),
            ("musica interno", "btodicta_youtube"),
            ("musica interna", "btodicta_youtube"),
            ("beto dicta", "btodicta_youtube"),
            ("btodicta", "btodicta_youtube"),
            ("youtube music", "youtube_music"), ("apple music", "apple_music"),
            ("musica de apple", "apple_music"), ("apple", "apple_music"),
            ("spotify", "spotify"),
            ("youtube", "youtube"), ("soundcloud", "soundcloud"), ("bandcamp", "bandcamp")
        ]
        if let a = alias.first(where: { s.contains($0.0) }) { return a.1 }
        return personales().first { s.contains(PerfilAgente.normalizar($0.nombre)) }?.id
    }

    /// Solo consume dos palabras cuando forman el nombre completo de un motor;
    /// así “YouTube música andina” no se come “música” como parte del proveedor.
    static func reconocerProveedorCompuesto(_ texto: String) -> String? {
        let s = PerfilAgente.normalizar(texto)
        let validos: Set<String> = [
            "apple music", "youtube music", "reproductor interno", "youtube interno",
            "musica interna", "musica interno", "beto dicta",
        ]
        guard validos.contains(s) else { return nil }
        return reconocerProveedor(en: s)
    }

    static func quitarNombreProveedor(_ texto: String, id: String) -> String {
        guard id != "auto", let p = proveedor(id) else { return texto }
        var s = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let nombres = [p.nombre, id.replacingOccurrences(of: "_", with: " ")]
        for nombre in nombres {
            let e = NSRegularExpression.escapedPattern(for: nombre)
            guard let re = try? NSRegularExpression(pattern: "^(?:en\\s+)?\(e)[,;:]?\\s*",
                                                    options: [.caseInsensitive]) else { continue }
            let ns = s as NSString
            if let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                s = ns.substring(from: NSMaxRange(m.range)); break
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Diferencia una orden de reproducción de una búsqueda deliberada. Solo
    /// mira la cabecera: una palabra como “buscar” dentro del título no cambia
    /// accidentalmente la acción. Si el planificador ya consumió el verbo, la
    /// operación musical normal sigue siendo reproducir.
    static func intencion(_ texto: String) -> IntencionMusica {
        let patronesBusqueda = [
            #"^(?:por\s+favor[,;:]?\s*)?(?:modo\s+)?m[uú]sica(?:\s+(?:interna?|interno|en\s+(?:beto\s*dicta|youtube|spotify|apple\s+music|youtube\s+music)))?[,;:]?\s*(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)(?:\b|\s)"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)\s+(?:en\s+)?(?:reproductor\s+interno|youtube\s+interno|beto\s*dicta|apple\s+music|youtube\s+music|spotify|youtube|soundcloud|bandcamp|m[uú]sica|canci[oó]n(?:es)?)\b"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)(?:\b|\s)"#,
        ]
        for patron in patronesBusqueda {
            guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let ns = texto as NSString
            if re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)) != nil {
                return .buscar
            }
        }
        return .reproducir
    }

    /// Interpreta controles breves sin IA. Se exige una cabecera accionable y,
    /// salvo órdenes inequívocas, una referencia musical para no convertir una
    /// frase normal como “continúa el informe” en un control multimedia.
    static func comando(_ texto: String, accionConfigurada: String = "auto") -> ComandoMusica {
        if let fijo = ComandoMusica(rawValue: accionConfigurada), accionConfigurada != "auto" {
            return fijo
        }
        let s = PerfilAgente.normalizar(texto)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let musical = ["musica", "cancion", "reproductor", "youtube", "spotify", "video"]
            .contains { s.contains($0) }
        if ["pausa", "pausar"].contains(s) { return .pausar }
        if ["reanuda", "reanudar", "continua", "continuar"].contains(s) { return .reanudar }
        if ["deten", "detener", "stop"].contains(s) { return .detener }
        if ["shuffle", "mezcla", "baraja", "aleatorio"].contains(s) { return .aleatorio }
        if s.contains("pantalla completa"), musical { return .pantallaCompleta }
        if (s.contains("modo compacto") || s.contains("vista compacta")
            || s.contains("solo musica") || s.contains("sin video")), musical { return .compacto }
        if s.range(of: #"^(?:por favor )?(?:mezcla|mezclar|baraja|barajar|shuffle|modo aleatorio)(?: la| el)? (?:musica|cola|canciones|reproductor)(?:\b|$)"#,
                   options: .regularExpression) != nil { return .aleatorio }
        if s.range(of: #"^(?:por favor )?(?:pausa|pausar|pon en pausa)(?:\b| )"#,
                   options: .regularExpression) != nil, musical { return .pausar }
        if s.range(of: #"^(?:por favor )?(?:reanuda|reanudar|continua|continuar|sigue)(?:\b| )"#,
                   options: .regularExpression) != nil, musical { return .reanudar }
        if s.range(of: #"^(?:por favor )?(?:deten|detener|stop)(?: la| el)? (?:musica|cancion|reproductor|video)(?:\b| )"#,
                   options: .regularExpression) != nil
            || s.range(of: #"^(?:por favor )?para(?: la| el)? (?:musica|cancion|reproductor|video)(?:\b| )"#,
                       options: .regularExpression) != nil { return .detener }
        if s.range(of: #"^(?:por favor )?(?:siguiente|proxima|proximo)(?: cancion| tema| video)?$"#,
                   options: .regularExpression) != nil { return .siguiente }
        if s.range(of: #"^(?:por favor )?(?:anterior|cancion anterior|tema anterior|video anterior)$"#,
                   options: .regularExpression) != nil { return .anterior }
        if s.range(of: #"^(?:por favor )?(?:cierra|cerrar)(?: la| el)? (?:musica|reproductor|video)(?:\b|$)"#,
                   options: .regularExpression) != nil { return .cerrar }
        return intencion(texto) == .buscar ? .buscar : .reproducir
    }

    /// Extrae únicamente planes que son UN control musical puro. Una cadena que
    /// además traduce, redacta o envía no se descarta silenciosamente por esta regla.
    static func controlExclusivo(en cadena: ModoCadena) -> ComandoMusica? {
        guard cadena.transforms.isEmpty, cadena.acciones.count == 1,
              let modo = cadena.acciones.first?.modo, modo.base == "musica",
              let comando = ComandoMusica(rawValue: modo.musicaAccion),
              comando.intencion == nil else { return nil }
        return comando
    }

    /// Comprueba el reproductor propio al instante y consulta MediaRemote solo si
    /// la frase YA fue reconocida como control. No hay red, embeddings ni IA.
    static func controlDisponible(_ comando: ComandoMusica,
                                  completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let interno = ReproductorYouTubeInterno.shared.estadoControl
            if comando.esAplicable(en: interno) {
                completion(true)
                return
            }
            // Estas operaciones pertenecen exclusivamente a la ventana propia.
            guard ![ComandoMusica.aleatorio, .cerrar, .pantallaCompleta, .compacto].contains(comando) else {
                completion(false)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let actual = MediaControl.estadoActual(timeout: 0.55)
                let contenido = actual.map {
                    $0.reproduciendo || !$0.titulo.isEmpty || !$0.artista.isEmpty || $0.id != nil
                } ?? false
                let externo = EstadoControlMusica(
                    reproduciendo: actual?.reproduciendo ?? false,
                    tieneContenido: contenido,
                    // MediaRemote no publica la longitud de la cola. Una sesión
                    // identificada permite intentarlo; el ejecutor verifica después
                    // que realmente haya cambiado la pista.
                    tieneCola: contenido,
                    interfazVisible: false)
                let disponible = comando.esAplicable(en: externo)
                DispatchQueue.main.async { completion(disponible) }
            }
        }
    }

    static func controlar(_ comando: ComandoMusica,
                          completion: @escaping (ResultadoMusica) -> Void) {
        func terminar(_ resultado: ResultadoMusica) {
            DispatchQueue.main.async {
                AgenteLog.registrar("musica_control", ["comando": comando.rawValue,
                                                        "ok": resultado.ok,
                                                        "estado": resultado.estado.rawValue])
                completion(resultado)
            }
        }
        DispatchQueue.main.async {
            let player = ReproductorYouTubeInterno.shared
            let controlesVerificables: Set<ComandoMusica> = [
                .pausar, .reanudar, .detener, .siguiente, .anterior, .aleatorio,
            ]
            if controlesVerificables.contains(comando),
               comando.esAplicable(en: player.estadoControl) {
                let detalle: (String, String, EstadoMusica)
                switch comando {
                case .pausar: detalle = ("Pausé la reproducción.",
                                         "YouTube no confirmó la pausa.", .pausado)
                case .reanudar: detalle = ("Reanudé la reproducción.",
                                           "YouTube no confirmó la reproducción.", .reproduciendo)
                case .detener: detalle = ("Detuve la reproducción.",
                                          "YouTube no confirmó que se detuvo.", .detenido)
                case .siguiente: detalle = ("Pasé al resultado siguiente.",
                                            "YouTube no confirmó el siguiente resultado.", .reproduciendo)
                case .anterior: detalle = ("Volví al resultado anterior.",
                                           "YouTube no confirmó el resultado anterior.", .reproduciendo)
                case .aleatorio: detalle = ("Elegí otra pista de la cola al azar.",
                                            "YouTube no confirmó otra pista de la cola.", .reproduciendo)
                default: return
                }
                player.controlarVerificado(comando) { ok in
                    terminar(.init(ok: ok, proveedor: "btodicta_youtube",
                                   mensaje: ok ? detalle.0 : detalle.1,
                                   estado: ok ? detalle.2 : .fallo))
                }
                return
            }
            switch comando {
            case .cerrar:
                player.cerrar()
                terminar(.init(ok: true, proveedor: "btodicta_youtube",
                    mensaje: "Cerré el reproductor y detuve la música.", estado: .detenido)); return
            case .pantallaCompleta:
                player.mostrar(); player.alternarPantallaCompleta()
                terminar(.init(ok: true, proveedor: "btodicta_youtube",
                    mensaje: "Cambié la vista de pantalla completa.", estado: .abierto)); return
            case .compacto:
                player.configurarCompacto(true)
                terminar(.init(ok: true, proveedor: "btodicta_youtube",
                    mensaje: "Reduje la interfaz y mantuve visible el reproductor oficial.", estado: .abierto)); return
            case .reproducir, .buscar:
                terminar(.init(ok: false, proveedor: "",
                    mensaje: "La orden necesita una consulta.", estado: .fallo)); return
            default:
                break
            }
            // El adaptador multimedia puede tardar mientras consulta al proceso
            // activo. Nunca bloqueamos AppKit ni congelamos el notch/menú.
            DispatchQueue.global(qos: .userInitiated).async {
                let ok: Bool
                let exito: String
                let fallo: String
                let estado: EstadoMusica
                switch comando {
                case .pausar:
                    ok = MediaControl.pausarActual(); exito = "Pausé la reproducción."
                    fallo = "No encontré música activa para pausar."; estado = .pausado
                case .reanudar:
                    ok = MediaControl.reproducirActual(); exito = "Reanudé la reproducción."
                    fallo = "No encontré música para reanudar."; estado = .reproduciendo
                case .detener:
                    ok = MediaControl.detenerActual(); exito = "Detuve la reproducción."
                    fallo = "No encontré música activa para detener."; estado = .detenido
                case .siguiente:
                    ok = MediaControl.siguienteActual(); exito = "Pasé a la canción siguiente."
                    fallo = "No hay una cola musical disponible."; estado = .reproduciendo
                case .anterior:
                    ok = MediaControl.anteriorActual(); exito = "Volví a la canción anterior."
                    fallo = "No hay una cola musical disponible."; estado = .reproduciendo
                case .aleatorio:
                    terminar(.init(ok: false, proveedor: "",
                                   mensaje: "No hay una cola interna para mezclar.", estado: .fallo))
                    return
                default: return
                }
                terminar(.init(ok: ok, proveedor: "sistema", mensaje: ok ? exito : fallo,
                               estado: ok ? estado : .fallo))
            }
        }
    }

    /// Convierte una orden hablada en una consulta limpia. Sirve tanto para el
    /// modo explícito ("modo música, pon Jessy Uribe") como para una petición
    /// natural ("reproduce en Spotify música de Jessy Uribe").
    static func extraerConsulta(_ texto: String, proveedor: String) -> String {
        var s = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let patrones = [
            #"^(?:por\s+favor[,;:]?\s*)?(?:modo\s+)?m[uú]sica[,;:]?\s*"#,
            #"^(?:intern[oa]|reproductor\s+interno|youtube\s+interno|beto\s*dicta|btodicta)[,;:]?\s+(?=(?:pon|reproduce|toca|escucha|busca|encuentra|muestra))"#,
            #"^(?:por\s+favor[,;:]?\s*)?(?:pon(?:me)?|poner|reproduce|reproducir|toca(?:me)?|escucha(?:me)?|b[uú]sca(?:me|r|lo|la)?|encuentra(?:me|r)?|mu[eé]stra(?:me|r)?)\s*"#,
            #"^(?:reproductor\s+interno|youtube\s+interno|m[uú]sica\s+intern[oa]|beto\s*dicta|btodicta)[,;:]?\s*"#,
            #"^(?:en|por|con)\s+(?:reproductor\s+interno|youtube\s+interno|beto\s*dicta|apple\s+music|youtube\s+music|spotify|youtube|soundcloud|bandcamp)[,;:]?\s*"#,
            #"^(?:(?:una|la|alguna|cualquier|cualquiera)\s+)?(?:m[uú]sica|canci[oó]n(?:es)?|tema|playlist|radio|[aá]lbum)\s*(?:(?:cualquiera|cualquier)\s+)?(?:de\s+)?"#,
            #"^(?:algo|alguna|cualquiera|cualquier)\s+(?:de\s+)?"#,
        ]
        var cambio = true
        while cambio {
            cambio = false
            for patron in patrones {
                guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
                let ns = s as NSString
                guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
                      m.range.length > 0 else { continue }
                s = ns.substring(from: NSMaxRange(m.range))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-\n\t"))
                cambio = true
                break
            }
        }
        if s.lowercased().hasPrefix("de ") { s.removeFirst(3) }
        return quitarNombreProveedor(s, id: proveedor)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-\n\t"))
    }

    private static func codificar(_ texto: String) -> String {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "+&=?#")
        return texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? texto
    }

    private static func url(_ p: ProveedorMusica, consulta: String) -> URL? {
        let q = codificar(consulta)
        return URL(string: p.plantilla.replacingOccurrences(of: "{q}", with: q))
    }

    private static func escaparAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Sin consulta reproduce una pista aleatoria de la biblioteca (valor por
    /// defecto) o reanuda, según el ajuste del usuario. Con consulta reproduce
    /// la primera coincidencia REAL de la biblioteca local. El catálogo remoto
    /// de Apple Music no expone una búsqueda+play arbitraria por AppleScript.
    private static func reproducirApple(_ consulta: String) -> Bool {
        guard Config.musicaIntentarReproducir() else { return false }
        let source: String
        if consulta.isEmpty {
            if Config.musicaSinConsulta() == "reanudar" {
                source = """
                tell application "Music"
                    activate
                    play
                    if player state is playing then return "OK"
                    return "NO"
                end tell
                """
            } else {
                source = """
                tell application "Music"
                    activate
                    set candidatas to every track of library playlist 1 whose enabled is true and duration > 60 and artist is not ""
                    if (count of candidatas) is 0 then set candidatas to every track of library playlist 1 whose enabled is true and duration > 60
                    if (count of candidatas) is 0 then set candidatas to every track of library playlist 1 whose enabled is true
                    set totalPistas to count of candidatas
                    if totalPistas is 0 then return "NO"
                    set indice to random number from 1 to totalPistas
                    play item indice of candidatas
                    delay 0.15
                    if player state is playing then return "OK"
                    return "NO"
                end tell
                """
            }
        } else {
            let q = escaparAppleScript(consulta)
            source = """
            tell application "Music"
                set encontrados to search library playlist 1 for "\(q)"
                if (count of encontrados) is 0 then return "NO"
                play item 1 of encontrados
                return "OK"
            end tell
            """
        }
        var error: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return false }
        return r?.stringValue == "OK"
    }

    /// Music puede tardar en publicar la biblioteca después de un arranque en
    /// frío. Abrimos la app una sola vez y reintentamos la operación real con
    /// una espera acotada; cada intento vuelve a verificar `player state`.
    /// Nunca se anuncia reproducción por el mero hecho de que la app se abrió.
    static func esperasArranqueApple(yaAbierto: Bool) -> [TimeInterval] {
        yaAbierto ? [0, 0.30, 0.55] : [0.45, 0.65, 0.85, 1.10, 1.40]
    }

    private static func reproducirApplePreparado(
        _ consulta: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard Config.musicaIntentarReproducir(),
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Music") else {
            completion(false); return
        }
        let yaAbierto = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Music").isEmpty
        let esperas = esperasArranqueApple(yaAbierto: yaAbierto)

        func intentar(_ indice: Int) {
            let ejecutar = {
                if reproducirApple(consulta) {
                    completion(true)
                } else if indice + 1 < esperas.count {
                    intentar(indice + 1)
                } else {
                    completion(false)
                }
            }
            let demora = esperas[indice]
            if demora == 0 { ejecutar() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + demora, execute: ejecutar) }
        }

        if yaAbierto {
            intentar(0)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, error in
                DispatchQueue.main.async {
                    if error == nil { intentar(0) }
                    else { completion(false) }
                }
            }
        }
    }

    private static func reproducirSpotifySinConsulta() -> Bool {
        guard Config.musicaIntentarReproducir() else { return false }
        let accion = Config.musicaSinConsulta() == "reanudar"
            ? "play"
            : "set shuffling to true\n            next track\n            play"
        let source = """
            tell application id "com.spotify.client"
                activate
                \(accion)
                if player state is playing then return "OK"
                return "NO"
            end tell
            """
        var error: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && r?.stringValue == "OK"
    }

    private static func abrir(_ p: ProveedorMusica, consulta: String,
                              intencion: IntencionMusica) -> EstadoMusica? {
        if intencion == .reproducir, p.id == "apple_music", reproducirApple(consulta) {
            return .reproduciendo
        }
        if intencion == .reproducir, p.id == "spotify", consulta.isEmpty,
           reproducirSpotifySinConsulta() { return .reproduciendo }
        if p.id == "apple_music", !consulta.isEmpty,
           AppleMusicCatalogo.abrirBusqueda(consulta) { return .busqueda }
        if consulta.isEmpty, !p.bundle.isEmpty,
           let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundle) {
            NSWorkspace.shared.openApplication(at: app, configuration: .init(), completionHandler: nil)
            return .abierto
        }
        guard let u = url(p, consulta: consulta) else { return nil }
        if NSWorkspace.shared.open(u) { return consulta.isEmpty ? .abierto : .busqueda }
        // Algunos macOS no aceptan el esquema music:// para una búsqueda. El
        // universal-link web conserva la consulta como failover del mismo motor.
        if p.id == "apple_music",
           let web = URL(string: "https://music.apple.com/search?term=\(codificar(consulta))") {
            return NSWorkspace.shared.open(web) ? .busqueda : nil
        }
        return nil
    }

    static func mensaje(estado: EstadoMusica, proveedor: ProveedorMusica,
                        consulta: String, intencion: IntencionMusica) -> String {
        switch estado {
        case .reproduciendo:
            return consulta.isEmpty
                ? (Config.musicaSinConsulta() == "reanudar"
                    ? "Listo, reanudé la música en \(proveedor.nombre)."
                    : "Listo, estoy poniendo una canción aleatoria en \(proveedor.nombre).")
                : "Listo, estoy reproduciendo «\(consulta)» en \(proveedor.nombre)."
        case .busqueda:
            if intencion == .buscar {
                return "Listo, te abrí la búsqueda de «\(consulta)» en \(proveedor.nombre)."
            }
            return "No pude reproducir «\(consulta)» automáticamente; te abrí la búsqueda en \(proveedor.nombre)."
        case .abierto:
            if intencion == .buscar { return "Abrí \(proveedor.nombre) para que busques música." }
            return "Abrí \(proveedor.nombre), pero no encontré una reproducción disponible."
        case .pausado: return "Pausé la reproducción."
        case .detenido: return "Detuve la reproducción."
        case .fallo:
            return "No pude abrir ningún servicio de música."
        }
    }

    static func orden(solicitado: String) -> [ProveedorMusica] {
        var ids: [String] = []
        if solicitado != "auto", !solicitado.isEmpty { ids.append(solicitado) }
        ids.append(contentsOf: Config.musicaCascada())
        ids.append(contentsOf: ["youtube_music", "youtube"])
        var vistos = Set<String>()
        return ids.compactMap { id in
            guard vistos.insert(id).inserted, let p = proveedor(id), disponible(p) else { return nil }
            return p
        }
    }

    static func ejecutar(_ consulta: String, solicitado: String = "auto",
                         intencion: IntencionMusica = .reproducir,
                         simular: Bool = false,
                         completion: @escaping (ResultadoMusica) -> Void) {
        let cascada: (Set<String>) -> Void = { omitidos in
            // Reanudar el reproductor global sigue disponible, pero es una
            // preferencia explícita. El valor predeterminado recorre la cascada
            // y pide una pista aleatoria al primer motor que pueda demostrarlo.
            if intencion == .reproducir, Config.musicaSinConsulta() == "reanudar",
               !simular, consulta.isEmpty, ["", "auto"].contains(solicitado),
               Config.musicaIntentarReproducir(), MediaControl.reproducirActual() {
                let mensaje = "Listo, reanudé tu reproductor actual."
                AgenteLog.registrar("musica", ["proveedor": "sistema", "consulta": "",
                                                  "simular": false, "ok": true,
                                                  "intencion": intencion.rawValue,
                                                  "estado": EstadoMusica.reproduciendo.rawValue])
                completion(ResultadoMusica(ok: true, proveedor: "sistema",
                                           mensaje: mensaje, estado: .reproduciendo)); return
            }
            let candidatos = orden(solicitado: solicitado).filter { !omitidos.contains($0.id) }
            guard !candidatos.isEmpty else {
                completion(ResultadoMusica(ok: false, proveedor: "",
                    mensaje: "No hay un servicio de música disponible.", estado: .fallo)); return
            }
            for p in candidatos {
                let estado: EstadoMusica? = simular
                    ? (intencion == .buscar ? (consulta.isEmpty ? .abierto : .busqueda) : .reproduciendo)
                    : abrir(p, consulta: consulta, intencion: intencion)
                if let estado {
                    let accion = mensaje(estado: estado, proveedor: p,
                                         consulta: consulta, intencion: intencion)
                    AgenteLog.registrar("musica", ["proveedor": p.id, "consulta": consulta,
                                                    "simular": simular, "ok": true,
                                                    "intencion": intencion.rawValue,
                                                    "estado": estado.rawValue])
                    completion(ResultadoMusica(ok: true, proveedor: p.id,
                                               mensaje: accion, estado: estado)); return
                }
            }
            AgenteLog.registrar("musica", ["consulta": consulta, "ok": false,
                                            "intencion": intencion.rawValue])
            completion(ResultadoMusica(ok: false, proveedor: "",
                                       mensaje: "No pude abrir ningún servicio de música.",
                                       estado: .fallo))
        }

        let trabajo = {
            let puedeUsarApple = ["", "auto", "apple_music"].contains(solicitado)
            let primero = orden(solicitado: solicitado).first

            // Con la preferencia aleatoria, Apple Music debe estar listo antes
            // de consultar la biblioteca. Este camino cubre tanto la app ya
            // abierta como el arranque en frío y solo termina al confirmar play.
            if intencion == .reproducir, !simular, consulta.isEmpty,
               Config.musicaSinConsulta() != "reanudar",
               primero?.id == "apple_music" {
                reproducirApplePreparado(consulta) { ok in
                    if ok, let apple = proveedor("apple_music") {
                        let m = mensaje(estado: .reproduciendo, proveedor: apple,
                                        consulta: consulta, intencion: intencion)
                        AgenteLog.registrar("musica", ["proveedor": "apple_music",
                                                        "consulta": "", "ok": true,
                                                        "intencion": intencion.rawValue,
                                                        "estado": EstadoMusica.reproduciendo.rawValue])
                        completion(.init(ok: true, proveedor: "apple_music",
                                         mensaje: m, estado: .reproduciendo))
                    } else {
                        AgenteLog.registrar("musica_failover", ["de": "apple_music_arranque",
                                                                "motivo": "no confirmó reproducción"])
                        cascada(["apple_music"])
                    }
                }
                return
            }

            // Reproductor propio: la búsqueda usa exclusivamente YouTube Data
            // API y la reproducción el IFrame Player oficial. La contraseña de
            // Google nunca entra en BtoDicta; OAuth ocurre en el navegador.
            if !simular, primero?.id == "btodicta_youtube" {
                let debeReproducir = intencion == .reproducir
                DispatchQueue.main.async {
                    ReproductorYouTubeInterno.shared.ejecutar(
                        consulta, reproducir: debeReproducir) { r in
                        let estado: EstadoMusica = r.reproduciendo ? .reproduciendo
                            : (r.encontro ? .busqueda : .fallo)
                        AgenteLog.registrar(r.encontro ? "musica" : "musica_failover", [
                            "proveedor": "btodicta_youtube", "consulta": consulta,
                            "ok": r.encontro, "intencion": intencion.rawValue,
                            "estado": estado.rawValue, "detalle": r.mensaje,
                        ])
                        if r.reproduciendo || (intencion == .buscar && r.encontro)
                            || (solicitado == "btodicta_youtube" && r.encontro) {
                            completion(.init(ok: true, proveedor: "btodicta_youtube",
                                             mensaje: r.mensaje, estado: estado))
                        } else {
                            cascada(["btodicta_youtube"])
                        }
                    }
                }
                return
            }

            // YouTube Music usa su app/PWA instalada cuando existe y la web
            // como failover. «Busca» termina en resultados; «reproduce» pulsa
            // el primer resultado AX y exige que la barra de ESA ventana pase
            // a «Pausar» antes de anunciar éxito.
            if !simular, !consulta.isEmpty, primero?.id == "youtube_music" {
                let debeReproducir = intencion == .reproducir
                    && Config.musicaIntentarReproducir()
                YouTubeMusicControl.ejecutar(consulta, reproducir: debeReproducir) { r in
                    let estado: EstadoMusica = r.reproduciendo ? .reproduciendo
                        : (r.ok ? .busqueda : .fallo)
                    let proveedor = r.via.isEmpty
                        ? "youtube_music" : "youtube_music_\(r.via)"
                    AgenteLog.registrar(r.ok ? "musica" : "musica_failover", [
                        "proveedor": proveedor, "consulta": consulta, "ok": r.ok,
                        "intencion": intencion.rawValue, "estado": estado.rawValue,
                        "detalle": r.detalle
                    ])
                    if r.ok {
                        completion(.init(ok: true, proveedor: proveedor,
                                         mensaje: r.detalle, estado: estado))
                    } else {
                        cascada(["youtube_music"])
                    }
                }
                return
            }

            // `spotify:search:` solo abre resultados. Cuando Spotify es el
            // proveedor elegido y la orden dice pon/reproduce, la capa AX pulsa
            // el primer botón visible y comprueba el player state antes de
            // responder. Una orden buscar sigue abriendo resultados sin play.
            if intencion == .reproducir, !simular, !consulta.isEmpty,
               primero?.id == "spotify" {
                SpotifyControl.reproducirPrimera(consulta) { r in
                    if r.ok {
                        AgenteLog.registrar("musica", ["proveedor": "spotify",
                                                        "consulta": consulta, "ok": true,
                                                        "intencion": intencion.rawValue,
                                                        "estado": EstadoMusica.reproduciendo.rawValue])
                        completion(.init(ok: true, proveedor: "spotify",
                                         mensaje: r.detalle, estado: .reproduciendo))
                    } else {
                        AgenteLog.registrar("musica_failover", ["de": "spotify_auto",
                                                                "motivo": r.detalle])
                        completion(.init(ok: true, proveedor: "spotify",
                                         mensaje: r.detalle, estado: .busqueda))
                    }
                }
                return
            }
            let catalogoOCascada: () -> Void = {
                guard intencion == .reproducir, !simular, !consulta.isEmpty, puedeUsarApple else {
                    cascada([]); return
                }
                // La biblioteca local es instantánea y no necesita red.
                if reproducirApple(consulta) {
                    let m = proveedor("apple_music").map {
                        mensaje(estado: .reproduciendo, proveedor: $0,
                                consulta: consulta, intencion: intencion)
                    } ?? "Listo, estoy reproduciendo «\(consulta)» en Apple Music."
                    AgenteLog.registrar("musica", ["proveedor": "apple_music_local",
                                                    "consulta": consulta, "ok": true,
                                                    "intencion": intencion.rawValue,
                                                    "estado": EstadoMusica.reproduciendo.rawValue])
                    completion(.init(ok: true, proveedor: "apple_music_local",
                                     mensaje: m, estado: .reproduciendo)); return
                }
                AppleMusicCatalogo.reproducirPrimera(consulta) { r in
                    if r.ok {
                        completion(.init(ok: true, proveedor: "apple_music_catalogo",
                                         mensaje: r.motivo, estado: .reproduciendo)); return
                    }
                    AgenteLog.registrar("musica_failover", ["de": "apple_music_catalogo",
                                                            "motivo": r.motivo])
                    cascada([])
                }
            }
            // Apple no expone una API pública para inyectar órdenes en Siri. El
            // Atajo incluido usa acciones oficiales de Música, pero BtoDicta no
            // confía solo en que macOS acepte abrirlo: verifica título/artista y,
            // si no coinciden,
            // continúa por la cascada sin anunciar un éxito falso.
            // Una búsqueda explícita jamás dispara reproducción. El Atajo se
            // reserva para “pon/reproduce” con una consulta concreta.
            if intencion == .reproducir, !simular, !consulta.isEmpty,
               Config.musicaAtajoPrimero() {
                let atajo = Config.musicaAtajoApple()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !atajo.isEmpty {
                    AppleAtajos.ejecutarMusica(nombre: atajo, texto: consulta) { r in
                        if r.ok {
                            AgenteLog.registrar("musica", ["proveedor": "atajo_apple",
                                                            "atajo": atajo,
                                                            "consulta": consulta, "ok": true,
                                                            "intencion": intencion.rawValue,
                                                            "estado": EstadoMusica.reproduciendo.rawValue])
                            completion(ResultadoMusica(ok: true, proveedor: "atajo_apple",
                                                       mensaje: r.mensaje,
                                                       estado: .reproduciendo)); return
                        }
                        AgenteLog.registrar("musica_failover", ["de": "atajo_apple",
                                                                "motivo": r.mensaje])
                        catalogoOCascada()
                    }
                    return
                }
            }
            catalogoOCascada()
        }
        if Thread.isMainThread { trabajo() } else { DispatchQueue.main.async(execute: trabajo) }
    }
}
