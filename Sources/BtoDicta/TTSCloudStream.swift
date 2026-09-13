import Foundation
import AVFoundation

// MARK: - Streaming por WebSocket para TTS de nube (suena mientras genera)
//
// Deepgram (VERIFICADO con key): protocolo Speak/Flush, recibe PCM linear16 crudo.
// Cartesia (documentado, sin key para probar): recibe chunks base64 pcm_f32le.
// PlayHT: por ahora batch (su WS necesita fetch de URL efímera; se hará con key).
//
// Falla suave: si el WS no conecta o no da audio → completion(false) → Voz.decir cae a
// batch / siguiente motor. Reproduce por AVAudioEngine (chunks en orden).

final class TTSCloudStream: NSObject {
    static var activo: TTSCloudStream?

    /// ¿Hay cliente WS para este proveedor? (los demás → batch)
    static func soporta(_ id: String) -> Bool { id == "deepgram_tts" || id == "cartesia_tts" }

    private var ws: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var fmt: AVAudioFormat!

    /// Corta el streaming de nube en curso de raíz (WS + audio). Para Cancelar.
    static func cancelar() {
        guard let c = activo else { return }
        c.terminado = true
        c.ws?.cancel(with: .goingAway, reason: nil); c.ws = nil
        c.player.stop(); c.engine.stop(); c.done = nil
        activo = nil
    }
    private var esFloat = false          // Cartesia = f32le; Deepgram = int16
    private var resto = Data()
    private var recibio = false
    private var onPCM: ((Data) -> Void)?
    private var reproducir = false
    private var done: ((Bool) -> Void)?
    private var terminado = false

    static func hablar(_ id: String, texto: String, completion: @escaping (Bool) -> Void) {
        let c = TTSCloudStream(); activo = c; c.reproducir = true
        c.correr(id: id, texto: texto, completion: completion)
    }

    static func capturarWav(_ id: String, texto: String, salida: URL, completion: @escaping (Bool) -> Void) {
        let c = TTSCloudStream(); activo = c
        var pcm = Data()
        c.onPCM = { pcm.append($0) }
        c.correr(id: id, texto: texto) { ok in
            if ok, !pcm.isEmpty {
                let sr = id == "cartesia_tts" ? 44100 : 24000
                let pcm16 = c.esFloat ? TTSCloudStream.f32aInt16(pcm) : pcm
                try? WavIO.escribir(pcm16: pcm16, sampleRate: sr, a: salida)
            }
            completion(ok && !pcm.isEmpty)
        }
    }

    private func correr(id: String, texto: String, completion: @escaping (Bool) -> Void) {
        done = completion
        guard let p = TTSCloud.proveedor(id) else { finish(false); return }
        let key = clave(p.keyEnv); guard !key.isEmpty else { finish(false); return }
        let voz = Config.ttsCloudVoz(id).isEmpty ? p.vozDefault : Config.ttsCloudVoz(id)
        let modelo = Config.ttsCloudModelo(id).isEmpty ? p.modeloDefault : Config.ttsCloudModelo(id)

        var req: URLRequest
        let sr: Double
        switch id {
        case "deepgram_tts":
            esFloat = false; sr = 24000
            let u = "wss://api.deepgram.com/v1/speak?encoding=linear16&sample_rate=24000&model=\(voz)"
            guard let url = URL(string: u) else { finish(false); return }
            req = URLRequest(url: url); req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        case "cartesia_tts":
            esFloat = true; sr = 44100
            let u = "wss://api.cartesia.ai/tts/websocket?api_key=\(key)&cartesia_version=2024-06-10"
            guard let url = URL(string: u) else { finish(false); return }
            req = URLRequest(url: url)
            _ = modelo // se usa en el mensaje de abajo
        default: finish(false); return
        }

        fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)
        if reproducir {
            engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt)
            guard AudioSeguro.arrancar(engine, player, contexto: "TTS nube WS") else { finish(false); return }
        }
        req.timeoutInterval = 15
        let task = URLSession.shared.webSocketTask(with: req); ws = task; task.resume()
        recibir()

        // Mensajes de apertura según proveedor.
        switch id {
        case "deepgram_tts":
            enviar(#"{"type":"Speak","text":\#(jsonStr(texto))}"#)
            enviar(#"{"type":"Flush"}"#)
        case "cartesia_tts":
            let msg: [String: Any] = ["model_id": modelo, "transcript": texto, "language": "es",
                "voice": ["mode": "id", "id": voz], "context_id": "beto",
                "output_format": ["container": "raw", "encoding": "pcm_f32le", "sample_rate": 44100]]
            if let d = try? JSONSerialization.data(withJSONObject: msg), let s = String(data: d, encoding: .utf8) { enviar(s) }
        default: break
        }
        // Tope: si no llega audio en 20s → failover.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, !self.terminado else { return }
            self.finish(self.recibio && self.onPCM == nil)
        }
    }

    private func enviar(_ s: String) { ws?.send(.string(s)) { _ in } }

    private func recibir() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure: self.finish(self.recibio)
            case .success(let msg):
                switch msg {
                case .data(let d): self.procesar(d)          // Deepgram: PCM binario crudo
                case .string(let s):
                    // Cartesia: JSON con audio base64; Deepgram: control (Flushed/Metadata).
                    if let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                        if let b64 = j["data"] as? String, let d = Data(base64Encoded: b64) { self.procesar(d) }
                        if (j["type"] as? String) == "Flushed" || (j["done"] as? Bool) == true { self.finish(true); return }
                    }
                @unknown default: break
                }
                self.recibir()
            }
        }
    }

    private func procesar(_ d: Data) {
        recibio = true
        if let onPCM { onPCM(d); return }
        let ancho = esFloat ? 4 : 2
        var buf = resto; buf.append(d)
        let usable = buf.count - (buf.count % ancho)
        guard usable > 0 else { resto = buf; return }
        let bloque = buf.subdata(in: 0..<usable); resto = buf.subdata(in: usable..<buf.count)
        let n = usable / ancho
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        pcm.frameLength = AVAudioFrameCount(n)
        bloque.withUnsafeBytes { raw in
            guard let out = pcm.floatChannelData?[0] else { return }
            if esFloat { let f = raw.bindMemory(to: Float32.self); for i in 0..<n { out[i] = f[i] } }
            else { let s = raw.bindMemory(to: Int16.self); for i in 0..<n { out[i] = Float(Int16(littleEndian: s[i])) / 32768.0 } }
        }
        player.scheduleBuffer(pcm)
    }

    private func finish(_ ok: Bool) {
        if terminado { return }; terminado = true
        ws?.cancel(with: .goingAway, reason: nil); ws = nil
        let cb = done; done = nil
        if reproducir { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cb?(ok) } } else { cb?(ok) }
    }

    private func clave(_ env: String) -> String {
        if let e = ProcessInfo.processInfo.environment[env], !e.isEmpty { return e }; return ApiKeys.get(env)
    }
    private func jsonStr(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)) ?? "\"\(s)\""
    }
    private static func f32aInt16(_ f32: Data) -> Data {
        var out = Data(capacity: f32.count / 2)
        f32.withUnsafeBytes { raw in let f = raw.bindMemory(to: Float32.self)
            for i in 0..<f.count { var s = Int16(max(-1, min(1, f[i])) * 32767).littleEndian; withUnsafeBytes(of: &s) { out.append(contentsOf: $0) } } }
        return out
    }
}
