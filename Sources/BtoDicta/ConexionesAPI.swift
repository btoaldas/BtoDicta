import Foundation

// MARK: - Conexiones API definidas por el usuario (acción "conexion")
//
// Un modo con base "accion" y accion "conexion" lleva embebida una CONEXIÓN API
// declarada por el usuario: URL base, autenticación, endpoints con variables
// tipadas y (fase 2) instrucciones para la IA en el prompt del modo. Nada del
// dominio (p. ej. un sistema institucional concreto) vive en el código: todo es
// configuración del usuario, igual que un buscador propio o una IA personalizada.
//
// Principios:
//   - La IA NUNCA ejecuta HTTP ni ve credenciales: el runner Swift valida y llama.
//   - Fail-closed: solo https (o http en loopback), sin redirects fuera del host,
//     secretos en Keychain (SecretosKeychain), evidencia sin credenciales.
//   - Fase 1: ejecución directa de endpoints GET de lectura. Los flujos con
//     escritura/confirmación (proponer → confirmar) llegan en fases siguientes
//     y por eso el runner los rechaza hoy en vez de ejecutarlos a medias.

/// Variable declarada de un endpoint. La IA (fase 2) llenará estos valores; en
/// fase 1 solo {texto} (el dictado) se llena automáticamente.
struct VariableAPI: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String        // cómo se cita en plantillas: {nombre}
    var tipo: String          // "texto" | "numero" | "fecha" | "lista"
    var requerida: Bool
    var descripcion: String   // una línea que verá la IA
    var itemCampos: [VariableAPI]   // solo tipo "lista": esquema de cada ítem

    init(nombre: String = "", tipo: String = "texto", requerida: Bool = false,
         descripcion: String = "", itemCampos: [VariableAPI] = []) {
        id = UUID().uuidString
        self.nombre = nombre; self.tipo = tipo; self.requerida = requerida
        self.descripcion = descripcion; self.itemCampos = itemCampos
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? ""
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "texto"
        requerida = (try? c.decode(Bool.self, forKey: .requerida)) ?? false
        descripcion = (try? c.decode(String.self, forKey: .descripcion)) ?? ""
        itemCampos = (try? c.decode([VariableAPI].self, forKey: .itemCampos)) ?? []
    }
}

/// Endpoint declarado. `clave` es el nombre estable que la IA y las plantillas
/// usan; `ruta` y `query` admiten {variables}; `bodyPlantilla` es JSON con
/// {variables} y se sustituye de forma JSON-aware (nunca pegado de strings).
struct EndpointAPI: Codable, Identifiable, Equatable {
    var id: String
    var clave: String
    var metodo: String        // GET | POST | PUT | DELETE
    var ruta: String          // "/v1/clima" o "/{ciudad}" (variables solo en segmentos)
    var descripcion: String   // una línea que verá la IA
    var query: String         // "q={texto}&formato=json" (se codifica al sustituir)
    var bodyPlantilla: String // JSON con {variables}; vacío en GET
    var esEscritura: Bool     // true ⇒ jamás se ejecuta sin confirmación (fase 3)
    var variables: [VariableAPI]

    init(clave: String = "", metodo: String = "GET", ruta: String = "/",
         descripcion: String = "", query: String = "", bodyPlantilla: String = "",
         esEscritura: Bool = false, variables: [VariableAPI] = []) {
        id = UUID().uuidString
        self.clave = clave; self.metodo = metodo; self.ruta = ruta
        self.descripcion = descripcion; self.query = query
        self.bodyPlantilla = bodyPlantilla; self.esEscritura = esEscritura
        self.variables = variables
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        clave = (try? c.decode(String.self, forKey: .clave)) ?? ""
        metodo = (try? c.decode(String.self, forKey: .metodo)) ?? "GET"
        ruta = (try? c.decode(String.self, forKey: .ruta)) ?? "/"
        descripcion = (try? c.decode(String.self, forKey: .descripcion)) ?? ""
        query = (try? c.decode(String.self, forKey: .query)) ?? ""
        bodyPlantilla = (try? c.decode(String.self, forKey: .bodyPlantilla)) ?? ""
        esEscritura = (try? c.decode(Bool.self, forKey: .esEscritura)) ?? false
        variables = (try? c.decode([VariableAPI].self, forKey: .variables)) ?? []
    }

    /// Un método distinto de GET se trata como escritura aunque el usuario no
    /// haya marcado la casilla: techo de seguridad, no depende de su memoria.
    var efectivamenteEscritura: Bool { esEscritura || metodo.uppercased() != "GET" }
}

/// Autenticación de la conexión. El SECRETO jamás se guarda aquí (va a
/// SecretosKeychain, cuenta = id del modo); solo la forma de presentarlo.
struct AuthConexion: Codable, Equatable {
    var tipo: String          // "ninguna" | "apikey" | "login" (usuario+clave → token)
    var header: String        // ej. "Authorization" / "X-Api-Key"
    var prefijo: String       // ej. "Bearer " o "" (una API key pelada va sin prefijo)
    var usuario: String       // solo "login"; visible, nunca es el secreto
    var loginRuta: String     // solo "login": ej. "/login"
    var loginFormato: String  // "json" | "form" (x-www-form-urlencoded)
    var campoUsuario: String  // nombre del campo de usuario en el body de login
    var campoClave: String    // nombre del campo de la clave
    var campoToken: String    // DOT-PATH del token en la respuesta ("token" o "data.access_token")
    var ttlMinutos: Int       // vida del token en cache (re-login al vencer)

