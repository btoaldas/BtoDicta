import Foundation

// MARK: - Núcleo local del asistente
//
// BtoDicta conserva sus capas originales (STT → Modos → IA/TTS). Este núcleo no
// las sustituye: añade identidad, autonomía, memoria breve y herramientas locales.
// Las reglas deterministas ganan primero; una IA solo responde cuando ninguna
// herramienta concreta resuelve el pedido.

enum NivelAutonomiaAgente: String, CaseIterable, Identifiable {
    case consultivo, asistido, autonomo

    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .consultivo: return "1 · Consultivo"
        case .asistido: return "2 · Asistido"
        case .autonomo: return "3 · Autónomo"
        }
    }
    var detalle: String {
        switch self {
        case .consultivo:
            return "Propone y pregunta antes de ejecutar cualquier herramienta."
        case .asistido:
            return "Puede leer, buscar, abrir y controlar música; confirma cambios y envíos."
        case .autonomo:
            return "También hace cambios locales reversibles; envíos, compras, borrados y publicaciones siempre se confirman."
        }
    }
}

enum RiesgoAgente: Int, Comparable {
    case lectura = 0              // consultar tareas/hora/listados
    case reversible = 1           // abrir app/web, buscar archivo, música
    case cambioLocal = 2          // crear recordatorio/evento/nota/tarea
    case externo = 3              // correo, WhatsApp, Atajo desconocido
    case destructivo = 4          // nunca se autoejecuta

    static func < (lhs: RiesgoAgente, rhs: RiesgoAgente) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum PoliticaAgente {
    static var nivel: NivelAutonomiaAgente {
        NivelAutonomiaAgente(rawValue: Config.agenteAutonomia()) ?? .asistido
    }

    static func riesgo(de cadena: ModoCadena) -> RiesgoAgente {
        var salida: RiesgoAgente = cadena.transforms.isEmpty ? .lectura : .reversible
        for etapa in cadena.acciones {
            let id = etapa.modo.accion
            let r: RiesgoAgente
            if etapa.modo.base == "buscar" || etapa.modo.base == "aplicacion" || etapa.modo.base == "musica" {
                r = .reversible
            } else {
                switch id {
                case "clima":
                    r = .lectura
                case "musica", "volumen", "archivo", "finder", "safari", "mapas", "spotlight", "aplicacion":
                    r = .reversible
                case "recordatorios", "calendario", "notas", "nota_local", "tarea_local", "archivo_nuevo",
                     "captura_pantalla", "grabar_pantalla":
                    r = .cambioLocal
                case "atajo_apple":
                    r = AppleAtajosCatalogo.riesgo(nombre: etapa.modo.prompt.isEmpty
                        ? Config.agenteAtajoApple() : etapa.modo.prompt)
                case "gmail", "correo", "outlook", "whatsapp", "mensajes", "url",
                     "captura_compartir":
                    r = .externo
                case "rutina":
                    r = RutinasAgenteStore.riesgo(id: etapa.modo.prompt)
                case "conexion":
                    // Lectura pura = reversible; una conexión con CUALQUIER
                    // endpoint de escritura se trata completa como externa.
                    r = ConexionesMotor.riesgo(etapa.modo.conexion)
                default:
                    r = .reversible
                }
            }
            if r > salida { salida = r }
        }
        return salida
    }

    /// Solo se usa para pedidos hechos dentro del Modo Agente / frase de presencia.
    /// Los pedidos naturales captados desde Dictado conservan siempre su modal actual.
    static func autoEjecutar(_ cadena: ModoCadena) -> Bool {
        autoEjecutar(cadena, nivel: nivel)
    }

    static func autoEjecutar(_ cadena: ModoCadena, nivel: NivelAutonomiaAgente) -> Bool {
        let r = riesgo(de: cadena)
        switch nivel {
        case .consultivo: return false
        case .asistido: return r <= .reversible
        case .autonomo: return r <= .cambioLocal
        }
    }
}

enum FormatoRespuestaAgente: String, CaseIterable, Identifiable {
    case texto
    case textoVoz = "texto_voz"

    var id: String { rawValue }
}

/// Frases breves y deterministas para las respuestas operativas. No despierta
/// una IA y, sobre todo, no anuncia éxito antes de recibir el resultado real.
enum MensajesAgente {
    /// Una grabación de pantalla debe empezar y terminar sin voz del asistente:
    /// cualquier acuse, pregunta hablada o error podría quedar dentro del video.
    /// La regla cubre también cadenas que transforman texto antes de grabar.
    static func requiereSilencioTotal(_ cadena: ModoCadena) -> Bool {
        if cadena.acciones.contains(where: { $0.modo.accion == "grabar_pantalla" }) {
            return true
        }
        // "Graba la pantalla y envíala por WhatsApp" se representa con la
        // acción de compartir, pero sigue siendo VIDEO. No debe colarse el
        // acuse hablado ni el sonido final dentro de esa grabación.
        return cadena.acciones.contains(where: { $0.modo.accion == "captura_compartir" })
            && SolicitudCapturaMac.interpretar(cadena.contenido).tipo == .video
    }

