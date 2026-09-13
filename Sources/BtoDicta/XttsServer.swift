import Foundation
import AVFoundation

// MARK: - Servidor XTTS residente (clon local RÁPIDO, sin recargar el modelo)
//
// Problema: correr `python voz_gen.py` por respuesta recarga el modelo (~2GB) cada vez
// → 10-20s de latencia → a veces timeout → failover a otra voz. Solución: un servidor
// Python que carga el modelo UNA vez (y precalcula los latentes del locutor) y responde
// por HTTP local en streaming. Cada respuesta = ~1-2s. Se levanta cuando el clon local
// es el motor activo (preactivar, parametrizable). Igual patrón que WhisperServer/Voxtral.

enum XttsServer {
    static var proceso: Process?
    static var puerto = 8791
    static var paqueteActivo = ""
    private static let salud = "http://127.0.0.1:8791/health"
    private static var ultimoUso = Date()      // para dormir por inactividad
    private static var protegidoHasta = Date.distantPast
    private static var vigia: Timer?
    private static var adoptado = false
    private static var logHandle: FileHandle?

    static var corriendo: Bool { proceso?.isRunning == true || adoptado }

    /// Marca que se acaba de usar (para el reloj de inactividad).
    static func tocar() {
        ultimoUso = Date()
        // Un uso real cambia la política de arranque (60 min) por la post-uso (15 min).
        protegidoHasta = .distantPast
    }

    private static func marcarCarga(protegerMinutos: Double) {
        ultimoUso = Date()
        if protegerMinutos > 0 {
            protegidoHasta = max(protegidoHasta,
                                  Date().addingTimeInterval(protegerMinutos * 60))
        } else {
            protegidoHasta = .distantPast
        }
    }

