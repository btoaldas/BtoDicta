import Foundation
import AVFoundation

// MARK: - Entrenador PIPER (voz fija .onnx, RÁPIDA) — fine-tune en CPU, background, resumible
//
// El carril veloz: el usuario suelta una carpeta de audios de UNA persona; BtoDicta
// arma el dataset (Whisper transcribe + resample a 22050Hz), hace FINE-TUNE de Piper
// (VITS) sobre un checkpoint base en español, y al final EXPORTA un .onnx que corre
// rapidísimo (~5x tiempo real, sin torch). XTTS se queda para clonar al vuelo con más
// calidad; Piper es la voz fija veloz.
//
// EL FONDO (verificado por ejecución, esta máquina):
//   • El error ".view size not compatible" del backward era un BUG SOLO-MPS de PyTorch
//     (pytorch#142344). Se arregla FORZANDO CPU en el Trainer (--trainer.accelerator cpu).
//     Con eso torch 2.5.1 entrena sin tocar nada (la voz XTTS clonada queda intacta).
//   • Fine-tune FRESCO: carga SOLO los pesos de la base; Adam y schedulers arrancan nuevos.
//   • Export ONNX funciona en Apple Silicon; el config del entreno = <modelo>.onnx.json.
//   • Resumible: si se apaga la compu, se reanuda desde el último checkpoint del proyecto.
//
// Todo corre en el motor AISLADO (~/.btodicta/voz-engine). Nada pesado en el Git: la
// base y las deps se descargan bajo demanda con permiso.

enum EntrenadorPiper {
    static var raizDir: URL { VozEngine.dir.appendingPathComponent("piper-train") }
    static var proyectosDir: URL { raizDir.appendingPathComponent("proyectos") }
    static var wrapURL: URL { raizDir.appendingPathComponent("train_wrap.py") }
    static var dsScriptURL: URL { raizDir.appendingPathComponent("piper_ds.py") }
    static var setupURL: URL { raizDir.appendingPathComponent("piper_setup.py") }
    static var valScriptURL: URL { raizDir.appendingPathComponent("piper_val.py") }
    private static var proc: Process?
    private static var sitePackages: URL {
        VozEngine.dir.appendingPathComponent("venv/lib/python3.11/site-packages")
    }

    // MARK: Calidad (parametrizable) — high / medium / low
    //
    // La "calidad" de Piper NO es un preset: es un set de params de arquitectura + sample
    // rate (verificado en piper1-gpl vits/config.py). El fine-tune necesita una BASE de ESA
    // calidad. Para ESPAÑOL solo existe base `medium` (davefx/sharvard); high y low solo
    // existen en INGLÉS (lessac) → se usan como base y el entreno los ADAPTA al español
    // (piper soporta fine-tune cross-idioma; TRAINING.md). Params/URLs/tamaños CONFIRMADOS.

    struct Calidad {
        let id: String            // "medium" | "high" | "low"
        let etiqueta: String
        let sampleRate: Int
        let archivoBase: String   // nombre local del .ckpt
        let url: String           // fuente de descarga (rhasspy/piper-checkpoints)
        let modelArgs: [String]   // flags --model.* extra (medium = vacío = defaults)
        let nota: String
    }

    static let calidades: [Calidad] = [
        Calidad(id: "medium", etiqueta: "Media (recomendada)", sampleRate: 22050,
                archivoBase: "es-medium.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/es/es_ES/davefx/medium/epoch=5629-step=1605020.ckpt",
                modelArgs: [],
                nota: "Base en ESPAÑOL (davefx). Rápida y natural. La mejor relación calidad/velocidad para español."),
        Calidad(id: "high", etiqueta: "Alta", sampleRate: 22050,
                archivoBase: "en-high.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/en/en_US/lessac/high/epoch=2218-step=838782.ckpt",
                modelArgs: ["--model.resblock", "1",
                            "--model.resblock_kernel_sizes", "[3,7,11]",
                            "--model.resblock_dilation_sizes", "[[1,3,5],[1,3,5],[1,3,5]]",
                            "--model.upsample_rates", "[8,8,2,2]",
                            "--model.upsample_initial_channel", "512",
                            "--model.upsample_kernel_sizes", "[16,16,4,4]"],
                nota: "Red MÁS grande (más nítida) pero MÁS lenta al hablar. Base en INGLÉS (lessac): el entreno la adapta al español; requiere más etapas. ~1 GB de descarga."),
        Calidad(id: "low", etiqueta: "Baja (veloz)", sampleRate: 16000,
                archivoBase: "en-low.ckpt",
                url: "https://huggingface.co/datasets/rhasspy/piper-checkpoints/resolve/main/en/en_US/lessac/low/epoch=2307-step=558536.ckpt",
                modelArgs: [],
                nota: "16 kHz: la más liviana y veloz, con menor fidelidad de audio. Base en INGLÉS (lessac), se adapta al español."),
    ]

    static func calidad(_ id: String) -> Calidad { calidades.first { $0.id == id } ?? calidades[0] }
    static func baseCkpt(_ id: String) -> URL { raizDir.appendingPathComponent("base/\(calidad(id).archivoBase)") }
    static func baseListo(_ id: String) -> Bool { FileManager.default.fileExists(atPath: baseCkpt(id).path) }

    // MARK: Estado

    /// ¿El vits está vendorizado en el venv? (piper.train NO trae el módulo de entreno en
    /// el wheel de pip; hay que copiarlo + compilar monotonic_align).
    static var vitsListo: Bool {
        let fm = FileManager.default
        let lightning = sitePackages.appendingPathComponent("piper/train/vits/lightning.py")
        let mono = sitePackages.appendingPathComponent("piper/train/vits/monotonic_align")
        let tieneSo = ((try? fm.contentsOfDirectory(atPath: mono.path)) ?? []).contains { $0.hasSuffix(".so") }
        return fm.fileExists(atPath: lightning.path) && tieneSo
    }
    /// Listo para entrenar Piper: motor + vits vendorizado (la base se baja por calidad).
    static var listo: Bool { VozEngine.estado() == .listo && vitsListo }

    // MARK: Plan (reusa el cerebro de Entrenador: minutos → etapas recomendadas)

    static func duracionMinutos(_ carpeta: URL) -> Double { Entrenador.duracionMinutos(carpeta) }
    static func recomendar(minutos: Double) -> PlanEntrenamiento { Entrenador.recomendar(minutos: minutos) }
    /// Piper en CPU ~1.5 s/paso (fine-tune sobre base). Estimación para avisar.
    static func horasEstimadas(etapas: Int) -> Double { Double(etapas) * 1.5 / 3600.0 }

    struct Progreso { var paso: Int; var total: Int; var epoca: Int; var texto: String }

    // MARK: Preparar (deps de entreno + vendorizar vits + escribir scripts)