    static func confirmacion(_ pregunta: ModoPreguntaPlan, modoNormal: Modo) -> String {
        let accion = pregunta.descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        return "¿Deseas \(accion.lowercased())? Pulsa función una vez para confirmar, o X para seguir en \(modoNormal.nombre)."
    }

    static func confirmacionModo(_ modo: Modo, modoNormal: Modo) -> String {
        "¿Deseas usar el modo \(modo.nombre)? Pulsa función una vez para confirmar, o X para seguir en \(modoNormal.nombre)."
    }

    /// Música sola responde con su resultado: “reproduciendo” o “abrí la
    /// búsqueda”. Un modo transformador solo (traducir/resumir/…) responde con
    /// el texto final. Así evitamos dos voces seguidas y nunca fingimos éxito.
    static func esperaResultado(_ cadena: ModoCadena) -> Bool {
        if cadena.acciones.isEmpty, !cadena.transforms.isEmpty { return true }
        if cadena.transforms.isEmpty, cadena.acciones.count == 1,
           cadena.acciones[0].modo.accion == "rutina",
           RutinasAgenteStore.devuelveResultado(id: cadena.acciones[0].modo.prompt) {
            return true
        }
        // Las capturas responden únicamente DESPUÉS del resultado. Antes se
        // decía «voy a abrir captura…» mientras `screencapture` arrancaba; una
        // voz local lenta podía quedar viva y dejar ese acuse pegado en el
        // notch. En video, además, el silencio total sigue teniendo prioridad.
        if cadena.transforms.isEmpty, cadena.acciones.count == 1,
           ["captura_pantalla", "captura_compartir"]
            .contains(cadena.acciones[0].modo.accion) { return true }
        if cadena.transforms.isEmpty, cadena.acciones.count == 1,
           cadena.acciones[0].modo.accion == "clima" { return true }
        if cadena.transforms.isEmpty, cadena.acciones.count == 1,
           cadena.acciones[0].modo.accion == "volumen" { return true }
        return cadena.transforms.isEmpty && cadena.acciones.count == 1
            && cadena.acciones[0].modo.base == "musica"
    }

    static func acuse(_ cadena: ModoCadena) -> String {
        let pregunta = ModoPlanificador.pregunta(para: cadena)
        let accion = pregunta.descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accion.isEmpty else { return "De acuerdo." }
        return "De acuerdo, voy a \(accion.lowercased())."
    }

    static let sinEntender = "No te entendí con suficiente claridad. Puedes repetirlo o decir el modo que quieres usar."
    static let escuchando = "Te escucho. Puedes continuar en el próximo dictado."
}

enum PerfilAgente {
    struct Invocacion {
        let frase: String
        let contenido: String
    }

    private static let palabra = try! NSRegularExpression(pattern: #"\p{L}[\p{L}\p{N}'’_-]*|\p{N}+"#)

    static func normalizar(_ s: String) -> String {
        String(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " "))
    }

    /// Detecta únicamente al INICIO y devuelve el texto restante sin destruir su
    /// puntuación. No mantiene el micrófono abierto: opera sobre el dictado normal.
    static func invocacion(en texto: String) -> Invocacion? {
        guard Config.agenteNucleoActivo() else { return nil }
        var activadores = Config.agenteActivadores()
        if Config.agenteCompatibilidadSiriLocal() {
            activadores += PasarelaSiriBeto.activadoresLocales(
                nombreAgente: Config.agenteNombre())
        }
        return invocacion(en: texto, activadores: activadores)
    }

