import Foundation

// MARK: - Cuarentena de proveedores STT que fallan de forma DETERMINISTA
//
// Un 4xx de configuración (key inválida, sin cuota, parámetro deprecado…) va a
// repetirse igual en la próxima llamada: no tiene sentido pegarle otra vez. Sin esto,
// la bitácora golpeaba a AssemblyAI ~25 veces por minuto con el mismo 400 (2 873
// llamadas fallidas en dos días, ago-2026), sumando latencia a CADA dictado antes de
// caer al siguiente motor.
//
// Reglas (revisadas): 401/402/403/404 → 30 min · 400 por parámetro/modelo → 30 min,
// pero 400 por ESTE audio (corto/corrupto) → 2 min · 413/415/422 (del archivo, no del
// proveedor) → nada · 429 → 5 min · 5xx → 2 min. Un OK la limpia al instante, y
// cambiar la key o la cascada la limpia toda. Avisa UNA vez por cuarentena.

/// Clasificador compartido: ¿el fallo es «no hay internet» (-1009 / -1020)?
/// Con ese diagnóstico ninguna cascada de nube tiene sentido: se corta de una
/// y se va al motor local o al texto original, con una sola línea de registro.
enum SinConexion {
    static func es(_ error: Error?) -> Bool {
        guard let e = error as? URLError else { return false }
        return e.code == .notConnectedToInternet || e.code == .dataNotAllowed
    }
}

enum CuarentenaSTT {
    private struct Entrada { let hasta: Date; let codigo: Int; let causa: String }
    private static var tabla: [String: Entrada] = [:]
    private static let lock = NSLock()

    static func activa(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let e = tabla[id] {
            if e.hasta > Date() { return true }
            tabla[id] = nil
        }
        return false
    }

    /// Para el error final si TODA la cadena quedó en cuarentena: causa y hora de fin.
    static func detalle(_ id: String) -> (codigo: Int, texto: String)? {
        lock.lock(); defer { lock.unlock() }
        guard let e = tabla[id], e.hasta > Date() else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return (e.codigo, "en cuarentena hasta \(f.string(from: e.hasta)) — \(e.causa)")
    }

    static func registrar(_ id: String, nombre: String, error: Error) {
        guard case ScribeError.http(let code, let body) = error else { return }
        let b = body.lowercased()
        let minutos: Double
        switch code {
        case 401, 402, 403, 404:
            minutos = 30
        case 400:
            // ¿Es de configuración (parámetro/modelo) o de ESTE audio (corto, corrupto)?
            let esConfig = ["param", "deprecat", "model", "invalid", "unsupported", "unknown"].contains { b.contains($0) }
            let esAudio = ["audio", "file", "duration", "too short", "empty", "format"].contains { b.contains($0) }
            minutos = (esConfig && !esAudio) ? 30 : 2
        case 413, 415, 422:
            return   // culpa del archivo, no del proveedor
        case 429:
            minutos = 5
        case 500...599:
            minutos = 2
        default:
            return
        }
        let causa = String(body.replacingOccurrences(of: "\n", with: " ").prefix(90))
        lock.lock()
        tabla[id] = Entrada(hasta: Date().addingTimeInterval(minutos * 60), codigo: code, causa: causa)
        lock.unlock()
        Log.log(.ia, "failover: \(nombre) en cuarentena \(Int(minutos)) min por HTTP \(code) (\(causa)) — se salta hasta entonces")
    }

    static func limpiar(_ id: String) {
        lock.lock(); tabla[id] = nil; lock.unlock()
    }

    /// Al cambiar una key o la cascada: lo que estaba mal ya puede estar bien.
    static func limpiarTodo() {
        lock.lock(); tabla.removeAll(); lock.unlock()
    }
}
