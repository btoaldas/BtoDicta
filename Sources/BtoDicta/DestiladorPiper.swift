import Foundation

// MARK: - XTTS de calidad → Piper/ONNX rápido (destilación local)
//
// No existe una conversión de archivos XTTS→ONNX compatible con Piper: son redes distintas.
// La ruta correcta es teacher/student: el XTTS ya bueno habla un corpus CONTROLADO; ese
// audio, con su texto exacto, entrena Piper y finalmente se exporta a ONNX. Así se evita el
// ruido del dataset original (otras voces, música y errores de Whisper) sin perder el XTTS.

enum DestiladorPiper {
    struct Tamano: Identifiable {
        let id: Int                 // frases
        let etiqueta: String
        let detalle: String
        let etapas: Int
    }

    static let tamanos = [
        Tamano(id: 120, etiqueta: "Prueba", detalle: "~10 min · comprueba el recorrido, no para voz final", etapas: 600),
        Tamano(id: 600, etiqueta: "Recomendado", detalle: "~45–60 min de voz sintética limpia", etapas: 3000),
        Tamano(id: 1200, etiqueta: "Alta fidelidad", detalle: "~1.5–2 h de voz sintética limpia", etapas: 4000),
        Tamano(id: 2400, etiqueta: "Máximo", detalle: "~3–4 h; tarda y ocupa más disco", etapas: 5000),
    ]

    static var scriptURL: URL { EntrenadorPiper.raizDir.appendingPathComponent("xtts_a_piper.py") }
    private static var proceso: Process?
    private static var cancelado = false

    /// Se guarda ANTES de generar el primer clip. Así un apagón durante el dataset
    /// conserva exactamente las decisiones del usuario, no solo el preset recomendado.
    struct PlanGuardado: Codable {
        let cantidad: Int
        let etapas: Int
        let calidad: String
    }

    static func stamp(_ voz: VozLocal) -> String { "onnx-" + Entrenador.slug(voz.id) }
    static func proyecto(_ voz: VozLocal) -> URL {
        EntrenadorPiper.proyectosDir.appendingPathComponent("\(Entrenador.slug(voz.nombre))_\(stamp(voz))")
    }

