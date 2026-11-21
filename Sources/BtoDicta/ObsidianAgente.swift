import Foundation

// MARK: - Obsidian (spec 021)
//
// Anotar y buscar en la bóveda del usuario. BtoDicta escribe SOLO en su carpeta
// propia (`BtoDicta/Notas de voz/`), nunca en las notas del usuario. Al buscar,
// nunca manda a la IA notas de credenciales ni líneas que parezcan claves.

enum ObsidianAgente {
    /// La bóveda configurada o, si no, la que Obsidian tiene abierta.
    static func boveda(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let dada = Config.obsidianBoveda().trimmingCharacters(in: .whitespaces)
        if !dada.isEmpty {
            let u = URL(fileURLWithPath: (dada as NSString).expandingTildeInPath, isDirectory: true)
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        let cfg = home.appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let d = try? Data(contentsOf: cfg),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let vs = j["vaults"] as? [String: [String: Any]] else { return nil }
        let lista = vs.values.compactMap { v -> (String, Bool, Double)? in
            guard let p = v["path"] as? String else { return nil }
            return (p, (v["open"] as? Bool) ?? false, (v["ts"] as? Double) ?? 0)
        }
        guard let mejor = lista.sorted(by: { ($0.1 ? 1 : 0, $0.2) > ($1.1 ? 1 : 0, $1.2) }).first else { return nil }
        let u = URL(fileURLWithPath: mejor.0, isDirectory: true)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: Anotar

    /// Añade la nota a «BtoDicta/Notas de voz/AAAA-MM-DD.md» (la crea si no existe). Devuelve el archivo.
    @discardableResult
    static func anotar(_ texto: String, en boveda: URL, ahora: Date = Date()) throws -> URL {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw NSError(domain: "BtoDicta", code: 1) }
        let dir = boveda.appendingPathComponent("BtoDicta/Notas de voz", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = DateFormatter(); fd.dateFormat = "yyyy-MM-dd"
        let fh = DateFormatter(); fh.dateFormat = "HH:mm"
        let u = dir.appendingPathComponent(fd.string(from: ahora) + ".md")
        let linea = "- \(fh.string(from: ahora)) — \(t.replacingOccurrences(of: "\n", with: " "))\n"
        if let h = try? FileHandle(forWritingTo: u) {
            h.seekToEndOfFile(); h.write(Data(linea.utf8)); try? h.close()
        } else {
            let cabecera = "---\nfecha: \(fd.string(from: ahora))\nautor: agente (BtoDicta)\ntipo: notas-de-voz\n---\n\n# Notas de voz — \(fd.string(from: ahora))\n\n"
            try (cabecera + linea).write(to: u, atomically: true, encoding: .utf8)
        }
        return u
    }

    // MARK: Buscar

    struct Hallazgo: Equatable { let archivo: URL; let titulo: String; let extracto: String }

    /// ¿La nota es de credenciales o secretos? Nunca va a la IA (puro).
    static func esSensible(ruta: String, texto: String) -> Bool {
        let r = PerfilAgente.normalizar(ruta)
        if r.contains("credencial") || r.contains("secreto") || r.contains("password") || r.contains("clave") { return true }
        let cab = texto.hasPrefix("---") ? String(texto.prefix(600)).lowercased() : ""
        return cab.contains("contiene_secretos: sí") || cab.contains("contiene_secretos: si") || cab.contains("tipo: credencial")
            || cab.contains("sensible")
    }

    /// Quita líneas que parecen claves, tokens o contraseñas (puro).
    static func sinSecretos(_ texto: String) -> String {
        let marcas = ["clave", "password", "contraseña", "contrasena", "token", "secret", "api key", "apikey", "<code>",
                      "pin", "passphrase", "private key", "-----begin"]
        return texto.split(separator: "\n", omittingEmptySubsequences: false).filter { l in
            let n = l.lowercased()
            return !marcas.contains { n.contains($0) }
        }.joined(separator: "\n")
    }

    /// Candidatas por Spotlight (rápido, ya indexado); nil si Spotlight no responde.
    static func candidatasSpotlight(_ palabras: [String], en boveda: URL) -> [URL]? {
        let p = Process(), salida = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        // Cada palabra como término propio; sin comillas ni operadores del usuario.
        p.arguments = ["-onlyin", boveda.path] + palabras.map { $0.filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
        p.standardOutput = salida; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let d = salida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let urls = String(decoding: d, as: UTF8.self).split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            .filter { $0.pathExtension == "md" && !$0.pathComponents.contains { $0.hasPrefix(".") } }
        return urls.isEmpty ? nil : urls
    }

    /// Las notas que contienen todas las palabras (por nombre o contenido), las más recientes primero.
    /// Primero por Spotlight; si no trae nada, recorre la bóveda (solo lo que ya está en el Mac).
    static func buscar(_ consulta: String, en boveda: URL, maximo: Int = 4) -> [Hallazgo] {
        let palabras = PerfilAgente.normalizar(consulta).split(separator: " ").map(String.init)
            .filter { $0.count > 3 && !["sobre", "donde", "tengo", "nota", "notas", "obsidian", "busca", "decidimos"].contains($0) }
        guard !palabras.isEmpty else { return [] }
        if let c = candidatasSpotlight(palabras, en: boveda) {
            let r = filtrar(c, palabras: palabras, boveda: boveda, maximo: maximo)
            if !r.isEmpty { return r }
        }
        guard let e = FileManager.default.enumerator(at: boveda, includingPropertiesForKeys: [.contentModificationDateKey,
                                                     .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var todas: [URL] = []
        for case let u as URL in e where u.pathExtension == "md" {
            todas.append(u)
            if todas.count > 20000 { break }
        }
        return filtrar(todas, palabras: palabras, boveda: boveda, maximo: maximo)
    }

    private static func filtrar(_ urls: [URL], palabras: [String], boveda: URL, maximo: Int) -> [Hallazgo] {
        var res: [(Hallazgo, Date)] = []
        for u in urls {
            // Solo lo que ya está en el Mac: leer un archivo que vive solo en la nube lo descargaría.
            if let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
               v.isUbiquitousItem == true, v.ubiquitousItemDownloadingStatus != .current { continue }
            guard let t = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let rel = String(u.path.dropFirst(boveda.path.count))
            guard !esSensible(ruta: rel, texto: t) else { continue }
            let n = PerfilAgente.normalizar(rel + " " + t)
            guard palabras.allSatisfy({ n.contains($0) }) else { continue }
            let fecha = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            res.append((Hallazgo(archivo: u, titulo: u.deletingPathExtension().lastPathComponent,
                                 extracto: String(sinSecretos(t).prefix(1500))), fecha))
        }
        return res.sorted { $0.1 > $1.1 }.prefix(maximo).map(\.0)
    }
}
