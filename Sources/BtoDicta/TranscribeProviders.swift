import Foundation

// MARK: - Clientes de transcripción por proveedor + failover

/// Transcripción vía cualquier API compatible con OpenAI (multipart + JSON).
/// La usan Groq, OpenAI y Mistral — solo cambian endpoint, key y modelo.
enum OpenAICompatible {
    static func transcribir(endpoint: String, key: String, model: String,
                            wav: CuerpoMultipart.Origen,
                            conPrompt: Bool = true,
                            completion: @escaping (Result<String, Error>) -> Void) {
        let boundary = "BtoDicta-\(UUID().uuidString)"
        var campos: [(String, String)] = [("model", model), ("language", "es"), ("response_format", "json")]
        if conPrompt {
            let glosario = Config.glosarioPrompt()
            if !glosario.isEmpty { campos.append(("prompt", glosario)) }
        }
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: campos,
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }

        var req = URLRequest(url: URL(string: endpoint)!); req.httpMethod = "POST"
        // Corto a propósito: mejor saltar al siguiente de la cascada que colgar.
        req.timeoutInterval = 15
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }  // locales sin auth

        CuerpoMultipart.subir(req, cuerpo: cuerpo) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code,
                        data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String else {
                    completion(.failure(ScribeError.sinTexto)); return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// Transcribe con OpenAI (whisper-1, gpt-4o-transcribe…).
enum OpenAITranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("OPENAI_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de OpenAI — ponla en Configuración → Modelos")))
            return
        }
        OpenAICompatible.transcribir(endpoint: "https://api.openai.com/v1/audio/transcriptions",
                                     key: key, model: model, wav: wav, completion: completion)
    }
}

/// Transcribe con Mistral (Voxtral en la nube).
enum MistralTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("MISTRAL_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Mistral — ponla en Configuración → Modelos")))
            return
        }
        // La API de audio de Mistral no acepta el campo "prompt".
        OpenAICompatible.transcribir(endpoint: "https://api.mistral.ai/v1/audio/transcriptions",
                                     key: key, model: model, wav: wav, conPrompt: false,
                                     completion: completion)
    }
}

/// Transcribe con Groq (whisper-large-v3, nube). API compatible OpenAI.
enum GroqTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String = "whisper-large-v3",
                    completion: @escaping (Result<String, Error>) -> Void) {
        guard let key = Config.groqKey() else { completion(.failure(ScribeError.sinApiKey)); return }
        let boundary = "BtoDicta-\(UUID().uuidString)"
        var campos: [(String, String)] = [("model", model), ("language", "es"), ("response_format", "json")]
        // Glosario: Whisper acepta un "prompt" que sesga el vocabulario (igual que keyterms en ElevenLabs)
        let glosario = Config.glosarioPrompt()
        if !glosario.isEmpty { campos.append(("prompt", glosario)) }
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: campos,
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }

        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        CuerpoMultipart.subir(req, cuerpo: cuerpo) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code,
                                                          data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = json["text"] as? String else { completion(.failure(ScribeError.sinTexto)); return }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// Transcribe con Fireworks (Whisper en la nube). API compatible OpenAI.
enum FireworksTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("FIREWORKS_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Fireworks — ponla en Configuración → Modelos"))); return
        }
        OpenAICompatible.transcribir(endpoint: "https://api.fireworks.ai/inference/v1/audio/transcriptions",
                                     key: key, model: model, wav: wav, completion: completion)
    }
}

// MARK: - STT de API propia (no compatibles con OpenAI)
//
// Estos proveedores NO exponen /audio/transcriptions estilo OpenAI: cada uno
// tiene su propio shape. Se agrupan en dos patrones:
//   • UN TIRO (HF, Deepgram): un POST con el audio crudo → JSON con el texto.
//   • POR LOTES (Gladia, AssemblyAI, Speechmatics): subir → crear job →
//     SONDEAR hasta que termine. Añade latencia (peor para dictado), por eso
//     van apagados por defecto; son opción de failover que elige el usuario.