    init(tipo: String = "ninguna", header: String = "Authorization",
         prefijo: String = "Bearer ", usuario: String = "",
         loginRuta: String = "/login", loginFormato: String = "json",
         campoUsuario: String = "email", campoClave: String = "password",
         campoToken: String = "token", ttlMinutos: Int = 45) {
        self.tipo = tipo; self.header = header; self.prefijo = prefijo
        self.usuario = usuario; self.loginRuta = loginRuta
        self.loginFormato = loginFormato; self.campoUsuario = campoUsuario
        self.campoClave = campoClave; self.campoToken = campoToken
        self.ttlMinutos = ttlMinutos
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "ninguna"
        header = (try? c.decode(String.self, forKey: .header)) ?? "Authorization"
        prefijo = (try? c.decode(String.self, forKey: .prefijo)) ?? "Bearer "
        usuario = (try? c.decode(String.self, forKey: .usuario)) ?? ""
        loginRuta = (try? c.decode(String.self, forKey: .loginRuta)) ?? "/login"
        loginFormato = (try? c.decode(String.self, forKey: .loginFormato)) ?? "json"
        campoUsuario = (try? c.decode(String.self, forKey: .campoUsuario)) ?? "email"
        campoClave = (try? c.decode(String.self, forKey: .campoClave)) ?? "password"
        campoToken = (try? c.decode(String.self, forKey: .campoToken)) ?? "token"
        ttlMinutos = (try? c.decode(Int.self, forKey: .ttlMinutos)) ?? 45
    }
}

/// La conexión completa embebida en un Modo (campo opcional `conexion`).
struct ConexionAPI: Codable, Equatable {
    var baseURL: String
    var auth: AuthConexion
    var headers: [String: String]   // encabezados extra (Accept, X-Requested-With…)
    var endpoints: [EndpointAPI]
    var timeoutSegundos: Int
    var vozResumen: Bool            // leer un resumen del resultado por TTS
    var usarIA: Bool                // la IA arma el plan (endpoint+variables) desde lo dictado
    /// Clave del endpoint de 2ª fase del flujo proponer→confirmar. Si existe,
    /// el endpoint de escritura elegido actúa como PROPUESTA (dry-run del
    /// servidor), su respuesta se muestra para el visto bueno, y tras el OK se
    /// llama este endpoint (las claves de primer nivel de la respuesta de la
    /// propuesta quedan disponibles como {variables}, p. ej. {previewId}).
    var confirmEndpointId: String
    /// Clave del endpoint de PROPUESTA (1ª fase, dry-run del servidor). El flujo
    /// de dos fases SOLO se activa cuando la IA elige EXACTAMENTE este endpoint;
    /// cualquier otra escritura pasa por confirmación local ANTES de ejecutarse
    /// (nunca se dispara un POST/DELETE mutante sin tu visto bueno). Vacío ⇒ no
    /// hay dos fases; toda escritura se confirma localmente antes de enviar.
    var previewEndpointId: String
    /// PROMPT DE VUELTA: cómo contarte el resultado. Si no está vacío (y hay
    /// IA), la respuesta cruda de la API se redacta con estas instrucciones
    /// («dame ciudad, grados y un consejo de abrigo») antes de mostrarse y
    /// hablarse. Vacío = respuesta cruda tal cual.
    var promptRespuesta: String
    /// La IA EXPLICA la propuesta del visto bueno en lenguaje natural (sin
    /// inventar). Apagado = solo el formato legible determinista. Los datos
    /// exactos del servidor SIEMPRE se muestran debajo, con o sin explicación.
    var propuestaConIA: Bool
    /// Instrucciones extra para esa explicación («di cuántas actividades, con
    /// qué estado, minutos y con quién»). Vacío = explicación genérica.
    var promptPropuesta: String

    init(baseURL: String = "", auth: AuthConexion = AuthConexion(),
         headers: [String: String] = [:], endpoints: [EndpointAPI] = [],
         timeoutSegundos: Int = 15, vozResumen: Bool = false, usarIA: Bool = true,
         confirmEndpointId: String = "", previewEndpointId: String = "",
         promptRespuesta: String = "",
         propuestaConIA: Bool = false, promptPropuesta: String = "") {
        self.baseURL = baseURL; self.auth = auth; self.headers = headers
        self.endpoints = endpoints; self.timeoutSegundos = timeoutSegundos
        self.vozResumen = vozResumen; self.usarIA = usarIA
        self.confirmEndpointId = confirmEndpointId
        self.previewEndpointId = previewEndpointId
        self.promptRespuesta = promptRespuesta
        self.propuestaConIA = propuestaConIA
        self.promptPropuesta = promptPropuesta
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        auth = (try? c.decode(AuthConexion.self, forKey: .auth)) ?? AuthConexion()
        headers = (try? c.decode([String: String].self, forKey: .headers)) ?? [:]
        endpoints = (try? c.decode([EndpointAPI].self, forKey: .endpoints)) ?? []
        timeoutSegundos = (try? c.decode(Int.self, forKey: .timeoutSegundos)) ?? 15
        vozResumen = (try? c.decode(Bool.self, forKey: .vozResumen)) ?? false
        usarIA = (try? c.decode(Bool.self, forKey: .usarIA)) ?? true
        confirmEndpointId = (try? c.decode(String.self, forKey: .confirmEndpointId)) ?? ""
        previewEndpointId = (try? c.decode(String.self, forKey: .previewEndpointId)) ?? ""
        promptRespuesta = (try? c.decode(String.self, forKey: .promptRespuesta)) ?? ""
        propuestaConIA = (try? c.decode(Bool.self, forKey: .propuestaConIA)) ?? false
        promptPropuesta = (try? c.decode(String.self, forKey: .promptPropuesta)) ?? ""
    }

    var tieneEscritura: Bool { endpoints.contains { $0.efectivamenteEscritura } }
}

// MARK: - Motor puro (sin red): validación y sustitución. Todo testeable en QA.

enum ConexionesMotor {

    /// Criterio único de URL admisible: https con host, o http SOLO en loopback
    /// (mismo criterio que Acciones.plantillaURLSegura / RutinasAgenteRunner).
    static func urlSegura(_ s: String) -> Bool {
        guard let c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme?.lowercased() else { return false }
        if scheme == "https" { return c.host?.isEmpty == false }
        if scheme == "http" {
            return ["localhost", "127.0.0.1", "::1"].contains((c.host ?? "").lowercased())
        }
        return false
    }

    /// Percent-encode de un valor para ruta o query (criterio de la casa).
    static func codificar(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }

