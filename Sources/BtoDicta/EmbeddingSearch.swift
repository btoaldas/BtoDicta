import Foundation

// MARK: - Búsqueda SEMÁNTICA del historial (por significado, con embeddings)
//
// La búsqueda normal del Historial es por TEXTO exacto (folding). Esta busca por
// SIGNIFICADO: convierte cada dictado y tu consulta en un vector (embedding) y
// los ordena por cercanía (coseno). Así "reunión de plata" encuentra un dictado
// sobre "presupuesto", aunque no compartan palabras.
//
// Motor por defecto: Ollama local (bge-m3) — gratis, privado, sin salir del Mac.
// Parametrizable: base + modelo (Config). Soporta Ollama (/api/embeddings) y
// cualquier API OpenAI-compat (/v1/embeddings). Opt-in (default OFF).
//
// Caché en disco (~/.btodicta/embeddings.json) por ruta+fecha: un dictado solo
// se embebe UNA vez; las siguientes búsquedas reusan el vector.

enum EmbeddingSearch {
    // Vectores de DISTINTOS motores no son comparables (dimensión/espacio
    // distintos). Cada entrada guarda con qué motor se calculó y solo se reusa
    // si coincide con el motor actual — cambiar de motor NO da cosenos basura.
    struct Entrada { let vec: [Double]; let mtime: Double; let motor: String }
    /// path del .txt → vector cacheado (+ mtime + motor).
    private static var cache: [String: Entrada] = [:]
    private static var cargado = false
    private static var cacheURL: URL { Config.dir.appendingPathComponent("embeddings.json") }

    /// Firma del motor actual (id:modelo) — clave de compatibilidad de la caché.
    static var firmaMotor: String { "\(motorActual.id):\(motorActual.modelo)" }

    static func cargarCache() {
        guard !cargado else { return }
        cargado = true
        guard let data = try? Data(contentsOf: cacheURL),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        lock.lock(); defer { lock.unlock() }
        for (k, v) in j {
            if let vec = v["v"] as? [Double], let m = v["m"] as? Double {
                cache[k] = Entrada(vec: vec, mtime: m, motor: (v["e"] as? String) ?? "")
            }
        }
    }

    private static func guardarCache() {
        // Snapshot BAJO lock (dos búsquedas solapadas mutan `cache` a la vez).
        lock.lock()
        var out: [String: [String: Any]] = [:]
        for (k, e) in cache { out[k] = ["v": e.vec, "m": e.mtime, "e": e.motor] }
        lock.unlock()
        if let d = try? JSONSerialization.data(withJSONObject: out) {
            Config.asegurarDirSeguro()
            if (try? d.write(to: cacheURL, options: .atomic)) != nil {
                Config.protegerSecreto(cacheURL)   // 0600: son vectores de tus dictados
            }
        }
    }

    // MARK: Motor (elegible — NO hardcodeado a Ollama)

    /// Un motor de embeddings. Ollama es local (sin key); los demás son de nube
    /// OpenAI-compat (/v1/embeddings). El usuario elige cuál en Ajustes→Avanzado.
    struct Motor: Identifiable {
        let id: String        // "ollama", "openai", "gemini", "mistral", "custom"
        let nombre: String
        let base: String
        let modelo: String
        let keyEnv: String    // "" = local (Ollama), sin auth
        var esOpenAICompat: Bool { base.contains("/v1") }
        var local: Bool { keyEnv.isEmpty }
    }

    /// Motores preconfigurados. El usuario solo pone la key (o tiene Ollama).
    static let motores: [Motor] = [
        Motor(id: "interno", nombre: "Interno de BtoDicta (sin instalar nada)",
              base: "http://127.0.0.1:8798/v1", modelo: "bge-m3", keyEnv: ""),
        Motor(id: "ollama", nombre: "Ollama (local, gratis)", base: "http://localhost:11434", modelo: "bge-m3", keyEnv: ""),
        Motor(id: "openai", nombre: "OpenAI (text-embedding-3-small)", base: "https://api.openai.com/v1", modelo: "text-embedding-3-small", keyEnv: "OPENAI_API_KEY"),
        Motor(id: "gemini", nombre: "Google Gemini (text-embedding-004)", base: "https://generativelanguage.googleapis.com/v1beta/openai", modelo: "text-embedding-004", keyEnv: "GEMINI_API_KEY"),
        Motor(id: "mistral", nombre: "Mistral (mistral-embed)", base: "https://api.mistral.ai/v1", modelo: "mistral-embed", keyEnv: "MISTRAL_API_KEY"),
    ]