/// Un POST de audio crudo (los bytes del WAV) a una API STT propia; extrae el
/// texto con un closure. La usan HF y Deepgram (endpoints de un solo tiro).
enum RawAudioSTT {
    static func run(url: String, headers: [String: String], contentType: String,
                    wav: CuerpoMultipart.Origen,
                    timeout: TimeInterval = 30,
                    extraer: @escaping ([String: Any]) -> String?,
                    completion: @escaping (Result<String, Error>) -> Void) {
        guard let u = URL(string: url) else { completion(.failure(ScribeError.ws("URL inválida"))); return }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = timeout; req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        CuerpoMultipart.subirCrudo(req, audio: wav) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = extraer(json), !text.isEmpty else {
                    completion(.failure(ScribeError.sinTexto)); return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// Sondea una URL GET cada `intervalo`s hasta que `evaluar` diga listo/error, o
/// se agote `limite`. Para las APIs por lotes (subir→crear→sondear). Acotado a
/// propósito: mejor rendirse y pasar al siguiente de la cascada que colgar.
enum STTPoll {
    enum Resultado { case listo(String); case error(String); case esperar }
    static func sondear(url: String, headers: [String: String], intervalo: TimeInterval = 1.5,
                        limite: TimeInterval = 40, transcurrido: TimeInterval = 0,
                        evaluar: @escaping ([String: Any]) -> Resultado,
                        completion: @escaping (Result<String, Error>) -> Void) {
        guard transcurrido < limite else {
            completion(.failure(ScribeError.ws("La transcripción tardó demasiado"))); return
        }
        guard let u = URL(string: url) else { completion(.failure(ScribeError.ws("URL inválida"))); return }
        var req = URLRequest(url: u); req.timeoutInterval = 15; for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        RedDictado.sesion().dataTask(with: req) { data, resp, err in
            if let err { DispatchQueue.main.async { completion(.failure(err)) }; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, (200..<300).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                }
                return
            }
            switch evaluar(json) {
            case .listo(let t):
                DispatchQueue.main.async { completion(.success(t.trimmingCharacters(in: .whitespacesAndNewlines))) }
            case .error(let m):
                DispatchQueue.main.async { completion(.failure(ScribeError.ws(m))) }
            case .esperar:
                DispatchQueue.main.asyncAfter(deadline: .now() + intervalo) {
                    sondear(url: url, headers: headers, intervalo: intervalo, limite: limite,
                            transcurrido: transcurrido + intervalo, evaluar: evaluar, completion: completion)
                }
            }
        }.resume()
        // ^ `.resume()` NO es decorativo. Sin él la tarea se crea y no arranca
        // nunca: el closure no corre, `completion` no se llama, y quien esperaba
        // la transcripción se queda esperando para siempre. Ni siquiera salta el
        // límite de tiempo de arriba, porque solo se comprueba al reentrar.
        //
        // Cuatro motores —AssemblyAI, Gladia, Soniox y Speechmatics— quedaron
        // mudos por esta línea que faltaba. Los cuatro son los únicos que
        // sondean; los demás no pasan por aquí y por eso funcionaban.
        //
        // Lo peor: el servicio SÍ hacía su trabajo. Sus paneles mostraban los
        // trabajos completados en 2-3 s, cobrados, y la aplicación nunca los
        // recogía.
    }
}

/// POST de JSON que devuelve un campo string (ej. una URL o un id de job).
private func postJSON(url: String, headers: [String: String], cuerpo: [String: Any],
                      timeout: TimeInterval = 20,
                      completion: @escaping (Result<[String: Any], Error>) -> Void) {
    guard let u = URL(string: url) else { completion(.failure(ScribeError.ws("URL inválida"))); return }
    var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = timeout
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
    RedDictado.sesion().dataTask(with: req) { data, resp, err in
        if let err { completion(.failure(err)); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let data, (200..<300).contains(code),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
            return
        }
        completion(.success(json))
    }.resume()
}

/// Hugging Face Inference (Whisper ASR) — free tier ⭐ (accesibilidad). Un POST
/// con el audio crudo al router; responde {"text": …}.
enum HFTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("HF_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Hugging Face — ponla en Configuración → Modelos"))); return
        }
        let m = model.isEmpty ? "openai/whisper-large-v3" : model
        RawAudioSTT.run(url: "https://router.huggingface.co/hf-inference/models/\(m)",
                        headers: ["Authorization": "Bearer \(key)"],
                        contentType: "audio/wav", wav: wav,
                        extraer: { $0["text"] as? String }, completion: completion)
    }
}

/// Deepgram (Nova) — free $200 de crédito. Un POST con el audio crudo;
/// el texto vive en results.channels[0].alternatives[0].transcript.
enum DeepgramTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("DEEPGRAM_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Deepgram — ponla en Configuración → Modelos"))); return
        }
        let m = model.isEmpty ? "nova-3" : model
        RawAudioSTT.run(url: "https://api.deepgram.com/v1/listen?model=\(m)&language=es&smart_format=true",
                        headers: ["Authorization": "Token \(key)"],
                        contentType: "audio/wav", wav: wav,
                        extraer: { json in
                            let results = json["results"] as? [String: Any]
                            let channels = results?["channels"] as? [[String: Any]]
                            let alts = channels?.first?["alternatives"] as? [[String: Any]]
                            return alts?.first?["transcript"] as? String
                        }, completion: completion)
    }
}

