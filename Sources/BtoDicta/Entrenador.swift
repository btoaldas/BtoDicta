import Foundation
import AVFoundation

// MARK: - Entrenador de clones de voz (planificación inteligente)
//
// El usuario suelta una carpeta de audios de UNA persona; BtoDicta entrena un clon
// XTTS (pipeline propio de BtoDicta, corre en el motor aislado, en background
// con resiliencia) y al final emite un PAQUETE portable. Este archivo es el CEREBRO
// de PARÁMETROS: según cuánto audio hay, recomienda etapas + checkpoints (el usuario
// puede cambiarlos). Nada se entrena aquí todavía — solo se decide el plan.
//
// Regla de la casa (confirmada con el pipeline real, info.py):
//   < 1h  → NO sirve (ni dejar iniciar): lo genérico domina, ningún checkpoint convence.
//   1–2h  → aceptable (se reconoce a la persona).       recomendado ~3000 etapas.
//   2–4h  → bueno (la persona domina, su acento).        recomendado ~4000.
//   4–6h  → excelente (impecable).                        recomendado ~5000.
//   > 6h  → ya no mejora proporcional (desperdicio).      tope 5000, con aviso.
// Menos audio = menos etapas (más etapas sobre poca voz sobreajusta y no mejora).

struct PlanEntrenamiento {
    var minutos: Double
    var permitido: Bool            // false si < 1h → ni se deja iniciar
    var tier: String               // etiqueta legible del nivel
    var etapasRecomendadas: Int    // etapas (steps) sugeridas
    var checkpoints: [Int]         // cortes donde guardar y luego comparar
    var aviso: String              // nota para el usuario (por qué / advertencia)
}

enum Entrenador {
    /// Validación: tu spec = 10 muestras de ~30s (se pasa como env VAL_N / VAL_SEC al
    /// pipeline, que por defecto trae 5 × 20s).
    static let valN = 10
    static let valSeg = 30

