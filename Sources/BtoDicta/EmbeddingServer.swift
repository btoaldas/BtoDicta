import Foundation

// MARK: - Motor de embeddings INTERNO de BtoDicta (sin Ollama, sin nada externo)
//
// BtoDicta ya embarca `llama-server` (lo usa Voxtral). Ese mismo binario sirve
// embeddings con --embedding. El modelo es bge-m3 en GGUF (el MISMO modelo del default
// de Ollama, misma calidad) y se DESCARGA bajo demanda con permiso (~417 MB, una vez).
// Sirve para los 3 usos que pasan por EmbeddingSearch: modos semánticos, búsqueda del
// historial y glosario inteligente. Con idle-sleep: se apaga solo tras 10 min sin uso
// (libera ~600 MB de RAM) y revive on-demand.

enum EmbeddingServer {
    static let puerto = 8798
    static var dir: URL { Config.dir.appendingPathComponent("embeddings-engine") }
    static var modeloURL: URL { dir.appendingPathComponent("bge-m3-Q4_K_M.gguf") }
    /// Fuente VERIFICADA (2026-07-17): gpustack/bge-m3-GGUF, Q4_K_M = 417 MB.
    static let urlDescarga = "https://huggingface.co/gpustack/bge-m3-GGUF/resolve/main/bge-m3-Q4_K_M.gguf"

    private static var proceso: Process?
    private static var adoptado = false
    private static var ultimoUso = Date()
    private static var vigia: Timer?

    static var instalado: Bool { FileManager.default.fileExists(atPath: modeloURL.path) }
    static var corriendo: Bool { proceso?.isRunning == true || adoptado }

    /// El llama-server embarcado (bundle) o, en desarrollo, el de Homebrew.
    static func binario() -> String? {
        let candidatos = [
            Bundle.main.resourcePath.map { $0 + "/bin/llama-server" } ?? "",
            "/Applications/BtoDicta.app/Contents/Resources/bin/llama-server",
            "/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server",
        ]
        return candidatos.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var disponible: Bool { instalado && binario() != nil }

    /// Descarga el modelo (una vez, reanudable con -C -). `onProgreso` con líneas legibles.
    static func descargar(onProgreso: @escaping (String) -> Void,
                          completion: @escaping (Bool, String) -> Void) {
        if instalado { completion(true, "El modelo ya está."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let part = modeloURL.path + ".part"
            onProgreso("Descargando bge-m3 (~417 MB, una sola vez)…")
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-L", "-C", "-", "--retry", "3", urlDescarga, "-o", part]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit() } catch {
                DispatchQueue.main.async { completion(false, "No pude descargar el modelo.") }; return
            }
            if p.terminationStatus == 0, fm.fileExists(atPath: part) {
                try? fm.removeItem(at: modeloURL)
                try? fm.moveItem(atPath: part, toPath: modeloURL.path)
            }
            let ok = instalado
            DispatchQueue.main.async { completion(ok, ok ? "Motor interno listo." : "Descarga incompleta (se reanuda al reintentar).") }
        }
    }

    /// Asegura el server arriba (arranca si hace falta; el primer uso espera la carga).
    static func asegurar(_ listo: @escaping (Bool) -> Void) {
        ultimoUso = Date()
        guard disponible else { listo(false); return }
        if corriendo { listo(true); return }
        // Si un server de una corrida anterior sigue vivo en el puerto (huérfano tras
        // reiniciar la app), lo ADOPTAMOS en vez de chocar con el bind.
        if ping() { adoptado = true; iniciarVigilancia(); listo(true); return }
        guard let bin = binario() else { listo(false); return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", modeloURL.path, "--embedding", "--port", "\(puerto)",
                       "--host", "127.0.0.1", "-c", "512", "--log-disable"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { listo(false); return }
        proceso = p
        iniciarVigilancia()
        DispatchQueue.global().async {
            for _ in 0..<40 {
                Thread.sleep(forTimeInterval: 0.5)
                if !p.isRunning { DispatchQueue.main.async { listo(false) }; return }
                if ping() { DispatchQueue.main.async { listo(true) }; return }
            }
            DispatchQueue.main.async { listo(false) }
        }
    }

    static func detener() {
        if proceso?.isRunning == true { proceso?.terminate() }
        else if adoptado {
            // Huérfano adoptado: se apaga por pkill del binario+puerto (sin PID propio).
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-f", "llama-server.*--port \(puerto)"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        proceso = nil; adoptado = false
    }

    static func tocar() { ultimoUso = Date() }

    /// Idle-sleep: sin uso por 10 min → se apaga (libera RAM). Revive on-demand.
    private static func iniciarVigilancia() {
        guard vigia == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { _ in
            guard corriendo, Date().timeIntervalSince(ultimoUso) > 600 else { return }
            Log.log(.ia, "motor de embeddings interno dormido por inactividad")
            detener()
        }
        RunLoop.main.add(t, forMode: .common); vigia = t
    }

    private static func ping() -> Bool {
        guard let u = URL(string: "http://127.0.0.1:\(puerto)/health") else { return false }
        var r = URLRequest(url: u); r.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5); return ok
    }
}