    static func invocacion(en texto: String, activadores: [String]) -> Invocacion? {
        let ns = texto as NSString
        let matches = palabra.matches(in: texto, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        let originales = matches.map { ns.substring(with: $0.range) }
        let normales = originales.map(normalizar)
        // Defensa en profundidad: los tests y otros llamadores pueden pasar una
        // lista directa sin atravesar Config. Nunca aceptar un activador genérico
        // de una palabra como "oye" o "beto".
        for frase in FrasesConfigurables.activadoresSeguros(activadores)
            .sorted(by: { $0.count > $1.count }) {
            let ft = normalizar(frase).split(separator: " ").map(String.init)
            guard !ft.isEmpty, ft.count <= normales.count,
                  Array(normales.prefix(ft.count)) == ft else { continue }
            let fin = NSMaxRange(matches[ft.count - 1].range)
            let resto = ns.substring(from: fin)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;—-\n\t"))
            return Invocacion(frase: frase, contenido: resto)
        }
        return nil
    }

    /// Variante conservadora exclusiva del detector manos libres. Apple puede
    /// escribir un nombre poco común con una letra extra ("Beteo" por "Beto").
    /// La primera palabra debe ser exacta y cada palabra restante conservar al
    /// menos 80 % de similitud; así "Oye Beteo" vale, pero "Oye beta" no.
    static func invocacionTolerante(en texto: String, activadores: [String]) -> Invocacion? {
        if let exacta = invocacion(en: texto, activadores: activadores) { return exacta }
        let ns = texto as NSString
        let matches = palabra.matches(in: texto, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        let normales = matches.map { normalizar(ns.substring(with: $0.range)) }
        for frase in FrasesConfigurables.activadoresSeguros(activadores)
            .sorted(by: { $0.count > $1.count }) {
            let ft = normalizar(frase).split(separator: " ").map(String.init)
            guard ft.count >= 2, ft.count <= normales.count,
                  normales[0] == ft[0] else { continue }
            let sims = zip(normales.prefix(ft.count), ft).map {
                ModoFuzzy.similitud($0.0, $0.1)
            }
            guard sims.dropFirst().allSatisfy({ $0 >= 0.80 }),
                  sims.reduce(0, +) / Double(sims.count) >= 0.88 else { continue }
            let fin = NSMaxRange(matches[ft.count - 1].range)
            let resto = ns.substring(from: fin)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;—-\n\t"))
            return Invocacion(frase: frase, contenido: resto)
        }
        return nil
    }

    /// El detector manos libres ya confirmó acústicamente una frase concreta.
    /// El búfer circular puede incluir silencio o palabras anteriores, por eso
    /// aquí se permite localizar ESA frase en cualquier posición y se descarta
    /// todo lo previo. No se usa en dictados normales: allí la frase continúa
    /// obligada al inicio para evitar falsos positivos.
    static func invocacionDedicada(en texto: String, frase: String) -> Invocacion? {
        guard FrasesConfigurables.activadorSeguro(frase) else { return nil }
        let ns = texto as NSString
        let matches = palabra.matches(in: texto,
                                      range: NSRange(location: 0, length: ns.length))
        let objetivo = normalizar(frase).split(separator: " ").map(String.init)
        guard !matches.isEmpty, !objetivo.isEmpty, objetivo.count <= matches.count else { return nil }
        let normales = matches.map { normalizar(ns.substring(with: $0.range)) }
        for inicio in 0...(normales.count - objetivo.count) {
            let finIndice = inicio + objetivo.count
            let candidato = Array(normales[inicio..<finIndice])
            let exacto = candidato == objetivo
            let sims = zip(candidato, objetivo).map {
                ModoFuzzy.similitud($0.0, $0.1)
            }
            let tolerante = candidato.first == objetivo.first
                && sims.dropFirst().allSatisfy { $0 >= 0.80 }
                && sims.reduce(0, +) / Double(max(1, sims.count)) >= 0.88
            guard exacto || tolerante else { continue }
            let fin = NSMaxRange(matches[finIndice - 1].range)
            let resto = ns.substring(from: fin)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;—-\n\t"))
            return Invocacion(frase: frase, contenido: resto)
        }
        return nil
    }

    static func prompt() -> String {
        let n = Config.agenteNombre()
        let p = Config.agentePersonalidad().trimmingCharacters(in: .whitespacesAndNewlines)
        let nivel = PoliticaAgente.nivel
        return """
        Tu nombre o presencia es \(n). Eres el asistente de voz local de la persona que usa BtoDicta.
        PERSONALIDAD CONFIGURADA: \(p.isEmpty ? "Natural, útil, directo y respetuoso." : p)
        NIVEL DE AUTONOMÍA: \(nivel.nombre). \(nivel.detalle)
        Responde en español natural, breve y sin preámbulos porque el resultado se leerá en voz alta.
        Nunca afirmes que abriste, enviaste, guardaste o modificaste algo si BtoDicta no te entregó un resultado real de herramienta.
        """
    }

    static func envolverParaHermes(_ pedido: String) -> String {
        let memoria = Config.agenteMemoriaContextoIA() ? MemoriaAgente.contexto() : ""
        return ["[PRESENCIA DE BTODICTA]", prompt(), memoria,
                "PEDIDO DEL USUARIO:\n\(pedido)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

// MARK: - Memoria conversacional corta (local, acotada y borrable)

struct TurnoAgente: Codable, Identifiable {
    var id: String
    var fecha: Double
    var usuario: String
    var asistente: String

    init(usuario: String, asistente: String) {
        id = UUID().uuidString; fecha = Date().timeIntervalSince1970
        self.usuario = usuario; self.asistente = asistente
    }
}

enum MemoriaAgente {
    private static var url: URL { Config.dir.appendingPathComponent("agente_memoria.json") }
    private static let lock = NSLock()

    private static func leerSinLock() -> [TurnoAgente] {
        guard let d = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode([TurnoAgente].self, from: d) else { return [] }
        return t
    }

    static func todos() -> [TurnoAgente] {
        lock.lock(); defer { lock.unlock() }
        return leerSinLock()
    }

    static func registrar(usuario: String, asistente: String) {
        guard Config.agenteMemoriaActiva() else { return }
        let u = usuario.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = asistente.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !a.isEmpty else { return }
        lock.lock()
        var t = leerSinLock(); t.append(TurnoAgente(usuario: u, asistente: a))
        // El control de Ajustes significa exactamente cuántos intercambios se
        // conservan; cada TurnoAgente ya contiene usuario + asistente.
        t = Array(t.suffix(Config.agenteMemoriaTurnos()))
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(t) {
            try? d.write(to: url, options: .atomic); Config.protegerSecreto(url)
        }
        lock.unlock()
    }

    static func limpiar() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    static func contexto() -> String {
        guard Config.agenteMemoriaActiva() else { return "" }
        let turnos = Array(todos().suffix(Config.agenteMemoriaTurnos()))
        guard !turnos.isEmpty else { return "" }
        let lineas = turnos.map {
            "Usuario: \($0.usuario.prefix(700))\n\(Config.agenteNombre()): \($0.asistente.prefix(900))"
        }
        return "MEMORIA CORTA DE ESTA CONVERSACIÓN (solo úsala si ayuda):\n" + lineas.joined(separator: "\n")
    }

    static func ultimoResumen() -> String? {
        guard let t = todos().last else { return nil }
        return "Me dijiste: «\(t.usuario)». Yo respondí: «\(t.asistente)»."
    }

    /// Texto al que suelen referirse “envíalo”, “tradúcelo” o “resúmelo”. Se
    /// limita antes de volver a entrar al planificador para que la memoria corta
    /// nunca convierta un seguimiento en un prompt sin límite.
    static func ultimaRespuestaParaReferencia() -> String? {
        guard Config.agenteMemoriaActiva(), let s = todos().last?.asistente
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return String(s.prefix(2_000))
    }
}

// MARK: - Registro auditable del agente

enum AgenteLog {
    private static let lock = NSLock()
    private static var url: URL {
        Config.dir.appendingPathComponent("logs", isDirectory: true).appendingPathComponent("agente.jsonl")
    }

    static func registrar(_ evento: String, _ datos: [String: Any] = [:]) {
        guard Config.logModos() else { return }
        var d = datos; d["evento"] = evento; d["ts"] = Date().timeIntervalSince1970
        guard JSONSerialization.isValidJSONObject(d),
              let raw = try? JSONSerialization.data(withJSONObject: d),
              var linea = String(data: raw, encoding: .utf8) else { return }
        linea += "\n"
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default; let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(linea.utf8)); try? h.close()
        }
        Config.protegerSecreto(url)
    }
}

// MARK: - Planificación local y respuestas que no necesitan IA

enum AgenteNucleo {
    private static func n(_ s: String) -> String { PerfilAgente.normalizar(s) }

    private static func accion(_ id: String, nombre: String? = nil, prompt: String = "") -> Modo {
        Modo(id: "agente-\(id)", nombre: nombre ?? Acciones.nombre(id), icono: "bolt.fill",
             base: "accion", prompt: prompt, accion: id)
    }

    private static func quitarPrefijo(_ texto: String, patrones: [String]) -> String {
        var salida = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        for patron in patrones {
            guard let re = try? NSRegularExpression(pattern: "^(?:por\\s+favor[,;:]?\\s*)?(?:\(patron))\\s*",
                                                    options: [.caseInsensitive]) else { continue }
            let ns = salida as NSString
            if let m = re.firstMatch(in: salida, range: NSRange(location: 0, length: ns.length)) {
                salida = ns.substring(from: NSMaxRange(m.range))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
                break
            }
        }
        return salida
    }

    private static func herramientasPermitidas(_ cadena: ModoCadena) -> Bool {
        cadena.acciones.allSatisfy { etapa in
            if etapa.modo.base == "musica" { return Config.agenteHerramientaMusica() }
            if etapa.modo.base == "aplicacion" { return Config.agenteHerramientaAplicaciones() }
            guard etapa.modo.base == "accion" else { return true }
            switch etapa.modo.accion {
            case "recordatorios": return Config.agenteHerramientaRecordatorios()
            case "calendario": return Config.agenteHerramientaCalendario()
            case "archivo", "archivo_nuevo": return Config.agenteHerramientaArchivos()
            case "captura_pantalla", "grabar_pantalla", "captura_compartir":
                return Config.agenteHerramientaCapturas()
            case "clima": return Config.agenteHerramientaClima()
            case "volumen": return Config.agenteHerramientaVolumen()
            case "atajo_apple": return Config.agenteHerramientaAtajos()
            case "gmail", "correo", "outlook", "whatsapp", "mensajes":
                return Config.agenteHerramientaComunicaciones()
            case "conexion": return Config.agenteHerramientaConexiones()
            default: return true
            }
        }
    }

    private static func pareceSeguimiento(_ texto: String) -> Bool {
        guard let primera = n(texto).split(separator: " ").first.map(String.init) else { return false }
        return [
            "envialo", "enviaselo", "mandalo", "mandaselo", "compartelo", "pasalo",
            "traducelo", "traducela", "resumelo", "formalizalo", "guardalo", "anotalo",
            "recuerdalo", "recuerdamelo"
        ].contains(primera)
    }

    enum AreaAclaracionCaptura: String {
        case pantalla
        case ventana
    }

    private struct PedidoCapturaNatural {
        let esGrabacion: Bool
        let esCaptura: Bool
        let requiereArea: Bool
        let comparte: Bool
    }

    /// Analiza únicamente órdenes en la zona inicial. Mantener esta gramática
    /// cerrada evita que una narración como “cuando comience una grabación…”
    /// se convierta accidentalmente en una herramienta.
    private static func analizarPedidoCaptura(_ texto: String) -> PedidoCapturaNatural? {
        let normal = n(texto)
        let tokens = normal.split(separator: " ").map(String.init)
        let cortesia: Set<String> = ["por", "favor", "porfavor", "porfa", "oye", "bto",
                                     "beto", "jarvis", "me"]
        var inicio = 0
        while inicio < tokens.count, cortesia.contains(tokens[inicio]) { inicio += 1 }
        guard inicio < tokens.count else { return nil }
        let verbo = tokens[inicio]
        let directos: Set<String> = ["haz", "haga", "hagas", "hacer", "toma", "tomar",
                                     "saca", "sacar", "captura", "capturar", "graba", "grabar",
                                     "grabemos", "realiza", "realizar", "inicia", "iniciar",
                                     "inicie", "comienza", "comenzar", "comience", "hagamos"]
        let peticion = ["puedes", "podrias"].contains(verbo)
            && inicio + 1 < tokens.count
            && ["hacer", "tomar", "sacar", "capturar", "grabar", "iniciar", "comenzar"]
                .contains(tokens[inicio + 1])
        let deseo = ["quiero", "necesito"].contains(verbo)
            && tokens.dropFirst(inicio + 1).prefix(3).contains(where: {
                ["captura", "capturar", "grabacion", "grabar"].contains($0)
            })
        // ElevenLabs/Apple pueden oír el imperativo «toma» como «tomo». Esa
        // forma solo se acepta cuando la MISMA frase también pide compartir la
        // captura por WhatsApp; así no convertimos narraciones como «tomo
        // capturas para mis informes» en una acción.
        let tomoCompartir = verbo == "tomo" && normal.contains("whatsapp")
            && normal.range(of: #"\b(?:envio|envia|enviala|mando|mandala|comparto|compartela)\b"#,
                            options: .regularExpression) != nil
        guard directos.contains(verbo) || peticion || deseo || tomoCompartir else { return nil }
        let pideGrabar = normal.contains("graba") || normal.contains("grabar")
            || normal.contains("grabemos") || normal.contains("grabacion")
            || normal.contains("video") || normal.contains("inicia")
            || normal.contains("iniciar") || normal.contains("comienza")
            || normal.contains("comenzar")
        let objetoVisible = normal.contains("pantalla") || normal.contains("ventana")
            || normal.contains("seccion") || normal.contains("seleccion") || normal.contains("area")
        let esAudio = normal.contains("audio") || normal.contains("voz")
            || normal.contains("podcast") || normal.contains("nota de voz")
        let restoGrabemos = tokens.dropFirst(inicio + 1).filter {
            !["un", "una", "la", "el", "por", "favor", "porfavor", "porfa"].contains($0)
        }
        let grabemosSolo = verbo == "grabemos" && restoGrabemos.isEmpty
        let grabacionGenerica = !esAudio && (normal.contains("grabacion") || grabemosSolo)
        let esGrabacion = pideGrabar && !esAudio && (objetoVisible || grabacionGenerica)
        let esCaptura = normal.contains("captura de pantalla")
            || normal.contains("pantallazo") || normal.contains("screenshot")
            || (normal.contains("captura") && (normal.contains("seccion")
                || normal.contains("ventana") || normal.contains("pantalla")
                || normal.contains("cuarto") || normal.contains("cuadrante")))
            || (tomoCompartir && normal.contains("captura"))
            || normal.contains("foto de la pantalla")
        guard esGrabacion || esCaptura else { return nil }
        return PedidoCapturaNatural(esGrabacion: esGrabacion, esCaptura: esCaptura,
                                    requiereArea: esGrabacion && !objetoVisible,
                                    comparte: normal.contains("whatsapp"))
    }

    /// Las grabaciones genéricas no adivinan qué parte de la pantalla quiere el
    /// usuario. AppDelegate guarda el pedido y pregunta “¿pantalla o ventana?”.
    static func necesitaAclararAreaCaptura(_ texto: String) -> Bool {
        analizarPedidoCaptura(texto)?.requiereArea == true
    }

    /// Interpreta la respuesta breve del siguiente turno sin perder el pedido
    /// original. Solo acepta las dos áreas ofrecidas; cualquier otra frase queda
    /// libre para continuar por el flujo normal de dictado.
    static func areaAclaracionCaptura(_ respuesta: String) -> AreaAclaracionCaptura? {
        let normal = n(respuesta)
        let tokens = normal.split(separator: " ").map(String.init)
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        if tokens.contains("ventana") || normal.contains("una ventana") {
            return .ventana
        }
        if tokens.contains("pantalla") || tokens.contains("monitor")
            || normal.contains("pantalla completa") || normal.contains("toda la pantalla") {
            return .pantalla
        }
        return nil
    }

    static func completarAclaracionCaptura(pedido: String, respuesta: String) -> String? {
        guard let area = areaAclaracionCaptura(respuesta) else { return nil }
        switch area {
        case .pantalla: return pedido + " de toda la pantalla"
        case .ventana: return pedido + " de una ventana"
        }
    }

    /// Intérprete puro de pantalla, separado para QA. Exige una forma verbal en
    /// la zona inicial: una narración como “la captura de ayer” no se ejecuta.
    static func planificarCaptura(_ texto: String) -> ModoPreguntaPlan? {
        guard let pedido = analizarPedidoCaptura(texto), !pedido.requiereArea else { return nil }
        let esGrabacion = pedido.esGrabacion
        let comparte = pedido.comparte
        let id = comparte ? "captura_compartir" : (esGrabacion ? "grabar_pantalla" : "captura_pantalla")
        let m = accion(id)
        return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: texto),
            fuente: .natural, confianza: 0.99)
    }

    /// Consulta de solo lectura. Funciona con ciudad explícita o con una única
    /// lectura de Core Location; nunca se entrega al cerebro de chat para que
    /// invente datos meteorológicos.
    static func planificarClima(_ texto: String) -> ModoPreguntaPlan? {
        guard Config.agenteHerramientaClima(),
              SolicitudClima.interpretar(texto) != nil else { return nil }
        let m = accion("clima", nombre: "Consultar clima")
        return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: texto),
            fuente: .natural, confianza: 0.99)
    }

