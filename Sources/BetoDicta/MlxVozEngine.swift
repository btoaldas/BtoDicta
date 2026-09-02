import Foundation
import AVFoundation

// MARK: - Motor local EQUILIBRADO (Qwen3-TTS sobre MLX)
//
// Tercer carril de una misma persona:
//   • XTTS       = máxima fidelidad del clon entrenado (más pesado/lento)
//   • Qwen3-MLX  = equilibrio, Apple Silicon + streaming local
//   • Piper/ONNX = casi instantáneo (menos natural)
//
// El runtime vive aislado en ~/.betodicta/voz-engine/mlx-venv. El modelo se baja una
// sola vez al caché de Hugging Face y después funciona sin internet. La voz de referencia
// nunca sale del Mac. Si no está instalado o falla, la cascada normal sigue hacia Apple.

enum MlxVozEngine {
    static let version = "0.4.0"
    static let modeloDefault = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"
    static let modeloCalidad = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"
    static let modelosPermitidos = [modeloDefault, modeloCalidad]

    static var dir: URL { VozEngine.dir.appendingPathComponent("mlx-venv") }
    /// Caché propio: instalar/quitar este motor no toca modelos de otras aplicaciones.
    static var cacheDir: URL { VozEngine.dir.appendingPathComponent("mlx-cache") }
    static var pythonURL: URL { dir.appendingPathComponent("bin/python") }
    private static var modulo: URL {
        dir.appendingPathComponent("lib/python3.11/site-packages/mlx_audio/__init__.py")
    }

    enum Estado { case noInstalado, instalando, listo }
    private(set) static var instalando = false

    /// Un paquete portable no puede pedir que se descargue un repositorio arbitrario.
    /// Por ahora admitimos únicamente los dos modelos que BetoDicta presenta en su GUI.
    static func modeloSeguro(_ candidato: String) -> String {
        modelosPermitidos.contains(candidato) ? candidato : modeloDefault
    }

    static func asegurarDirectorios() {
        Config.asegurarDirSeguro()
        try? FileManager.default.createDirectory(at: VozEngine.dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cacheDir.path)
    }

    static func estado() -> Estado {
        if instalando { return .instalando }
        return FileManager.default.isExecutableFile(atPath: pythonURL.path)
            && FileManager.default.fileExists(atPath: modulo.path) ? .listo : .noInstalado
    }

    /// Instalación explícita desde la GUI. No usa ni modifica Python/Homebrew del usuario.
    static func instalar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        if estado() == .listo { completion(true, "El motor equilibrado ya está instalado."); return }
        guard !instalando else { completion(false, "Ya se está instalando."); return }
        instalando = true
        asegurarDirectorios()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let uv = try VozEngine.uvBin(onProgreso)
                onProgreso("Creando Python aislado para MLX…")
                try VozEngine.correrUv(uv, ["venv", "--python", "3.11", dir.path], onProgreso)
                onProgreso("Instalando MLX-Audio \(version)…")
                try VozEngine.correrUv(uv, ["pip", "install", "--prerelease=allow",
                                             "--python", pythonURL.path,
                                             "mlx-audio==\(version)"], onProgreso)
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
                instalando = false
                DispatchQueue.main.async {
                    completion(estado() == .listo,
                               "Motor equilibrado instalado. La primera voz descargará su modelo (~2,6 GB).")
                }
            } catch {
                instalando = false
                DispatchQueue.main.async { completion(false, "Falló: \(error.localizedDescription)") }
            }
        }
    }

    static func desinstalar() {
        MlxVozServer.detener()
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.removeItem(at: VozEngine.dir.appendingPathComponent("mlx_server.py"))
        try? FileManager.default.removeItem(at: VozEngine.dir.appendingPathComponent("mlx-active.json"))
    }
}

// MARK: - Servidor residente Qwen3-TTS/MLX

enum MlxVozServer {
    static var proceso: Process?
    static let puerto = 8792
    private static var identidadActiva = ""
    private static var adoptado = false
    private static var tokenActivo = ""
    private static var listo = false
    private static var esperandoInicio: [(Bool) -> Void] = []
    private static var player: AVAudioPlayer?
    private static let fin = MlxFin()
    private static var stream: MlxStreamPlayer?
    private static var ultimoUso = Date()
    private static var protegidoHasta = Date.distantPast
    private static var vigia: Timer?

    static var corriendo: Bool { proceso?.isRunning == true || adoptado }
    static var hablando: Bool { (player?.isPlaying ?? false) || stream != nil }

