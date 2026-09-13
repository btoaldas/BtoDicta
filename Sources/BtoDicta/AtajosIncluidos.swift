import AppKit
import Foundation

/// Instaladores de Atajos que viajan dentro del bundle de BtoDicta.
///
/// macOS exige una importación visible por cada `.shortcut`: BtoDicta abre el
/// paquete firmado, pero nunca pulsa «Añadir atajo» ni cambia sus permisos. El
/// Atajo Universal evita distribuir decenas de automatizaciones redundantes;
/// las recetas internas se despachan a través de ese único contrato.
enum AtajoIncluidoID: String, CaseIterable, Identifiable {
    case asistente, universal, musica

    var id: String { rawValue }
}

struct AtajoIncluidoInfo: Identifiable {
    let id: AtajoIncluidoID
    let nombre: String
    let detalle: String
    let riesgo: RiesgoAtajoApple
    let requiereScripts: Bool
}

enum AtajosIncluidos {
    static let recursoAsistente = "BtoDicta · Escuchar asistente"
    static let nombreUniversal = "BtoDicta Universal"
    // El nombre físico debe ser ASCII: los volúmenes HFS de los DMG normalizan
    // los acentos y eso invalida el sello de recursos de codesign. El nombre
    // visible del Atajo sigue siendo «BtoDicta · Reproducir música».
    static let recursoMusica = "BtoDicta-Reproducir-musica"

    static func info(_ id: AtajoIncluidoID, nombreAgente: String) -> AtajoIncluidoInfo {
        switch id {
        case .asistente:
            let nombre = PasarelaSiriBeto.nombreSugerido(nombreAgente)
            return .init(id: id, nombre: nombre,
                         detalle: "Siri abre un turno limpio con «\(nombre)». No ejecuta acciones por sí solo.",
                         riesgo: .reversible, requiereScripts: true)
        case .universal:
            return .init(id: id, nombre: nombreUniversal,
                         detalle: "Un único puente para música, calendario, recordatorios, apps, HomeKit, capturas y recetas.",
                         riesgo: .externo, requiereScripts: true)
        case .musica:
            return .init(id: id, nombre: AppleAtajos.nombreMusicaIncluido,
                         detalle: "Busca una canción en tu biblioteca de Apple Music y reproduce una coincidencia.",
                         riesgo: .reversible, requiereScripts: false)
        }
    }

    static func nombreEsperado(_ id: AtajoIncluidoID, nombreAgente: String) -> String {
        info(id, nombreAgente: nombreAgente).nombre
    }

    static func estaInstalado(_ id: AtajoIncluidoID, nombreAgente: String,
                              nombres: [String]) -> Bool {
        let esperado = PerfilAgente.normalizar(nombreEsperado(id, nombreAgente: nombreAgente))
        return !esperado.isEmpty && nombres.contains {
            PerfilAgente.normalizar($0) == esperado
        }
    }

    private static func nombreRecurso(_ id: AtajoIncluidoID) -> String {
        switch id {
        case .asistente: return recursoAsistente
        case .universal: return nombreUniversal
        case .musica: return recursoMusica
        }
    }

    /// El fallback `Resources/` permite ejecutar los hooks desde `swift build`;
    /// una app distribuida siempre resuelve el recurso dentro de su bundle.
    static func paquete(_ id: AtajoIncluidoID) -> URL? {
        let nombre = nombreRecurso(id)
        if let u = Bundle.main.url(forResource: nombre, withExtension: "shortcut") {
            return u
        }
        let desarrollo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(nombre).appendingPathExtension("shortcut")
        return FileManager.default.fileExists(atPath: desarrollo.path) ? desarrollo : nil
    }

    private static func nombreArchivoSeguro(_ nombre: String) -> String {
        let prohibidos = CharacterSet(charactersIn: "/:\\\0\n\r\t")
        let limpio = nombre.unicodeScalars.map { prohibidos.contains($0) ? "-" : String($0) }
            .joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return String((limpio.isEmpty ? "BtoDicta" : limpio).prefix(60)) + ".shortcut"
    }

    /// Renombrar el archivo firmado no modifica su contenido ni su firma. Apple
    /// usa ese nombre como propuesta al importarlo, por eso la pasarela puede
    /// llamarse Gloria, Jarvis o cualquier nombre configurado sin hardcodearlo.
    static func paqueteParaInstalar(_ id: AtajoIncluidoID,
                                    nombreAgente: String) -> URL? {
        guard let origen = paquete(id) else { return nil }
        guard id == .asistente else { return origen }

        _ = Config.agentePasarelaSiriToken()
        Config.asegurarDirSeguro()
        let fm = FileManager.default
        let dir = Config.dir.appendingPathComponent("instaladores-atajos", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let destino = dir.appendingPathComponent(
                nombreArchivoSeguro(nombreEsperado(id, nombreAgente: nombreAgente)))
            if fm.fileExists(atPath: destino.path) { try fm.removeItem(at: destino) }
            try fm.copyItem(at: origen, to: destino)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
            return destino
        } catch {
            return nil
        }
    }

    static func instalar(_ id: AtajoIncluidoID,
                         nombreAgente: String) -> ResultadoHerramientaApple {
        guard Thread.isMainThread else {
            return .init(ok: false, mensaje: "Abre el instalador desde la interfaz de BtoDicta.")
        }
        guard let paquete = paqueteParaInstalar(id, nombreAgente: nombreAgente) else {
            return .init(ok: false, mensaje: "No encontré el instalador incluido de este Atajo.")
        }
        guard NSWorkspace.shared.open(paquete) else {
            return .init(ok: false, mensaje: "No pude abrir el instalador en Atajos.")
        }
        let nombre = nombreEsperado(id, nombreAgente: nombreAgente)
        return .init(ok: true,
                     mensaje: "Atajos abrió «\(nombre)». Revisa sus acciones y confirma «Añadir atajo».")
    }
}
