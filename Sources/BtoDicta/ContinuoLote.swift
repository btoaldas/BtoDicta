import AVFoundation
import Foundation

// MARK: - Bitácora continua: tanda diferida
//
// Transcribe en bloque lo que la bitácora fue grabando, y de paso comprime el
// audio crudo. Se ejecuta cuando el usuario lo pida —cada tantos minutos, a una
// hora fija, al encender, al apagar o a mano— y nunca mientras se dicta.
//
// Diferir es el punto: transcribir en caliente mantiene un modelo de voz
// ocupando CPU todo el día. En una sola pasada, con el equipo enchufado, sale
// mucho más barato y no se nota.
//
// Reanudable por construcción: el índice marca cada fragmento como procesado
// solo cuando su texto ya está guardado. Si la tanda se corta a la mitad, la
// siguiente sigue donde quedó sin repetir trabajo.

enum ContinuoLote {

    private static let cola = DispatchQueue(label: "btodicta.continuo.lote", qos: .utility)
    private static var enMarcha = false
    private static let candado = NSLock()

    /// Última vez que se vio actividad de dictado, para no arrancar encima.
    static var dictadoOcupado: (() -> Bool)?

    /// ¿Hay alguien dictando ahora mismo?
    ///
    /// Lo publica el hilo principal, que es quien lo sabe, y lo lee la cola de
    /// la tanda. Antes la cola llamaba a un cierre que iba a leer propiedades
    /// de `main`: una carrera sobre el dato con el que se decide si transcribir
    /// de fondo mientras la persona está hablando. En la duda vale más creer
    /// que sí está ocupado —la tanda espera— que ponerse a competir por la CPU
    /// justo cuando más se nota.
    private static let candadoOcupado = NSLock()
    private static var _ocupado = true
    static var ocupadoPublicado: Bool {
        candadoOcupado.lock(); defer { candadoOcupado.unlock() }
        return _ocupado
    }
    static func publicarOcupado(_ v: Bool) {
        candadoOcupado.lock(); _ocupado = v; candadoOcupado.unlock()
    }

    // MARK: Entrada

    /// Lanza una tanda si procede. `manual` salta las condiciones de energía
    /// porque lo pidió una persona mirando la pantalla.
    /// `canal`: qué procesar — "todo", "voz", "sistema" o "pantalla". A
    /// petición se puede drenar un solo canal sin esperar a los demás.
    /// `huboTanda` dice si esta llamada llegó a procesar algo. Importa: una
    /// rutina que se dispara mientras otra tanda está en marcha recibía el aviso
    /// y GENERABA SU DOCUMENTO IGUAL, con material que todavía no se había
    /// transcrito. El documento salía pobre y nadie sabía por qué.
    static func ejecutar(manual: Bool = false, canal: String = "todo",
                         alTerminar: ((String) -> Void)? = nil,
                         huboTanda: ((Bool) -> Void)? = nil) {
        candado.lock()
        if enMarcha {
            candado.unlock()
            alTerminar?("Ya hay una tanda en curso.")
            huboTanda?(false)
            return
        }
        enMarcha = true
        candado.unlock()
        defer { huboTanda?(true) }

        cola.async {
            let resumen = trabajar(manual: manual, canal: canal)
            candado.lock(); enMarcha = false; candado.unlock()
            Log.log(.sistema, "bitácora: \(resumen)")
            DispatchQueue.main.async { alTerminar?(resumen) }
        }
    }

    static var ocupado: Bool {
        candado.lock(); defer { candado.unlock() }
        return enMarcha
    }

    // MARK: Trabajo

