import Foundation
import CryptoKit

// MARK: - Caché estática de frases comunes
//
// Las frases fijas que la app dice a menudo (por ejemplo «Resumen del día. No tienes
// tareas pendientes.») se generan UNA vez con la voz de ElevenLabs configurada y
// el modelo con expresiones, y se guardan en `~/.btodicta/frases/`. Después se
// reproducen desde disco: sin internet, sin créditos y sin caer a la voz de macOS.
// El audio es dato local del usuario: nunca se versiona ni se empaqueta.

enum FrasesBeto {
    /// `texto` = lo que la app dice (clave de búsqueda); `voz` = el mismo texto con
    /// etiquetas de expresión para el modelo. Las etiquetas no se pronuncian. Mismos
    /// criterios que el skill global de voz sintética: etiquetas en inglés de la lista
    /// aprobada, `language_code` es y estabilidad natural (0,5).
    struct Frase { let texto: String; let voz: String }

    static let catalogo: [Frase] = [
        .init(texto: "Resumen del día. No tienes tareas pendientes.",
              voz: "[warm] Resumen del día. [cheerful] No tienes tareas pendientes."),
        .init(texto: "Resumen de la tarde. No tienes tareas pendientes.",
              voz: "[calm] Resumen de la tarde. [reassuring] No tienes tareas pendientes."),
        .init(texto: "No tienes tareas pendientes.",
              voz: "[cheerful] No tienes tareas pendientes."),
        .init(texto: "No tienes tareas pendientes en BtoDicta.",
              voz: "[cheerful] No tienes tareas pendientes en BtoDicta."),
        .init(texto: "No tienes tareas para hoy.",
              voz: "[cheerful] No tienes tareas para hoy."),
        .init(texto: "No tienes tareas para esta semana.",
              voz: "[cheerful] No tienes tareas para esta semana."),
        .init(texto: "Nada que hacer.", voz: "[calm] Nada que hacer."),
        .init(texto: "Respaldo listo.", voz: "[happy] Respaldo listo."),
        .init(texto: "Listo.", voz: "[cheerful] Listo."),
        .init(texto: "Hecho.", voz: "[happy] Hecho."),
        .init(texto: "Entendido.", voz: "[friendly] Entendido."),
        .init(texto: "Un momento, por favor.", voz: "[calm] Un momento, por favor."),
        .init(texto: "Encontré varios contactos. ¿A cuál quieres enviar?",
              voz: "[curious] Encontré varios contactos. ¿A cuál quieres enviar?"),
        .init(texto: "Encontré varias aplicaciones parecidas. ¿Cuál quieres abrir?",
              voz: "[curious] Encontré varias aplicaciones parecidas. ¿Cuál quieres abrir?"),
        .init(texto: "Hola. Soy BtoDicta y ya puedo hablarte con el motor que elegiste.",
              voz: "[warm] Hola. Soy BtoDicta y ya puedo hablarte con el motor que elegiste."),
    ]

    /// Minúsculas, sin signos y con espacios simples: «¿Listo?» y «listo.» coinciden.
    static func normalizar(_ s: String) -> String {
        let limpio = s.lowercased().unicodeScalars.map {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
                ? Character($0) : " "
        }
        return String(limpio).split(separator: " ").joined(separator: " ")
    }

    /// La carpeta depende de voz y modelo: al cambiarlos, la caché vieja deja de
    /// usarse sola y se regenera.
    static func carpeta() -> URL {
        Config.dir.appendingPathComponent("frases", isDirectory: true)
            .appendingPathComponent("\(Config.ttsElevenVoz())-\(Config.ttsFrasesModelo())-es",
                                    isDirectory: true)
    }

