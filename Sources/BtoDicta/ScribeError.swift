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

/// Algunos motores locales representan el silencio con un token textual. Ese
/// token no es un dictado y nunca debe llegar al pulido, al portapapeles ni al
/// historial como si fueran palabras del usuario.
enum TextoTranscrito {
    static func limpiar(_ texto: String) -> String {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = limpio.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let marcadores = [
            "(empty)", "[empty]", "<empty>", "[blank_audio]",
            "<|nospeech|>", "<|no_speech|>", "(silence)", "[silence]",
        ]
        return marcadores.contains(n) ? "" : limpio
    }
}
