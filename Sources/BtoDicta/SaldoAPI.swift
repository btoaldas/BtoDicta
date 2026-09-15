import Foundation
import UserNotifications

// MARK: - Cuánto te queda en cada proveedor
//
// Hoy uno se entera de que se acabó el saldo cuando un dictado falla a mitad de
// camino. Tres de los proveedores que usa BtoDicta sí publican su saldo, así que
// se puede saber ANTES.
//
// Los que no lo publican —OpenAI, Groq, Anthropic— se dicen como tales. Estimar
// su consumo por los tokens que llevamos contados sería inventar una cifra que
// no cuadra con la factura, y una cifra inventada es peor que un «no se puede
// saber»: se confía en ella.
enum SaldoAPI {

    struct Saldo: Identifiable {
        let id: String            // id del proveedor
        let nombre: String
        /// Lo que queda, en la unidad del proveedor.
        let restante: Double
        /// El total contratado, si lo hay. 0 = no aplica (saldo prepago).
        let total: Double
        let unidad: String        // "USD" | "caracteres"
        let consultado: Date
        let error: String?

        /// Fracción que queda, 0-1. `nil` si el proveedor no da un total contra
        /// el que comparar (un saldo en dinero no tiene «porcentaje»).
        var fraccion: Double? {
            guard total > 0 else { return nil }
            return max(0, min(1, restante / total))
        }

        var texto: String {
            if let error { return "no se pudo consultar — \(error)" }
            if unidad == "caracteres" {
                return "\(Int(restante).formatted()) de \(Int(total).formatted()) caracteres"
            }
            if unidad == "h usadas" {
                return String(format: "%.2f h consumidas (el plan no publica su tope)", restante)
            }
            if total > 0 {
                return String(format: "%.2f de %.2f %@", restante, total, "USD")
            }
            return String(format: "%.2f %@", restante, unidad)
        }
    }

    /// Proveedores que publican saldo, con la clave que necesitan.
    /// Cada uno lo publica a su manera, y varios no lo publican en absoluto.
    /// Esta lista sale de PROBARLOS uno por uno con claves reales el 2026-09-15,
    /// no de la documentación: Deepgram y Anthropic sí tienen punto de consulta
    /// pero exigen una clave de administrador, así que para una clave normal es
    /// como si no existiera.
    static let consultables: [(id: String, nombre: String, keyEnv: String)] = [
        ("elevenlabs", "ElevenLabs", "ELEVENLABS_API_KEY"),
        ("fish", "Fish Audio", "FISH_API_KEY"),
        ("deepseek", "DeepSeek", "DEEPSEEK_API_KEY"),
        ("openrouter", "OpenRouter", "OPENROUTER_API_KEY"),
        ("novita", "Novita AI", "NOVITA_API_KEY"),
        ("speechmatics", "Speechmatics", "SPEECHMATICS_API_KEY"),
    ]

    /// Los que NO publican saldo se enseñan igual, con una PRUEBA DE VIDA: es
    /// la pregunta que uno se hace de verdad («¿está caído?»), y esa sí tiene
    /// respuesta para todos. Se consulta su listado de modelos, que es barato,
    /// no cuesta tokens y sirve además para saber si la clave sigue siendo
    /// buena.
    struct Vida: Identifiable {
        let id: String
        let nombre: String
        let familia: String      // "IA" | "Dictado" | "Voz"
        let vivo: Bool?          // nil = no se pudo probar
        let ms: Int
        let detalle: String
    }

    private static var cacheVida: [String: Vida] = [:]
    static func vidasCacheadas() -> [Vida] {
        candado.lock(); defer { candado.unlock() }
        return cacheVida.values.sorted { ($0.familia, $0.nombre) < ($1.familia, $1.nombre) }
    }