    /// Control local, reversible y sin IA. La operación queda congelada dentro
    /// de `prompt`; el ejecutor no vuelve a reinterpretar una frase distinta.
    static func planificarVolumen(_ texto: String,
                                  permitir: Bool = Config.agenteHerramientaVolumen(),
                                  paso: Int = Config.agenteVolumenPaso()) -> ModoPreguntaPlan? {
        guard permitir,
              let solicitud = SolicitudVolumenMac.interpretar(texto,
                                                               pasoPredeterminado: paso) else { return nil }
        let m = accion("volumen", nombre: "Volumen del Mac", prompt: solicitud.codigo)
        return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: texto),
            fuente: .natural, confianza: 0.995)
    }

    /// Reutiliza la última RESPUESTA solo ante un pronombre imperativo inequívoco.
    /// Una frase corriente nunca hereda contenido en silencio.
    static func completarSeguimiento(_ texto: String, referencia: String?) -> String? {
        guard pareceSeguimiento(texto),
              let r = referencia?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return nil }
        let seguro = String(r.prefix(2_000)).replacingOccurrences(of: "\"", with: "”")
        return texto + ": «" + seguro + "»"
    }

    /// Herramientas deterministas. El resultado se somete después a la política de
    /// autonomía; esta función nunca ejecuta nada por sí sola.
    static func planificar(_ texto: String,
                           catalogo: ModoCatalogo = ModoCatalogoCache.actual(),
                           referencia: String? = nil,
                           ignorarInterruptor: Bool = false) -> ModoPreguntaPlan? {
        guard ignorarInterruptor || Config.agenteNucleoActivo() else { return nil }

        // Selección/Finder deben resolverse antes del parser de texto general.
        // “Resume la selección” actúa sobre lo seleccionado; no resume las dos
        // palabras literales “la selección”.
        if let r = RutinasAgenteStore.detectarSeleccionBreve(texto)
            ?? RutinasAgenteStore.detectarPrioritaria(texto) {
            let m = accion("rutina", nombre: "Rutina · \(r.rutina.nombre)", prompt: r.rutina.id)
            return ModoPlanificador.pregunta(
                para: ModoCadena(transforms: [],
                    acciones: [ModoAccionPlan(modo: m, destinatario: nil)],
                    contenido: r.contenido), fuente: .natural, confianza: 0.99)
        }

        // El clima es tiempo real: debe resolverse antes de cualquier IA para
        // que Codex/Hermes no contesten con datos inventados o desactualizados.
        if let clima = planificarClima(texto) { return clima }

        // Porcentaje/mute son órdenes locales inequívocas. Se resuelven antes
        // del planificador general y de cualquier cerebro de IA.
        if let volumen = planificarVolumen(texto) { return volumen }

        // Reutiliza primero el planificador maduro de Modos (correo, WhatsApp,
        // traducción, apps, búsquedas…). Evita un Agente dentro de otro Agente.
        if let p = ModoPlanificador.detectarNatural(texto, catalogo: catalogo),
           !p.cadena.transforms.contains(where: { $0.base == "agente" }),
           herramientasPermitidas(p.cadena) {
            return p
        }

        // “Mándaselo a Andrés por WhatsApp” carece deliberadamente de cuerpo.
        // Solo entonces completamos con la última respuesta y volvemos a pasar
        // por el MISMO planificador/confirmación; no ejecutamos nada aquí.
        let anterior = referencia ?? MemoriaAgente.ultimaRespuestaParaReferencia()
        if let ampliado = completarSeguimiento(texto, referencia: anterior),
           let p = ModoPlanificador.detectarNatural(ampliado, catalogo: catalogo),
           !p.cadena.transforms.contains(where: { $0.base == "agente" }),
           herramientasPermitidas(p.cadena) {
            return p
        }

        if let r = RutinasAgenteStore.detectar(texto) {
            let m = accion("rutina", nombre: "Rutina · \(r.rutina.nombre)", prompt: r.rutina.id)
            return ModoPlanificador.pregunta(
                para: ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: m, destinatario: nil)],
                                  contenido: r.contenido),
                fuente: .natural, confianza: 0.98)
        }

        // Modos-conexión del usuario ("pon mis actividades …"): sus frases de voz
        // los activan también DENTRO del asistente, con TOLERANCIA a cortesía y
        // conectores («por favor, pon EN mis actividades…»). Se pasa el MODO
        // REAL (con su conexión embebida); la política de riesgo decide.
        if Config.agenteHerramientaConexiones(),
           let det = ConexionesDeteccion.detectar(texto, modos: catalogo.modos,
                                                  nombreAsistente: Config.agenteNombre()) {
            return ModoPlanificador.pregunta(
                para: ModoCadena(transforms: [],
                    acciones: [ModoAccionPlan(modo: det.modo, destinatario: nil)],
                    contenido: texto),   // pedido COMPLETO: la IA necesita el verbo
                fuente: .natural, confianza: 0.97)
        }

        let normal = n(texto)
        let toks = Set(normal.split(separator: " ").map(String.init))

        if Config.agenteHerramientaCapturas(), let captura = planificarCaptura(texto) { return captura }

        if Config.agenteHerramientaMusica() {
            let verbos: Set<String> = ["pon", "ponme", "reproduce", "reproducir", "toca", "tocame",
                                        "escucha", "escuchar", "busca", "buscar", "buscame", "encuentra",
                                        "encuentrame", "muestra", "muestrame"]
            let objetos: Set<String> = ["musica", "cancion", "canciones", "tema", "playlist", "radio", "album"]
            if !toks.isDisjoint(with: verbos), !toks.isDisjoint(with: objetos) {
                var m = ModosStore.modo("musica")
                if let p = Musica.reconocerProveedor(en: normal) { m.musicaProveedor = p }
                m.musicaAccion = Musica.intencion(texto).rawValue
                let contenido = quitarPrefijo(texto, patrones: [
                    #"(?:pon(?:me)?|reproduce|toca(?:me)?|escucha|busca(?:me)?|encuentra(?:me)?|muestra(?:me)?)\s+(?:(?:una|la|alguna|cualquier|cualquiera|algo\s+de)\s+)?(?:m[uú]sica|canci[oó]n(?:es)?|tema|playlist|radio|[aá]lbum)?\s*(?:(?:cualquiera|cualquier)\s+)?(?:de\s+)?"#
                ])
                return ModoPlanificador.pregunta(
                    para: ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: m, destinatario: nil)],
                                      contenido: Musica.quitarNombreProveedor(contenido, id: m.musicaProveedor)),
                    fuente: .natural, confianza: 0.96)
            }
        }

        if Config.agenteHerramientaRecordatorios(),
           normal.hasPrefix("recuerdame") || normal.hasPrefix("crea un recordatorio")
                || normal.hasPrefix("crear recordatorio") || normal.hasPrefix("agrega un recordatorio") {
            let contenido = quitarPrefijo(texto, patrones: [
                #"recu[eé]rdame(?:\s+que)?"#, #"crea(?:r)?\s+(?:un\s+)?recordatorio"#,
                #"agrega(?:r)?\s+(?:un\s+)?recordatorio"#
            ])
            let m = accion("recordatorios", nombre: "Recordatorio de Mac")
            return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
                acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: contenido),
                fuente: .natural, confianza: 0.97)
        }

        if Config.agenteHerramientaCalendario() {
            let verbos: Set<String> = ["agenda", "agendame", "programa", "programame", "crea", "crear", "anade", "agrega"]
            let objetos: Set<String> = ["evento", "reunion", "cita", "calendario", "horario"]
            if !toks.isDisjoint(with: verbos), !toks.isDisjoint(with: objetos) {
                let contenido = quitarPrefijo(texto, patrones: [
                    #"(?:agenda(?:me)?|programa(?:me)?|crea(?:r)?|a[nñ]ade|agrega)"#
                ])
                let m = accion("calendario", nombre: "Evento de Calendario")
                return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
                    acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: contenido),
                    fuente: .natural, confianza: 0.95)
            }
        }

        if Config.agenteHerramientaArchivos(),
           (normal.hasPrefix("busca el archivo") || normal.hasPrefix("busca archivo")
            || normal.hasPrefix("encuentra el archivo") || normal.hasPrefix("encuentra archivo")
            || normal.hasPrefix("abre el archivo") || normal.hasPrefix("abre archivo")) {
            let contenido = quitarPrefijo(texto, patrones: [
                #"(?:busca|encuentra|abre)\s+(?:el\s+)?archivo"#
            ])
            let m = accion("archivo", nombre: "Buscar archivo en la Mac")
            return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
                acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: contenido),
                fuente: .natural, confianza: 0.96)
        }

        if Config.agenteHerramientaAtajos(),
           normal.hasPrefix("dile a siri") || normal.hasPrefix("pidele a siri")
                || normal.hasPrefix("usa siri") || normal.hasPrefix("ejecuta el atajo") {
            let contenido = quitarPrefijo(texto, patrones: [
                #"(?:dile|p[ií]dele)\s+a\s+siri(?:\s+que)?"#, #"usa\s+siri(?:\s+para)?"#,
                #"ejecuta\s+el\s+atajo"#
            ])
            let m = accion("atajo_apple", nombre: "Atajo Apple / Siri", prompt: Config.agenteAtajoApple())
            return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
                acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: contenido),
                fuente: .natural, confianza: 0.94)
        }
        return nil
    }

    /// Respuestas exactas que no justifican despertar una IA.
    static func respuestaLocal(_ texto: String) -> String? {
        guard Config.agenteNucleoActivo() else { return nil }
        let s = n(texto)
        if s.contains("que hora") || s == "hora" || s.contains("hora es") {
            let f = DateFormatter(); f.locale = Locale(identifier: "es_EC"); f.dateFormat = "h:mm a"
            return "Son las \(f.string(from: Date()))."
        }
        if s.contains("que dia") || s.contains("fecha de hoy") || s == "fecha" {
            let f = DateFormatter(); f.locale = Locale(identifier: "es_EC")
            f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy"
            return "Hoy es \(f.string(from: Date()))."
        }
        if s.contains("tareas") || s.contains("pendientes") || s.contains("que debo hacer") {
            let t = NotasStore.tareas().filter { !$0.hecho }
            if t.isEmpty { return "No tienes tareas pendientes en BtoDicta." }
            return "Tienes \(t.count) tareas pendientes: " + t.prefix(8).map(\.texto).joined(separator: "; ") + "."
        }
        if s.contains("mis notas") || s.contains("notas guardadas") {
            let t = NotasStore.notas()
            if t.isEmpty { return "No tienes notas guardadas en BtoDicta." }
            return "Tus notas más recientes son: " + t.prefix(6).map(\.texto).joined(separator: "; ") + "."
        }
        if s.contains("que te dije") || s.contains("que dijimos") || s.contains("lo anterior") {
            return MemoriaAgente.ultimoResumen() ?? "Todavía no tengo una conversación anterior guardada."
        }
        if s.contains("que puedes hacer") || s.contains("tus capacidades") {
            return "Puedo conversar, consultar el clima, tus tareas y notas, buscar y abrir archivos o aplicaciones, poner música, crear recordatorios y eventos, ejecutar tus rutinas y usar Hermes o un Atajo de Apple cuando los configures."
        }
        return nil
    }
}
