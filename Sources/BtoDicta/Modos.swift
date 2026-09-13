import Foundation
import AppKit   // NSWorkspace / NSAppleScript para los triggers por contexto

// MARK: - Modos: qué hacer con lo dictado (pulir / correo / oficio / traducir…)
//
// Un MODO es una receta con nombre para transformar el texto dictado DESPUÉS de
// transcribir. Cada uno lleva su propia IA + modelo + prompt. El modo activo se
// elige en caliente (notch / menú), igual que el proveedor. "Dictado" es el
// default y hace lo de siempre (solo pulir). "Traducir" traduce.
//
// base:
//   "pulir"     — limpia/transforma el texto según `prompt` (Dictado = prompt vacío = limpieza estándar).
//   "traducir"  — traduce al `idiomaDestino`.
//   "responder"  — trata el dictado como una instrucción y redacta la respuesta.
//   "musica"     — busca/reproduce con una cascada de servicios de música.
//   "aplicacion" — abre una app instalada y coloca allí el texto, sin enviarlo.

struct Modo: Codable, Identifiable {
    var id: String
    var nombre: String
    var icono: String            // SF Symbol
    var base: String             // "pulir" | "traducir" | "responder"
    var prompt: String           // instrucción del modo (vacío en Dictado)
    var proveedorId: String      // "" = usa el proveedor global de pulido
    var modelo: String           // "" = default del proveedor elegido
    var idiomaDestino: String    // solo "traducir"
    var esFijo: Bool             // base (no se borra) vs propio del usuario
    var palabraVoz: String       // frase al inicio del dictado que activa este modo
    var apps: [String]           // apps (nombre o bundle id) que activan este modo
    var sitios: [String]         // dominios/URLs que activan este modo (en navegador)
    var buscador: String         // solo base "buscar": google/bing/duckduckgo/…/spotlight/personalizado
    var almacen: String          // "tarea"|"nota"|"" — guarda lo procesado en la lista local
    var accion: String           // solo base "accion": id del preset (correo/outlook/whatsapp/…/url)
    var ejemplosVoz: [String]    // frases de ejemplo del usuario para el reconocimiento semántico
    var color: String            // color del modo en el notch, hex "#RRGGBB"; "" = automático
    var appNombre: String        // aplicación dinámica resuelta para ESTE dictado
    var appBundleId: String      // bundle id inventariado (nunca una orden arbitraria)
    var appRuta: String          // respaldo: ruta .app validada contra el catálogo actual
    var musicaProveedor: String  // solo "musica": auto/apple_music/spotify/…
    var musicaAccion: String     // solo "musica": auto/reproducir/buscar/controles
    var conexion: ConexionAPI?   // solo accion "conexion": API declarada por el usuario

    init(id: String, nombre: String, icono: String, base: String, prompt: String = "",
         proveedorId: String = "", modelo: String = "", idiomaDestino: String = "inglés",
         esFijo: Bool = true, palabraVoz: String = "", apps: [String] = [], sitios: [String] = [],
         buscador: String = "google", almacen: String = "", accion: String = "correo",
         ejemplosVoz: [String] = [], color: String = "", appNombre: String = "",
         appBundleId: String = "", appRuta: String = "", musicaProveedor: String = "auto",
         musicaAccion: String = "auto", conexion: ConexionAPI? = nil) {
        self.id = id; self.nombre = nombre; self.icono = icono; self.base = base
        self.prompt = prompt; self.proveedorId = proveedorId; self.modelo = modelo
        self.idiomaDestino = idiomaDestino; self.esFijo = esFijo; self.palabraVoz = palabraVoz
        self.apps = apps; self.sitios = sitios; self.buscador = buscador; self.almacen = almacen
        self.accion = accion; self.ejemplosVoz = ejemplosVoz; self.color = color
        self.appNombre = appNombre; self.appBundleId = appBundleId; self.appRuta = appRuta
        self.musicaProveedor = musicaProveedor; self.musicaAccion = musicaAccion
        self.conexion = conexion
    }
    // Decodificación tolerante (JSON viejo sin un campo nuevo no revienta).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? "Modo"
        icono = (try? c.decode(String.self, forKey: .icono)) ?? "wand.and.stars"
        base = (try? c.decode(String.self, forKey: .base)) ?? "pulir"
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        proveedorId = (try? c.decode(String.self, forKey: .proveedorId)) ?? ""
        modelo = (try? c.decode(String.self, forKey: .modelo)) ?? ""
        idiomaDestino = (try? c.decode(String.self, forKey: .idiomaDestino)) ?? "inglés"
        esFijo = (try? c.decode(Bool.self, forKey: .esFijo)) ?? false
        palabraVoz = (try? c.decode(String.self, forKey: .palabraVoz)) ?? ""
        apps = (try? c.decode([String].self, forKey: .apps)) ?? []
        sitios = (try? c.decode([String].self, forKey: .sitios)) ?? []
        buscador = (try? c.decode(String.self, forKey: .buscador)) ?? "google"
        almacen = (try? c.decode(String.self, forKey: .almacen)) ?? ""
        accion = (try? c.decode(String.self, forKey: .accion)) ?? "correo"
        ejemplosVoz = (try? c.decode([String].self, forKey: .ejemplosVoz)) ?? []
        color = (try? c.decode(String.self, forKey: .color)) ?? ""
        appNombre = (try? c.decode(String.self, forKey: .appNombre)) ?? ""
        appBundleId = (try? c.decode(String.self, forKey: .appBundleId)) ?? ""
        appRuta = (try? c.decode(String.self, forKey: .appRuta)) ?? ""
        musicaProveedor = (try? c.decode(String.self, forKey: .musicaProveedor)) ?? "auto"
        musicaAccion = (try? c.decode(String.self, forKey: .musicaAccion)) ?? "auto"
        conexion = try? c.decode(ConexionAPI.self, forKey: .conexion)
    }
}

enum ModosStore {
    private static var url: URL { Config.dir.appendingPathComponent("modos.json") }

