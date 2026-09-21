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
    private static var vigia: DispatchSourceTimer?
    private static let colaVigia = DispatchQueue(label: "btodicta.embeddings.vigia")
    private static let candadoVigia = NSLock()

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
        // Y se retira el vigía: si no, cada arranque dejaría uno más detrás,
        // todos mirando el mismo reloj.
        candadoVigia.lock()
        vigia?.cancel(); vigia = nil
        candadoVigia.unlock()
    }

    static func tocar() { ultimoUso = Date() }

    /// Cuánto aguanta encendido sin que nadie le pida nada.
    ///
    /// Diez minutos: bastante para no reencenderlo entre dos usos seguidos, poco
    /// para no retener 400 MB toda la tarde. Arrancar en frío cuesta ~1 s, así
    /// que equivocarse por corto es barato.
    static func minutosDeGracia() -> Double {
        // El mínimo es bajo a propósito. Con `max(1, …)` una gracia de seis
        // segundos se convertía en sesenta, y como el vigía miraba cada minuto
        // la espera real llegaba a dos. Eso hacía imposible comprobar el apagado
        // sin esperar minutos, y una prueba que tarda minutos es una prueba que
        // no se corre.
        max(0.05, (Config.json0("embeddings_apagar_tras_minutos") as? Double) ?? 10)
    }

    /// Se duerme solo cuando nadie lo usa, y libera la memoria del modelo.
    /// Revive en el siguiente uso.
    ///
    /// Antes esto era un `Timer` añadido con `RunLoop.main.add(...)`. El problema
    /// es que `asegurar()` se llama desde donde toque —colas de transcripción, de
    /// pulido, del agente—, y meter un temporizador en el bucle del hilo
    /// principal DESDE OTRO HILO no está garantizado: unas veces quedaba
    /// registrado y otras no. Por eso el apagado funcionaba a ratos: medido el
    /// 2026-09-20, el motor llevaba 24 minutos vivo y 22 sin uso, reteniendo
    /// 399 MB, mientras que el día anterior sí se había dormido dos veces.
    ///
    /// Un `DispatchSourceTimer` sobre una cola propia no depende del bucle de
    /// eventos ni de quién lo cree.
    private static func iniciarVigilancia() {
        candadoVigia.lock(); defer { candadoVigia.unlock() }
        guard vigia == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: colaVigia)
        // Se mira a mitad de la gracia, con tope de un minuto: con gracia larga
        // basta mirar de vez en cuando, y con gracia corta hay que mirar pronto
        // o el apagado llegaría al doble de tarde de lo pedido.
        let cada = min(60.0, max(2.0, minutosDeGracia() * 60 / 2))
        t.schedule(deadline: .now() + cada, repeating: cada)
        t.setEventHandler {
            guard corriendo else { return }
            let ocioso = Date().timeIntervalSince(ultimoUso)
            guard ocioso > minutosDeGracia() * 60 else { return }
            Log.log(.ia, "motor de embeddings: \(Int(ocioso / 60)) min sin uso — lo apago y libero su memoria")
            detener()
        }
        t.resume()
        vigia = t
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
