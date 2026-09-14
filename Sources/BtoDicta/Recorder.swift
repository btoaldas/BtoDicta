import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Grabadora (micrófono → PCM16 16 kHz mono, con chunks y nivel)

final class Recorder {
    private let engine = AVAudioEngine()
    private var samples = Data()
    // El tap escribe desde el hilo de audio y main lee a mitad de grabación
    // (backlog en vivo): sin este candado es una carrera de datos real.
    private let candado = NSLock()
    private var converter: AVAudioConverter?
    /// Frecuencia INTERNA de la app. El micrófono de cada equipo entrega la
    /// suya —44 100, 48 000, 96 000 Hz…— y el conversor la lleva siempre aquí,
    /// así que nada del resto del código depende del hardware de turno.
    static let frecuenciaInterna: Double = 16000
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Recorder.frecuenciaInterna, channels: 1, interleaved: true)!

    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?
    private(set) var isRecording = false

    /// PCM crudo acumulado hasta ahora (para transcripción parcial en vivo).
    var pcmAcumulado: Data {
        candado.lock(); defer { candado.unlock() }
        return samples
    }

    /// Buffers recibidos del micrófono en el dictado en curso. Cero tras unos
    /// segundos significa que no está entrando NADA: mejor decirlo que dejar al
    /// usuario hablando contra un micrófono mudo.
    private(set) var buffersRecibidos = 0

    func start(preloadPCM: Data = Data()) throws {
        // Blindaje contra doble arranque: un segundo installTap en el mismo
        // bus lanza NSException y tumba la app (crash real del 2026-07-10).
        guard !isRecording else { return }
        candado.lock()
        samples = preloadPCM
        candado.unlock()
        let input = engine.inputNode
        input.removeTap(onBus: 0)   // por si quedó un tap de un intento fallido
        // Fijar el micrófono ANTES de leer el formato: sin esto macOS puede
        // enchufarnos el mic del iPhone (Continuity) y grabar silencio.
        Microfono.aplicar(a: input.audioUnit)
        // El formato del micrófono puede llegar INVÁLIDO (0 Hz o 0 canales)
        // cuando el dispositivo está en transición: justo lo que pasa al pulsar
        // la tecla mientras la bitácora acaba de soltar el micrófono. Con ese
        // formato, `installTapOnBus` lanza una NSException que Swift no puede
        // atrapar y la app ABORTA a mitad del dictado (crash real 2026-09-13).
        var inFormat = input.outputFormat(forBus: 0)
        if inFormat.sampleRate <= 0 || inFormat.channelCount == 0 {
            // Un respiro y una segunda lectura: el dispositivo suele asentarse
            // en milisegundos. Si sigue mal, se falla limpio y la cascada
            // normal se encarga; nunca se aborta.
            engine.stop(); engine.reset()
            Thread.sleep(forTimeInterval: 0.15)
            inFormat = input.outputFormat(forBus: 0)
            Log.log(.sistema, "micrófono en transición — releído a \(Int(inFormat.sampleRate)) Hz, \(inFormat.channelCount) can")
        }
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            Log.log(.sistema, "micrófono no disponible (formato \(inFormat.sampleRate) Hz, \(inFormat.channelCount) can) — no arranco el dictado")
            throw ScribeError.ws("el micrófono no está disponible ahora mismo")
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        buffersRecibidos = 0
        let instalar = { [weak self] in
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            self.buffersRecibidos &+= 1
            let ratio = self.outFormat.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.outFormat, frameCapacity: capacity) else { return }
            var served = false
            converter.convert(to: out, error: nil) { _, status in
                if served {
                    status.pointee = .noDataNow
                    return nil
                }
                served = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
            let chunk = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
            self.candado.lock()
            self.samples.append(chunk)
            self.candado.unlock()
            self.onChunk?(chunk)

            var sum: Double = 0
            let n = Int(out.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                sum += v * v
            }
            let rms = Float((sum / Double(max(n, 1))).squareRoot())
            let boosted = Float(pow(Double(min(rms * 12, 1.0)), 0.5))
            self.onLevel?(boosted)
        }

        }
        // AVFoundation lanza excepciones de Objective-C que `try` no ve: van por
        // el atrapador nativo o se llevan la app por delante.
        if let fallo = AudioSeguro.atrapar(instalar) {
            input.removeTap(onBus: 0)
            Log.log(.sistema, "micrófono: no pude instalar la escucha (\(fallo)) — dictado no iniciado")
            throw ScribeError.ws("el micrófono no aceptó la escucha")
        }
        engine.prepare()
        var errorArranque: Error?
        if let fallo = AudioSeguro.atrapar({
            do { try self.engine.start() } catch { errorArranque = error }
        }) {
            input.removeTap(onBus: 0)
            Log.log(.sistema, "micrófono: el motor de audio no arrancó (\(fallo))")
            throw ScribeError.ws("el motor de audio no arrancó")
        }
        if let errorArranque {
            // Sin esto el tap queda huérfano y el próximo start crashea
            // (doble installTap en el mismo bus).
            input.removeTap(onBus: 0)
            throw errorArranque
        }
        isRecording = true
        // La activación manos libres entrega los últimos segundos que estaban
        // solo en RAM. Pasan por el MISMO historial/preview/backlog que el audio
        // nuevo y la cascada final recibe una única grabación continua.
        if !preloadPCM.isEmpty { onChunk?(preloadPCM) }
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        candado.lock(); defer { candado.unlock() }
        let wav = wavFile(from: samples)
        // Se suelta el PCM en cuanto está el WAV. Antes se quedaba vivo hasta
        // el siguiente dictado, así que durante toda la transcripción convivían
        // dos copias completas del audio: en seis horas, 1,4 GB para nada.
        samples = Data()
        return wav
    }

    /// Los últimos `segundos` de audio, sin copiar el dictado entero. Para las
    /// vistas previas en vivo, que no necesitan lo que ya se transcribió.
    func pcmReciente(segundos: Double) -> Data {
        candado.lock(); defer { candado.unlock() }
        let tope = Int(segundos * Recorder.frecuenciaInterna) * 2
        guard samples.count > tope else { return samples }
        return samples.suffix(tope)
    }

    private func wavFile(from pcm: Data) -> Data {
        var wav = Data()
        let sampleRate: UInt32 = 16000
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian)
        append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian)
        append(UInt16(16).littleEndian)
        wav.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        return wav
    }
}