    /// Modos BASE (siempre presentes; el usuario edita su prompt/IA pero no los borra).
    static let base: [Modo] = [
        Modo(id: "dictado", nombre: "Dictado", icono: "mic.fill", base: "pulir", prompt: ""),
        Modo(id: "correo", nombre: "Correo", icono: "envelope.fill", base: "pulir",
             prompt: "Reescribe el dictado como un CORREO ELECTRÓNICO claro y bien estructurado: saludo, cuerpo y despedida. Conserva el significado; ajusta el tono (formal por defecto) según lo dictado. Devuelve solo el correo.",
             palabraVoz: "modo correo, modo correos, modo carreo"),
        Modo(id: "oficio", nombre: "Oficio", icono: "doc.text.fill", base: "pulir",
             prompt: "Reescribe el dictado como un OFICIO o memorando FORMAL e institucional, en registro correcto y respetuoso. Conserva el fondo. Devuelve solo el texto del oficio.",
             palabraVoz: "modo oficio, modo oficios"),
        Modo(id: "tarea", nombre: "Tarea", icono: "checklist", base: "pulir",
             prompt: "Convierte el dictado en una TAREA breve y accionable: una sola línea, empieza con un verbo en infinitivo, sin relleno. Devuelve solo la tarea.",
             palabraVoz: "modo tarea, modo tareas, mudo tarea, molde tarea, moto tarea, modo tare", almacen: "tarea"),
        Modo(id: "nota", nombre: "Nota", icono: "note.text", base: "pulir",
             prompt: "Ordena el dictado como una NOTA clara y legible: puntuación correcta, sin muletillas; usa viñetas si hay varios puntos. Conserva todo el contenido. Devuelve solo la nota.",
             palabraVoz: "modo nota, modo notas, moda nota, modo note", almacen: "nota"),
        Modo(id: "traducir", nombre: "Traducir", icono: "globe", base: "traducir", idiomaDestino: "inglés",
             palabraVoz: "modo traducir, modo traduce, modo traducción"),
        Modo(id: "resumir", nombre: "Resumir", icono: "text.redaction", base: "pulir",
             prompt: "Resume el texto con fidelidad y claridad. Conserva las ideas y datos importantes, elimina repeticiones y devuelve solo el resumen.",
             palabraVoz: "modo resumir, modo resumen, modo sintetizar"),
        Modo(id: "asistente", nombre: "Asistente", icono: "sparkles", base: "responder",
             prompt: "El dictado es una instrucción o pregunta. Responde o redacta lo pedido de forma útil, directa y concisa, en español (salvo que se pida otro idioma). Devuelve solo la respuesta, sin preámbulos.",
             palabraVoz: "modo asistente, modo asistentes"),
        Modo(id: "buscar", nombre: "Buscar", icono: "magnifyingglass", base: "buscar",
             palabraVoz: "modo buscar, modo busca, modo búsqueda, modo buscador", buscador: "google"),
        Modo(id: "musica", nombre: "Música", icono: "music.note", base: "musica",
             palabraVoz: "modo música, modo musica, modo musical, pon música, reproduce música",
             musicaProveedor: "auto"),
        Modo(id: "aplicacion", nombre: "Aplicación", icono: "square.grid.2x2.fill", base: "aplicacion",
             palabraVoz: "modo abrir aplicación, modo abrir aplicacion, modo aplicación, modo aplicacion, modo abrir app, modo abre app, modo abrir"),
        Modo(id: "agente", nombre: "Agente", icono: "sparkle", base: "agente",
             prompt: "Eres el asistente de voz del usuario. Responde su pedido de forma útil, directa y BREVE (se leerá en voz alta), en español, sin preámbulos.",
             palabraVoz: "modo agente, modo la gente, modo gente, modo asistente de voz, modo jarvis"),
    ]

    static func todos() -> [Modo] {
        guard let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([Modo].self, from: data), !list.isEmpty else {
            return base
        }
        // Sumar modos base nuevos que un JSON viejo no conozca (sin duplicar).
        let faltan = base.filter { b in !list.contains { $0.id == b.id } }
        var cambio = false
        if !faltan.isEmpty { list.append(contentsOf: faltan); cambio = true }
        // Auto-sanado de la frase de voz: si un app de versión ANTERIOR reescribió
        // modos.json sin el campo palabraVoz (lo borra al no conocerlo), lo
        // restauramos desde la definición base. Solo si está VACÍO (no pisa lo que
        // tú edites) y solo la frase (prompt/IA/apps/sitios se respetan tal cual).
        for (i, m) in list.enumerated() {
            guard let b = base.first(where: { $0.id == m.id }) else { continue }
            // UNIÓN de frases de voz: suma las del base que falten (así los alias
            // nuevos llegan a configs viejos) sin borrar las que el usuario agregó.
            // VACÍO se respeta: si el usuario borró TODAS las frases, ese modo queda
            // SIN activación por voz (no se re-agregan los alias del catálogo).
            var frases = frasesVoz(m)
            if !frases.isEmpty {
                for f in frasesVoz(b) where !frases.contains(where: { normalizar($0) == normalizar(f) }) {
                    frases.append(f); cambio = true
                }
                let unido = FrasesConfigurables.formatear(frases, multilinea: false)
                if unido != m.palabraVoz { list[i].palabraVoz = unido; cambio = true }
            }
            if m.almacen.isEmpty, !b.almacen.isEmpty { list[i].almacen = b.almacen; cambio = true }
        }
        if cambio { guardar(list) }
        return list
    }

    static func guardar(_ modos: [Modo]) {
        if let d = try? JSONEncoder().encode(modos) {
            Config.asegurarDirSeguro()
            try? d.write(to: url, options: .atomic)
            Config.protegerSecreto(url)
            ModoCatalogoCache.invalidar()
        }
    }

    static func modo(_ id: String) -> Modo {
        todos().first { $0.id == id } ?? base[0]
    }

    /// El modo POR DEFECTO (sticky): al que se vuelve tras cada dictado.
    static func defecto() -> Modo { modo(Config.modoDefecto()) }
    /// Fija el modo por defecto (Ajustes → Modos) y lo aplica ya.
    static func fijarDefecto(_ id: String) {
        Config.set("modo_defecto", to: id)
        Config.set("modo_activo", to: id)
        Log.log(.config, "modo por defecto → \(modo(id).nombre)")
    }
    /// El modo ACTIVO ahora (transitorio; el notch/menú lo cambia al vuelo).
    static func activo() -> Modo { modo(Config.modoActivo()) }
    /// Cambio en caliente (notch/menú): de un solo uso si modoRevertir (default).
    static func fijarActivo(_ id: String) {
        Config.set("modo_activo", to: id)
        Log.log(.config, "modo activo → \(modo(id).nombre)")
    }
    /// Vuelve al modo por defecto si el usuario tiene el "un solo uso" activo.
    /// Se llama tras entregar cada dictado y al arrancar (limpia un transitorio viejo).
    static func revertirADefecto() {
        guard Config.modoRevertir(), Config.modoActivo() != Config.modoDefecto() else { return }
        Config.set("modo_activo", to: Config.modoDefecto())
        Log.log(.config, "modo vuelve al defecto → \(defecto().nombre)")
    }

