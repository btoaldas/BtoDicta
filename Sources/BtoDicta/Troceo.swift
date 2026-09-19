import Foundation

// MARK: - Partir lo que no cupo, sin saber de antemano cuánto cabe
//
// Todo motor de transcripción tiene un techo —de tamaño, de duración o de
// ambos— y ninguno lo anuncia igual. Fish rechaza por encima de unos 25 MB con
// un «format not recognised» que ni siquiera menciona el tamaño; otros
// devuelven 413, otros 400, otros simplemente se cuelgan. Codificar el límite
// de cada uno sería una lista que envejece mal y que falla con el proveedor que
// aún no conocemos.
//
// Así que aquí no hay lista. Se manda entero, y si el motor lo rechaza de una
// forma que PUEDE ser de tamaño, se parte en dos y se vuelve a intentar con el
// MISMO motor; si una mitad también falla, esa mitad se parte otra vez. El
// límite se descubre rompiéndose contra él, que es la única manera de saberlo
// para un proveedor cualquiera.
//
// Y se aprende: lo más grande que tragó y lo más pequeño que rechazó quedan
// anotados, así que la próxima vez se parte de entrada y no se paga el primer
// rechazo. La medida se guarda por motor y sobrevive al reinicio.
//
// Los tramos llevan SOLAPE y se unen con el mismo cosido por coincidencia de
// palabras que ya rescata los dictados rotos, así que en la costura no se
// pierde ni se repite una palabra.
enum Troceo {

    /// Solape entre tramos. Cinco segundos bastan para que la palabra partida
    /// por el corte aparezca entera en uno de los dos lados.
    static let solapeSegundos = 5

    /// Por debajo de esto no se parte: si un motor rechaza medio minuto de
    /// audio, el problema no es el tamaño y partirlo solo multiplica el fallo.
    static let minimoParaPartir = 90 * RedSeguridadDictado.bytesPorSegundo   // 90 s

    // MARK: Lo aprendido

    private static var archivo: URL { Config.dir.appendingPathComponent("limites-motores.json") }
    private static let candado = NSLock()
    private static var cache: [String: [String: Int]]?

    private static func tabla() -> [String: [String: Int]] {
        candado.lock(); defer { candado.unlock() }
        if let c = cache { return c }
        let d = (try? Data(contentsOf: archivo)) ?? Data()
        let t = (try? JSONSerialization.jsonObject(with: d)) as? [String: [String: Int]] ?? [:]
        cache = t
        return t
    }

    private static func guardar(_ t: [String: [String: Int]]) {
        candado.lock(); cache = t; candado.unlock()
        guard let d = try? JSONSerialization.data(withJSONObject: t, options: [.prettyPrinted]) else { return }
        Config.asegurarDirSeguro()
        try? d.write(to: archivo, options: .atomic)
    }

    /// El motor tragó `bytes`: sube el listón de lo que se sabe que cabe.
    ///
    /// Y si tragó algo que supuestamente rechazaba, la medida anterior era
    /// mentira —vino de una caída de red, de un mal momento del servidor o de
    /// un cupo que ya cambió— y se tira entera. Esta es la vía por la que el
    /// sistema se desdice solo, sin que nadie tenga que borrar nada.
    static func anotarExito(_ id: String, bytes: Int) {
        var t = tabla()
        var e = t[id] ?? [:]
        if let rechaza = e["rechaza"], bytes >= rechaza {
            olvidar(id, porque: "entró \(bytes / 1024) kB, más de lo que supuestamente no admitía")
            var nuevo = tabla(); nuevo[id] = ["cabe": bytes]; guardar(nuevo)
            return
        }
        guard bytes > (e["cabe"] ?? 0) else { return }
        e["cabe"] = bytes
        t[id] = e
        guardar(t)
    }

