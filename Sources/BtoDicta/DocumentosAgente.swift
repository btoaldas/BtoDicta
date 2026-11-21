import AppKit
import Foundation

// MARK: - Herramientas deterministas del asistente (spec 017, fase 3)
//
// La IA solo aporta los datos (asunto, destinatario, cuerpo, filas); el formato
// lo pone BtoDicta con plantillas fijas. La numeración de un documento nunca la
// inventa nadie: queda «N.° ____» para el usuario o su sistema oficial.

enum DocumentosAgente {
    static var carpeta: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("BtoDicta", isDirectory: true)
    }

    // MARK: Word con plantilla

    static let tipos: [String: String] = ["memo": "MEMORANDO", "memorando": "MEMORANDO", "oficio": "OFICIO",
                                          "informe": "INFORME", "carta": "CARTA", "documento": ""]

    /// HTML del documento (puro, probado). `tipo`: memo, oficio, informe, carta o documento.
    static func html(tipo: String, asunto: String, para: String?, de: String?, cuerpo: String,
                     fecha: Date = Date()) -> String {
        let t = tipos[PerfilAgente.normalizar(tipo)] ?? ""
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        func e(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var h = "<html><head><meta charset=\"utf-8\"></head><body style=\"font-family: Arial; font-size: 11pt;\">"
        if !t.isEmpty {
            h += "<p style=\"text-align:center\"><b>\(t)" + (t == "INFORME" || t == "CARTA" ? "" : " N.° ____") + "</b></p>"
        }
        h += "<p style=\"text-align:right\">\(e(f.string(from: fecha)))</p>"
        if let para, !para.isEmpty { h += "<p><b>PARA:</b> \(e(para))</p>" }
        if let de, !de.isEmpty { h += "<p><b>DE:</b> \(e(de))</p>" }
        if !asunto.isEmpty { h += "<p><b>ASUNTO:</b> \(e(asunto))</p>" }
        h += "<hr>"
        for parrafo in cuerpo.components(separatedBy: "\n\n") {
            let p = parrafo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { h += "<p style=\"text-align:justify\">\(e(p).replacingOccurrences(of: "\n", with: "<br>"))</p>" }
        }
        if t != "INFORME", !t.isEmpty { h += "<p><br>Atentamente,</p><p><br><br>____________________</p>" }
        return h + "</body></html>"
    }

    /// Nombre de archivo nuevo, sin sobrescribir nunca.
    static func nombreLibre(_ base: String, extension ext: String, en dir: URL, fecha: Date = Date()) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmm"
        let limpio = base.folding(options: [.diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            .prefix(6).joined(separator: "_")
        let raiz = (limpio.isEmpty ? "Documento" : limpio) + "_" + f.string(from: fecha)
        var u = dir.appendingPathComponent(raiz).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent("\(raiz)-\(n)").appendingPathExtension(ext); n += 1
        }
        return u
    }

    /// Crea el .docx con textutil (de macOS) y lo abre. En main.
    static func crearDocumento(tipo: String, asunto: String, para: String?, de: String?, cuerpo: String,
                               abrir: Bool = true, fin: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                let destino = nombreLibre("\(tipo) \(asunto)", extension: "docx", en: carpeta)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
                try html(tipo: tipo, asunto: asunto, para: para, de: de, cuerpo: cuerpo)
                    .write(to: tmp, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                p.arguments = ["-convert", "docx", tmp.path, "-output", destino.path]
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: destino.path) else {
                    throw NSError(domain: "BtoDicta", code: 1, userInfo: [NSLocalizedDescriptionKey: "No pude crear el Word."])
                }
                DispatchQueue.main.async {
                    if abrir { NSWorkspace.shared.open(destino) }
                    fin(.success(destino))
                }
            } catch { DispatchQueue.main.async { fin(.failure(error)) } }
        }
    }

    // MARK: Hoja de cálculo

    /// CSV con BOM (Excel lo abre con tildes bien); los campos con coma o comillas van entre comillas.
    static func csv(_ filas: [[String]]) -> String {
        "\u{FEFF}" + filas.map { fila in
            fila.map { original in
                // Una celda que empieza con = + - @ sería una fórmula para Excel: va como texto.
                // Los números puros («-5», «10.5») se dejan como números.
                let peligroso = original.first.map { "=+-@\t\r".contains($0) } ?? false
                let c = peligroso && Double(original) == nil ? "'" + original : original
                return
                c.contains(",") || c.contains("\"") || c.contains("\n") || c != original
                    ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c
            }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    static func crearHoja(titulo: String, filas: [[String]], abrir: Bool = true) throws -> URL {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let destino = nombreLibre(titulo.isEmpty ? "Tabla" : titulo, extension: "csv", en: carpeta)
        try csv(filas).write(to: destino, atomically: true, encoding: .utf8)
        if abrir {
            let excel = URL(fileURLWithPath: "/Applications/Microsoft Excel.app")
            if FileManager.default.fileExists(atPath: excel.path) {
                NSWorkspace.shared.open([destino], withApplicationAt: excel, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(destino)
            }
        }
        return destino
    }

    // MARK: Historial de dictados

    struct DictadoEncontrado: Equatable { let fecha: Date; let texto: String }

    /// Busca en los dictados de los últimos `dias` días los que contienen todas las palabras.
    static func buscarHistorial(_ consulta: String, dias: Int = 60, ahora: Date = Date(),
                                dir: URL = HistoryWriter.historyDir) -> [DictadoEncontrado] {
        let palabras = PerfilAgente.normalizar(consulta).split(separator: " ").map(String.init).filter { $0.count > 2 }
        guard !palabras.isEmpty else { return [] }
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd/HH-mm-ss"
        var res: [DictadoEncontrado] = []
        for d in 0..<max(1, min(365, dias)) {
            guard let dia = cal.date(byAdding: .day, value: -d, to: ahora) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: dia)
            let carpetaDia = dir.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            let urls = (try? FileManager.default.contentsOfDirectory(at: carpetaDia, includingPropertiesForKeys: nil)) ?? []
            for u in urls.filter(HistoryWriter.esTextoPrincipal).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                guard let t = try? String(contentsOf: HistoryWriter.textoPreferidoURL(para: u), encoding: .utf8) else { continue }
                let n = PerfilAgente.normalizar(t)
                guard palabras.allSatisfy({ n.contains($0) }) else { continue }
                let rel = String(format: "%04d/%02d/%02d/", c.year!, c.month!, c.day!) + u.deletingPathExtension().lastPathComponent
                res.append(DictadoEncontrado(fecha: f.date(from: rel) ?? dia, texto: t))
                if res.count >= 5 { return res }
            }
        }
        return res
    }

    static func historialHablado(_ r: [DictadoEncontrado]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d 'a las' HH:mm"
        return r.prefix(3).map { d in
            let t = d.texto.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return "el \(f.string(from: d.fecha)): «\(t.count > 140 ? String(t.prefix(140)) + "…" : t)»"
        }.joined(separator: "; ")
    }

    // MARK: Archivo para transcribir

    static let extensionesAudio: Set<String> = ["m4a", "mp3", "wav", "aac", "ogg", "opus", "flac", "mp4", "mov", "m4v", "caf", "aiff"]

    /// La ruta dada si es audio o video; si no, el más reciente de Descargas o Escritorio.
    static func archivoParaTranscribir(_ pista: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let p = (pista.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if p.hasPrefix("/") {
            // Solo de Descargas, Escritorio o Documentos, con la ruta real.
            let u = URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL
            return extensionesAudio.contains(u.pathExtension.lowercased()) && CorreoAcciones.permitido(u, home: home)
                && FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        let carpetas = ["Downloads", "Desktop"].map { home.appendingPathComponent($0) }
        let candidatos = carpetas.flatMap { c in
            ((try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { extensionesAudio.contains($0.pathExtension.lowercased()) }
        }
        return candidatos.max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
    }
}