    /// Prueba de vida de TODO lo que tenga clave puesta: las IA de chat por su
    /// listado de modelos, y los motores de dictado y voz por el suyo.
    static func probarTodo(completion: @escaping ([Vida]) -> Void) {
        var pruebas: [(id: String, nombre: String, familia: String, req: URLRequest)] = []

        // IA de chat: la propia configuración ya trae base y autenticación.
        for ia in ChatIA.conectadas where !ia.local && !ia.esCuentaCodex {
            guard let clave = ia.key, !clave.isEmpty,
                  let u = URL(string: "\(ia.base)/models") else { continue }
            var r = URLRequest(url: u); r.timeoutInterval = 10
            r.setValue(ia.authPrefix + clave, forHTTPHeaderField: ia.authHeader)
            for (k, v) in ia.headersExtra { r.setValue(v, forHTTPHeaderField: k) }
            pruebas.append((ia.id, ia.nombre, "IA", r))
        }

        // Dictado y voz: listados propios de cada casa.
        let otros: [(String, String, String, String, String, String)] = [
            // id, nombre, familia, url, cabecera, prefijo
            ("deepgram", "Deepgram", "Dictado", "https://api.deepgram.com/v1/projects", "Authorization", "Token "),
            ("fireworks", "Fireworks", "Dictado", "https://api.fireworks.ai/v1/accounts", "Authorization", "Bearer "),
            ("soniox", "Soniox", "Dictado", "https://api.soniox.com/v1/models", "Authorization", "Bearer "),
            ("speechmatics", "Speechmatics", "Dictado", "https://asr.api.speechmatics.com/v2/jobs?limit=1", "Authorization", "Bearer "),
            ("assemblyai", "AssemblyAI", "Dictado", "https://api.assemblyai.com/v2/transcript?limit=1", "authorization", ""),
            ("gladia", "Gladia", "Dictado", "https://api.gladia.io/v2/pre-recorded", "x-gladia-key", ""),
            ("elevenlabs", "ElevenLabs", "Voz", "https://api.elevenlabs.io/v1/voices", "xi-api-key", ""),
            ("fish", "Fish Audio", "Voz", "https://api.fish.audio/model?self=true&page_size=1", "Authorization", "Bearer "),
        ]
        let claves = ["deepgram": "DEEPGRAM_API_KEY", "assemblyai": "ASSEMBLYAI_API_KEY",
                      "gladia": "GLADIA_API_KEY", "elevenlabs": "ELEVENLABS_API_KEY",
                      "fish": "FISH_API_KEY", "fireworks": "FIREWORKS_API_KEY",
                      "soniox": "SONIOX_API_KEY", "speechmatics": "SPEECHMATICS_API_KEY"]
        for (id, nombre, familia, url, cab, pre) in otros {
            let clave = ApiKeys.get(claves[id] ?? "")
            guard !clave.isEmpty, let u = URL(string: url) else { continue }
            var r = URLRequest(url: u); r.timeoutInterval = 10
            r.setValue(pre + clave, forHTTPHeaderField: cab)
            pruebas.append((id, nombre, familia, r))
        }

        guard !pruebas.isEmpty else { completion([]); return }
        let grupo = DispatchGroup()
        var salida: [Vida] = []
        let mutex = NSLock()
        for p in pruebas {
            grupo.enter()
            let t0 = Date()
            URLSession.shared.dataTask(with: p.req) { datos, resp, err in
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                // El cuerpo del error es donde los proveedores dicen lo que de
                // verdad pasa. Fireworks, por ejemplo, contesta «Account …
                // is suspended, possibly due to reaching the monthly spending
                // limit»: eso vale más que un «HTTP 412» y solo se sabe leyendo.
                let cuerpo = datos.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                func motivoDelServidor() -> String? {
                    let b = cuerpo.lowercased()
                    for (marca, texto) in [("suspend", "cuenta suspendida"),
                                           ("insufficient", "sin saldo"),
                                           ("quota", "cuota agotada"),
                                           ("expired", "clave caducada"),
                                           ("past due", "factura pendiente")]
                    where b.contains(marca) { return texto }
                    return nil
                }
                let v: Vida
                if err != nil {
                    v = Vida(id: p.id, nombre: p.nombre, familia: p.familia, vivo: false, ms: ms,
                             detalle: "no responde")
                } else if let m = motivoDelServidor() {
                    v = Vida(id: p.id, nombre: p.nombre, familia: p.familia, vivo: false, ms: ms,
                             detalle: m)
                } else if code == 401 || code == 403 {
                    v = Vida(id: p.id, nombre: p.nombre, familia: p.familia, vivo: false, ms: ms,
                             detalle: "la clave ya no vale (HTTP \(code))")
                } else if (200..<500).contains(code) {
                    // Un 404 o un 400 también prueban que el servicio contesta.
                    v = Vida(id: p.id, nombre: p.nombre, familia: p.familia, vivo: true, ms: ms,
                             detalle: "responde en \(ms) ms")
                } else {
                    v = Vida(id: p.id, nombre: p.nombre, familia: p.familia, vivo: false, ms: ms,
                             detalle: "HTTP \(code)")
                }
                mutex.lock(); salida.append(v); mutex.unlock()
                grupo.leave()
            }.resume()
        }
        grupo.notify(queue: .main) {
            candado.lock()
            for v in salida { cacheVida[v.id] = v }
            candado.unlock()
            completion(salida.sorted { ($0.familia, $0.nombre) < ($1.familia, $1.nombre) })
        }
    }