    /// El motor elegido (Config.embeddingProveedor). "custom" usa base/modelo/key
    /// libres; si no hay elección, Ollama por defecto.
    static var motorActual: Motor {
        let id = Config.embeddingProveedor()
        if id == "custom" {
            return Motor(id: "custom", nombre: "Personalizado", base: Config.embeddingBase(),
                         modelo: Config.embeddingModelo(), keyEnv: Config.embeddingKeyEnv())
        }
        return motores.first { $0.id == id } ?? motores[0]
    }

    /// http/localhost permitido (Ollama local); nube exige https (fail-closed).
    private static func esSeguro(_ url: URL) -> Bool {
        if url.scheme == "https" { return true }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    }

    /// ¿Está disponible cada motor? Ollama: sondea /api/tags por un modelo de
    /// embeddings; nube: hay key. Para ofrecer los activos y marcar los inactivos.
    static func detectar(_ done: @escaping ([(Motor, Bool)]) -> Void) {
        var res: [(Motor, Bool)] = []
        let grupo = DispatchGroup()
        for m in motores {
            if m.id == "interno" {
                // Disponible = modelo descargado + llama-server embarcado presente.
                res.append((m, EmbeddingServer.disponible))
            } else if m.local {
                grupo.enter()
                probarOllamaEmb(base: m.base) { ok in res.append((m, ok)); grupo.leave() }
            } else {
                res.append((m, !ApiKeys.get(m.keyEnv).isEmpty))
            }
        }
        grupo.notify(queue: .main) {
            done(motores.compactMap { m in res.first { $0.0.id == m.id } })
        }
    }

