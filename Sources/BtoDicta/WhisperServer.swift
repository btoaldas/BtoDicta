import Foundation

// MARK: - Whisper local residente (carga bajo demanda + descarga por inactividad)
//
// El modelo local NO vive siempre en memoria. Al empezar un dictado se
// precalienta un whisper-server (carga el modelo mientras grabas); tras cada
// uso tiene N segundos (default 120) para recibir otro dictado. Si no llega,
// se apaga solo y libera la RAM. Si llega, el contador se renueva.

enum WhisperServer {
    private static let host = "127.0.0.1"
    private static let port = 8178
    private static var process: Process?
    private static var modeloCargado: String?
    private static var apagador: DispatchWorkItem?
    private static let lock = NSLock()

    static var keepAliveSegundos: TimeInterval { Config.whisperKeepAlive() }

    static var serverURL: URL? {
        // 1) binario bundleado en la app  2) build local de whisper.cpp
        if let p = Bundle.main.path(forResource: "whisper-server", ofType: nil, inDirectory: "bin") { return URL(fileURLWithPath: p) }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("whisper.cpp/build/bin/whisper-server")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    static var corriendo: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// Lanza el server si el proveedor local está activo y aún no corre.
    /// Se llama al APLASTAR la tecla de dictado: el modelo carga mientras hablas.
    static func precalentar() {
        guard Providers.cadena().contains(where: { $0.id == "whisper_local" }) else { return }
        guard let bin = serverURL else { return }
        let modelo = WhisperLocal.modeloArchivo
        guard FileManager.default.fileExists(atPath: WhisperLocal.modelURL.path) else { return }

        lock.lock()
        // Si ya corre con el mismo modelo, solo renovar la vida.
        if process?.isRunning == true && modeloCargado == modelo {
            lock.unlock()
            tocar()
            return
        }
        // Modelo cambió o server muerto: reiniciar limpio.
        process?.terminate()
        process = nil

        let p = Process()
        p.executableURL = bin
        // El glosario NO se fija aquí: va por request en transcribe(), así
        // editar keyterms.txt aplica al instante sin reiniciar el server.
        p.arguments = ["-m", WhisperLocal.modelURL.path, "-l", "es",
                       "--host", host, "--port", "\(port)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            process = p
            modeloCargado = modelo
            lock.unlock()
            Log.log(.ia, "whisper-server precalentando \(modelo) (pid \(p.processIdentifier))")
            tocar()
        } catch {
            process = nil
            modeloCargado = nil
            lock.unlock()
            Log.log(.ia, "whisper-server no arrancó: \(error.localizedDescription)")
        }
    }

    /// Renueva el contador de vida: N segundos más desde ahora.
    /// Siempre en main para no correr carreras con el propio timer.
    static func tocar() {
        DispatchQueue.main.async {
            apagador?.cancel()
            let w = DispatchWorkItem { apagar(motivo: "\(Int(keepAliveSegundos))s sin uso") }
            apagador = w
            DispatchQueue.main.asyncAfter(deadline: .now() + keepAliveSegundos, execute: w)
        }
    }

    /// Apaga el server y libera la memoria del modelo.
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
            Log.log(.ia, "whisper-server apagado (\(motivo)) — memoria liberada")
        }
    }

    /// Mata servers huérfanos de sesiones anteriores (crash de la app),
    /// sin tocar el server que ESTA sesión pueda haber lanzado ya.
    static func limpiarHuerfanos() {
        lock.lock()
        let propio = process?.processIdentifier
        lock.unlock()

        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-f", "whisper-server.*--port \(port)( |$)"]
        let pipe = Pipe()
        pg.standardOutput = pipe
        guard (try? pg.run()) != nil else { return }
        pg.waitUntilExit()
        let salida = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for linea in salida.split(separator: "\n") {
            guard let pid = Int32(linea.trimmingCharacters(in: .whitespaces)), pid != propio else { continue }
            kill(pid, SIGTERM)
            Log.log(.ia, "whisper-server huérfano (pid \(pid)) eliminado")
        }
    }

    /// Transcribe vía server residente. Si el puerto aún no abre (el modelo
    /// sigue cargando del precalentamiento), reintenta hasta ~40 s antes de
    /// rendirse; un server colgado no bloquea la cascada más de ese margen.
    static func transcribe(wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard corriendo else { completion(.failure(ScribeError.ws("server local no corre"))); return }
        let boundary = "BtoDicta-\(UUID().uuidString)"
        var body = Data()
        func field(_ n: String, _ v: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!)
        }
        field("response_format", "json")
        field("language", "es")
        // Glosario por request: siempre el keyterms.txt vigente.
        let glosario = Config.glosarioPrompt()
        if !glosario.isEmpty { field("prompt", glosario) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "http://\(host):\(port)/inference")!)
        req.httpMethod = "POST"
        // Acotado: suficiente para el audio dictado, sin secuestrar el failover.
        let segundosAudio = Double(max(wav.count - 44, 0)) / 32000.0
        req.timeoutInterval = min(90, max(30, segundosAudio))
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        postear(req, body: body, deadline: Date().addingTimeInterval(40), completion: completion)
    }

    /// POST con reintentos mientras el server precalienta (puerto todavía
    /// cerrado → conexión rechazada al instante; reintentar no cuesta nada).
    private static func postear(_ req: URLRequest, body: Data, deadline: Date,
                                completion: @escaping (Result<String, Error>) -> Void) {
        URLSession.shared.uploadTask(with: req, from: body) { data, resp, err in
            DispatchQueue.main.async {
                if let err {
                    let e = err as NSError
                    let rechazada = e.code == NSURLErrorCannotConnectToHost || e.code == NSURLErrorNetworkConnectionLost
                    if rechazada && corriendo && Date() < deadline {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            postear(req, body: body, deadline: deadline, completion: completion)
                        }
                        return
                    }
                    completion(.failure(err)); return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String else {
                    completion(.failure(ScribeError.ws("server local respondió mal (HTTP \(code))")))
                    return
                }
                tocar()
                // El server separa segmentos con saltos de línea: aplanar a una sola línea.
                let plano = text.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                completion(.success(plano))
            }
        }.resume()
    }
}