    // MARK: Modos propios (crear / borrar)
    static func crear(nombre: String) -> Modo {
        let m = Modo(id: "propio-\(UUID().uuidString.prefix(8))",
                     nombre: nombre.isEmpty ? "Mi modo" : nombre,
                     icono: "wand.and.stars", base: "pulir", esFijo: false)
        var lista = todos(); lista.append(m); guardar(lista)
        return m
    }
    static func borrar(_ id: String) {
        var lista = todos()
        // Si el modo tenía una conexión API, su secreto muere con él (Keychain
        // y respaldo). No dejamos credenciales huérfanas de modos borrados.
        if lista.contains(where: { $0.id == id && !$0.esFijo && $0.conexion != nil }) {
            SecretosKeychain.borrar(cuenta: id)
            ConexionesAuth.invalidar(id)   // el token cacheado muere con el modo
        }
        lista.removeAll { $0.id == id && !$0.esFijo }   // los base no se borran
        guardar(lista)
        // No dejar modo_activo NI modo_defecto colgando en un id inexistente.
        if Config.modoDefecto() == id { Config.set("modo_defecto", to: "dictado") }
        if Config.modoActivo() == id { fijarActivo("dictado") }
    }

    // MARK: Activación por VOZ
    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Si el dictado EMPIEZA con la palabra de voz de algún modo, devuelve ese
    /// modo y el texto SIN la frase disparadora. nil si ninguno coincide. El
    /// modo con la frase más LARGA gana (evita que "modo" choque con "modo correo").
    /// Cada modo puede tener VARIAS frases (separadas por coma) como failover ante
    /// mal-escuchas del STT ("mudo tarea", "molde tarea" = "modo tarea"). Gana la
    /// frase más LARGA que haga prefijo (entre TODAS las frases de TODOS los modos).
    static func frasesVoz(_ m: Modo) -> [String] {
        FrasesConfigurables.parsear(m.palabraVoz)
    }
    static func detectarPorVoz(_ texto: String) -> (Modo, String)? {
        guard let match = ModoResolver.detectarExacto(texto) else { return nil }
        return (match.modo, match.textoLimpio)
    }

    // MARK: Activación por CONTEXTO (app / sitio web al frente)
    /// El modo cuyo app o sitio coincide con dónde estás (app al frente / URL del
    /// navegador). nil si ninguno. El activo/dictado no cuenta como trigger.
    static func detectarPorContexto(bundleId: String, nombre: String, url: String?) -> Modo? {
        coincidePorContexto(todos(), bundleId: bundleId, nombre: nombre, url: url)
    }
    /// Matcher puro (sin disco) — testeable sin tocar la config real.
    static func coincidePorContexto(_ modos: [Modo], bundleId: String, nombre: String, url: String?) -> Modo? {
        let bid = bundleId.lowercased(), nom = normalizar(nombre), u = url?.lowercased()
        for m in modos where m.id != "dictado" {
            for a in m.apps {
                let an = normalizar(a)
                if !an.isEmpty, bid.contains(an) || nom.contains(an) { return m }
            }
            if let u {
                for s in m.sitios {
                    let sn = normalizar(s)
                    if !sn.isEmpty, u.contains(sn) { return m }
                }
            }
        }
        return nil
    }
}

// MARK: - Contexto: app al frente y URL del navegador (para los triggers)

enum ContextoApp {
    static func alFrente() -> (bundleId: String, nombre: String) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier ?? "", app?.localizedName ?? "")
    }
    /// URL del navegador al frente (best-effort, vía AppleScript). Requiere
    /// permiso de Automatización (lo pide macOS la 1ª vez). nil si no aplica.
    static func urlNavegador(_ bundleId: String) -> String? {
        let scripts: [String: String] = [
            "com.apple.safari": "tell application \"Safari\" to return URL of current tab of front window",
            "com.google.chrome": "tell application \"Google Chrome\" to return URL of active tab of front window",
            "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to return URL of active tab of front window",
            "com.brave.browser": "tell application \"Brave Browser\" to return URL of active tab of front window",
            "company.thebrowser.browser": "tell application \"Arc\" to return URL of active tab of front window",
        ]
        guard let src = scripts[bundleId.lowercased()], let s = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        let out = s.executeAndReturnError(&err)
        return err == nil ? out.stringValue : nil
    }
}

// MARK: - Idiomas para el modo "Traducir" (con banderita + agregar propios)

