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
    static func run(wav: Data, model: String, completion: @escaping (Result<String, Error>) -> Void) {
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
        let esWav = wav.count > 4 && wav.prefix(4) == Data("RIFF".utf8)
        let nombreArchivo = esWav ? "audio.wav" : "audio.mp3"
        let tipo = esWav ? "audio/wav" : "audio/mpeg"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"\(nombreArchivo)\"\r\nContent-Type: \(tipo)\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n".utf8))
        body.append(campo("language", "es"))
        // Sin tiempos: la app solo quiere el texto y así la respuesta es menor.
        body.append(campo("ignore_timestamps", "true"))
        body.append(Data("--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        URLSession.shared.uploadTask(with: req, from: body) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
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
                completion(.success(texto))
            }
        }.resume()
    }
}
