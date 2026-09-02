import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Errores

enum ScribeError: LocalizedError {
    case sinApiKey, http(Int, String), sinTexto, ws(String)

    var errorDescription: String? {
        switch self {
        case .sinApiKey: return "Falta la API key del proveedor — ponla en Configuración → Modelos"
        // Error COMPARTIDO por todos los proveedores HTTP (Groq, AssemblyAI, Deepgram…):
        // sin nombre de marca, si no el log culpa a ElevenLabs de fallos ajenos.
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(120))"
        case .sinTexto: return "Respuesta sin texto"
        case .ws(let message): return "Streaming: \(message)"
        }
    }
}