    // MARK: Caché

    private static var cache: [String: Saldo] = [:]
    private static var ultimaConsulta = Date.distantPast
    private static let candado = NSLock()

    static func cacheados() -> [Saldo] {
        candado.lock(); defer { candado.unlock() }
        return consultables.compactMap { cache[$0.id] }
    }

    /// Consulta los saldos. Nunca en el camino del dictado: esto va de fondo y,
    /// si un proveedor no contesta, los demás se ven igual.
    static func consultar(forzar: Bool = false, completion: @escaping ([Saldo]) -> Void) {
        candado.lock()
        let reciente = Date().timeIntervalSince(ultimaConsulta) < 1800   // media hora
        candado.unlock()
        if reciente && !forzar { completion(cacheados()); return }
        candado.lock(); ultimaConsulta = Date(); candado.unlock()

        let grupo = DispatchGroup()
        var resultados: [Saldo] = []
        let mutex = NSLock()
        for p in consultables {
            let clave = ApiKeys.get(p.keyEnv)
            guard !clave.isEmpty else { continue }
            grupo.enter()
            uno(p, clave: clave) { s in
                mutex.lock(); resultados.append(s); mutex.unlock()
                grupo.leave()
            }
        }
        grupo.notify(queue: .main) {
            candado.lock()
            for s in resultados { cache[s.id] = s }
            candado.unlock()
            avisarSiHaceFalta(resultados)
            completion(resultados.sorted { $0.nombre < $1.nombre })
        }
    }