enum Idiomas {
    /// Idiomas comunes con la bandera que MÁS los representa (aprox: idioma≠país).
    /// kichwa/shuar → 🇪🇨 (lenguas de la Amazonía ecuatoriana).
    static let base: [(nombre: String, bandera: String)] = [
        ("inglés", "🇬🇧"), ("español", "🇪🇸"), ("portugués", "🇧🇷"), ("francés", "🇫🇷"),
        ("alemán", "🇩🇪"), ("italiano", "🇮🇹"), ("chino", "🇨🇳"), ("japonés", "🇯🇵"),
        ("coreano", "🇰🇷"), ("ruso", "🇷🇺"), ("árabe", "🇸🇦"), ("hindi", "🇮🇳"),
        ("neerlandés", "🇳🇱"), ("turco", "🇹🇷"), ("polaco", "🇵🇱"), ("ucraniano", "🇺🇦"),
        ("griego", "🇬🇷"), ("hebreo", "🇮🇱"), ("vietnamita", "🇻🇳"), ("tailandés", "🇹🇭"),
        ("indonesio", "🇮🇩"), ("sueco", "🇸🇪"), ("noruego", "🇳🇴"), ("danés", "🇩🇰"),
        ("finés", "🇫🇮"), ("checo", "🇨🇿"), ("rumano", "🇷🇴"), ("húngaro", "🇭🇺"),
        ("kichwa", "🇪🇨"), ("quichua", "🇪🇨"), ("shuar", "🇪🇨"),
    ]
    private static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Si `token` nombra un idioma conocido (base o propio), devuelve su nombre
    /// canónico; si no, nil (para el argumento por voz de "modo traducir <idioma>").
    static func reconocer(_ token: String) -> String? {
        let n = norm(token)
        // Algunos STT devuelven el nombre del idioma en inglés o una forma
        // fonética corta aunque el resto esté en español. Son alias observados,
        // no fuzzy abierto: aquí equivocarse cambiaría el idioma de salida.
        let alias: [String: String] = [
            "english": "inglés", "spanish": "español", "portuguese": "portugués",
            "french": "francés", "german": "alemán", "italian": "italiano",
            "chinese": "chino", "japanese": "japonés", "korean": "coreano",
            "russian": "ruso", "arabic": "árabe", "dutch": "neerlandés",
            "greek": "griego", "hebrew": "hebreo", "quha": "quichua",
            "quija": "quichua", "quigua": "quichua", "quichwa": "quichua"
        ]
        if let a = alias[n] { return a }
        return todos().first { norm($0.nombre) == n }?.nombre
    }
    /// Todos: base + los que el usuario agregó (bandera genérica para los propios).
    static func todos() -> [(nombre: String, bandera: String)] {
        var vistos = Set(base.map { $0.nombre.lowercased() })
        var lista = base
        for p in Config.idiomasPersonales() where !p.isEmpty && !vistos.contains(p.lowercased()) {
            lista.append((p, "🏳️")); vistos.insert(p.lowercased())
        }
        return lista
    }
    static func bandera(_ nombre: String) -> String {
        base.first { $0.nombre.caseInsensitiveCompare(nombre) == .orderedSame }?.bandera ?? "🏳️"
    }
    /// Agrega un idioma propio (idempotente; no pisa los base). Devuelve el nombre
    /// CANÓNICO: si ya existe (aunque difiera en mayúsculas/acentos), devuelve el
    /// que está en la lista para que el Picker lo empareje por tag exacto.
    @discardableResult static func agregar(_ nombre: String) -> String {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return "" }
        if let existente = todos().first(where: { $0.nombre.caseInsensitiveCompare(n) == .orderedSame }) {
            return existente.nombre   // ya está: usa el canónico, no el tecleado
        }
        var props = Config.idiomasPersonales(); props.append(n)
        Config.set("idiomas_personales", to: props)
        return n
    }
}

// MARK: - Buscadores para el modo "Buscar"

enum Buscadores {
    /// id, nombre visible, plantilla URL con {q} (nil = Spotlight local ⌘Espacio).
    static let base: [(id: String, nombre: String, url: String?)] = [
        ("google", "Google", "https://www.google.com/search?q={q}"),
        ("bing", "Bing", "https://www.bing.com/search?q={q}"),
        ("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q={q}"),
        ("wikipedia", "Wikipedia", "https://es.wikipedia.org/w/index.php?search={q}"),
        ("youtube", "YouTube", "https://www.youtube.com/results?search_query={q}"),
        ("maps", "Google Maps", "https://www.google.com/maps/search/{q}"),
        ("gmail", "Gmail (buscar correo)", "https://mail.google.com/mail/u/0/#search/{q}"),
        ("hotmail", "Outlook/Hotmail (buscar)", "https://outlook.live.com/mail/0/search/?q={q}"),
        ("facebook", "Facebook", "https://www.facebook.com/search/top?q={q}"),
        ("amazon", "Amazon", "https://www.amazon.com/s?k={q}"),
        ("mercadolibre", "MercadoLibre", "https://listado.mercadolibre.com.ec/{q}"),
        ("x", "X (Twitter)", "https://twitter.com/search?q={q}"),
        ("github", "GitHub", "https://github.com/search?q={q}"),
        ("spotlight", "Spotlight (⌘Espacio en la Mac)", nil),
        ("personalizado", "Personalizado (URL con {q})", nil),
    ]
    /// Buscadores que el usuario agregó (nombre + URL con {q}). id = "personal:<nombre>".
    static func personales() -> [(id: String, nombre: String, url: String)] {
        Config.buscadoresPersonales().compactMap {
            guard let n = $0["nombre"], let u = $0["url"], !n.isEmpty, u.contains("{q}") else { return nil }
            return ("personal:\(n.lowercased())", n, u)
        }
    }
    /// Para el selector: base + los propios del usuario.
    static func paraPicker() -> [(id: String, nombre: String)] {
        base.map { ($0.id, $0.nombre) } + personales().map { ($0.id, $0.nombre) }
    }
    static func nombre(_ id: String) -> String {
        base.first { $0.id == id }?.nombre ?? personales().first { $0.id == id }?.nombre ?? id
    }
    static func plantilla(_ id: String) -> String? {
        base.first { $0.id == id }?.url ?? personales().first { $0.id == id }?.url
    }
    /// Si `token` nombra un buscador (id o 1ª palabra del nombre), devuelve su id;
    /// si no, nil (para "modo buscar <buscador> <consulta>"). Alias comunes incluidos.
    static func reconocer(_ token: String) -> String? {
        let n = token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = ["ddg": "duckduckgo", "duck": "duckduckgo", "yt": "youtube",
                     "mapas": "maps", "spot": "spotlight"]
        if let a = alias[n] { return a }
        return base.first { $0.id == n || $0.nombre.lowercased().hasPrefix(n) && !n.isEmpty }?.id
    }
    /// URL final para la consulta. nil = Spotlight (no es URL). `custom` = plantilla
    /// del modo cuando id=="personalizado" (debe tener {q}; si no, cae a Google).
    static func url(_ id: String, query: String, custom: String = "") -> String? {
        guard id != "spotlight" else { return nil }
        let tpl = id == "personalizado"
            ? (custom.contains("{q}") ? custom : "https://www.google.com/search?q={q}")
            : (plantilla(id) ?? "https://www.google.com/search?q={q}")
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = query.addingPercentEncoding(withAllowedCharacters: cs) ?? query
        return tpl.replacingOccurrences(of: "{q}", with: enc)
    }
}

// MARK: - Acciones para el modo "Acción" (abrir app / correo / web con el texto)

