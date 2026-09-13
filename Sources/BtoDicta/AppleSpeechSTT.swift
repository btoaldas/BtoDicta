import Foundation
import AVFoundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Apple Speech nativo (voz → texto, 100% on-device, macOS 26+)
//
// Usa la API NUEVA de macOS 26 (Tahoe): SpeechAnalyzer + SpeechTranscriber
// (framework Speech). Gratis, sin API key, sin red — el mismo motor que usa
// VoiceInk ("Apple Speech · Built in · On-Device"). Reemplaza a SFSpeechRecognizer.
//
// Se integra como UN proveedor más del catálogo STT (id "apple_speech"), con
// failover: si la máquina no es macOS 26, o el idioma no tiene su modelo bajado,
// falla suave y la cascada pasa al siguiente proveedor. NUNCA bloquea.
//
// Modo actual: BATCH de archivo (transcribe el wav grabado al soltar la tecla).
// El streaming en vivo (parciales) es una sub-fase futura (misma API con
// analyzer.start(inputSequence:) + [.volatileResults]).

enum AppleSpeechSTT {

    enum Error: Swift.Error, LocalizedError {
        case sinSoporte        // macOS < 26
        case idiomaNoSoportado
        case assetsNoListos     // el modelo del idioma no está bajado (y no se pudo bajar ya)
        case sinAudio
        case timeout
        var errorDescription: String? {
            switch self {
            case .sinSoporte: return "Apple Speech requiere macOS 26 o superior."
            case .idiomaNoSoportado: return "Apple Speech no soporta ese idioma."
            case .assetsNoListos: return "El modelo de idioma de Apple Speech no está descargado todavía."
            case .sinAudio: return "Apple Speech no recibió audio."
            case .timeout: return "Apple Speech tardó demasiado."
            }
        }
    }

    /// ¿Está disponible en esta máquina? (macOS 26 con el framework).
    static var disponible: Bool {
        if #available(macOS 26, *) {
            #if canImport(Speech)
            return true
            #else
            return false
            #endif
        }
        return false
    }

    /// Transcribe un wav (batch). Bridge async→completion para encajar en la
    /// cascada de `TranscribeProviders`.
    static func run(wav: Data, idioma: String? = nil,
                    completion: @escaping (Result<String, Swift.Error>) -> Void) {
        guard disponible else { completion(.failure(Error.sinSoporte)); return }
        #if canImport(Speech)
        if #available(macOS 26, *) {
            let lang = idioma ?? Config.appleSpeechIdioma()
            Task {
                do {
                    let texto = try await transcribir(wav: wav, idioma: lang)
                    completion(.success(texto))
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            completion(.failure(Error.sinSoporte))
        }
        #else
        completion(.failure(Error.sinSoporte))
        #endif
    }

    #if canImport(Speech)
    @available(macOS 26, *)
    private static func transcribir(wav: Data, idioma: String) async throws -> String {
        // 1) wav en Data → archivo temporal (AVAudioFile necesita URL). Se auto-convierte.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-apple-\(UInt64(wav.count)).wav")
        try wav.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let audioFile = try AVAudioFile(forReading: tmp)
        let dur = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        // 2) Idioma: es-EC no existe en la lista de Apple → se mapea al español
        //    más cercano (es-ES/es-MX/es-US) automáticamente.
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: idioma)) else {
            throw Error.idiomaNoSoportado
        }
        let transcriber = SpeechTranscriber(locale: loc, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [])

        // 3) Assets del idioma: si no están, intentar bajarlos on-demand (una vez).
        //    Si no se pueden dejar listos, fallar → la cascada usa otro proveedor.
        try await asegurarAssets(transcriber)

        // 4) Reservar el locale (límite del sistema; si falla pero ya está bajado, seguimos).
        await reservarSiHaceFalta(loc, transcriber)

        // 5) Analizar el archivo completo. Recolectar el texto de results en paralelo.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let recolector = Task<String, Swift.Error> {
            var t = ""
            for try await r in transcriber.results { t += String(r.text.characters) }
            return t
        }
        do {
            if let ultimo = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: ultimo)
            } else {
                recolector.cancel()
                await analyzer.cancelAndFinishNow()
                throw Error.sinAudio
            }
        } catch {
            recolector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        // 6) Esperar el texto con tope (audio largo = más margen).
        let tope = max(20.0, dur * 4.0 + 10.0)
        return try await conTimeout(recolector, segundos: tope)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deja listos los assets del idioma: si faltan, dispara la descarga y espera.
    @available(macOS 26, *)
    private static func asegurarAssets(_ transcriber: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .supported, .downloading:
            // Bajar e instalar (lo gestiona el sistema). Una sola vez por idioma.
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await req.downloadAndInstall()
            }
            // Re-chequear: si sigue sin instalar, avisar para failover.
            if await AssetInventory.status(forModules: [transcriber]) != .installed {
                throw Error.assetsNoListos
            }
        case .unsupported:
            throw Error.idiomaNoSoportado
        @unknown default:
            throw Error.assetsNoListos
        }
    }

    @available(macOS 26, *)
    private static func reservarSiHaceFalta(_ loc: Locale, _ transcriber: SpeechTranscriber) async {
        let reservados = await AssetInventory.reservedLocales
        if reservados.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return }
        _ = try? await AssetInventory.reserve(locale: loc)
    }

    /// Espera el resultado de una Task con un tope de tiempo.
    private static func conTimeout(_ tarea: Task<String, Swift.Error>, segundos: Double) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { grupo in
            grupo.addTask { try await tarea.value }
            grupo.addTask {
                try await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                throw Error.timeout
            }
            defer { grupo.cancelAll() }
            guard let primero = try await grupo.next() else { throw Error.sinAudio }
            return primero
        }
    }
    #endif
}