    /// Un valor que viaja en un SEGMENTO de ruta no puede cambiar de endpoint:
    /// sin "/", sin "..", sin vacío. (El percent-encode ya neutraliza el resto.)
    static func valorSeguroParaRuta(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && !t.contains("/") && !t.contains("..")
    }

    /// Extrae los nombres {var} presentes en una plantilla.
    static func variablesEnPlantilla(_ plantilla: String) -> Set<String> {
        var out = Set<String>()
        var resto = Substring(plantilla)
        while let a = resto.firstIndex(of: "{") {
            guard let b = resto[a...].firstIndex(of: "}") else { break }
            let nombre = String(resto[resto.index(after: a)..<b])
            if !nombre.isEmpty, !nombre.contains(" ") { out.insert(nombre) }
            resto = resto[resto.index(after: b)...]
        }
        return out
    }

    /// Valida los valores contra el esquema del endpoint. Devuelve la lista de
    /// problemas (vacía = válido). No conoce la red: puro.
    static func validarValores(endpoint: EndpointAPI, valores: [String: Any]) -> [String] {
        var errores: [String] = []
        for v in endpoint.variables where v.requerida && valores[v.nombre] == nil {
            errores.append("falta la variable requerida «\(v.nombre)»")
        }
        let declaradas = Set(endpoint.variables.map(\.nombre) + ["texto", "hoy"])
        for (k, valor) in valores {
            guard declaradas.contains(k) else {
                errores.append("variable no declarada «\(k)»"); continue
            }
            guard let esquema = endpoint.variables.first(where: { $0.nombre == k }) else { continue }
            switch esquema.tipo {
            case "numero":
                if !(valor is NSNumber) && Double("\(valor)") == nil {
                    errores.append("«\(k)» debe ser un número")
                }
            case "lista":
                if !(valor is [Any]) { errores.append("«\(k)» debe ser una lista") }
            default: break   // texto/fecha viajan como texto
            }
        }
        // Variables que la RUTA usa: su valor no puede alterar los segmentos.
        for nombre in variablesEnPlantilla(endpoint.ruta) {
            if let s = valores[nombre] as? String, !valorSeguroParaRuta(s) {
                errores.append("«\(nombre)» no es válida para la ruta (sin «/» ni «..», no vacía)")
            }
        }
        return errores
    }