enum Acciones {
    /// id, nombre, esquema URL con {q} ("" = solo abrir la app, sin texto en URL;
    /// "{q}" = URL propia del usuario en `prompt`), bundle id de la app.
    static let base: [(id: String, nombre: String, esquema: String, bundle: String)] = [
        ("gmail",         "Gmail (nuevo borrador)",          "", ""),
        ("correo",        "Correo / Mail (nuevo correo)",    "mailto:?body={q}", "com.apple.mail"),
        // Ruta especial: un `mailto:` se entrega explícitamente a Outlook y la
        // ventana nueva se verifica por Accesibilidad (BorradoresCorreo).
        ("outlook",       "Outlook: nuevo correo",           "", "com.microsoft.Outlook"),
        ("whatsapp",      "WhatsApp (con el texto)",         "whatsapp://send?text={q}", "net.whatsapp.WhatsApp"),
        ("mensajes",      "Mensajes (copia el texto)",       "", "com.apple.MobileSMS"),
        ("notas",         "Nota de Apple (crear y verificar)", "", "com.apple.Notes"),
        ("recordatorios", "Recordatorio nativo de Mac",      "", "com.apple.reminders"),
        ("calendario",    "Evento nativo de Calendario",     "", "com.apple.iCal"),
        ("finder",        "Finder",                          "", "com.apple.finder"),
        ("safari",        "Safari",                          "", "com.apple.Safari"),
        ("musica",        "Música",                          "", "com.apple.Music"),
        ("volumen",       "Controlar volumen del Mac",       "", ""),
        ("terminal",      "Terminal (copia el texto)",       "", "com.apple.Terminal"),
        ("mapas",         "Mapas (busca lo dictado)",        "https://maps.apple.com/?q={q}", "com.apple.Maps"),
        ("fotos",         "Fotos",                           "", "com.apple.Photos"),
        ("contactos",     "Contactos",                       "", "com.apple.AddressBook"),
        ("textedit",      "TextEdit (copia el texto)",       "", "com.apple.TextEdit"),
        ("vistaprevia",   "Vista Previa",                    "", "com.apple.Preview"),
        ("ajustes",       "Ajustes del Sistema",             "", "com.apple.systempreferences"),
        ("appstore",      "App Store",                       "", "com.apple.AppStore"),
        ("facetime",      "FaceTime",                        "", "com.apple.FaceTime"),
        ("spotlight",     "Spotlight (⌘Espacio, pega el texto)", "", ""),
        ("archivo",       "Buscar archivo en la Mac",        "", "com.apple.finder"),
        ("archivo_nuevo", "Crear archivo de texto…",         "", ""),
        ("captura_pantalla", "Captura de pantalla",           "", ""),
        ("grabar_pantalla",  "Grabación de pantalla",         "", ""),
        ("captura_compartir", "Captura para compartir",       "", ""),
        ("clima",          "Consultar clima actual",          "", ""),
        ("atajo_apple",   "Atajo Apple / Siri",              "", "com.apple.shortcuts"),
        ("rutina",        "Rutina del asistente",            "", ""),
        ("conexion",      "Conexión API (se configura abajo)", "", ""),
        ("nota_local",    "Nota local de BtoDicta",         "", ""),
        ("tarea_local",   "Tarea local de BtoDicta",        "", ""),
        ("url",           "Abrir web (tu URL con {q})",      "{q}", ""),
    ]
    static func nombre(_ id: String) -> String { base.first { $0.id == id }?.nombre ?? id }
    static func bundle(_ id: String) -> String { base.first { $0.id == id }?.bundle ?? "" }
    static func valido(_ id: String) -> Bool { base.contains { $0.id == id } }
    static func plantillaURLSegura(_ plantilla: String) -> Bool {
        let prueba = plantilla.replacingOccurrences(of: "{q}", with: "prueba")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: prueba), let scheme = c.scheme?.lowercased() else { return false }
        if scheme == "https" { return c.host?.isEmpty == false }
        if scheme == "http" {
            let h = (c.host ?? "").lowercased()
            return ["localhost", "127.0.0.1", "::1"].contains(h)
        }
        return false
    }
    /// WhatsApp con FAILOVER: app de escritorio (whatsapp://) si está instalada,
    /// si no la web wa.me. El llamador decide `app` (¿hay app de escritorio?).
    static func whatsapp(texto: String, app: Bool) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        return app ? "whatsapp://send?text=\(enc)" : "https://wa.me/?text=\(enc)"
    }
    /// URL/esquema final con el texto (nil = acción de SOLO abrir app, sin URL).
    /// `custom` = plantilla del usuario cuando id=="url" (debe tener {q}).
    static func url(_ id: String, texto: String, custom: String = "") -> String? {
        guard let e = base.first(where: { $0.id == id }), !e.esquema.isEmpty else { return nil }
        if id == "url" {
            let c = custom.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty else { return "https://www.google.com/search?q={q}" }
            guard plantillaURLSegura(c) else { return nil }
            // URL propia SIN {q} → abre la página tal cual (ignora el texto).
            if !c.contains("{q}") { return c }
            var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
            let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
            return c.replacingOccurrences(of: "{q}", with: enc)
        }
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        return e.esquema.replacingOccurrences(of: "{q}", with: enc)
    }
}

// MARK: - Modos ENCADENADOS por voz (pipeline: transforms + acción final) — Fase 6
//
// "modo traducir quichua a correo outlook <texto>" → traduce a quichua, luego abre
// Outlook con ese texto. Orden-independiente ("modo correo y traducir quichua …"):
// los transforms se aplican en orden y las ACCIONES finales reciben el mismo resultado.
// Solo se activa con 2+ etapas; 1 etapa la maneja detectarPorVoz normal (sin regresión).

extension ModosStore {
    struct DeteccionSemantica {
        let modo: Modo?
        let textoLimpio: String
        let comando: String
        let score: Double
        let segundoId: String?
        let segundoScore: Double
        let margen: Double
        let superaUmbral: Bool
        let inequívoco: Bool
    }

