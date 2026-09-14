import Foundation

// MARK: - Motor transcribe.cpp (Nemotron, Parakeet, Canary… — el motor de Handy)
//
// CLI efímero: carga el modelo, transcribe y muere (los modelos son chicos,
// ~500-750 MB, cargan en segundos). Sin glosario nativo — los reemplazos
// corrigen después, como siempre. Nemotron 3.5 streaming es multilingüe
// (40 locales) con puntuación y mayúsculas nativas.

enum TranscribeCpp {
    static var modelsDir: URL { Config.dir.appendingPathComponent("models") }

    static var cliURL: URL? {
        if let p = Bundle.main.path(forResource: "transcribe-cli", ofType: nil, inDirectory: "bin") { return URL(fileURLWithPath: p) }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("transcribe.cpp/build/bin/transcribe-cli")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    /// Estado para la UI: qué le falta a este motor.
    static func diagnostico(modelo archivo: String) -> String? {
        if cliURL == nil { return "falta el motor transcribe.cpp (~/transcribe.cpp)" }
        let m = modelsDir.appendingPathComponent(archivo)
        guard FileManager.default.fileExists(atPath: m.path) else { return "falta descargar el modelo" }
        return nil
    }

    /// ¿El archivo de modelo está descargado en la carpeta de modelos?
    static func descargado(_ archivo: String) -> Bool {
        !archivo.isEmpty && FileManager.default.fileExists(
            atPath: modelsDir.appendingPathComponent(archivo).path)
    }

    /// Los modelos ggml de whisper (.bin) los ejecuta whisper-cli, no
    /// transcribe-cli: se despacha solo para que quien llama no lo sepa.
    static func run(wav: Data, modelo archivo: String,
                    completion: @escaping (Result<String, Error>) -> Void) {
        if archivo.hasSuffix(".bin") {
            WhisperCLI.run(wav: wav, modelo: archivo, completion: completion); return
        }
        guard let cli = cliURL else {
            completion(.failure(ScribeError.ws("transcribe-cli no encontrado"))); return
        }
        let modelURL = modelsDir.appendingPathComponent(archivo)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            completion(.failure(ScribeError.ws("Falta el modelo — descárgalo en Modelos"))); return
        }
        DispatchQueue.global().async {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("beto-\(UUID().uuidString).wav")
            try? wav.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let task = Process()
            task.executableURL = cli
            // Cada familia pide su código: Nemotron usa locale (es-US), Canary
            // el corto (es), y los realtime solo auto-detectan (sin flag).
            let bajo = archivo.lowercased()
            var args = ["-m", modelURL.path]
            if bajo.contains("nemotron") {
                args += ["--language", "es-US"]
            } else if !bajo.contains("realtime") {
                args += ["--language", "es"]
            }
            args.append(tmp.path)
            task.arguments = args
            let out = Pipe()
            task.standardOutput = out
            task.standardError = Pipe()
            do {
                try task.run()
                let guardia = WhisperCLI.vigilar(task, wav: wav.count)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                guardia.cancel()
                let salida = String(data: data, encoding: .utf8) ?? ""
                // La transcripción viene en la línea "text: …"
                let texto = salida.split(separator: "\n")
                    .first { $0.hasPrefix("text: ") }
                    .map { String($0.dropFirst("text: ".count)) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    texto.isEmpty ? completion(.failure(ScribeError.sinTexto))
                                  : completion(.success(texto))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