    /// El motor rechazó `bytes`: baja el techo conocido.
    ///
    /// Solo se llama cuando el SERVIDOR contestó que no. Un corte de internet o
    /// una conexión colgada NO enseñan nada: si se aprendiera de ellos, una
    /// caída de red de un minuto dejaría al motor marcado para siempre con un
    /// techo falso de tres minutos, partiendo dictados que tragaba de sobra.
    static func anotarRechazo(_ id: String, bytes: Int) {
        var t = tabla()
        var e = t[id] ?? [:]
        let previo = e["rechaza"] ?? Int.max
        guard bytes < previo else { return }
        e["rechaza"] = bytes
        e["visto"] = Int(Date().timeIntervalSince1970)
        t[id] = e
        guardar(t)
        Log.log(.ia, "límites: \(id) rechazó \(bytes / 1024) kB — lo recuerdo y a partir de ahora parto antes de mandarlo")
    }

    /// Cuánto vive un techo aprendido. Un proveedor amplía cupos, cambia de
    /// plan o arregla un fallo suyo; pasado este plazo se vuelve a probar
    /// entero, y si entra, la medida sube sola.
    private static let caducidad: TimeInterval = 14 * 24 * 3600   // dos semanas

    /// Olvida lo aprendido de un motor. Se usa cuando la medida se contradice
    /// con la realidad —entró algo más grande de lo que supuestamente rechaza—
    /// o cuando ha envejecido.
    static func olvidar(_ id: String, porque motivo: String) {
        var t = tabla()
        guard t[id] != nil else { return }
        t.removeValue(forKey: id)
        guardar(t)
        Log.log(.ia, "límites: olvido lo aprendido de \(id) (\(motivo)) — vuelvo a probarlo entero")
    }

    /// Tamaño con el que conviene mandar a este motor, o nil si no se sabe nada
    /// todavía. Se deja un margen del 20 % bajo el rechazo conocido: el techo
    /// real está entre lo que cupo y lo que no, y arrimarse no compensa.
    static func tamanoSeguro(_ id: String, minimo: Int = minimoParaPartir) -> Int? {
        let e = tabla()[id] ?? [:]
        guard let rechaza = e["rechaza"] else { return nil }
        // Caducado: se vuelve a probar entero. Si el techo sigue ahí, se
        // aprenderá otra vez a la primera; si ya no, se recupera lo perdido.
        if let visto = e["visto"], Date().timeIntervalSince1970 - Double(visto) > caducidad {
            olvidar(id, porque: "la medida tiene más de dos semanas")
            return nil
        }
        let cabe = e["cabe"] ?? 0
        let seguro = cabe > 0 && cabe < rechaza ? cabe : Int(Double(rechaza) * 0.8)
        return max(minimo, RedSeguridadDictado.par(seguro))
    }

    // MARK: Lo mismo, pero con texto
    //
    // Una IA que pule tiene un techo de contexto igual que un transcriptor tiene
    // uno de tamaño, y tampoco lo declara de forma uniforme: unas devuelven la
    // respuesta cortada, otras un error. El trato es el mismo — se aprende del
    // corte y la próxima vez se manda partido.

    /// Por debajo de esto no se parte un texto: si la IA no puede con cuatro mil
    /// caracteres, el problema no es la longitud.
    static let minimoTextoParaPartir = 4_000

    /// Clave con la que se anotan los techos de una IA, para no confundirlos con
    /// los de un motor de audio que podría llamarse igual.
    static func claveIA(_ id: String) -> String { "ia:\(id)" }

    /// Parte por FRASES, nunca a mitad de palabra ni de oración: pulir media
    /// frase produce mayúsculas y puntos donde no van, y al unir se nota.
    /// Si una sola frase ya excede el tope —un dictado sin puntuación— se parte
    /// por palabras, que sigue siendo mejor que cortar por la mitad una.
    static func partirTexto(_ texto: String, maxBytes: Int) -> [String] {
        let tope = max(500, maxBytes)
        guard texto.utf8.count > tope else { return [texto] }
        var partes: [String] = []
        var actual = ""
        func cerrar() {
            let t = actual.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { partes.append(t) }
            actual = ""
        }
        for frase in oraciones(texto) {
            if actual.utf8.count + frase.utf8.count > tope, !actual.isEmpty { cerrar() }
            if frase.utf8.count > tope {
                cerrar()
                // Frase gigantesca: se reparte por palabras.
                var trozo = ""
                for palabra in frase.split(separator: " ", omittingEmptySubsequences: false) {
                    if trozo.utf8.count + palabra.utf8.count + 1 > tope, !trozo.isEmpty {
                        partes.append(trozo.trimmingCharacters(in: .whitespaces)); trozo = ""
                    }
                    trozo += palabra + " "
                }
                if !trozo.trimmingCharacters(in: .whitespaces).isEmpty {
                    partes.append(trozo.trimmingCharacters(in: .whitespaces))
                }
            } else {
                actual += frase
            }
        }
        cerrar()
        return partes.isEmpty ? [texto] : partes
    }

