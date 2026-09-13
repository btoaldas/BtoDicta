import Foundation

// MARK: - Voxtral local residente (motor llama.cpp, mismo patrón que WhisperServer)
//
// Carga bajo demanda al empezar el dictado y se apaga tras N segundos sin uso.
// llama-server abre el puerto ANTES de terminar de cargar (responde 503):
// el cliente reintenta ante conexión rechazada Y ante 503 hasta ~60 s.

enum VoxtralServer {
    private static let host = "127.0.0.1"
    private static let port = 8180
    private static var process: Process?
    private static var modeloCargado: String?
    private static var apagador: DispatchWorkItem?
    private static let lock = NSLock()

    static var modelsDir: URL { Config.dir.appendingPathComponent("models") }

    static var pesosURL: URL? {
        guard let m = Providers.modelo(de: "voxtral_local") else { return nil }
        return modelsDir.appendingPathComponent(m)
    }
    static var mmprojURL: URL? {
        guard let m = Providers.modelo(de: "voxtral_local") else { return nil }
        // El proyector acompaña a los pesos: mismo sufijo de versión.
        let mmproj = "mmproj-" + m.replacingOccurrences(of: "-Q4_K_M.gguf", with: "-Q8_0.gguf")
        return modelsDir.appendingPathComponent(mmproj)
    }

    static var serverBinURL: URL? {
        if let p = Bundle.main.path(forResource: "llama-server", ofType: nil, inDirectory: "bin") { return URL(fileURLWithPath: p) }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("llama.cpp-static/build/bin/llama-server")
        for ruta in [dev.path, "/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
        where FileManager.default.isExecutableFile(atPath: ruta) {
            return URL(fileURLWithPath: ruta)
        }
        return nil
    }

    /// Estado para la UI: qué le falta a este motor para funcionar.
    static var diagnostico: String? {
        if serverBinURL == nil { return "falta el motor llama.cpp" }
        guard let m = Providers.modelo(de: "voxtral_local"),
              let cat = ModelCatalog.exoticos.first(where: { $0.archivos.first == m }) else {
            return "modelo no reconocido"
        }
        guard cat.descargado else { return "falta descargar el modelo (o quedó a medias)" }
        return nil
    }

    static var corriendo: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// Lanza el server si el proveedor está activo en la cadena y no corre.
    /// Solo aplica al Voxtral 3B (llama.cpp); el Realtime 4B usa bto-stream.
    static func precalentar() {
        guard let prov = Providers.cadena().first(where: { $0.id == "voxtral_local" }),
              !TcppStreamClient.esModeloStreaming(prov.modelo ?? "") else { return }
        guard let bin = serverBinURL, let pesos = pesosURL, let mm = mmprojURL,
              diagnostico == nil else { return }
        let modelo = pesos.lastPathComponent

        lock.lock()
        if process?.isRunning == true && modeloCargado == modelo {
            lock.unlock()
            tocar()
            return
        }
        process?.terminate()
        process = nil

        let p = Process()
        p.executableURL = bin
        p.arguments = ["-m", pesos.path, "--mmproj", mm.path,
                       "--host", host, "--port", "\(port)",
                       "-ngl", "99", "--no-webui"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
            modeloCargado = modelo
            lock.unlock()
            Log.log(.ia, "voxtral-server precalentando \(modelo) (pid \(p.processIdentifier))")
            tocar()
        } catch {
            process = nil
            modeloCargado = nil
            lock.unlock()
            Log.log(.ia, "voxtral-server no arrancó: \(error.localizedDescription)")
        }
    }

    static func tocar() {
        DispatchQueue.main.async {
            apagador?.cancel()
            let w = DispatchWorkItem { apagar(motivo: "\(Int(Config.whisperKeepAlive()))s sin uso") }
            apagador = w
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.whisperKeepAlive(), execute: w)
        }
    }

    static func apagar(motivo: String = "cierre") {
        lock.lock()
        let p = process
        process = nil
        modeloCargado = nil
        lock.unlock()
        apagador?.cancel()
        apagador = nil
        if let p, p.isRunning {
            p.terminate()
            Log.log(.ia, "voxtral-server apagado (\(motivo)) — memoria liberada")
        }
    }