    /// Deja el motor listo para ENTRENAR Piper. Reusa instalarEntrenamiento (Whisper) y
    /// añade las deps de Piper-train; vendoriza el vits + compila monotonic_align si falta
    /// (fresh install). Idempotente: si ya está, no rehace nada pesado.
    static func preparar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        guard VozEngine.estado() == .listo else { completion(false, "Primero instala el motor de voz."); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.createDirectory(at: raizDir, withIntermediateDirectories: true)
                escribirScripts()
                // Deps de entrenamiento de Piper (además de Whisper/librosa ya instaladas
                // por instalarEntrenamiento de XTTS, que compartimos).
                onProgreso("Instalando herramientas de Piper (lightning, cython, onnx)…")
                let uv = try VozEngine.uvBin(onProgreso)
                try VozEngine.correrUv(uv, ["pip", "install", "--python", VozEngine.pythonURL.path] + pinsPiper, onProgreso)
                if !vitsListo {
                    guard compiladorListo() else {
                        throw Err.compilador
                    }
                    onProgreso("Preparando el entrenador de Piper (vits + monotonic_align)…")
                    let p = Process(); p.executableURL = VozEngine.pythonURL
                    p.arguments = [setupURL.path, sitePackages.path]
                    p.environment = ProcessInfo.processInfo.environment
                    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                    pipe.fileHandleForReading.readabilityHandler = { fh in
                        if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty {
                            for l in s.split(separator: "\n") { onProgreso(String(l)) }
                        }
                    }
                    try p.run(); p.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    guard vitsListo else { throw Err.setup }
                }
                // La base se descarga por calidad en la pantalla; aquí basta con vits listo.
                DispatchQueue.main.async { completion(vitsListo, "Entrenador de Piper listo. Elige la calidad y (si falta) descarga su base.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló: \(error.localizedDescription)") }
            }
        }
    }

    static func escribirScripts() {
        try? FileManager.default.createDirectory(at: raizDir, withIntermediateDirectories: true)
        try? piperDsPy.data(using: .utf8)?.write(to: dsScriptURL)
        try? trainWrapPy.data(using: .utf8)?.write(to: wrapURL)
        try? setupPy.data(using: .utf8)?.write(to: setupURL)
        try? valPy.data(using: .utf8)?.write(to: valScriptURL)
    }

    // MARK: Validación — puntuar checkpoints (inteligibilidad Whisper + parecido d-vector)

    struct RankPiper { var paso: Int; var inteligible: Double; var parecido: Double; var score: Double; var ckpt: URL? }

    /// Corre piper_val.py: por cada checkpoint genera 5 frases, mide INTELIGIBILIDAD con
    /// Whisper (transcribe y compara) y PARECIDO de voz con d-vector vs los audios reales,
    /// deja validacion.csv + validacion.png. Así nunca eliges a ciegas entre basura.
    static func validar(_ proyecto: URL, onProgreso: @escaping (String) -> Void,
                        onFin: @escaping (Bool) -> Void) {
        escribirScripts()
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process(); p.executableURL = VozEngine.pythonURL
            p.arguments = [valScriptURL.path, proyecto.path]
            p.environment = entorno()
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { fh in
                if let s = String(data: fh.availableData, encoding: .utf8) {
                    for l in s.split(separator: "\n") where l.contains("[val]") || l.contains("[OK") {
                        DispatchQueue.main.async { onProgreso(String(l)) }
                    }
                }
            }
            do { try p.run() } catch { DispatchQueue.main.async { onFin(false) }; return }
            p.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = FileManager.default.fileExists(atPath: proyecto.appendingPathComponent("validacion.csv").path)
            DispatchQueue.main.async { onFin(ok) }
        }
    }

    /// Lee validacion.csv → ranking del mejor al peor (por score). Mapea a los .ckpt.
    static func rankingPiper(_ proyecto: URL) -> [RankPiper] {
        guard let csv = try? String(contentsOf: proyecto.appendingPathComponent("validacion.csv"), encoding: .utf8) else { return [] }
        let cks = checkpoints(proyecto)
        var out: [RankPiper] = []
        for (i, l) in csv.split(separator: "\n").enumerated() where i > 0 {
            let c = l.split(separator: ",")
            guard c.count >= 4, let paso = Int(c[0]), let it = Double(c[1]), let sm = Double(c[2]), let sc = Double(c[3]) else { continue }
            out.append(RankPiper(paso: paso, inteligible: it, parecido: sm, score: sc,
                                 ckpt: cks.first { $0.paso == paso }?.url))
        }
        return out.sorted { $0.score > $1.score }
    }

    static func graficaValidacion(_ proyecto: URL) -> URL? {
        let png = proyecto.appendingPathComponent("validacion.png")
        return FileManager.default.fileExists(atPath: png.path) ? png : nil
    }

    // MARK: Descargar la base (fine-tune) — bajo demanda con permiso

    /// URL del checkpoint base es (medium). Parametrizable; si está vacía, se informa al
    /// usuario que la coloque (política: nada pesado forzado, descarga con permiso).
    /// URL de la base para una calidad. Para `medium` respeta el override Config si existe.
    static func baseURL(_ id: String) -> String {
        if id == "medium", !Config.piperBaseURL().isEmpty { return Config.piperBaseURL() }
        return calidad(id).url
    }

    static func descargarBase(calidadId: String, onProgreso: @escaping (String) -> Void,
                              completion: @escaping (Bool, String) -> Void) {
        if baseListo(calidadId) { completion(true, "La base ya está."); return }
        let dst = baseCkpt(calidadId)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try? FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                onProgreso("Descargando la base de calidad \(calidad(calidadId).etiqueta) (una sola vez)…")
                // A archivo temporal y luego mover: si se corta, no deja un .ckpt a medias.
                let tmp = dst.path + ".part"
                try VozEngine.correrUv("/usr/bin/curl", ["-Lf", "--retry", "3", baseURL(calidadId), "-o", tmp], onProgreso)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.moveItem(atPath: tmp, toPath: dst.path)
                let ok = baseListo(calidadId)
                DispatchQueue.main.async { completion(ok, ok ? "Base lista." : "No pude descargar la base.") }
            } catch {
                DispatchQueue.main.async { completion(false, "Falló la descarga: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: Entrenar (dataset → fit en background, resumible)

    /// Lanza el entrenamiento. FASE 1 dataset (piper_ds.py: Whisper + resample 22050).
    /// FASE 2 fit en BACKGROUND (fine-tune CPU sobre la base, contador en 0). Guarda
    /// checkpoints periódicos para elegir el mejor. `reanudar` = continuar un proyecto
    /// existente desde su último checkpoint (recuperación tras apagón).
    static func entrenar(carpeta: URL?, nombre: String, stamp: String, etapas: Int,
                         calidadId: String = "medium", reanudar: Bool = false,
                         onProgreso: @escaping (Progreso) -> Void,
                         onArranco: @escaping (Bool, String, URL) -> Void) {
        guard listo else { onArranco(false, "El entrenador de Piper no está listo.", raizDir); return }
        escribirScripts()
        let proyecto = proyectosDir.appendingPathComponent("\(Entrenador.slug(nombre))_\(stamp)")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: proyecto, withIntermediateDirectories: true)
            // La calidad se FIJA al crear el proyecto (la arquitectura debe coincidir al
            // reanudar). Proyecto nuevo → usa calidadId; reanudar → lee la guardada.
            let calFile = proyecto.appendingPathComponent("calidad.txt")
            let cal: Calidad
            if reanudar, let g = try? String(contentsOf: calFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                cal = calidad(g)
            } else {
                cal = calidad(calidadId)
                try? cal.id.write(to: calFile, atomically: true, encoding: .utf8)
            }
            guard baseListo(cal.id) else {
                DispatchQueue.main.async { onArranco(false, "Falta la base de calidad \(cal.etiqueta). Descárgala primero.", proyecto) }; return
            }
            let dsDir = proyecto.appendingPathComponent("dataset")
            let meta = dsDir.appendingPathComponent("metadata.csv")
            cancelado = false
            // Reentreno FRESCO (no reanudar): limpia checkpoints/run viejos para NO mezclar
            // cortes de una sesión anterior (con audios distintos) con los nuevos.
            if !reanudar {
                try? fm.removeItem(at: proyecto.appendingPathComponent("ckpts"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("run"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("seguro"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("cache"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("config.json"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("validacion.csv"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("validacion.png"))
                try? fm.removeItem(at: proyecto.appendingPathComponent("validacion"))
            }

            // FASE 1 — dataset. Se construye SOLO si aún no existe uno usable (así reintentar
            // el mismo proyecto NO re-transcribe los 452 min: reusa el dataset ya hecho).
            let dsHecho = (try? String(contentsOf: meta, encoding: .utf8))?.split(separator: "\n").count ?? 0
            if dsHecho <= 3 {
                guard ffmpegListo() else {
                    DispatchQueue.main.async { onArranco(false, "Falta ffmpeg (necesario para preparar el audio). Instálalo: brew install ffmpeg", proyecto) }; return
                }
                DispatchQueue.main.async { onProgreso(Progreso(paso: 0, total: 0, epoca: 0, texto: "Transcribiendo y preparando audios (Whisper)…")) }
                guard let carpeta else { DispatchQueue.main.async { onArranco(false, "Falta la carpeta de audios.", proyecto) }; return }
                try? fm.createDirectory(at: dsDir, withIntermediateDirectories: true)
                let ds = Process(); ds.executableURL = VozEngine.pythonURL
                ds.arguments = [dsScriptURL.path, carpeta.path, dsDir.path]
                var dsEnv = entorno()
                // Rutas ABSOLUTAS de ffmpeg/ffprobe → piper_ds no depende del PATH.
                if let ff = rutaBin("ffmpeg") { dsEnv["FFMPEG"] = ff }
                if let fp = rutaBin("ffprobe") { dsEnv["FFPROBE"] = fp }
                ds.environment = dsEnv
                let dsLog = proyecto.appendingPathComponent("dataset.log")
                fm.createFile(atPath: dsLog.path, contents: nil)
                if let fh = try? FileHandle(forWritingTo: dsLog) { ds.standardOutput = fh; ds.standardError = fh }
                proc = ds   // para que "Detener" mate también la transcripción (Fase 1)
                do { try ds.run(); ds.waitUntilExit() } catch {
                    DispatchQueue.main.async { onArranco(false, "Falló el dataset: \(error.localizedDescription)", proyecto) }; return
                }
                if cancelado { DispatchQueue.main.async { onArranco(false, "Detenido.", proyecto) }; return }
                let n = (try? String(contentsOf: meta, encoding: .utf8))?.split(separator: "\n").count ?? 0
                guard ds.terminationStatus == 0, n > 3 else {
                    let pista = pistaDataset(proyecto)
                    DispatchQueue.main.async {
                        onArranco(false, "El dataset quedó vacío o muy corto (\(n) clips)." + (pista.isEmpty ? "" : " · \(pista)"), proyecto)
                    }; return
                }
            }

            if cancelado { DispatchQueue.main.async { onArranco(false, "Detenido.", proyecto) }; return }
            // FASE 2 — fit en background.
            DispatchQueue.main.async { onProgreso(Progreso(paso: 0, total: etapas, epoca: 0, texto: "Arrancando el entrenamiento…")) }
            let ckptsDir = proyecto.appendingPathComponent("ckpts")
            try? fm.createDirectory(at: ckptsDir, withIntermediateDirectories: true)
            // ¿Reanudar? → Lightning recupera TODO el último checkpoint. Proyecto nuevo →
            // NO se restaura el checkpoint: el wrapper carga SOLO sus pesos en on_fit_start,
            // de modo que Adam/schedulers empiezan frescos (la base trae 1.6 M pasos).
            let reanuda = ultimoCheckpoint(proyecto)
            let cada = max(200, etapas / 5)
            let tr = Process(); tr.executableURL = VozEngine.pythonURL
            var argumentos = [
                wrapURL.path, "fit",
                "--data.csv_path", meta.path,
                "--data.audio_dir", dsDir.appendingPathComponent("audio").path,
                "--data.cache_dir", proyecto.appendingPathComponent("cache").path,
                "--data.config_path", proyecto.appendingPathComponent("config.json").path,
                "--data.voice_name", Entrenador.slug(nombre),
                "--data.espeak_voice", "es",
                "--model.sample_rate", "\(cal.sampleRate)",
                "--data.batch_size", "\(Config.piperBatch())",
                "--data.num_workers", "0",
                "--trainer.default_root_dir", proyecto.appendingPathComponent("run").path,
                "--trainer.accelerator", "cpu", "--trainer.devices", "1", "--trainer.precision", "32",
                "--trainer.max_steps", "\(etapas)",
                "--trainer.num_sanity_val_steps", "0",
                "--trainer.callbacks+=lightning.pytorch.callbacks.ModelCheckpoint",
                "--trainer.callbacks.dirpath", ckptsDir.path,
                "--trainer.callbacks.every_n_train_steps", "\(cada)",
                "--trainer.callbacks.save_top_k", "-1",
                "--trainer.callbacks.filename", "paso{step}",
                // 2º checkpoint DE SEGURIDAD, rodante: cada 200 pasos, se SOBREESCRIBE
                // (save_top_k 1 + mismo filename) → un apagón pierde ≤200 pasos (~10 min)
                // en vez de hasta un tramo entero. Va a su propia carpeta para que la
                // lista de "elegir el mejor" siga mostrando solo los hitos.
                "--trainer.callbacks+=lightning.pytorch.callbacks.ModelCheckpoint",
                "--trainer.callbacks.dirpath", proyecto.appendingPathComponent("seguro").path,
                "--trainer.callbacks.every_n_train_steps", "200",
                "--trainer.callbacks.save_top_k", "1",
                "--trainer.callbacks.monitor", "step",
                "--trainer.callbacks.mode", "max",
                "--trainer.callbacks.filename", "seguro-paso{step}",
            ] + cal.modelArgs   // params de arquitectura de la calidad (high/low); medium = vacío
            if reanudar, let reanuda { argumentos += ["--ckpt_path", reanuda.path] }
            tr.arguments = argumentos
            var env = entorno()
            env.removeValue(forKey: "PIPER_INIT_WEIGHTS")
            // Proyecto nuevo: pesos de la base, pero optimizadores/schedulers RECIÉN creados.
            if !(reanudar && reanuda != nil) { env["PIPER_INIT_WEIGHTS"] = baseCkpt(cal.id).path }
            // Limitar torch a los núcleos RÁPIDOS (performance): en Apple Silicon incluir los
            // efficiency frena cada op al ritmo del más lento (CPU 100% sin avanzar).
            let pc = "\(nucleosRapidos())"
            env["PIPER_THREADS"] = pc; env["OMP_NUM_THREADS"] = pc
            env["MKL_NUM_THREADS"] = pc; env["VECLIB_MAXIMUM_THREADS"] = pc
            // Sin buffer: que la barra de progreso (paso/época) salga al log EN VIVO, no
            // recién al primer checkpoint. Así la bitácora muestra los pasos en tiempo real.
            env["PYTHONUNBUFFERED"] = "1"
            tr.environment = env
            let trLog = proyecto.appendingPathComponent("piper.log")
            if reanudar {
                if !fm.fileExists(atPath: trLog.path) { _ = fm.createFile(atPath: trLog.path, contents: nil) }
            } else {
                // Un entrenamiento FRESCO no puede heredar el "terminó" ni la barra de
                // una corrida anterior. `createFile` NO truncaba un archivo existente.
                try? Data().write(to: trLog, options: .atomic)
            }
            if let fh = try? FileHandle(forWritingTo: trLog) {
                if reanudar {
                    _ = try? fh.seekToEnd()
                    let pasoBase = reanuda.flatMap(pasoCheckpoint) ?? 0
                    try? fh.write(contentsOf: Data("\n[BD] reanudando desde checkpoint step=\(pasoBase)\n".utf8))
                }
                tr.standardOutput = fh; tr.standardError = fh
            }
            do { try tr.run() } catch {
                DispatchQueue.main.async { onArranco(false, "No pude lanzar el entrenamiento.", proyecto) }; return
            }
            proc = tr
            // Espera a que el LOOP de entrenamiento arranque (la barra/época aparece) o muera.
            // OJO: el 1er checkpoint recién sale a ~200 pasos, así que NO esperamos "paso>=1".
            var arranco = false
            for _ in 0..<240 {
                Thread.sleep(forTimeInterval: 1)
                if logEntrenando(proyecto) { arranco = true; break }
                if !tr.isRunning { break }
            }
            DispatchQueue.main.async {
                onArranco(arranco && tr.isRunning,
                          arranco ? "Entrenando en \(proyecto.lastPathComponent)" : "El entrenamiento no arrancó (mira piper.log).",
                          proyecto)
            }
        }
    }

    private static var cancelado = false
    static func detener() { cancelado = true; proc?.terminate(); proc = nil }
    static func esActivo() -> Bool { proc?.isRunning ?? false }

    /// DETENER A PRUEBA DE BALAS, controlado por el USUARIO (no depende de `proc`, que es
    /// nil si la app se reabrió). Mata TODO el árbol del proyecto — python de entrenamiento
    /// o de dataset, y sus hijos (ffmpeg, whisper) — porque TODOS llevan la ruta del
    /// proyecto en sus argumentos. SIGTERM y, a lo que quede, SIGKILL. Verifica que murió.
    static func detenerProyecto(_ proyecto: URL, done: @escaping (Bool) -> Void = { _ in }) {
        cancelado = true
        proc?.terminate(); proc = nil
        let patron = proyecto.lastPathComponent   // p.ej. "mivoz_run": único por proyecto
        DispatchQueue.global(qos: .userInitiated).async {
            matar(["-TERM", "-f", patron])
            Thread.sleep(forTimeInterval: 0.8)
            matar(["-KILL", "-f", patron])         // forzado a lo que ignore el TERM (torch/C)
            Thread.sleep(forTimeInterval: 0.4)
            var vivo = sigueVivo(proyecto)
            if vivo { matar(["-KILL", "-f", patron]); Thread.sleep(forTimeInterval: 0.4); vivo = sigueVivo(proyecto) }
            DispatchQueue.main.async { done(!vivo) }
        }
    }

    private static func matar(_ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = args; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }; p.waitUntilExit()
    }

    /// ¿Queda ALGÚN proceso vivo de este proyecto? (para confirmar el Detener en la UI).
    static func sigueVivo(_ proyecto: URL) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", proyecto.lastPathComponent]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }; p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Extrae una PISTA legible del dataset.log para decirle al usuario qué pasó
    /// (ffmpeg faltante, sin audios, errores por archivo). Objetivo: ver el porqué.
    static func pistaDataset(_ proyecto: URL) -> String {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("dataset.log"), encoding: .utf8)) ?? ""
        let lineas = log.split(separator: "\n").map(String.init)
        if let x = lineas.last(where: { $0.contains("[X]") }) { return String(x.dropFirst(3).prefix(120)).trimmingCharacters(in: .whitespaces) }
        if lineas.contains(where: { $0.contains("No such file or directory: 'ffmpeg'") || $0.contains("ffmpeg") && $0.contains("[!]") }) {
            return "no se encontró ffmpeg al procesar (instala: brew install ffmpeg)"
        }
        if let bang = lineas.last(where: { $0.contains("[!]") }) { return "error al procesar audios: " + String(bang.dropFirst(3).prefix(100)) }
        if let ok = lineas.last(where: { $0.contains("[OK]") }) { return String(ok.dropFirst(4).prefix(120)).trimmingCharacters(in: .whitespaces) }
        return ""
    }

    /// Entorno para subprocesos con PATH AMPLIADO. Una app lanzada desde Finder (LSUIElement)
    /// trae PATH mínimo y NO vería ffmpeg de Homebrew → el dataset fallaría. Añadimos las
    /// rutas típicas (mismo patrón que AgenteHermes).
    static func entorno() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "")
        return env
    }

    /// Ruta ABSOLUTA de ffmpeg/ffprobe (nil si no hay). Una app de Finder no ve el PATH de
    /// Homebrew, así que buscamos en las rutas típicas y, si no, vía `which` con PATH ampliado.
    static func rutaBin(_ nombre: String) -> String? {
        for base in ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"]
            where FileManager.default.isExecutableFile(atPath: base + nombre) { return base + nombre }
        let w = Process(); w.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        w.arguments = ["which", nombre]; w.environment = entorno()
        let pipe = Pipe(); w.standardOutput = pipe; w.standardError = FileHandle.nullDevice
        do { try w.run() } catch { return nil }; w.waitUntilExit()
        guard w.terminationStatus == 0 else { return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }
    static func ffmpegListo() -> Bool { rutaBin("ffmpeg") != nil }

    /// Núcleos RÁPIDOS (performance) del Mac. En Apple Silicon usar solo estos evita que los
    /// efficiency (lentos) frenen el entrenamiento. Fallback: mitad de los lógicos.
    static func nucleosRapidos() -> Int {
        var n: Int32 = 0; var sz = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &n, &sz, nil, 0) == 0, n > 0 { return Int(n) }
        return max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    }

    /// ¿El loop de entrenamiento ya arrancó? (la barra/época o los params aparecen en el
    /// log). Señal de "arranco" fiable: el 1er checkpoint recién sale a ~200 pasos.
    private static func logEntrenando(_ proyecto: URL) -> Bool {
        let log = colaLog(proyecto.appendingPathComponent("piper.log"))
        return log.contains("[BD] step=") || log.contains("Epoch 0") || log.contains("it/s") || log.contains("Trainable params")
    }
    /// ¿El fit terminó de verdad? (Lightning imprime el motivo de parada).
    static func termino(_ proyecto: URL) -> Bool {
        let log = colaLog(proyecto.appendingPathComponent("piper.log"))
        return log.contains("max_steps=") && log.contains("reached") || log.contains("`Trainer.fit` stopped")
    }

    // MARK: Progreso VIVO + re-enganche al reabrir la app
    //
    // El entrenamiento corre como proceso HIJO. Si el usuario cierra la ventana o incluso
    // BtoDicta, el proceso queda HUÉRFANO y SIGUE (launchd lo adopta) escribiendo su log.
    // Al reabrir, detectamos ese proceso vivo (pgrep) y re-enganchamos el progreso. Si de
    // plano se apagó la compu, no hay proceso: se ofrece REANUDAR desde el último checkpoint.

    struct Vivo { var fase: Int; var faseTotal: Int; var pct: Double; var texto: String; var activo: Bool; var termino: Bool
        var paso: Int = 0; var total: Int = 0; var epoca: Int = 0 }

    private static func mtime(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Lee SOLO la cola (últimos `kb` KB) de un archivo. piper.log crece a decenas de MB
    /// (la barra de tqdm escribe una línea por refresco); leerlo entero cada 2s trababa la
    /// UI. La cola basta para el estado actual (barra, época, fin, últimas líneas).
    static func colaLog(_ url: URL, kb: Int = 96) -> String {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let n = UInt64(kb * 1024)
        if size > n { try? fh.seek(toOffset: size - n) }
        else { try? fh.seek(toOffset: 0) }
        let data = (try? fh.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r", with: "\n")
    }

    /// ¿Sigue vivo un proceso de entrenamiento de ESTE proyecto? (aunque la app se cerró y
    /// reabrió: lo detecta por pgrep sobre la ruta del proyecto).
    static func procesoVivo(_ proyecto: URL) -> Bool {
        if esActivo() { return true }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", proyecto.lastPathComponent + "/run"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }; p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// El proyecto que está trabajando AHORA (entrenando o preparando dataset), para
    /// re-enganchar el progreso al reabrir. Basado en proceso vivo o log recién escrito.
    static func proyectoActivo() -> URL? {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: proyectosDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for d in dirs.sorted(by: { mtime($0) > mtime($1) }) {
            if procesoVivo(d) { return d }
            let dl = d.appendingPathComponent("dataset.log")
            let pl = d.appendingPathComponent("piper.log")
            // dataset en curso: dataset.log fresco y aún sin fase de entrenamiento.
            if FileManager.default.fileExists(atPath: dl.path), !FileManager.default.fileExists(atPath: pl.path),
               Date().timeIntervalSince(mtime(dl)) < 90 { return d }
        }
        return nil
    }

    private static func ultimoPar(_ s: String, _ pat: String) -> (Int, Int)? {
        guard let re = try? NSRegularExpression(pattern: pat) else { return nil }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard let m = ms.last, let r1 = Range(m.range(at: 1), in: s), let r2 = Range(m.range(at: 2), in: s) else { return nil }
        return (Int(s[r1]) ?? 0, Int(s[r2]) ?? 0)
    }
    private static func ultimoEntero(_ s: String, _ pat: String, primero: Bool = false) -> Int {
        guard let re = try? NSRegularExpression(pattern: pat) else { return 0 }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard let m = (primero ? ms.first : ms.last), let r = Range(m.range(at: 1), in: s) else { return 0 }
        return Int(s[r]) ?? 0
    }

    /// El wrapper antiguo contaba LOTES, pero Piper hace dos optimizer.step por lote;
    /// Lightning, checkpoints y `max_steps` cuentan PASOS GLOBALES. Convierte ambos
    /// formatos y conserva el checkpoint como piso fiable. El wrapper nuevo ya escribe
    /// `global_step` directamente.
    private static func pasoYVelocidad(_ log: String, pisoCheckpoint: Int) -> (paso: Int, gps: Double, exacto: Bool) {
        let global = ultimoEntero(log, "\\[BD\\] global_step=(\\d+)")
        if global > 0 {
            return (max(pisoCheckpoint, global), ultimoDouble(log, "gps=([0-9.]+)"), true)
        }
        let lote = ultimoEntero(log, "\\[BD\\] step=(\\d+)")
        let sps = ultimoDouble(log, "sps=([0-9.]+)")
        guard lote > 0 else { return (pisoCheckpoint, 0, false) }

        // Reanudaciones nuevas anotan el paso base. En logs antiguos reanudados sin base
        // no sumamos a ciegas sobre un checkpoint rodante que sigue avanzando.
        let base = ultimoEntero(log, "\\[BD\\] reanudando desde checkpoint step=(\\d+)")
        if base > 0 { return (max(pisoCheckpoint, base + lote * 2), sps * 2, false) }
        if log.contains("[BD] reanudando desde checkpoint") {
            return (pisoCheckpoint, 0, false)
        }
        return (max(pisoCheckpoint, lote * 2), sps * 2, false)
    }

    /// Progreso VIVO combinado con % y texto dinámico. Sabe en qué FASE va (1 dataset,
    /// 2 entrenamiento), calcula el % de cada una y dice qué está pasando ahora mismo.
    static func progresoVivo(_ proyecto: URL, etapas: Int) -> Vivo {
        let piLog = colaLog(proyecto.appendingPathComponent("piper.log"))
        let dsLog = colaLog(proyecto.appendingPathComponent("dataset.log"))
        let vivo = procesoVivo(proyecto)
        let fin = termino(proyecto)
        // piper.log con contenido = ya estamos en FASE 2 (aunque aún esté armando la caché).
        if !piLog.isEmpty || fin {
            // OJO: la barra de Lightning "X/Y m:ss" es el LOTE dentro de la ÉPOCA (X) sobre
            // los lotes-por-época (Y); se REINICIA cada época. NO es el paso global. El paso
            // GLOBAL = época × lotes_por_época + lote. Piso fiable: el último checkpoint.
            let bar = ultimoPar(piLog, "(\\d+)/(\\d+) \\d+:\\d+")
            let ep = ultimoEntero(piLog, "Epoch (\\d+)")
            let piso = pasoUltimoCheckpoint(proyecto)
            let vivoBD = pasoYVelocidad(piLog, pisoCheckpoint: piso)
            var paso = vivoBD.paso
            if !vivoBD.exacto, let (lote, lotesEp) = bar, lotesEp > 0 {
                // Barra/época también cuenta lotes: dos pasos globales por lote.
                paso = max(paso, (ep * lotesEp + lote) * 2)
            }
            let total = etapasPersistidas(proyecto) ?? (etapas > 0 ? etapas : 0)
            paso = total > 0 ? min(paso, total) : paso
            let pct = total > 0 ? min(1.0, Double(paso) / Double(total)) : 0
            let arrancoPasos = bar != nil || paso > 0
            let txt: String
            if fin { txt = "✓ Terminó — escucha y elige el mejor checkpoint abajo." }
            else if !arrancoPasos { txt = "Fase 2/2 · Preparando el modelo y la caché de audio (arranca en breve)…" }
            else { txt = "Fase 2/2 · Entrenando: paso \(paso) de \(total) (\(Int(pct*100))%) · época \(ep)" }
            return Vivo(fase: 2, faseTotal: 2, pct: pct, texto: txt, activo: vivo && !fin, termino: fin,
                        paso: paso, total: total, epoca: ep)
        }
        // Fase 1 — dataset (Whisper): archivos hechos / total + fragmentos.
        let tot = ultimoEntero(dsLog, "(\\d+) audios en", primero: true)
        let hechos = ultimoPar(dsLog, "(\\d+)/(\\d+) \\| clips")?.0 ?? 0
        let clips = ultimoEntero(dsLog, "clips=(\\d+)")
        let pct = tot > 0 ? Double(hechos) / Double(tot) : 0
        let txt = tot > 0
            ? "Fase 1/2 · Transcribiendo audios (Whisper): \(hechos) de \(tot) (\(Int(pct*100))%) · \(clips) fragmentos"
            : "Fase 1/2 · Preparando audios (Whisper)…"
        return Vivo(fase: 1, faseTotal: 2, pct: pct, texto: txt, activo: vivo || !dsLog.isEmpty, termino: false,
                    paso: hechos, total: tot, epoca: 0)
    }

    // MARK: Snapshot RICO para la bitácora en la app (recursos + contadores + últimas líneas)

    struct Snapshot {
        var fase: Int; var texto: String; var pct: Double
        var avanceGlobal: Double     // 0-1 del trabajo COMPLETO (dataset + entrenamiento)
        var avanceFase: Double       // 0-1 de la FASE actual
        var subfase: String          // qué se hace ahora mismo (archivo / época·paso)
        var paso: Int; var total: Int; var epoca: Int
        var itPerSec: Double; var etaMin: Int; var transcurridoMin: Int
        var finEstimada: Date?
        var cpuNucleos: Double; var nucleos: Int; var ramGB: Double; var discoGB: Double
        var gpu: String; var ia: String   // honesto: el entrenamiento va en CPU
        var clips: Int; var checkpoints: Int; var hitos: Int; var seguroPaso: Int
        var checkpointPuntos: [CheckpointInfo]; var rechazos: String
        var activo: Bool; var termino: Bool; var errores: Int
        var motor: String            // qué proceso trabaja (whisper / entrenamiento)
        var bitacora: [String]       // últimas líneas del log activo, limpias
    }

    private static var pidCache: (Date, Int?) = (.distantPast, nil)
    private static var discoCache: (Date, Double) = (.distantPast, 0)

    /// PID del proceso de entrenamiento del proyecto (o nil). Cacheado 3s.
    static func pidDe(_ proyecto: URL) -> Int? {
        if Date().timeIntervalSince(pidCache.0) < 3 { return pidCache.1 }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", proyecto.lastPathComponent + "/run"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        var pid: Int? = nil
        if (try? p.run()) != nil { p.waitUntilExit()
            let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            pid = s.split(separator: "\n").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        pidCache = (Date(), pid); return pid
    }

    private static func recursosProc(_ pid: Int) -> (Double, Double) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "%cpu=,rss=", "-p", "\(pid)"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (0, 0) }; p.waitUntilExit()
        let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let cols = s.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
        guard cols.count >= 2 else { return (0, 0) }
        return (cols[0], cols[1] / 1_048_576.0)   // %cpu, rss KB→GB
    }

    private static func discoGB(_ proyecto: URL) -> Double {
        if Date().timeIntervalSince(discoCache.0) < 12 { return discoCache.1 }   // du es caro
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", proyecto.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        var gb = discoCache.1
        if (try? p.run()) != nil { p.waitUntilExit()
            let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if let kb = Double(s.split(separator: "\t").first ?? "") { gb = kb / 1_048_576.0 }
        }
        discoCache = (Date(), gb); return gb
    }

    private static func ultimoDouble(_ s: String, _ pat: String) -> Double {
        guard let re = try? NSRegularExpression(pattern: pat) else { return 0 }
        let ms = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        guard let m = ms.last, let r = Range(m.range(at: 1), in: s) else { return 0 }
        return Double(s[r]) ?? 0
    }

    private static func velocidadCheckpoints(_ puntos: [CheckpointInfo]) -> Double {
        var unicos: [Int: CheckpointInfo] = [:]
        for p in puntos { unicos[p.paso] = p }
        let orden = unicos.values.sorted { $0.fecha < $1.fecha }
        guard orden.count >= 2 else { return 0 }
        for i in stride(from: orden.count - 1, through: 1, by: -1) {
            let a = orden[i - 1], b = orden[i]
            let dt = b.fecha.timeIntervalSince(a.fecha)
            let dp = b.paso - a.paso
            if dt > 10, dp > 0 { return Double(dp) / dt }
        }
        return 0
    }

    private static func inicioEntrenamiento(_ proyecto: URL) -> Date? {
        let log = proyecto.appendingPathComponent("piper.log")
        let a = try? FileManager.default.attributesOfItem(atPath: log.path)
        return a?[.creationDate] as? Date
    }

    static func snapshot(_ proyecto: URL, etapas: Int) -> Snapshot {
        let totalReal = etapasPersistidas(proyecto) ?? etapas
        let v = progresoVivo(proyecto, etapas: totalReal)
        let piLog = colaLog(proyecto.appendingPathComponent("piper.log"))
        let dsLog = colaLog(proyecto.appendingPathComponent("dataset.log"))
        let enFase2 = v.fase == 2
        let puntos = checkpointsDetalle(proyecto)
        let live = pasoYVelocidad(piLog, pisoCheckpoint: pasoUltimoCheckpoint(proyecto))
        let tasaCkpt = velocidadCheckpoints(puntos)
        let tasaBarra = ultimoDouble(piLog, "([0-9.]+)it/s") * 2
        let its = live.exacto && live.gps > 0 ? live.gps
            : (tasaCkpt > 0 ? tasaCkpt : max(live.gps, tasaBarra))
        let eta = (enFase2 && its > 0 && v.total > v.paso) ? Int(Double(v.total - v.paso) / its / 60.0) : 0
        let inicio = inicioEntrenamiento(proyecto)
        let transcurrido = inicio.map { max(0, Int(Date().timeIntervalSince($0) / 60)) } ?? 0
        let finEstimada = eta > 0 ? Date().addingTimeInterval(Double(eta) * 60) : nil
        let pid = v.activo ? pidDe(proyecto) : nil
        let rec = pid != nil ? recursosProc(pid!) : (0, 0)
        let clips = (try? String(contentsOf: proyecto.appendingPathComponent("dataset/metadata.csv"), encoding: .utf8))?
            .split(separator: "\n").count ?? 0
        // rechazos del dataset (última línea con {...})
        var rech = ""
        if let re = try? NSRegularExpression(pattern: "rechaz[^:]*: (\\{[^}]*\\})"),
           let m = re.matches(in: dsLog, range: NSRange(dsLog.startIndex..., in: dsLog)).last,
           let r = Range(m.range(at: 1), in: dsLog) { rech = String(dsLog[r]) }
        let errores = (piLog + dsLog).components(separatedBy: "Traceback").count - 1
        let activoLog = enFase2 ? piLog : dsLog
        // Bitácora: últimas líneas útiles (sin warnings ruidosos ni líneas vacías).
        let ruido = ["does not have many workers", "UserWarning", "FutureWarning", "warnings.warn",
                     "Tip:", "litmodels", "self.manual_backward", "optimizer.step()", "def training_step"]
        let lineas = activoLog.split(separator: "\n").map(String.init)
            .filter { l in !l.trimmingCharacters(in: .whitespaces).isEmpty && !ruido.contains { l.contains($0) } }
        let bit = Array(lineas.suffix(14))
        let motor = enFase2 ? "entrenamiento (torch/CPU)" : (v.activo ? "Whisper + ffmpeg" : "—")
        // Avance GLOBAL: el dataset pesa ~8% del trabajo; el entrenamiento ~92%.
        let pesoDS = 0.08
        let avGlobal: Double = v.termino ? 1.0 : (enFase2 ? pesoDS + (1 - pesoDS) * v.pct : pesoDS * v.pct)
        let subfase = enFase2
            ? (v.paso > 0 ? "época \(v.epoca) · paso \(v.paso)/\(v.total)" : "preparando modelo/caché")
            : (v.total > 0 ? "archivo \(v.paso)/\(v.total)" : "leyendo audios")
        // El entrenamiento corre en CPU: GPU y Neural Engine (IA) NO se usan (honesto).
        let ncpu = ProcessInfo.processInfo.activeProcessorCount
        return Snapshot(fase: v.fase, texto: v.texto, pct: v.pct,
                        avanceGlobal: avGlobal, avanceFase: v.pct, subfase: subfase,
                        paso: v.paso, total: v.total, epoca: v.epoca,
                        itPerSec: its, etaMin: eta, transcurridoMin: transcurrido,
                        finEstimada: finEstimada,
                        cpuNucleos: rec.0 / 100.0, nucleos: ncpu, ramGB: rec.1, discoGB: discoGB(proyecto),
                        gpu: "sin usar (entrena en CPU)", ia: "sin usar (entrena en CPU)",
                        clips: clips, checkpoints: puntos.count,
                        hitos: puntos.filter { !$0.seguro }.count,
                        seguroPaso: puntos.filter { $0.seguro }.map(\.paso).max() ?? 0,
                        checkpointPuntos: puntos, rechazos: rech,
                        activo: v.activo, termino: v.termino, errores: errores, motor: motor, bitacora: bit)
    }

    /// Nombre "bonito" (para reconstruir el campo Nombre al re-enganchar) desde la carpeta.
    static func nombreDeProyecto(_ proyecto: URL) -> String {
        proyecto.lastPathComponent.replacingOccurrences(of: "_run", with: "").replacingOccurrences(of: "-", with: " ")
    }
    /// Fuente de verdad del objetivo: config real de Lightning (si ya arrancó) → plan
    /// persistido (dataset/preparación) → log legado.
    /// Nunca vuelve a presentar 5000/5000 si el proceso fue lanzado con 10000 pasos.
    private static func etapasPersistidas(_ proyecto: URL) -> Int? {
        let logs = proyecto.appendingPathComponent("run/lightning_logs")
        if let en = FileManager.default.enumerator(at: logs, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let configs = en.compactMap { $0 as? URL }.filter { $0.lastPathComponent == "config.yaml" }
                .sorted { mtime($0) > mtime($1) }
            for u in configs {
                let s = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                let n = ultimoEntero(s, "max_steps:\\s*(\\d+)")
                if n > 0 { return n }
            }
        }
        if let n = DestiladorPiper.planGuardado(proyecto)?.etapas, n > 0 { return n }
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        let n = ultimoEntero(log, "max_steps=(\\d+)")
        return n > 0 ? n : nil
    }

    static func etapasDe(_ proyecto: URL) -> Int {
        etapasPersistidas(proyecto) ?? max(3000, pasoUltimoCheckpoint(proyecto))
    }

    // MARK: Resumible + progreso + checkpoints

    /// Extrae el paso únicamente del marcador `step=` que escribe Lightning.
    static func pasoCheckpoint(_ url: URL) -> Int? {
        guard let r = url.lastPathComponent.range(of: "step=") else { return nil }
        let num = url.lastPathComponent[r.upperBound...].prefix { $0.isNumber }
        return Int(num)
    }

    /// El último checkpoint (mayor paso) de un proyecto — para reanudar tras apagón.
    /// Considera los HITOS (ckpts/) y el checkpoint DE SEGURIDAD rodante (seguro/, cada
    /// 200 pasos): devuelve el de MAYOR paso → un apagón pierde 200 pasos como mucho.
    static func ultimoCheckpoint(_ proyecto: URL) -> URL? {
        var candidatos = checkpoints(proyecto)
        let seg = proyecto.appendingPathComponent("seguro")
        let items = (try? FileManager.default.contentsOfDirectory(at: seg, includingPropertiesForKeys: nil)) ?? []
        for u in items where u.pathExtension == "ckpt" {
            if let n = pasoCheckpoint(u) { candidatos.append((n, u)) }
        }
        return candidatos.max(by: { $0.paso < $1.paso })?.url
    }

    static func pasoUltimoCheckpoint(_ proyecto: URL) -> Int {
        ultimoCheckpoint(proyecto).flatMap(pasoCheckpoint) ?? 0
    }

    /// Checkpoints periódicos guardados (paso ascendente). El usuario elige el mejor.
    static func checkpoints(_ proyecto: URL) -> [(paso: Int, url: URL)] {
        let dir = proyecto.appendingPathComponent("ckpts")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [(Int, URL)] = []
        for u in items where u.pathExtension == "ckpt" {
            // nombre "pasostep=NNN.ckpt" o "...step=NNN...".
            if let n = pasoCheckpoint(u) { out.append((n, u)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    struct CheckpointInfo: Identifiable {
        let paso: Int
        let url: URL
        let seguro: Bool
        let fecha: Date
        var id: String { url.path }
    }

    /// Hitos elegibles + el seguro rodante. La UI los distingue: el seguro protege un
    /// apagón; los hitos son los que se validan y entre los que el usuario elige.
    static func checkpointsDetalle(_ proyecto: URL) -> [CheckpointInfo] {
        var out = checkpoints(proyecto).map {
            CheckpointInfo(paso: $0.paso, url: $0.url, seguro: false, fecha: mtime($0.url))
        }
        let dir = proyecto.appendingPathComponent("seguro")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for u in items where u.pathExtension == "ckpt" {
            if let p = pasoCheckpoint(u) { out.append(CheckpointInfo(paso: p, url: u, seguro: true, fecha: mtime(u))) }
        }
        return out.sorted { $0.fecha < $1.fecha }
    }

    /// ¿Hay un proyecto a medio entrenar? (para ofrecer "reanudar"). Devuelve el más
    /// reciente con checkpoints pero sin voz emitida.
    static func proyectoReanudable() -> URL? {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: proyectosDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let conCkpt = dirs.filter { ultimoCheckpoint($0) != nil }
        return conCkpt.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.first
    }

    /// Progreso EN VIVO. El paso global fiable = el MAYOR checkpoint guardado (Lightning
    /// no imprime "step=N" en el log, solo la barra "época N · lote X/Y"). El "lote" de la
    /// barra da movimiento fino entre checkpoints. `total` lo compone el caller (etapas).
    static func progreso(_ proyecto: URL) -> Progreso {
        let raw = (try? String(contentsOf: proyecto.appendingPathComponent("piper.log"), encoding: .utf8)) ?? ""
        let log = raw.replacingOccurrences(of: "\r", with: "\n")
        func ultimoInt(_ patron: String, _ grupo: Int = 1) -> Int {
            guard let re = try? NSRegularExpression(pattern: patron) else { return 0 }
            let ms = re.matches(in: log, range: NSRange(log.startIndex..., in: log))
            guard let m = ms.last, let r = Range(m.range(at: grupo), in: log) else { return 0 }
            return Int(log[r]) ?? 0
        }
        let epoca = ultimoInt("Epoch (\\d+)")
        let paso = pasoUltimoCheckpoint(proyecto)
        // Barra rica: "… 2/4 0:00:04 • …" → lote actual / total del tramo.
        let lote = ultimoInt("(\\d+)/(\\d+) \\d+:\\d+", 1)
        let loteTot = ultimoInt("\\d+/(\\d+) \\d+:\\d+", 1)
        var texto = "Preparando…"
        if paso > 0 {
            texto = "paso \(paso) · época \(epoca)" + (lote > 0 ? " · lote \(lote)/\(loteTot)" : "")
        } else if lote > 0 {
            texto = "época \(epoca) · lote \(lote)/\(loteTot)"
        }
        return Progreso(paso: paso, total: 0, epoca: epoca, texto: texto)
    }

    // MARK: Exportar ONNX + registrar como voz ⚡

    /// Exporta el checkpoint elegido a .onnx (+ .onnx.json = config del entreno) y lo
    /// registra en la biblioteca como voz Piper rápida, con su persona (prompt). `prompt`
    /// = cómo habla la persona (parámetro del usuario). Pesado; corre en background.
    static func exportarYregistrar(proyecto: URL, checkpoint: URL, nombre: String, prompt: String,
                                   stamp: String, vozExistenteId: String? = nil,
                                   completion: @escaping (VozLocal?, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("piperexp_\(stamp)")
            try? fm.removeItem(at: tmp); try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let onnx = tmp.appendingPathComponent("voz.onnx")
            let exp = Process(); exp.executableURL = VozEngine.pythonURL
            exp.arguments = ["-m", "piper.train.export_onnx", "--checkpoint", checkpoint.path, "--output-file", onnx.path]
            exp.environment = ProcessInfo.processInfo.environment
            exp.standardOutput = FileHandle.nullDevice; exp.standardError = FileHandle.nullDevice
            do { try exp.run(); exp.waitUntilExit() } catch {
                DispatchQueue.main.async { completion(nil, "No pude exportar el ONNX.") }; return
            }
            guard exp.terminationStatus == 0, fm.fileExists(atPath: onnx.path) else {
                DispatchQueue.main.async { completion(nil, "El export falló (revisa el checkpoint).") }; return
            }
            // <modelo>.onnx.json = config del entreno (Piper lo necesita para hablar).
            let cfg = proyecto.appendingPathComponent("config.json")
            if fm.fileExists(atPath: cfg.path) {
                try? fm.copyItem(at: cfg, to: URL(fileURLWithPath: onnx.path + ".json"))
            }
            // Registrar como voz nueva, o VINCULAR al XTTS que la enseñó (destilación).
            let registrada = vozExistenteId.flatMap { VocesLocales.vincularPiper(desde: onnx, a: $0) }
                ?? (vozExistenteId == nil ? VocesLocales.importarPiper(desde: onnx, nombre: nombre) : nil)
            guard var voz = registrada else {
                DispatchQueue.main.async { completion(nil, "No pude registrar la voz.") }; return
            }
            try? fm.removeItem(at: tmp)
            // Persona (cómo habla) — la que el usuario escribió, o autogenerada de los audios.
            var persona = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if persona.isEmpty, vozExistenteId != nil { persona = voz.persona }
            if persona.isEmpty {
                persona = Entrenador.personaDesdeAudios(
                    carpetaAudios: proyecto.appendingPathComponent("dataset/audio"),
                    nombre: nombre, stamp: stamp)
            }
            if !persona.isEmpty {
                var list = VocesLocales.todas()
                if let i = list.firstIndex(where: { $0.id == voz.id }) {
                    list[i].persona = persona; VocesLocales.guardar(list); voz = list[i]
                }
            }
            let msg = vozExistenteId == nil
                ? "✓ Voz “\(nombre)” lista (Piper rápida) y agregada a tu biblioteca."
                : "✓ Versión rápida ONNX vinculada a “\(nombre)”. Conservaste también XTTS."
            DispatchQueue.main.async { completion(voz, msg) }
        }
    }

    /// Genera una muestra hablada de un checkpoint (export temporal → piper) para que el
    /// usuario ESCUCHE antes de elegir. Devuelve el wav.
    static func muestra(proyecto: URL, checkpoint: URL, texto: String, stamp: String,
                        completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent("pipersamp_\(stamp)")
            try? fm.removeItem(at: tmp); try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            let onnx = tmp.appendingPathComponent("m.onnx")
            let exp = Process(); exp.executableURL = VozEngine.pythonURL
            exp.arguments = ["-m", "piper.train.export_onnx", "--checkpoint", checkpoint.path, "--output-file", onnx.path]
            exp.environment = ProcessInfo.processInfo.environment
            exp.standardOutput = FileHandle.nullDevice; exp.standardError = FileHandle.nullDevice
            do { try exp.run(); exp.waitUntilExit() } catch { DispatchQueue.main.async { completion(nil) }; return }
            let cfg = proyecto.appendingPathComponent("config.json")
            if fm.fileExists(atPath: cfg.path) { try? fm.copyItem(at: cfg, to: URL(fileURLWithPath: onnx.path + ".json")) }
            PiperTTS.decir(onnx: onnx, texto: texto) { wav in completion(wav) }
        }
    }

    // MARK: Errores

    /// ¿Hay un compilador C? (Xcode CLT) — necesario SOLO en fresh-install para compilar
    /// monotonic_align. En Mac de desarrollo siempre está; en Mac limpio: xcode-select --install.
    static func compiladorListo() -> Bool {
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/cc") { return true }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }; p.waitUntilExit()
        return p.terminationStatus == 0
    }

    enum Err: Error, LocalizedError {
        case setup, compilador
        var errorDescription: String? {
            switch self {
            case .setup: return "no pude preparar el entrenador de Piper (vits/monotonic)"
            case .compilador: return "falta el compilador de Apple. Abre Terminal y corre: xcode-select --install, luego reintenta"
            }
        }
    }

    // Deps de Piper-train (setup.py extra [train] de piper1-gpl v1.4.2). Sin pin de torch:
    // se usa el torch 2.5.1 del motor (funciona en CPU). lightning = paquete unificado.
    private static let pinsPiper = [
        "piper-tts", "lightning>=2,<3", "cython>=3,<4",
        "jsonargparse[signatures]>=4.27.7", "onnx", "tensorboardx",
        // Dataset + control de calidad. También hacen falta si el usuario IMPORTÓ un
        // XTTS y nunca abrió antes el entrenador XTTS completo.
        "mlx-whisper", "resemblyzer", "librosa", "soundfile", "matplotlib",
    ]

    // MARK: Scripts embebidos (nada depende de carpetas del usuario)

    /// Dataset Piper: carpeta de audios → 22050Hz mono + metadata.csv "archivo.wav|texto".
    /// Reusa ffmpeg (denoise/loudnorm) + mlx-whisper (turbo, ya descargado por XTTS).
    private static let piperDsPy = #"""
    #!/usr/bin/env python3
    import os, re, subprocess, sys, glob
    FOLDER=sys.argv[1]; OUT=sys.argv[2]
    AUD=os.path.join(OUT,"audio"); os.makedirs(AUD,exist_ok=True)
    SR=22050; MODEL="mlx-community/whisper-large-v3-turbo"; MIN_S,MAX_S=1.5,15.0
    # ffmpeg/ffprobe por ruta ABSOLUTA (una app de Finder no ve el PATH de Homebrew).
    FFMPEG=os.environ.get("FFMPEG","ffmpeg"); FFPROBE=os.environ.get("FFPROBE","ffprobe")
    EXTS=(".mp3",".ogg",".wav",".opus",".m4a",".aac",".flac")
    files=sorted(f for f in glob.glob(os.path.join(FOLDER,"**","*"),recursive=True) if f.lower().endswith(EXTS))
    print(f"[i] {len(files)} audios en {FOLDER} | ffmpeg={FFMPEG}",flush=True)
    if not files: print("[X] NO se hallaron audios (mp3/wav/m4a/opus/aac/flac/ogg) en la carpeta.",flush=True); sys.exit(0)
    try:
        import mlx_whisper
    except Exception as e:
        print("[X] mlx_whisper no disponible:",e,flush=True); sys.exit(0)
    rej={"dur":0,"txt":0,"cps":0,"reprobe":0}
    def dn(s,d): subprocess.run([FFMPEG,"-y","-v","error","-i",s,"-af","highpass=f=60,afftdn=nr=10:nf=-25,loudnorm=I=-20:TP=-2","-ar",str(SR),"-ac","1",d],check=True)
    def cut(s,a,b,d): subprocess.run([FFMPEG,"-y","-v","error","-ss",f"{a:.3f}","-to",f"{b:.3f}","-i",s,"-ar",str(SR),"-ac","1","-sample_fmt","s16",d],check=True)
    def dur(w):
        try: return float(subprocess.run([FFPROBE,"-v","error","-show_entries","format=duration","-of","csv=p=0",w],capture_output=True,text=True).stdout or 0)
        except: return 0.0
    meta=open(os.path.join(OUT,"metadata.csv"),"w"); tmp=os.path.join(OUT,"_t.wav"); kept=0; tot=0.0
    for i,f in enumerate(files):
        base=re.sub(r'[^A-Za-z0-9]','_',os.path.splitext(os.path.basename(f))[0])[:36]+f"_{i}"
        try:
            dn(f,tmp); r=mlx_whisper.transcribe(tmp,path_or_hf_repo=MODEL,language="es")
        except Exception as e: print("[!]",os.path.basename(f),repr(e),flush=True); continue
        for j,sg in enumerate(r.get("segments",[])):
            s,e2,txt=sg["start"],sg["end"],re.sub(r'\s+',' ',sg["text"].strip()); d=e2-s
            if d<MIN_S or d>MAX_S: rej["dur"]+=1; continue
            if len(txt)<4 or not re.search(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]',txt): rej["txt"]+=1; continue
            cps=len(txt)/d
            if cps<3 or cps>25: rej["cps"]+=1; continue
            cid=f"{base}_{j:02d}"; w=os.path.join(AUD,cid+".wav"); cut(tmp,s,e2,w)
            if MIN_S<=dur(w)<=MAX_S: meta.write(f"{cid}.wav|{txt}\n"); kept+=1; tot+=d
            else:
                rej["reprobe"]+=1
                try: os.remove(w)
                except OSError: pass
        meta.flush(); print(f"[i] {i+1}/{len(files)} | clips={kept} | {tot/60:.1f}min | rechazos {rej}",flush=True)
    meta.close()
    if os.path.exists(tmp):
        try: os.remove(tmp)
        except OSError: pass
    print(f"[OK] clips={kept} {tot/60:.1f}min | rechazados: {rej}",flush=True)
    """#

    /// Wrapper del fit: arregla torch 2.5 (weights_only) + hparams viejos. Para un
    /// proyecto NUEVO, PIPER_INIT_WEIGHTS carga solo state_dict en on_fit_start: el
    /// optimizador y los schedulers quedan realmente nuevos. Reanudar sí restaura todo.
    private static let trainWrapPy = #"""
    import inspect, os, torch, sys
    # Apple Silicon: torch reparte cada op entre TODOS los núcleos, pero los efficiency
    # (lentos) frenan al ritmo del más lento → CPU al 100% pero sin avanzar. Limitar a los
    # núcleos RÁPIDOS (performance) acelera muchísimo. PIPER_THREADS lo fija BtoDicta.
    _thr = int(os.environ.get("PIPER_THREADS", "6") or "6")
    if _thr > 0:
        torch.set_num_threads(_thr)
        try: torch.set_num_interop_threads(max(1, _thr // 2))
        except Exception: pass
    from piper.train.vits.lightning import VitsModel
    from piper.train.vits.dataset import VitsDataModule
    _m_keys = set(inspect.signature(VitsModel.__init__).parameters) - {"self"}
    _d_keys = set(inspect.signature(VitsDataModule.__init__).parameters) - {"self"}
    _init_weights = os.environ.get("PIPER_INIT_WEIGHTS", "").strip()
    _orig = torch.load
    def _load(*a, **k):
        k["weights_only"] = False
        ck = _orig(*a, **k)
        if isinstance(ck, dict):
            hp = ck.get("hyper_parameters")
            if isinstance(hp, dict):
                ck["hyper_parameters"] = {x: hp[x] for x in list(hp) if x in _m_keys}
            dhp = ck.get("datamodule_hyper_parameters")
            if isinstance(dhp, dict):
                ck["datamodule_hyper_parameters"] = {x: dhp[x] for x in list(dhp) if x in _d_keys}
        return ck
    torch.load = _load
    # Warm-start COMPLETO de pesos con estado de optimizador VACÍO. Trainer crea Adam antes
    # de on_fit_start y éste conserva referencias a los mismos parámetros, por lo que cargar
    # state_dict aquí actualiza el modelo sin heredar los 1.6 M pasos de la base.
    _orig_fit_start = VitsModel.on_fit_start
    def _fit_start(self):
        _orig_fit_start(self)
        if not _init_weights:
            return
        ck = _orig(_init_weights, map_location="cpu", weights_only=False)
        state = ck.get("state_dict", ck) if isinstance(ck, dict) else ck
        self.load_state_dict(state, strict=True)
        print("[BD] pesos base cargados; optimizadores frescos", flush=True)
    VitsModel.on_fit_start = _fit_start
    # Progreso EN VIVO propio: Lightning NO emite su barra al log cuando la salida es un
    # archivo (no-TTY). `training_step` es un LOTE, pero Piper ejecuta dos optimizadores
    # por lote; por eso registramos el global_step REAL de Lightning, no un contador local.
    import time as _t
    _bd = {"n": 0, "t": _t.time(), "g0": None}
    _orig_ts = VitsModel.training_step
    def _ts(self, *a, **k):
        antes = int(getattr(getattr(self,"trainer",None),"global_step",0) or 0)
        if _bd["g0"] is None: _bd["g0"] = antes
        r = _orig_ts(self, *a, **k)
        _bd["n"] += 1
        if _bd["n"] <= 3 or _bd["n"] % 10 == 0:
            gs = int(getattr(getattr(self,"trainer",None),"global_step",0) or 0)
            dt = _t.time() - _bd["t"]
            gps = (gs - int(_bd["g0"] or 0)) / dt if dt > 0 else 0
            bps = _bd["n"] / dt if dt > 0 else 0
            print(f"[BD] global_step={gs} batch={_bd['n']} gps={gps:.3f} bps={bps:.3f}", flush=True)
        return r
    VitsModel.training_step = _ts
    from piper.train.__main__ import main
    sys.argv[0] = "piper.train"
    main()
    """#

    /// Fresh-install: vendoriza el módulo vits de piper1-gpl v1.4.2 (el wheel de pip no lo
    /// trae) y compila monotonic_align REPLICANDO el build_monotonic_align.sh OFICIAL
    /// (cythonize -i + mover el .so a la subcarpeta anidada). Probado en Mac ARM. Solo
    /// corre si falta (idempotente).
    private static let setupPy = #"""
    import os, sys, subprocess, tarfile, tempfile, urllib.request, shutil, glob
    SP = sys.argv[1]  # site-packages
    dst = os.path.join(SP, "piper", "train", "vits")
    tag = "v1.4.2"
    url = f"https://github.com/OHF-Voice/piper1-gpl/archive/refs/tags/{tag}.tar.gz"
    tmp = tempfile.mkdtemp()
    tgz = os.path.join(tmp, "src.tar.gz")
    print("[i] descargando fuente piper1-gpl", tag, flush=True)
    urllib.request.urlretrieve(url, tgz)
    with tarfile.open(tgz) as t: t.extractall(tmp)
    root = glob.glob(os.path.join(tmp, "piper1-gpl-*"))[0]
    srcv = os.path.join(root, "src", "piper", "train", "vits")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst): shutil.rmtree(dst)
    shutil.copytree(srcv, dst)
    print("[i] vits copiado a", dst, flush=True)
    # Parche: comparación de resblock robusta (int/str). Sin esto, la calidad 'high'
    # (resblock tipo "1") NO carga: el CLI pasa 1 como int y models.py compara con "1".
    try:
        mp = os.path.join(dst, "models.py"); s = open(mp).read()
        s2 = s.replace('modules.ResBlock1 if resblock == "1" else modules.ResBlock2',
                       'modules.ResBlock1 if str(resblock) == "1" else modules.ResBlock2')
        if s != s2: open(mp, "w").write(s2); print("[i] models.py: resblock int/str", flush=True)
    except Exception as e: print("[!] parche models.py:", e, flush=True)
    # Compilar monotonic_align tal como el build_monotonic_align.sh oficial:
    #   cd monotonic_align; mkdir -p monotonic_align; rm -f core.c; cythonize -i core.pyx;
    #   mv core*.so monotonic_align/   (estructura anidada que __init__.py espera)
    mono = os.path.join(dst, "monotonic_align")
    if os.path.isdir(mono):
        nested = os.path.join(mono, "monotonic_align"); os.makedirs(nested, exist_ok=True)
        try: os.remove(os.path.join(mono, "core.c"))
        except OSError: pass
        cythonize = os.path.join(os.path.dirname(sys.executable), "cythonize")
        cmd = [cythonize, "-i", "core.pyx"] if os.path.exists(cythonize) \
              else [sys.executable, "-m", "Cython.Build.Cythonize", "-i", "core.pyx"]
        r = subprocess.run(cmd, cwd=mono, capture_output=True, text=True)
        if r.returncode != 0: print("[!] cythonize:", r.stderr[-400:], flush=True)
        for s in glob.glob(os.path.join(mono, "core*.so")):
            shutil.move(s, os.path.join(nested, os.path.basename(s)))
        ok = bool(glob.glob(os.path.join(nested, "core*.so")))
        print("[i] monotonic_align compilado:", ok, flush=True)
    print("[OK] setup vits listo", flush=True)
    """#

    /// Validación: por cada checkpoint, genera 5 frases, mide INTELIGIBILIDAD (Whisper
    /// transcribe y compara con el texto) + PARECIDO de voz (d-vector vs audios reales),
    /// escribe validacion.csv + validacion.png y dice cuál es el mejor. Marca la basura.
    private static let valPy = #"""
    #!/usr/bin/env python3
    import os, sys, subprocess, difflib, unicodedata, re, shutil, math
    import numpy as np
    PROJ=sys.argv[1]; PY=sys.executable
    CK=os.path.join(PROJ,"ckpts"); REF=os.path.join(PROJ,"dataset","audio"); OUT=os.path.join(PROJ,"val")
    os.makedirs(OUT,exist_ok=True)
    FRASES=["Hola mijo cómo estás, espero que estés muy bien.",
            "El río suena entre las piedras del camino.",
            "Hoy hace un día muy bonito para caminar.",
            "Te mando un abrazo grande y muchos cariños.",
            "Mañana vamos a cocinar algo rico.",
            "¿Puedes revisar el informe antes de las ocho y treinta?",
            "Ecuador tiene costa, sierra, Amazonía y región insular.",
            "Por favor envía el correo a Andrés cuando esté listo.",
            "Uno, dos, tres, cuatro, cinco, seis, siete, ocho y nueve.",
            "Gracias por tu ayuda; nos vemos mañana, que descanses."]
    def norm(s):
        s=unicodedata.normalize("NFD",s.lower()); s="".join(c for c in s if unicodedata.category(c)!="Mn")
        return re.sub(r"[^a-z0-9 ]","",s).split()
    def isim(a,b): return difflib.SequenceMatcher(None,norm(a),norm(b)).ratio()
    def stepof(f):
        m=re.search(r"(\d+)",f.replace("step=","")); return int(m.group(1)) if m else 0
    if not os.path.isdir(CK) or not [f for f in os.listdir(CK) if f.endswith(".ckpt")]:
        print("[OK] sin checkpoints",flush=True); sys.exit(0)
    print("[val] cargando modelos (Whisper + d-vector)…",flush=True)
    import mlx_whisper
    from resemblyzer import VoiceEncoder, preprocess_wav
    enc=VoiceEncoder()
    todas=[os.path.join(REF,f) for f in sorted(os.listdir(REF)) if f.endswith(".wav")] if os.path.isdir(REF) else []
    # Referencias repartidas por TODO el corpus, no solo las primeras 25.
    refs=[todas[i] for i in np.linspace(0,len(todas)-1,min(25,len(todas)),dtype=int)] if todas else []
    ref_emb=None
    if refs:
        try: ref_emb=np.mean([enc.embed_utterance(preprocess_wav(r)) for r in refs],axis=0)
        except Exception as e: print("[val] (sin ref de voz:",e,")",flush=True)
    cks=sorted([f for f in os.listdir(CK) if f.endswith(".ckpt")],key=stepof)
    # REANUDABLE: si un apagón cortó la validación, reusa lo ya puntuado (validacion.csv
    # se escribe INCREMENTALMENTE tras cada checkpoint) y salta esos checkpoints.
    rows=[]; hechos_previos=set()
    csvp=os.path.join(PROJ,"validacion.csv")
    pasos_actuales={stepof(f) for f in cks}
    if os.path.exists(csvp):
        for i,l in enumerate(open(csvp,encoding="utf-8")):
            c=l.strip().split(",")
            if i==0 or len(c)<4: continue
            try:
                st=int(c[0])
                if st in pasos_actuales:
                    rows.append((st,float(c[1]),float(c[2]),float(c[3]))); hechos_previos.add(st)
            except ValueError: pass
        if hechos_previos: print(f"[val] reusando {len(hechos_previos)} checkpoints ya validados",flush=True)
    def guardar_csv():
        tmp=csvp+".tmp"
        with open(tmp,"w",encoding="utf-8") as f:
            f.write("paso,inteligibilidad,parecido,score\n")
            for r in sorted(rows): f.write(f"{r[0]},{r[1]:.3f},{r[2]:.3f},{r[3]:.3f}\n")
        os.replace(tmp,csvp)
    for ck in cks:
        st=stepof(ck)
        if st in hechos_previos:
            print(f"[val] paso {st}: ya validado (reusado)",flush=True); continue
        onnx=os.path.join(OUT,ck+".onnx")
        exp=subprocess.run([PY,"-m","piper.train.export_onnx","--checkpoint",os.path.join(CK,ck),"--output-file",onnx],capture_output=True)
        if exp.returncode != 0 or not os.path.exists(onnx):
            print(f"[!] paso {st}: no se pudo exportar; se reintentará al continuar",flush=True); continue
        cfg=os.path.join(PROJ,"config.json")
        if os.path.exists(cfg): shutil.copy(cfg,onnx+".json")
        intel=[]; sims=[]
        for i,fr in enumerate(FRASES):
            wav=os.path.join(OUT,f"{st}_{i}.wav")
            subprocess.run([PY,"-m","piper","-m",onnx,"-f",wav],input=fr.encode(),capture_output=True)
            if not os.path.exists(wav): continue
            try:
                t=mlx_whisper.transcribe(wav,path_or_hf_repo="mlx-community/whisper-large-v3-turbo",language="es")["text"]
                intel.append(isim(fr,t))
            except Exception as e:
                print(f"[!] paso {st}, muestra {i}: Whisper falló ({e}); se reintentará",flush=True)
                continue
            if ref_emb is not None:
                try: sims.append(float(np.dot(ref_emb,enc.embed_utterance(preprocess_wav(wav)))))
                except Exception: pass
        # Un fallo transitorio no se memoriza como puntuación cero para siempre.
        minimo=max(3,math.ceil(len(FRASES)*0.6))
        if len(intel)<minimo:
            print(f"[!] paso {st}: solo {len(intel)}/{len(FRASES)} muestras válidas; queda pendiente",flush=True)
            continue
        it=float(np.mean(intel))
        sm=float(np.mean(sims)) if sims else 0.0
        score=it*0.6+(sm if it>=0.5 else 0.0)*0.4
        rows.append((st,it,sm,score))
        guardar_csv()   # incremental: un apagón aquí no pierde lo ya puntuado
        print(f"[val] paso {st}: inteligible={it:.2f} parecido={sm:.2f} score={score:.2f}",flush=True)
        for i in range(len(FRASES)):
            w=os.path.join(OUT,f"{st}_{i}.wav")
            if i>0 and os.path.exists(w):
                try: os.remove(w)
                except OSError: pass
    rows=sorted(rows)
    guardar_csv()
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        s=[r[0] for r in rows]
        plt.figure(figsize=(8,4.2))
        plt.plot(s,[r[1] for r in rows],"-o",label="inteligibilidad (Whisper)")
        plt.plot(s,[r[2] for r in rows],"-s",label="parecido de voz (d-vector)")
        plt.plot(s,[r[3] for r in rows],"-^",lw=2.2,label="score final")
        plt.axhline(0.5,color="red",ls="--",alpha=0.4,label="mínimo inteligible")
        plt.ylim(0,1); plt.xlabel("paso"); plt.ylabel("0 a 1"); plt.legend(fontsize=8); plt.grid(alpha=0.3)
        plt.title("Validación de checkpoints Piper (más arriba = mejor)")
        plt.tight_layout(); plt.savefig(os.path.join(PROJ,"validacion.png"),dpi=100)
    except Exception as e: print("[val] (sin gráfica:",e,")",flush=True)
    best=max(rows,key=lambda r:r[3]) if rows else None
    if best and best[1]>=0.5: print(f"[OK] mejor=paso{best[0]} score={best[3]:.2f} — sí es usable",flush=True)
    elif best: print(f"[OK] ninguno inteligible (mejor paso{best[0]} intel={best[1]:.2f}) — necesita MÁS entrenamiento",flush=True)
    else: print("[OK] sin checkpoints",flush=True)
    """#
}