    /// Trocea en oraciones conservando el separador, para que al unir quede
    /// exactamente el mismo texto.
    private static func oraciones(_ texto: String) -> [String] {
        var out: [String] = []
        var actual = ""
        for c in texto {
            actual.append(c)
            if ".!?…\n".contains(c) {
                out.append(actual); actual = ""
            }
        }
        if !actual.isEmpty { out.append(actual) }
        return out
    }

    /// Lo aprendido, para el panel de salud.
    static func aprendidos() -> [(motor: String, cabe: Int, rechaza: Int)] {
        tabla().compactMap { (id, e) in
            guard let r = e["rechaza"] else { return nil }
            return (id, e["cabe"] ?? 0, r)
        }.sorted { $0.motor < $1.motor }
    }

    // MARK: ¿Este fallo puede ser de tamaño?

    /// No se pregunta «¿cuál es el límite?», sino «¿este fallo es compatible con
    /// haberme pasado?». Las credenciales, la cuota y el audio sin voz NO lo
    /// son: ahí partir no arregla nada y solo gasta dinero y tiempo.
    /// ¿El fallo huele a «no pude con algo tan grande»?
    ///
    /// `conVoz` dice si el audio contiene habla. Importa para un solo caso, pero
    /// es el que dejaba pasar el fallo más caro: ver abajo.
    static func pareceDeTamano(_ e: Error, bytes: Int, conVoz: Bool = false) -> Bool {
        guard bytes > minimoParaPartir else { return false }
        if case ScribeError.sinTexto = e {
            // Un motor que no devuelve texto puede estar diciendo dos cosas muy
            // distintas, y durante mucho tiempo se supuso siempre la primera:
            //
            //   a) «aquí no hay nadie hablando» — partir el silencio no produce
            //      texto, así que trocear sería puro gasto.
            //   b) «no pude con esto» — los motores LOCALES no contestan 413: se
            //      quedan sin memoria y salen sin escribir nada. Medido el
            //      2026-09-19: con 61 min de audio, Voxtral pide un buffer de
            //      64 GB, falla en 1,7 s y devuelve vacío. Como esto se leía como
            //      el caso (a), no se troceaba NUNCA y la hora entera se perdía
            //      en ese motor.
            //
            // Los distingue el propio audio: si tiene voz, el vacío no es del
            // audio, es del motor.
            return conVoz
        }
        if case ScribeError.sinApiKey = e { return false }
        if case ScribeError.http(let code, _) = e {
            switch code {
            case 401, 402, 403, 404, 429: return false   // credencial, saldo o ritmo
            default: return true                          // 400, 413, 422, 5xx…
            }
        }
        // Un envío que se cuelga con un archivo grande también encaja: muchos
        // servidores cortan la conexión en vez de contestar «demasiado grande».
        let n = e as NSError
        if n.domain == NSURLErrorDomain {
            return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                    NSURLErrorDataLengthExceedsMaximum].contains(n.code)
        }
        return false
    }

    // MARK: ¿Vino todo?

    /// Segundos de audio con voz dentro de un WAV, con el mismo criterio que usa
    /// la bitácora para no mandar silencio a la nube.
    ///
    /// Se mide sobre el audio que se va a enviar, no sobre su duración total:
    /// media hora de reunión con diez minutos de habla debe juzgarse por los
    /// diez, o cualquier umbral sobre el texto daría falsa alarma.
    static func segundosDeVoz(_ wav: CuerpoMultipart.Origen) -> Double {
        let umbral = AudioSilencio.umbralPico()
        guard umbral > 0 else { return Double(max(0, wav.bytes - 44)) / Double(RedSeguridadDictado.bytesPorSegundo) }
        var sonoras = 0
        let datos = wav.leer()
        guard datos.count > 44 else { return 0 }
        datos.withUnsafeBytes { crudo in
            let muestras = crudo.bindMemory(to: Int16.self)
            var i = 22                                   // saltar los 44 B de cabecera
            while i < muestras.count {
                if Int(muestras[i].magnitude) >= umbral { sonoras += 1 }
                i += 1
            }
        }
        return Double(sonoras) / Double(RedSeguridadDictado.bytesPorSegundo / 2)
    }

    /// ¿El texto devuelto es demasiado poco para lo que se oye en el audio?
    ///
    /// Este es el fallo hermano del anterior, y el más peligroso de los dos: un
    /// motor que se atraganta con audio largo no siempre falla. A veces
    /// transcribe los primeros minutos, se detiene y devuelve ESO como si fuera
    /// todo. La llamada sale bien, el registro dice «OK», y lo que falta no lo
    /// echa en falta nadie — salvo quien dictó.
    ///
    /// El umbral es deliberadamente flojo: hablando despacio salen unas 100
    /// palabras por minuto, y aquí se exige una sola cada tres segundos de VOZ.
    /// No pretende juzgar la calidad; solo cazar al motor que entregó un tercio
    /// de lo dictado. Con menos de dos minutos de voz no opina: en lo corto, una
    /// respuesta breve puede ser legítima.
    static func pareceTruncado(texto: String, segundosDeVoz voz: Double) -> Bool {
        guard voz >= 120 else { return false }
        let palabras = texto.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        return Double(palabras) < voz / 3.0
    }

    // MARK: Partir y coser

    /// Corta el WAV en tramos de `bytesPorTramo` con solape, cada uno como un
    /// WAV completo y válido. El corte va SIEMPRE en frontera de muestra: el
    /// PCM es de 16 bits y empezar en un byte impar convierte el audio en ruido.
    static func tramos(_ wav: Data, bytesPorTramo: Int) -> [Data] {
        guard wav.count > 44 else { return [] }
        let pcm = wav.subdata(in: 44..<wav.count)
        let paso = max(RedSeguridadDictado.bytesPorSegundo, RedSeguridadDictado.par(bytesPorTramo))
        let solape = RedSeguridadDictado.par(solapeSegundos * RedSeguridadDictado.bytesPorSegundo)
        guard pcm.count > paso else { return [wav] }
        var out: [Data] = []
        var inicio = 0
        while inicio < pcm.count {
            let fin = min(pcm.count, inicio + paso)
            out.append(HistoryWriter.wavData(pcm: pcm.subdata(in: inicio..<fin)))
            if fin >= pcm.count { break }
            inicio = RedSeguridadDictado.par(max(inicio + 1, fin - solape))
        }
        return out
    }

    /// Manda `wav` por `enviar`, y si vuelve rechazado de una forma que puede
    /// ser de tamaño, lo parte en dos y reintenta cada mitad por el MISMO
    /// motor, recursivamente, hasta que entre o hasta que los tramos sean tan
    /// cortos que el problema ya no pueda ser el tamaño.
    ///
    /// `profundidad` limita la recursión: cada nivel duplica el número de
    /// llamadas, y más allá de cuatro (dieciséis tramos) el fallo es otro.
    static func enviarPartiendo(_ wav: CuerpoMultipart.Origen, motor: String, profundidad: Int = 0,
                                enviar: @escaping (CuerpoMultipart.Origen, @escaping (Result<String, Error>) -> Void) -> Void,
                                completion: @escaping (Result<String, Error>) -> Void) {
        // Si ya se sabe que este motor no traga tanto, se parte de entrada.
        if profundidad == 0, let seguro = tamanoSeguro(motor), wav.bytes > seguro + 44 {
            // Partir es lo excepcional, y solo aquí hace falta el audio en memoria.
            let partes = tramos(wav.leer(), bytesPorTramo: seguro)
            if partes.count > 1 {
                Log.log(.ia, "\(motor): \(wav.bytes / 1024) kB pasan de lo que admite — lo mando en \(partes.count) tramos")
                encadenar(partes, motor: motor, profundidad: profundidad + 1,
                          enviar: enviar, completion: completion)
                return
            }
        }
        // Cuánta voz trae el audio. Se calcula UNA vez y solo cuando el audio es
        // grande: es recorrer las muestras, y en lo corto no decide nada.
        let voz: Double = wav.bytes > minimoParaPartir ? segundosDeVoz(wav) : 0

        enviar(wav) { r in
            switch r {
            case .success(let texto):
                // Un éxito con muy poco texto para lo que se oye no es un éxito:
                // es un motor que se detuvo a medias y no lo dijo. Se trata como
                // lo que es —no pudo con el tamaño— y se reintenta partido.
                if profundidad < 4, pareceTruncado(texto: texto, segundosDeVoz: voz),
                   case let partes = tramos(wav.leer(), bytesPorTramo: RedSeguridadDictado.par((wav.bytes - 44) / 2)),
                   partes.count > 1 {
                    Log.log(.ia, "\(motor): devolvió \(texto.split(separator: " ").count) palabras para \(Int(voz)) s de voz — parece que se quedó a medias, lo reintento en \(partes.count) tramos")
                    anotarRechazo(motor, bytes: wav.bytes)
                    encadenar(partes, motor: motor, profundidad: profundidad + 1,
                              enviar: enviar, completion: completion)
                    return
                }
                anotarExito(motor, bytes: wav.bytes)
                completion(.success(texto))
            case .failure(let e):
                guard profundidad < 4, pareceDeTamano(e, bytes: wav.bytes, conVoz: voz > 0.5) else {
                    completion(.failure(e)); return
                }
                // Un motor local sin memoria no contesta un código: se va en
                // silencio. Ese caso también deja medida, porque su techo es
                // estable —depende de la RAM del equipo, no del servidor de
                // nadie— y conviene recordarlo para el próximo dictado largo.
                if case ScribeError.sinTexto = e { anotarRechazo(motor, bytes: wav.bytes) }
                // Partir SÍ se intenta siempre que el fallo encaje; APRENDER
                // solo cuando contestó el servidor. Un cuelgue de red merece un
                // reintento en trozos —por si acaso—, pero jamás una medida.
                if case ScribeError.http = e { anotarRechazo(motor, bytes: wav.bytes) }
                let mitad = RedSeguridadDictado.par((wav.bytes - 44) / 2)
                let partes = tramos(wav.leer(), bytesPorTramo: mitad)
                guard partes.count > 1 else { completion(.failure(e)); return }
                Log.log(.ia, "\(motor) no admitió \(wav.bytes / 1024) kB — lo parto en \(partes.count) y sigo con el mismo motor")
                encadenar(partes, motor: motor, profundidad: profundidad + 1,
                          enviar: enviar, completion: completion)
            }
        }
    }

    /// Envía los tramos EN SERIE —no en paralelo: los planes de estos servicios
    /// limitan las peticiones simultáneas y adelantar dos segundos no compensa
    /// que te corten— y los cose quitando el solape.
    private static func encadenar(_ partes: [Data], motor: String, profundidad: Int,
                                  enviar: @escaping (CuerpoMultipart.Origen, @escaping (Result<String, Error>) -> Void) -> Void,
                                  completion: @escaping (Result<String, Error>) -> Void) {
        var texto = ""
        var fallos = 0
        var ultimoError: Error?
        func siguiente(_ i: Int) {
            guard i < partes.count else {
                // Con que UN tramo haya salido, se entrega: el objetivo es que
                // no se pierda lo dictado, no que la llamada sea perfecta.
                if texto.isEmpty { completion(.failure(ultimoError ?? ScribeError.sinTexto)) }
                else {
                    if fallos > 0 {
                        Log.log(.ia, "\(motor): \(partes.count - fallos) de \(partes.count) tramos salieron — entrego lo recuperado")
                    }
                    completion(.success(texto))
                }
                return
            }
            // Los tramos ya están partidos y son pequeños: van en memoria.
            enviarPartiendo(.datos(partes[i]), motor: motor, profundidad: profundidad,
                            enviar: enviar) { r in
                switch r {
                case .success(let t): texto = texto.isEmpty ? t : RedSeguridadDictado.unir(texto, t)
                case .failure(let e): fallos += 1; ultimoError = e
                    Log.log(.ia, "\(motor): el tramo \(i + 1) de \(partes.count) falló (\(e.localizedDescription)) — sigo con el resto")
                }
                siguiente(i + 1)
            }
        }
        siguiente(0)
    }
}