    private static let conectores: Set<String> = [
        "a", "al", "y", "e", "en", "para", "con", "de", "la", "el", "lo", "los", "las",
        "modo"   // el usuario repite "modo" por etapa ("modo traducir modo buscar")
    ]
    /// Normaliza un token para MATCHEAR verbos: sin acentos/mayúsculas y SIN la
    /// puntuación pegada ("traducir," "Google." → "traducir" "google").
    private static func limpioTok(_ s: String) -> String {
        normalizar(s).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?¡¿\"'«»()-—"))
    }
    // verbo (1 palabra tras "modo") → id de modo TRANSFORM
    private static let verbosTransform: [String: String] = [
        "traducir": "traducir", "traduce": "traducir", "traduccion": "traducir",
        "resumen": "resumir", "resumir": "resumir", "resume": "resumir", "sintetizar": "resumir",
        "oficio": "oficio", "tarea": "tarea", "nota": "nota",
        "asistente": "asistente", "responde": "asistente",
    ]
    // verbo → preset de ACCIÓN ("buscar" es especial: lleva buscador)
    private static let verbosAccion: [String: String] = [
        "correo": "correo", "email": "correo", "enviar": "correo", "mail": "correo", "mailto": "correo",
        "outlook": "outlook",
        "whatsapp": "whatsapp", "wasap": "whatsapp", "guasap": "whatsapp", "wasa": "whatsapp",
        "notas": "notas", "finder": "finder", "recordatorios": "recordatorios",
        "calendario": "calendario", "mensajes": "mensajes",
        "aplicacion": "aplicacion", "app": "aplicacion", "abrir": "aplicacion", "abre": "aplicacion",
        "buscar": "buscar", "busca": "buscar", "google": "buscar", "bing": "buscar",
        "duckduckgo": "buscar", "youtube": "buscar", "maps": "buscar", "mapas": "buscar",
        "musica": "musica", "cancion": "musica", "reproducir": "musica", "reproduce": "musica",
        "poner": "musica", "pon": "musica",
    ]

    // Capa 2 (sin IA): matcheo por RAÍZ. Tolera formas variables sin enumerar todo.
    private static let transformStems: [(String, String)] = [
        ("traduc", "traducir"), ("resum", "resumir"), ("sintet", "resumir"),
        ("ofici", "oficio"), ("tarea", "tarea"), ("nota", "nota"),
        ("asist", "asistente"), ("respond", "asistente"),
    ]
    private static let accionStems: [(String, String)] = [
        ("correo", "correo"), ("mail", "correo"), ("outlook", "outlook"),
        ("whats", "whatsapp"), ("wasa", "whatsapp"), ("guasa", "whatsapp"),
        ("mensaj", "mensajes"), ("imessage", "mensajes"),
        ("recordat", "recordatorios"), ("calendar", "calendario"), ("agenda", "calendario"),
        ("finder", "finder"), ("archivo", "finder"), ("safari", "safari"), ("navegador", "safari"),
        ("music", "musica"), ("cancion", "musica"), ("reproduc", "musica"),
        ("terminal", "terminal"), ("consola", "terminal"),
        ("mapa", "mapas"), ("foto", "fotos"), ("contacto", "contactos"),
        ("textedit", "textedit"), ("editor", "textedit"), ("preview", "vistaprevia"), ("vista", "vistaprevia"),
        ("ajuste", "ajustes"), ("config", "ajustes"), ("appstore", "appstore"), ("tienda", "appstore"),
        ("facetime", "facetime"), ("videollam", "facetime"),
        ("aplic", "aplicacion"),
        ("spotlight", "spotlight"), ("lupa", "spotlight"),
        ("busc", "buscar"), ("google", "buscar"), ("bing", "buscar"), ("youtube", "buscar"), ("duckduck", "buscar"),
    ]
    /// Resuelve un token a (tipo, id): exacto primero, luego por raíz (≥4 letras).
    static func resolverVerbo(_ tok: String) -> (tipo: String, id: String)? {
        let w = limpioTok(tok)
        guard w.count >= 3 else { return nil }
        if let t = verbosTransform[w] { return ("transform", t) }
        if let a = verbosAccion[w] { return ("accion", a) }
        for (s, id) in transformStems where s.count >= 4 && w.hasPrefix(s) { return ("transform", id) }
        for (s, id) in accionStems where s.count >= 4 && w.hasPrefix(s) { return ("accion", id) }
        return nil
    }

    /// Parsea una CADENA de voz. nil si no empieza con "modo" o si hay <2 etapas.
    static func detectarCadena(_ texto: String) -> ModoCadena? {
        var tokens = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard let f = tokens.first,
              ModoResolver.palabrasModoSeguras.contains(limpioTok(f)) else { return nil }
        tokens.removeFirst()
        var transforms: [Modo] = []
        var acciones: [ModoAccionPlan] = []
        func agregarAccion(_ m: Modo) {
            // “modo música Spotify, reproduce…” sigue siendo UNA herramienta.
            // El verbo reproducir no debe crear una segunda etapa musical solo
            // porque la primera ya congeló un proveedor distinto de `auto`.
            if m.base == "musica", let indice = acciones.firstIndex(where: {
                $0.modo.base == "musica"
            }) {
                if acciones[indice].modo.musicaProveedor == "auto",
                   m.musicaProveedor != "auto" {
                    acciones[indice].modo.musicaProveedor = m.musicaProveedor
                }
                return
            }
            let firma: String
            if m.base == "buscar" { firma = "buscar:\(m.buscador)" }
            else if m.base == "musica" { firma = "musica:\(m.musicaProveedor)" }
            else if m.base == "aplicacion" { firma = "app:\(m.appBundleId)|\(m.appRuta)" }
            else { firma = m.accion }
            guard !acciones.contains(where: {
                let otra: String
                if $0.modo.base == "buscar" { otra = "buscar:\($0.modo.buscador)" }
                else if $0.modo.base == "musica" { otra = "musica:\($0.modo.musicaProveedor)" }
                else if $0.modo.base == "aplicacion" { otra = "app:\($0.modo.appBundleId)|\($0.modo.appRuta)" }
                else { otra = $0.modo.accion }
                return otra == firma
            }) else { return }
            acciones.append(ModoAccionPlan(modo: m, destinatario: nil))
        }
        var i = 0
        while i < tokens.count {
            let w = limpioTok(tokens[i])
            if w.isEmpty || conectores.contains(w) { i += 1; continue }
            guard let v = resolverVerbo(tokens[i]) else { break }   // desconocido → contenido
            i += 1
            if v.tipo == "transform" {
                var m = modo(v.id)
                if m.base == "traducir" {
                    // salta conectores ("a", "al"…) y toma el idioma si viene
                    var j = i
                    while j < tokens.count, conectores.contains(limpioTok(tokens[j])) { j += 1 }
                    if j < tokens.count, let idi = Idiomas.reconocer(limpioTok(tokens[j])) { m.idiomaDestino = idi; i = j + 1 }
                }
                transforms.append(m)
            } else if v.id == "buscar" {
                // Dentro de “modo música, busca Julio Jaramillo”, `busca` define
                // la intención del reproductor. No es una segunda acción de
                // navegador. Al dejar la cadena con una sola etapa, el resolvedor
                // exacto conserva todo el resto para `Musica.intencion`.
                if acciones.contains(where: { $0.modo.base == "musica" }) { break }
                var b = modo("buscar")
                if let eng = Buscadores.reconocer(w) { b.buscador = eng }
                else {
                    var j = i
                    while j < tokens.count, conectores.contains(limpioTok(tokens[j])) { j += 1 }
                    if j < tokens.count, let eng = Buscadores.reconocer(limpioTok(tokens[j])) { b.buscador = eng; i = j + 1 }
                }
                agregarAccion(b)
            } else if v.id == "musica" {
                var m = modo("musica")
                var j = i
                while j < tokens.count, conectores.contains(limpioTok(tokens[j])) { j += 1 }
                if j < tokens.count {
                    if j + 1 < tokens.count {
                        let dos = limpioTok(tokens[j]) + " " + limpioTok(tokens[j + 1])
                        if let p = Musica.reconocerProveedorCompuesto(dos) {
                            m.musicaProveedor = p; i = j + 2
                        } else if let p = Musica.reconocerProveedor(en: limpioTok(tokens[j])) {
                            m.musicaProveedor = p; i = j + 1
                        }
                    } else if let p = Musica.reconocerProveedor(en: limpioTok(tokens[j])) {
                        m.musicaProveedor = p; i = j + 1
                    }
                }
                agregarAccion(m)
            } else if v.id == "aplicacion", Config.modoAplicaciones() {
                var j = i
                let relleno: Set<String> = ["aplicacion", "app", "programa", "el", "la"]
                while j < tokens.count, relleno.contains(limpioTok(tokens[j])) { j += 1 }
                guard j < tokens.count else { break }
                let resto = tokens[j...].map(limpioTok)
                guard case .encontrada(let match) = AplicacionesMac.resolverPrefijo(resto) else { break }
                let appModo = AplicacionesMac.aplicar(match, a: modo("aplicacion"))
                agregarAccion(appModo)
                i = j + match.palabrasConsumidas
            } else {
                var accion = Modo(id: "cadena-\(v.id)", nombre: Acciones.nombre(v.id),
                                  icono: "bolt.fill", base: "accion", accion: v.id)
                // "enviar POR CORREO/WHATSAPP…": el medio concreto tras el verbo genérico
                // MANDA y se consume (antes quedaba pegado al contenido: el correo salía
                // con "por correo hola equipo" adentro).
                if w == "enviar" {
                    let puentes: Set<String> = ["por", "al", "a", "en", "el", "la", "un", "una"]
                    var j = i
                    while j < tokens.count,
                          conectores.contains(limpioTok(tokens[j])) || puentes.contains(limpioTok(tokens[j])) { j += 1 }
                    if j < tokens.count, let v2 = resolverVerbo(tokens[j]),
                       v2.tipo != "transform", v2.id != "buscar" {
                        accion = Modo(id: "cadena-\(v2.id)", nombre: Acciones.nombre(v2.id),
                                      icono: "bolt.fill", base: "accion", accion: v2.id)
                        i = j + 1
                    }
                }
                agregarAccion(accion)
            }
        }
        guard transforms.count + acciones.count >= 2 else { return nil }
        let contenido = tokens[i...].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n"))
        return ModoCadena(transforms: transforms, acciones: acciones, contenido: contenido)
    }
}