    /// Suma la duración (minutos) de los audios de una carpeta (recursivo). Sin deps:
    /// AVFoundation. Para mostrar el plan ANTES de entrenar.
    static func duracionMinutos(_ carpeta: URL) -> Double {
        let exts: Set<String> = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "opus"]
        let fm = FileManager.default
        guard let en = fm.enumerator(at: carpeta, includingPropertiesForKeys: nil) else { return 0 }
        var seg = 0.0
        for case let u as URL in en where exts.contains(u.pathExtension.lowercased()) {
            let a = AVURLAsset(url: u)
            let d = CMTimeGetSeconds(a.duration)
            if d.isFinite, d > 0 { seg += d }
        }
        return seg / 60.0
    }

    /// Recomienda el plan según los MINUTOS de audio. El usuario puede editar todo.
    static func recomendar(minutos: Double) -> PlanEntrenamiento {
        switch minutos {
        case ..<60:
            return PlanEntrenamiento(
                minutos: minutos, permitido: false, tier: "❌ Muy poco (menos de 1 hora)",
                etapasRecomendadas: 0, checkpoints: [],
                aviso: "Con menos de 1 hora de voz el clon no convence — lo genérico domina y ningún corte queda bien. Junta más audio (meta: 1 a 3 horas).")
        case 60..<120:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🟡 Aceptable (1–2 h)",
                etapasRecomendadas: 3000, checkpoints: [500, 1500, 2000, 2500, 3000],
                aviso: "Se reconoce a la persona (aún cuela algo genérico). Con poca voz, más etapas NO mejora: tope ~3000.")
        case 120..<240:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🟢 Bueno (2–4 h)",
                etapasRecomendadas: 4000, checkpoints: [1000, 2000, 3000, 3500, 4000],
                aviso: "La persona domina y se le nota su acento. Recomendado ~4000 etapas.")
        case 240..<360:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "⭐ Excelente (4–6 h)",
                etapasRecomendadas: 5000, checkpoints: [1500, 2500, 3500, 4500, 5000],
                aviso: "Suficiente voz para un clon impecable. Recomendado ~5000 etapas.")
        default:
            return PlanEntrenamiento(
                minutos: minutos, permitido: true, tier: "🔵 De sobra (más de 6 h)",
                etapasRecomendadas: 5000, checkpoints: [1500, 2500, 3500, 4500, 5000],
                aviso: "Ya tienes voz de sobra; más de ~5000 etapas no mejora proporcional, solo cuesta tiempo y disco. Se mantiene el tope en 5000.")
        }
    }

    /// Estimación de horas de entrenamiento (CPU) para mostrar antes de arrancar.
    /// Muy aproximada: XTTS en CPU ~2-4 s/paso según la máquina.
    static func horasEstimadas(etapas: Int, segPorPaso: Double = 3.0) -> Double {
        Double(etapas) * segPorPaso / 3600.0
    }

    // MARK: Orquestación (dataset → train en background)

    /// Carpeta donde viven los proyectos de entrenamiento (gestionados).
    static var proyectosDir: URL { Config.dir.appendingPathComponent("entrenamientos") }
    private static var trainProc: Process?

    struct Progreso { var fase: String; var paso: Int; var total: Int; var texto: String; var loss: Double = 0 }

    /// Lanza un entrenamiento: FASE dataset (Whisper) → FASE train (background).
    /// `stamp` = marca de tiempo para el nombre del proyecto (se pasa desde afuera:
    /// los scripts no pueden usar Date()). `onArranco(true)` cuando train ya da pasos.
    /// Corre en el motor AISLADO. NO espera a terminar (son horas); el caller decide.
    static func entrenar(carpeta: URL, nombre: String, stamp: String, etapas: Int = 0,
                         onProgreso: @escaping (Progreso) -> Void,
                         onArranco: @escaping (Bool, String) -> Void) {
        guard VozEngine.estado() == .listo, VozEngine.entrenoListo else {
            onArranco(false, "El motor de entrenamiento no está listo."); return
        }
        let proyecto = proyectosDir.appendingPathComponent("\(slug(nombre))_\(stamp)")
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(at: proyecto, withIntermediateDirectories: true)
            let clonar = VozEngine.pipelineDir.appendingPathComponent("clonar")
            // FASE 1 — dataset (build_ds.py). Sincrónico; con VAL_N/VAL_SEC del spec.
            DispatchQueue.main.async { onProgreso(Progreso(fase: "dataset", paso: 0, total: 0, texto: "Transcribiendo audios (Whisper)…")) }
            let ds = Process(); ds.executableURL = VozEngine.pythonURL
            ds.arguments = [clonar.appendingPathComponent("build_ds.py").path, carpeta.path, proyecto.path]
            var env = entornoProceso()
            env["VAL_N"] = "\(valN)"; env["VAL_SEC"] = "\(valSeg)"
            if etapas > 0 { env["STEPS"] = "\(etapas)" }   // etapas elegidas por el usuario (0 = auto)
            ds.environment = env
            let dsLog = proyecto.appendingPathComponent("dataset.log")
            fm.createFile(atPath: dsLog.path, contents: nil)
            if let fh = try? FileHandle(forWritingTo: dsLog) { ds.standardOutput = fh; ds.standardError = fh }
            do { try ds.run(); ds.waitUntilExit() } catch {
                DispatchQueue.main.async { onArranco(false, "Falló el dataset: \(error.localizedDescription)") }; return
            }
            guard ds.terminationStatus == 0,
                  let n = try? String(contentsOf: proyecto.appendingPathComponent("dataset/metadata_train.csv"), encoding: .utf8),
                  n.split(separator: "\n").count > 1 else {
                DispatchQueue.main.async { onArranco(false, "El dataset quedó vacío (¿audio muy corto?).") }; return
            }
            // FASE 2 — train (train.py) en BACKGROUND → train.log.
            DispatchQueue.main.async { onProgreso(Progreso(fase: "train", paso: 0, total: 0, texto: "Arrancando el entrenamiento…")) }
            let tr = Process(); tr.executableURL = VozEngine.pythonURL
            // train.py lee el plan por ARGUMENTO. Antes solo se ponía STEPS en el entorno
            // y la cantidad elegida en la interfaz podía quedar ignorada.
            tr.arguments = [clonar.appendingPathComponent("train.py").path,
                            proyecto.path, "\(etapas)"]
            tr.environment = env
            let trLog = proyecto.appendingPathComponent("train.log")
            fm.createFile(atPath: trLog.path, contents: nil)
            if let fh = try? FileHandle(forWritingTo: trLog) { tr.standardOutput = fh; tr.standardError = fh }
            do { try tr.run() } catch {
                DispatchQueue.main.async { onArranco(false, "No pude lanzar el entrenamiento.") }; return
            }
            trainProc = tr
            // Espera a que dé el 1er paso (arrancó de verdad) o muera.
            var arranco = false
            for _ in 0..<120 {
                Thread.sleep(forTimeInterval: 1)
                let p = leerProgreso(proyecto)
                if p.total > 0 { DispatchQueue.main.async { onProgreso(p) } }
                if p.paso >= 0 && p.total > 0 && registroTieneStep(trLog) { arranco = true; break }
                if !tr.isRunning { break }
            }
            DispatchQueue.main.async {
                onArranco(arranco && tr.isRunning, arranco ? "Entrenando en \(proyecto.lastPathComponent)" : "El entrenamiento no arrancó.")
            }
        }
    }

    static func detener() { trainProc?.terminate(); trainProc = nil }

    // MARK: Best-pick — ranking de checkpoints (d-vector coseno)

    struct RankCheckpoint { var etapa: Int; var score: Double; var ruta: URL? }

    /// Lee validacion.csv (measure.py: d-vector Resemblyzer + coseno vs voz real) y
    /// devuelve los checkpoints ordenados del MEJOR al peor (promedio de coseno). El
    /// #1 es la RECOMENDACIÓN; el usuario puede escuchar cualquiera y elegir.
    static func rankingValidacion(proyecto: URL) -> [RankCheckpoint] {
        guard let csv = try? String(contentsOf: proyecto.appendingPathComponent("validacion.csv"), encoding: .utf8) else { return [] }
        let ckpts = (try? FileManager.default.contentsOfDirectory(at: proyecto.appendingPathComponent("run"),
                     includingPropertiesForKeys: nil)) ?? []
        func ruta(_ n: Int) -> URL? {
            // Busca run/**/checkpoint_N.pth.
            for d in ckpts {
                let c = d.appendingPathComponent("checkpoint_\(n).pth")
                if FileManager.default.fileExists(atPath: c.path) { return c }
            }
            return nil
        }
        var filas: [RankCheckpoint] = []
        for (i, linea) in csv.split(separator: "\n").enumerated() where i > 0 {   // salta cabecera
            let cols = linea.split(separator: ",")
            guard cols.count >= 2, let etapa = Int(cols[0]), let score = Double(cols[cols.count - 1]) else { continue }
            filas.append(RankCheckpoint(etapa: etapa, score: score, ruta: ruta(etapa)))
        }
        return filas.sorted { $0.score > $1.score }
    }

    /// Corre la VALIDACIÓN de un proyecto entrenado: pick_clips → genera esos clips con
    /// CADA checkpoint → measure (d-vector coseno). Deja validacion.csv + validacion.png.
    /// `onFin(true)` si produjo el CSV. Pesado (genera N clips × M checkpoints).
    static func validar(proyecto: URL, onProgreso: @escaping (String) -> Void,
                        onFin: @escaping (Bool) -> Void) {
        guard VozEngine.estado() == .listo, VozEngine.entrenoListo else { onFin(false); return }
        let clonar = VozEngine.pipelineDir.appendingPathComponent("clonar")
        DispatchQueue.global(qos: .userInitiated).async {
            func py(_ script: String, _ args: [String]) -> Bool {
                let p = Process(); p.executableURL = VozEngine.pythonURL
                p.arguments = [clonar.appendingPathComponent(script).path] + args
                var env = entornoProceso()
                env["VAL_N"] = "\(valN)"; env["VAL_SEC"] = "\(valSeg)"
                p.environment = env
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return false }; p.waitUntilExit(); return p.terminationStatus == 0
            }
            DispatchQueue.main.async { onProgreso("Eligiendo clips de validación…") }
            _ = py("pick_clips.py", [proyecto.path])
            // gen por checkpoint × clip.
            let val = (try? String(contentsOf: proyecto.appendingPathComponent("val_clips.txt"), encoding: .utf8)) ?? ""
            let clips = val.split(separator: "\n").map(String.init).filter { $0.contains("|") }
            let ckDirs = (try? FileManager.default.contentsOfDirectory(at: proyecto.appendingPathComponent("run"), includingPropertiesForKeys: nil)) ?? []
            var checkpoints: [(Int, URL)] = []
            for d in ckDirs {
                let items = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
                for c in items where c.lastPathComponent.hasPrefix("checkpoint_") && c.pathExtension == "pth" {
                    if let n = Int(c.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "checkpoint_", with: "")) {
                        checkpoints.append((n, c))
                    }
                }
            }
            try? FileManager.default.createDirectory(at: proyecto.appendingPathComponent("val"), withIntermediateDirectories: true)
            for (n, ck) in checkpoints.sorted(by: { $0.0 < $1.0 }) {
                DispatchQueue.main.async { onProgreso("Generando validación del checkpoint \(n)…") }
                for (i, linea) in clips.enumerated() {
                    let txt = linea.components(separatedBy: "|").last ?? ""
                    guard !txt.isEmpty else { continue }
                    _ = py("gen.py", [proyecto.path, ck.path, txt, proyecto.appendingPathComponent("val/\(n)_\(i).wav").path])
                }
            }
            DispatchQueue.main.async { onProgreso("Comparando con tu voz real (d-vector)…") }
            _ = py("measure.py", [proyecto.path])
            let ok = FileManager.default.fileExists(atPath: proyecto.appendingPathComponent("validacion.csv").path)
            DispatchQueue.main.async { onFin(ok) }
        }
    }

    // MARK: Post-train — persona + emitir el PAQUETE portable

    /// Genera la PERSONA (cómo habla) del proyecto con persona.py (Whisper ya transcribió
    /// en el dataset). Devuelve la persona lista; conserva además corpus y prompt
    /// detallado para que el usuario pueda revisarla o mejorarla.
    static func generarPersona(proyecto: URL, nombre: String) -> String {
        let clonar = VozEngine.pipelineDir.appendingPathComponent("clonar")
        let meta = proyecto.appendingPathComponent("dataset/metadata.csv")
        guard FileManager.default.fileExists(atPath: meta.path) else { return "" }
        let p = Process(); p.executableURL = VozEngine.pythonURL
        p.arguments = [clonar.appendingPathComponent("persona.py").path, meta.path, proyecto.path, nombre]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        let skill = proyecto.appendingPathComponent("persona_SKILL.md")
        let prompt = proyecto.appendingPathComponent("persona_PROMPT.md")
        return (try? String(contentsOf: FileManager.default.fileExists(atPath: skill.path) ? skill : prompt,
                            encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Genera la PERSONA a partir de una carpeta de audios (transcribe con Whisper vía
    /// build_ds → persona.py). Para clones de FUERA que llegan sin persona. "" si no se
    /// puede (motor sin entrenamiento). `stamp` para el temporal.
    static func personaDesdeAudios(carpetaAudios: URL, nombre: String, stamp: String) -> String {
        guard VozEngine.estado() == .listo, VozEngine.entrenoListo else { return "" }
        let clonar = VozEngine.pipelineDir.appendingPathComponent("clonar")
        let proj = FileManager.default.temporaryDirectory.appendingPathComponent("persona_\(slug(nombre))_\(stamp)")
        try? FileManager.default.removeItem(at: proj)
        try? FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        func py(_ script: String, _ args: [String]) {
            let p = Process(); p.executableURL = VozEngine.pythonURL
            p.arguments = [clonar.appendingPathComponent(script).path] + args
            p.environment = entornoProceso()
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        py("build_ds.py", [carpetaAudios.path, proj.path])   // transcribe → dataset/metadata.csv
        let meta = proj.appendingPathComponent("dataset/metadata.csv")
        guard FileManager.default.fileExists(atPath: meta.path) else { try? FileManager.default.removeItem(at: proj); return "" }
        py("persona.py", [meta.path, proj.path, nombre])
        let skill = proj.appendingPathComponent("persona_SKILL.md")
        let prompt = proj.appendingPathComponent("persona_PROMPT.md")
        let persona = (try? String(contentsOf: FileManager.default.fileExists(atPath: skill.path) ? skill : prompt,
                                   encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(at: proj)
        return persona
    }

    /// Emite el PAQUETE portable de un checkpoint elegido: persona + ensamblado
    /// (reusa el import inteligente → rellena config/vocab/runner/manifest). Registra
    /// la voz. `stamp` para el temporal (los scripts no usan Date()).
    static func emitirPaquete(proyecto: URL, checkpoint: URL, nombre: String, stamp: String,
                              completion: @escaping (VocesLocales.ResultadoImport) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let persona = generarPersona(proyecto: proyecto, nombre: nombre)
            // Carpeta temporal con lo mínimo; el import inteligente completa el resto.
            let temp = fm.temporaryDirectory.appendingPathComponent("emitir_\(slug(nombre))_\(stamp)")
            try? fm.removeItem(at: temp)
            try? fm.createDirectory(at: temp.appendingPathComponent("refs"), withIntermediateDirectories: true)
            // El portable usa un checkpoint SLIM (solo inferencia), no el estado completo
            // del optimizador. Si slim falla, conserva el checkpoint original como respaldo.
            let slimDir = temp.appendingPathComponent("_slim")
            try? fm.createDirectory(at: slimDir, withIntermediateDirectories: true)
            let slim = Process(); slim.executableURL = VozEngine.pythonURL
            slim.arguments = [VozEngine.pipelineDir.appendingPathComponent("clonar/slim.py").path,
                              checkpoint.path, slimDir.path]
            slim.environment = entornoProceso()
            slim.standardOutput = FileHandle.nullDevice; slim.standardError = FileHandle.nullDevice
            if (try? slim.run()) != nil { slim.waitUntilExit() }
            let modelo = ((try? fm.contentsOfDirectory(at: slimDir, includingPropertiesForKeys: nil)) ?? [])
                .first(where: { $0.pathExtension == "pth" }) ?? checkpoint
            try? fm.copyItem(at: modelo, to: temp.appendingPathComponent(modelo.lastPathComponent))
            try? fm.removeItem(at: slimDir)
            // Refs desde ref_list.txt del proyecto (rutas relativas al proyecto o absolutas).
            if let lista = try? String(contentsOf: proyecto.appendingPathComponent("ref_list.txt"), encoding: .utf8) {
                for (i, l) in lista.split(separator: "\n").prefix(8).enumerated() {
                    let ruta = l.hasPrefix("/") ? String(l) : proyecto.appendingPathComponent(String(l)).path
                    if fm.fileExists(atPath: ruta) {
                        try? fm.copyItem(atPath: ruta, toPath: temp.appendingPathComponent("refs/ref\(i).wav").path)
                    }
                }
            }
            if !persona.isEmpty {
                try? persona.write(to: temp.appendingPathComponent("persona.txt"),
                                   atomically: true, encoding: .utf8)
            }
            // El portable lleva persona activa + corpus/prompt para revisarla o volver a
            // mejorarla en otra Mac, sin Hermes ni el proyecto original.
            for nombrePersona in ["persona_SKILL.md", "persona_PROMPT.md", "persona_corpus.txt"] {
                let src = proyecto.appendingPathComponent(nombrePersona)
                if fm.fileExists(atPath: src.path) {
                    try? fm.copyItem(at: src, to: temp.appendingPathComponent(nombrePersona))
                }
            }
            // Todo clon XTTS creado por BtoDicta puede usar la restauración común. El
            // portable lleva solo esta receta; el runtime/pesas se instalan una vez por Mac.
            let maxima = temp.appendingPathComponent("maxima")
            try? fm.createDirectory(at: maxima, withIntermediateDirectories: true)
            let maximaCfg: [String: Any] = ["formato": "btodicta-maxima/1",
                                            "motor": "xtts+resemble-enhance",
                                            "nfe": 128, "tau": 0.15, "lambda": 0.5]
            if let data = try? JSONSerialization.data(withJSONObject: maximaCfg, options: .prettyPrinted) {
                try? data.write(to: maxima.appendingPathComponent("config.json"), options: .atomic)
            }
            let manifest = ["nombre": nombre]
            if let mj = try? JSONSerialization.data(withJSONObject: manifest) {
                try? mj.write(to: temp.appendingPathComponent("btodicta-voz.json"))
            }
            let r = VocesLocales.importarPaquete(desde: temp)
            try? fm.removeItem(at: temp)
            DispatchQueue.main.async { completion(r) }
        }
    }

    /// Lee el avance desde train.log (STEP/GLOBAL_STEP y el total del [PLAN]).
    static func leerProgreso(_ proyecto: URL) -> Progreso {
        let log = (try? String(contentsOf: proyecto.appendingPathComponent("train.log"), encoding: .utf8)) ?? ""
        func ultimo(_ patron: String) -> Int? {
            guard let re = try? NSRegularExpression(pattern: patron) else { return nil }
            let ms = re.matches(in: log, range: NSRange(log.startIndex..., in: log))
            guard let m = ms.last, let r = Range(m.range(at: 1), in: log) else { return nil }
            return Int(log[r])
        }
        func ultimoD(_ patron: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: patron) else { return nil }
            let ms = re.matches(in: log, range: NSRange(log.startIndex..., in: log))
            guard let m = ms.last, let r = Range(m.range(at: 1), in: log) else { return nil }
            return Double(log[r])
        }
        let paso = ultimo("GLOBAL_STEP: (\\d+)") ?? 0
        let total = ultimo("~(\\d+) pasos") ?? 0
        let loss = ultimoD("loss: ([0-9.]+)") ?? 0
        let pct = total > 0 ? Int(Double(paso) / Double(total) * 100) : 0
        return Progreso(fase: "train", paso: paso, total: total,
                        texto: total > 0 ? "Paso \(paso) de \(total) (\(pct)%)" + (loss > 0 ? " · loss \(String(format: "%.3f", loss))" : "") : "Preparando…",
                        loss: loss)
    }

    private static func registroTieneStep(_ log: URL) -> Bool {
        guard let t = try? String(contentsOf: log, encoding: .utf8) else { return false }
        return t.contains("GLOBAL_STEP:")
    }

    /// Entorno estable para procesos lanzados desde una app GUI (que normalmente no
    /// hereda el PATH de Homebrew). Los scripts reciben rutas explícitas de audio.
    private static func entornoProceso() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["COQUI_TOS_AGREED"] = "1"
        let prefijos = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (prefijos + [env["PATH"] ?? ""]).joined(separator: ":")
        if let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            env["BTODICTA_FFMPEG"] = ffmpeg
        }
        if let ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            env["BTODICTA_FFPROBE"] = ffprobe
        }
        return env
    }

    static func slug(_ s: String) -> String {
        let b = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return b.isEmpty ? "voz" : b
    }
}
