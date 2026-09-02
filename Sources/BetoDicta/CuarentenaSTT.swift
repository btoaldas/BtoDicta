import Foundation

// MARK: - Cuarentena de proveedores STT que fallan de forma DETERMINISTA
//
// Un 4xx (key inválida, sin cuota, parámetro deprecado…) va a repetirse igual en la
// próxima llamada: no tiene sentido pegarle otra vez. Sin esto, la bitácora golpeaba a
// AssemblyAI ~25 veces por minuto con el mismo 400 (2 873 llamadas fallidas en dos
// días, ago-2026), sumando latencia a CADA dictado antes de caer al siguiente motor.
//
// Regla: 4xx → se salta el proveedor 30 min; 429 → 5 min; 5xx → 2 min. Un OK lo
// limpia al instante. Avisa UNA sola vez por cuarentena (nada de spam en el log).

enum CuarentenaSTT {
    private static var hasta: [String: Date] = [:]
    private static let lock = NSLock()

    static func activa(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let h = hasta[id] {
            if h > Date() { return true }
            hasta[id] = nil
        }
        return false
    }

    static func registrar(_ id: String, nombre: String, error: Error) {
        guard case ScribeError.http(let code, let body) = error else { return }
        let minutos: Double
        switch code {
        case 400...428, 430...499: minutos = 30
        case 429: minutos = 5
        case 500...599: minutos = 2
        default: return
        }
        lock.lock(); hasta[id] = Date().addingTimeInterval(minutos * 60); lock.unlock()
        let resumen = body.replacingOccurrences(of: "\n", with: " ").prefix(90)
        Log.log(.ia, "failover: \(nombre) en cuarentena \(Int(minutos)) min por HTTP \(code) (\(resumen)) — se salta hasta entonces")
    }

    static func limpiar(_ id: String) {
        lock.lock(); hasta[id] = nil; lock.unlock()
    }
}
