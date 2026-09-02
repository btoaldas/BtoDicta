import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Cliente streaming (scribe_v2_realtime, texto en vivo)

final class StreamClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var committedPieces: [String] = []

    var onPartial: ((String) -> Void)?
    var onCommitted: ((String) -> Void)?
    var onError: ((String) -> Void)?
    /// La sesión murió a mitad del dictado (el servidor cerró por cuota o
    /// clave, o la red cayó). Se avisa UNA vez, para que quien dicta pase al
    /// plan B con todo el audio acumulado en vez de seguir enviando al vacío.
    var onCierre: ((String) -> Void)?
    private var cierreAvisado = false

    /// Circuit breaker: si el WS acaba de fallar (red caída), los próximos
    /// dictados van DIRECTO a grabar sin esperar otro timeout de conexión.
    private static var ultimoFallo: Date?
    static var enCuarentena: Bool {
        guard let f = ultimoFallo else { return false }
        return Date().timeIntervalSince(f) < 60
    }
    static func registrarFallo() { ultimoFallo = Date() }
    static func registrarExito() { ultimoFallo = nil }

    /// true cuando el servidor confirmó la sesión (session_started).
    private(set) var conectado = false

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let key = Config.apiKey() else {
            completion(.failure(ScribeError.sinApiKey))
            return
        }
        committedPieces = []

        // Tope de conexión: con red mala el TLS puede colgarse un minuto;
        // a los 4 s cortamos y el dictado sigue por otro camino.
        var respondido = false
        let responder: (Result<Void, Error>) -> Void = { [weak self] r in
            guard !respondido else { return }
            respondido = true
            if case .success = r { self?.conectado = true }
            completion(r)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard !respondido else { return }
            self?.disconnect()
            responder(.failure(ScribeError.ws("conexión tardó más de 4 s")))
        }
        conectar(key: key, completion: responder)
    }

    private func conectar(key: String, completion: @escaping (Result<Void, Error>) -> Void) {

        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
            URLQueryItem(name: "language_code", value: "es"),
        ]
        // El WS acepta máx. 50 keyterms de hasta 20 caracteres
        var seen = Set<String>()
        for term in Config.keyterms() {
            let t = term.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 20, !seen.contains(t.lowercased()) else { continue }
            seen.insert(t.lowercased())
            items.append(URLQueryItem(name: "keyterms", value: t))
            if seen.count == 50 { break }
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()

        task.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(ScribeError.ws(error.localizedDescription)))
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["message_type"] as? String {
                        if type == "session_started" {
                            self?.receiveLoop()
                            completion(.success(()))
                        } else {
                            let msg = json["message"] as? String ?? type
                            completion(.failure(ScribeError.ws(msg)))
                        }
                    } else {
                        self?.receiveLoop()
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func send(chunk: Data) {
        // Sin sesión viva no hay a quién mandar: enviar a un socket que el
        // servidor cerró fallaba diez veces por segundo durante TODO el dictado
        // (un buffer de micrófono cada 100 ms) y llenaba el registro — 19 539
        // líneas en tres días — sin que nadie pasara al plan B.
        guard conectado else { return }
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": chunk.base64EncodedString(),
            "commit": false,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func commit() {
        guard conectado else { return }
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": 16000,
        ]
        sendJSON(message)
    }

    func fullText() -> String {
        committedPieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// true cuando NOSOTROS cerramos: el error de cancelación que dispara el
    /// receive pendiente no es un fallo de red y no debe activar cuarentena.
    private var cerrando = false

    func disconnect() {
        cerrando = true
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.onError?(error.localizedDescription) }
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // Conexión muerta a mitad del dictado: marcarlo para que el
                // cierre tome la ruta de rescate (cascada con el wav completo).
                // OJO: si NOSOTROS desconectamos (cierre normal tras un dictado
                // exitoso), este .failure es la cancelación esperada — contarlo
                // como red caída mandaba a cuarentena tras CADA dictado bueno.
                DispatchQueue.main.async {
                    guard !self.cerrando else { return }
                    self.conectado = false
                    StreamClient.registrarFallo()
                    self.avisarCierre("conexión perdida: \(error.localizedDescription)")
                }
                return
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["message_type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "partial_transcript":
                if let t = json["text"] as? String { self.onPartial?(t) }
            case "committed_transcript", "committed_transcript_with_timestamps":
                if let t = json["text"] as? String, !t.isEmpty {
                    self.committedPieces.append(t)
                    self.onCommitted?(self.fullText())
                }
            case "quota_exceeded", "auth_error", "rate_limited", "resource_exhausted":
                // El servidor va a cerrar la sesión: sin cuota o sin clave. Es
                // la cuarentena REAL del proveedor (30 min; 5 min si es tope de
                // ritmo), no la breve de «red caída»: la cascada por lotes y la
                // siguiente sesión en vivo lo saltan de plano.
                let codigo = (type == "rate_limited" || type == "resource_exhausted") ? 429 : 401
                CuarentenaSTT.registrar("elevenlabs", nombre: "ElevenLabs",
                                        error: ScribeError.http(codigo, type))
                self.onError?(json["message"] as? String ?? type)
                self.conectado = false
                self.avisarCierre(type)
            case "error", "session_time_limit_exceeded",
                 "input_error", "chunk_size_exceeded", "transcriber_error":
                self.onError?(json["message"] as? String ?? type)
            default:
                break
            }
        }
    }

    private func avisarCierre(_ motivo: String) {
        guard !cierreAvisado else { return }
        cierreAvisado = true
        onCierre?(motivo)
    }

    /// Solo para la prueba de robustez: inyecta un mensaje como si viniera
    /// del servidor (mismo camino que `receiveLoop`).
    func inyectarParaPrueba(_ texto: String) { handle(texto) }
}

