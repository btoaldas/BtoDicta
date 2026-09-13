import AppKit
import Foundation

// MARK: - Catálogo dinámico de aplicaciones instaladas
//
// El modo "Aplicación" no mantiene una lista inyectada: descubre los .app reales
// de esta Mac, compila alias hablables y resuelve el nombre SOLO al comienzo de la
// orden. El catálogo se cachea para que los parciales en vivo no recorran el disco.

struct AplicacionMac {
    let nombre: String
    let bundleId: String
    let ruta: String
    let alias: [String]

    var url: URL { URL(fileURLWithPath: ruta) }

    /// Crear un documento con ⌘N es razonablemente determinista en estos editores.
    /// En las demás apps se pega en el control que tenga el foco, sin pulsar Enter.
    var admiteDocumentoNuevo: Bool {
        let b = bundleId.lowercased()
        return [
            "com.microsoft.word",
            "com.apple.textedit",
            "org.libreoffice.script"
        ].contains(b)
    }
}

struct CoincidenciaAplicacionMac {
    let app: AplicacionMac
    let palabrasConsumidas: Int
    let confianza: Double
    let exacta: Bool
}

enum ResultadoAplicacionMac {
    case encontrada(CoincidenciaAplicacionMac)
    case ambiguas([CoincidenciaAplicacionMac])
    case ninguna
}

enum AplicacionesMac {
    private struct Candidato {
        let app: AplicacionMac
        let n: Int
        let score: Double
        let exacta: Bool
    }

    private static let lock = NSLock()
    private static var cache: [AplicacionMac]?
    private static var fechaCache: Date?
    private static let vigencia: TimeInterval = 120