    private static func trabajar(manual: Bool, canal: String = "todo") -> String {
        guard Config.continuoActivo() else { return "la bitácora está apagada" }
        if !manual, Config.continuoLoteSoloConCorriente(), !EnergiaMac.conCorriente() {
            return "tanda pospuesta: el equipo está con batería"
        }

        ContinuoIndice.shared.abrir()
        purgarPapelera()
        // Pase lo que pase al salir (fin normal, corte por dictado, canal sin
        // pendientes), los diarios quedan al día con lo procesado hasta ese
        // momento. Antes solo se reconstruían al final feliz y una tanda
        // interrumpida los dejaba viejos.
        //
        // Y no solo los de HOY: los pendientes llegan de lo más viejo a lo más
        // nuevo sin filtrar por fecha, así que una tanda procesa rutinariamente
        // material de días anteriores (el Mac durmió de noche, tanda «al
        // encender»). Como el diario filtra por día, ese texto no entra en el
        // de hoy — hay que regenerar también el diario de cada día tocado, o
        // lo transcrito de ayer no llegaría jamás a ningún diario.
        var diasTocados: Set<Date> = [Calendar.current.startOfDay(for: Date())]
        defer { for dia in diasTocados.sorted(by: <) { reconstruirDiarios(dia) } }

        // El canal separa la voz del audio del sistema por su columna `origen`
        // en el índice: ambos son material "audio" y se pueden drenar por
        // separado a petición. El filtro va DENTRO de la consulta, antes del
        // tope por tanda: filtrarlo aquí después de cortar hacía que una cola
        // larga del otro canal tapara los fragmentos del canal pedido y la
        // tanda respondiera «no había pendiente» habiendo trabajo.
        let pendientes = canal == "pantalla" ? [] : ContinuoIndice.shared.pendientes(
            material: .audio, limite: Config.continuoLoteMaximoPorTanda(),
            canal: canal == "voz" || canal == "sistema" ? canal : nil)
        if pendientes.isEmpty {
            if canal == "voz" || canal == "sistema" { return "no había \(canal) pendiente" }
            if canal == "pantalla" { return leerPantallas(prefijo: "", soloPantalla: true, diasTocados: &diasTocados) }
            return leerPantallas(prefijo: "no había audio pendiente", diasTocados: &diasTocados)
        }

        Log.log(.sistema, "bitácora: tanda con \(pendientes.count) fragmentos pendientes")
        var hechos = 0, fallos = 0, saltados = 0, silenciosos = 0
        var comprimidos: Int64 = 0

        for p in pendientes {
            // El dictado manda también aquí: si la persona está hablando, la
            // tanda espera. Transcribir de fondo mientras se dicta compite por
            // CPU justo en el momento en que más se nota.
            if dictadoOcupado?() == true {
                Log.log(.sistema, "bitácora: tanda en pausa, hay dictado en curso")
                return "tanda detenida al empezar un dictado — \(hechos) hechos, quedan \(pendientes.count - hechos)"
            }
            guard FileManager.default.fileExists(atPath: p.ruta.path) else {
                // El archivo se borró por fuera: se marca para no reintentarlo eternamente.
                ContinuoIndice.shared.anotarTexto("", material: .audio, id: p.id)
                saltados += 1
                continue
            }

            // Si no suena nada, no se manda a ningún motor.
            //
            // La bitácora graba todo el rato, y buena parte de lo que graba es
            // silencio: nadie habla, o se está delante del equipo sin decir
            // nada. Medido en esta máquina: el 36 % de los trozos. Cada uno se
            // mandaba a la nube, el motor devolvía «respuesta sin texto»
            // —correctamente, porque no hay nada que transcribir—, la cascada lo
            // contaba como FALLO y probaba con el siguiente motor. En un día:
            // 312 llamadas gastadas para no obtener nada.
            //
            // Mirar el audio cuesta milisegundos y se hace en local.
            if AudioSilencio.esSilencio(p.ruta) {
                ContinuoIndice.shared.anotarTexto("", material: .audio, id: p.id)
                silenciosos += 1
                // Guardar horas de ruido de fondo no sirve a nadie y ocupa. Pero
                // esta puerta sola mira ENERGÍA, no voz, y equivocarse aquí
                // cuesta audio perdido: por eso no borra. Solo se retira lo que
                // las DOS puertas den por mudo, más abajo.
                continue
            }

            // SEGUNDA PUERTA: un motor local hace de portero.
            //
            // Mirar la energía del audio es barato pero tonto: distingue fuerte
            // de flojo, no voz de ruido. Un ventilador, una obra en la calle o
            // una conversación en el pasillo tienen energía de sobra y pasan.
            //
            // Un modelo de voz sí sabe distinguirlo, y para esto NO necesita
            // transcribir bien: solo necesita contestar si alguien habló. Por eso
            // el portero puede ser el motor local más rápido aunque no sea el más
            // preciso — su respuesta no se entrega a nadie, solo abre o cierra la
            // puerta. Lo que se entrega lo produce el motor que el usuario haya
            // puesto primero en su cascada, sea local o de nube.
            //
            // Apple Speech va en el sistema, no sale del equipo, no cuesta y
            // tarda 0,8 s con dos minutos de audio.
            if let portero = Config.bitacoraPortero(), !portero.isEmpty {
                let veredicto = PorteroVoz.hayVoz(en: p.ruta, motor: portero)
                if veredicto == .silencio {
                    ContinuoIndice.shared.anotarTexto("", material: .audio, id: p.id)
                    silenciosos += 1
                    // Aquí sí: DOS jueces independientes coinciden en que no hay
                    // voz —la energía del audio y un motor de reconocimiento—, y
                    // el trozo no vale ni el disco que ocupa.
                    //
                    // Va a la PAPELERA, no al vacío. Un detector puede
                    // equivocarse, y la diferencia entre un archivo recuperable y
                    // uno perdido es la diferencia entre un susto y un daño.
                    if Config.bitacoraRetirarSilencios() { aPapelera(p.ruta) }
                    continue
                }
                // `.noSePudo` (el portero falló, no hay modelo, se agotó el
                // tiempo) NO cierra la puerta: ante la duda se transcribe. Un
                // portero averiado no puede hacer perder lo dictado.
            }

            switch transcribir(p.ruta) {
            case .success(let texto):
                ContinuoIndice.shared.anotarTexto(texto, material: .audio, id: p.id)
                guardarTexto(texto, junto: p.ruta)
                diasTocados.insert(Calendar.current.startOfDay(for: p.instante))
                hechos += 1
                if Config.continuoLoteComprimir(), p.ruta.pathExtension == "pcm",
                   p.ruta.path.hasPrefix(Config.continuoCarpeta().path) {
                    if let ahorro = comprimir(p.ruta, id: p.id) { comprimidos += ahorro }
                }
            case .failure(let e):
                fallos += 1
                Log.log(.sistema, "bitácora: no pude transcribir \(p.ruta.lastPathComponent) — \(e.localizedDescription)")
            }
        }

        var partes = ["tanda terminada: \(hechos) transcritos"]
        if fallos > 0 { partes.append("\(fallos) con error") }
        if saltados > 0 { partes.append("\(saltados) sin archivo") }
        // Se dice: es la medida de cuánto se ahorra en llamadas de nube.
        if silenciosos > 0 { partes.append("\(silenciosos) en silencio, no enviados") }
        if comprimidos > 0 { partes.append("\(ContinuoBitacora.tamanoLegible(comprimidos)) liberados") }

        // Con canal de solo audio no se toca el OCR: eso es lo que pidió quien
        // pulsó el botón.
        if canal == "voz" || canal == "sistema" {
            return partes.joined(separator: ", ")
        }
        return leerPantallas(prefijo: partes.joined(separator: ", "), diasTocados: &diasTocados)
    }

