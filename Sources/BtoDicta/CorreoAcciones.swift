import AppKit
import Foundation

// MARK: - Correo II: marcar, mover, papelera y adjuntos (spec 019, fase 2)
//
// Lo común a Microsoft y Google. Los adjuntos van a ~/Downloads/BtoDicta sin
// sobrescribir y NUNCA se abren solos (pueden traer algo dañino): se muestran
// en el Finder.

struct AdjuntoCorreo: Equatable {
    let nombre: String
    let datos: Data
}

enum MarcaCorreo: String, CaseIterable {
    case leido, noLeido, destacado, sinDestacar

    /// La marca pedida en palabras («leído», «no leído», «importante», «quita la estrella»…). Puro.
    static func desde(_ texto: String) -> MarcaCorreo? {
        let t = PerfilAgente.normalizar(texto)
        let quita = t.contains("quita") || t.contains("sin ") || t.contains("desmarca") || t.hasPrefix("no ")
            || t.contains(" no ")
        if t.contains("destac") || t.contains("estrella") || t.contains("importante") || t.contains("seguimiento") || t.contains("bandera") {
            return quita ? .sinDestacar : .destacado
        }
        if t.contains("no leido") || t.contains("sin leer") || t.contains("no lei") { return .noLeido }
        if t.contains("leido") || t.contains("lei") { return .leido }
        return nil
    }

    var hablado: String {
        switch self {
        case .leido: return "como leído"
        case .noLeido: return "como no leído"
        case .destacado: return "como destacado"
        case .sinDestacar: return "sin destacar"
        }
    }
}

enum CorreoAcciones {
    static var carpetaDescargas: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("BtoDicta", isDirectory: true)
    }

    /// Nombre seguro para un adjunto que viene de afuera: sin rutas, sin ocultos, sin vacíos. Puro.
    static func nombreSeguro(_ nombre: String) -> String {
        let base = (nombre as NSString).lastPathComponent
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)).joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
        return base.isEmpty ? "adjunto" : String(base.prefix(150))
    }

    /// Guarda sin sobrescribir («informe.pdf», «informe-2.pdf»…). Devuelve dónde quedó.
    static func guardar(_ a: AdjuntoCorreo, en dir: URL = carpetaDescargas) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let n = nombreSeguro(a.nombre)
        let ext = (n as NSString).pathExtension, raiz = (n as NSString).deletingPathExtension
        var u = dir.appendingPathComponent(n)
        var i = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(raiz)-\(i)" : "\(raiz)-\(i).\(ext)"); i += 1
        }
        try a.datos.write(to: u, options: .withoutOverwriting)
        // Cuarentena de macOS: al abrirlo, Gatekeeper lo revisa como cualquier descarga.
        var v = URLResourceValues()
        v.quarantineProperties = [kLSQuarantineAgentNameKey as String: "BtoDicta",
                                  kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String]
        var marcado = u
        try? marcado.setResourceValues(v)
        return u
    }

    /// La carpeta o etiqueta que nombra el usuario: exacta, luego la que la contiene. Puro.
    static func elegirCarpeta(_ pedida: String, entre nombres: [(id: String, nombre: String)]) -> (id: String, nombre: String)? {
        let p = PerfilAgente.normalizar(pedida)
        guard !p.isEmpty else { return nil }
        return nombres.first { PerfilAgente.normalizar($0.nombre) == p }
            ?? nombres.first { PerfilAgente.normalizar($0.nombre).contains(p) }
            ?? nombres.first { p.contains(PerfilAgente.normalizar($0.nombre)) && $0.nombre.count >= 3 }
    }

    /// Archivo para adjuntar: la ruta dada, o el más reciente de Descargas o Escritorio. Máx. 3 MB.
    static func archivoParaAdjuntar(_ pista: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let p = (pista.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        // Solo de Descargas, Escritorio o Documentos, con la ruta real (sin atajos simbólicos).
        if p.hasPrefix("/") {
            let u = URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL
            return permitido(u, home: home) && FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        let carpetas = ["Downloads", "Desktop"].map { home.appendingPathComponent($0) }
        let candidatos = carpetas.flatMap { c -> [URL] in
            ((try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                           options: [.skipsHiddenFiles])) ?? [])
                .map { $0.resolvingSymlinksInPath() }
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && permitido($0, home: home) }
        }
        let fecha: (URL) -> Date = { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        if !p.isEmpty, let c = candidatos.filter({ PerfilAgente.normalizar($0.lastPathComponent).contains(PerfilAgente.normalizar(p)) })
            .max(by: { fecha($0) < fecha($1) }) { return c }
        return p.isEmpty ? candidatos.max { fecha($0) < fecha($1) } : nil
    }

    static let maximoAdjunto = 3 * 1024 * 1024

    /// Carpetas desde las que se puede adjuntar (ruta ya resuelta). Puro.
    static func permitido(_ u: URL, home: URL) -> Bool {
        let real = home.resolvingSymlinksInPath().standardizedFileURL.path
        return ["Downloads", "Desktop", "Documents"].contains { u.standardizedFileURL.path.hasPrefix(real + "/" + $0 + "/") }
    }

    /// Claves, certificados y carpetas ocultas nunca se adjuntan (ni por error ni por un texto malicioso). Puro.
    static func archivoSensible(_ u: URL) -> Bool {
        let ext = u.pathExtension.lowercased()
        if ["p12", "pfx", "pem", "key", "p8", "keychain", "keychain-db", "kdbx", "env", "ovpn", "ppk"].contains(ext) { return true }
        let n = u.lastPathComponent.lowercased()
        if n.hasPrefix("id_rsa") || n.hasPrefix("id_ed25519") || n.hasPrefix("id_ecdsa") || n == ".env" { return true }
        return u.standardizedFileURL.pathComponents.contains { $0.hasPrefix(".") && $0.count > 1 }
    }
}
