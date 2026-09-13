import Foundation

// MARK: - Cliente streaming Deepgram (STT en vivo por WebSocket)
//
// Igual carril que StreamClient (ElevenLabs), pero para Deepgram: manda el PCM
// CRUDO (linear16 16 kHz) como mensajes binarios y recibe resultados con
// is_final. Los interim (is_final=false) pintan el parcial; los finales se
// acumulan. Opt-in (Config.sttStreaming), additivo: si está apagado, el motor
// nube sigue siendo por lotes como siempre.

final class DeepgramStreamClient: NSObject, LiveNubeSTT {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finales: [String] = []        // segmentos ya finalizados (is_final)
    private var cerrando = false

    var onPartial: ((String) -> Void)?        // texto acumulado + interim actual
    var onError: ((String) -> Void)?
    private(set) var conectado = false

    /// Circuit breaker compartido con el de ElevenLabs no aplica; propio.
    private static var ultimoFallo: Date?
    static var enCuarentena: Bool {
        guard let f = ultimoFallo else { return false }
        return Date().timeIntervalSince(f) < 60
    }
    static func registrarFallo() { ultimoFallo = Date() }

    func connect(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let key = ApiKeys.get("DEEPGRAM_API_KEY")
        guard !key.isEmpty else { completion(.failure(ScribeError.sinApiKey)); return }
        finales = []
        var comp = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        comp.queryItems = [
            URLQueryItem(name: "model", value: model.isEmpty ? "nova-3" : model),
            URLQueryItem(name: "language", value: "es"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
        ]
        // Glosario → keyterm (Nova-3 usa "keyterm"; "keywords" era de Nova-2).
        for term in Config.keyterms().prefix(50) {
            let t = term.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { comp.queryItems?.append(URLQueryItem(name: "keyterm", value: t)) }
        }
        var req = URLRequest(url: comp.url!)
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")

        var respondido = false
        let responder: (Result<Void, Error>) -> Void = { [weak self] r in
            guard !respondido else { return }
            respondido = true
            if case .success = r { self?.conectado = true }
            completion(r)
        }
        // Tope de conexión de 4 s (igual que ElevenLabs): con red mala, seguir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard !respondido else { return }
            self?.disconnect()
            responder(.failure(ScribeError.ws("Deepgram: conexión tardó más de 4 s")))
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: req)
        self.session = session; self.task = task
        task.resume()
        // Deepgram no manda un "session_started": si el WS abre, ya escucha.
        // Se confirma con el primer receive OK (o el timeout de arriba).
        receiveLoop(primerResponder: responder)
        // Considera conectado en cuanto la tarea corre; el receiveLoop avisa fallos.
        responder(.success(()))
    }

    func send(chunk: Data) {
        task?.send(.data(chunk)) { [weak self] error in
            if let error { DispatchQueue.main.async { self?.onError?(error.localizedDescription) } }
        }
    }

    /// Cierra el stream pidiendo a Deepgram que finalice lo pendiente.
    func finalizar() {
        guard let task else { return }
        if let data = try? JSONSerialization.data(withJSONObject: ["type": "CloseStream"]),
           let s = String(data: data, encoding: .utf8) {
            task.send(.string(s)) { _ in }
        }
    }

    func fullText() -> String {
        finales.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func disconnect() {
        cerrando = true
        task?.cancel(with: .normalClosure, reason: nil); task = nil
        session?.invalidateAndCancel(); session = nil
    }

    private func receiveLoop(primerResponder: ((Result<Void, Error>) -> Void)? = nil) {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async {
                    guard !self.cerrando else { return }
                    self.conectado = false
                    DeepgramStreamClient.registrarFallo()
                    self.onError?("Deepgram: conexión cerrada")
                }
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop()
            }
        }
    }

    /// Parsea un mensaje de Deepgram. Estático + público para poder probarlo sin
    /// una conexión real. Devuelve (transcript, is_final) o nil si no aplica.
    static func parse(_ text: String) -> (String, Bool)? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Solo mensajes de resultados (ignora Metadata, SpeechStarted, etc.).
        if let type = json["type"] as? String, type != "Results" { return nil }
        let canal = json["channel"] as? [String: Any]
        let alts = canal?["alternatives"] as? [[String: Any]]
        guard let t = alts?.first?["transcript"] as? String else { return nil }
        let final = (json["is_final"] as? Bool) ?? false
        return (t, final)
    }

    private func handle(_ text: String) {
        guard let (t, final) = Self.parse(text) else { return }
        DispatchQueue.main.async {
            if final {
                if !t.isEmpty { self.finales.append(t) }
                self.onPartial?(self.fullText())
            } else {
                // Interim: texto acumulado + el segmento en curso.
                let base = self.fullText()
                let vis = t.isEmpty ? base : (base.isEmpty ? t : base + " " + t)
                self.onPartial?(vis)
            }
        }
    }
}
