import Foundation

// MARK: - Motor PIPER (voz FIJA .onnx, RÁPIDA, 100% local) — el carril veloz
//
// Piper (VITS/ONNX) sintetiza ~5x tiempo real en CPU → casi instantáneo, sin torch.
// A diferencia del XTTS (clona cualquier voz pero va ~tiempo real), Piper usa una voz
// FIJA horneada (entrenada). Aquí se ENTRENA la voz de Alberto en Piper (con el mismo
// dataset) y luego corre rapidísima. XTTS se queda para calidad/clonar al vuelo.
//
// Corre con el Python del motor: `python -m piper -m voz.onnx -f salida.wav` (texto por
// stdin). Falla suave → nil → el llamador hace failover.

enum PiperTTS {
    static var disponible: Bool { VozEngine.estado() == .listo }

    /// Sintetiza `texto` con la voz .onnx y devuelve el wav (o nil).
    static func decir(onnx: URL, texto: String, completion: @escaping (URL?) -> Void) {
        guard disponible, FileManager.default.fileExists(atPath: onnx.path) else { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let salida = FileManager.default.temporaryDirectory
                .appendingPathComponent("piper-\(abs(texto.hashValue)).wav")
            let p = Process(); p.executableURL = VozEngine.pythonURL
            p.arguments = ["-m", "piper", "-m", onnx.path, "-f", salida.path]
            p.environment = ProcessInfo.processInfo.environment
            let inPipe = Pipe(); p.standardInput = inPipe
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                inPipe.fileHandleForWriting.write(texto.data(using: .utf8) ?? Data())
                inPipe.fileHandleForWriting.closeFile()
                p.waitUntilExit()
            } catch { DispatchQueue.main.async { completion(nil) }; return }
            let ok = p.terminationStatus == 0 && FileManager.default.fileExists(atPath: salida.path)
            DispatchQueue.main.async { completion(ok ? salida : nil) }
        }
    }
}