/// Cloudflare Workers AI (Whisper) — 10k neuronas/día gratis. Necesita el
/// Account ID en la URL (igual que el chat). Un POST del audio crudo →
/// result.text. El token va como Bearer; el Account ID lo pone el usuario.
enum CloudflareTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("CLOUDFLARE_API_KEY")
        let acct = Config.cloudflareAccountId()
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta el token de Cloudflare — ponlo en Configuración → Modelos"))); return
        }
        guard !acct.isEmpty else {
            completion(.failure(ScribeError.ws("Falta el Account ID de Cloudflare — ponlo en Configuración → Modelos"))); return
        }
        let m = model.isEmpty ? "@cf/openai/whisper" : model
        RawAudioSTT.run(url: "https://api.cloudflare.com/client/v4/accounts/\(acct)/ai/run/\(m)",
                        headers: ["Authorization": "Bearer \(key)"],
                        contentType: "application/octet-stream", wav: wav,
                        extraer: { json in (json["result"] as? [String: Any])?["text"] as? String },
                        completion: completion)
    }
}

/// Soniox — STT premium multilingüe (excelente español latino + code-switching
/// es/en), el más barato del tier de pago ($0.10/h async), capa gratis. Por
/// lotes: subir archivo → crear transcripción → sondear → bajar el texto.
enum SonioxTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("SONIOX_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Soniox — ponla en Configuración → Modelos"))); return
        }
        let auth = ["Authorization": "Bearer \(key)"]
        let modelo = model.isEmpty ? "stt-async-v5" : model
        // 1) subir el audio (multipart, campo "file")
        let boundary = "BtoDicta-\(UUID().uuidString)"
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: [],
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }
        var up = URLRequest(url: URL(string: "https://api.soniox.com/v1/files")!); up.httpMethod = "POST"; up.timeoutInterval = 30
        up.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        up.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        CuerpoMultipart.subir(up, cuerpo: cuerpo) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard err == nil, let data, (200..<300).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fileId = json["id"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                }
                return
            }
            // 2) crear la transcripción (sesga a español/inglés)
            postJSON(url: "https://api.soniox.com/v1/transcriptions", headers: auth,
                     cuerpo: ["file_id": fileId, "model": modelo, "language_hints": ["es", "en"]]) { r2 in
                switch r2 {
                case .failure(let e): DispatchQueue.main.async { completion(.failure(e)) }
                case .success(let j):
                    guard let id = j["id"] as? String else {
                        DispatchQueue.main.async { completion(.failure(ScribeError.sinTexto)) }; return
                    }
                    // 3) sondear estado
                    STTPoll.sondear(url: "https://api.soniox.com/v1/transcriptions/\(id)", headers: auth, evaluar: { jj in
                        switch jj["status"] as? String {
                        case "completed": return .listo("__LISTO__")   // señal: bajar transcript
                        case "error":     return .error((jj["error_message"] as? String) ?? "Soniox falló")
                        default:          return .esperar
                        }
                    }) { r in
                        switch r {
                        case .failure(let e): completion(.failure(e))
                        case .success:
                            // 4) bajar el texto
                            var t = URLRequest(url: URL(string: "https://api.soniox.com/v1/transcriptions/\(id)/transcript")!)
                            t.timeoutInterval = 15
                            t.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                            RedDictado.sesion().dataTask(with: t) { d, rp, e in
                                DispatchQueue.main.async {
                                    let c = (rp as? HTTPURLResponse)?.statusCode ?? 0
                                    guard e == nil, let d, (200..<300).contains(c),
                                          let jt = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                                          let texto = jt["text"] as? String else {
                                        completion(.failure(ScribeError.sinTexto)); return
                                    }
                                    completion(.success(texto.trimmingCharacters(in: .whitespacesAndNewlines)))
                                }
                            }.resume()   // sin esto la descarga no arranca y nadie contesta
                        }
                    }
                }
            }
        }
    }
}

