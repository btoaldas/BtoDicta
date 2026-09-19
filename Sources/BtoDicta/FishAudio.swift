import Foundation

// MARK: - Fish Audio — voz y transcripción con la misma clave
//
// Fish Audio hace las dos cosas que aquí interesan, como ElevenLabs: hablar con
// una voz CLONADA y transcribir. Se enchufa en los dos catálogos de la app —el
// de motores de transcripción y el de voces de nube— con una sola clave,
// `FISH_API_KEY`.
//
// Tres cosas que esta API hace distinto y cuestan tiempo si no se saben:
//
//  1. El modelo de voz viaja en una CABECERA HTTP (`model:`), no en el cuerpo.
//  2. La voz se elige con `reference_id`, que es el identificador del clon
//     entrenado en fish.audio (no un nombre como "alloy" o "Kore").
//  3. El crédito de API es una bolsa DISTINTA del crédito de la plataforma y
//     empieza en cero. Sin recargarlo, los modelos de pago y la transcripción
//     responden 402 — que aquí cae en cuarentena de 30 min como cualquier otro
//     proveedor sin saldo. El modelo `s2.1-pro-free` sí habla sin crédito, y
//     por eso es el que viene puesto por defecto.

enum FishAudio {
    static let base = "https://api.fish.audio"

    /// Modelos de voz, del recomendado al heredado. `s2.1-pro-free` va primero
    /// porque es el único que funciona sin recargar el crédito de API.
    static let modelosVoz = ["s2.1-pro-free", "s2.1-pro", "s2-pro", "s1"]

    /// El único que no consume crédito. Es el primer escalón de la cascada de
    /// ahorro: si responde, la frase sale gratis.
    static let modeloGratis = "s2.1-pro-free"

    static func clave() -> String {
        if let e = ProcessInfo.processInfo.environment["FISH_API_KEY"], !e.isEmpty { return e }
        return ApiKeys.get("FISH_API_KEY")
    }
}

