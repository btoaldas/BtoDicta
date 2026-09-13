import Foundation

// MARK: - Motor de voz interno y AISLADO (corre paquetes de voz clonada, 100% local)
//
// BtoDicta trae su PROPIO runtime de clonación de voz bajo ~/.btodicta/voz-engine/,
// sin tocar el Python del sistema ni Homebrew. Así cualquier usuario puede subir un
// paquete de voz portable y usarlo, sin tener que instalar nada a mano.
//
//   • Intérprete propio: `uv` crea un Python standalone (python-build-standalone) en
//     voz-engine/venv, y ahí instala torch + torchaudio + coqui-tts (versiones
//     PROBADAS que funcionan con XTTS). Todo bajo el home del usuario → sin permisos
//     de macOS, sin admin. Borrable de un tirón (desinstalar()).
//   • Correr un paquete: python <paquete>/voz_gen.py "texto" salida.wav → BtoDicta
//     reproduce el wav (sin ffmpeg: coqui ya entrega wav).
//
// La descarga (~3-4 GB: torch/coqui) se hace UNA vez, con permiso explícito del
// usuario y progreso. Si no está instalado, la voz local degrada suave (failover).

enum VozEngine {
    static var dir: URL { Config.dir.appendingPathComponent("voz-engine") }
    static var pythonURL: URL { dir.appendingPathComponent("venv/bin/python") }
    private static var marcador: URL { dir.appendingPathComponent(".listo") }

    // Versiones PROBADAS (mismas que el venv que funciona). No subir a ciegas:
    // transformers 5.x rompe coqui-tts (isin_mps_friendly); setuptools 81+ quita pkg_resources.
    private static let pins = ["torch==2.5.1", "torchaudio==2.5.1",
                               "coqui-tts==0.27.5", "transformers==4.57.6", "setuptools<81"]

    // Deps EXTRA para ENTRENAR (además de las de inferencia): Whisper (transcribir),
    // Resemblyzer (elegir el mejor checkpoint por d-vector), librosa/soundfile (audio),
    // matplotlib (gráficas). Todo cacheable → instalación rápida tras la 1ª vez.
    private static let pinsEntreno = ["mlx-whisper", "resemblyzer", "librosa", "soundfile", "matplotlib"]

    /// Carpeta del pipeline internalizado (scripts de clonación + xtts_base).
    static var pipelineDir: URL { dir.appendingPathComponent("pipeline") }
    static var entrenoListo: Bool {
        let requeridos = ["clonar/build_ds.py", "clonar/train.py", "clonar/persona.py",
                          "clonar/pick_clips.py", "clonar/gen.py", "clonar/measure.py",
                          "clonar/slim.py", "xtts_base/model.pth", "xtts_base/config.json",
                          "xtts_base/vocab.json", "xtts_base/dvae.pth", "xtts_base/mel_stats.pth"]
        return requeridos.allSatisfy {
            FileManager.default.fileExists(atPath: pipelineDir.appendingPathComponent($0).path)
        }
    }

    enum Estado { case noInstalado, instalando, listo }
    private(set) static var instalando = false

    static func estado() -> Estado {
        if instalando { return .instalando }
        return (FileManager.default.fileExists(atPath: pythonURL.path)
                && FileManager.default.fileExists(atPath: marcador.path)) ? .listo : .noInstalado
    }

    // MARK: Instalación (bootstrap del runtime)

