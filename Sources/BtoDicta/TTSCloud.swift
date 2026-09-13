import Foundation

// MARK: - Motores TTS de NUBE (texto → voz) — catálogo parametrizable con failover
//
// Cada proveedor es un motor más para el Modo Agente / Voz del sistema, elegible en
// Ajustes. Todo parametrizable POR proveedor (voz/modelo/streaming), key propia del
// usuario. Sin key → nil → failover al siguiente motor (nunca truena).
//
//   Con WebSocket IMPLEMENTADO: ElevenLabs (cliente propio), Cartesia y Deepgram.
//   Por HTTP/batch en BtoDicta: OpenAI, Gemini, Azure, Inworld y PlayHT.
//   Que el proveedor publique un protocolo WS no significa que el adaptador ya exista:
//   el selector solo promete streaming cuando TTSCloudStream realmente lo implementa.
//
// `decir` devuelve audio LISTO para reproducir (mp3, o wav si el proveedor da PCM).

struct TTSNubeProveedor: Identifiable {
    let id: String
    let nombre: String
    let keyEnv: String
    let ws: Bool               // soporta streaming por WebSocket (para el toggle por proveedor)
    let vozDefault: String
    let modeloDefault: String
    let nota: String
}

enum TTSCloud {
    static let catalogo: [TTSNubeProveedor] = [
        TTSNubeProveedor(id: "openai_tts", nombre: "OpenAI", keyEnv: "OPENAI_API_KEY", ws: false,
                         vozDefault: "alloy", modeloDefault: "gpt-4o-mini-tts", nota: "Natural, barato. Sin clonación."),
        TTSNubeProveedor(id: "gemini_tts", nombre: "Google Gemini", keyEnv: "GEMINI_API_KEY", ws: false,
                         vozDefault: "Kore", modeloDefault: "gemini-2.5-flash-preview-tts", nota: "Multilingüe, PCM."),
        TTSNubeProveedor(id: "deepgram_tts", nombre: "Deepgram Aura-2", keyEnv: "DEEPGRAM_API_KEY", ws: true,
                         vozDefault: "aura-2-celeste-es", modeloDefault: "aura-2", nota: "Baja latencia; español latino."),
        TTSNubeProveedor(id: "cartesia_tts", nombre: "Cartesia Sonic", keyEnv: "CARTESIA_API_KEY", ws: true,
                         vozDefault: "", modeloDefault: "sonic-2", nota: "Líder de latencia; clona. Requiere key + voice id."),
        TTSNubeProveedor(id: "inworld_tts", nombre: "Inworld", keyEnv: "INWORLD_API_KEY", ws: false,
                         vozDefault: "Ashley", modeloDefault: "inworld-tts-1", nota: "HTTP/batch en BtoDicta; su WS aún no está integrado."),
        TTSNubeProveedor(id: "playht_tts", nombre: "PlayHT", keyEnv: "PLAYHT_API_KEY", ws: false,
                         vozDefault: "", modeloDefault: "Play3.0-mini", nota: "HTTP/batch en BtoDicta; requiere key + PLAYHT_USER_ID."),
        TTSNubeProveedor(id: "azure_tts", nombre: "Azure Speech", keyEnv: "AZURE_SPEECH_KEY", ws: false,
                         vozDefault: "es-EC-AndreaNeural", modeloDefault: "", nota: "Español EC nativo. Requiere key + región (AZURE_SPEECH_REGION)."),
    ]

    static func proveedor(_ id: String) -> TTSNubeProveedor? { catalogo.first { $0.id == id } }