// MARK: - Reconocimiento SEMÁNTICO de modos (embeddings, capa 3, opt-in) — Fase B
//
// Cuando el exacto/raíz NO reconoce el comando pero el dictado empieza con "modo"
// (o una mal-escucha: mudo/molde/moto…), se embebe la ZONA-COMANDO (el inicio) y se
// elige el modo más cercano por coseno. Umbral para no forzar. El resto = contenido.

extension ModosStore {
    /// Palabras que valen como "modo" (indispensable) aunque el STT las mal-escuche.
    static let palabrasModo: Set<String> = ["modo", "mudo", "molde", "moto", "modho", "moldo", "mode", "modos", "mod", "moro"]
    static func esPalabraModo(_ tok: String) -> Bool { palabrasModo.contains(limpioTok(tok)) }
    /// ¿El dictado PARECE un comando? (empieza con una palabra tipo "modo").
    static func pareceComando(_ texto: String) -> Bool {
        let f = texto.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
        return esPalabraModo(f)
    }

    /// Frases-ejemplo de CÓMO se pide cada modo (para el matcheo semántico). Base
    /// curada + las frases de voz + el nombre. El usuario amplía con sus frases.
    static func ejemplos(_ m: Modo) -> [String] {
        var e = frasesVoz(m)
        e.append("modo \(m.nombre.lowercased())")
        switch m.id {
        case "correo": e += ["enviar un correo", "mandar un email", "escribir un correo", "redactar un mensaje"]
        case "oficio": e += ["hacer un oficio", "redactar un memorando", "documento formal institucional"]
        case "tarea": e += ["agregar una tarea", "anotar un pendiente", "recuérdame hacer algo", "nueva tarea"]
        case "nota": e += ["tomar una nota", "apuntar una idea", "guardar una nota"]
        case "traducir": e += ["traducir esto", "traduce al inglés", "cómo se dice esto en otro idioma"]
        case "resumir": e += ["resumir este texto", "hazme un resumen", "sintetiza lo siguiente", "condensa estas ideas"]
        case "asistente": e += ["responde esto", "ayúdame a redactar", "escribe una respuesta"]
        case "agente": e += ["pregúntale al agente", "pregúntale a la gente", "consulta al agente", "modo jarvis"]
        case "buscar": e += ["buscar en google", "busca esto en internet", "googlear algo"]
        case "musica": e += ["poner música", "reproduce una canción", "pon música en spotify", "buscar una canción en apple music"]
        case "aplicacion": e += ["abrir una aplicación", "abre word y pega el texto", "iniciar una app de mac"]
        default:
            if m.base == "accion" {
                switch m.accion {
                case "whatsapp": e += ["enviar un whatsapp", "mandar un whatsapp", "escribir por whatsapp", "mándale un mensaje de whatsapp"]
                case "correo", "outlook": e += ["enviar un correo", "abrir el correo", "nuevo correo en outlook"]
                case "notas": e += ["abrir notas", "crear una nota en notas de mac"]
                case "recordatorios": e += ["abrir recordatorios", "crear un recordatorio"]
                case "calendario": e += ["abrir el calendario", "ver mi agenda"]
                case "mapas": e += ["abrir mapas", "buscar en el mapa"]
                case "url": e += ["abrir la página web", "abrir mi sitio"]
                case "conexion": e += ["consulta \(m.nombre.lowercased())",
                                       "usa la conexión \(m.nombre.lowercased())",
                                       "pregúntale a \(m.nombre.lowercased())"]
                default: e += ["abrir \(Acciones.nombre(m.accion))"]
                }
            } else if m.base == "traducir" {
                e += ["traducir a \(m.idiomaDestino)"]
            }
        }
        e += m.ejemplosVoz   // frases que el usuario agregó (su propio "entrenamiento")
        return e.filter { !$0.isEmpty }
    }

