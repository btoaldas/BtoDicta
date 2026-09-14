import Foundation

// MARK: - Que nunca falte texto, sin rehacer trabajo ya hecho
//
// Los motores de transcripción EN VIVO no garantizan el texto completo en
// dictados largos. Medido sobre un dictado real de 915 s (Voxtral Realtime
// por bto-stream, 2026-09-12), reproducido tres veces:
//
//   · a los ~756 s el motor elidió 27 palabras y dejó "..." en su lugar;
//   · a los ~890 s dejó de emitir: el decodificador da su token de fin y ya
//     no vuelve a dar un paso (`while (!cc->stream_eos …)`), así que las
//     últimas 50 palabras no salieron nunca;
//   · alimentarle 30 s de silencio extra no lo reanimó (dos actualizaciones
//     más, cero palabras nuevas);
//   · el MISMO motor con el MISMO modelo, sobre recortes de ese audio (70 s,
//     600 s y 740 s), devolvió el texto completo y sin "...".
//
// El fallo depende del estado acumulado del stream, no del audio. Pero
// re-transcribir cada dictado por si acaso sería pagar dos veces el mismo
// trabajo: el 99 % de los dictados salen bien. Así que aquí no hay IA ni
// verificación a ciegas, sino señales DETERMINISTAS de que el motor se
// quedó corto, y reparación SOLO del tramo afectado.
enum RedSeguridadDictado {

    /// Bytes por segundo del PCM con el que trabaja la app: 16 kHz, mono,
    /// 16 bits. NO es la frecuencia del micrófono —esa la pone cada equipo y
    /// puede ser 44 100, 48 000 o 96 000 Hz— sino la de salida del conversor,
    /// que es igual en todas partes. Las cuentas de tiempo van por aquí.
    static let bytesPorSegundo = Int(Recorder.frecuenciaInterna) * 2

    /// Por qué se sospecha que falta texto. Sin motivo no se hace nada.
    enum Motivo: String {
        case congelado  = "el motor dejó de emitir mientras seguías hablando"
        case cortado    = "el texto termina a mitad de frase con voz al final"
        case vacio      = "el motor no devolvió texto"
    }

    // MARK: Detección

    /// ¿El texto termina como termina una frase? Un final en "...", en coma o
    /// en una palabra suelta significa que el motor se quedó a medias.
    static func finalIncompleto(_ texto: String) -> Bool {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ultimo = t.last else { return true }
        if t.hasSuffix("...") || t.hasSuffix("…") { return true }
        return !".!?\"')]»".contains(ultimo)
    }

