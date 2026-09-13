import Foundation

// MARK: - STT en vivo de NUBE (WebSocket) — protocolo común + fábrica
//
// Varios proveedores nube nuevos soportan transcripción EN VIVO por WebSocket,
// cada uno con su protocolo. Se unifican tras este protocolo para que el carril
// en vivo del AppDelegate (entregaVivo / conmutación en caliente / cierre) sea
// UNO solo, sin duplicar ramas por proveedor. Los que NO tienen WS en vivo
// (Hugging Face, Cloudflare, Fireworks serverless, OpenAI/Groq/Mistral) siguen
// transcribiendo por lotes al soltar la tecla.

protocol LiveNubeSTT: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var conectado: Bool { get }
    /// Conecta y confirma (o falla) por el completion. `model` = modelo elegido.
    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void)
    func send(chunk: Data)       // PCM16 16 kHz mono crudo
    func finalizar()             // pedir el cierre y los finales pendientes
    func fullText() -> String    // texto final acumulado
    func disconnect()
}

enum LiveNube {
    /// Proveedores nube con STT en vivo (WebSocket) → su variable de key.
    static let soportan: [String: String] = [
        "deepgram": "DEEPGRAM_API_KEY",
        "soniox": "SONIOX_API_KEY",
        "assemblyai": "ASSEMBLYAI_API_KEY",
        "speechmatics": "SPEECHMATICS_API_KEY",
        "gladia": "GLADIA_API_KEY",
    ]

    /// ¿Este proveedor puede ir EN VIVO ahora? (soporta WS + flag ON + key).
    static func disponible(_ id: String) -> Bool {
        guard Config.sttStreaming(), let env = soportan[id], !ApiKeys.get(env).isEmpty else { return false }
        return true
    }

    /// Crea el cliente en vivo del proveedor (o nil si no tiene).
    static func cliente(_ id: String) -> LiveNubeSTT? {
        switch id {
        case "deepgram":     return DeepgramStreamClient()
        case "soniox":       return SonioxStreamClient()
        case "assemblyai":   return AssemblyAIStreamClient()
        case "speechmatics": return SpeechmaticsStreamClient()
        case "gladia":       return GladiaLiveClient()
        default:             return nil
        }
    }
}
