import Foundation

/// El portero: un motor local decide si en un trozo habló alguien.
///
/// Por qué existe
/// --------------
/// La bitácora graba la jornada entera, y la mayor parte de lo que graba no es
/// nadie hablando. Mirar la energía del audio (ver `AudioSilencio`) es barato
/// pero tonto: distingue fuerte de flojo, no voz de ruido. Un ventilador, una
/// obra en la calle o una conversación en el pasillo tienen energía de sobra.
///
/// Medido el 2026-09-19 en esta máquina: **764 minutos de audio enviados a un
/// motor de pago en un día**, de los cuales 414 llamadas volvieron sin una sola
/// palabra.
///
/// La idea clave
/// -------------
/// El portero **no transcribe para entregar**: solo abre o cierra la puerta. Por
/// eso puede ser el motor local más rápido aunque no sea el más preciso — que
/// confunda una palabra da igual, lo único que se le pregunta es si hubo voz.
/// Lo que se entrega lo produce el motor que el usuario haya puesto primero en
/// su cascada, sea local o de nube: esa elección sigue siendo suya.
///
/// Ante la duda, se pasa
/// ---------------------
/// Si el portero falla, no hay modelo o se agota el tiempo, la respuesta es
/// `.noSePudo` y el trozo **se transcribe igual**. Un portero averiado no puede
/// hacer perder lo que alguien dictó; a lo sumo cuesta una llamada de más.
enum PorteroVoz {

    enum Veredicto { case hayVoz; case silencio; case noSePudo }

    /// Cuántas letras tiene que devolver el portero para dar por buena la voz.
    ///
    /// No es cero: los motores devuelven a veces un artefacto suelto sobre audio
    /// mudo —una muletilla, un «mm», un signo—. Tres letras descartan eso sin
    /// llegar a descartar un «sí» o un «no», que son respuestas legítimas.
    static func minimoLetras() -> Int {
        max(1, (Config.json0("bitacora_portero_minimo") as? Int) ?? 3)
    }

    /// Cuánto se le espera. Pasado el plazo, `.noSePudo` y el trozo se manda:
    /// el portero existe para ahorrar, no para retrasar.
    static func plazoSegundos() -> Double {
        max(2, (Config.json0("bitacora_portero_plazo") as? Double) ?? 25)
    }

    /// Veredicto de VARIOS porteros sobre el mismo trozo.
    ///
    /// La asimetría es deliberada y es lo que hace seguro apartar audio:
    ///
    /// - Para **abrir** basta uno: si cualquiera oye voz, el trozo se transcribe.
    /// - Para **cerrar** tienen que coincidir todos. Descartar exige que dos
    ///   motores independientes se equivoquen a la vez.
    ///
    /// Y se pregunta en orden, parando en cuanto uno oye voz: al segundo solo se
    /// le consulta cuando el primero dijo que no había nada, que es justo el
    /// caso en el que conviene una segunda opinión.
    static func hayVoz(en archivo: URL, motores: [String]) -> Veredicto {
        guard !motores.isEmpty else { return .noSePudo }
        var algunoRespondio = false
        for m in motores {
            switch hayVoz(en: archivo, motor: m) {
            case .hayVoz:   return .hayVoz          // uno basta para abrir
            case .silencio: algunoRespondio = true  // sigue preguntando
            case .noSePudo: continue                // ese juez no cuenta
            }
        }
        // Si ninguno pudo pronunciarse, no hay veredicto: ante la duda, se manda.
        return algunoRespondio ? .silencio : .noSePudo
    }

    static func hayVoz(en archivo: URL, motor: String) -> Veredicto {
        let datos: Data
        if archivo.pathExtension.lowercased() == "pcm" {
            guard let crudo = try? Data(contentsOf: archivo) else { return .noSePudo }
            datos = HistoryWriter.wavData(pcm: crudo)
        } else {
            guard let d = try? Data(contentsOf: archivo) else { return .noSePudo }
            datos = d
        }

        let semaforo = DispatchSemaphore(value: 0)
        var texto: String?
        var fallo = false

        let terminar: (Result<String, Error>) -> Void = { r in
            switch r {
            case .success(let t): texto = t
            case .failure:        fallo = true      // incluye «sin texto»
            }
            semaforo.signal()
        }

        switch motor {
        case "apple_speech":
            AppleSpeechSTT.run(wav: .datos(datos), idioma: nil, completion: terminar)
        default:
            // Cualquier otro motor local del catálogo, como cadena de uno solo:
            // así conserva su modelo y su configuración.
            let cadena = Providers.cadena().filter { $0.id == motor }
            guard !cadena.isEmpty else { return .noSePudo }
            Failover.transcribe(wav: .datos(datos), cadena: cadena) { r in
                terminar(r.map { $0.0 })
            }
        }

        guard semaforo.wait(timeout: .now() + plazoSegundos()) == .success else {
            Log.log(.ia, "portero: \(motor) no contestó en \(Int(plazoSegundos())) s — mando el trozo igual")
            return .noSePudo
        }

        // Un fallo del portero NO es un veredicto de silencio. La única excepción
        // es «sin texto», que aquí es exactamente la respuesta que se buscaba:
        // el motor escuchó y no encontró palabras.
        if fallo { return .silencio }

        let limpio = (texto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let letras = limpio.filter { $0.isLetter || $0.isNumber }.count
        return letras >= minimoLetras() ? .hayVoz : .silencio
    }
}
