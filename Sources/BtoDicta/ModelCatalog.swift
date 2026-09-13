import Foundation

// MARK: - Catálogo de modelos Whisper locales descargables (whisper.cpp GGML)

struct WhisperModelo: Identifiable {
    var id: String { archivo }
    let nombre: String
    let archivo: String
    let tamañoMB: Int
    let nota: String
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(archivo)")! }
    var localURL: URL { WhisperLocal.modelsDir.appendingPathComponent(archivo) }
    var descargado: Bool { FileManager.default.fileExists(atPath: localURL.path) }
}

// MARK: - Modelos exóticos (motor llama.cpp: Voxtral y futuros)

/// Modelo local que necesita el motor llama.cpp (no whisper-cli): puede
/// requerir varios archivos (pesos + proyector de audio).
struct ExoticoModelo: Identifiable {
    var id: String { nombre }
    let nombre: String
    let repo: String               // repo de HuggingFace
    let archivos: [String]         // [pesos, mmproj]
    let tamañosMB: [Int]           // esperado por archivo (valida descargas a medias)
    let nota: String

    var tamañoMB: Int { tamañosMB.reduce(0, +) }
    var urls: [URL] { archivos.map { URL(string: "https://huggingface.co/\(repo)/resolve/main/\($0)")! } }
    var localURLs: [URL] { archivos.map { VoxtralServer.modelsDir.appendingPathComponent($0) } }

    /// Descargado DE VERDAD: existe, pesa lo esperado (±5%) y es GGUF válido.
    /// Un archivo a medias (descarga interrumpida) no cuenta como descargado.
    var descargado: Bool {
        zip(localURLs, tamañosMB).allSatisfy { Self.esGGUFValido($0, esperadoMB: $1) }
    }

    static func esGGUFValido(_ url: URL, esperadoMB: Int) -> Bool {
        // MB decimales (como los reporta HuggingFace), no MiB.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int,
              bytes >= Int(Double(esperadoMB) * 0.95) * 1_000_000 else { return false }
        guard let h = try? FileHandle(forReadingFrom: url),
              let magic = try? h.read(upToCount: 4) else { return false }
        try? h.close()
        return magic == Data("GGUF".utf8)
    }
}

// MARK: - Modelos del motor transcribe.cpp (el de Handy: Nemotron/Parakeet/Canary)

struct TcppModelo: Identifiable {
    var id: String { archivo }
    let nombre: String
    let repo: String
    let archivo: String
    let tamañoMB: Int
    let nota: String

    var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(archivo)")! }
    var localURL: URL { TranscribeCpp.modelsDir.appendingPathComponent(archivo) }
    var descargado: Bool { ExoticoModelo.esGGUFValido(localURL, esperadoMB: tamañoMB) }
}

enum ModelCatalog {
    // Familias del motor transcribe.cpp (GGUF de handy-computer, verificados).
    // Cada familia tiene su propio proveedor en la cascada.

    static let nemotron: [TcppModelo] = [
        TcppModelo(nombre: "Nemotron 3.5 Streaming 0.6B",
                   repo: "handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf",
                   archivo: "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf",
                   tamañoMB: 751,
                   nota: "NVIDIA · 40 idiomas · liviano y muy rápido (32x)"),
    ]

    static let canary: [TcppModelo] = [
        TcppModelo(nombre: "Canary 1B Flash",
                   repo: "handy-computer/canary-1b-flash-gguf",
                   archivo: "canary-1b-flash-Q8_0.gguf",
                   tamañoMB: 1048,
                   nota: "NVIDIA · en/es/de/fr · el más veloz (93x) · solo por lotes"),
    ]

    static let voxtralRealtime: [TcppModelo] = [
        TcppModelo(nombre: "Voxtral Realtime 4B",
                   repo: "handy-computer/Voxtral-Mini-4B-Realtime-2602-gguf",
                   archivo: "Voxtral-Mini-4B-Realtime-2602-Q4_K_M.gguf",
                   tamañoMB: 2830,
                   nota: "Mistral · idioma automático · el mejor con siglas"),
    ]

    /// Modelos que corren con llama.cpp (audio multimodal). Verificados en HF.
    static let exoticos: [ExoticoModelo] = [
        ExoticoModelo(nombre: "Voxtral Mini 3B",
                      repo: "ggml-org/Voxtral-Mini-3B-2507-GGUF",
                      archivos: ["Voxtral-Mini-3B-2507-Q4_K_M.gguf",
                                 "mmproj-Voxtral-Mini-3B-2507-Q8_0.gguf"],
                      tamañosMB: [2473, 716],
                      nota: "Mistral · entiende contexto, multilingüe · pide llama.cpp"),
    ]

    /// Modelos Whisper que corren en nuestro whisper-cli (GGML). Verificados.
    static let whisper: [WhisperModelo] = [
        WhisperModelo(nombre: "Tiny", archivo: "ggml-tiny.bin", tamañoMB: 74,
                      nota: "El más liviano y rápido · calidad básica"),
        WhisperModelo(nombre: "Base", archivo: "ggml-base.bin", tamañoMB: 141,
                      nota: "Liviano · buen equilibrio para máquinas modestas"),
        WhisperModelo(nombre: "Small", archivo: "ggml-small.bin", tamañoMB: 465,
                      nota: "Calidad media · rápido"),
        WhisperModelo(nombre: "Medium", archivo: "ggml-medium.bin", tamañoMB: 1462,
                      nota: "Buena calidad · más lento"),
        WhisperModelo(nombre: "Large v3 Turbo", archivo: "ggml-large-v3-turbo.bin", tamañoMB: 1549,
                      nota: "La mejor relación calidad/velocidad · recomendado"),
        WhisperModelo(nombre: "Large v3", archivo: "ggml-large-v3.bin", tamañoMB: 3095,
                      nota: "Máxima calidad · pesado y lento"),
    ]
}