    private static func paresEjemplos() -> [(id: String, ejemplos: [String])] {
        // El destino "aplicación" necesita un bundle REAL del inventario local;
        // no se delega a embeddings porque podrían consumir el nombre de la app.
        todos().filter { $0.id != "dictado" && $0.base != "aplicacion" }
            .map { ($0.id, ejemplos($0)) }
    }

    /// Elige el modo por SIGNIFICADO. Si los vectores no están calientes, los
    /// calienta en 2º plano y devuelve nil (esta vez cae al comportamiento normal).
    static func detectarSemanticoDetallado(_ texto: String,
                                           done: @escaping (DeteccionSemantica) -> Void) {
        let pares = paresEjemplos()
        guard EmbeddingSearch.modosListos(pares) else {
            EmbeddingSearch.calentarModos(pares)
            done(DeteccionSemantica(modo: nil, textoLimpio: texto, comando: "",
                                    score: 0, segundoId: nil, segundoScore: 0,
                                    margen: 0, superaUmbral: false, inequívoco: false)); return
        }
        var toks = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        if let f = toks.first, esPalabraModo(f) { toks.removeFirst() }
        guard !toks.isEmpty else {
            done(DeteccionSemantica(modo: nil, textoLimpio: texto, comando: "",
                                    score: 0, segundoId: nil, segundoScore: 0,
                                    margen: 0, superaUmbral: false, inequívoco: false)); return
        }
        // VENTANA DINÁMICA: crecemos la zona-comando palabra por palabra y nos
        // quedamos con la ventana de MAYOR score (donde la intención "consolida").
        // Así "mándale mensaje whatsapp | a Andrés, hola" corta bien: el comando
        // llega hasta donde el score es máximo, y "a Andrés…" queda como contenido
        // (para extraer el destinatario). Techo = 1ª coma o N palabras (parametrizable).
        var techo = min(toks.count, max(2, Config.modoSemanticoPalabras()))
        if let coma = toks.firstIndex(where: { $0.contains(",") }) { techo = min(techo, coma + 1) }
        let umbral = Config.modoSemanticoUmbral()
        let grupo = DispatchGroup(); let lk = NSLock()
        var res: [(w: Int, primero: EmbeddingSearch.PuntajeModo?, segundo: EmbeddingSearch.PuntajeModo?)] = []
        for w in 1...techo {
            let cmd = toks.prefix(w).joined(separator: " ")
            grupo.enter()
            EmbeddingSearch.rankingModos(comando: cmd, modos: pares) { ranking in
                lk.lock(); res.append((w, ranking.first, ranking.dropFirst().first)); lk.unlock(); grupo.leave()
            }
        }
        grupo.notify(queue: .main) {
            let mejor = res.max { ($0.primero?.score ?? 0) < ($1.primero?.score ?? 0) }
            let comandoTxt = mejor.map { toks.prefix($0.w).joined(separator: " ") } ?? ""
            let score = mejor?.primero?.score ?? 0
            let segundoScore = mejor?.segundo?.score ?? 0
            let margen = score - segundoScore
            let supera = mejor?.primero != nil && score >= umbral
            let inequivoco = supera && margen >= Config.modoSemanticoMargen()
            ModosLog.registrar("semantico", ["comando": comandoTxt, "ventana": mejor?.w ?? 0,
                "mejor": mejor?.primero?.id ?? "-", "score": score,
                "segundo": mejor?.segundo?.id ?? "-", "segundo_score": segundoScore,
                "margen": margen, "margen_min": Config.modoSemanticoMargen(),
                "umbral": umbral, "aceptado": supera, "inequivoco": inequivoco])
            guard let mejor, let id = mejor.primero?.id, supera,
                  var m = todos().first(where: { $0.id == id }) else {
                done(DeteccionSemantica(modo: nil, textoLimpio: texto, comando: comandoTxt,
                                        score: score, segundoId: mejor?.segundo?.id,
                                        segundoScore: segundoScore, margen: margen,
                                        superaUmbral: false, inequívoco: false)); return
            }
            // No dejes conectores finales ("a", "para"…) en el comando: van al
            // contenido, para que "…whatsapp a | Andrés" → contenido "a Andrés"
            // y objetivo() extraiga el destinatario.
            var w = mejor.w
            while w > 1, conectores.contains(limpioTok(toks[w - 1])) { w -= 1 }
            // El embedding puede consolidar en "traducir"/"buscar" antes de oír
            // el argumento. Si viene inmediatamente después, aplícalo y consúmelo.
            var candidato = w
            while candidato < toks.count,
                  ["a", "al", "en", "con", "idioma", "buscador"].contains(limpioTok(toks[candidato])) {
                candidato += 1
            }
            if candidato < toks.count {
                if m.base == "traducir", let idi = Idiomas.reconocer(limpioTok(toks[candidato])) {
                    m.idiomaDestino = idi; w = candidato + 1
                } else if m.base == "buscar", let b = Buscadores.reconocer(limpioTok(toks[candidato])) {
                    m.buscador = b; w = candidato + 1
                } else if m.base == "musica" {
                    let uno = limpioTok(toks[candidato])
                    let dos = candidato + 1 < toks.count
                        ? uno + " " + limpioTok(toks[candidato + 1]) : uno
                    if let p = Musica.reconocerProveedorCompuesto(dos) {
                        m.musicaProveedor = p; w = candidato + 2
                    } else if let p = Musica.reconocerProveedor(en: uno) {
                        m.musicaProveedor = p; w = candidato + 1
                    }
                }
            }
            let contenido = toks.dropFirst(w).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:\n"))
            done(DeteccionSemantica(modo: m, textoLimpio: contenido,
                                    comando: toks.prefix(w).joined(separator: " "),
                                    score: score, segundoId: mejor.segundo?.id,
                                    segundoScore: segundoScore, margen: margen,
                                    superaUmbral: true, inequívoco: inequivoco))
        }
    }

    static func detectarSemantico(_ texto: String, done: @escaping (Modo?, String) -> Void) {
        detectarSemanticoDetallado(texto) { r in
            done(r.inequívoco ? r.modo : nil, r.inequívoco ? r.textoLimpio : texto)
        }
    }
}