    /// Vigila la inactividad: si el clon no se usa en N minutos, lo DUERME (mata el
    /// server → libera ~2GB de RAM + CPU). Se despierta al grabar (fn) vía preactivarLocal.
    static func iniciarVigilancia() {
        vigia?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            guard corriendo, Config.ttsXttsDormir() else { return }
            let limiteUso = ultimoUso.addingTimeInterval(Config.ttsXttsDormirMin() * 60)
            if Date() > max(limiteUso, protegidoHasta) {
                Log.log(.ia, "clon local dormido por inactividad (RAM liberada); fn lo despierta")
                detener()
            }
        }
        RunLoop.main.add(t, forMode: .common); vigia = t
    }

    /// Asegura el servidor levantado para ESTE paquete (lo reinicia si cambió la voz).
    /// `onListo(true)` cuando el modelo está cargado (GET /health responde).
    static func asegurar(paquete: URL, protegerMinutos: Double = 0,
                         onListo: @escaping (Bool) -> Void) {
        guard VozEngine.estado() == .listo else { onListo(false); return }
        marcarCarga(protegerMinutos: protegerMinutos)
        if corriendo && paqueteActivo == paquete.path {
            iniciarVigilancia(); onListo(true); return
        }
        // Si BtoDicta se cerró a la fuerza, el Python puede quedar adoptado por launchd.
        // Reúsalo si es la MISMA voz: evita cargar 2 GB otra vez y chocar con el puerto.
        if let s = saludActual(), s.motor == "btodicta-xtts" {
            if s.paquete == paquete.path {
                proceso = nil; adoptado = true; paqueteActivo = paquete.path
                iniciarVigilancia(); onListo(true); return
            }
            pedirApagado()   // otra voz ocupa el puerto; apágala antes de cambiar
            for _ in 0..<20 where saludActual() != nil { Thread.sleep(forTimeInterval: 0.1) }
        } else if respondeSalud() {
            // Migración desde el servidor de versiones viejas: respondía solo "ok" y no
            // podía identificarse ni apagarse por HTTP. Mata ÚNICAMENTE nuestro script.
            matarServidorLegacy()
            for _ in 0..<20 where respondeSalud() { Thread.sleep(forTimeInterval: 0.1) }
        }
        detener()
        VozEngine.asegurarServerPy()
        paqueteActivo = paquete.path
        // FULL potencia: XTTS en CPU ya va al límite (~1.3x tiempo real); NO reducir hilos
        // (lo hundía por debajo de tiempo real). El hilo de audio de CoreAudio es de
        // prioridad real y no lo ahoga la generación. Hilos opcionales (Config.ttsXttsHilos).
        let p = Process(); p.executableURL = VozEngine.pythonURL
        p.arguments = [VozEngine.serverPyURL.path, paquete.path, "\(puerto)"]
        var env = ProcessInfo.processInfo.environment; env["COQUI_TOS_AGREED"] = "1"
        if Config.ttsXttsHilos() > 0 {
            let h = "\(Config.ttsXttsHilos())"; env["XTTS_THREADS"] = h; env["OMP_NUM_THREADS"] = h
        }
        p.environment = env
        let log = prepararLogServidor()
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        do { try p.run() } catch {
            try? log?.close(); logHandle = nil
            Log.log(.ia, "XTTS servidor: no pudo arrancar (\(error.localizedDescription))")
            onListo(false); return
        }
        logHandle = log
        proceso = p; adoptado = false
        // Sondear /health hasta ~40s (la 1ª carga del modelo tarda).
        DispatchQueue.global().async {
            for _ in 0..<80 {
                Thread.sleep(forTimeInterval: 0.5)
                if !(p.isRunning) { DispatchQueue.main.async { onListo(false) }; return }
                if ping() {
                    DispatchQueue.main.async { iniciarVigilancia(); onListo(true) }
                    return
                }
            }
            DispatchQueue.main.async { onListo(false) }
        }
    }

    static func detener() {
        if proceso?.isRunning == true { proceso?.terminate() }
        else if adoptado { pedirApagado() }
        proceso = nil; adoptado = false; paqueteActivo = ""
        protegidoHasta = .distantPast
        vigia?.invalidate(); vigia = nil
        try? logHandle?.close(); logHandle = nil
    }

    /// Hace una inferencia corta y descarta el audio. Calienta el camino real sin hablar;
    /// si falla, no bloquea ni cambia la voz elegida.
    static func precalentar(frase: String, completion: ((Bool) -> Void)? = nil) {
        let texto = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard corriendo, !texto.isEmpty,
              let u = URL(string: "http://127.0.0.1:\(puerto)/generate") else {
            completion?(false); return
        }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 120
        req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let ok = err == nil && (200..<300).contains(code) && (data?.count ?? 0) >= 8
            if !ok { Log.log(.ia, "XTTS: calentamiento silencioso omitido") }
            DispatchQueue.main.async { completion?(ok) }
        }.resume()
    }

    /// Conserva un diagnóstico local y privado. Antes la salida iba a /dev/null y una
    /// falla del runtime solo se veía como "sin audio". Rota a 1 MB para no crecer.
    private static func prepararLogServidor() -> FileHandle? {
        let fm = FileManager.default
        let dir = Config.dir.appendingPathComponent("logs")
        let url = dir.appendingPathComponent("xtts-server.log")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        if let tam = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), tam > 1_000_000 {
            try? Data().write(to: url, options: .atomic)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: Data()) }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }
        do { try h.seekToEnd() } catch { try? h.close(); return nil }
        return h
    }

    /// Corta la VOZ en curso (streaming o lotes) SIN matar el servidor residente (así la
    /// próxima respuesta sigue siendo rápida). Para el botón/tecla Cancelar.
    static func pararVoz() {
        player?.stop(); player = nil
        stream?.parar(); stream = nil
    }

    private struct Salud: Decodable { let motor: String; let paquete: String; let pid: Int }

    private static func saludActual() -> Salud? {
        guard let u = URL(string: salud) else { return nil }
        var r = URLRequest(url: u); r.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0); var valor: Salud?
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let d {
                valor = try? JSONDecoder().decode(Salud.self, from: d)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5); return valor
    }

    private static func ping() -> Bool { saludActual()?.motor == "btodicta-xtts" }

    private static func respondeSalud() -> Bool {
        guard let u = URL(string: salud) else { return false }
        var r = URLRequest(url: u); r.timeoutInterval = 0.5
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            ok = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 0.8); return ok
    }

    private static func matarServidorLegacy() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-TERM", "-f", VozEngine.serverPyURL.path + ".*\(puerto)"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { }
    }

    private static func pedirApagado() {
        guard let u = URL(string: "http://127.0.0.1:\(puerto)/shutdown") else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
    }

    private static var player: AVAudioPlayer?
    private static let fin = XttsFin()

    /// Habla por el servidor. Genera el audio COMPLETO (el modelo ya está en RAM → rápido)
    /// y LUEGO lo reproduce de corrido. Así la reproducción NO compite con la CPU de la
    /// generación → suena parejo, sin bajones ni trabas. Falla suave (completion(false)).
    private static var stream: XttsStreamPlayer?

    static func decir(texto: String, empezar: (() -> Void)? = nil, completion: @escaping (Bool) -> Void) {
        guard corriendo, let u = URL(string: "http://127.0.0.1:\(puerto)/say") else { completion(false); return }
        tocar()
        // MODO RÁPIDO: streaming (suena en ~1-2s). El server ya corre niced + hilos
        // limitados → el audio no se traba. Si no, por lotes (garantizado fluido).
        if Config.ttsXttsRapido() {
            let sp = XttsStreamPlayer(); stream = sp
            sp.reproducir(texto: texto, url: u, empezar: empezar, completion: completion)
            return
        }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 120
        req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, (200..<300).contains(code), data.count >= 8 else {
                Log.log(.ia, "XTTS servidor: sin audio (\(err?.localizedDescription ?? "HTTP \(code)"))")
                DispatchQueue.main.async { completion(false) }; return
            }
            // PCM float32 24kHz mono → WAV → AVAudioPlayer (reproducción fluida garantizada).
            guard let wav = try? pcmFloatAWav(data) else { DispatchQueue.main.async { completion(false) }; return }
            DispatchQueue.main.async {
                do {
                    let p = try AVAudioPlayer(data: wav)
                    fin.alTerminar = completion; p.delegate = fin
                    player = p; p.prepareToPlay()
                    empezar?()   // el texto del notch arranca justo cuando suena la voz
                    p.play()
                } catch { Log.log(.ia, "XTTS servidor: no reproduce (\(error.localizedDescription))"); completion(false) }
            }
        }.resume()
    }

    /// Genera el WAV completo con el modelo YA residente, sin reproducirlo. La variante
    /// Máxima usa esta salida para aplicar su restauración, evitando recargar ~2 GB en
    /// cada frase y conservando exactamente los parámetros batch del clon.
    static func generarWav(texto: String, completion: @escaping (URL?) -> Void) {
        guard corriendo, let u = URL(string: "http://127.0.0.1:\(puerto)/generate") else {
            completion(nil); return
        }
        tocar()
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 180
        req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, (200..<300).contains(code), data.count >= 8,
                  let wav = try? pcmFloatAWav(data) else {
                Log.log(.ia, "XTTS servidor: no generó WAV para Máxima (\(err?.localizedDescription ?? "HTTP \(code)"))")
                DispatchQueue.main.async { completion(nil) }; return
            }
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("btodicta-xtts-raw-\(UUID().uuidString).wav")
            do {
                try wav.write(to: out, options: .atomic)
                DispatchQueue.main.async { completion(out) }
            } catch { DispatchQueue.main.async { completion(nil) } }
        }.resume()
    }

    /// float32 LE (24kHz mono) → WAV int16.
    private static func pcmFloatAWav(_ f32: Data) throws -> Data {
        var pcm16 = Data(capacity: f32.count / 2)
        f32.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            for i in 0..<f.count { var s = Int16(max(-1, min(1, f[i])) * 32767).littleEndian; withUnsafeBytes(of: &s) { pcm16.append(contentsOf: $0) } }
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xtts-srv-\(UUID().uuidString).wav")
        try WavIO.escribir(pcm16: pcm16, sampleRate: 24000, a: tmp)
        let d = try Data(contentsOf: tmp); try? FileManager.default.removeItem(at: tmp); return d
    }
}