/// Transcripción por lotes (`POST /v1/asr`). Un solo envío multipart; la
/// respuesta trae el texto completo y, si se piden, los tiempos por segmento
/// —que aquí no hacen falta, así que se ahorran.
///
/// Ojo: este extremo NO tiene capa gratuita. Sin crédito de API responde 402 y
/// el failover salta al siguiente motor.
enum FishTranscribe {
    /// ¿El fallo es del TRANSPORTE —la conexión, no el servidor—? Distinguirlo
    /// importa: que se atragante un envío no significa que el proveedor esté
    /// caído, y abandonarlo por eso es un falso positivo que manda el dictado a
    /// otro motor peor teniendo este perfectamente sano. Un 402 o un 401 sí son
    /// del servidor y ahí no hay nada que reintentar.
    private static func esDeLaConexion(_ e: Error) -> Bool {
        let n = e as NSError
        guard n.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost].contains(n.code)
    }

    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        intentar(wav: wav, reintentos: 1, completion: completion)
    }

    private static func intentar(wav: CuerpoMultipart.Origen, reintentos: Int,
                                 completion: @escaping (Result<String, Error>) -> Void) {
        let key = FishAudio.clave()
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la key de Fish Audio — ponla en Configuración → Modelos"))); return
        }
        guard let url = URL(string: "\(FishAudio.base)/v1/asr") else {
            completion(.failure(ScribeError.ws("URL de Fish Audio inválida"))); return
        }
        let boundary = "BtoDicta-\(UUID().uuidString)"
        func campo(_ nombre: String, _ valor: String) -> Data {
            Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombre)\"\r\n\r\n\(valor)\r\n".utf8)
        }
        // La app siempre manda WAV, pero la prueba de ida y vuelta reinyecta el
        // mp3 que acaba de generar el TTS. Se rotula por el contenido real:
        // mentir en el tipo es la forma más tonta de que el servidor rechace un
        // audio que está perfectamente bien.
        // Los primeros bytes bastan para saber si es WAV: no hace falta leerlo entero.
        let cabecera = wav.primerosBytes(4)
        let esWav = cabecera == Data("RIFF".utf8)
        let nombreArchivo = esWav ? "audio.wav" : "audio.mp3"
        let tipo = esWav ? "audio/wav" : "audio/mpeg"
        // Los campos van DESPUÉS del audio, como estaban: el orden de las
        // partes no es indiferente para esta API.
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(
                boundary: boundary, campos: [],
                nombreCampo: "audio", nombreArchivo: nombreArchivo, tipo: tipo,
                audio: wav,
                camposDespues: [("language", "es", nil),
                                // Sin tiempos: la app solo quiere el texto y así
                                // la respuesta es menor.
                                ("ignore_timestamps", "true", nil)])
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // Plazo proporcional al audio, no un número fijo y grande. Medido sobre
        // esta API: 72 s de audio se transcriben en 2,8-3,1 s, y 12 s en ~1 s.
        // Un tope de 60 s no protegía de nada y sí castigaba: una conexión que
        // se quedó colgada hizo esperar un minuto entero antes de pasar al
        // siguiente motor. Con esto el failover llega en 20-45 s según el
        // tamaño —diez veces lo medido— y aun así se reintenta antes de rendirse.
        let segundos = Double(max(0, wav.bytes - 44)) / Double(RedSeguridadDictado.bytesPorSegundo)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = max(15, min(30, segundos * 0.4))
        // SIN `Connection: close`. Lo tenía, y era la causa de que un dictado se
        // colgara justo el tiempo del plazo mientras el anterior y el siguiente
        // salían en un segundo: el servidor cerraba la conexión al responder y
        // el banco del cliente se la quedaba igualmente, de modo que el envío
        // siguiente esperaba a un socket que ya no existía. Se deja que
        // URLSession gobierne la conexión, como ya se aprendió en el pulido.
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Medir SIEMPRE, no solo cuando falla. Medido desde fuera de la app
        // —misma máquina, mismo audio, misma hora— la subida va a 800 kB/s y la
        // respuesta llega en menos de 3 s; dentro de la app, en cambio, algunos
        // dictados largos agotan el plazo. Sin estos números el diagnóstico es
        // adivinanza, así que cada llamada deja su tamaño y su tiempo.
        let kb = cuerpo.bytes / 1024
        let t0 = Date()
        // El primer envío aprovecha el banco compartido (conexión ya caliente);
        // el reintento estrena la suya, porque si el primero se colgó lo más
        // probable es que la culpa sea justo de esa conexión.
        // Primer envío: la conexión compartida del dictado, que se renueva
        // sola si lleva rato parada. Reintento: siempre una nueva.
        let sesion = reintentos > 0 ? RedDictado.sesion() : RedDictado.sesionNueva()
        CuerpoMultipart.subir(req, cuerpo: cuerpo, sesion: sesion) { data, resp, err in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            // La sesión de un solo uso se cierra en cuanto contesta; la
            // compartida es de toda la aplicación y no se toca.
            if !RedDictado.esCompartida(sesion) { sesion.finishTasksAndInvalidate() }
            DispatchQueue.main.async {
                Log.debug("Fish Audio: \(kb) kB de audio, plazo \(Int(req.timeoutInterval)) s → \(ms) ms")
                if let err {
                    Log.log(.ia, "Fish Audio: falló tras \(ms) ms con \(kb) kB (plazo \(Int(req.timeoutInterval)) s)")
                    // Se reintenta UNA vez, y solo si el fallo fue de la
                    // conexión. Medido: 72 s de audio se transcriben en ~3 s,
                    // así que un envío que se cuelga es un tropiezo de red, no
                    // un motor caído — y cambiar de motor por eso empeora el
                    // resultado sin motivo.
                    if reintentos > 0, esDeLaConexion(err) {
                        Log.log(.ia, "Fish Audio: se cortó el envío (\(err.localizedDescription)) — reintento antes de cambiar de motor")
                        intentar(wav: wav, reintentos: reintentos - 1, completion: completion)
                        return
                    }
                    completion(.failure(err)); return
                }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let texto = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !texto.isEmpty else {
                    completion(.failure(ScribeError.sinTexto)); return
                }
                // El aviso se mide CONTRA LA DURACIÓN del audio, no contra un
                // número fijo. Medido en nueve corridas de 52 a 180 s, esta API
                // tarda un 3-4 % de lo que dura el audio, así que tres minutos
                // en seis segundos es normal y un umbral fijo de cinco los
                // marcaría todos. Se avisa al pasar del 10 %: el triple de lo
                // normal, y nunca por debajo de cinco segundos.
                let umbral = max(5_000.0, segundos * 100)
                if Double(ms) > umbral {
                    Log.log(.ia, "Fish Audio: tardó \(ms) ms con \(kb) kB para \(Int(segundos)) s de audio — el triple de lo normal")
                }
                completion(.success(texto))
            }
        }
    }
}