    /// Instala el motor: localiza/baja `uv`, crea el venv con Python propio e instala
    /// las dependencias. `onProgreso` recibe líneas legibles; `completion(ok, msg)`.
    /// Idempotente: si ya está, responde listo al toque.
    static func instalar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        if estado() == .listo { completion(true, "El motor ya está instalado."); return }
        guard !instalando else { completion(false, "Ya se está instalando."); return }
        instalando = true
        Config.asegurarDirSeguro()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                onProgreso("Preparando el instalador de Python (uv)…")
                let uv = try localizarObajarUv(onProgreso)
                onProgreso("Creando un Python propio y aislado…")
                try correr(uv, ["venv", "--python", "3.11", dir.appendingPathComponent("venv").path],
                           onProgreso)
                onProgreso("Descargando la IA de voz (torch + coqui, ~3-4 GB). Esto tarda…")
                try correr(uv, ["pip", "install", "--python", pythonURL.path] + pins, onProgreso)
                FileManager.default.createFile(atPath: marcador.path, contents: Data())
                instalando = false
                DispatchQueue.main.async { completion(true, "Motor de voz instalado.") }
            } catch {
                instalando = false
                DispatchQueue.main.async { completion(false, "Falló la instalación: \(error.localizedDescription)") }
            }
        }
    }

    /// Localiza `uv` (motor propio → ~/.local/bin → Homebrew → PATH). Si no hay, lo
    /// BAJA (binario estático, ~15 MB) a voz-engine/bin/uv. Nada de instalar global.
    private static func localizarObajarUv(_ onProgreso: @escaping (String) -> Void) throws -> String {
        let candidatos = [dir.appendingPathComponent("bin/uv").path,
                          (NSHomeDirectory() + "/.local/bin/uv"),
                          "/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        for c in candidatos where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Descargar el binario estático de uv para arm64-apple-darwin.
        onProgreso("Descargando uv (instalador de Python)…")
        let bin = dir.appendingPathComponent("bin"); try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let url = "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz"
        let tgz = dir.appendingPathComponent("uv.tar.gz")
        try correr("/usr/bin/curl", ["-LsSf", url, "-o", tgz.path], onProgreso)
        try correr("/usr/bin/tar", ["xzf", tgz.path, "-C", bin.path, "--strip-components=1"], onProgreso)
        try? FileManager.default.removeItem(at: tgz)
        let uv = bin.appendingPathComponent("uv").path
        // Quitar quarantine (Gatekeeper) y permiso de ejecución.
        try? correr("/usr/bin/xattr", ["-d", "com.apple.quarantine", uv]) { _ in }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv)
        guard FileManager.default.isExecutableFile(atPath: uv) else { throw Err.uv }
        return uv
    }

    // MARK: Correr un paquete de voz

    /// Corre `<carpeta>/voz_gen.py "texto" salida.wav` con el Python del motor.
    /// Devuelve la URL del wav (o nil si falla → el llamador hace failover).
    static func correrPaquete(carpeta: URL, texto: String, completion: @escaping (URL?) -> Void) {
        guard estado() == .listo else { completion(nil); return }
        let gen = carpeta.appendingPathComponent("voz_gen.py")
        guard FileManager.default.fileExists(atPath: gen.path) else {
            Log.log(.ia, "VozEngine: el paquete no tiene voz_gen.py"); completion(nil); return
        }
        let salida = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-engine-\(abs(texto.hashValue)).wav")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try correr(pythonURL.path, [gen.path, texto, salida.path]) { _ in }
                if FileManager.default.fileExists(atPath: salida.path) {
                    DispatchQueue.main.async { completion(salida) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                Log.log(.ia, "VozEngine: falló correr el paquete (\(error.localizedDescription))")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: Entrenamiento (instala deps extra + pipeline internalizado)

    /// Prepara el motor para ENTRENAR: instala las deps extra y deja el pipeline
    /// (scripts + xtts_base) bajo voz-engine/pipeline/. Requiere el motor base listo.
    /// Los scripts vienen dentro de BtoDicta y la base oficial se migra solo cuando
    /// coincide su SHA-256 o se descarga por HTTPS. No depende de VozClon/Hermes.
    static func instalarEntrenamiento(onProgreso: @escaping (String) -> Void,
                                      completion: @escaping (Bool, String) -> Void) {
        guard estado() == .listo else { completion(false, "Primero instala el motor de voz."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try instalarEntrenamientoSincrono(onProgreso: onProgreso)
                DispatchQueue.main.async { completion(true, "Entrenamiento listo.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló: \(error.localizedDescription)") }
            }
        }
    }

    /// Misma instalación usada por la GUI, disponible para hooks QA/migraciones.
    static func instalarEntrenamientoSincrono(onProgreso: @escaping (String) -> Void) throws {
        guard estado() == .listo else { throw Err.proceso(0, "motor XTTS no instalado") }
        onProgreso("Instalando herramientas de entrenamiento (Whisper, Resemblyzer, gráficas)…")
        let uv = try localizarObajarUv(onProgreso)
        try correr(uv, ["pip", "install", "--python", pythonURL.path] + pinsEntreno, onProgreso)
        onProgreso("Preparando el pipeline propio de BtoDicta…")
        try prepararPipeline(onProgreso)
        guard entrenoListo else { throw Err.proceso(0, "faltan recursos del pipeline") }
    }

    private struct RecursoXTTS {
        let nombre: String
        let sha256: String
        var url: String { "https://huggingface.co/coqui/XTTS-v2/resolve/main/\(nombre)" }
    }

    private static let recursosXTTS = [
        RecursoXTTS(nombre: "model.pth", sha256: "c7ea20001c6a0a841c77e252d8409f6a74fb423e79b3206a0771ba5989776187"),
        RecursoXTTS(nombre: "config.json", sha256: "ef262b1454dd2a77e1461b0b2cd53e19b8a7624cc131b837d36df67356bc75e8"),
        RecursoXTTS(nombre: "vocab.json", sha256: "928260878a59da8a72a2a5b7687fea29d5106137669d90945430fe17e415304a"),
        RecursoXTTS(nombre: "dvae.pth", sha256: "b29bc227d410d4991e0a8c09b858f77415013eeb9fba9650258e96095557d97a"),
        RecursoXTTS(nombre: "mel_stats.pth", sha256: "1f69422a8a8f344c4fca2f0c6b8d41d2151d6615b7321e48e6bb15ae949b119c")
    ]

    /// Deja scripts EMBARCADOS + base oficial verificada bajo voz-engine/pipeline/.
    private static func prepararPipeline(_ onProgreso: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: pipelineDir.appendingPathComponent("clonar"),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: pipelineDir.appendingPathComponent("xtts_base"),
                               withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])

        // El bundle es la fuente de producción. La ruta del repo solo permite correr el
        // binario de desarrollo antes de construir BtoDicta.app.
        let fuenteBundle = Bundle.main.resourceURL?.appendingPathComponent("voice-pipeline/clonar")
        let fuenteRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/voice-pipeline/clonar")
        guard let srcClonar = [fuenteBundle, fuenteRepo].compactMap({ $0 }).first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("train.py").path)
        }) else { throw Err.proceso(0, "la app no contiene el pipeline de entrenamiento") }
        for src in try fm.contentsOfDirectory(at: srcClonar, includingPropertiesForKeys: nil)
            where src.pathExtension == "py" {
            let dst = pipelineDir.appendingPathComponent("clonar/" + src.lastPathComponent)
            try? fm.removeItem(at: dst); try fm.copyItem(at: src, to: dst)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
        }

        // Migración sin red: reutiliza recursos oficiales ya presentes SOLO si su hash
        // coincide. En una Mac limpia los descarga por HTTPS desde Coqui/Hugging Face.
        let baseLegada = URL(fileURLWithPath:
            (Config.vozClonBase() as NSString).expandingTildeInPath).appendingPathComponent("xtts_base")
        let dstBase = pipelineDir.appendingPathComponent("xtts_base")
        for recurso in recursosXTTS {
            let dst = dstBase.appendingPathComponent(recurso.nombre)
            if sha256(dst) == recurso.sha256 {
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
                continue
            }
            try? fm.removeItem(at: dst)
            let candidatos = [coquiCache.appendingPathComponent(recurso.nombre),
                              baseLegada.appendingPathComponent(recurso.nombre)]
            if let local = candidatos.first(where: { sha256($0) == recurso.sha256 }) {
                onProgreso("Migrando \(recurso.nombre) al entorno propio…")
                try fm.copyItem(at: local, to: dst)
            } else {
                onProgreso("Descargando base oficial XTTS: \(recurso.nombre)…")
                let tmp = dst.appendingPathExtension("download")
                try? fm.removeItem(at: tmp)
                try correr("/usr/bin/curl", ["--fail", "--location", "--retry", "3",
                                                "--output", tmp.path, recurso.url], onProgreso)
                guard sha256(tmp) == recurso.sha256 else {
                    try? fm.removeItem(at: tmp)
                    throw Err.proceso(0, "SHA-256 inválido para \(recurso.nombre)")
                }
                try fm.moveItem(at: tmp, to: dst)
            }
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
        }
    }

    // MARK: Streaming (XTTS inference_stream → PCM float32 por stdout)

    static var streamRunnerURL: URL { dir.appendingPathComponent("stream_runner.py") }

    /// Runner genérico de streaming: lee el manifest del paquete (btodicta-voz.json)
    /// para hallar modelo/config/vocab/refs y emite PCM float32 (24000Hz mono) por
    /// stdout conforme genera. Se escribe una vez; sirve para CUALQUIER paquete.
    private static let runnerPy = """
    import os, sys, json, warnings, re
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"] = "1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
    import torch
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    PKG = sys.argv[1]; TXT = sys.argv[2]
    man = {}
    p = os.path.join(PKG, "btodicta-voz.json")
    if os.path.exists(p):
        man = json.load(open(p)).get("archivos", {})
    def rel(k, d): return os.path.join(PKG, man.get(k, d))
    config = XttsConfig(); config.load_json(rel("config", "config.json"))
    model = Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_path=rel("modelo", "xtts_clon.pth"),
                          vocab_path=rel("vocab", "vocab.json"), use_deepspeed=False)
    model.cpu(); model.train(False)
    refs = [os.path.join(PKG, l.strip()) for l in open(rel("ref_list", "ref_list.txt")) if l.strip()]
    gpt_lat, spk = model.get_conditioning_latents(audio_path=refs)
    def segmentos(txt, limite):
        txt = re.sub(r"\\s+", " ", txt).strip()
        if not txt: return []
        partes = re.split(r"(?<=[.!?…])\\s+", txt)
        salida = []
        for parte in partes:
            palabras = parte.split()
            actual = ""
            for palabra in palabras:
                nuevo = palabra if not actual else actual + " " + palabra
                if actual and len(nuevo) > limite:
                    salida.append(actual); actual = palabra
                else: actual = nuevo
            if actual: salida.append(actual)
        return salida
    limite = max(80, int(getattr(model.tokenizer, "char_limits", {}).get("es", 239)) - 10)
    out = sys.stdout.buffer
    partes = segmentos(TXT, limite)
    for i, parte in enumerate(partes):
        for chunk in model.inference_stream(parte, "es", gpt_lat, spk, temperature=0.55,
                                            length_penalty=1.0, repetition_penalty=5.0,
                                            top_k=30, top_p=0.80, enable_text_splitting=False):
            out.write(chunk.cpu().numpy().astype("<f4").tobytes()); out.flush()
        if i + 1 < len(partes):
            out.write(torch.zeros(int(0.08 * 24000), dtype=torch.float32).numpy().astype("<f4").tobytes())
            out.flush()
    """

    static func asegurarStreamRunner() {
        try? runnerPy.data(using: .utf8)?.write(to: streamRunnerURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: streamRunnerURL.path)
    }

    static var serverPyURL: URL { dir.appendingPathComponent("xtts_server.py") }

    /// Servidor XTTS residente: carga el modelo UNA vez + precalcula los latentes del
    /// locutor, y sirve por HTTP local streaming PCM float32. Mata la latencia (no
    /// recarga el modelo por respuesta). Lo levanta BtoDicta cuando el clon local es
    /// el motor activo (preactivar).
    private static let serverPy = """
    import os, sys, json, warnings, threading, traceback, re
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"]="1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES","")
    import torch
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    # Limitar hilos → deja CPU libre para el hilo de AUDIO (streaming sin trabas).
    _th=int(os.environ.get("XTTS_THREADS","0"))
    if _th>0:
        torch.set_num_threads(_th)
    PKG=sys.argv[1]; PORT=int(sys.argv[2])
    man={}
    p=os.path.join(PKG,"btodicta-voz.json")
    if os.path.exists(p): man=json.load(open(p)).get("archivos",{})
    def rel(k,d): return os.path.join(PKG, man.get(k,d))
    config=XttsConfig(); config.load_json(rel("config","config.json"))
    model=Xtts.init_from_config(config)
    model.load_checkpoint(config, checkpoint_path=rel("modelo","model.pth"), vocab_path=rel("vocab","vocab.json"), use_deepspeed=False)
    model.cpu(); model.train(False)   # XTTS no acelera bien en MPS; CPU estable
    refs=[os.path.join(PKG,l.strip()) for l in open(rel("ref_list","ref_list.txt")) if l.strip()]
    GPT,SPK=model.get_conditioning_latents(audio_path=refs)   # una sola vez
    LIMITE=max(80,int(getattr(model.tokenizer,"char_limits",{}).get("es",239))-10)
    def segmentos(txt):
        txt=re.sub(r"\\s+"," ",txt).strip()
        if not txt: return []
        salida=[]
        for parte in re.split(r"(?<=[.!?…])\\s+",txt):
            actual=""
            for palabra in parte.split():
                nuevo=palabra if not actual else actual+" "+palabra
                if actual and len(nuevo)>LIMITE:
                    salida.append(actual); actual=palabra
                else: actual=nuevo
            if actual: salida.append(actual)
        return salida
    class H(BaseHTTPRequestHandler):
        protocol_version="HTTP/1.1"
        def log_message(self,*a): pass
        def chunk(self,body):
            self.wfile.write(("%X\\r\\n"%len(body)).encode()+body+b"\\r\\n"); self.wfile.flush()
        def do_GET(self):
            # El servidor es serial porque el modelo no admite inferencias paralelas.
            # Cerrar cada respuesta evita que un keep-alive ocioso monopolice el único
            # handler e impida entrar a otro URLSession (por ejemplo, el reproductor).
            self.close_connection=True
            if self.path.startswith("/health"):
                body=json.dumps({"motor":"btodicta-xtts","paquete":os.path.realpath(PKG),"pid":os.getpid()}).encode()
                self.send_response(200); self.send_header("Content-Type","application/json")
                self.send_header("Content-Length",str(len(body))); self.send_header("Connection","close")
                self.end_headers(); self.wfile.write(body)
            elif self.path.startswith("/shutdown"):
                self.send_response(200); self.send_header("Content-Length","3")
                self.send_header("Connection","close"); self.end_headers(); self.wfile.write(b"bye")
                self.wfile.flush()
                # Salida dura y breve: torch puede dejar pools C vivos incluso después de
                # serve_forever.shutdown(). El proceso es solo este servidor y no guarda datos.
                threading.Timer(0.10,lambda: os._exit(0)).start()
            else:
                self.send_response(404); self.send_header("Content-Length","0")
                self.send_header("Connection","close"); self.end_headers()
        def do_POST(self):
            self.close_connection=True
            n=int(self.headers.get("Content-Length",0)); txt=self.rfile.read(n).decode("utf-8")
            partes=segmentos(txt)
            if not partes:
                self.send_response(400); self.send_header("Content-Length","0")
                self.send_header("Connection","close"); self.end_headers(); return
            try:
                kw=dict(temperature=0.55,length_penalty=1.0,repetition_penalty=5.0,
                        top_k=30,top_p=0.80,enable_text_splitting=False)
                if self.path.startswith("/generate"):
                    audios=[]
                    for i,parte in enumerate(partes):
                        audios.append(torch.as_tensor(model.inference(parte,"es",GPT,SPK,**kw)["wav"]))
                        if i+1<len(partes): audios.append(torch.zeros(int(0.08*24000)))
                    body=torch.cat([a.flatten() for a in audios]).cpu().numpy().astype("<f4").tobytes()
                    self.send_response(200); self.send_header("Content-Type","application/octet-stream")
                    self.send_header("Content-Length",str(len(body))); self.send_header("Connection","close")
                    self.end_headers()
                    self.wfile.write(body)
                    self.wfile.flush()
                else:
                    # HTTP chunked distingue un final correcto de un proceso que murió a
                    # mitad. URLSession quita el framing y entrega únicamente PCM al player.
                    self.send_response(200); self.send_header("Content-Type","application/octet-stream")
                    self.send_header("Transfer-Encoding","chunked"); self.send_header("Connection","close")
                    self.end_headers()
                    for i,parte in enumerate(partes):
                        for ch in model.inference_stream(parte,"es",GPT,SPK,**kw):
                            self.chunk(ch.cpu().numpy().astype("<f4").tobytes())
                        if i+1<len(partes):
                            self.chunk(torch.zeros(int(0.08*24000)).numpy().astype("<f4").tobytes())
                    self.wfile.write(b"0\\r\\n\\r\\n"); self.wfile.flush()
            except (BrokenPipeError,ConnectionResetError):
                self.close_connection=True
            except Exception:
                traceback.print_exc(file=sys.stderr); sys.stderr.flush()
                # Sin el terminador chunked, URLSession reporta error en vez de aceptar
                # como completa una frase truncada y dejar que la voz "se muera" al final.
                self.close_connection=True
    print("READY", flush=True); sys.stdout.flush()
    HTTPServer(("127.0.0.1",PORT), H).serve_forever()
    """

    static func asegurarServerPy() {
        try? serverPy.data(using: .utf8)?.write(to: serverPyURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: serverPyURL.path)
    }

    /// Cache del modelo BASE de Coqui XTTS v2 (vocab.json/config.json comunes a TODO
    /// clon XTTS). Sirve para rellenar paquetes traídos de fuera que llegan incompletos.
    static var coquiCache: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/tts/tts_models--multilingual--multi-dataset--xtts_v2")
    }
    static func baseVocab() -> URL? {
        existe(pipelineDir.appendingPathComponent("xtts_base/vocab.json"))
            ?? existe(coquiCache.appendingPathComponent("vocab.json"))
    }
    static func baseConfig() -> URL? {
        existe(pipelineDir.appendingPathComponent("xtts_base/config.json"))
            ?? existe(coquiCache.appendingPathComponent("config.json"))
    }
    private static func existe(_ u: URL) -> URL? { FileManager.default.fileExists(atPath: u.path) ? u : nil }

    /// Quita SOLO el runtime XTTS. No borra voces, entrenamientos, el pipeline, Máxima
    /// ni Qwen/MLX: reinstalar el motor no puede destruir trabajo del usuario.
    static func desinstalar() {
        XttsServer.detener()
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("venv"))
        try? FileManager.default.removeItem(at: marcador)
        try? FileManager.default.removeItem(at: streamRunnerURL)
        try? FileManager.default.removeItem(at: serverPyURL)
    }

    // Wrappers públicos para que otros módulos (EntrenadorPiper) reusen uv + el runner.
    static func uvBin(_ onProgreso: @escaping (String) -> Void) throws -> String {
        try localizarObajarUv(onProgreso)
    }
    @discardableResult
    static func correrUv(_ exe: String, _ args: [String],
                         _ onLinea: @escaping (String) -> Void) throws -> String {
        try correr(exe, args, onLinea)
    }
    /// Ejecuta una herramienta concreta sin pasar por un shell. Lo usan los runtimes
    /// gestionados (Máxima, Piper, etc.) para conservar argumentos y rutas seguros.
    @discardableResult
    static func correrComando(_ exe: String, _ args: [String],
                              _ onLinea: @escaping (String) -> Void = { _ in }) throws -> String {
        try correr(exe, args, onLinea)
    }

    private static func sha256(_ archivo: URL) -> String? {
        guard FileManager.default.fileExists(atPath: archivo.path) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", archivo.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        guard p.terminationStatus == 0,
              let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }
        return s.split(separator: " ").first.map(String.init)
    }

    // MARK: Utilidades

    enum Err: Error, LocalizedError {
        case proceso(Int32, String), uv
        var errorDescription: String? {
            switch self {
            case .proceso(let c, let m): return "salió \(c): \(m)"
            case .uv: return "no pude preparar uv"
            }
        }
    }

    /// Corre un proceso y transmite su salida línea a línea. Lanza si sale != 0.
    @discardableResult
    private static func correr(_ exe: String, _ args: [String],
                              _ onLinea: @escaping (String) -> Void) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        // uv y el Python propio viven en el home; PATH mínimo, sin depender del sistema.
        var env = ProcessInfo.processInfo.environment
        env["COQUI_TOS_AGREED"] = "1"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        var salida = ""
        let h = pipe.fileHandleForReading
        h.readabilityHandler = { fh in
            let d = fh.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            salida += s
            for l in s.split(separator: "\n") where !l.trimmingCharacters(in: .whitespaces).isEmpty {
                onLinea(String(l))
            }
        }
        try p.run(); p.waitUntilExit()
        h.readabilityHandler = nil
        if p.terminationStatus != 0 {
            throw Err.proceso(p.terminationStatus, String(salida.suffix(300)))
        }
        return salida
    }
}
