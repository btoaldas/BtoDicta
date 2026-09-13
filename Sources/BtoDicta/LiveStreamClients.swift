import Foundation

// MARK: - Clientes STT en vivo (WebSocket) de los proveedores nube nuevos
//
// Cada proveedor tiene su protocolo; todos conforman LiveNubeSTT para entrar en
// el MISMO carril en vivo del AppDelegate. Cada uno trae un parse() estático,
// probable sin conexión (BTODICTA_*PARSETEST), que es la parte más delicada.
// La prueba EN VIVO end-to-end necesita la key real del proveedor + micrófono.

// MARK: Soniox (tokens con is_final)

final class SonioxStreamClient: NSObject, LiveNubeSTT {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finales = ""
    private var cerrando = false
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var conectado = false

    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let key = ApiKeys.get("SONIOX_API_KEY")
        guard !key.isEmpty else { completion(.failure(ScribeError.sinApiKey)); return }
        finales = ""
        guard let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket") else {
            completion(.failure(ScribeError.ws("URL inválida"))); return
        }
        var respondido = false
        let responder: (Result<Void, Error>) -> Void = { [weak self] r in
            guard !respondido else { return }; respondido = true
            if case .success = r { self?.conectado = true }; completion(r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard !respondido else { return }
            self?.disconnect(); responder(.failure(ScribeError.ws("Soniox: conexión tardó más de 4 s")))
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session; self.task = task
        task.resume()
        // Primer mensaje = configuración (incluye la key).
        let config: [String: Any] = [
            "api_key": key, "model": model.isEmpty ? "stt-rt-v5" : model,
            "audio_format": "pcm_s16le", "sample_rate": 16000, "num_channels": 1,
            "language_hints": ["es", "en"], "enable_language_identification": true,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: config), let s = String(data: d, encoding: .utf8) {
            task.send(.string(s)) { err in
                if let err { DispatchQueue.main.async { responder(.failure(ScribeError.ws(err.localizedDescription))) } }
            }
        }
        receiveLoop()
        responder(.success(()))
    }

    func send(chunk: Data) { task?.send(.data(chunk)) { [weak self] e in if let e { DispatchQueue.main.async { self?.onError?(e.localizedDescription) } } } }
    func finalizar() { task?.send(.string("")) { _ in } }   // string vacío = fin de audio
    func fullText() -> String { finales.trimmingCharacters(in: .whitespacesAndNewlines) }
    func disconnect() { cerrando = true; task?.cancel(with: .normalClosure, reason: nil); task = nil; session?.invalidateAndCancel(); session = nil }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { guard !self.cerrando else { return }; self.conectado = false; self.onError?("Soniox: conexión cerrada") }
            case .success(let m):
                if case .string(let t) = m { self.handle(t) }
                self.receiveLoop()
            }
        }
    }

    /// (textoFinalNuevo, textoInterim) de un mensaje de Soniox, o nil.
    static func parse(_ text: String) -> (String, String)? {
        guard let data = text.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = j["tokens"] as? [[String: Any]] else { return nil }
        var fin = "", inter = ""
        for tk in tokens {
            let t = (tk["text"] as? String) ?? ""
            if (tk["is_final"] as? Bool) ?? false { fin += t } else { inter += t }
        }
        return (fin, inter)
    }

    private func handle(_ text: String) {
        guard let (fin, inter) = Self.parse(text) else { return }
        DispatchQueue.main.async {
            if !fin.isEmpty { self.finales += fin }
            let vis = (self.finales + inter).trimmingCharacters(in: .whitespacesAndNewlines)
            self.onPartial?(vis)
        }
    }
}

// MARK: AssemblyAI Universal-Streaming v3 (mensajes "Turn")