    /// Mata llama-servers huérfanos de sesiones anteriores en nuestro puerto.
    static func limpiarHuerfanos() {
        lock.lock()
        let propio = process?.processIdentifier
        lock.unlock()
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-f", "llama-server.*--port \(port)( |$)"]
        let pipe = Pipe()
        pg.standardOutput = pipe
        guard (try? pg.run()) != nil else { return }
        pg.waitUntilExit()
        let salida = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for linea in salida.split(separator: "\n") {
            guard let pid = Int32(linea.trimmingCharacters(in: .whitespaces)), pid != propio else { continue }
            kill(pid, SIGTERM)
            Log.log(.ia, "voxtral-server huérfano (pid \(pid)) eliminado")
        }
    }

    /// Transcribe mandando el WAV como audio multimodal al chat de llama.cpp.
    static func transcribe(wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard corriendo else { completion(.failure(ScribeError.ws("voxtral no corre"))); return }

        var instruccion = "Transcribe literalmente el audio en español latino. Responde ÚNICAMENTE con la transcripción, sin comentarios ni prefijos."
        let glosario = Config.glosarioPrompt()
        if !glosario.isEmpty { instruccion += " \(glosario)" }

        let cuerpo = cuerpoPeticion(wav: wav, instruccion: instruccion)

        var req = URLRequest(url: URL(string: "http://\(host):\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        let segundosAudio = Double(max(wav.count - 44, 0)) / 32000.0
        req.timeoutInterval = min(120, max(45, segundosAudio * 2))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)

        postear(req, deadline: Date().addingTimeInterval(60), completion: completion)
    }

    /// llama.cpp/Voxtral necesita recibir primero la instrucción y después el
    /// audio. Con el orden inverso el modelo interpreta el texto como una tarea
    /// posterior al audio y puede responder "No puedo realizar esa tarea".
    static func cuerpoPeticion(wav: Data, instruccion: String) -> [String: Any] {
        [
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": instruccion],
                    ["type": "input_audio",
                     "input_audio": ["data": wav.base64EncodedString(), "format": "wav"]],
                ],
            ]],
        ]
    }

    /// QA puro: no arranca llama.cpp ni toca modelos/configuración.
    static func problemaPayloadQA() -> String? {
        let wav = Data([0, 1, 2, 3, 254, 255])
        let instruccion = "Transcribe esta prueba"
        let cuerpo = cuerpoPeticion(wav: wav, instruccion: instruccion)
        guard let mensajes = cuerpo["messages"] as? [[String: Any]], mensajes.count == 1,
              let contenido = mensajes[0]["content"] as? [[String: Any]], contenido.count == 2 else {
            return "estructura messages/content inválida"
        }
        guard contenido[0]["type"] as? String == "text",
              contenido[0]["text"] as? String == instruccion else {
            return "la instrucción no está primero"
        }
        guard contenido[1]["type"] as? String == "input_audio",
              let audio = contenido[1]["input_audio"] as? [String: String],
              audio["format"] == "wav",
              let base64 = audio["data"], Data(base64Encoded: base64) == wav else {
            return "el audio WAV no está segundo o perdió bytes"
        }
        return nil
    }

    /// POST con reintentos mientras el server carga (conexión rechazada o 503).
    private static func postear(_ req: URLRequest, deadline: Date,
                                completion: @escaping (Result<String, Error>) -> Void) {
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let rechazada = (err as NSError?).map {
                    $0.code == NSURLErrorCannotConnectToHost || $0.code == NSURLErrorNetworkConnectionLost
                } ?? false
                if (rechazada || code == 503) && corriendo && Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        postear(req, deadline: deadline, completion: completion)
                    }
                    return
                }
                if let err { completion(.failure(err)); return }
                guard let data, (200..<300).contains(code),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let msg = choices.first?["message"] as? [String: Any],
                      let texto = (msg["content"] as? String)?
                          .trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty else {
                    completion(.failure(ScribeError.ws("voxtral respondió mal (HTTP \(code))")))
                    return
                }
                tocar()
                // El LLM a veces envuelve la transcripción en comillas: fuera.
                var limpio = texto
                for (a, c) in [("\"", "\""), ("«", "»"), ("'", "'")]
                where limpio.hasPrefix(a) && limpio.hasSuffix(c) && limpio.count > 2 {
                    limpio = String(limpio.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespaces)
                }
                completion(.success(limpio))
            }
        }.resume()
    }
}
