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

    static func run(wav: CuerpoMultipart.Origen, modelo archivo: String,
                    completion: @escaping (Result<String, Error>) -> Void) {
        guard let cli = cliURL else {
            completion(.failure(ScribeError.ws("whisper-cli no encontrado"))); return
        }
        let modelURL = TranscribeCpp.modelsDir.appendingPathComponent(archivo)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            completion(.failure(ScribeError.ws("Falta el modelo \(archivo)"))); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            // Enlace duro al audio, no copia: el binario escribe su salida junto
            // al archivo de entrada, así que necesita una ruta temporal, pero no
            // hay por qué duplicar el audio para dársela.
            guard let enlace = wav.enlaceTemporal(prefijo: "btodicta-cli") else {
                DispatchQueue.main.async { completion(.failure(ScribeError.ws("no pude preparar el audio para el motor local"))) }
                return
            }
            let tmp = enlace.url
            defer { if enlace.retirar { try? FileManager.default.removeItem(at: tmp) } }
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
                let guardia = vigilar(task, wav: wav.bytes)
                task.waitUntilExit()
                guardia.cancel()
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

    /// Perro guardián del proceso, compartido con `TranscribeCpp`.
    ///
    /// `waitUntilExit()` espera PARA SIEMPRE. Si el binario se atasca —modelo a
    /// medio descargar, disco lleno, memoria agotada— el hilo queda colgado y
    /// la llamada no devuelve nunca: quien esperaba el texto no recibe ni
    /// siquiera un error, y el dictado se queda en el aire. Se le da un margen
    /// generoso y proporcional al audio, porque esto tiene que funcionar
    /// también en un equipo lento, y pasado ese margen se le manda parar:
    /// entonces `waitUntilExit` devuelve y el fallo se puede tratar.
    ///
    /// Quien lo llama debe cancelar la guardia al terminar bien.
    static func vigilar(_ task: Process, wav bytes: Int) -> DispatchWorkItem {
        let segundos = Double(max(0, bytes - 44)) / Double(RedSeguridadDictado.bytesPorSegundo)
        let margen = max(120.0, segundos * 6)
        let guardia = DispatchWorkItem {
            guard task.isRunning else { return }
            Log.log(.ia, "transcripción por lotes atascada más de \(Int(margen)) s — detengo el proceso")
            task.terminate()
            // Si a los 5 s sigue vivo es que no atiende señales suaves.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + margen, execute: guardia)
        return guardia
    }
}