final class AssemblyAIStreamClient: NSObject, LiveNubeSTT {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finales: [String] = []
    private var turnoActual = ""
    private var cerrando = false
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var conectado = false

    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let key = ApiKeys.get("ASSEMBLYAI_API_KEY")
        guard !key.isEmpty else { completion(.failure(ScribeError.sinApiKey)); return }
        finales = []; turnoActual = ""
        var comp = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        comp.queryItems = [
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "format_turns", value: "true"),
        ]
        var req = URLRequest(url: comp.url!)
        req.setValue(key, forHTTPHeaderField: "Authorization")
        var respondido = false
        let responder: (Result<Void, Error>) -> Void = { [weak self] r in
            guard !respondido else { return }; respondido = true
            if case .success = r { self?.conectado = true }; completion(r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard !respondido else { return }
            self?.disconnect(); responder(.failure(ScribeError.ws("AssemblyAI: conexión tardó más de 4 s")))
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: req)
        self.session = session; self.task = task
        task.resume()
        receiveLoop()
        responder(.success(()))
    }

    func send(chunk: Data) { task?.send(.data(chunk)) { [weak self] e in if let e { DispatchQueue.main.async { self?.onError?(e.localizedDescription) } } } }
    func finalizar() { if let d = try? JSONSerialization.data(withJSONObject: ["type": "Terminate"]), let s = String(data: d, encoding: .utf8) { task?.send(.string(s)) { _ in } } }
    func fullText() -> String { (finales + [turnoActual]).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    func disconnect() { cerrando = true; task?.cancel(with: .normalClosure, reason: nil); task = nil; session?.invalidateAndCancel(); session = nil }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { guard !self.cerrando else { return }; self.conectado = false; self.onError?("AssemblyAI: conexión cerrada") }
            case .success(let m):
                if case .string(let t) = m { self.handle(t) }
                self.receiveLoop()
            }
        }
    }

    /// (transcript, endOfTurn, formateado) de un mensaje "Turn", o nil. Con
    /// format_turns=true, el fin de turno llega DOS veces (crudo y formateado):
    /// hay que anexar solo el formateado para no duplicar.
    static func parse(_ text: String) -> (String, Bool, Bool)? {
        guard let data = text.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (j["type"] as? String) == "Turn",
              let t = j["transcript"] as? String else { return nil }
        return (t, (j["end_of_turn"] as? Bool) ?? false, (j["turn_is_formatted"] as? Bool) ?? false)
    }

    private func handle(_ text: String) {
        guard let (t, fin, formateado) = Self.parse(text) else { return }
        DispatchQueue.main.async {
            if fin && formateado {
                // Fin de turno DEFINITIVO (formateado): se anexa una sola vez.
                if !t.isEmpty { self.finales.append(t) }
                self.turnoActual = ""
            } else {
                self.turnoActual = t   // crudo o parcial: transcript acumulativo del turno
            }
            self.onPartial?(self.fullText())
        }
    }
}

// MARK: Speechmatics realtime v2 (StartRecognition → AddTranscript)

final class SpeechmaticsStreamClient: NSObject, LiveNubeSTT {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finales: [String] = []
    private var parcial = ""
    private var seq = 0
    private var cerrando = false
    private var pendingResponder: ((Result<Void, Error>) -> Void)?   // resuelve RecognitionStarted/Error
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var conectado = false

    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let key = ApiKeys.get("SPEECHMATICS_API_KEY")
        guard !key.isEmpty else { completion(.failure(ScribeError.sinApiKey)); return }
        finales = []; parcial = ""; seq = 0
        guard let url = URL(string: "wss://eu2.rt.speechmatics.com/v2") else { completion(.failure(ScribeError.ws("URL inválida"))); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // Responder persistente: se resuelve en RecognitionStarted (éxito) o en el
        // mensaje Error (falla con la razón), venga en el mensaje que venga — no
        // solo el primero. Así no se pierde y no espera el timeout en vano.
        var respondido = false
        pendingResponder = { [weak self] r in
            guard !respondido else { return }; respondido = true
            if case .success = r { self?.conectado = true }; completion(r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, !respondido else { return }
            self.disconnect(); self.pendingResponder?(.failure(ScribeError.ws("Speechmatics: no confirmó (RecognitionStarted) en 6 s")))
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: req)
        self.session = session; self.task = task
        task.resume()
        let op = model == "enhanced" ? "enhanced" : "standard"
        let start: [String: Any] = [
            "message": "StartRecognition",
            "audio_format": ["type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000],
            "transcription_config": ["language": "es", "operating_point": op, "enable_partials": true, "max_delay": 2.0],
        ]
        if let d = try? JSONSerialization.data(withJSONObject: start), let s = String(data: d, encoding: .utf8) {
            task.send(.string(s)) { _ in }
        }
        receiveLoop()
    }

    func send(chunk: Data) {
        seq += 1
        task?.send(.data(chunk)) { [weak self] e in if let e { DispatchQueue.main.async { self?.onError?(e.localizedDescription) } } }
    }
    func finalizar() {
        if let d = try? JSONSerialization.data(withJSONObject: ["message": "EndOfStream", "last_seq_no": seq]),
           let s = String(data: d, encoding: .utf8) { task?.send(.string(s)) { _ in } }
    }
    func fullText() -> String { finales.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    func disconnect() { cerrando = true; task?.cancel(with: .normalClosure, reason: nil); task = nil; session?.invalidateAndCancel(); session = nil }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    guard !self.cerrando else { return }
                    self.conectado = false
                    // Si aún no confirmó, esto ES el fallo de conexión (auth, red).
                    self.pendingResponder?(.failure(ScribeError.ws("Speechmatics: conexión cerrada")))
                    self.pendingResponder = nil
                    self.onError?("Speechmatics: conexión cerrada")
                }
            case .success(let m):
                if case .string(let t) = m { self.handle(t) }
                self.receiveLoop()
            }
        }
    }

    /// (transcript, isFinal) de AddTranscript/AddPartialTranscript, o nil.
    static func parse(_ text: String) -> (String, Bool)? {
        guard let data = text.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = j["message"] as? String else { return nil }
        let meta = j["metadata"] as? [String: Any]
        guard let t = meta?["transcript"] as? String else { return nil }
        if msg == "AddTranscript" { return (t, true) }
        if msg == "AddPartialTranscript" { return (t, false) }
        return nil
    }

    private func handle(_ text: String) {
        // Confirmación / error de la sesión (resuelven la conexión).
        if let data = text.data(using: .utf8),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = j["message"] as? String {
            if msg == "RecognitionStarted" {
                DispatchQueue.main.async { self.pendingResponder?(.success(())); self.pendingResponder = nil }
                return
            }
            if msg == "Error" {
                let razon = (j["reason"] as? String) ?? (j["type"] as? String) ?? "error"
                DispatchQueue.main.async {
                    self.pendingResponder?(.failure(ScribeError.ws("Speechmatics: \(razon)"))); self.pendingResponder = nil
                    self.onError?("Speechmatics: \(razon)")
                }
                return
            }
        }
        guard let (t, fin) = Self.parse(text) else { return }
        DispatchQueue.main.async {
            if fin { if !t.isEmpty { self.finales.append(t) }; self.parcial = "" }
            else { self.parcial = t }
            let vis = (self.finales.joined(separator: " ") + " " + self.parcial).trimmingCharacters(in: .whitespacesAndNewlines)
            self.onPartial?(vis)
        }
    }
}