    private static var serverPyURL: URL { VozEngine.dir.appendingPathComponent("mlx_server.py") }
    private static var arranqueURL: URL { VozEngine.dir.appendingPathComponent("mlx-active.json") }
    private static var saludURL: URL { URL(string: "http://127.0.0.1:\(puerto)/health")! }

    private static func identidad(_ voz: VozLocal) -> String {
        "\(MlxVozEngine.modeloSeguro(voz.mlxModelo))|\(URL(fileURLWithPath: voz.mlxRef).standardizedFileURL.path)"
    }

    static func iniciarVigilancia() {
        vigia?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            guard corriendo, Config.ttsMlxDormir() else { return }
            let limiteUso = ultimoUso.addingTimeInterval(Config.ttsMlxDormirMin() * 60)
            if Date() > max(limiteUso, protegidoHasta) {
                Log.log(.ia, "Qwen3-MLX dormido por inactividad (RAM liberada)")
                detener()
            }
        }
        RunLoop.main.add(t, forMode: .common); vigia = t
    }

    static func asegurar(voz: VozLocal, protegerMinutos: Double = 0,
                         onListo: @escaping (Bool) -> Void) {
        // Toda la máquina de estados vive en main. Preactivar y hablar pueden coincidir;
        // ambos esperan UNA sola carga en vez de lanzar dos procesos o usarlo prematuro.
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                asegurar(voz: voz, protegerMinutos: protegerMinutos, onListo: onListo)
            }
            return
        }
        guard MlxVozEngine.estado() == .listo, voz.tieneMlx else { onListo(false); return }
        ultimoUso = Date()
        protegidoHasta = protegerMinutos > 0
            ? max(protegidoHasta, Date().addingTimeInterval(protegerMinutos * 60))
            : .distantPast
        let id = identidad(voz)
        if corriendo && identidadActiva == id {
            if listo { onListo(true) }
            else { esperandoInicio.append(onListo) }
            return
        }
        // Permite adoptar un servidor propio superviviente tras un cierre forzado, sin
        // dejar su API local abierta a otros procesos del usuario.
        if tokenActivo.isEmpty { tokenActivo = tokenGuardado() ?? "" }
        if let s = saludActual(), s.motor == "betodicta-qwen-mlx" {
            if s.identidad == id {
                proceso = nil; adoptado = true; identidadActiva = id; listo = true
                onListo(true); return
            }
            pedirApagado()
            for _ in 0..<20 where saludActual() != nil { Thread.sleep(forTimeInterval: 0.1) }
        }
        detener()
        MlxVozEngine.asegurarDirectorios()
        asegurarServerPy()
        tokenActivo = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard prepararArranque(voz) else { onListo(false); return }
        identidadActiva = id; listo = false; esperandoInicio = [onListo]

        let p = Process()
        p.executableURL = MlxVozEngine.pythonURL
        // Solo viaja la ruta del JSON privado: la transcripción de la muestra no queda
        // expuesta en `ps`/Monitor de Actividad como argumento del proceso.
        p.arguments = [serverPyURL.path, arranqueURL.path]
        var env = ProcessInfo.processInfo.environment
        // HTTPS normal es más robusto que Xet con VPN/túneles; no usa token ni sube la voz.
        env["HF_HUB_DISABLE_XET"] = "1"
        env["HF_HUB_DOWNLOAD_TIMEOUT"] = "300"
        env["HF_HOME"] = MlxVozEngine.cacheDir.path
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let log = prepararLog()
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        do { try p.run() } catch {
            try? log?.close()
            Log.log(.ia, "Qwen3-MLX no arrancó: \(error.localizedDescription)")
            completarInicio(false); return
        }
        proceso = p; adoptado = false
        p.terminationHandler = { terminado in
            try? log?.close()
            Log.log(.ia, "Qwen3-MLX terminó (\(terminado.terminationStatus))")
            DispatchQueue.main.async {
                if proceso === terminado {
                    proceso = nil; listo = false; identidadActiva = ""
                    completarInicio(false)
                }
            }
        }
        // La primera vez puede descargar ~2,6 GB. Las siguientes cargas son mucho menores.
        DispatchQueue.global(qos: .utility).async {
            for _ in 0..<1200 {
                Thread.sleep(forTimeInterval: 0.5)
                if !p.isRunning { DispatchQueue.main.async { completarInicio(false) }; return }
                if saludActual()?.identidad == id {
                    DispatchQueue.main.async { iniciarVigilancia(); completarInicio(true) }; return
                }
            }
            DispatchQueue.main.async { completarInicio(false) }
        }
    }

    static func decir(voz: VozLocal, texto: String, empezar: (() -> Void)? = nil,
                      completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                decir(voz: voz, texto: texto, empezar: empezar, completion: completion)
            }
            return
        }
        ultimoUso = Date()
        protegidoHasta = .distantPast
        let ejecutar = {
            guard corriendo, identidadActiva == identidad(voz) else { completion(false); return }
            if voz.streaming { decirStream(texto, empezar: empezar, completion: completion) }
            else { decirBatch(texto, empezar: empezar, completion: completion) }
        }
        if listo && corriendo && identidadActiva == identidad(voz) { ejecutar() }
        else { asegurar(voz: voz) { ok in ok ? ejecutar() : completion(false) } }
    }

    static func pararVoz() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { pararVoz() }
            return
        }
        player?.stop(); player = nil
        stream?.parar(); stream = nil
    }

    static func detener() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { detener() }
            return
        }
        pararVoz()
        vigia?.invalidate(); vigia = nil
        if proceso?.isRunning == true { proceso?.terminate() }
        else if adoptado { pedirApagado() }
        proceso = nil; adoptado = false; identidadActiva = ""; listo = false
        protegidoHasta = .distantPast
        tokenActivo = ""
        completarInicio(false)
    }

    /// Infiere una frase mínima y descarta su PCM para compilar/calentar kernels Metal.
    /// No habla, no cambia de variante y su fallo siempre degrada suavemente.
    static func precalentar(voz: VozLocal, frase: String,
                            completion: ((Bool) -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { precalentar(voz: voz, frase: frase, completion: completion) }
            return
        }
        let texto = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard listo, corriendo, identidadActiva == identidad(voz), !texto.isEmpty,
              let u = URL(string: "http://127.0.0.1:\(puerto)/say?stream=0") else {
            completion?(false); return
        }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 180
        autorizar(&req); req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let ok = err == nil && (200..<300).contains(code) && (data?.count ?? 0) >= 8
            if !ok { Log.log(.ia, "Qwen3-MLX: calentamiento silencioso omitido") }
            DispatchQueue.main.async { completion?(ok) }
        }.resume()
    }

    private static func completarInicio(_ ok: Bool) {
        if ok { listo = true }
        let callbacks = esperandoInicio; esperandoInicio.removeAll()
        callbacks.forEach { $0(ok) }
    }

    private static func decirStream(_ texto: String, empezar: (() -> Void)?,
                                    completion: @escaping (Bool) -> Void) {
        guard let u = URL(string: "http://127.0.0.1:\(puerto)/say?stream=1") else {
            completion(false); return
        }
        let sp = MlxStreamPlayer(colchonSeg: Config.ttsMlxColchonSeg())
        stream = sp
        sp.reproducir(texto: texto, url: u, token: tokenActivo, empezar: empezar) { ok in
            stream = nil; completion(ok)
        }
    }

    private static func decirBatch(_ texto: String, empezar: (() -> Void)?,
                                   completion: @escaping (Bool) -> Void) {
        guard let u = URL(string: "http://127.0.0.1:\(puerto)/say?stream=0") else {
            completion(false); return
        }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 180
        autorizar(&req)
        req.httpBody = texto.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, (200..<300).contains(code), data.count >= 8,
                  let wav = try? pcmFloatAWav(data) else {
                Log.log(.ia, "Qwen3-MLX sin audio (\(err?.localizedDescription ?? "HTTP \(code)"))")
                DispatchQueue.main.async { completion(false) }; return
            }
            DispatchQueue.main.async {
                do {
                    let p = try AVAudioPlayer(data: wav)
                    fin.alTerminar = completion; p.delegate = fin; player = p
                    p.prepareToPlay(); empezar?(); p.play()
                } catch { completion(false) }
            }
        }.resume()
    }

    private struct Salud: Decodable { let motor: String; let identidad: String; let pid: Int }

    private static func saludActual() -> Salud? {
        var r = URLRequest(url: saludURL); r.timeoutInterval = 0.7
        autorizar(&r)
        let sem = DispatchSemaphore(value: 0); var valor: Salud?
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            if (resp as? HTTPURLResponse)?.statusCode == 200, let d {
                valor = try? JSONDecoder().decode(Salud.self, from: d)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1); return valor
    }

    private static func pedirApagado() {
        guard let u = URL(string: "http://127.0.0.1:\(puerto)/shutdown") else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 1
        autorizar(&r)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { _, _, _ in sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
    }

    private static func prepararLog() -> FileHandle? {
        let d = Config.dir.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: d.path)
        let u = d.appendingPathComponent("mlx-tts.log")
        if !FileManager.default.fileExists(atPath: u.path) {
            FileManager.default.createFile(atPath: u.path, contents: Data())
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        let h = try? FileHandle(forWritingTo: u); _ = try? h?.seekToEnd(); return h
    }

    private struct Arranque: Encodable {
        let model: String
        let ref: String
        let refText: String
        let port: Int
        let interval: Double
        let token: String
    }

    private static func prepararArranque(_ voz: VozLocal) -> Bool {
        let cfg = Arranque(model: MlxVozEngine.modeloSeguro(voz.mlxModelo),
                           ref: URL(fileURLWithPath: voz.mlxRef).standardizedFileURL.path,
                           refText: voz.mlxRefText,
                           port: puerto,
                           interval: min(1.0, max(0.16, Config.ttsMlxIntervalo())),
                           token: tokenActivo)
        guard let data = try? JSONEncoder().encode(cfg) else { return false }
        do {
            try data.write(to: arranqueURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: arranqueURL.path)
            return true
        } catch {
            Log.log(.ia, "Qwen3-MLX no pudo guardar su configuración privada: \(error.localizedDescription)")
            return false
        }
    }

    /// Solo para peticiones al servidor propio y para el hook reproducible de QA.
    static func autorizar(_ request: inout URLRequest) {
        guard !tokenActivo.isEmpty else { return }
        request.setValue("Bearer \(tokenActivo)", forHTTPHeaderField: "Authorization")
    }

    private static func tokenGuardado() -> String? {
        guard let data = try? Data(contentsOf: arranqueURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["token"] as? String, t.count >= 24 else { return nil }
        return t
    }

    private static func pcmFloatAWav(_ f32: Data) throws -> Data {
        var pcm16 = Data(capacity: f32.count / 2)
        f32.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            for i in 0..<f.count {
                var s = Int16(max(-1, min(1, f[i])) * 32767).littleEndian
                withUnsafeBytes(of: &s) { pcm16.append(contentsOf: $0) }
            }
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("betodicta-mlx-\(UUID().uuidString).wav")
        try WavIO.escribir(pcm16: pcm16, sampleRate: 24000, a: tmp)
        let d = try Data(contentsOf: tmp); try? FileManager.default.removeItem(at: tmp); return d
    }

    private static func asegurarServerPy() {
        try? serverPy.data(using: .utf8)?.write(to: serverPyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serverPyURL.path)
    }

    private static let serverPy = #"""
import json, os, sys, threading, warnings
warnings.filterwarnings("ignore")
import numpy as np
from http.server import BaseHTTPRequestHandler, HTTPServer
from mlx_audio.tts.utils import load_model

with open(sys.argv[1], "r", encoding="utf-8") as f:
    cfg = json.load(f)
MODEL = cfg["model"]
REF = cfg["ref"]
REF_TEXT = cfg["refText"]
PORT = int(cfg["port"])
INTERVAL = float(cfg["interval"])
TOKEN = cfg["token"]
IDENTIDAD = MODEL + "|" + os.path.realpath(REF)
model = load_model(MODEL)
lock = threading.Lock()

class H(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def autorizado(self):
        return self.headers.get("Authorization", "") == "Bearer " + TOKEN
    def do_GET(self):
        if not self.autorizado():
            self.send_response(401); self.end_headers(); return
        if self.path.startswith("/health"):
            body = json.dumps({"motor":"betodicta-qwen-mlx", "identidad":IDENTIDAD, "pid":os.getpid()}).encode()
            self.send_response(200); self.send_header("Content-Type","application/json")
            self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
        elif self.path.startswith("/shutdown"):
            self.send_response(200); self.end_headers(); self.wfile.write(b"bye"); self.wfile.flush()
            threading.Timer(0.10, lambda: os._exit(0)).start()
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        if not self.autorizado():
            self.send_response(401); self.end_headers(); return
        if not self.path.startswith("/say"):
            self.send_response(404); self.end_headers(); return
        n = int(self.headers.get("Content-Length",0)); text = self.rfile.read(n).decode("utf-8").strip()
        if not text:
            self.send_response(400); self.end_headers(); return
        streaming = "stream=1" in self.path
        self.send_response(200); self.send_header("Content-Type","application/octet-stream"); self.end_headers()
        try:
            with lock:
                for result in model.generate(text=text, ref_audio=REF, ref_text=REF_TEXT,
                        lang_code="spanish", temperature=0.7, top_p=0.9, top_k=50,
                        repetition_penalty=1.5, max_tokens=2400, verbose=False,
                        stream=streaming, streaming_interval=INTERVAL):
                    raw = np.asarray(result.audio, dtype=np.float32).astype("<f4", copy=False).tobytes()
                    self.wfile.write(raw); self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print("ERROR", repr(e), flush=True)

print("READY", flush=True)
# MLX liga el stream Metal al hilo que cargó el modelo. Un HTTPServer serial mantiene
# carga+generación en ese mismo hilo y, además, impide mezclar dos respuestas de voz.
HTTPServer(("127.0.0.1", PORT), H).serve_forever()
"""#
}

private final class MlxFin: NSObject, AVAudioPlayerDelegate {
    var alTerminar: ((Bool) -> Void)?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let cb = alTerminar; alTerminar = nil; DispatchQueue.main.async { cb?(flag) }
    }
}

/// Reproductor de PCM float32/24 kHz recibido progresivamente desde localhost.
private final class MlxStreamPlayer: NSObject, URLSessionDataDelegate {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    private let callbacks: OperationQueue = {
        let q = OperationQueue(); q.name = "betodicta.mlx-stream"; q.maxConcurrentOperationCount = 1; return q
    }()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var acum = Data()
    private var sonando = false
    private let colchon: Int
    private let trozo = 4800
    private var programadas = 0
    private var recibio = false
    private var empezar: (() -> Void)?
    private var done: ((Bool) -> Void)?
    private var terminado = false

    init(colchonSeg: Double) {
        colchon = Int(max(0.2, colchonSeg) * 24000)
        super.init()
    }

    func reproducir(texto: String, url: URL, token: String,
                    empezar: (() -> Void)?, completion: @escaping (Bool) -> Void) {
        self.empezar = empezar; done = completion
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: fmt)
        guard AudioSeguro.arrancarMotor(engine, player, contexto: "MLX voz") else { finish(false); return }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 180
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = texto.data(using: .utf8)
        let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: callbacks)
        session = s; let t = s.dataTask(with: req); task = t; t.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !terminado else { return }
        recibio = true; acum.append(data)
        while acum.count >= trozo * 4 { encolar(trozo) }
        if !sonando, programadas >= colchon { arrancar() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !terminado else { return }
        let restantes = acum.count / 4; if restantes > 0 { encolar(restantes) }
        guard recibio else { finish(false); return }
        encolarFinal(error == nil)
        if !sonando { arrancar() }
    }

    func parar() { callbacks.addOperation { [weak self] in self?.pararEnCola() } }

    private func pararEnCola() {
        guard !terminado else { return }
        terminado = true; empezar = nil; done = nil
        player.stop(); engine.stop(); session?.invalidateAndCancel(); session = nil; task = nil
    }

    private func arrancar() {
        guard !terminado else { return }
        let cb = empezar; empezar = nil
        guard AudioSeguro.reproducir(player, contexto: "MLX voz") else { finish(false); return }
        sonando = true
        if let cb { DispatchQueue.main.async(execute: cb) }
    }

    private func encolar(_ n: Int) {
        let bytes = n * 4
        guard n > 0, acum.count >= bytes,
              let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        let b = acum.subdata(in: 0..<bytes); acum.removeSubrange(0..<bytes)
        pcm.frameLength = AVAudioFrameCount(n)
        b.withUnsafeBytes { raw in
            let f = raw.bindMemory(to: Float32.self)
            guard let out = pcm.floatChannelData?[0] else { return }
            for i in 0..<n { out[i] = f[i] }
        }
        player.scheduleBuffer(pcm); programadas += n
    }

    private func encolarFinal(_ ok: Bool) {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1) else { finish(ok); return }
        pcm.frameLength = 1; pcm.floatChannelData?[0][0] = 0
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in self?.finish(ok) }
    }

    private func finish(_ ok: Bool) { callbacks.addOperation { [weak self] in self?.finishEnCola(ok) } }

    private func finishEnCola(_ ok: Bool) {
        guard !terminado else { return }
        terminado = true; let cb = done; done = nil; empezar = nil
        player.stop(); engine.stop(); session?.finishTasksAndInvalidate(); session = nil; task = nil
        DispatchQueue.main.async { cb?(ok) }
    }
}