private final class XttsFin: NSObject, AVAudioPlayerDelegate {
    var alTerminar: ((Bool) -> Void)?
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let cb = alTerminar; alTerminar = nil; DispatchQueue.main.async { cb?(true) }
    }
}

// Reproductor STREAMING (modo rápido): recibe PCM float32 por HTTP y lo va sonando con un
// jitter buffer (colchón). El server corre a baja prioridad → el audio no compite → parejo.
private final class XttsStreamPlayer: NSObject, URLSessionDataDelegate {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    /// URLSession entrega datos aquí en serie. Cancelar y finalizar también pasan por la
    /// misma cola: no se puede reactivar el player después de Esc ni tocar estado a la vez.
    private let callbacks: OperationQueue = {
        let q = OperationQueue()
        q.name = "btodicta.xtts-stream"
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var acum = Data()
    private var sonando = false
    // Colchón (caché) parametrizable: junta N segundos de audio antes de sonar, para
    // cubrir las pausas entre frases del XTTS → fluido, arrancando en ~ese tiempo.
    private let colchon = Int(Config.ttsXttsColchonSeg() * 24000)
    private let trozo = 4800               // ~0.2s por buffer
    private var progr = 0
    private var recibio = false
    private var empezar: (() -> Void)?
    private var done: ((Bool) -> Void)?
    private var terminado = false

    func reproducir(texto: String, url: URL, empezar: (() -> Void)?, completion: @escaping (Bool) -> Void) {
        self.empezar = empezar; self.done = completion
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt)
        guard AudioSeguro.arrancarMotor(engine, player, contexto: "XTTS servidor") else { finish(false); return }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 120
        req.httpBody = texto.data(using: .utf8)
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: callbacks)
        session = s
        let t = s.dataTask(with: req); task = t; t.resume()
    }

    func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !terminado else { return }
        recibio = true; acum.append(data)
        while acum.count >= trozo * 4 { encolar(trozo) }
        if !sonando, progr >= colchon { arrancar() }
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !terminado else { return }
        let r = acum.count / 4; if r > 0 { encolar(r) }
        guard recibio else { finish(false); return }
        // Marcador silencioso al FINAL de la cola. Su callback ocurre cuando CoreAudio ya
        // reprodujo todo; antes avisábamos a los 0.4 s y una respuesta siguiente podía
        // reemplazar este player y cortar la frase todavía pendiente.
        encolarFinal(recibio && error == nil)
        if !sonando { arrancar() }
    }
    private func arrancar() {
        guard !terminado else { return }
        let cb = empezar; empezar = nil
        guard AudioSeguro.reproducir(player, contexto: "XTTS servidor") else { finish(false); return }
        sonando = true
        // AppKit (notch) SOLO en main. Este era el crash al responder el Modo Agente:
        // el callback venía desde com.apple.NSURLSession-delegate.
        if let cb { DispatchQueue.main.async(execute: cb) }
    }

    /// Corta la reproducción en curso (para Cancelar).
    func parar() {
        callbacks.addOperation { [weak self] in self?.pararEnCola() }
    }
    private func pararEnCola() {
        guard !terminado else { return }
        terminado = true; empezar = nil; done = nil
        player.stop(); engine.stop()
        session?.invalidateAndCancel(); session = nil; task = nil
    }
    private func encolar(_ n: Int) {
        let bytes = n * 4
        guard acum.count >= bytes, n > 0, let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        let b = acum.subdata(in: 0..<bytes); acum.removeSubrange(0..<bytes); pcm.frameLength = AVAudioFrameCount(n)
        b.withUnsafeBytes { raw in let f = raw.bindMemory(to: Float32.self)
            guard let out = pcm.floatChannelData?[0] else { return }; for i in 0..<n { out[i] = f[i] } }
        player.scheduleBuffer(pcm); progr += n
    }
    private func encolarFinal(_ ok: Bool) {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) else { finish(ok); return }
        pcm.frameLength = 1; pcm.floatChannelData?[0][0] = 0
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in self?.finish(ok) }
    }
    private func finish(_ ok: Bool) {
        callbacks.addOperation { [weak self] in self?.finishEnCola(ok) }
    }
    private func finishEnCola(_ ok: Bool) {
        guard !terminado else { return }
        terminado = true
        let cb = done; done = nil; empezar = nil
        player.stop(); engine.stop()
        session?.finishTasksAndInvalidate(); session = nil; task = nil
        DispatchQueue.main.async { cb?(ok) }
    }
}
