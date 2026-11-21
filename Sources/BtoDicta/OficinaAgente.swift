import AppKit
import Foundation
import PDFKit

// MARK: - Oficina (spec 019, fase 5)
//
// Leer documentos que ya existen, resumir una página web, abrir sesiones de IA
// en un proyecto y preparar una firma. Todo lo leído es DATO no confiable. La
// firma nunca la hace BtoDicta: solo abre el PDF en FirmaEC, y firma el titular.

enum OficinaAgente {
    // MARK: Leer documentos

    static let extensionesDocumento: Set<String> = ["docx", "doc", "rtf", "odt", "pdf", "xlsx", "csv", "txt", "md", "pages"]

    /// La ruta dada o el documento más reciente (o el que contiene el nombre) de Descargas,
    /// Escritorio o Documentos. Rutas reales y solo de esas carpetas.
    static func documentoParaLeer(_ pista: String, extensiones: Set<String> = extensionesDocumento,
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let p = (pista.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if p.hasPrefix("/") {
            let u = URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL
            return CorreoAcciones.permitido(u, home: home) && extensiones.contains(u.pathExtension.lowercased())
                && FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        let fm = FileManager.default
        var candidatos: [URL] = []
        for c in ["Downloads", "Desktop", "Documents", "Documents/BtoDicta"].map({ home.appendingPathComponent($0) }) {
            candidatos += ((try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: [.contentModificationDateKey],
                                                        options: [.skipsHiddenFiles])) ?? [])
                .map { $0.resolvingSymlinksInPath() }
                .filter { extensiones.contains($0.pathExtension.lowercased()) && CorreoAcciones.permitido($0, home: home) }
        }
        let fecha: (URL) -> Date = { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        let n = PerfilAgente.normalizar(p)
        let filtrados = n.isEmpty ? candidatos : candidatos.filter {
            let nombre = PerfilAgente.normalizar($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " "))
            return n.split(separator: " ").filter { $0.count > 2 }.allSatisfy { nombre.contains($0) }
        }
        return filtrados.max { fecha($0) < fecha($1) }
    }

    /// Texto de un documento (máx. `maximo` caracteres).
    static func leer(_ u: URL, maximo: Int = 12000) -> String {
        let ext = u.pathExtension.lowercased()
        var t = ""
        switch ext {
        case "pdf":
            t = PDFDocument(url: u)?.string ?? ""
        case "xlsx":
            t = textoDeXLSX(u)
        case "csv", "txt", "md":
            t = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1)) ?? ""
        default:   // docx, doc, rtf, odt, pages (textutil de macOS)
            t = ejecutar("/usr/bin/textutil", ["-convert", "txt", "-stdout", u.path])
        }
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximo))
    }

    private static func ejecutar(_ bin: String, _ args: [String]) -> String {
        let p = Process(), salida = Pipe()
        p.executableURL = URL(fileURLWithPath: bin); p.arguments = args
        p.standardOutput = salida; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let d = salida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }

    /// Hojas de un Excel como texto con tabuladores (sin fórmulas ni formato).
    static func textoDeXLSX(_ u: URL) -> String {
        let compartidas = cadenasCompartidas(ejecutar("/usr/bin/unzip", ["-p", u.path, "xl/sharedStrings.xml"]))
        let lista = ejecutar("/usr/bin/unzip", ["-Z1", u.path]).split(separator: "\n")
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted()
        return lista.prefix(5).enumerated().map { i, hoja in
            "Hoja \(i + 1):\n" + filasDeHoja(ejecutar("/usr/bin/unzip", ["-p", u.path, String(hoja)]), compartidas: compartidas)
                .map { $0.joined(separator: "\t") }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// Textos de sharedStrings.xml (puro).
    static func cadenasCompartidas(_ xml: String) -> [String] {
        partes(xml, "<si>", "</si>").map { si in partes(si, "<t", "</t>").map { t in
            let s = t.firstIndex(of: ">").map { String(t[t.index(after: $0)...]) } ?? t
            return desescapar(s)
        }.joined() }
    }

    /// Filas de una hoja (puro): valores en orden; las celdas de texto compartido se resuelven.
    static func filasDeHoja(_ xml: String, compartidas: [String]) -> [[String]] {
        partes(xml, "<row", "</row>").prefix(400).map { fila in
            partes(fila, "<c ", "</c>").map { celda -> String in
                let cab = String(celda.prefix(while: { $0 != ">" }))
                let v = partes(celda, "<v>", "</v>").first.map(desescapar) ?? ""
                if cab.contains("t=\"s\""), let i = Int(v), compartidas.indices.contains(i) { return compartidas[i] }
                if cab.contains("t=\"inlineStr\"") {
                    return partes(celda, "<t", "</t>").map { t in
                        desescapar(t.firstIndex(of: ">").map { String(t[t.index(after: $0)...]) } ?? t)
                    }.joined()
                }
                return v
            }
        }.filter { !$0.allSatisfy(\.isEmpty) }
    }

    private static func partes(_ s: String, _ abre: String, _ cierra: String) -> [String] {
        var res: [String] = [], resto = s[...]
        while let a = resto.range(of: abre), let c = resto.range(of: cierra, range: a.upperBound..<resto.endIndex) {
            res.append(String(resto[a.upperBound..<c.lowerBound])); resto = resto[c.upperBound...]
        }
        return res
    }

    private static func desescapar(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Página web

    /// Solo http(s) públicas: nada de la red local ni del propio equipo. Puro.
    static func urlPublica(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), let esquema = u.scheme?.lowercased(), ["http", "https"].contains(esquema),
              var host = u.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        guard host.contains(".") else { return nil }
        // Hosts numéricos solo en forma canónica de 4 octetos decimales («127.1» o «0x7f.0.0.1» no).
        let etiquetas = host.split(separator: ".", omittingEmptySubsequences: false)
        if etiquetas.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isHexDigit || $0 == "x" } }),
           etiquetas.contains(where: { $0.first?.isNumber == true }) {
            guard etiquetas.count == 4, etiquetas.allSatisfy({ e in e.allSatisfy(\.isNumber) && (Int(e) ?? 999) <= 255
                && !(e.count > 1 && e.hasPrefix("0")) }) else { return nil }
        }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.hasSuffix(".internal") { return nil }
        let o = host.split(separator: ".").compactMap { Int($0) }
        if o.count == 4, ipPrivada(o) { return nil }
        if host.contains(":") { return nil }   // IPv6 literal
        return u
    }

    /// IPv4 de uso no público: propia, privada, enlace local, CGNAT, multidifusión o reservada. Puro.
    static func ipPrivada(_ o: [Int]) -> Bool {
        guard o.count == 4 else { return true }
        return o[0] == 0 || o[0] == 10 || o[0] == 127 || (o[0] == 169 && o[1] == 254) || (o[0] == 192 && o[1] == 168)
            || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 100 && (64...127).contains(o[1])) || o[0] >= 224
            || (o[0] == 198 && (18...19).contains(o[1])) || (o[0] == 192 && o[1] == 0 && (o[2] == 0 || o[2] == 2))
            || (o[0] == 198 && o[1] == 51 && o[2] == 100) || (o[0] == 203 && o[1] == 0 && o[2] == 113)
    }

    /// IPv6 de uso no público (propia, enlace local, única local, multidifusión, IPv4 incrustada). Puro.
    static func ipv6Privada(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return true }
        if b.allSatisfy({ $0 == 0 }) || (b[0..<15].allSatisfy { $0 == 0 } && b[15] == 1) { return true }
        if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }
        if (b[0] & 0xfe) == 0xfc || b[0] == 0xff { return true }
        if b[0..<10].allSatisfy({ $0 == 0 }) && ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0)) {
            return ipPrivada(b[12..<16].map(Int.init))
        }
        // NAT64 (64:ff9b::/96 con la IPv4 al final; 64:ff9b:1::/48 local) y 6to4 (2002::/16 con la IPv4 en los bytes 2–5).
        if b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b {
            if b[4] == 0 && b[5] == 1 { return true }
            return ipPrivada(b[12..<16].map(Int.init))
        }
        if b[0] == 0x20 && b[1] == 0x02 { return ipPrivada(b[2..<6].map(Int.init)) }
        return false
    }

    /// Resuelve el nombre y exige que TODAS sus direcciones sean públicas (evita nombres que apuntan a la red local).
    static func hostResuelvePublico(_ host: String) -> Bool {
        var pistas = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                              ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &pistas, &res) == 0, let primero = res else { return false }
        defer { freeaddrinfo(primero) }
        var p: UnsafeMutablePointer<addrinfo>? = primero, alguna = false
        while let a = p {
            if a.pointee.ai_family == AF_INET, let sa = a.pointee.ai_addr {
                let v = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if ipPrivada([Int(v >> 24), Int((v >> 16) & 255), Int((v >> 8) & 255), Int(v & 255)]) { return false }
                alguna = true
            } else if a.pointee.ai_family == AF_INET6, let sa = a.pointee.ai_addr {
                let b = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s -> [UInt8] in
                    withUnsafeBytes(of: s.pointee.sin6_addr) { Array($0) }
                }
                if ipv6Privada(b) { return false }
                alguna = true
            }
            p = a.pointee.ai_next
        }
        return alguna
    }

    /// Texto visible de una página HTML (puro y sencillo).
    static func textoDeHTML(_ html: String, maximo: Int = 12000) -> String {
        var s = html
        for etiqueta in ["script", "style", "noscript", "svg", "head"] {
            while let a = s.range(of: "<\(etiqueta)", options: .caseInsensitive),
                  let c = s.range(of: "</\(etiqueta)>", options: .caseInsensitive, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<c.upperBound)
            }
        }
        s = s.replacingOccurrences(of: "<br", with: "\n<br", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = desescapar(s).replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\n\\s*", with: "\n", options: .regularExpression)
        return String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximo))
    }

    /// Descarga la página (GET, 15 s, máx. 3 MB) y devuelve su texto. En main.
    static func leerPagina(_ u: URL, fin: @escaping (String?) -> Void) {
        var req = URLRequest(url: u); req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (Macintosh) BtoDicta", forHTTPHeaderField: "User-Agent")
        DispatchQueue.global(qos: .userInitiated).async {
            guard let h = u.host, hostResuelvePublico(h) else { DispatchQueue.main.async { fin(nil) }; return }
            let lector = Lector(fin: fin)
            let sesion = URLSession(configuration: .ephemeral, delegate: lector, delegateQueue: nil)
            sesion.dataTask(with: req).resume()
            sesion.finishTasksAndInvalidate()
        }
    }

    /// IP remota de verdad (la de la conexión hecha), por si el nombre cambió de dirección entre la revisión y la conexión.
    static func direccionPublica(_ texto: String?) -> Bool {
        guard var t = texto, !t.isEmpty else { return false }
        if let i = t.firstIndex(of: "%") { t = String(t[..<i]) }   // zona IPv6
        var a4 = in_addr(), a6 = in6_addr()
        if inet_pton(AF_INET, t, &a4) == 1 {
            let v = UInt32(bigEndian: a4.s_addr)
            return !ipPrivada([Int(v >> 24), Int((v >> 16) & 255), Int((v >> 8) & 255), Int(v & 255)])
        }
        if inet_pton(AF_INET6, t, &a6) == 1 { return !ipv6Privada(withUnsafeBytes(of: a6) { Array($0) }) }
        return false
    }

    /// Junta la respuesta (máx. 3 MB), revisa cada redirección y la IP real de cada conexión.
    private final class Lector: NSObject, URLSessionDataDelegate {
        private var datos = Data(), codigo = 0, remotaPublica = true
        private let fin: (String?) -> Void
        init(fin: @escaping (String?) -> Void) { self.fin = fin }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let u = request.url, let v = OficinaAgente.urlPublica(u.absoluteString), let h = v.host,
                  OficinaAgente.hostResuelvePublico(h) else { completionHandler(nil); return }
            completionHandler(request)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            codigo = (response as? HTTPURLResponse)?.statusCode ?? 0
            completionHandler(codigo == 200 ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            datos.append(data)
            if datos.count > 3_000_000 { dataTask.cancel() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            remotaPublica = metrics.transactionMetrics.filter { $0.remoteAddress != nil }
                .allSatisfy { OficinaAgente.direccionPublica($0.remoteAddress) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let ok = error == nil && codigo == 200 && remotaPublica && datos.count <= 3_000_000
            let t = ok ? (String(data: datos, encoding: .utf8) ?? String(data: datos, encoding: .isoLatin1)) : nil
            if !remotaPublica { Log.write("página descartada: la conexión fue a una dirección no pública") }
            let f = fin
            DispatchQueue.main.async { f(t.map { OficinaAgente.textoDeHTML($0) }) }
        }
    }

    // MARK: Sesiones de IA

    /// Carpeta del proyecto que nombra el usuario dentro de ~/Developer (o ~/Projects). Puro salvo el listado.
    static func carpetaProyecto(_ nombre: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let n = PerfilAgente.normalizar(nombre).replacingOccurrences(of: " ", with: "")
        guard !n.isEmpty else { return nil }
        let raices = ["Developer", "Projects", "Proyectos"].map { home.appendingPathComponent($0) }
        let todas = raices.flatMap { r in
            ((try? FileManager.default.contentsOfDirectory(at: r, includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        let clave: (URL) -> String = { PerfilAgente.normalizar($0.lastPathComponent).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") }
        return todas.first { clave($0) == n } ?? todas.first { clave($0).contains(n) } ?? todas.first { n.contains(clave($0)) && clave($0).count >= 4 }
    }

    enum SesionIA: String { case claudeCode, codex, claude, chatgpt, gemini
        /// La herramienta que nombra el usuario (puro).
        static func desde(_ t: String) -> SesionIA? {
            let n = PerfilAgente.normalizar(t)
            if n.contains("claude code") || n.contains("cloud code") { return .claudeCode }
            if n.contains("codex") { return .codex }
            if n.contains("chatgpt") || n.contains("chat gpt") || n.contains("openai") { return .chatgpt }
            if n.contains("gemini") { return .gemini }
            if n.contains("claude") || n.contains("cloud") { return .claude }
            return nil
        }
        var nombre: String {
            switch self { case .claudeCode: return "Claude Code"; case .codex: return "Codex"; case .claude: return "Claude"
            case .chatgpt: return "ChatGPT"; case .gemini: return "Gemini" }
        }
    }

    /// Abre la sesión. Las de terminal (Claude Code, Codex) se abren en la carpeta del proyecto.
    @discardableResult
    static func abrirSesion(_ s: SesionIA, en carpeta: URL?) -> Bool {
        switch s {
        case .claudeCode, .codex:
            let dir = carpeta ?? FileManager.default.homeDirectoryForCurrentUser
            let orden = s == .claudeCode ? "claude" : "codex"
            let guion = FileManager.default.temporaryDirectory.appendingPathComponent("btodicta-\(orden)-\(UUID().uuidString.prefix(6)).command")
            let ruta = dir.path.replacingOccurrences(of: "'", with: "'\\''")
            let texto = "#!/bin/zsh -l\ncd '\(ruta)' && \(orden)\n"
            guard (try? texto.write(to: guion, atomically: true, encoding: .utf8)) != nil else { return false }
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: guion.path)
            return NSWorkspace.shared.open(guion)
        case .claude, .chatgpt:
            let app = URL(fileURLWithPath: "/Applications/\(s == .claude ? "Claude" : "ChatGPT").app")
            if FileManager.default.fileExists(atPath: app.path) { NSWorkspace.shared.open(app); return true }
            return NSWorkspace.shared.open(URL(string: s == .claude ? "https://claude.ai/new" : "https://chatgpt.com/")!)
        case .gemini:
            return NSWorkspace.shared.open(URL(string: "https://gemini.google.com/app")!)
        }
    }

    // MARK: Firma

    /// App de firma oficial instalada (FirmaEC), si hay.
    static var appFirma: URL? {
        ["FirmaEC", "FirmaECTransversal"].map { URL(fileURLWithPath: "/Applications/\($0).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
