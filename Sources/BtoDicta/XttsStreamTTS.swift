import Foundation
import AVFoundation

// MARK: - Clon local XTTS por STREAMING (suena mientras genera) — Fase asistente por voz
//
// No es WebSocket (es 100% local): corre el motor interno con inference_stream, que
// entrega el audio POR TROZOS conforme genera. BtoDicta lee esos trozos (PCM float32
// @24000Hz mono por stdout) y los encola en un AVAudioPlayerNode → el 1er sonido sale
// en ~1-2s en vez de esperar todo el wav. Mismo efecto que el WS de ElevenLabs, local.
//
// Parametrizable POR VOZ (VozLocal.streaming). Falla suave: si el proceso muere sin
// audio, completion(false) y Voz.decir cae al batch / siguiente motor.

final class XttsStreamTTS: NSObject {
    static var activo: XttsStreamTTS?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private var proceso: Process?
    private var resto = Data()          // bytes sueltos (< 4) entre lecturas
    private var recibioAudio = false
    private var onPCM: ((Data) -> Void)?
    private var reproducir = false
    private var done: ((Bool) -> Void)?
    private var terminado = false

    /// Corta el streaming local en curso de raíz (proceso python + audio). Para Cancelar.
    static func cancelar() {
        guard let c = activo else { return }
        c.terminado = true
        c.proceso?.terminationHandler = nil
        c.proceso?.terminate(); c.proceso = nil
        c.player.stop(); c.engine.stop(); c.done = nil
        activo = nil
    }

    /// Habla en vivo por los parlantes (streaming).
    static func hablar(paquete: URL, texto: String, completion: @escaping (Bool) -> Void) {
        let c = XttsStreamTTS(); activo = c; c.reproducir = true
        c.correr(paquete: paquete, texto: texto, completion: completion)
    }

    /// Captura el PCM a un WAV (para pruebas). No reproduce.
    static func capturarWav(paquete: URL, texto: String, salida: URL, completion: @escaping (Bool) -> Void) {
        let c = XttsStreamTTS(); activo = c
        var f32 = Data()
        c.onPCM = { f32.append($0) }
        c.correr(paquete: paquete, texto: texto) { ok in
            if ok, !f32.isEmpty {
                let pcm16 = floatABytesInt16(f32)
                try? WavIO.escribir(pcm16: pcm16, sampleRate: 24000, a: salida)
            }
            completion(ok && !f32.isEmpty)
        }
    }

    private func correr(paquete: URL, texto: String, completion: @escaping (Bool) -> Void) {
        done = completion
        guard VozEngine.estado() == .listo else { finish(false); return }
        VozEngine.asegurarStreamRunner()

        if reproducir {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            guard AudioSeguro.arrancar(engine, player, contexto: "XTTS streaming") else { finish(false); return }
        }

        let p = Process()
        p.executableURL = VozEngine.pythonURL
        p.arguments = [VozEngine.streamRunnerURL.path, paquete.path, texto]
        var env = ProcessInfo.processInfo.environment; env["COQUI_TOS_AGREED"] = "1"
        p.environment = env
        let outPipe = Pipe(); p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice   // los warnings de python NO ensucian el PCM
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let d = fh.availableData
            guard !d.isEmpty else { return }
            self?.procesar(d)
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.finish(proc.terminationStatus == 0 && (self?.recibioAudio ?? false)) }
        }
        proceso = p
        do { try p.run() } catch { finish(false) }
    }

    /// Convierte bytes → floats (alineando a 4 bytes) → buffer → cola/captura.
    private func procesar(_ d: Data) {
        recibioAudio = true
        var buf = resto; buf.append(d)
        let usable = buf.count - (buf.count % 4)
        guard usable > 0 else { resto = buf; return }
        let bloque = buf.subdata(in: 0..<usable)
        resto = buf.subdata(in: usable..<buf.count)
        if let onPCM { onPCM(bloque); return }
        let n = usable / 4
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        pcm.frameLength = AVAudioFrameCount(n)
        bloque.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            guard let out = pcm.floatChannelData?[0] else { return }
            for i in 0..<n { out[i] = f[i] }   // XTTS ya entrega float [-1,1]
        }
        player.scheduleBuffer(pcm)
    }

    private func finish(_ ok: Bool) {
        if terminado { return }
        terminado = true
        proceso?.terminationHandler = nil
        let cb = done; done = nil
        if reproducir {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cb?(ok) }
        } else { cb?(ok) }
    }

    /// float32 LE → Int16 LE (para guardar WAV en pruebas).
    private static func floatABytesInt16(_ f32: Data) -> Data {
        var out = Data(capacity: f32.count / 2)
        f32.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            for i in 0..<f.count {
                let v = max(-1, min(1, f[i]))
                var s = Int16(v * 32767).littleEndian
                withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
            }
        }
        return out
    }
}
