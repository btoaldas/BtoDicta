import Foundation
import AVFoundation

// MARK: - ElevenLabs TTS por WebSocket (streaming, voz clonada "Bto") — Fase asistente por voz
//
// El audio EMPIEZA A SONAR mientras se genera (no espera el mp3 completo). Manda el
// texto por WebSocket (stream-input), recibe chunks PCM 16-bit @22050Hz y los encola
// en un AVAudioPlayerNode → latencia percibida ~75-130ms al primer sonido.
//
// URLSessionWebSocketTask es nativo (cero dependencias). Falla suave: si el WS no
// conecta o corta, se avisa (completion(false)) y Voz.decir cae al batch / siguiente
// motor. https/wss fail-closed: la key va en el header sobre TLS.

final class ElevenLabsStreamTTS: NSObject {
    // Retenido mientras suena (si se libera, se corta el audio).
    static var activo: ElevenLabsStreamTTS?

    private var ws: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!

    /// Corta el streaming en curso de raíz (WS + audio). Para el botón/tecla Cancelar.
    static func cancelar() {
        guard let c = activo else { return }
        c.terminado = true
        c.ws?.cancel(with: .goingAway, reason: nil); c.ws = nil
        c.player.stop(); c.engine.stop(); c.done = nil
        activo = nil
    }
    private var onPCM: ((Data) -> Void)?      // para captura (tests); si nil → reproduce
    private var terminado = false
    private var done: ((Bool) -> Void)?
    private var bytesSonados = 0              // audio ya reproducido: un corte tardío NO debe repetirse

    /// Habla en vivo (reproduce por los parlantes).
    static func hablar(_ texto: String, completion: @escaping (Bool) -> Void) {
        let c = ElevenLabsStreamTTS(); activo = c
        c.reproducir = true
        c.stream(texto) { ok in completion(ok) }
    }

    /// Captura el PCM a un WAV (para pruebas). No reproduce.
    static func capturarWav(_ texto: String, salida: URL, completion: @escaping (Bool) -> Void) {
        let c = ElevenLabsStreamTTS(); activo = c
        var pcm = Data()
        c.onPCM = { pcm.append($0) }
        c.stream(texto) { ok in
            if ok, !pcm.isEmpty { try? WavIO.escribir(pcm16: pcm, sampleRate: 22050, a: salida) }
            completion(ok && !pcm.isEmpty)
        }
    }

    private var reproducir = false

    private func stream(_ texto: String, _ completion: @escaping (Bool) -> Void) {
        done = completion
        guard let key = Config.apiKey(), !key.isEmpty else { finish(false); return }
        let voz = Config.ttsElevenVoz()
        let modelo = Config.ttsElevenModelo()
        let urlStr = "wss://api.elevenlabs.io/v1/text-to-speech/\(voz)/stream-input"
            + "?model_id=\(modelo)&output_format=pcm_22050&language_code=es&auto_mode=true&inactivity_timeout=20"
        guard let url = URL(string: urlStr) else { finish(false); return }

        if reproducir {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            // Sin excepciones ObjC de AVFoundation: si no hay salida o el motor no corre,
            // false → failover (era el crash diario de las 20:00).
            guard AudioSeguro.arrancar(engine, player, contexto: "ElevenLabs WS") else { finish(false); return }
        }

        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 15
        let task = URLSession.shared.webSocketTask(with: req)
        // El default (1 MB) revienta con frames de audio de respuestas largas
        // («Message too long») y disparaba el failover a batch A MITAD de la
        // reproducción — el texto entero se oía DOS veces.
        task.maximumMessageSize = 8 * 1024 * 1024
        ws = task
        task.resume()
        recibir()

        // 1) Mensaje inicial (abre el stream).
        let bos = #"{"text":" ","voice_settings":{"stability":0.5,"similarity_boost":0.75,"style":0,"use_speaker_boost":true,"speed":1.0},"generation_config":{"chunk_length_schedule":[120,160,250,290]}}"#
        enviar(bos)
        // 2) El texto (con flush para que empiece a generar ya).
        if let t = try? JSONSerialization.data(withJSONObject: ["text": texto + " ", "flush": true]),
           let s = String(data: t, encoding: .utf8) { enviar(s) }
        // 3) Cierre: buffer vacío → manda el audio final y luego isFinal.
        enviar(#"{"text":""}"#)

        // Tope de seguridad: si en 20s no llegó isFinal, cerrar y avisar (failover).
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, !self.terminado else { return }
            Log.log(.ia, "TTS WS: sin isFinal en 20s → failover"); self.finish(self.onPCM != nil ? false : true)
        }
    }

    private func enviar(_ s: String) {
        ws?.send(.string(s)) { err in if let err { Log.log(.ia, "TTS WS send: \(err.localizedDescription)") } }
    }

    private func recibir() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Log.log(.ia, "TTS WS recv: \(e.localizedDescription)")
                // Si YA sonó audio, esto es un corte al final, no un fallo total:
                // repetir el texto completo por batch duplicaría lo escuchado.
                if self.reproducir, self.bytesSonados > 0 {
                    Log.log(.ia, "TTS WS cortó tras reproducir \(self.bytesSonados) bytes — no se repite por batch")
                    self.finish(true)
                } else {
                    self.finish(false)
                }
            case .success(let msg):
                if case .string(let txt) = msg, let data = txt.data(using: .utf8),
                   let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let b64 = j["audio"] as? String, let pcm = Data(base64Encoded: b64), !pcm.isEmpty {
                        self.procesar(pcm)
                    }
                    if (j["isFinal"] as? Bool) == true {
                        self.finish(true); return
                    }
                }
                self.recibir()   // seguir escuchando
            }
        }
    }

    private func procesar(_ pcm: Data) {
        if let onPCM { onPCM(pcm); return }
        // Reproducir: Int16 LE → Float32 → buffer → cola.
        let n = pcm.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            guard let out = buf.floatChannelData?[0] else { return }
            for i in 0..<n { out[i] = Float(Int16(littleEndian: s[i])) / 32768.0 }
        }
        player.scheduleBuffer(buf)
        bytesSonados += pcm.count
    }

    private func finish(_ ok: Bool) {
        if terminado { return }
        terminado = true
        ws?.cancel(with: .goingAway, reason: nil); ws = nil
        let cb = done; done = nil
        // Deja que termine de sonar lo encolado antes de soltar el engine.
        if reproducir {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // No paramos el engine aquí: los buffers encolados siguen sonando;
                // se libera al soltar la referencia estática en la próxima llamada.
                cb?(ok)
            }
        } else {
            cb?(ok)
        }
    }
}

// MARK: - WAV mínimo (PCM 16-bit mono) para pruebas de captura

enum WavIO {
    static func escribir(pcm16: Data, sampleRate: Int, a url: URL) throws {
        let ch = 1, bits = 16
        let byteRate = sampleRate * ch * bits / 8
        let blockAlign = ch * bits / 8
        var d = Data()
        func le32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
        func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
        d.append("RIFF".data(using: .ascii)!); d.append(le32(36 + pcm16.count)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); d.append(le32(16)); d.append(le16(1)); d.append(le16(ch))
        d.append(le32(sampleRate)); d.append(le32(byteRate)); d.append(le16(blockAlign)); d.append(le16(bits))
        d.append("data".data(using: .ascii)!); d.append(le32(pcm16.count)); d.append(pcm16)
        try d.write(to: url)
    }
}