    private static let raices: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]

    /// Alias especialmente útiles al dictar. Se suman a los derivados del nombre y
    /// bundle; no reemplazan el inventario real ni permiten abrir rutas arbitrarias.
    private static let aliasPorBundle: [String: [String]] = [
        "com.microsoft.word": ["word", "world", "microsoft word"],
        "com.microsoft.excel": ["excel", "microsoft excel"],
        "com.microsoft.powerpoint": ["powerpoint", "power point", "microsoft powerpoint"],
        "com.microsoft.outlook": ["outlook", "microsoft outlook"],
        "com.microsoft.onenote.mac": ["onenote", "one note", "microsoft onenote"],
        "com.microsoft.teams2": ["teams", "microsoft teams"],
        "com.microsoft.teams": ["teams", "microsoft teams"],
        "com.google.chrome": ["chrome", "google chrome"],
        "com.microsoft.edgemac": ["edge", "microsoft edge"],
        "com.apple.safari": ["safari"],
        "com.apple.notes": ["notas", "notas de mac", "notes"],
        "com.apple.reminders": ["recordatorios", "reminders"],
        "com.apple.ical": ["calendario", "calendar"],
        "com.apple.mail": ["correo de mac", "mail"],
        "com.apple.textedit": ["textedit", "text edit", "editor de texto"],
        "com.apple.systempreferences": ["ajustes", "configuracion", "ajustes del sistema"],
        "com.apple.mobilesms": ["mensajes", "messages"],
        "com.apple.finder": ["finder"],
        "com.apple.terminal": ["terminal"],
        "net.whatsapp.whatsapp": ["whatsapp", "wasap", "guasap"],
        "com.openai.chat": ["chatgpt", "chat gpt"],
        "com.microsoft.vscode": ["visual studio code", "vs code", "vscode", "code"],
        "md.obsidian": ["obsidian"],
        "com.apple.iwork.pages": ["pages"],
        "com.apple.iwork.numbers": ["numbers"],
        "com.apple.iwork.keynote": ["keynote"]
    ]

    static func normalizar(_ texto: String) -> String {
        let plegado = texto.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: Locale(identifier: "es"))
        let escalares = plegado.unicodeScalars.map { u -> Character in
            Character(CharacterSet.alphanumerics.contains(u) ? String(u) : " ")
        }
        return String(escalares).split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func aliases(nombre: String, bundleId: String) -> [String] {
        var salida = Set<String>()
        func agregar(_ s: String) {
            let n = normalizar(s)
            if !n.isEmpty { salida.insert(n) }
        }
        agregar(nombre)

        let prefijos = ["microsoft ", "google ", "adobe ", "apple "]
        let normal = normalizar(nombre)
        for p in prefijos where normal.hasPrefix(p) {
            agregar(String(normal.dropFirst(p.count)))
        }
        // Quita un año de versión para que "Photoshop" encuentre "Photoshop 2026".
        let sinVersion = normal.split(separator: " ").filter { tok in
            !(tok.count == 4 && Int(tok) != nil)
        }.joined(separator: " ")
        agregar(sinVersion)

        if let ultimo = bundleId.split(separator: ".").last {
            let b = normalizar(String(ultimo))
            let genericos: Set<String> = ["app", "mac", "macos", "helper", "launcher", "shim"]
            if b.count >= 3, !genericos.contains(b) { agregar(b) }
        }
        for a in aliasPorBundle[bundleId.lowercased()] ?? [] { agregar(a) }
        return salida.sorted {
            let ac = $0.split(separator: " ").count, bc = $1.split(separator: " ").count
            return ac == bc ? $0.count > $1.count : ac > bc
        }
    }

    private static func leerCatalogo() -> [AplicacionMac] {
        let fm = FileManager.default
        var porClave: [String: AplicacionMac] = [:]
        var rutasVistas = Set<String>()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        for raiz in raices where fm.fileExists(atPath: raiz.path) {
            guard let e = fm.enumerator(at: raiz, includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                guard url.pathExtension.lowercased() == "app" else { continue }
                e.skipDescendants()
                let ruta = url.standardizedFileURL.path
                guard rutasVistas.insert(ruta).inserted, let bundle = Bundle(url: url) else { continue }
                let info = bundle.infoDictionary ?? [:]
                let localizado = bundle.localizedInfoDictionary ?? [:]
                let nombre = (localizado["CFBundleDisplayName"] as? String)
                    ?? (localizado["CFBundleName"] as? String)
                    ?? (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let bid = bundle.bundleIdentifier ?? ""
                guard !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let app = AplicacionMac(nombre: nombre, bundleId: bid, ruta: ruta,
                                        alias: aliases(nombre: nombre, bundleId: bid))
                let clave = bid.isEmpty ? ruta.lowercased() : bid.lowercased()
                // Ante duplicados (p. ej. una copia .old), conserva la ruta más corta
                // y no expone dos resultados idénticos al reconocimiento por voz.
                if let previa = porClave[clave], previa.ruta.count <= ruta.count { continue }
                porClave[clave] = app
            }
        }
        return porClave.values.sorted {
            $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
        }
    }

    static func todas() -> [AplicacionMac] {
        lock.lock()
        if let cache, let fechaCache, Date().timeIntervalSince(fechaCache) < vigencia {
            lock.unlock(); return cache
        }
        lock.unlock()
        let nuevas = leerCatalogo()
        lock.lock()
        cache = nuevas; fechaCache = Date()
        lock.unlock()
        return nuevas
    }

    @discardableResult static func refrescar() -> [AplicacionMac] {
        lock.lock(); cache = nil; fechaCache = nil; lock.unlock()
        return todas()
    }

    static func precalentar() {
        DispatchQueue.global(qos: .utility).async { _ = todas() }
    }

    /// Resuelve la aplicación usando el prefijo más largo. Exacto primero; fuzzy
    /// conservador después. Si dos apps empatan, devuelve ambas: nunca adivina.
    static func resolverPrefijo(_ tokens: [String], en catalogo: [AplicacionMac]? = nil,
                                permitirDifuso: Bool = true) -> ResultadoAplicacionMac {
        let entrada = tokens.map(normalizar).filter { !$0.isEmpty }
        guard !entrada.isEmpty else { return .ninguna }
        let apps = catalogo ?? todas()
        var exactos: [Candidato] = []
        for app in apps {
            for alias in app.alias {
                let a = alias.split(separator: " ").map(String.init)
                guard !a.isEmpty, a.count <= entrada.count,
                      Array(entrada.prefix(a.count)) == a else { continue }
                exactos.append(Candidato(app: app, n: a.count, score: 1, exacta: true))
            }
        }
        if !exactos.isEmpty {
            let maxN = exactos.map(\.n).max() ?? 1
            let mejores = unicos(exactos.filter { $0.n == maxN })
            let m = mejores.map { CoincidenciaAplicacionMac(app: $0.app,
                palabrasConsumidas: $0.n, confianza: 1, exacta: true) }
            return m.count == 1 ? .encontrada(m[0]) : .ambiguas(m)
        }

        guard permitirDifuso else { return .ninguna }
        var difusos: [Candidato] = []
        for app in apps {
            for alias in app.alias {
                let a = alias.split(separator: " ").map(String.init)
                guard !a.isEmpty, a.count <= entrada.count else { continue }
                let b = Array(entrada.prefix(a.count))
                let scores = zip(a, b).map { ModoFuzzy.similitud($0, $1) }
                guard scores.allSatisfy({ $0 >= 0.72 }) else { continue }
                let score = scores.reduce(0, +) / Double(scores.count)
                if score >= 0.84 { difusos.append(Candidato(app: app, n: a.count, score: score, exacta: false)) }
            }
        }
        guard let mejorScore = difusos.map(\.score).max() else { return .ninguna }
        let cercanos = unicos(difusos.filter { mejorScore - $0.score < 0.04 })
            .sorted { $0.score > $1.score }
        let matches = cercanos.map { CoincidenciaAplicacionMac(app: $0.app,
            palabrasConsumidas: $0.n, confianza: $0.score, exacta: false) }
        return matches.count == 1 ? .encontrada(matches[0]) : .ambiguas(matches)
    }

    private static func unicos(_ candidatos: [Candidato]) -> [Candidato] {
        var vistos = Set<String>()
        return candidatos.filter { candidato in
            let clave = candidato.app.bundleId.isEmpty
                ? candidato.app.ruta.lowercased() : candidato.app.bundleId.lowercased()
            return vistos.insert(clave).inserted
        }
    }

    static func aplicar(_ match: CoincidenciaAplicacionMac, a base: Modo) -> Modo {
        var modo = base
        modo.nombre = "Aplicación · \(match.app.nombre)"
        modo.appNombre = match.app.nombre
        modo.appBundleId = match.app.bundleId
        modo.appRuta = match.app.ruta
        return modo
    }

    /// Resuelve únicamente contra el catálogo actual. Aunque alguien edite
    /// modos.json, una ruta externa que no corresponda a un .app inventariado no abre.
    static func resolver(_ modo: Modo) -> AplicacionMac? {
        let apps = todas()
        if !modo.appBundleId.isEmpty,
           let app = apps.first(where: { $0.bundleId.caseInsensitiveCompare(modo.appBundleId) == .orderedSame }) {
            return app
        }
        if !modo.appRuta.isEmpty {
            return apps.first { $0.ruta == URL(fileURLWithPath: modo.appRuta).standardizedFileURL.path }
        }
        return nil
    }
}