/// Azure AI Speech — Fast Transcription (un solo POST). Muy buen español, único
/// con locale es-EC (Ecuador) nativo. Necesita la key y la REGIÓN (va en la URL,
/// como el Account ID de Cloudflare). Respuesta: combinedPhrases[].text.
enum AzureTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("AZURE_SPEECH_KEY")
        let region = Config.azureSpeechRegion()
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la key de Azure Speech — ponla en Configuración → Modelos"))); return
        }
        guard !region.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la región de Azure (ej. eastus) — ponla en Configuración → Modelos"))); return
        }
        let url = "https://\(region).api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2024-11-15"
        let boundary = "BtoDicta-\(UUID().uuidString)"
        // Prioriza español de Ecuador y variantes LATAM (deja que Azure elija).
        let definition = "{\"locales\":[\"es-EC\",\"es-MX\",\"es-CO\",\"es-ES\"],\"profanityFilterMode\":\"None\"}"
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: [],
                                                   nombreCampo: "audio",
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav,
                                                   camposDespues: [("definition", definition, "application/json")])
        } catch { completion(.failure(error)); return }
        var req = URLRequest(url: URL(string: url)!); req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        CuerpoMultipart.subir(req, cuerpo: cuerpo) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let frases = json["combinedPhrases"] as? [[String: Any]] else {
                    completion(.failure(ScribeError.sinTexto)); return
                }
                let texto = frases.compactMap { $0["text"] as? String }.joined(separator: " ")
                texto.isEmpty ? completion(.failure(ScribeError.sinTexto))
                              : completion(.success(texto.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// AssemblyAI — free credits. Por lotes: subir bytes → crear transcript →
/// sondear /transcript/{id} hasta status=completed.
enum AssemblyAITranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("ASSEMBLYAI_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de AssemblyAI — ponla en Configuración → Modelos"))); return
        }
        let auth = ["Authorization": key]
        // 1) subir el audio crudo
        RawAudioSTT.run(url: "https://api.assemblyai.com/v2/upload",
                        headers: auth, contentType: "application/octet-stream", wav: wav,
                        timeout: 30, extraer: { $0["upload_url"] as? String }) { r in
            switch r {
            case .failure(let e): completion(.failure(e))
            case .success(let uploadURL):
                // 2) crear el job de transcripción
                var cuerpo: [String: Any] = ["audio_url": uploadURL, "language_code": "es"]
                // `speech_model` quedó DEPRECADO: la API responde 400 desde ago-2026 (2 873
                // fallos en dos días). Ahora va `speech_models`, lista en orden de
                // preferencia. Alias viejos: best → universal-3-5-pro, nano → universal-2.
                // Valores que la API acepta HOY: universal-3-5-pro y universal-2. Alias
                // viejos (catálogo/config guardada) se mapean para no caer en 400.
                let modelos: [String]
                switch model {
                case "", "best", "universal-3-pro", "universal", "slam-1":
                    modelos = ["universal-3-5-pro", "universal-2"]
                case "nano":
                    modelos = ["universal-2"]
                default:
                    modelos = [model, "universal-2"]
                }
                cuerpo["speech_models"] = modelos
                postJSON(url: "https://api.assemblyai.com/v2/transcript",
                         headers: auth, cuerpo: cuerpo) { r2 in
                    switch r2 {
                    case .failure(let e): DispatchQueue.main.async { completion(.failure(e)) }
                    case .success(let json):
                        guard let id = json["id"] as? String else {
                            DispatchQueue.main.async { completion(.failure(ScribeError.sinTexto)) }; return
                        }
                        // 3) sondear
                        STTPoll.sondear(url: "https://api.assemblyai.com/v2/transcript/\(id)", headers: auth,
                                        evaluar: { j in
                            switch j["status"] as? String {
                            case "completed": return .listo((j["text"] as? String) ?? "")
                            case "error":     return .error((j["error"] as? String) ?? "AssemblyAI falló")
                            default:          return .esperar
                            }
                        }, completion: completion)
                    }
                }
            }
        }
    }
}

/// Gladia — 10 h/mes gratis. Por lotes: subir (multipart) → pre-recorded →
/// sondear result_url hasta status=done.
enum GladiaTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("GLADIA_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Gladia — ponla en Configuración → Modelos"))); return
        }
        let auth = ["x-gladia-key": key]
        // 1) subir el audio (multipart)
        let boundary = "BtoDicta-\(UUID().uuidString)"
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: [],
                                                   nombreCampo: "audio",
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }
        var up = URLRequest(url: URL(string: "https://api.gladia.io/v2/upload")!); up.httpMethod = "POST"; up.timeoutInterval = 30
        up.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        up.setValue(key, forHTTPHeaderField: "x-gladia-key")
        CuerpoMultipart.subir(up, cuerpo: cuerpo) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard err == nil, let data, (200..<300).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let audioURL = json["audio_url"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                }
                return
            }
            // 2) crear el job
            postJSON(url: "https://api.gladia.io/v2/pre-recorded",
                     headers: auth, cuerpo: ["audio_url": audioURL, "language": "es"]) { r2 in
                switch r2 {
                case .failure(let e): DispatchQueue.main.async { completion(.failure(e)) }
                case .success(let j):
                    guard let resultURL = j["result_url"] as? String else {
                        DispatchQueue.main.async { completion(.failure(ScribeError.sinTexto)) }; return
                    }
                    // 3) sondear
                    STTPoll.sondear(url: resultURL, headers: auth, evaluar: { jj in
                        switch jj["status"] as? String {
                        case "done":
                            let result = jj["result"] as? [String: Any]
                            let trans = result?["transcription"] as? [String: Any]
                            return .listo((trans?["full_transcript"] as? String) ?? "")
                        case "error": return .error("Gladia falló")
                        default:      return .esperar
                        }
                    }, completion: completion)
                }
            }
        }
    }
}