    /// Construye la URL final: base + ruta con {vars} + query con {vars}, todo
    /// percent-encoded. nil si la URL resultante no es segura o no parsea.
    static func construirURL(base: String, endpoint: EndpointAPI,
                             valores: [String: Any]) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b = String(b.dropLast()) }
        guard urlSegura(b) else { return nil }
        var ruta = endpoint.ruta.trimmingCharacters(in: .whitespaces)
        if !ruta.isEmpty, !ruta.hasPrefix("/") { ruta = "/" + ruta }
        for nombre in variablesEnPlantilla(ruta) {
            guard let valor = valores[nombre].map({ "\($0)" }), valorSeguroParaRuta(valor) else { return nil }
            ruta = ruta.replacingOccurrences(of: "{\(nombre)}", with: codificar(valor))
        }
        var query = endpoint.query.trimmingCharacters(in: .whitespaces)
        for nombre in variablesEnPlantilla(query) {
            let valor = valores[nombre].map { "\($0)" } ?? ""
            query = query.replacingOccurrences(of: "{\(nombre)}", with: codificar(valor))
        }
        let s = b + ruta + (query.isEmpty ? "" : "?" + query)
        guard urlSegura(s), let url = URL(string: s) else { return nil }
        return url
    }

    /// Sustitución JSON-AWARE del body: la plantilla se parsea como JSON y los
    /// {placeholders} se reemplazan NODO a NODO — un string que es exactamente
    /// "{var}" recibe el valor con su TIPO (número, lista, texto); un string
    /// mixto "hola {var}" interpola como texto. Nunca se pega texto crudo en el
    /// JSON: comillas, tildes y saltos de línea dictados no pueden romperlo.
    static func sustituirBody(_ plantilla: String, valores: [String: Any]) -> Data? {
        let t = plantilla.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard let data = t.data(using: .utf8),
              let raiz = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil   // la plantilla misma no es JSON válido: error de config
        }
        func sustituir(_ nodo: Any) -> Any {
            if let s = nodo as? String {
                let nombres = variablesEnPlantilla(s)
                if nombres.count == 1, let n = nombres.first, s == "{\(n)}" {
                    return valores[n] ?? NSNull()   // valor TIPADO tal cual
                }
                var out = s
                for n in nombres {
                    out = out.replacingOccurrences(of: "{\(n)}", with: valores[n].map { "\($0)" } ?? "")
                }
                return out
            }
            if let a = nodo as? [Any] { return a.map(sustituir) }
            if let d = nodo as? [String: Any] { return d.mapValues(sustituir) }
            return nodo
        }
        let final = sustituir(raiz)
        return try? JSONSerialization.data(withJSONObject: final, options: [.sortedKeys])
    }

    /// Convierte un JSON en líneas LEGIBLES para el modal del visto bueno:
    /// «clave: valor» con sangría, arrays numerados, claves técnicas de texto
    /// gigante (tokens/JWT) omitidas. Determinista a propósito: la propuesta
    /// que se confirma debe mostrar datos EXACTOS, jamás una redacción de IA.
    static func lineasLegibles(_ json: Any, sangria: String = "", limite: Int = 80) -> [String] {
        var out: [String] = []
        func agregar(_ linea: String) { if out.count < limite { out.append(linea) } }
        func valorCorto(_ v: Any) -> String? {
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.count > 160 ? nil : t   // un JWT/token no aporta al visto bueno
            }
            if let b = v as? Bool { return b ? "sí" : "no" }
            if let n = v as? NSNumber { return "\(n)" }
            if v is NSNull { return nil }
            return nil
        }
        func caminar(_ nodo: Any, _ sangria: String) {
            if let d = nodo as? [String: Any] {
                for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                    if let plano = valorCorto(v) {
                        if !plano.isEmpty { agregar("\(sangria)\(k): \(plano)") }
                    } else if v is [String: Any] || v is [Any] {
                        agregar("\(sangria)\(k):")
                        caminar(v, sangria + "   ")
                    }
                }
            } else if let a = nodo as? [Any] {
                for (i, v) in a.enumerated() {
                    if let plano = valorCorto(v) { agregar("\(sangria)\(i + 1). \(plano)") }
                    else {
                        agregar("\(sangria)\(i + 1).")
                        caminar(v, sangria + "   ")
                    }
                }
            }
        }
        caminar(json, sangria)
        if out.count >= limite { out.append("…") }
        return out.isEmpty ? ["(respuesta sin datos legibles)"] : out
    }

    /// Versión hablable de una respuesta: sin emojis ni símbolos gráficos (el
    /// TTS los deletrea o tropieza), espacios colapsados, tope de 400 chars.
    static func textoParaVoz(_ texto: String) -> String {
        // Rangos gráficos completos, no solo isEmoji: la flecha ↓ (U+2193) no
        // es "emoji" para Swift, y el selector VS16 (U+FE0F) queda huérfano si
        // solo se quita el símbolo base.
        let graficos: [ClosedRange<UInt32>] = [
            0x2190...0x21FF,     // flechas
            0x2300...0x27BF,     // técnicos, misceláneos, dingbats
            0x2B00...0x2BFF,     // flechas y símbolos suplementarios
            0x1F000...0x1FAFF,   // emojis y pictogramas
            0xFE0E...0xFE0F,     // selectores de variación texto/emoji
            0x200D...0x200D,     // zero-width joiner
        ]
        let sinEmoji = texto.unicodeScalars.filter { s in
            !graficos.contains { $0.contains(s.value) }
        }
        var t = String(String.UnicodeScalarView(sinEmoji))
        // Símbolos → palabras en español: un TTS multilingüe ante "+16°C" lee
        // signos sueltos y hasta cambia de idioma. "16 grados" lo ancla.
        let reemplazos: [(String, String)] = [
            (#"\+(?=\d)"#, ""),                    // +16 → 16
            (#"(?<=\s)-(?=\d)"#, "menos "),        // -3 → menos 3 (no el guion de rangos)
            (#"°\s*C\b"#, " grados"),
            (#"°\s*F\b"#, " grados fahrenheit"),
            (#"°(?=\s|$)"#, " grados"),
            (#"%"#, " por ciento"),
            (#"km/h\b"#, " kilómetros por hora"),   // sin \b inicial: "5km/h" viene pegado
            (#"(?<=\d)\s*m/s\b"#, " metros por segundo"),
            (#"(?<=[\p{L}\)])\s*:"#, ","),         // "Quito:" → "Quito," (no toca horas 14:30)
        ]
        for (patron, valor) in reemplazos {
            t = t.replacingOccurrences(of: patron, with: valor, options: .regularExpression)
        }
        let limpio = t
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(limpio.prefix(400))
    }

    /// Enmascara secretos en un texto destinado a logs/evidencia. Se aplica a
    /// TODO lo que salga del runner; un token jamás debe llegar a AgenteLog.
    static func enmascarar(_ texto: String, secretos: [String]) -> String {
        var out = texto
        for s in secretos where s.count >= 4 {
            out = out.replacingOccurrences(of: s, with: "•••")
        }
        return out
    }

    /// Riesgo para la política del agente: leer es reversible; cualquier
    /// endpoint de escritura vuelve TODA la conexión externa (confirmación).
    static func riesgo(_ conexion: ConexionAPI?) -> RiesgoAgente {
        guard let c = conexion else { return .externo }   // sin declarar = prudencia
        return c.tieneEscritura ? .externo : .reversible
    }
}

// MARK: - Detección tolerante de modos-conexión en el pedido al asistente
//
// «Oye Jarvis, por favor, pon en mis actividades que…» debe activar el modo
// aunque lleve cortesía inicial y conectores intercalados. Determinista y puro
// (QA-able): tokens de la frase EN ORDEN al inicio del pedido, tolerando hasta
// dos palabras intercaladas; el resto del dictado es el contenido.

enum ConexionesDeteccion {
    private static let cortesia: Set<String> = [
        "por", "favor", "porfavor", "porfa", "oye", "me", "puedes", "podrias",
        "ayudame", "necesito", "quiero", "porfis", "debes", "deberias", "hay",
        "que", "vamos", "a",
    ]

    /// «pongo»~«pon», «registro»~«registra», «actividad»~«actividades»: las
    /// conjugaciones y mal-escuchas del STT no deben romper el match. Igualdad
    /// exacta, o prefijo compartido con raíz de al menos 3 letras.
    private static func coincide(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 3, b.count >= 3 else { return false }
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    static func detectar(_ texto: String, modos: [Modo],
                         nombreAsistente: String = "") -> (modo: Modo, contenido: String)? {
        // Normalizar POR TOKEN mantiene alineación 1:1 con los originales, para
        // que el índice consumido recorte el contenido sin perder palabras
        // (normalizar el texto entero podía cambiar el conteo de tokens).
        let originales = texto.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var toks = originales.map { PerfilAgente.normalizar($0) }
        var saltados = 0
        let nombreAsist = PerfilAgente.normalizar(nombreAsistente)
        while let primero = toks.first, cortesia.contains(primero) || primero == nombreAsist {
            toks.removeFirst(); saltados += 1
        }
        guard !toks.isEmpty else { return nil }
        let candidatos = modos.filter { $0.accion == "conexion" && $0.conexion != nil && $0.base == "accion" }
        var mejor: (modo: Modo, consumidos: Int, puntaje: Int)?
        for m in candidatos {
            for frase in FrasesConfigurables.parsear(m.palabraVoz) {
                let ft = PerfilAgente.normalizar(frase).split(separator: " ").map(String.init)
                    .filter { $0 != "modo" }   // «modo actividades» sirve también como «actividades»
                guard !ft.isEmpty else { continue }
                // Tokens de la frase EN ORDEN dentro de una ventana con hasta 2 extras.
                // Hasta 3 palabras iniciales cualesquiera antes del primer token
                // de la frase («debes INGRESAR EN mis actividades…»): la frase
                // completa igual debe aparecer en orden — sin robar narraciones.
                var i = 0, j = 0, extras = 0, arranque = 0
                while i < toks.count, j < ft.count, extras <= 2 {
                    if coincide(toks[i], ft[j]) { j += 1 }
                    else if j == 0, arranque < 3 { arranque += 1 }
                    else if j > 0 { extras += 1 }
                    else { break }
                    i += 1
                }
                if j == ft.count {
                    if mejor == nil || ft.count > mejor!.puntaje {
                        mejor = (m, i + saltados, ft.count)
                    }
                }
            }
        }
        guard let mejor else {
            // Pedido cortito que ES el nombre del modo («actividades» a secas):
            // se activa sin contenido y la IA repreguntará lo que falte.
            if toks.count <= 3 {
                for m in candidatos {
                    let nombreToks = PerfilAgente.normalizar(m.nombre)
                        .split(separator: " ").map(String.init)
                    if let primeroNombre = nombreToks.first, toks.contains(primeroNombre) {
                        return (m, "")
                    }
                }
            }
            return nil
        }
        let contenido = originales.dropFirst(min(mejor.consumidos, originales.count))
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
        return (mejor.modo, contenido)
    }
}

// MARK: - Delegate de red: sin redirects fuera del host declarado ni https→http

final class ConexionRedDelegate: NSObject, URLSessionTaskDelegate {
    private let hostPermitido: String
    private let esquemaOriginal: String
    init(url: URL) {
        hostPermitido = url.host?.lowercased() ?? ""
        esquemaOriginal = url.scheme?.lowercased() ?? "https"
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let nuevoHost = request.url?.host?.lowercased() ?? ""
        let nuevoEsquema = request.url?.scheme?.lowercased() ?? ""
        // Cross-host se rechaza siempre; https puede degradar a http jamás.
        let degrada = esquemaOriginal == "https" && nuevoEsquema != "https"
        completionHandler(nuevoHost == hostPermitido && !degrada ? request : nil)
    }
}

// MARK: - Runner: lectura directa + escritura vía proponer→confirmar (fase 3)

/// El runner pide el visto bueno a través de este closure (el AppDelegate pone
/// el modal fn/X; el QA pone una respuesta programática). `responder` DEBE
/// llamarse exactamente una vez; sin confirmador no hay escritura posible.
typealias ConfirmadorConexion = (_ titulo: String, _ detalles: [String],
                                 _ responder: @escaping (Bool) -> Void) -> Void

enum ConexionesRunner {

    /// Elige el endpoint a ejecutar sin IA: si el dictado empieza con la clave
    /// de un endpoint la usa (también de escritura — la confirmación protege);
    /// si no, el primer GET de lectura. El endpoint de 2ª fase nunca se elige.
    static func endpointPara(_ conexion: ConexionAPI, texto: String) -> EndpointAPI? {
        let elegibles = conexion.endpoints.filter {
            conexion.confirmEndpointId.isEmpty || $0.clave != conexion.confirmEndpointId
        }
        let n = texto.lowercased().trimmingCharacters(in: .whitespaces)
        if let porClave = elegibles.first(where: { !$0.clave.isEmpty && n.hasPrefix($0.clave.lowercased()) }) {
            return porClave
        }
        return elegibles.first { !$0.efectivamenteEscritura }
    }

    /// Ejecuta la conexión de un modo para el texto dictado.
    static func ejecutar(modo: Modo, texto: String, ignorarInterruptor: Bool = false,
                         confirmar: ConfirmadorConexion? = nil,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard ignorarInterruptor || Config.agenteHerramientaConexiones() else {
            completion(.init(ok: false, mensaje: "Las conexiones API están apagadas en Ajustes → Asistente.")); return
        }
        guard let conexion = modo.conexion else {
            completion(.init(ok: false, mensaje: "El modo «\(modo.nombre)» no tiene una conexión API configurada.")); return
        }
        guard ConexionesMotor.urlSegura(conexion.baseURL) else {
            completion(.init(ok: false, mensaje: "La URL base no es segura. Usa HTTPS, o HTTP únicamente para localhost.")); return
        }
        guard !conexion.endpoints.isEmpty else {
            completion(.init(ok: false, mensaje: "La conexión «\(modo.nombre)» no tiene endpoints configurados.")); return
        }
        // Con IA: ella arma el plan (endpoint + variables) desde el dictado.
        if conexion.usarIA, ConexionesIA.iaDisponible(modo) != nil {
            ConexionesIA.resolver(modo: modo, conexion: conexion, texto: texto) { r in
                switch r {
                case .plan(let plan):
                    ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: plan.endpoint,
                                     valores: plan.valores, resumen: plan.resumen,
                                     confirmar: confirmar, completion: completion)
                case .faltan(let nombres):
                    let lista = nombres.joined(separator: ", ")
                    completion(.init(ok: false,
                        mensaje: "Me falta saber: \(lista). Dímelo de nuevo incluyendo ese dato.",
                        evidencia: ["faltan": lista]))
                case .invalido(let motivo):
                    // Fallback determinista SOLO si es viable sin inventar valores.
                    if let ep = endpointPara(conexion, texto: texto),
                       ep.variables.allSatisfy({ !$0.requerida }) {
                        var valores: [String: Any] = [:]
                        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { valores["texto"] = t }
                        ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: ep,
                                         valores: valores, resumen: "",
                                         confirmar: confirmar, completion: completion)
                    } else {
                        completion(.init(ok: false, mensaje: "No pude armar el plan: \(motivo)."))
                    }
                }
            }
            return
        }
        // Camino determinista: clave dictada o primer GET, solo {texto}.
        guard let endpoint = endpointPara(conexion, texto: texto) else {
            completion(.init(ok: false, mensaje: conexion.tieneEscritura
                ? "Esta conexión solo tiene endpoints de escritura y sin IA no puedo armar su plan."
                : "La conexión «\(modo.nombre)» no tiene endpoints de lectura.")); return
        }
        var valores: [String: Any] = [:]
        let contenido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contenido.isEmpty { valores["texto"] = contenido }
        ejecutarEndpoint(modo: modo, conexion: conexion, endpoint: endpoint,
                         valores: valores, resumen: "", confirmar: confirmar,
                         completion: completion)
    }

    /// Tramo común. La validación contra el esquema se repite SIEMPRE — nadie
    /// salta el validador. La escritura entra al flujo proponer→confirmar.
    private static func ejecutarEndpoint(modo: Modo, conexion: ConexionAPI,
                                         endpoint: EndpointAPI, valores: [String: Any],
                                         resumen: String,
                                         confirmar: ConfirmadorConexion?,
                                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        var valores = valores
        if valores["hoy"] == nil {   // {hoy} SIEMPRE disponible (la IA no sabe la fecha)
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"; valores["hoy"] = f.string(from: Date())
        }
        let problemas = ConexionesMotor.validarValores(endpoint: endpoint, valores: valores)
        guard problemas.isEmpty else {
            completion(.init(ok: false, mensaje: "No puedo llamar «\(endpoint.clave)»: " + problemas.joined(separator: "; ") + ".")); return
        }
        let pedido = (valores["texto"] as? String) ?? ""
        guard endpoint.efectivamenteEscritura else {
            hacerLlamada(modo: modo, conexion: conexion, endpoint: endpoint,
                         valores: valores, resumen: resumen) { r in
                entregarRedactado(r, modo: modo, conexion: conexion, pedido: pedido,
                                  completion: completion)
            }
            return
        }
        // ESCRITURA: sin confirmador no hay cómo pedir el visto bueno → no se ejecuta.
        guard let confirmar else {
            completion(.init(ok: false, mensaje: "«\(endpoint.clave)» es de escritura y este camino no puede pedir tu confirmación.")); return
        }
        let confirmEp = conexion.endpoints.first {
            !conexion.confirmEndpointId.isEmpty && $0.clave == conexion.confirmEndpointId
        }
        let esPropuestaDesignada = !conexion.previewEndpointId.isEmpty
            && endpoint.clave == conexion.previewEndpointId
        if let confirmEp, confirmEp.clave != endpoint.clave, esPropuestaDesignada {
            // Dos fases: SOLO si el endpoint elegido es el de propuesta
            // designado (dry-run del servidor). Su respuesta se muestra para el
            // OK; tras el OK, la confirmación va al 2º endpoint con las claves de
            // primer nivel de esa respuesta como {variables} (p. ej. {previewId}).
            flujoDosFases(modo: modo, conexion: conexion, propuesta: endpoint,
                          confirmacion: confirmEp, valores: valores, resumen: resumen,
                          confirmar: confirmar, intento: 1, completion: completion)
        } else {
            // Cualquier OTRA escritura (incluida una que la IA eligiera y NO sea
            // la propuesta designada): confirmación LOCAL del request ANTES de
            // ejecutar. Jamás se dispara un POST/DELETE mutante sin visto bueno.
            // Una fase: resumen LOCAL del request → OK → ejecutar.
            var detalles = ["\(endpoint.metodo) \(endpoint.clave) — \(endpoint.descripcion)"]
            let legibles = valores.filter { $0.key != "texto" }
                .map { "\($0.key): \(String(describing: $0.value).prefix(120))" }.sorted()
            detalles.append(contentsOf: legibles)
            confirmar(resumen.isEmpty ? "¿Enviar «\(endpoint.clave)» de \(modo.nombre)?" : "¿\(resumen)?",
                      detalles) { acepta in
                guard acepta else {
                    ConexionesIA.registrarRechazo(modoId: modo.id, pedido: pedido,
                                                  tabla: detalles)
                    completion(.init(ok: false, mensaje: "Cancelado. No envié nada. Si quieres ajustarlo, dime solo el cambio.",
                                     evidencia: ["cancelado": "usuario"])); return
                }
                hacerLlamada(modo: modo, conexion: conexion, endpoint: endpoint,
                             valores: valores, resumen: resumen) { r in
                    if r.ok { ConexionesIA.limpiarPendiente(modoId: modo.id) }
                    entregarRedactado(r, modo: modo, conexion: conexion, pedido: pedido,
                                      completion: completion)
                }
            }
        }
    }

    private static func flujoDosFases(modo: Modo, conexion: ConexionAPI,
                                      propuesta: EndpointAPI, confirmacion: EndpointAPI,
                                      valores: [String: Any], resumen: String,
                                      confirmar: @escaping ConfirmadorConexion, intento: Int,
                                      completion: @escaping (ResultadoHerramientaApple) -> Void) {
        var cuerpoPropuesta = ""
        hacerLlamada(modo: modo, conexion: conexion, endpoint: propuesta,
                     valores: valores, resumen: resumen,
                     cuerpoCompleto: { cuerpoPropuesta = $0 }) { rPropuesta in
            guard rPropuesta.ok else { completion(rPropuesta); return }
            // La respuesta del servidor ES la propuesta que se confirma. El
            // merge usa el cuerpo COMPLETO (un previewId JWT no cabe en el
            // recorte de logs) y el modal la muestra en líneas LEGIBLES.
            var valoresConfirm = valores
            var detallesLegibles = [String((rPropuesta.evidencia["salida"] ?? rPropuesta.mensaje).prefix(900))]
            if let data = cuerpoPropuesta.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in json where !(v is [String: Any]) && !(v is [Any]) {
                    valoresConfirm[k] = v
                }
                detallesLegibles = ConexionesMotor.lineasLegibles(json)
            }
            let tituloBase = "¿Confirmas \(resumen.isEmpty ? "el envío de \(modo.nombre)" : resumen.lowercased())?"
            // Explicación por IA (opcional): el TÍTULO (que también se habla)
            // lleva la explicación; los datos exactos SIEMPRE quedan debajo.
            ConexionesIA.explicarPropuesta(modo: modo, conexion: conexion,
                                           pedido: (valores["texto"] as? String) ?? "",
                                           cuerpo: cuerpoPropuesta) { explicacion in
                let titulo = explicacion.map { "\($0) ¿Confirmas?" } ?? tituloBase
                confirmar(titulo, detallesLegibles) { acepta in
                guard acepta else {
                    // El rechazo queda en memoria unos minutos: si el usuario
                    // vuelve a dictar a este modo pidiendo un cambio, la IA
                    // corrige la propuesta en vez de empezar de cero.
                    ConexionesIA.registrarRechazo(modoId: modo.id,
                                                  pedido: (valores["texto"] as? String) ?? "",
                                                  tabla: detallesLegibles)
                    completion(.init(ok: false, mensaje: "Cancelado. La propuesta no se confirmó. Si quieres ajustarla, dime solo el cambio.",
                                     evidencia: ["cancelado": "usuario"])); return
                }
                hacerLlamada(modo: modo, conexion: conexion, endpoint: confirmacion,
                             valores: valoresConfirm, resumen: resumen) { rConfirm in
                    // Propuesta vencida (el servidor la caducó entre el OK y el
                    // envío): se rehace UNA vez y se vuelve a pedir el OK.
                    let estado = Int(rConfirm.evidencia["estado"] ?? "") ?? 0
                    if !rConfirm.ok, (400..<500).contains(estado), intento == 1 {
                        flujoDosFases(modo: modo, conexion: conexion, propuesta: propuesta,
                                      confirmacion: confirmacion, valores: valores,
                                      resumen: resumen, confirmar: confirmar,
                                      intento: 2, completion: completion)
                    } else {
                        if rConfirm.ok { ConexionesIA.limpiarPendiente(modoId: modo.id) }
                        entregarRedactado(rConfirm, modo: modo, conexion: conexion,
                                          pedido: (valores["texto"] as? String) ?? "",
                                          completion: completion)
                    }
                }
                }
            }
        }
    }

    /// «Probar conexión» del editor: auth (si es login, hace login real) y el
    /// primer GET de lectura. JAMÁS toca un endpoint de escritura.
    static func probar(_ conexion: ConexionAPI, modoId: String,
                       _ done: @escaping (Bool, String) -> Void) {
        guard ConexionesMotor.urlSegura(conexion.baseURL) else {
            done(false, "URL base no segura (usa https, o http solo en localhost)"); return
        }
        func probarLectura() {
            let endpoint = conexion.endpoints.first { !$0.efectivamenteEscritura }
                ?? EndpointAPI(clave: "base", metodo: "GET", ruta: "/")
            var valores: [String: Any] = [:]
            for v in endpoint.variables { valores[v.nombre] = v.nombre }
            valores["texto"] = "prueba"
            let modoFicticio = Modo(id: modoId, nombre: "Prueba", icono: "bolt",
                                    base: "accion", accion: "conexion", conexion: conexion)
            hacerLlamada(modo: modoFicticio, conexion: conexion, endpoint: endpoint,
                         valores: valores, resumen: "") { r in
                DispatchQueue.main.async { done(r.ok, r.mensaje) }
            }
        }
        if conexion.auth.tipo == "login" {
            ConexionesAuth.obtenerToken(conexion: conexion, modoId: modoId, forzar: true) { token, error in
                DispatchQueue.main.async {
                    if token != nil { done(true, "login correcto — token recibido") }
                    else { done(false, error ?? "login falló") }
                }
            }
        } else {
            probarLectura()
        }
    }

    /// Entrega el resultado FINAL: si la conexión tiene prompt de vuelta y hay
    /// IA, la respuesta cruda se redacta («ciudad, grados y consejo»); ante
    /// cualquier fallo de la IA se entrega la cruda — jamás se pierde un dato.
    /// Las propuestas intermedias del flujo de dos fases NO pasan por aquí.
    private static func entregarRedactado(_ r: ResultadoHerramientaApple, modo: Modo,
                                          conexion: ConexionAPI, pedido: String,
                                          completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard r.ok,
              !conexion.promptRespuesta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(r); return
        }
        // La redacción recibe QUÉ operación fue: una consulta jamás puede
        // narrarse como «quedó registrado» (pasó: describió una lectura del
        // día como si acabara de publicar).
        let clave = r.evidencia["endpoint"] ?? ""
        let ep = conexion.endpoints.first { $0.clave == clave }
        let operacion = ep.map { "\($0.clave) (\($0.efectivamenteEscritura ? "escritura" : "consulta de solo lectura")): \($0.descripcion)" } ?? ""
        ConexionesIA.redactarRespuesta(modo: modo, conexion: conexion, pedido: pedido,
                                       respuestaAPI: r.evidencia["salida"] ?? r.mensaje,
                                       operacion: operacion) { redactado in
            guard let redactado else {
                // La redacción nunca bloquea, pero un JSON crudo tampoco se
                // muestra ni se habla: cae al formato legible determinista.
                let crudo = r.evidencia["salida"] ?? r.mensaje
                if let data = crudo.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    let legible = ConexionesMotor.lineasLegibles(json).joined(separator: "\n")
                    var evidencia = r.evidencia
                    evidencia["salida"] = legible
                    completion(.init(ok: true, mensaje: legible, evidencia: evidencia))
                } else {
                    completion(r)
                }
                return
            }
            var evidencia = r.evidencia
            evidencia["redactado"] = "true"
            evidencia["salida_cruda"] = evidencia["salida"] ?? ""
            evidencia["salida"] = redactado   // lo consolidable (rutinas) es el texto útil
            completion(.init(ok: true, mensaje: redactado, evidencia: evidencia))
        }
    }

    // MARK: HTTP

    /// Resuelve el valor del header de auth: API key del Llavero, o token de
    /// login (cache/login). `nil, nil` = conexión sin autenticación.
    private static func credencial(conexion: ConexionAPI, modoId: String, forzar: Bool,
                                   _ done: @escaping (_ valor: String?, _ error: String?) -> Void) {
        switch conexion.auth.tipo {
        case "apikey":
            guard let s = SecretosKeychain.leer(cuenta: modoId), !s.isEmpty else {
                done(nil, "no hay API key guardada para esta conexión"); return
            }
            done(conexion.auth.prefijo + s, nil)
        case "login":
            ConexionesAuth.obtenerToken(conexion: conexion, modoId: modoId, forzar: forzar) { token, error in
                done(token.map { conexion.auth.prefijo + $0 }, error)
            }
        default:
            done(nil, nil)
        }
    }

    /// La llamada HTTP con todo: método, query/ruta/body sustituidos, auth,
    /// anti-redirect, timeout, evidencia sin secretos y UN reintento con
    /// re-login si el servidor devuelve 401/403 a una conexión con login.
    private static func hacerLlamada(modo: Modo, conexion: ConexionAPI, endpoint: EndpointAPI,
                                     valores: [String: Any], resumen: String,
                                     reintentoAuth: Bool = false,
                                     cuerpoCompleto: ((String) -> Void)? = nil,
                                     completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard let url = ConexionesMotor.construirURL(base: conexion.baseURL,
                                                     endpoint: endpoint, valores: valores) else {
            completion(.init(ok: false, mensaje: "No pude armar una URL segura para «\(endpoint.clave)». Revisa la ruta y las variables.")); return
        }
        let metodo = endpoint.metodo.uppercased()
        var body: Data?
        if metodo != "GET", !endpoint.bodyPlantilla.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let b = ConexionesMotor.sustituirBody(endpoint.bodyPlantilla, valores: valores) else {
                completion(.init(ok: false, mensaje: "La plantilla de body de «\(endpoint.clave)» no es JSON válido.")); return
            }
            body = b
        }
        credencial(conexion: conexion, modoId: modo.id, forzar: reintentoAuth) { credencialValor, credencialError in
            if let credencialError {
                DispatchQueue.main.async {
                    completion(.init(ok: false, mensaje: "Autenticación: \(credencialError)."))
                }
                return
            }
            var req = URLRequest(url: url)
            req.httpMethod = metodo
            req.timeoutInterval = TimeInterval(min(120, max(3, conexion.timeoutSegundos)))
            // Los encabezados del usuario van PRIMERO; los reservados (auth,
            // Content-Type, Connection) después, para que estos siempre ganen y
            // el usuario no pueda pisar la credencial ni el tipo de contenido.
            for (h, v) in conexion.headers { req.setValue(v, forHTTPHeaderField: h) }
            req.setValue("close", forHTTPHeaderField: "Connection")
            var secretos: [String] = []
            if let credencialValor {
                let h = conexion.auth.header.isEmpty ? "Authorization" : conexion.auth.header
                req.setValue(credencialValor, forHTTPHeaderField: h)
                // Enmascarar el header COMPLETO y también el secreto pelado: si
                // el servidor devuelve el token sin el prefijo «Bearer », igual
                // no debe aparecer en evidencia ni llegar a la IA de vuelta.
                secretos.append(credencialValor.trimmingCharacters(in: .whitespaces))
                let pelado = credencialValor.hasPrefix(conexion.auth.prefijo) && !conexion.auth.prefijo.isEmpty
                    ? String(credencialValor.dropFirst(conexion.auth.prefijo.count))
                    : credencialValor
                let peladoT = pelado.trimmingCharacters(in: .whitespaces)
                if peladoT.count >= 4 { secretos.append(peladoT) }
            }
            if let body {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
            }
            let delegado = ConexionRedDelegate(url: url)
            let sesion = URLSession(configuration: .ephemeral, delegate: delegado, delegateQueue: nil)
            let inicio = Date()
            let tarea = sesion.dataTask(with: req) { data, resp, error in
                defer { sesion.finishTasksAndInvalidate() }
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                if let error {
                    let msg = ConexionesMotor.enmascarar(error.localizedDescription, secretos: secretos)
                    DispatchQueue.main.async {
                        completion(.init(ok: false, mensaje: "La conexión falló: \(msg)",
                                         evidencia: ["endpoint": endpoint.clave, "ms": "\(ms)"]))
                    }
                    return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                // Token vencido en el servidor antes que en el cache local:
                // re-login UNA vez y repetir la misma llamada.
                if [401, 403].contains(code), conexion.auth.tipo == "login", !reintentoAuth {
                    ConexionesAuth.invalidar(modo.id)
                    hacerLlamada(modo: modo, conexion: conexion, endpoint: endpoint,
                                 valores: valores, resumen: resumen, reintentoAuth: true,
                                 cuerpoCompleto: cuerpoCompleto, completion: completion)
                    return
                }
                let cuerpoCrudo = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                // El cuerpo SIN truncar viaja solo a quien lo pidió (el merge de
                // dos fases necesita el previewId completo — un JWT puede medir
                // más de 2000 chars); a logs y evidencia va siempre truncado.
                if (200..<300).contains(code), let cuerpoCompleto {
                    cuerpoCompleto(ConexionesMotor.enmascarar(cuerpoCrudo, secretos: secretos))
                }
                let cuerpo = ConexionesMotor.enmascarar(String(cuerpoCrudo.prefix(2_000)), secretos: secretos)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                AgenteLog.registrar("conexion_api", [
                    "modo": modo.id, "endpoint": endpoint.clave, "metodo": metodo,
                    "host": url.host ?? "", "estado": code, "ms": ms,
                ])   // deliberadamente SIN url completa ni headers: cero secretos en logs
                DispatchQueue.main.async {
                    guard (200..<300).contains(code) else {
                        completion(.init(ok: false,
                            mensaje: "El servidor respondió HTTP \(code)." + (cuerpo.isEmpty ? "" : " \(String(cuerpo.prefix(200)))"),
                            evidencia: ["endpoint": endpoint.clave, "estado": "\(code)", "ms": "\(ms)"]))
                        return
                    }
                    var evidencia = ["endpoint": endpoint.clave, "estado": "\(code)", "ms": "\(ms)",
                                     "salida": cuerpo]
                    if !resumen.isEmpty { evidencia["plan"] = resumen }
                    completion(.init(ok: true,
                        mensaje: cuerpo.isEmpty ? "«\(endpoint.clave)» respondió sin contenido (HTTP \(code))." : cuerpo,
                        evidencia: evidencia))
                }
            }
            tarea.resume()
        }
    }
}
