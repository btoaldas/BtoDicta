import Foundation

// MARK: - Traducir al dictar (vía Groq)

/// Traduce el texto dictado al idioma configurado, conservando los términos
/// del glosario intactos (nombres propios no se traducen). Si algo falla,
/// devuelve el texto original — nunca rompe un dictado.
enum Translate {

    static func to(_ idioma: String, text: String, completion: @escaping (String) -> Void) {
        guard let ia = ChatIA.seleccionada() else {
            Log.log(.ia, "traducir: sin IA de chat conectada, texto sin traducir")
            completion(text); return
        }
        let glosario = Config.keyterms().prefix(80).joined(separator: ", ")
        let prompt = """
        Traduce el siguiente texto al \(idioma).
        - Mantén sin traducir estos nombres propios y términos técnicos: \(glosario).
        - Conserva el significado y el tono. No agregues comentarios ni notas.
        Devuelve ÚNICAMENTE la traducción.

        Texto:

        \(text)
        """

        let inicio = Date()
        if ia.esCuentaCodex {
            AgenteCodex.transformar(prompt, modelo: ia.modeloEfectivo,
                                    timeout: Config.pulidoTimeout()) { salida in
                guard let out = salida?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !out.isEmpty else {
                    Log.log(.ia, "traducir: cuenta Codex no respondió, texto sin traducir")
                    completion(text); return
                }
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                Log.log(.ia, "traducir a \(idioma) con cuenta Codex: OK en \(ms)ms")
                completion(out)
            }
            return
        }
        guard let request = ia.requestChat(prompt: prompt, temperatura: 0.2, textLen: text.count) else {
            Log.log(.ia, "traducir: no pude armar la request, texto sin traducir"); completion(text); return
        }

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                if let data, ia.fueTruncado(data) {
                    Log.log(.ia, "traducir: respuesta truncada por tope de tokens, texto sin traducir")
                    completion(text); return
                }
                guard let data,
                      let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                      let out = ia.extraerContenido(data)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !out.isEmpty else {
                    Log.log(.ia, "traducir: falló, texto sin traducir")
                    completion(text); return
                }
                let ms = Int(Date().timeIntervalSince(inicio) * 1000)
                Log.log(.ia, "traducir a \(idioma): OK en \(ms)ms")
                completion(out)
            }
        }.resume()
    }
}
