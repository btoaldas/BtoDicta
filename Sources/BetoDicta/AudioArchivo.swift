import Foundation
import AVFoundation

/// Todos los contenedores llegan al mismo contrato STT: WAV PCM16, mono, 16 kHz.
/// No modifica el original, no usa micrófono y no envía nada a la red.
enum AudioArchivo {
    enum Fallo: LocalizedError {
        case detalle(String)
        var errorDescription: String? {
            if case .detalle(let texto) = self { return texto }
            return nil
        }
    }
    static let maxPCM = 512 * 1024 * 1024

    static func normalizar(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw Fallo.detalle("Selecciona un archivo local, no una dirección de red.") }
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw Fallo.detalle("No se puede leer el archivo seleccionado.")
        }
        do { return try nativo(url) }
        catch {
            // Ogg y códecs que macOS no entiende pueden usar un ffmpeg ya instalado.
            // No se descarga ni instala nada, y tampoco se deriva a ElevenLabs.
            guard let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw error }
            return try alternativo(url, ejecutable: ffmpeg)
        }
    }

    private static func nativo(_ url: URL) throws -> Data {
        // La pista debe vivir dentro del contenedor elegido, no en URLs referidas.
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
        ])
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw Fallo.detalle("El archivo no contiene una pista de audio compatible con macOS.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw Fallo.detalle("No se puede decodificar la pista de audio.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Fallo.detalle("No se pudo abrir el audio.") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var pcm = Data()
        let limite = Date().addingTimeInterval(180)
        while let sample = output.copyNextSampleBuffer() {
            guard Date() < limite else { throw Fallo.detalle("La conversión local excedió 3 minutos.") }
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(buffer)
            guard count > 0 else { continue }
            guard count <= maxPCM - pcm.count else {
                throw Fallo.detalle("El audio convertido supera 512 MB; divídelo en partes.")
            }
            var bloque = Data(count: count)
            let status = bloque.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: count, destination: $0.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw Fallo.detalle("No se pudo decodificar el audio completo.") }
            pcm.append(bloque)
        }
        guard reader.status == .completed else { throw reader.error ?? Fallo.detalle("El audio está incompleto o dañado.") }
        guard !pcm.isEmpty else { throw Fallo.detalle("El archivo no contiene muestras de audio.") }
        return wav(pcm)
    }

    private static func alternativo(_ url: URL, ejecutable: String) throws -> Data {
        let temporal = FileManager.default.temporaryDirectory.appendingPathComponent("betodicta-audio-\(UUID().uuidString).pcm")
        // Solo se retira este derivado efímero de esta operación, nunca la fuente.
        defer { try? FileManager.default.removeItem(at: temporal) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ejecutable)
        task.arguments = ["-nostdin", "-v", "error", "-protocol_whitelist", "file",
                          "-i", url.path, "-map", "0:a:0", "-vn",
                          "-ac", "1", "-ar", "16000", "-f", "s16le", "-fs", String(maxPCM + 2), temporal.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let fin = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in fin.signal() }
        try task.run()
        guard fin.wait(timeout: .now() + 180) == .success else {
            task.terminate()
            task.waitUntilExit()
            throw Fallo.detalle("La conversión local excedió 3 minutos.")
        }
        guard task.terminationStatus == 0 else {
            throw Fallo.detalle("No se pudo convertir el archivo localmente; comprueba su formato o pista de audio.")
        }
        let pcm = try Data(contentsOf: temporal, options: .mappedIfSafe)
        guard !pcm.isEmpty, pcm.count <= maxPCM else {
            throw Fallo.detalle("Audio vacío o convertido mayor de 512 MB; divídelo en partes.")
        }
        return wav(pcm)
    }

    static func wav(_ pcm: Data) -> Data {
        var result = Data()
        func u16(_ x: UInt16) { var n = x.littleEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
        func u32(_ x: UInt32) { var n = x.littleEndian; withUnsafeBytes(of: &n) { result.append(contentsOf: $0) } }
        result.append(contentsOf: "RIFF".utf8); u32(UInt32(pcm.count + 36))
        result.append(contentsOf: "WAVEfmt ".utf8); u32(16); u16(1); u16(1)
        u32(16000); u32(32000); u16(2); u16(16)
        result.append(contentsOf: "data".utf8); u32(UInt32(pcm.count)); result.append(pcm)
        return result
    }

    typealias ResultadoSTT = Result<(String, String, String), Error>
    typealias Motor = (Data, @escaping (ResultadoSTT) -> Void) -> Void

    static func transcribir(_ url: URL,
                            motor: @escaping Motor = { wav, fin in Failover.transcribe(wav: wav, completion: fin) },
                            completion: @escaping (ResultadoSTT) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let wav = try normalizar(url)
                DispatchQueue.main.async {
                    Log.log(.ia, "archivo: normalizado localmente a WAV mono 16 kHz, \(wav.count) bytes → cascada STT")
                    motor(wav) { r in DispatchQueue.main.async { completion(r) } }
                }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
}
