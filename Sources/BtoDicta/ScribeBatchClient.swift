import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Cliente batch (scribe_v1 / scribe_v2 + keyterms)

func transcribeBatch(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
    guard let key = Config.apiKey() else {
        completion(.failure(ScribeError.sinApiKey))
        return
    }
    let boundary = "BtoDicta-\(UUID().uuidString)"
    var campos: [(String, String)] = [("model_id", model), ("language_code", "es"),
                                      ("tag_audio_events", "false")]
    for term in Config.keyterms().prefix(1000) { campos.append(("keyterms", term)) }
    let cuerpo: CuerpoMultipart.Preparado
    do {
        cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: campos,
                                               nombreArchivo: "dictado.wav",
                                               tipo: "audio/wav", audio: wav)
    } catch { completion(.failure(error)); return }

    // SIN `Connection: close`, y por la sesión compartida del dictado. Este
    // motor se quedó fuera del arreglo de 0.59.0: seguía pidiendo el cierre de
    // la conexión sobre `URLSession.shared`, así que el envío siguiente heredaba
    // un socket ya cerrado y esperaba en balde hasta agotar el plazo.
    var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
    request.httpMethod = "POST"
    // Corto a propósito: con red mala es mejor saltar rápido al siguiente
    // proveedor de la cascada (Whisper local responde en <1 s) que esperar.
    request.timeoutInterval = 15
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "xi-api-key")

    CuerpoMultipart.subir(request, cuerpo: cuerpo) { data, response, error in
        DispatchQueue.main.async {
            if let error { completion(.failure(error)); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(ScribeError.sinTexto)); return }
            guard (200..<300).contains(code) else {
                completion(.failure(ScribeError.http(code, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                completion(.failure(ScribeError.sinTexto))
                return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}

/// Transcribe un archivo de disco (audio o video). ElevenLabs acepta muchos
/// formatos (wav, mp3, m4a, ogg, mp4, mov…) y extrae el audio del video.
func transcribeFile(url: URL, model: String, completion: @escaping (Result<String, Error>) -> Void) {
    guard let key = Config.apiKey() else { completion(.failure(ScribeError.sinApiKey)); return }
    guard let fileData = try? Data(contentsOf: url) else {
        completion(.failure(ScribeError.http(0, "No se pudo leer el archivo")))
        return
    }
    let mime: String = {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "ogg", "oga": return "audio/ogg"
        case "flac": return "audio/flac"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "audio/wav"
        }
    }()

    let boundary = "BtoDicta-\(UUID().uuidString)"
    var body = Data()
    func field(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    field("model_id", model)
    field("language_code", "es")
    field("tag_audio_events", "false")
    for term in Config.keyterms().prefix(1000) { field("keyterms", term) }
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!); request.setValue("close", forHTTPHeaderField: "Connection")
    request.httpMethod = "POST"
    request.timeoutInterval = 300   // archivos largos
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(key, forHTTPHeaderField: "xi-api-key")

    URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        DispatchQueue.main.async {
            if let error { completion(.failure(error)); return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(ScribeError.sinTexto)); return }
            guard (200..<300).contains(code) else {
                completion(.failure(ScribeError.http(code, String(data: data, encoding: .utf8) ?? "")))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                completion(.failure(ScribeError.sinTexto)); return
            }
            completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }.resume()
}

