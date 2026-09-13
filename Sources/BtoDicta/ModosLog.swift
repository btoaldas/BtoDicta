import Foundation
import AppKit

// MARK: - Registro DETALLADO del subsistema de Modos (para analizar y mejorar)
//
// Escribe una línea JSON por evento en ~/.btodicta/logs/modos.jsonl (JSONL, fácil
// de analizar). Captura cada decisión: por voz/cadena/contexto/semántico, el modo
// resuelto, args, score del semántico, resolución de contactos de WhatsApp, etc.
// Así, con el tiempo, se ve qué reconoció bien y qué no, y se mejora con DATOS.
// 100% local, 0600 (contiene texto dictado). Parametrizable (Config.logModos).

enum ModosLog {
    private static let lock = NSLock()
    private static var url: URL {
        let dir = Config.dir.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("modos.jsonl")
    }

    static func registrar(_ evento: String, _ datos: [String: Any]) {
        guard Config.logModos() else { return }
        var o = datos
        o["ev"] = evento
        o["t"] = Date().timeIntervalSince1970
        o["fecha"] = ModosLog.iso(Date())
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return }
        let linea = Data((s + "\n").utf8)
        lock.lock(); defer { lock.unlock() }
        Config.asegurarDirSeguro()
        let u = url
        if let fh = try? FileHandle(forWritingTo: u) {
            fh.seekToEndOfFile(); fh.write(linea); try? fh.close()
        } else {
            try? linea.write(to: u, options: .atomic)
            Config.protegerSecreto(u)
        }
    }

    private static func iso(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: d)
    }

    static func abrir() { NSWorkspace.shared.open(url) }
}