// MARK: Gladia live v2 (POST init → WS url)

final class GladiaLiveClient: NSObject, LiveNubeSTT {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finales = ""
    private var parcial = ""
    private var cerrando = false
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var conectado = false

    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let key = ApiKeys.get("GLADIA_API_KEY")
        guard !key.isEmpty else { completion(.failure(ScribeError.sinApiKey)); return }
        finales = ""; parcial = ""
        var respondido = false
        let responder: (Result<Void, Error>) -> Void = { [weak self] r in
            guard !respondido else { return }; respondido = true
            if case .success = r { self?.conectado = true }; completion(r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard !respondido else { return }
            self?.disconnect(); responder(.failure(ScribeError.ws("Gladia: conexión tardó más de 5 s")))
        }
        // 1) POST /v2/live para obtener la URL del WebSocket.
        var req = URLRequest(url: URL(string: "https://api.gladia.io/v2/live")!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-gladia-key")
        let cfg: [String: Any] = [
            "encoding": "wav/pcm", "sample_rate": 16000, "bit_depth": 16, "channels": 1,
            "language_config": ["languages": ["es"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: cfg)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            guard err == nil, let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urlStr = j["url"] as? String, let url = URL(string: urlStr) else {
                DispatchQueue.main.async { responder(.failure(ScribeError.ws("Gladia: no dio URL de WS"))) }; return
            }
            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: url)
            self.session = session; self.task = task
            task.resume()
            self.receiveLoop()
            DispatchQueue.main.async { responder(.success(())) }
        }.resume()
    }

    func send(chunk: Data) { task?.send(.data(chunk)) { [weak self] e in if let e { DispatchQueue.main.async { self?.onError?(e.localizedDescription) } } } }
    func finalizar() { if let d = try? JSONSerialization.data(withJSONObject: ["type": "stop_recording"]), let s = String(data: d, encoding: .utf8) { task?.send(.string(s)) { _ in } } }
    func fullText() -> String { finales.trimmingCharacters(in: .whitespacesAndNewlines) }
    func disconnect() { cerrando = true; task?.cancel(with: .normalClosure, reason: nil); task = nil; session?.invalidateAndCancel(); session = nil }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { guard !self.cerrando else { return }; self.conectado = false; self.onError?("Gladia: conexión cerrada") }
            case .success(let m):
                if case .string(let t) = m { self.handle(t) }
                self.receiveLoop()
            }
        }
    }

    /// (text, isFinal) de un mensaje "transcript" de Gladia, o nil.
    static func parse(_ text: String) -> (String, Bool)? {
        guard let data = text.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (j["type"] as? String) == "transcript",
              let d = j["data"] as? [String: Any] else { return nil }
        let utt = d["utterance"] as? [String: Any]
        guard let t = (utt?["text"] as? String) ?? (d["text"] as? String) else { return nil }
        return (t, (d["is_final"] as? Bool) ?? false)
    }

    private func handle(_ text: String) {
        guard let (t, fin) = Self.parse(text) else { return }
        DispatchQueue.main.async {
            if fin { self.finales += (self.finales.isEmpty ? "" : " ") + t; self.parcial = "" }
            else { self.parcial = t }
            let vis = (self.finales + " " + self.parcial).trimmingCharacters(in: .whitespacesAndNewlines)
            self.onPartial?(vis)
        }
    }
}