    private static func uno(_ p: (id: String, nombre: String, keyEnv: String), clave: String,
                            completion: @escaping (Saldo) -> Void) {
        func fallo(_ q: String) -> Saldo {
            Saldo(id: p.id, nombre: p.nombre, restante: 0, total: 0,
                  unidad: "", consultado: Date(), error: q)
        }
        var req: URLRequest
        switch p.id {
        case "elevenlabs":
            req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
            req.setValue(clave, forHTTPHeaderField: "xi-api-key")
        case "fish":
            req = URLRequest(url: URL(string: "https://api.fish.audio/wallet/self/api-credit")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        case "deepseek":
            req = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        case "openrouter":
            req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/credits")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        case "novita":
            req = URLRequest(url: URL(string: "https://api.novita.ai/v3/user")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        case "speechmatics":
            req = URLRequest(url: URL(string: "https://asr.api.speechmatics.com/v2/usage")!)
            req.setValue("Bearer \(clave)", forHTTPHeaderField: "Authorization")
        default:
            completion(fallo("proveedor desconocido")); return
        }
        req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err { completion(fallo(err.localizedDescription)); return }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard let data, (200..<300).contains(code),
                      let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(fallo(code == 401 ? "la clave no es válida" : "HTTP \(code)")); return
                }
                switch p.id {
                case "elevenlabs":
                    // Da lo CONSUMIDO y el tope; lo que queda es la resta.
                    let usado = (j["character_count"] as? Double) ?? 0
                    let tope = (j["character_limit"] as? Double) ?? 0
                    completion(Saldo(id: p.id, nombre: p.nombre, restante: max(0, tope - usado),
                                     total: tope, unidad: "caracteres", consultado: Date(), error: nil))
                case "fish":
                    let c = Double((j["credit"] as? String) ?? "") ?? (j["credit"] as? Double) ?? 0
                    completion(Saldo(id: p.id, nombre: p.nombre, restante: c, total: 0,
                                     unidad: "USD", consultado: Date(), error: nil))
                case "deepseek":
                    let infos = (j["balance_infos"] as? [[String: Any]])?.first
                    let t = Double((infos?["total_balance"] as? String) ?? "") ?? 0
                    completion(Saldo(id: p.id, nombre: p.nombre, restante: t, total: 0,
                                     unidad: (infos?["currency"] as? String) ?? "USD",
                                     consultado: Date(), error: nil))
                case "openrouter":
                    // Da el total comprado y el consumido; lo que queda es la resta.
                    let d = j["data"] as? [String: Any]
                    let total = (d?["total_credits"] as? Double) ?? 0
                    let usado = (d?["total_usage"] as? Double) ?? 0
                    completion(Saldo(id: p.id, nombre: p.nombre, restante: max(0, total - usado),
                                     total: total, unidad: "USD", consultado: Date(), error: nil))
                case "novita":
                    completion(Saldo(id: p.id, nombre: p.nombre,
                                     restante: (j["credit_balance"] as? Double) ?? 0,
                                     total: 0, unidad: "USD", consultado: Date(), error: nil))
                case "speechmatics":
                    // No publica el tope del plan, solo lo consumido. Se enseña
                    // eso tal cual: media verdad medida vale más que un
                    // porcentaje inventado.
                    let horas = ((j["details"] as? [[String: Any]]) ?? [])
                        .compactMap { $0["duration_hrs"] as? Double }.reduce(0, +)
                    completion(Saldo(id: p.id, nombre: p.nombre, restante: horas, total: 0,
                                     unidad: "h usadas", consultado: Date(), error: nil))
                default:
                    completion(fallo("sin lector para este proveedor"))
                }
            }
        }.resume()
    }

    // MARK: Aviso

    private static var avisado: [String: String] = [:]   // id → "yyyy-MM-dd"

    /// Avisa UNA vez al día por proveedor. Un aviso que se repite en cada
    /// consulta deja de leerse a la tercera.
    private static func avisarSiHaceFalta(_ saldos: [Saldo]) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let hoy = f.string(from: Date())
        for s in saldos where s.error == nil {
            guard estaBajo(s) else { avisado[s.id] = nil; continue }
            guard avisado[s.id] != hoy else { continue }
            avisado[s.id] = hoy
            let aviso = s.restante <= 0
                ? "\(s.nombre) se quedó SIN saldo (\(s.texto))"
                : "a \(s.nombre) le queda poco: \(s.texto)"
            Log.log(.ia, "saldo: \(aviso)")
            NotificacionSaldo.mostrar(titulo: "BtoDicta — saldo bajo", cuerpo: aviso)
        }
    }

    /// ¿Está por debajo del umbral? Con tope conocido se mira el porcentaje; con
    /// saldo en dinero, una cantidad mínima.
    static func estaBajo(_ s: Saldo) -> Bool {
        // Un contador de consumo sin tope conocido no se puede agotar: avisar
        // por él sería avisar siempre.
        guard s.unidad != "h usadas" else { return false }
        if let fr = s.fraccion { return fr <= Config.saldoAvisoFraccion() }
        return s.restante <= Config.saldoAvisoMinimoUSD()
    }
}

/// Aviso del sistema, separado para poder probar el resto sin abrir ventanas.
enum NotificacionSaldo {
    static var mostrarReal = true
    private(set) static var ultimo: (titulo: String, cuerpo: String)?

    static func mostrar(titulo: String, cuerpo: String) {
        ultimo = (titulo, cuerpo)
        Log.log(.sistema, "aviso: \(titulo) — \(cuerpo)")
        guard mostrarReal, Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        let req = UNNotificationRequest(identifier: "saldo-\(UUID().uuidString)",
                                        content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
