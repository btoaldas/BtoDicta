import Foundation
import CryptoKit

enum PoliticaPulido {
    /// Presupuesto de pared por proveedor. Incluye contexto (instrucciones y
    /// glosario), no solo dictado. Los largos conservan hasta dos minutos.
    static func espera(texto: Int, contexto: Int, base: Double = 8) -> TimeInterval {
        min(120, max(5, base) + Double(max(0, texto - 500)) / 90
            + Double(max(0, contexto - 3000)) / 400)
    }
}

/// Estado efímero: no desactiva proveedores ni reordena la configuración.
/// Una credencial/modelo diferente obtiene otra identidad sin guardar secretos.
final class CuarentenaPulido {
    static let compartida = CuarentenaPulido()
    private let lock = NSLock()
    private var hasta: [String: Date] = [:]
    private var nubeHasta = Date.distantPast

    static func identidad(_ ia: ChatIA) -> String {
        let credencial = SHA256.hash(data: Data((ia.key ?? "").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "\(ia.id)|\(ia.base)|\(ia.modeloEfectivo)|\(credencial)"
    }

    static func duracion(codigo: Int, cuerpo: String, error: Error?) -> TimeInterval {
        if let e = error as? URLError {
            if e.code == .cancelled { return 0 }
            return 15
        }
        let b = cuerpo.lowercased()
        if ["insufficient_quota", "quota_exceeded", "insufficient balance",
            "insufficient_balance", "credit balance", "payment required", "billing_hard_limit"]
            .contains(where: { b.contains($0) }) { return 1800 }
        switch codigo {
        case 401, 402, 403, 404: return 1800
        case 429: return 60
        case 500...599: return 30
        default: return 0 // Un texto demasiado largo no invalida al proveedor.
        }
    }

    func activa(_ identidad: String, local: Bool, ahora: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !local && nubeHasta > ahora { return true }
        guard let fin = hasta[identidad] else { return false }
        if fin > ahora { return true }
        hasta[identidad] = nil
        return false
    }

    @discardableResult
    func registrar(_ identidad: String, local: Bool, codigo: Int, cuerpo: String,
                   error: Error?, ahora: Date = Date()) -> TimeInterval {
        let segundos = Self.duracion(codigo: codigo, cuerpo: cuerpo, error: error)
        guard segundos > 0 else { return 0 }
        lock.lock(); defer { lock.unlock() }
        hasta[identidad] = ahora.addingTimeInterval(segundos)
        if !local && SinConexion.es(error) { nubeHasta = ahora.addingTimeInterval(15) }
        return segundos
    }

    func limpiar(_ identidad: String) {
        lock.lock(); defer { lock.unlock() }
        hasta[identidad] = nil
    }
}

/// URLSession.timeoutInterval mide inactividad, no siempre tiempo total.
/// Este límite cancela la operación y entrega exactamente una respuesta, en main.
enum PeticionPulido {
    static func ejecutar(_ request: URLRequest, session: URLSession = .shared,
                         completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        var terminado = false // Acceso exclusivamente en la cola principal.
        var limite: DispatchWorkItem?
        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard !terminado else { return }
                terminado = true
                limite?.cancel()
                completion(data, response, error)
            }
        }
        let alarma = DispatchWorkItem {
            guard !terminado else { return }
            terminado = true
            task.cancel()
            completion(nil, nil, URLError(.timedOut))
        }
        limite = alarma
        DispatchQueue.main.asyncAfter(deadline: .now() + request.timeoutInterval, execute: alarma)
        task.resume()
    }
}