    /// Sintetiza `texto` con el proveedor `id`. Devuelve audio reproducible (mp3/wav)
    /// o nil (sin key / error) → el llamador hace failover. https fail-closed.
    static func decir(_ id: String, texto: String, completion: @escaping (Data?) -> Void) {
        guard let p = proveedor(id) else { completion(nil); return }
        let key = clave(p.keyEnv)
        guard !key.isEmpty else { Log.log(.ia, "TTS \(p.nombre): sin API key"); completion(nil); return }
        let voz = Config.ttsCloudVoz(id).isEmpty ? p.vozDefault : Config.ttsCloudVoz(id)
        let modelo = Config.ttsCloudModelo(id).isEmpty ? p.modeloDefault : Config.ttsCloudModelo(id)
        guard let (req, pcm) = construir(p, texto: texto, key: key, voz: voz, modelo: modelo) else { completion(nil); return }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, (200..<300).contains(code), !data.isEmpty else {
                Log.log(.ia, "TTS \(p.nombre) falló (\(err?.localizedDescription ?? "HTTP \(code)"))"); completion(nil); return
            }
            // Extraer audio según proveedor (algunos envuelven el audio en JSON base64/PCM).
            completion(extraer(p, data: data, pcm: pcm))
        }.resume()
    }

    // MARK: Construcción por proveedor

    /// Devuelve (request, esPCM). esPCM=true → la respuesta es PCM crudo que hay que
    /// envolver en WAV para reproducir.
    private static func construir(_ p: TTSNubeProveedor, texto: String, key: String,
                                  voz: String, modelo: String) -> (URLRequest, Bool)? {
        func json(_ url: String, _ headers: [String: String], _ body: [String: Any]) -> URLRequest? {
            guard let u = URL(string: url) else { return nil }
            var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 25
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("close", forHTTPHeaderField: "Connection")
            for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
            r.httpBody = try? JSONSerialization.data(withJSONObject: body); return r
        }
        switch p.id {
        case "openai_tts":
            return json("https://api.openai.com/v1/audio/speech", ["Authorization": "Bearer \(key)"],
                        ["model": modelo, "voice": voz, "input": texto, "response_format": "mp3"]).map { ($0, false) }
        case "gemini_tts":
            let url = "https://generativelanguage.googleapis.com/v1beta/models/\(modelo):generateContent?key=\(key)"
            let body: [String: Any] = ["contents": [["parts": [["text": texto]]]],
                "generationConfig": ["responseModalities": ["AUDIO"],
                    "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voz]]]]]
            return json(url, [:], body).map { ($0, true) }   // Gemini devuelve PCM base64 (L16 24k)
        case "deepgram_tts":
            let url = "https://api.deepgram.com/v1/speak?model=\(voz)&encoding=mp3"
            return json(url, ["Authorization": "Token \(key)"], ["text": texto]).map { ($0, false) }
        case "cartesia_tts":
            let body: [String: Any] = ["model_id": modelo, "transcript": texto, "language": "es",
                "voice": ["mode": "id", "id": voz],
                "output_format": ["container": "mp3", "sample_rate": 44100, "bit_rate": 128000]]
            return json("https://api.cartesia.ai/tts/bytes",
                        ["X-API-Key": key, "Cartesia-Version": "2024-06-10"], body).map { ($0, false) }
        case "inworld_tts":
            return json("https://api.inworld.ai/tts/v1/voice", ["Authorization": "Bearer \(key)"],
                        ["text": texto, "voiceId": voz, "modelId": modelo]).map { ($0, false) }   // audioContent base64
        case "playht_tts":
            let uid = clave("PLAYHT_USER_ID")
            return json("https://api.play.ht/api/v2/tts/stream",
                        ["Authorization": "Bearer \(key)", "X-User-Id": uid, "Accept": "audio/mpeg"],
                        ["text": texto, "voice": voz, "voice_engine": modelo, "output_format": "mp3"]).map { ($0, false) }
        case "azure_tts":
            let region = clave("AZURE_SPEECH_REGION").isEmpty ? "eastus" : clave("AZURE_SPEECH_REGION")
            guard let u = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else { return nil }
            var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 25
            r.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
            r.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
            r.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
            let ssml = "<speak version='1.0' xml:lang='es-EC'><voice name='\(voz)'>\(escaparXML(texto))</voice></speak>"
            r.httpBody = ssml.data(using: .utf8); return (r, false)
        default: return nil
        }
    }

    /// Extrae el audio de la respuesta. mp3 directo → tal cual; PCM/JSON → desenvuelve.
    private static func extraer(_ p: TTSNubeProveedor, data: Data, pcm: Bool) -> Data? {
        switch p.id {
        case "gemini_tts":
            // JSON con inlineData.data (base64 PCM L16 24kHz) → WAV.
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cands = j["candidates"] as? [[String: Any]],
                  let parts = (cands.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
                  let b64 = (parts.first?["inlineData"] as? [String: Any])?["data"] as? String,
                  let raw = Data(base64Encoded: b64) else { return nil }
            return (try? WavIOWrap(pcm16: raw, sampleRate: 24000)) ?? nil
        case "inworld_tts":
            // JSON con audioContent base64 (mp3/wav).
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let b64 = (j["audioContent"] as? String) ?? (j["audio"] as? String),
                  let audio = Data(base64Encoded: b64) else { return nil }
            return audio
        default:
            return pcm ? ((try? WavIOWrap(pcm16: data, sampleRate: 24000)) ?? nil) : data
        }
    }

    private static func clave(_ env: String) -> String {
        if let e = ProcessInfo.processInfo.environment[env], !e.isEmpty { return e }
        return ApiKeys.get(env)
    }
    private static func escaparXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    /// Envuelve PCM16 en WAV (reutiliza WavIO de ElevenLabsStreamTTS).
    private static func WavIOWrap(pcm16: Data, sampleRate: Int) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("btodicta-cloudtts-\(abs(pcm16.count)).wav")
        try WavIO.escribir(pcm16: pcm16, sampleRate: sampleRate, a: tmp)
        let d = try Data(contentsOf: tmp); try? FileManager.default.removeItem(at: tmp); return d
    }
}