    /// Tres archivos PUROS por día, uno por canal, siempre completos:
    ///   transcripcion-voz.md · transcripcion-sistema.md · transcripcion-pantalla.md
    /// Se reescriben ENTEROS desde el índice tras cada tanda en vez de ir
    /// añadiendo al final: así son idempotentes (nada se duplica), quedan en
    /// orden aunque una tanda procese fragmentos viejos, y borrar uno no pierde
    /// nada — la próxima tanda lo regenera.
    static func reconstruirDiarios(_ dia: Date = Date()) {
        let piezas = ContinuoIndice.shared.materialDelDia(dia, incluirPantalla: true)
        guard !piezas.isEmpty else { return }
        // OJO con la ruta: `carpetaDelDia(dia, "")` seguido de quitar el último
        // componente da la carpeta del MES, no la del día — así se colaron los
        // primeros diarios en 2026/08/. Con un sub real y quitándolo, queda el
        // día de verdad.
        let carpeta = ContinuoAudio.carpetaDelDia(dia, sub: "audio").deletingLastPathComponent()
        let hora = DateFormatter(); hora.dateFormat = "HH:mm:ss"
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"

        var voz: [String] = [], sistema: [String] = [], pantalla: [String] = []
        for pieza in piezas {
            let limpio = pieza.texto.replacingOccurrences(of: "\n", with: " · ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty else { continue }
            let linea = "[\(hora.string(from: pieza.instante))] \(limpio)"
            switch (pieza.material, pieza.fuente) {
            case (.audio, "sistema"): sistema.append(linea)
            case (.audio, "dictado"): voz.append("[\(hora.string(from: pieza.instante))] (dictado) \(limpio)")
            case (.audio, _): voz.append(linea)
            case (.pantalla, _):
                let app = pieza.fuente.isEmpty ? "" : " [\(pieza.fuente)]"
                pantalla.append("[\(hora.string(from: pieza.instante))]\(app) \(limpio)")
            }
        }

        func escribir(_ lineas: [String], canal: String, titulo: String) {
            guard !lineas.isEmpty else { return }
            // La fecha va en el nombre: sin ella, el diario de un día pisaría
            // al del anterior en cuanto la carpeta coincidiera.
            let url = carpeta.appendingPathComponent("transcripcion-\(canal)-\(f.string(from: dia)).md")
            let cuerpo = "# \(titulo) — \(f.string(from: dia))\n\n" + lineas.joined(separator: "\n") + "\n"
            try? cuerpo.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        escribir(voz, canal: "voz", titulo: "Voz (micrófono y dictados)")
        escribir(sistema, canal: "sistema", titulo: "Audio del sistema")
        escribir(pantalla, canal: "pantalla", titulo: "Texto en pantalla (OCR)")
        Log.log(.sistema, "bitácora: diarios reconstruidos — voz \(voz.count), sistema \(sistema.count), pantalla \(pantalla.count) líneas")
    }

    /// Texto de las capturas, en la MISMA pasada que el audio: si ya pagamos el
    /// coste de despertar el equipo para transcribir, leer la pantalla sale
    /// prácticamente gratis.
    /// Con `soloPantalla` (canal "pantalla" a petición) el mensaje habla de
    /// capturas y de OCR, nunca de audio: quien pulsó ese botón no preguntó
    /// por el audio, y «no había audio pendiente» le haría creer que tampoco
    /// hay capturas.
    private static func leerPantallas(prefijo: String, soloPantalla: Bool = false,
                                      diasTocados: inout Set<Date>) -> String {
        guard Config.continuoOcrActivo() else {
            return soloPantalla ? "la lectura del texto en pantalla está desactivada" : prefijo
        }
        let ocr = ContinuoOCR.procesarPendientes(limite: Config.continuoLoteMaximoPorTanda()) {
            dictadoOcupado?() == true
        }
        // Las capturas viejas sufren lo mismo que el audio viejo: su día
        // también hay que regenerarlo, o su texto no llega a ningún diario.
        diasTocados.formUnion(ocr.dias)
        guard ocr.hechas > 0 else {
            return soloPantalla ? "no había capturas pendientes" : prefijo
        }
        let detalle = "\(ocr.hechas) capturas leídas (\(ocr.conTexto) con texto)"
        return soloPantalla ? detalle : prefijo + ", " + detalle
    }

    /// Lanza el resumen del día tras la tanda, si está activado. Separado del
    /// trabajo principal porque es lo único del módulo que puede salir del
    /// equipo: falla sin arrastrar al resto.
    static func resumirDia(_ dia: Date = Date(), alTerminar: ((String) -> Void)? = nil) {
        guard Config.continuoResumenActivo() else {
            alTerminar?("el resumen con IA está desactivado"); return
        }
        ContinuoResumen.generar(dia: dia) { r in
            switch r {
            case .success(let url): alTerminar?("resumen escrito en \(url.lastPathComponent)")
            case .failure(let e): alTerminar?("no pude resumir: \(e.localizedDescription)")
            }
        }
    }

    // MARK: Transcripción

    /// Convierte el fragmento a WAV y lo pasa por el motor elegido. Síncrono a
    /// propósito: la tanda es secuencial y así no hay que orquestar nada.
    private static func transcribir(_ url: URL) -> Result<String, Error> {
        guard let crudo = try? Data(contentsOf: url), !crudo.isEmpty else {
            return .failure(ErrorLote.archivoVacio)
        }
        // Los fragmentos propios son PCM crudo; los adoptados del dictado ya son
        // WAV con cabecera.
        let wav = url.pathExtension == "pcm" ? HistoryWriter.wavData(pcm: crudo) : crudo

        let semaforo = DispatchSemaphore(value: 0)
        var salida: Result<String, Error> = .failure(ErrorLote.sinRespuesta)

        let motor = Config.continuoLoteMotor()
        if motor == "cadena" {
            // La misma cascada que el dictado: respeta los proveedores activos,
            // su orden y su failover. Así, conectar un motor nuevo en Modelos
            // lo pone a disposición de la bitácora sin tocar nada aquí.
            Failover.transcribe(wav: wav) { r in
                salida = r.map { $0.0 }
                semaforo.signal()
            }
        } else if motor == "cadena_local" {
            // La cascada, con su failover, pero SIN salir del equipo.
            //
            // La bitácora graba la jornada entera. Mandarla a un servicio de
            // nube tiene dos costes: el audio de todo un día de trabajo sale de
            // la máquina, y se paga por minuto. Medido el 2026-09-19 con la
            // cascada completa: **764 minutos enviados en un día**, de los que
            // 414 llamadas volvieron sin una sola palabra.
            //
            // Y no hace falta renunciar a nada: medido con el mismo audio y la
            // misma referencia, Nemotron local acierta el 100 % —igual que el
            // mejor de nube— en 5,6 s y sin coste.
            let locales = Providers.cadena().filter { $0.tipo == "local" }
            if locales.isEmpty {
                // Sin ningún motor local activo, esto no puede cumplir su
                // promesa. Se dice y se usa Apple, que va en el sistema.
                Log.log(.ia, "bitácora: no hay motores locales activos — uso Apple Speech, que no sale del equipo")
                AppleSpeechSTT.run(wav: CuerpoMultipart.Origen.datos(wav)) { r in salida = r; semaforo.signal() }
            } else {
                Failover.transcribe(wav: .datos(wav), cadena: locales) { r in
                    salida = r.map { $0.0 }
                    semaforo.signal()
                }
            }
        } else if motor == "apple_speech" {
            AppleSpeechSTT.run(wav: CuerpoMultipart.Origen.datos(wav)) { r in salida = r; semaforo.signal() }
        } else if motor == "whisper_local" {
            WhisperServer.transcribe(wav: wav) { r in salida = r; semaforo.signal() }
        } else {
            // Cualquier otro id del catálogo: se fija ese proveedor como cadena
            // de uno solo, para no perder su configuración de modelo y clave.
            let uno = Providers.cadena().filter { $0.id == motor }
            if uno.isEmpty {
                Failover.transcribe(wav: wav) { r in salida = r.map { $0.0 }; semaforo.signal() }
            } else {
                Failover.transcribe(wav: wav, cadena: uno) { r in
                    salida = r.map { $0.0 }
                    semaforo.signal()
                }
            }
        }

        // Tope generoso: un fragmento de dos minutos en local puede tardar.
        if semaforo.wait(timeout: .now() + 300) == .timedOut {
            return .failure(ErrorLote.tiempoAgotado)
        }
        // El diccionario propio de la app —reemplazos, siglas y corrección por
        // sonido— se aplica igual que en el dictado. Aquí importa más todavía:
        // nadie está mirando el texto en el momento para corregirlo a mano.
        if Config.continuoDiccionarioAudio() {
            return salida.map { applyReplacements($0) }
        }
        return salida
    }

    /// Deja el texto junto al audio, para poder leerlo sin la app.
    /// SOLO dentro de la carpeta de la bitácora: un archivo adoptado del
    /// historial de dictado tiene ya su .txt (pulido) y pisarlo con texto
    /// crudo destruiría trabajo del usuario.
    /// Papelera PROPIA de la aplicación, no la del sistema.
    ///
    /// La del sistema tendría dos problemas: se llenaría de cientos de trozos
    /// de ruido mezclados con lo que el usuario tira a mano, y vaciarla sería
    /// cosa suya. Esta se limpia sola.
    ///
    /// Un archivo retirado aquí se puede recuperar durante unos días —el plazo
    /// lo fija `bitacoraPapeleraDias`— y después se borra de verdad. Nunca se
    /// borra nada al momento: entre «esto es ruido» y «esto ya no existe» hay
    /// una semana para desdecirse.
    static var papeleraInterna: URL {
        Config.dir.appendingPathComponent("papelera-bitacora", isDirectory: true)
    }

    private static func aPapelera(_ ruta: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ruta.path) else { return }
        do {
            try fm.createDirectory(at: papeleraInterna, withIntermediateDirectories: true)
            // El nombre lleva el día: así la purga sabe qué caducó sin tener que
            // fiarse de las fechas del sistema de archivos, que una copia o una
            // restauración pueden reescribir.
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
            var destino = papeleraInterna.appendingPathComponent("\(f.string(from: Date()))-\(ruta.lastPathComponent)")
            var n = 2
            while fm.fileExists(atPath: destino.path) {
                destino = papeleraInterna.appendingPathComponent("\(f.string(from: Date()))-\(n)-\(ruta.lastPathComponent)")
                n += 1
            }
            try fm.moveItem(at: ruta, to: destino)
        } catch {
            // Si no se puede mover, NO se fuerza el borrado: se deja el archivo
            // y se dice. Ahorrar disco no vale perder audio.
            Log.log(.ia, "bitácora: no pude retirar \(ruta.lastPathComponent) (\(error.localizedDescription)) — lo dejo donde está")
        }
    }

    /// Vacía de la papelera interna lo que pasó de plazo. Se llama al empezar
    /// cada tanda: no hace falta un temporizador propio para algo que solo tiene
    /// que ocurrir de vez en cuando.
    static func purgarPapelera() {
        let dias = Config.bitacoraPapeleraDias()
        guard dias > 0 else { return }               // 0 = guardar para siempre
        let fm = FileManager.default
        guard let hijos = try? fm.contentsOfDirectory(at: papeleraInterna,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limite = Date().addingTimeInterval(-Double(dias) * 86_400)
        var borrados = 0, bytes: Int64 = 0
        for h in hijos {
            let fecha = (try? h.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let fecha, fecha < limite else { continue }
            let tam = ((try? fm.attributesOfItem(atPath: h.path))?[.size] as? NSNumber)?.int64Value ?? 0
            if (try? fm.removeItem(at: h)) != nil { borrados += 1; bytes += tam }
        }
        if borrados > 0 {
            Log.log(.sistema, "bitácora: la papelera soltó \(borrados) trozos de ruido de más de \(dias) días (\(bytes / 1_048_576) MB)")
        }
    }

    private static func guardarTexto(_ texto: String, junto url: URL) {
        guard url.path.hasPrefix(Config.continuoCarpeta().path) else { return }
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let destino = url.deletingPathExtension().appendingPathExtension("txt")
        try? texto.write(to: destino, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
    }

    // MARK: Compresión

    /// PCM crudo a m4a, ahora que el fragmento ya está transcrito y cerrado.
    /// Devuelve los bytes ahorrados, o nil si no se pudo y se conserva el crudo.
    /// Interno (no privado) para que la prueba de robustez lo ejercite de
    /// punta a punta con un PCM sintético; con `id` ≤ 0 no toca el índice.
    static func comprimir(_ pcm: URL, id: Int64) -> Int64? {
        guard let crudo = try? Data(contentsOf: pcm), crudo.count > 1_024 else { return nil }
        let destino = pcm.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: destino)
        let marcos = Int64(crudo.count / 2)

        do {
            // La escritura vive en SU función: el AVAudioFile de escritura se
            // libera al salir de ella y solo entonces el contenedor MPEG-4 queda
            // finalizado. Validarlo con el escritor todavía vivo (bastaba una
            // segunda referencia en este mismo ámbito) hacía que la lectura
            // fallara siempre, se borrara un m4a perfectamente bueno y se
            // conservara el crudo: dos semanas así dejaron 17 GB de PCM.
            try escribirM4A(crudo, marcos: AVAudioFrameCount(marcos), en: destino)
        } catch {
            Log.log(.sistema, "bitácora: no pude comprimir \(pcm.lastPathComponent) — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: destino)
            return nil
        }

        let escrito = ((try? FileManager.default.attributesOfItem(atPath: destino.path))?[.size] as? Int64) ?? 0
        guard escrito > 1_024 else {
            try? FileManager.default.removeItem(at: destino)
            return nil
        }
        // El tamaño no basta: el contenedor tiene que ABRIR y traer (casi) los
        // mismos marcos que el crudo — AVAudioFile descuenta el priming del AAC,
        // así que más de medio segundo de diferencia es un archivo truncado.
        // Borrar el crudo contra un m4a corrupto es perder la grabación.
        let minimo = max(1, marcos - 8_000)
        guard let comprobacion = try? AVAudioFile(forReading: destino),
              comprobacion.length >= minimo else {
            let leidos = (try? AVAudioFile(forReading: destino))?.length ?? -1
            try? FileManager.default.removeItem(at: destino)
            Log.log(.sistema, "bitácora: el m4a de \(pcm.lastPathComponent) no valida (\(leidos) marcos de \(marcos)) — conservo el crudo")
            return nil
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
        let antes = Int64(crudo.count)
        // Sin índice actualizado no hay intercambio: quedarían un m4a huérfano
        // (que el rescate volvería a transcribir) y una fila apuntando a un
        // crudo borrado. Se deshace y se reintenta en otra pasada.
        if id > 0, !ContinuoIndice.shared.reemplazarRuta(id: id, material: .audio, por: destino, bytes: escrito) {
            try? FileManager.default.removeItem(at: destino)
            Log.log(.sistema, "bitácora: el índice no aceptó el m4a de \(pcm.lastPathComponent) — conservo el crudo")
            return nil
        }
        try? FileManager.default.removeItem(at: pcm)
        // El .txt conserva el mismo nombre base que el audio, así que no
        // hay que moverlo: sigue emparejado con el .m4a.
        return antes - escrito
    }

    /// Escribe el AAC y, al salir, suelta el escritor: ahí se cierra el
    /// contenedor. Nada de fuera debe conservar una referencia a `salida`.
    private static func escribirM4A(_ crudo: Data, marcos: AVAudioFrameCount, en destino: URL) throws {
        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24_000
        ]
        let salida = try AVAudioFile(forWriting: destino, settings: ajustes)
        // El buffer DEBE ir en el processingFormat del archivo (Float32), no
        // en Int16: `write(from:)` lanza si el formato no coincide, y ese
        // fallo dejaba antes un contenedor de 28 bytes.
        let formato = salida.processingFormat
        guard marcos > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: marcos),
              let destinoCanal = buffer.floatChannelData else {
            throw ErrorLote.bufferInvalido
        }
        buffer.frameLength = marcos
        crudo.withUnsafeBytes { bytes in
            guard let origen = bytes.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<Int(marcos) {
                destinoCanal[0][i] = Float(origen[i]) / 32768.0
            }
        }
        try salida.write(from: buffer)
    }

    // MARK: Recompresión de crudos pendientes

    /// Archivos que no se pudieron comprimir en esta sesión: se apartan para
    /// que un PCM dañado no bloquee la cola eternamente.
    private static var recompresionFallidos: Set<Int64> = []
    private static var recompresionReloj: Timer?

    /// Comprime el PCM que quedó crudo estando ya transcrito (por ejemplo, tras
    /// una temporada en que la compresión fallaba). Va por la misma cola que la
    /// tanda, de a `tope` archivos por pasada, y se detiene si empieza un
    /// dictado. Parametrizable: Config.continuoRecomprimirPendientes; respeta
    /// «solo con el equipo enchufado» y el interruptor de compresión.
    static func recomprimirPendientes(tope: Int = 1_500, manual: Bool = false,
                                      alTerminar: ((String) -> Void)? = nil) {
        guard Config.continuoActivo(), Config.continuoLoteComprimir() else {
            alTerminar?("la compresión está desactivada"); return
        }
        guard manual || Config.continuoRecomprimirPendientes() else {
            alTerminar?("la recompresión automática está desactivada"); return
        }
        if !manual, Config.continuoLoteSoloConCorriente(), !EnergiaMac.conCorriente() {
            alTerminar?("recompresión pospuesta: el equipo está con batería"); return
        }
        candado.lock()
        if enMarcha {
            candado.unlock()
            alTerminar?("hay una tanda en curso"); return
        }
        enMarcha = true
        candado.unlock()

        cola.async {
            defer { candado.lock(); enMarcha = false; candado.unlock() }
            ContinuoIndice.shared.abrir()
            let carpeta = Config.continuoCarpeta()
            let candidatos = ContinuoIndice.shared.audiosCrudosProcesados(
                limite: tope + recompresionFallidos.count, carpeta: carpeta)
                .filter { !recompresionFallidos.contains($0.id) }
                .prefix(tope)
            guard !candidatos.isEmpty else {
                DispatchQueue.main.async { alTerminar?("no hay audio crudo pendiente de comprimir") }
                return
            }
            var hechos = 0, fallos = 0, cortado = false
            var ahorro: Int64 = 0
            let inicio = Date()
            for c in candidatos {
                if dictadoOcupado?() == true { cortado = true; break }
                guard FileManager.default.fileExists(atPath: c.ruta.path) else {
                    recompresionFallidos.insert(c.id); continue
                }
                if let a = comprimir(c.ruta, id: c.id) {
                    hechos += 1; ahorro += a
                } else {
                    fallos += 1; recompresionFallidos.insert(c.id)
                }
                // Respiro entre archivos: que el disco y la CPU sigan siendo
                // de quien está usando el equipo.
                Thread.sleep(forTimeInterval: 0.02)
            }
            var partes = ["recompresión: \(hechos) archivos, \(ContinuoBitacora.tamanoLegible(ahorro)) liberados en \(Int(Date().timeIntervalSince(inicio))) s"]
            if fallos > 0 { partes.append("\(fallos) sin comprimir (se apartan)") }
            if cortado { partes.append("detenida al empezar un dictado") }
            else if candidatos.count == tope { partes.append("quedan más; sigue en la próxima pasada") }
            let resumen = partes.joined(separator: ", ")
            Log.log(.sistema, "bitácora: \(resumen)")
            DispatchQueue.main.async {
                alTerminar?(resumen)
                // Con cola pendiente no hay por qué esperar al próximo cuarto de
                // hora: otra pasada al minuto (solo automática y con reloj vivo).
                if !manual, !cortado, candidatos.count == tope, recompresionReloj != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { recomprimirPendientes() }
                }
            }
        }
    }

    /// Pasada automática: una al minuto de encender la bitácora, luego cada
    /// 15 min y, mientras quede cola, una por minuto. Cero coste sin crudo.
    static func programarRecompresion() {
        DispatchQueue.main.async {
            recompresionReloj?.invalidate()
            recompresionReloj = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
                recomprimirPendientes()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { recomprimirPendientes() }
        }
    }

    static func detenerRecompresion() {
        DispatchQueue.main.async {
            recompresionReloj?.invalidate()
            recompresionReloj = nil
        }
    }

    enum ErrorLote: LocalizedError {
        case archivoVacio, sinRespuesta, tiempoAgotado, bufferInvalido
        var errorDescription: String? {
            switch self {
            case .archivoVacio: return "el fragmento está vacío"
            case .sinRespuesta: return "el motor no respondió"
            case .tiempoAgotado: return "se agotó el tiempo de transcripción"
            case .bufferInvalido: return "no pude preparar el buffer de audio"
            }
        }
    }
}
