import Foundation

// MARK: - Autenticación login→token de las conexiones API (fase 3)
//
// El login (usuario visible en la config, CLAVE solo en Keychain) se hace una
// vez y el token vive en cache: memoria + archivo 0600 con TTL. Ante 401/403
// el runner invalida y reintenta una vez. Reglas duras:
//   - La respuesta del login JAMÁS se loguea (contiene el token).
//   - El token se enmascara en toda evidencia.
//   - Sin clave en Keychain no hay login: error claro, nunca un prompt colgado.

enum ConexionesAuth {

    struct TokenCacheado: Codable {
        let token: String
        let expira: Date
    }

    private static let lock = NSLock()
    private static var memoria: [String: TokenCacheado] = [:]

    private static var dirCache: URL {
        Config.dir.appendingPathComponent(".cache/conexiones")
    }
    private static func urlCache(_ modoId: String) -> URL {
        // Defensa en profundidad: el id NUNCA debe escapar de dirCache (aunque
        // ModosPortables ya fuerza ids limpios al importar). Solo alfanuméricos,
        // guion y guion bajo; cualquier otra cosa (incluido «..» y «/») a "_".
        let seguro = modoId.map { c -> Character in
            c.isLetter || c.isNumber || c == "-" || c == "_" ? c : "_"
        }
        let nombre = String(String(seguro).prefix(80))
        return dirCache.appendingPathComponent("\(nombre.isEmpty ? "modo" : nombre).token.json")
    }

    /// Navega un dot-path ("data.access_token") por un JSON ya parseado.
    static func valorDotPath(_ json: Any, ruta: String) -> Any? {
        var actual: Any = json
        for parte in ruta.split(separator: ".").map(String.init) {
            guard let d = actual as? [String: Any], let sig = d[parte] else { return nil }
            actual = sig
        }
        return actual
    }

    /// application/x-www-form-urlencoded (logins legados).
    static func formEncode(_ campos: [(String, String)]) -> Data {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let cuerpo = campos.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: cs) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: cs) ?? v)"
        }.joined(separator: "&")
        return Data(cuerpo.utf8)
    }

    // MARK: cache

    static func tokenCacheado(_ modoId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let t = memoria[modoId], t.expira > Date() { return t.token }
        guard let d = try? Data(contentsOf: urlCache(modoId)),
              let t = try? JSONDecoder().decode(TokenCacheado.self, from: d),
              t.expira > Date() else { return nil }
        memoria[modoId] = t
        return t.token
    }

    static func cachear(_ token: String, modoId: String, ttlMinutos: Int) {
        let t = TokenCacheado(token: token,
                              expira: Date().addingTimeInterval(TimeInterval(max(1, ttlMinutos)) * 60))
        lock.lock(); memoria[modoId] = t; lock.unlock()
        try? FileManager.default.createDirectory(at: dirCache, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if let d = try? JSONEncoder().encode(t) {
            try? d.write(to: urlCache(modoId), options: .atomic)
            Config.protegerSecreto(urlCache(modoId))
        }
    }

    /// Invalida (401/403, o al borrar el modo).
    static func invalidar(_ modoId: String) {
        lock.lock(); memoria[modoId] = nil; lock.unlock()
        try? FileManager.default.removeItem(at: urlCache(modoId))
    }

    // MARK: login

    /// Devuelve un token utilizable para la conexión: cache válido, o login.
    /// `forzar` salta el cache (tras un 401/403).
    static func obtenerToken(conexion: ConexionAPI, modoId: String, forzar: Bool = false,
                             completion: @escaping (_ token: String?, _ error: String?) -> Void) {
        guard conexion.auth.tipo == "login" else { completion(nil, "la conexión no usa login"); return }
        if !forzar, let t = tokenCacheado(modoId) { completion(t, nil); return }
        guard let clave = SecretosKeychain.leer(cuenta: modoId), !clave.isEmpty else {
            completion(nil, "no hay clave guardada para esta conexión (Ajustes → Modos → Secreto)"); return
        }
        var base = conexion.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        var ruta = conexion.auth.loginRuta.trimmingCharacters(in: .whitespaces)
        if !ruta.isEmpty, !ruta.hasPrefix("/") { ruta = "/" + ruta }
        let urlStr = base + ruta
        guard ConexionesMotor.urlSegura(urlStr), let url = URL(string: urlStr) else {
            completion(nil, "la URL de login no es segura"); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = TimeInterval(min(60, max(3, conexion.timeoutSegundos)))
        req.setValue("close", forHTTPHeaderField: "Connection")
        if conexion.auth.loginFormato == "form" {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = formEncode([(conexion.auth.campoUsuario, conexion.auth.usuario),
                                       (conexion.auth.campoClave, clave)])
        } else {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                conexion.auth.campoUsuario: conexion.auth.usuario,
                conexion.auth.campoClave: clave,
            ])
        }
        for (h, v) in conexion.headers { req.setValue(v, forHTTPHeaderField: h) }
        let delegado = ConexionRedDelegate(url: url)
        let sesion = URLSession(configuration: .ephemeral, delegate: delegado, delegateQueue: nil)
        let inicio = Date()
        sesion.dataTask(with: req) { data, resp, error in
            defer { sesion.finishTasksAndInvalidate() }
            let ms = Int(Date().timeIntervalSince(inicio) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // Evidencia SIN cuerpo: la respuesta del login contiene el token.
            AgenteLog.registrar("conexion_login", ["modo": modoId, "estado": code, "ms": ms])
            if let error { completion(nil, "login falló: \(error.localizedDescription)"); return }
            guard (200..<300).contains(code) else {
                completion(nil, "login rechazado (HTTP \(code)) — revisa usuario y clave"); return
            }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data),
                  let token = valorDotPath(json, ruta: conexion.auth.campoToken)
                    .flatMap({ $0 as? String ?? ($0 as? NSNumber)?.stringValue }),
                  !token.isEmpty else {
                completion(nil, "el login respondió, pero no encontré el token en «\(conexion.auth.campoToken)»"); return
            }
            cachear(token, modoId: modoId, ttlMinutos: conexion.auth.ttlMinutos)
            completion(token, nil)
        }.resume()
    }
}