/// Speechmatics — 480 min/mes gratis. Por lotes: crear job (multipart config +
/// audio) → sondear /jobs/{id} hasta done → bajar el transcript en texto.
enum SpeechmaticsTranscribe {
    static func run(wav: CuerpoMultipart.Origen, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let key = ApiKeys.get("SPEECHMATICS_API_KEY")
        guard !key.isEmpty else {
            completion(.failure(ScribeError.ws("Falta la API key de Speechmatics — ponla en Configuración → Modelos"))); return
        }
        let punto = model.isEmpty ? "standard" : model   // "standard" | "enhanced"
        let config = "{\"type\":\"transcription\",\"transcription_config\":{\"language\":\"es\",\"operating_point\":\"\(punto)\"}}"
        let boundary = "BtoDicta-\(UUID().uuidString)"
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary,
                                                   campos: [("config", config)],
                                                   nombreCampo: "data_file",
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }
        var req = URLRequest(url: URL(string: "https://asr.api.speechmatics.com/v2/jobs")!); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        CuerpoMultipart.subir(req, cuerpo: cuerpo) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard err == nil, let data, (200..<300).contains(code),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                }
                return
            }
            let auth = ["Authorization": "Bearer \(key)"]
            // sondear el estado del job
            STTPoll.sondear(url: "https://asr.api.speechmatics.com/v2/jobs/\(id)", headers: auth, evaluar: { jj in
                let job = jj["job"] as? [String: Any]
                switch job?["status"] as? String {
                case "done":    return .listo("__LISTO__")   // señal: bajar el transcript
                case "rejected": return .error("Speechmatics rechazó el audio")
                default:        return .esperar
                }
            }) { r in
                switch r {
                case .failure(let e): completion(.failure(e))
                case .success:
                    // bajar el transcript en texto plano
                    var t = URLRequest(url: URL(string: "https://asr.api.speechmatics.com/v2/jobs/\(id)/transcript?format=txt")!)
                    t.timeoutInterval = 15
                    t.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    RedDictado.sesion().dataTask(with: t) { d, rp, e in
                        DispatchQueue.main.async {
                            let c = (rp as? HTTPURLResponse)?.statusCode ?? 0
                            guard e == nil, let d, (200..<300).contains(c),
                                  let texto = String(data: d, encoding: .utf8) else {
                                completion(.failure(ScribeError.sinTexto)); return
                            }
                            completion(.success(texto.trimmingCharacters(in: .whitespacesAndNewlines)))
                        }
                    }.resume()   // sin esto la descarga no arranca y nadie contesta
                }
            }
        }
    }
}