    /// Decide si hay que reparar. `vozAlFinal` es el dato que lo cambia todo:
    /// un texto sin punto final tras un silencio es normal (el usuario cortó);
    /// el mismo texto con voz sonando en el último segundo significa que el
    /// motor se quedó atrás.
    static func motivo(texto: String, congelado: Bool, vozAlFinal: Bool) -> Motivo? {
        if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .vacio }
        if congelado { return .congelado }
        if vozAlFinal && finalIncompleto(texto) { return .cortado }
        return nil
    }

    /// Redondea a frontera de muestra (16 bits = 2 bytes). Cortar el PCM en
    /// un byte impar desplaza medio valor cada muestra y el audio se vuelve
    /// ruido: el motor devuelve casi nada y parecería que no hay qué recuperar.
    static func par(_ n: Int) -> Int { n - (n % 2) }

    static func palabras(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Un punto del dictado donde falta texto. Un mismo dictado puede tener
    /// VARIOS: el motor puede colgarse más de una vez y, entre medias, saltarse
    /// tramos dejando puntos suspensivos. Se reparan todos, uno por uno.
    struct Hueco {
        /// Posición aproximada en el PCM donde está el audio no transcrito.
        let byte: Int
        /// Dónde cortar el texto para coser lo recuperado (índice de carácter).
        let corteTexto: Int?
        let origen: Origen
        enum Origen: String { case congelacion = "el motor se colgó", elision = "el motor se saltó texto" }
    }

    /// Los puntos suspensivos que el motor deja al saltarse contenido. Se
    /// ignora el del final (esa es la cola, que tiene su propia reparación) y
    /// la posición en el audio se estima por la proporción del texto, que es
    /// suficiente: la ventana que se transcribe va holgada y el cosido se hace
    /// por coincidencia de palabras, no por tiempo.
    static func elisionesInternas(_ texto: String, pcmBytes: Int) -> [Hueco] {
        let total = texto.count
        guard total > 200, pcmBytes > 0 else { return [] }
        var out: [Hueco] = []
        // Un motor marca lo que se saltó con tres puntos y otro con el carácter
        // único «…». Se buscan los dos: mirar solo uno deja la mitad de los
        // huecos sin ver, según qué motor esté transcribiendo.
        for marca in ["...", "…"] {
            var desde = texto.startIndex
            while let r = texto.range(of: marca, range: desde..<texto.endIndex) {
                desde = r.upperBound
                let off = texto.distance(from: texto.startIndex, to: r.lowerBound)
                // El del final no cuenta como elisión interna.
                guard total - off > 40 else { continue }
                let byte = Int(Double(off) / Double(total) * Double(pcmBytes))
                out.append(Hueco(byte: byte, corteTexto: off, origen: .elision))
            }
        }
        return out
    }

    // MARK: Reparación quirúrgica

    /// Transcribe SOLO el tramo de audio que quedó sin texto y lo pega al que
    /// ya existe. No se rehace lo que ya estaba bien: ni el audio anterior ni
    /// el pulido, que corre una sola vez sobre el texto unido.
    ///
    /// `desdeByte` es la posición del PCM en la que el texto creció por última
    /// vez; se retrocede un solape para no cortar una palabra por la mitad y
    /// la unión elimina la repetición.
    static func repararCola(vivo: String, pcm: Data, desdeByte: Int, motivo: Motivo,
                            completion: @escaping (String, String?) -> Void) {
        let solapeBytes = bytesPorSegundo * 3            // 3 s a 16 kHz mono int16
        let inicio = par(max(0, min(desdeByte - solapeBytes, pcm.count)))
        let faltante = pcm.count - inicio
        guard Config.redSeguridadDictado() else { completion(vivo, nil); return }
        guard faltante > bytesPorSegundo else {          // menos de 1 s: nada que ganar
            completion(vivo, nil); return
        }
        guard let motor = motorLotes() else {
            Log.log(.ia, "dictado: \(motivo.rawValue), pero no hay motor local por lotes para recuperarlo")
            completion(vivo, nil); return
        }
        let segundos = Double(faltante) / Double(bytesPorSegundo)
        Log.log(.ia, "dictado: \(motivo.rawValue) — recupero los últimos \(Int(segundos)) s con \(motor.nombre) (el resto NO se re-transcribe)")
        let t0 = Date()
        var respondido = false
        let responder: (String, String?) -> Void = { texto, via in
            guard !respondido else { return }
            respondido = true
            completion(texto, via)
        }
        // Tope proporcional al tramo, no al dictado: reparar 30 s no puede
        // costar lo que costaría rehacer 15 minutos.
        let tope = min(Double(Config.redSeguridadTopeSegundos()), max(20, segundos * 2))
        DispatchQueue.main.asyncAfter(deadline: .now() + tope) {
            if !respondido { Log.log(.ia, "dictado: la recuperación tardó más de \(Int(tope)) s — entrego lo que hay") }
            responder(vivo, nil)
        }
        let wavTramo = HistoryWriter.wavData(pcm: pcm.subdata(in: inicio..<pcm.count))
        TranscribeCpp.run(wav: wavTramo, modelo: motor.modelo) { r in
            DispatchQueue.main.async {
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                switch r {
                case .failure(let e):
                    Log.log(.ia, "dictado: no pude recuperar la cola (\(e.localizedDescription))")
                    responder(vivo, nil)
                case .success(let cola):
                    let unido = unir(vivo, cola)
                    let ganadas = palabras(unido) - palabras(vivo)
                    if ganadas > 0 {
                        Log.log(.ia, "dictado: recuperadas \(ganadas) palabras con \(motor.nombre) en \(ms)ms")
                        responder(unido, "+\(motor.nombre)")
                    } else {
                        Log.log(.ia, "dictado: la cola no aportó texto nuevo (\(ms)ms) — el original estaba completo")
                        responder(vivo, nil)
                    }
                }
            }
        }
    }

    /// Repara, uno por uno, todos los huecos detectados y por último la cola.
    /// Cada hueco cuesta una ventana corta de audio (no el dictado entero) y
    /// nunca puede empeorar el texto: si la ventana no encaja, se deja como
    /// estaba. El pulido llega después, una sola vez, sobre el texto ya unido.
    /// `tope` solo lo usa la prueba propia, para no tener que tocar la
    /// configuración real del equipo; en uso normal manda el valor de Config.
    static func repararTodo(vivo: String, pcm: Data, huecos: [Hueco], colaDesdeByte: Int?,
                            tope: Double? = nil,
                            completion: @escaping (String, String?) -> Void) {
        guard Config.redSeguridadDictado(), let motor = motorLotes() else {
            completion(vivo, nil); return
        }
        // De atrás hacia delante: así los índices de carácter de los huecos
        // anteriores siguen siendo válidos aunque el texto crezca.
        let lista = huecos.sorted { $0.byte > $1.byte }
        let palabrasAntes = palabras(vivo)
        var texto = vivo
        var reparados = 0
        let inicioTodo = Date()

        // El dictado SE ENTREGA SIEMPRE, pase lo que pase con la reparación.
        // Quien nos llamó ya dio por respondido al motor en vivo y desarmó su
        // propio tope: si esta cadena no llamara a `completion`, el texto no
        // llegaría nunca y el panel se quedaría en «Recuperando lo que falta».
        var entregado = false
        func entregar(_ t: String, _ via: String?) {
            guard !entregado else { return }
            entregado = true
            completion(t, via)
        }

        func terminar() {
            let ganadas = palabras(texto) - palabrasAntes
            if reparados == 0 || ganadas <= 0 {
                Log.log(.ia, "dictado: nada que recuperar — el texto ya estaba completo")
                entregar(vivo, nil); return
            }
            let ms = Int(Date().timeIntervalSince(inicioTodo) * 1000)
            Log.log(.ia, "dictado: \(reparados) \(reparados == 1 ? "tramo recuperado" : "tramos recuperados") con \(motor.nombre), +\(ganadas) palabras en \(ms)ms")
            entregar(texto, "+\(motor.nombre)")
        }

        // Tope de toda la reparación, no de cada tramo. Aunque el motor por
        // lotes se cuelgue y su propio perro guardián tarde en morderle, aquí
        // se entrega lo que haya: más vale el dictado con un hueco que ningún
        // dictado. Lo recuperado hasta ese instante SÍ va incluido.
        let topeTotal = tope ?? Double(Config.redSeguridadTopeSegundos())
        DispatchQueue.main.asyncAfter(deadline: .now() + topeTotal) {
            guard !entregado else { return }
            Log.log(.ia, "dictado: la recuperación pasó de \(Int(topeTotal)) s — entrego lo que hay")
            let ganadas = palabras(texto) - palabrasAntes
            entregar(ganadas > 0 ? texto : vivo, ganadas > 0 ? "+\(motor.nombre)" : nil)
        }

        func siguienteHueco(_ i: Int) {
            guard !entregado else { return }          // el tope ya entregó
            guard i < lista.count else {
                // Al final, la cola: el tramo desde el último texto conocido
                // hasta el final del audio.
                guard let desde = colaDesdeByte, pcm.count - desde > bytesPorSegundo else { terminar(); return }
                repararCola(vivo: texto, pcm: pcm, desdeByte: desde, motivo: .congelado) { t2, via in
                    if via != nil, palabras(t2) > palabras(texto) { texto = t2; reparados += 1 }
                    terminar()
                }
                return
            }
            let h = lista[i]
            // Sin punto de corte en el TEXTO no hay dónde coser lo que se
            // recupere, así que transcribir la ventana sería pagar 90 s de
            // motor para tirar el resultado. Se comprueba ANTES de gastar nada,
            // no después: ese era el orden y costaba una transcripción entera
            // por cada congelación detectada, sin recuperar una sola palabra.
            guard let corte = h.corteTexto else {
                Log.debug("dictado: el tramo del segundo \(h.byte / bytesPorSegundo) no trae punto de corte — no gasto motor en él")
                siguienteHueco(i + 1); return
            }
            let media = 45 * bytesPorSegundo                                   // ±45 s alrededor
            // SIEMPRE en frontera de muestra: el PCM es de 16 bits, así que
            // empezar en un byte impar parte cada muestra por la mitad y el
            // audio llega como ruido — medido, 9 palabras en 90 s en vez de 250.
            let a = par(max(0, h.byte - media)), b = par(min(pcm.count, h.byte + media))
            guard b - a > bytesPorSegundo else { siguienteHueco(i + 1); return }
            Log.log(.ia, "dictado: \(h.origen.rawValue) hacia el segundo \(h.byte / bytesPorSegundo) — reviso ese tramo")
            let wavV = HistoryWriter.wavData(pcm: pcm.subdata(in: a..<b))
            TranscribeCpp.run(wav: wavV, modelo: motor.modelo) { r in
                DispatchQueue.main.async {
                    guard !entregado else { return }
                    switch r {
                    case .failure(let e):
                        Log.log(.ia, "dictado: no pude leer ese tramo (\(e.localizedDescription))")
                    case .success(let ventana):
                        Log.debug("dictado: tramo del segundo \(h.byte / bytesPorSegundo) → \(palabras(ventana)) palabras de referencia")
                        if let cosido = coser(texto: texto, ventana: ventana, cerca: corte) {
                            if palabras(cosido) > palabras(texto) {
                                Log.log(.ia, "dictado: cosido el tramo del segundo \(h.byte / bytesPorSegundo) (+\(palabras(cosido) - palabras(texto)) palabras)")
                                texto = cosido
                                reparados += 1
                            } else {
                                Log.debug("dictado: el tramo del segundo \(h.byte / bytesPorSegundo) no aportaba texto nuevo")
                            }
                        } else {
                            Log.log(.ia, "dictado: no encontré dónde coser el tramo del segundo \(h.byte / bytesPorSegundo) — lo dejo como está")
                        }
                    }
                    siguienteHueco(i + 1)
                }
            }
        }
        siguienteHueco(0)
    }

    /// Cose el texto de una ventana recuperada DENTRO del texto, en el punto
    /// donde el motor se saltó contenido. Busca las palabras de alrededor del
    /// corte dentro de la ventana y sustituye solo ese tramo. Si no encuentra
    /// ambos anclajes, devuelve nil: preferimos no tocar nada antes que
    /// inventar una costura.
    static func coser(texto: String, ventana: String, cerca corte: Int) -> String? {
        func norm(_ s: Substring) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let idx = texto.index(texto.startIndex, offsetBy: min(corte, texto.count))
        var izquierda = String(texto[texto.startIndex..<idx])
        // El "..." del corte no sobrevive: lo recuperado ocupa su lugar.
        while izquierda.hasSuffix(".") || izquierda.hasSuffix("…") || izquierda.hasSuffix(" ") {
            izquierda.removeLast()
        }
        let derecha = String(texto[idx...]).trimmingCharacters(in: CharacterSet(charactersIn: ". …"))
        let pIzq = izquierda.split(whereSeparator: { $0.isWhitespace })
        let pDer = derecha.split(whereSeparator: { $0.isWhitespace })
        let pVen = ventana.split(whereSeparator: { $0.isWhitespace })
        guard pIzq.count >= 4, pDer.count >= 4, pVen.count >= 8 else { return nil }
        let vn = pVen.map(norm)

        // Los dos textos vienen de MOTORES DISTINTOS: uno escribe «prototipo»
        // y el otro «prototipos», uno pone coma donde el otro pone punto. Por
        // eso el anclaje no exige igualdad palabra por palabra, sino parecido:
        // se acepta la posición que más coincide, siempre que pase del 60 %.
        func parecidas(_ a: String, _ b: String) -> Bool {
            if a == b { return true }
            let m = min(a.count, b.count)
            guard m >= 4 else { return false }
            // Misma raíz: cubre plurales, género y terminaciones verbales.
            return a.prefix(m - 1) == b.prefix(m - 1)
        }
        /// Mejor posición de la ventana para un patrón, con su puntuación.
        func buscar(_ patron: [String], desde: Int, ultima: Bool) -> (idx: Int, score: Double)? {
            guard !patron.isEmpty, patron.count <= vn.count, desde < vn.count else { return nil }
            var mejorIdx = -1
            var mejorScore = 0.0
            var i = desde
            while i + patron.count <= vn.count {
                var aciertos = 0
                for (j, w) in patron.enumerated() where parecidas(vn[i + j], w) { aciertos += 1 }
                let s = Double(aciertos) / Double(patron.count)
                if s > mejorScore || (ultima && s == mejorScore && s >= 0.6) {
                    mejorScore = s; mejorIdx = i
                }
                i += 1
            }
            guard mejorIdx >= 0, mejorScore >= 0.6 else { return nil }
            return (mejorIdx, mejorScore)
        }
        // Ancla izquierda: las últimas palabras antes del corte.
        var finIzq: Int?
        for k in stride(from: min(8, pIzq.count), through: 4, by: -1) {
            let pat = pIzq.suffix(k).map(norm)
            if let p = buscar(pat, desde: 0, ultima: true) { finIzq = p.idx + k; break }
        }
        guard let fi = finIzq, fi < vn.count else { return nil }
        // Ancla derecha: las primeras palabras tras el corte, buscadas DESPUÉS.
        var iniDer: Int?
        for k in stride(from: min(8, pDer.count), through: 4, by: -1) {
            let pat = pDer.prefix(k).map(norm)
            if let p = buscar(pat, desde: fi, ultima: false) { iniDer = p.idx; break }
        }
        guard let id = iniDer, id > fi else { return nil }
        let medio = pVen[fi..<id].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !medio.isEmpty else { return nil }
        return izquierda + " " + medio + " " + derecha
    }

    /// Une el texto en vivo con el tramo recuperado quitando la repetición del
    /// solape: busca la coincidencia más larga entre el final del primero y el
    /// principio del segundo, comparando palabras normalizadas.
    static func unir(_ prefijo: String, _ cola: String) -> String {
        let a = prefijo.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = cola.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return b }
        guard !b.isEmpty else { return a }
        func norm(_ s: Substring) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                .filter { $0.isLetter || $0.isNumber }
        }
        let pa = a.split(whereSeparator: { $0.isWhitespace }).map(norm)
        let pb = b.split(whereSeparator: { $0.isWhitespace })
        let pbn = pb.map(norm)
        let maxSolape = min(60, min(pa.count, pbn.count))
        var mejor = 0
        if maxSolape >= 3 {
            for k in stride(from: maxSolape, through: 3, by: -1) {
                if Array(pa.suffix(k)) == Array(pbn.prefix(k)) { mejor = k; break }
            }
        }
        // Los puntos suspensivos con que el motor marca lo que se saltó no
        // pueden sobrevivir a la reparación: el texto recuperado ocupa su
        // lugar. Se quitan SIEMPRE del final del prefijo, haya solape o no.
        var base = a
        while base.hasSuffix(".") || base.hasSuffix("…") || base.hasSuffix(" ") {
            if base.hasSuffix("...") { base.removeLast(3) }
            else if base.hasSuffix("…") { base.removeLast() }
            else if base.hasSuffix(" ") { base.removeLast() }
            else { break }
            base = base.trimmingCharacters(in: .whitespaces)
        }
        if base.isEmpty { base = a }
        let resto = pb.dropFirst(mejor).joined(separator: " ")
        if resto.isEmpty { return base }
        return base.isEmpty ? resto : base + " " + resto
    }

    // MARK: Motor de repuesto

    /// Motor por lotes para la recuperación: whisper local (rápido, sin estado
    /// de streaming) si está descargado; si no, cualquier modelo local que no
    /// sea el de streaming que falló. Nunca la nube: reparar no puede costar
    /// dinero ni depender de la red.
    static func motorLotes() -> (id: String, modelo: String, nombre: String)? {
        let locales = Providers.cadena().filter { $0.tipo == "local" }
        if let w = locales.first(where: { $0.id == "whisper_local" }),
           let m = Providers.modelo(de: w.id), TranscribeCpp.descargado(m) {
            return (w.id, m, "Whisper")
        }
        for p in locales {
            guard let m = Providers.modelo(de: p.id), TranscribeCpp.descargado(m),
                  !TcppStreamClient.esModeloStreaming(m) else { continue }
            return (p.id, m, nombreDe(p.id))
        }
        if let w = (try? FileManager.default.contentsOfDirectory(atPath: TranscribeCpp.modelsDir.path))?
            .filter({ $0.hasSuffix(".bin") && ($0.contains("whisper") || $0.hasPrefix("ggml-")) })
            .sorted().last {
            return ("whisper_local", w, "Whisper")
        }
        if let p = locales.first, let m = Providers.modelo(de: p.id), TranscribeCpp.descargado(m) {
            return (p.id, m, nombreDe(p.id))
        }
        return nil
    }

    private static func nombreDe(_ id: String) -> String {
        switch id {
        case "whisper_local": return "Whisper"
        case "voxtral_local": return "Voxtral"
        case "nemotron_local": return "Nemotron"
        case "canary_local": return "Canary"
        default: return id
        }
    }
}