    static func archivo(_ texto: String) -> URL {
        let h = SHA256.hash(data: Data(normalizar(texto).utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return carpeta().appendingPathComponent("\(h).mp3")
    }

    /// Audio guardado para este texto, solo si es una frase del catálogo.
    static func audio(para texto: String) -> Data? {
        let n = normalizar(texto)
        guard Config.ttsFrasesCache(), catalogo.contains(where: { normalizar($0.texto) == n })
        else { return nil }
        return try? Data(contentsOf: archivo(texto))
    }

    static func faltantes() -> [Frase] {
        catalogo.filter { !FileManager.default.fileExists(atPath: archivo($0.texto).path) }
    }

    /// Genera en serie las frases que faltan. Sin red o sin clave no hace nada y se
    /// reintenta en el próximo arranque. `completion(generadas, fallidas)`.
    static func generarFaltantes(completion: ((Int, Int) -> Void)? = nil) {
        let pendientes = faltantes()
        guard Config.ttsFrasesCache(), !pendientes.isEmpty,
              let key = Config.apiKey(), !key.isEmpty else { completion?(0, 0); return }
        try? FileManager.default.createDirectory(at: carpeta(), withIntermediateDirectories: true)
        var ok = 0, fallo = 0
        func siguiente(_ i: Int) {
            guard i < pendientes.count else {
                Log.log(.ia, "frases en caché: \(ok) generadas, \(fallo) fallidas")
                completion?(ok, fallo); return
            }
            generar(pendientes[i], key: key) { data in
                if let data, (try? data.write(to: archivo(pendientes[i].texto), options: .atomic)) != nil {
                    ok += 1
                } else {
                    fallo += 1
                }
                siguiente(i + 1)
            }
        }
        siguiente(0)
    }

    private static func generar(_ f: Frase, key: String, completion: @escaping (Data?) -> Void) {
        let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(Config.ttsElevenVoz())?output_format=mp3_44100_128"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": f.voz, "model_id": Config.ttsFrasesModelo(), "language_code": "es",
            "voice_settings": ["stability": 0.5],
        ])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, code == 200, data.count > 1_000 else {
                Log.log(.ia, "frase en caché falló «\(f.texto)» (\(err?.localizedDescription ?? "HTTP \(code)"))")
                completion(nil); return
            }
            completion(data)
        }.resume()
    }
}

/// `BTODICTA_FRASESTEST=1`: prueba pura de normalización y búsqueda, sin red.
/// `BTODICTA_FRASESGEN=1`: genera las frases que falten y sale (usa red y créditos).
enum FrasesBetoQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if env["BTODICTA_FRASESTEST"] == "1" { probar() }
        if env["BTODICTA_FRASESGEN"] == "1" { generar() }
    }

    private static func probar() -> Never {
        let a = FrasesBeto.normalizar("¿Resumen del día.  No tienes tareas pendientes!")
        let b = FrasesBeto.normalizar("resumen del día no tienes tareas pendientes")
        let iguales = a == b
            && FrasesBeto.archivo("Listo.") == FrasesBeto.archivo("listo")
            && FrasesBeto.archivo("Listo.") != FrasesBeto.archivo("Hecho.")
        let unicas = Set(FrasesBeto.catalogo.map { FrasesBeto.normalizar($0.texto) }).count
            == FrasesBeto.catalogo.count
        let fuera = FrasesBeto.audio(para: "Tienes vencidas: 2.") == nil
        let ok = iguales && unicas && fuera
        print("FRASESTEST normalizar=\(iguales) unicas=\(unicas) fuera_catalogo=\(fuera) → \(ok ? "OK" : "FALLO")")
        exit(ok ? 0 : 1)
    }

    private static func generar() -> Never {
        let listo = DispatchSemaphore(value: 0)
        var res = (0, 0)
        FrasesBeto.generarFaltantes { ok, fallo in res = (ok, fallo); listo.signal() }
        listo.wait()
        let faltan = FrasesBeto.faltantes().count
        print("FRASESGEN generadas=\(res.0) fallidas=\(res.1) faltan=\(faltan) carpeta=\(FrasesBeto.carpeta().path)")
        exit(faltan == 0 ? 0 : 1)
    }
}