/// Transcribe con un GATEWAY personalizado marcado "para voz". Asume que expone
/// /audio/transcriptions estilo OpenAI (multipart). Respeta su esquema de auth
/// (Authorization / x-api-key / encabezado propio + headers extra) y es
/// FAIL-CLOSED: no manda la key ni los headers por http sin cifrar.
enum GatewayTranscribe {
    static func run(gw: IAPersonalizada, wav: CuerpoMultipart.Origen, completion: @escaping (Result<String, Error>) -> Void) {
        guard !gw.base.isEmpty else { completion(.failure(ScribeError.ws("Gateway sin URL base"))); return }
        let endpoint = (gw.base.hasSuffix("/") ? gw.base : gw.base + "/") + "audio/transcriptions"
        guard let u = URL(string: endpoint) else { completion(.failure(ScribeError.ws("URL inválida"))); return }
        // Fail-closed: solo mandar secretos por https o a localhost.
        let segura = (u.scheme == "https") || ["localhost", "127.0.0.1", "::1"].contains(u.host ?? "")
        let boundary = "BtoDicta-\(UUID().uuidString)"
        var campos: [(String, String)] = []
        if !gw.modelo.isEmpty { campos.append(("model", gw.modelo)) }
        campos.append(("language", "es")); campos.append(("response_format", "json"))
        let cuerpo: CuerpoMultipart.Preparado
        do {
            cuerpo = try CuerpoMultipart.construir(boundary: boundary, campos: campos,
                                                   nombreArchivo: "audio.wav",
                                                   tipo: "audio/wav", audio: wav)
        } catch { completion(.failure(error)); return }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 20; req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if segura {
            if !gw.apiKey.isEmpty {
                req.setValue(gw.authPrefix + gw.apiKey, forHTTPHeaderField: gw.authHeader.isEmpty ? "Authorization" : gw.authHeader)
            }
            for (h, v) in gw.headers { req.setValue(v, forHTTPHeaderField: h) }
        }
        CuerpoMultipart.subir(req, cuerpo: cuerpo) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(.failure(err)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code) else {
                    completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? "")))
                    return
                }
                guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let t = j["text"] as? String else { completion(.failure(ScribeError.sinTexto)); return }
                completion(.success(t.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

/// Transcribe con un servidor LOCAL (Ollama/LM Studio) que tenga un modelo
/// whisper — vía /v1/audio/transcriptions (OpenAI-compat, sin auth). El modelo
/// lo detecta ChatIA.sttLocalModelo (detección INTELIGENTE): si el local no
/// tiene un modelo que escuche, este motor NO transcribe (y no debe ofrecerse).
enum LocalTranscribe {
    /// base ej. http://localhost:11434/v1 (ollama) o :1234/v1 (lm studio).
    static func run(base: String, model: String, wav: CuerpoMultipart.Origen, completion: @escaping (Result<String, Error>) -> Void) {
        OpenAICompatible.transcribir(endpoint: "\(base)/audio/transcriptions",
                                     key: "", model: model, wav: wav, conPrompt: false, completion: completion)
    }
}

/// Transcribe con Whisper LOCAL (whisper-cli + modelo ggml). 100% offline.
enum WhisperLocal {
    static var modelsDir: URL { Config.dir.appendingPathComponent("models") }
    /// Archivo del modelo activo (lo fija la pestaña Modelos).
    static var modeloArchivo: String {
        get { Providers.modelo(de: "whisper_local") ?? "ggml-large-v3-turbo.bin" }
        set {
            var lista = Providers.load()
            if let i = lista.firstIndex(where: { $0.id == "whisper_local" }) {
                lista[i].modelo = newValue; Providers.save(lista)
            }
        }
    }
    static var modelURL: URL { modelsDir.appendingPathComponent(modeloArchivo) }
    static var cliURL: URL? {
        // 1) binario bundleado en la app  2) build local de whisper.cpp
        if let p = Bundle.main.path(forResource: "whisper-cli", ofType: nil, inDirectory: "bin") { return URL(fileURLWithPath: p) }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dev = home.appendingPathComponent("whisper.cpp/build/bin/whisper-cli")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    static var disponible: Bool {
        cliURL != nil && FileManager.default.fileExists(atPath: modelURL.path)
    }

    static func run(wav: CuerpoMultipart.Origen, completion: @escaping (Result<String, Error>) -> Void) {
        // Vía rápida: server residente ya precalentado (modelo en memoria).
        if WhisperServer.corriendo {
            // Si el audio está en disco, el servidor local lo sube desde ahí.
            let enviar: (@escaping (Result<String, Error>) -> Void) -> Void = { cb in
                if let url = wav.archivoURL { WhisperServer.transcribe(wavURL: url, completion: cb) }
                else { WhisperServer.transcribe(wav: wav.leer(), completion: cb) }
            }
            enviar { r in
                switch r {
                case .success(let texto): completion(.success(texto))
                case .failure:
                    Log.log(.ia, "server local falló → whisper-cli de respaldo")
                    runCLI(wav: wav.leer(), completion: completion)
                }
            }
            return
        }
        runCLI(wav: wav.leer(), completion: completion)
    }

    /// Vía clásica: proceso whisper-cli efímero (carga modelo, transcribe, muere).
    private static func runCLI(wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let cli = cliURL else { completion(.failure(ScribeError.ws("whisper-cli no encontrado"))); return }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            completion(.failure(ScribeError.ws("Falta el modelo local — descárgalo en Modelos"))); return
        }
        DispatchQueue.global().async {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("beto-\(UUID().uuidString).wav")
            try? wav.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let task = Process()
            task.executableURL = cli
            var args = ["-m", modelURL.path, "-l", "es", "-nt", "-otxt", "-f", tmp.path,
                        "-of", tmp.deletingPathExtension().path]
            // Glosario: whisper.cpp acepta --prompt para sesgar el vocabulario
            let glosario = Config.glosarioPrompt()
            if !glosario.isEmpty { args += ["--prompt", glosario] }
            task.arguments = args
            let pipe = Pipe(); task.standardError = pipe; task.standardOutput = Pipe()
            do {
                try task.run(); task.waitUntilExit()
                let txtURL = tmp.deletingPathExtension().appendingPathExtension("txt")
                let texto = (try? String(contentsOf: txtURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try? FileManager.default.removeItem(at: txtURL)
                DispatchQueue.main.async {
                    texto.isEmpty ? completion(.failure(ScribeError.sinTexto)) : completion(.success(texto))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

// MARK: - Orquestador de failover (batch)

enum Failover {
    /// Intenta transcribir el WAV recorriendo la cadena de proveedores activos.
    /// Devuelve el primer éxito, o el último error si todos fallan.
    /// completion: (texto, nombre del proveedor, modelo usado).
    static func transcribe(wav: Data, completion: @escaping (Result<(String, String, String), Error>) -> Void) {
        transcribe(wav: .datos(wav), completion: completion)
    }

    /// La misma cascada partiendo de un ARCHIVO. Es el camino que evita cargar
    /// el dictado en memoria: cada motor sube desde disco.
    static func transcribe(wav: CuerpoMultipart.Origen,
                           completion: @escaping (Result<(String, String, String), Error>) -> Void) {
        let cadena = Providers.cadena()
        intentar(wav: wav, cadena: cadena, idx: 0, ultimoError: nil, completion: completion)
    }

    /// Igual, pero sobre una cadena dada: sirve para fijar un único proveedor
    /// sin perder su configuración de modelo y credenciales.
    static func transcribe(wav: Data, cadena: [Provider],
                           completion: @escaping (Result<(String, String, String), Error>) -> Void) {
        intentar(wav: .datos(wav), cadena: cadena, idx: 0, ultimoError: nil, completion: completion)
    }

    static func transcribe(wav: CuerpoMultipart.Origen, cadena: [Provider],
                           completion: @escaping (Result<(String, String, String), Error>) -> Void) {
        intentar(wav: wav, cadena: cadena, idx: 0, ultimoError: nil, completion: completion)
    }

    private static func intentar(wav: CuerpoMultipart.Origen, cadena: [Provider], idx: Int,
                                 ultimoError: Error?, completion: @escaping (Result<(String, String, String), Error>) -> Void) {
        guard idx < cadena.count else {
            completion(.failure(ultimoError ?? ScribeError.sinTexto)); return
        }
        let p = cadena[idx]
        // Red hacia ElevenLabs recién caída: saltarlo sin gastar su timeout —
        // el siguiente de la cascada responde ya.
        if p.id == "elevenlabs" && StreamClient.enCuarentena {
            Log.log(.ia, "failover: ElevenLabs en cuarentena breve (su streaming cayó hace menos de 1 min) → siguiente")
            intentar(wav: wav, cadena: cadena, idx: idx + 1, ultimoError: ultimoError, completion: completion)
            return
        }
        // Fallo DETERMINISTA reciente (4xx: key/cuota/parámetro deprecado): se salta sin
        // gastar la llamada ni sumar latencia. Ver CuarentenaSTT (avisa una vez).
        if CuarentenaSTT.activa(p.id) {
            let d = CuarentenaSTT.detalle(p.id)
            intentar(wav: wav, cadena: cadena, idx: idx + 1,
                     ultimoError: ultimoError ?? ScribeError.http(d?.codigo ?? 0, "\(p.nombre) \(d?.texto ?? "en cuarentena")"),
                     completion: completion)
            return
        }
        Log.log(.ia, "failover: intentando \(p.nombre) (#\(idx + 1))")
        // Modelo efectivo por proveedor (el que fija el costo real).
        let modeloUsado: String
        switch p.id {
        case "elevenlabs": modeloUsado = elevenModel(p)
        case "apple_speech": modeloUsado = p.modelo ?? "es-EC"
        case "groq": modeloUsado = p.modelo ?? "whisper-large-v3"
        case "openai": modeloUsado = p.modelo ?? "gpt-4o-mini-transcribe"
        case "mistral": modeloUsado = p.modelo ?? "voxtral-mini-latest"
        case "fireworks": modeloUsado = p.modelo ?? "whisper-v3"
        case "hf": modeloUsado = p.modelo ?? "openai/whisper-large-v3"
        case "deepgram": modeloUsado = p.modelo ?? "nova-3"
        case "assemblyai": modeloUsado = p.modelo ?? "best"
        case "fish": modeloUsado = p.modelo ?? "transcribe-1"
        case "gladia": modeloUsado = p.modelo ?? "default"
        case "speechmatics": modeloUsado = p.modelo ?? "standard"
        case "cloudflare_stt": modeloUsado = p.modelo ?? "@cf/openai/whisper"
        case "soniox": modeloUsado = p.modelo ?? "stt-async-v5"
        case "azure": modeloUsado = p.modelo ?? "azure-fast"
        case "ollama_stt": modeloUsado = ChatIA.sttLocalModelo["ollama"] ?? ""
        case "lmstudio_stt": modeloUsado = ChatIA.sttLocalModelo["lmstudio"] ?? ""
        case let g where g.hasPrefix("gw:"): modeloUsado = p.modelo ?? ""
        default: modeloUsado = p.modelo ?? ""
        }

        // Se mide SIEMPRE, no solo cuando falla: lo que interesa es cuánto
        // tarda un motor cuando funciona, que es lo que decide si merece ir
        // primero en la cascada.
        let arranque = Date()
        let siguiente: (Result<String, Error>) -> Void = { r in
            let ms = Int(Date().timeIntervalSince(arranque) * 1000)
            switch r {
            case .success(let texto):
                LatenciaMotores.anotar(p.nombre, ms: ms)
                Log.log(.ia, "failover: \(p.nombre) OK en \(ms) ms")
                CuarentenaSTT.limpiar(p.id)
                completion(.success((texto, p.nombre, modeloUsado)))
            case .failure(let e):
                Log.log(.ia, "failover: \(p.nombre) falló (\(e.localizedDescription)) → siguiente")
                CuarentenaSTT.registrar(p.id, nombre: p.nombre, error: e)
                intentar(wav: wav, cadena: cadena, idx: idx + 1, ultimoError: e, completion: completion)
            }
        }
        // Un SOLO punto de envío por motor. Troceo lo usa para reintentar el
        // mismo motor con el audio partido cuando el techo del proveedor —que
        // nadie declara igual— rechaza el envío entero.
        let enviarAlMotor: (CuerpoMultipart.Origen, @escaping (Result<String, Error>) -> Void) -> Void = { fuente, cb in
            switch p.id {

            case "elevenlabs": transcribeBatch(wav: fuente, model: elevenModel(p)) { cb($0) }
            case "groq": GroqTranscribe.run(wav: fuente, model: p.modelo ?? "whisper-large-v3") { cb($0) }
            case "apple_speech": AppleSpeechSTT.run(wav: fuente, idioma: p.modelo) { cb($0) }
            case "whisper_local": WhisperLocal.run(wav: fuente) { cb($0) }
            case "voxtral_local":
                // La familia Voxtral tiene dos motores: el Mini 3B corre en
                // llama.cpp (server residente); el Realtime 4B en transcribe.cpp.
                if TcppStreamClient.esModeloStreaming(p.modelo ?? "") {
                    TranscribeCpp.run(wav: fuente, modelo: p.modelo ?? "") { cb($0) }
                } else if VoxtralServer.corriendo {
                    VoxtralServer.transcribe(wav: fuente.leer()) { cb($0) }
                } else if VoxtralServer.diagnostico == nil {
                    // No precalentó (p.ej. se activó recién): arrancar y transcribir.
                    VoxtralServer.precalentar()
                    VoxtralServer.transcribe(wav: fuente.leer()) { cb($0) }
                } else {
                    cb(.failure(ScribeError.ws(VoxtralServer.diagnostico ?? "voxtral no disponible")))
                }
            case "nemotron_local", "canary_local":
                TranscribeCpp.run(wav: fuente, modelo: p.modelo ?? "") { cb($0) }
            case "openai":
                OpenAITranscribe.run(wav: fuente, model: p.modelo ?? "gpt-4o-mini-transcribe") { cb($0) }
            case "mistral":
                MistralTranscribe.run(wav: fuente, model: p.modelo ?? "voxtral-mini-latest") { cb($0) }
            case "fireworks":
                FireworksTranscribe.run(wav: fuente, model: p.modelo ?? "whisper-v3") { cb($0) }
            case "hf":
                HFTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "deepgram":
                DeepgramTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "assemblyai":
                AssemblyAITranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "fish":
                FishTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "gladia":
                GladiaTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "speechmatics":
                SpeechmaticsTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "cloudflare_stt":
                CloudflareTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "soniox":
                SonioxTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "azure":
                AzureTranscribe.run(wav: fuente, model: p.modelo ?? "") { cb($0) }
            case "ollama_stt":
                // Detección inteligente: solo si Ollama tiene un modelo que escuche.
                if let m = ChatIA.sttLocalModelo["ollama"] {
                    LocalTranscribe.run(base: "http://localhost:11434/v1", model: m, wav: fuente) { cb($0) }
                } else { cb(.failure(ScribeError.ws("Ollama no tiene un modelo whisper (haz: ollama pull whisper)"))) }
            case "lmstudio_stt":
                if let m = ChatIA.sttLocalModelo["lmstudio"] {
                    LocalTranscribe.run(base: "http://localhost:1234/v1", model: m, wav: fuente) { cb($0) }
                } else { cb(.failure(ScribeError.ws("LM Studio no tiene un modelo whisper cargado"))) }
            case let g where g.hasPrefix("gw:"):
                // Gateway personalizado marcado "para voz": busca su config y transcribe.
                let uuid = String(g.dropFirst(3))
                if let gw = PersonalizadaStore.cargar().first(where: { $0.id == uuid }) {
                    GatewayTranscribe.run(gw: gw, wav: fuente) { cb($0) }
                } else { cb(.failure(ScribeError.ws("El gateway de voz ya no existe"))) }
            default: cb(.failure(ScribeError.sinTexto))
            }
        }
        Troceo.enviarPartiendo(wav, motor: p.id, enviar: enviarAlMotor) { siguiente($0) }
    }

    private static func elevenModel(_ p: Provider) -> String {
        let m = p.modelo ?? "scribe_v2"
        return m == "scribe_v2_realtime" ? "scribe_v2" : m
    }
}
