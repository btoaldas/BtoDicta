import Foundation

// MARK: - whisper.cpp por lotes (binario whisper-cli del paquete)
//
// Camino OFFLINE de whisper: sin estado de streaming, sin ventana deslizante
// y sin token de fin que congele el decodificador. Es el verificador de la
// red de seguridad del dictado: un audio de 15 minutos tarda ~25 s con
// large-v3-turbo en Apple Silicon.
enum WhisperCLI {
    static var cliURL: URL? {
        if let p = Bundle.main.path(forResource: "whisper-cli", ofType: nil, inDirectory: "bin") {
            return URL(fileURLWithPath: p)
        }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("whisper.cpp/build/bin/whisper-cli")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    static func run(wav: Data, modelo archivo: String,
                    completion: @escaping (Result<String, Error>) -> Void) {
        guard let cli = cliURL else {
            completion(.failure(ScribeError.ws("whisper-cli no encontrado"))); return
        }
        let modelURL = TranscribeCpp.modelsDir.appendingPathComponent(archivo)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            completion(.failure(ScribeError.ws("Falta el modelo \(archivo)"))); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("beto-red-\(UUID().uuidString).wav")
            try? wav.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let salidaBase = tmp.deletingPathExtension()
            let salidaTxt = salidaBase.appendingPathExtension("txt")
            defer { try? FileManager.default.removeItem(at: salidaTxt) }
            let task = Process()
            task.executableURL = cli
            // El texto se recoge del ARCHIVO, no de stdout: medido, la salida
            // por consola pierde segmentos (1 368 palabras frente a 2 315 del
            // archivo sobre el mismo audio).
            task.arguments = ["-m", modelURL.path, "-l", "es", "-otxt",
                              "-of", salidaBase.path, "-f", tmp.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                let texto = ((try? String(contentsOf: salidaTxt, encoding: .utf8)) ?? "")
                    .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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