    private static func probarOllamaEmb(base: String, _ done: @escaping (Bool) -> Void) {
        guard let u = URL(string: "\(base)/api/tags") else { done(false); return }
        var req = URLRequest(url: u); req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let ok: Bool = {
                guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let ms = j["models"] as? [[String: Any]] else { return false }
                let nombres = ms.compactMap { $0["name"] as? String }.map { $0.lowercased() }
                return nombres.contains { n in ["embed", "bge", "nomic", "mxbai", "minilm"].contains { n.contains($0) } }
            }()
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    /// Embebe un texto con el MOTOR ELEGIDO. Ollama: /api/embeddings
    /// ({model,prompt}→embedding). Nube OpenAI-compat: /v1/embeddings
    /// ({model,input}→data[0].embedding), con Bearer key.
    static func embed(_ texto: String, completion: @escaping (Result<[Double], Error>) -> Void) {
        let m = motorActual
        // Motor INTERNO: es nuestro llama-server embarcado con bge-m3 — se levanta
        // on-demand (el primer uso espera la carga) y duerme solo por inactividad.
        if m.id == "interno" {
            EmbeddingServer.asegurar { ok in
                guard ok else {
                    completion(.failure(ScribeError.ws(EmbeddingServer.instalado
                        ? "El motor interno de embeddings no arrancó"
                        : "El motor interno no está descargado (Ajustes → Reconocimiento inteligente)")))
                    return
                }
                EmbeddingServer.tocar()
                embedHTTP(m, texto: texto, completion: completion)
            }
            return
        }
        embedHTTP(m, texto: texto, completion: completion)
    }

    private static func embedHTTP(_ m: Motor, texto: String,
                                  completion: @escaping (Result<[Double], Error>) -> Void) {
        let openai = m.esOpenAICompat
        let endpoint = openai ? "\(m.base)/embeddings" : "\(m.base)/api/embeddings"
        guard let url = URL(string: endpoint) else { completion(.failure(ScribeError.ws("URL de embeddings inválida"))); return }
        guard esSeguro(url) else { completion(.failure(ScribeError.ws("Embeddings en la nube exige https"))); return }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("close", forHTTPHeaderField: "Connection")   // conexión fresca (VPN mata sockets idle)
        let key = m.keyEnv.isEmpty ? "" : ApiKeys.get(m.keyEnv)
        if openai, !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let cuerpo: [String: Any] = openai ? ["model": m.modelo, "input": texto] : ["model": m.modelo, "prompt": texto]
        req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err)); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, (200..<300).contains(code),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ScribeError.http(code, data.flatMap { String(data: $0, encoding: .utf8) } ?? ""))); return
            }
            // Ollama: {embedding:[...]}. OpenAI: {data:[{embedding:[...]}]}.
            let vec = (j["embedding"] as? [Double])
                ?? ((j["data"] as? [[String: Any]])?.first?["embedding"] as? [Double])
            guard let v = vec, !v.isEmpty else { completion(.failure(ScribeError.sinTexto)); return }
            completion(.success(v))
        }.resume()
    }

    static func coseno(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let den = (na.squareRoot() * nb.squareRoot())
        return den == 0 ? 0 : dot / den
    }

    /// Asegura el vector de un texto (ruta+mtime como clave de caché). Devuelve
    /// el vector por el callback (desde caché o recién calculado).
    static func vectorDe(path: String, mtime: Double, texto: String,
                         completion: @escaping ([Double]?) -> Void) {
        lock.lock(); let e = cache[path]; lock.unlock()
        if let e, e.mtime == mtime, e.motor == firmaMotor { completion(e.vec); return }
        embed(texto) { r in
            switch r {
            case .success(let v):
                lock.lock(); cache[path] = Entrada(vec: v, mtime: mtime, motor: firmaMotor); lock.unlock()
                completion(v)
            case .failure:
                completion(nil)
            }
        }
    }

    // MARK: Reconocimiento semántico de MODOS (capa 3) — misma idea que el glosario
    private static func clavesEjemplos(_ modos: [(id: String, ejemplos: [String])]) -> [String] {
        modos.flatMap { par in par.ejemplos.map { "modoej:\(par.id):\($0)" } }
    }
    static func modosListos(_ modos: [(id: String, ejemplos: [String])]) -> Bool {
        cargarCache()
        lock.lock(); defer { lock.unlock() }
        let firma = firmaMotor
        return clavesEjemplos(modos).allSatisfy { cache[$0]?.motor == firma }
    }
    /// Calienta (2º plano) los vectores de las frases-ejemplo de los modos.
    static func calentarModos(_ modos: [(id: String, ejemplos: [String])]) {
        cargarCache()
        let firma = firmaMotor
        // par (clave, texto) que falta embeber
        var faltan: [(String, String)] = []
        lock.lock()
        for par in modos { for ej in par.ejemplos {
            let k = "modoej:\(par.id):\(ej)"
            if cache[k]?.motor != firma { faltan.append((k, ej)) }
        } }
        let ocupado = calentando
        if !faltan.isEmpty { calentando = true }
        lock.unlock()
        guard !faltan.isEmpty, !ocupado else { return }
        DispatchQueue.global(qos: .utility).async {
            let sem = DispatchSemaphore(value: 4); let grupo = DispatchGroup()
            for (k, ej) in faltan {
                sem.wait(); grupo.enter()
                embed(ej) { r in
                    if case .success(let v) = r { lock.lock(); cache[k] = Entrada(vec: v, mtime: 0, motor: firma); lock.unlock() }
                    sem.signal(); grupo.leave()
                }
            }
            grupo.wait(); guardarCache()
            lock.lock(); calentando = false; lock.unlock()
        }
    }
    struct PuntajeModo {
        let id: String
        let score: Double
    }

    /// Devuelve el ranking completo. El margen entre 1º y 2º evita escoger un
    /// modo por muy poco cuando dos intenciones se parecen (correo/Outlook, por
    /// ejemplo). Los vectores de ejemplos siguen saliendo del caché local.
    static func rankingModos(comando: String, modos: [(id: String, ejemplos: [String])],
                             done: @escaping ([PuntajeModo]) -> Void) {
        embed(comando) { r in
            guard case .success(let qv) = r else { DispatchQueue.main.async { done([]) }; return }
            lock.lock(); let firma = firmaMotor
            var puntajes: [PuntajeModo] = []
            for par in modos {
                var maxS = 0.0
                for ej in par.ejemplos {
                    if let e = cache["modoej:\(par.id):\(ej)"], e.motor == firma { maxS = max(maxS, coseno(qv, e.vec)) }
                }
                puntajes.append(PuntajeModo(id: par.id, score: maxS))
            }
            lock.unlock()
            puntajes.sort { $0.score > $1.score }
            DispatchQueue.main.async { done(puntajes) }
        }
    }

    /// Compatibilidad para búsqueda simple: primer elemento del ranking.
    static func mejorModo(comando: String, modos: [(id: String, ejemplos: [String])], done: @escaping (String?, Double) -> Void) {
        rankingModos(comando: comando, modos: modos) { ranking in
            done(ranking.first?.id, ranking.first?.score ?? 0)
        }
    }

    /// Estado de una búsqueda semántica (progreso + resultados).
    struct Resultado { let path: String; let score: Double }

    private static let lock = NSLock()
    private static var calentando = false

    // MARK: Glosario inteligente (opt-in) — manda al pulido SOLO los términos afines
    //
    // El glosario crece y mandarlo entero cada vez alarga el prompt (lento). Con
    // embeddings: vectorizamos cada término UNA vez (caché "glosario:<t>"), y por
    // dictado embebemos el texto y mandamos solo los K términos más cercanos (por
    // coseno) + los que aparecen literalmente. Rápido y escala con glosario grande.

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
    }
    /// ¿Ya están cacheados los vectores de TODOS los términos (con el motor actual)?
    static func glosarioListo(_ keyterms: [String]) -> Bool {
        cargarCache()
        lock.lock(); defer { lock.unlock() }
        let firma = firmaMotor
        return keyterms.allSatisfy { cache["glosario:\($0)"]?.motor == firma }
    }
    /// Calienta (en segundo plano) los vectores de términos que falten. Idempotente.
    static func calentarGlosario(_ keyterms: [String]) {
        cargarCache()
        let firma = firmaMotor
        lock.lock()
        let faltan = keyterms.filter { !$0.isEmpty && cache["glosario:\($0)"]?.motor != firma }
        let ocupado = calentando
        if !faltan.isEmpty { calentando = true }
        lock.unlock()
        guard !faltan.isEmpty, !ocupado else { return }
        DispatchQueue.global(qos: .utility).async {
            let sem = DispatchSemaphore(value: 4); let grupo = DispatchGroup()
            for t in faltan {
                sem.wait(); grupo.enter()
                embed(t) { r in
                    if case .success(let v) = r {
                        lock.lock(); cache["glosario:\(t)"] = Entrada(vec: v, mtime: 0, motor: firma); lock.unlock()
                    }
                    sem.signal(); grupo.leave()
                }
            }
            grupo.wait(); guardarCache()
            lock.lock(); calentando = false; lock.unlock()
        }
    }
    /// Devuelve los K términos MÁS afines al texto + los que aparecen literalmente.
    /// Requiere glosarioListo==true (el llamador lo verifica y cae al glosario
    /// completo mientras se calienta).
    static func terminosRelevantes(texto: String, keyterms: [String], k: Int, done: @escaping ([String]) -> Void) {
        let t = fold(texto)
        let lits = keyterms.filter { let n = fold($0); return !n.isEmpty && t.contains(n) }
        embed(texto) { r in
            guard case .success(let qv) = r else { DispatchQueue.main.async { done(keyterms) }; return }
            lock.lock(); let firma = firmaMotor
            let scored = keyterms.compactMap { term -> (String, Double)? in
                guard let e = cache["glosario:\(term)"], e.motor == firma else { return nil }
                return (term, coseno(qv, e.vec))
            }.sorted { $0.1 > $1.1 }
            lock.unlock()
            var sel = Set(lits)
            for (term, _) in scored where sel.count < max(k, lits.count) { sel.insert(term) }
            let out = keyterms.filter { sel.contains($0) }
            DispatchQueue.main.async { done(out.isEmpty ? keyterms : out) }
        }
    }

    /// Indexa (si hace falta) y ordena las entradas por cercanía a la consulta.
    /// `items`: (path, mtime, texto). Llama `progreso(hechos, total)` mientras
    /// embebe los que faltan, y `done` con los pares (path, score) ordenados.
    /// Embebe hasta 6 a la vez (rápido, sin reventar el servidor); el primer
    /// indexado de un historial grande tarda, luego TODO queda cacheado.
    static func buscar(consulta: String, items: [(path: String, mtime: Double, texto: String)],
                       progreso: @escaping (Int, Int) -> Void,
                       done: @escaping (Result<[Resultado], Error>) -> Void) {
        cargarCache()
        embed(consulta) { r in
            switch r {
            case .failure(let e): DispatchQueue.main.async { done(.failure(e)) }
            case .success(let qv):
                DispatchQueue.global(qos: .userInitiated).async {
                    let total = items.count
                    var resultados: [Resultado] = []
                    var hechos = 0
                    let sem = DispatchSemaphore(value: 6)   // hasta 6 embeds en vuelo
                    let grupo = DispatchGroup()
                    func avanzar() {
                        lock.lock(); hechos += 1; let h = hechos; lock.unlock()
                        DispatchQueue.main.async { progreso(h, total) }
                    }
                    let firma = firmaMotor
                    for it in items {
                        lock.lock(); let cacheado = cache[it.path]; lock.unlock()
                        if let e = cacheado, e.mtime == it.mtime, e.motor == firma {
                            let s = coseno(qv, e.vec)
                            lock.lock(); resultados.append(Resultado(path: it.path, score: s)); lock.unlock()
                            avanzar(); continue
                        }
                        sem.wait(); grupo.enter()
                        embed(it.texto) { r in
                            if case .success(let v) = r {
                                let s = coseno(qv, v)
                                lock.lock()
                                cache[it.path] = Entrada(vec: v, mtime: it.mtime, motor: firma)
                                resultados.append(Resultado(path: it.path, score: s))
                                lock.unlock()
                            }
                            avanzar(); sem.signal(); grupo.leave()
                        }
                    }
                    grupo.wait()
                    guardarCache()
                    lock.lock(); resultados.sort { $0.score > $1.score }; let out = resultados; lock.unlock()
                    DispatchQueue.main.async { done(.success(out)) }
                }
            }
        }
    }
}