    static func guardarPlan(_ plan: PlanGuardado, en proyecto: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: proyecto, withIntermediateDirectories: true)
        let url = proyecto.appendingPathComponent("plan-destilacion.json")
        let data = try JSONEncoder().encode(plan)
        try data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func planGuardado(_ proyecto: URL) -> PlanGuardado? {
        let url = proyecto.appendingPathComponent("plan-destilacion.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlanGuardado.self, from: data)
    }

    static func clipsListos(_ proyecto: URL) -> Int {
        ((try? String(contentsOf: proyecto.appendingPathComponent("dataset/metadata.csv"), encoding: .utf8))?
            .split(separator: "\n").count) ?? 0
    }

    /// Detecta también un generador huérfano de una instancia anterior de BtoDicta.
    /// Evita lanzar DOS XTTS sobre la misma tanda si la app se cerró pero el hijo sobrevivió.
    static func procesoVivo(_ proyecto: URL) -> Bool {
        if let propio = proceso, propio.isRunning {
            return propio.arguments?.contains(where: { $0.contains(proyecto.path) }) ?? false
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "xtts_a_piper.py.*\(proyecto.lastPathComponent)"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Corpus español determinista y fonéticamente variado. Al ampliar el tamaño conserva
    /// las primeras frases, de modo que una generación interrumpida se puede continuar.
    static func corpus(cantidad: Int) -> [String] {
        let especiales = [
            "Hola, hoy quiero conversar contigo con calma y claridad.",
            "¿Cómo estás? Espero que tengas una mañana tranquila y productiva.",
            "El rápido zorro café saltó sobre quince cajas de madera.",
            "Zentrix, WhatsApp, Outlook y BtoDicta son nombres que uso con frecuencia.",
            "Mañana a las ocho y treinta revisaré la agenda y los recordatorios.",
            "En Quito llueve con fuerza, pero la tarde suele sentirse cálida.",
            "Necesito comprar café, azúcar, pan, queso y veinticuatro limones.",
            "La tecnología debe ser útil, sencilla, privada y accesible para todos.",
            "Por favor, envía el informe antes del viernes veintiséis de septiembre.",
            "¡Qué alegría escucharte! Cuéntame despacio qué sucedió durante el viaje.",
            "Uno, dos, tres, cuatro, cinco, seis, siete, ocho, nueve y diez.",
            "La niña pidió jugo de naranja mientras su hermano arreglaba el jardín.",
            "Ecuador tiene costa, sierra, Amazonía y una región insular extraordinaria.",
            "¿Quieres que busque la dirección, abra el mapa o prepare un correo?",
            "Gracias por tu ayuda; quedamos atentos a cualquier observación adicional.",
            "La guitarra, el xilófono y el charango acompañaron aquella canción.",
            "Mi número de referencia es cuatrocientos treinta y dos, guion, dieciocho.",
            "Aunque parezca difícil, podemos resolverlo paso a paso y sin apuro.",
            "Buenos días, equipo. Adjunto el documento revisado para su aprobación.",
            "Nos vemos mañana. Que descanses y tengas una noche muy bonita.",
        ]
        let inicios = [
            "Hoy quiero", "Esta mañana necesito", "Antes de salir voy a", "Por la tarde prefiero",
            "Con mucha calma puedo", "Cuando termine deseo", "Para ayudarte debo", "En unos minutos intentaré",
            "Si todo sale bien podremos", "Después del almuerzo conviene", "Durante la reunión vamos a",
            "Al comenzar el día suelo", "Con atención es posible", "La próxima semana quisiera",
        ]
        let acciones = [
            "revisar", "organizar", "explicar", "comparar", "confirmar", "preparar", "corregir",
            "compartir", "guardar", "buscar", "recordar", "actualizar", "clasificar", "resumir",
            "comprobar", "traducir", "redactar", "escuchar", "presentar", "coordinar", "calcular",
        ]
        let objetos = [
            "el informe de actividades", "las tareas pendientes", "un mensaje para la familia",
            "la lista completa de contactos", "los datos del proyecto", "una respuesta clara y amable",
            "el calendario de esta semana", "la carpeta de documentos", "el presupuesto actualizado",
            "las fotografías del viaje", "la dirección del nuevo edificio", "el correo para el equipo",
            "los resultados de la prueba", "la música de la biblioteca", "una nota breve para mañana",
            "los números de la factura", "la configuración de la computadora", "el texto de la presentación",
            "las ideas de la conversación", "el archivo que recibimos ayer", "la agenda del próximo mes",
        ]
        let finales = [
            "antes de continuar", "sin perder ningún detalle", "y avisarte cuando esté listo",
            "con palabras sencillas", "para evitar una confusión", "de la manera más segura",
            "mientras tomamos un café", "en español latino", "con una voz natural y pausada",
            "para compartirlo mañana", "sin cambiar el sentido original", "y comprobar el resultado dos veces",
            "desde esta misma computadora", "con respeto y buena ortografía", "cuando termine la descarga",
            "aunque no tengamos conexión a internet", "para que cualquier persona lo entienda",
        ]

        var salida: [String] = []
        var vistos = Set<String>()
        func agregar(_ texto: String) {
            let t = texto.replacingOccurrences(of: "|", with: ",")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, vistos.insert(t).inserted { salida.append(t) }
        }
        especiales.forEach(agregar)
        var i = 0
        while salida.count < max(4, cantidad) {
            let ini = inicios[i % inicios.count]
            let accion = acciones[(i * 5 + i / 7) % acciones.count]
            let objeto = objetos[(i * 7 + i / 3) % objetos.count]
            let final = finales[(i * 11 + i / 5) % finales.count]
            agregar("\(ini) \(accion) \(objeto) \(final).")
            i += 1
        }
        return Array(salida.prefix(max(4, cantidad)))
    }

    static func escribirScript() {
        try? FileManager.default.createDirectory(at: EntrenadorPiper.raizDir, withIntermediateDirectories: true)
        try? script.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
    }

    /// Genera/reanuda el dataset exacto. No borra clips válidos: ampliar 600→1200 reutiliza
    /// los primeros 600. `completion` vuelve en main con proyecto + número de clips usables.
    static func prepararDataset(voz: VozLocal, cantidad: Int, calidadId: String,
                                onProgreso: @escaping (String) -> Void,
                                completion: @escaping (Bool, String, URL, Int) -> Void) {
        let proyecto = proyecto(voz)
        guard proceso?.isRunning != true, !procesoVivo(proyecto) else {
            completion(false, "Ya hay una destilación local trabajando.", proyecto, clipsListos(proyecto)); return
        }
        guard VozEngine.estado() == .listo else {
            completion(false, "Primero instala el motor local de voz.", proyecto, 0); return
        }
        guard !voz.paquete.isEmpty, FileManager.default.fileExists(atPath: voz.paquete) else {
            completion(false, "La voz XTTS no tiene un paquete local válido.", proyecto, 0); return
        }
        escribirScript(); cancelado = false
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let ds = proyecto.appendingPathComponent("dataset")
            let corpusURL = proyecto.appendingPathComponent("corpus-xtts.txt")
            let logURL = proyecto.appendingPathComponent("destilacion.log")
            do {
                try fm.createDirectory(at: ds.appendingPathComponent("audio"), withIntermediateDirectories: true)
                let textos = corpus(cantidad: cantidad)
                try (textos.joined(separator: "\n") + "\n").write(to: corpusURL, atomically: true, encoding: .utf8)
                let reanudando = clipsListos(proyecto) > 0
                if !reanudando { try Data().write(to: logURL, options: .atomic) }
                else if !fm.fileExists(atPath: logURL.path) { _ = fm.createFile(atPath: logURL.path, contents: nil) }
                let log = try FileHandle(forWritingTo: logURL)
                if reanudando {
                    try log.seekToEnd()
                    try log.write(contentsOf: Data("\n[BDDEST] reanudando dataset\n".utf8))
                }
                let p = Process(); p.executableURL = VozEngine.pythonURL
                p.arguments = [scriptURL.path, voz.paquete, corpusURL.path, ds.path,
                               "\(EntrenadorPiper.calidad(calidadId).sampleRate)"]
                var env = EntrenadorPiper.entorno()
                env["COQUI_TOS_AGREED"] = "1"; env["CUDA_VISIBLE_DEVICES"] = ""
                env["PYTHONUNBUFFERED"] = "1"
                let hilos = "\(EntrenadorPiper.nucleosRapidos())"
                env["XTTS_THREADS"] = hilos; env["OMP_NUM_THREADS"] = hilos
                p.environment = env
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                pipe.fileHandleForReading.readabilityHandler = { fh in
                    let data = fh.availableData
                    guard !data.isEmpty else { return }
                    try? log.write(contentsOf: data)
                    guard let s = String(data: data, encoding: .utf8) else { return }
                    for linea in s.split(separator: "\n") {
                        let l = String(linea)
                        if l.contains("[BDDEST]") || l.contains("[OK]") || l.contains("[!]") {
                            DispatchQueue.main.async { onProgreso(l) }
                        }
                    }
                }
                proceso = p
                try p.run(); p.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                try? log.close(); proceso = nil
                let n = clipsListos(proyecto)
                let ok = !cancelado && p.terminationStatus == 0 && n > 3
                let msg = cancelado ? "Destilación detenida; puedes continuarla después."
                    : (ok ? "Dataset exacto listo: \(n) frases generadas por XTTS."
                          : "La destilación no terminó (\(n) clips). Revisa destilacion.log.")
                DispatchQueue.main.async { completion(ok, msg, proyecto, n) }
            } catch {
                proceso = nil
                DispatchQueue.main.async { completion(false, "Falló la destilación: \(error.localizedDescription)", proyecto, clipsListos(proyecto)) }
            }
        }
    }

    static func detener() { cancelado = true; proceso?.terminate(); proceso = nil }

    private static let script = #"""
    #!/usr/bin/env python3
    import json, math, os, sys, warnings
    warnings.filterwarnings("ignore")
    os.environ["COQUI_TOS_AGREED"]="1"; os.environ.setdefault("CUDA_VISIBLE_DEVICES","")
    import torch, torchaudio

    PKG=os.path.realpath(sys.argv[1]); CORPUS=sys.argv[2]; OUT=sys.argv[3]; SR=int(sys.argv[4])
    AUD=os.path.join(OUT,"audio"); META=os.path.join(OUT,"metadata.csv")
    os.makedirs(AUD,exist_ok=True)
    threads=int(os.environ.get("XTTS_THREADS","0") or "0")
    if threads>0:
        torch.set_num_threads(threads)
        try: torch.set_num_interop_threads(max(1,threads//2))
        except Exception: pass

    texts=[x.strip() for x in open(CORPUS,encoding="utf-8") if x.strip()]
    def safe(rel):
        p=os.path.realpath(os.path.join(PKG,rel))
        if os.path.commonpath([PKG,p]) != PKG: raise RuntimeError("ruta fuera del paquete")
        return p
    manp=safe("btodicta-voz.json")
    man=json.load(open(manp,encoding="utf-8")).get("archivos",{}) if os.path.exists(manp) else {}
    def rel(k,d): return safe(man.get(k,d))
    def okwav(path):
        try:
            info=torchaudio.info(path); dur=info.num_frames/max(1,info.sample_rate)
            return info.sample_rate == SR and 1.25 <= dur <= 16.0 and info.num_frames>0
        except Exception: return False
    def escribir(rows):
        tmp=META+".tmp"
        with open(tmp,"w",encoding="utf-8") as f:
            for idx,text in enumerate(texts):
                name=f"xtts_{idx+1:05d}.wav"
                if name in rows: f.write(name+"|"+text.replace("|",",")+"\n")
        os.replace(tmp,META)

    rows={}; faltan=[]
    for idx,text in enumerate(texts):
        name=f"xtts_{idx+1:05d}.wav"; path=os.path.join(AUD,name)
        if okwav(path): rows[name]=text
        else: faltan.append((idx,text,name,path))
    escribir(rows)
    print(f"[BDDEST] corpus={len(texts)} reusados={len(rows)} faltan={len(faltan)}",flush=True)
    if not faltan:
        print(f"[OK] dataset exacto listo clips={len(rows)}",flush=True); sys.exit(0)

    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import Xtts
    config=XttsConfig(); config.load_json(rel("config","config.json"))
    model=Xtts.init_from_config(config)
    model.load_checkpoint(config,checkpoint_path=rel("modelo","model.pth"),
                          vocab_path=rel("vocab","vocab.json"),use_deepspeed=False)
    model.cpu(); model.train(False)
    refs=[safe(x.strip()) for x in open(rel("ref_list","ref_list.txt"),encoding="utf-8") if x.strip()]
    if not refs: raise RuntimeError("el paquete no tiene muestras de referencia")
    gpt,spk=model.get_conditioning_latents(audio_path=refs)
    hechos=0; rechazados=0
    for pos,(idx,text,name,path) in enumerate(faltan,1):
        valido=False
        for intento,temp in enumerate((0.35,0.45,0.30),1):
            try:
                out=model.inference(text,"es",gpt,spk,temperature=temp,length_penalty=1.0,
                    repetition_penalty=10.0,top_k=40,top_p=0.82,enable_text_splitting=False)
                wav=torch.as_tensor(out["wav"],dtype=torch.float32).flatten()
                if wav.numel()==0 or not torch.isfinite(wav).all(): raise RuntimeError("audio vacío/NaN")
                if SR!=24000: wav=torchaudio.functional.resample(wav,24000,SR)
                dur=wav.numel()/float(SR); peak=float(wav.abs().max())
                habla=float((wav.abs()>0.008).float().mean())
                if not (1.25<=dur<=16.0) or peak<0.01 or habla<0.18:
                    raise RuntimeError(f"audio anómalo dur={dur:.1f}s habla={habla:.2f}")
                if peak>0.98: wav=wav*(0.98/peak)
                tmp=path+".tmp.wav"; torchaudio.save(tmp,wav.unsqueeze(0),SR,encoding="PCM_S",bits_per_sample=16)
                os.replace(tmp,path); valido=okwav(path)
                if valido: break
            except Exception as e:
                if intento==3: print(f"[!] {name}: {e}",flush=True)
        if valido: rows[name]=text; hechos+=1
        else: rechazados+=1
        if pos<=3 or pos%5==0 or pos==len(faltan):
            escribir(rows)
            print(f"[BDDEST] listo={len(rows)}/{len(texts)} nuevos={hechos} rechazados={rechazados}",flush=True)
    escribir(rows)
    if len(rows)<4: raise RuntimeError("muy pocos clips válidos")
    print(f"[OK] dataset exacto listo clips={len(rows)} rechazados={rechazados}",flush=True)
    """#
}
