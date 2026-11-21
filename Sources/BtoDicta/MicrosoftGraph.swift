import Foundation

// MARK: - Correo de Microsoft por Graph, solo lectura (spec 015)
//
// Inicio de sesión con el flujo oficial de código de dispositivo: BtoDicta
// muestra un código, el usuario autoriza en la página de Microsoft y BtoDicta
// recibe un token. Nunca ve la contraseña. El token de renovación vive en el
// Llavero; el de acceso, solo en memoria. Tokens y códigos no van al registro.

struct CorreoLeido: Equatable {
    var id: String = ""
    let de: String
    let asunto: String
    let fecha: Date
    let vistaPrevia: String
    let importante: Bool
    let leido: Bool
}

struct CodigoDispositivo: Equatable {
    let codigoDispositivo: String
    let codigoUsuario: String
    let url: String
    let intervalo: Double
    let expira: Double
}

enum MicrosoftGraph {
    static let alcances = "offline_access User.Read Mail.ReadWrite Mail.Send Calendars.ReadWrite People.Read User.ReadBasic.All"
    private static let lock = NSLock()
    /// Caché de acceso por cuenta (clave: su entrada del Llavero). Solo en memoria.
    private static var accesos: [String: (token: String, vence: Date)] = [:]
    private static var esperandoCodigo = false
    /// La cuenta Microsoft con la que se trabaja ahora (spec 018); por defecto la predeterminada.
    private static var elegida: CuentaNube?

    // MARK: Estado

    static var cuenta: CuentaNube? {
        elegida ?? CuentasNube.conectadas.first { $0.proveedor == .microsoft && $0.predeterminada }
            ?? CuentasNube.conectadas.first { $0.proveedor == .microsoft }
    }
    static func usar(_ c: CuentaNube?) { lock.lock(); elegida = c; lock.unlock() }
    private static var cuentaLlavero: String { cuenta?.llavero ?? CuentasNube.llaveroMicrosoftAnterior }
    private static var acceso: (token: String, vence: Date)? {
        get { accesos[cuentaLlavero] }
        set { accesos[cuentaLlavero] = newValue }
    }

    static var conectado: Bool { SecretosKeychain.existe(cuenta: cuentaLlavero) }
    static var disponible: Bool { Config.agenteGraphActivo() && !clientID.isEmpty && conectado }
    private static var clientID: String {
        (cuenta?.clientID ?? Config.graphClientID()).trimmingCharacters(in: .whitespaces)
    }
    private static var tenant: String {
        let t = (cuenta?.tenant ?? Config.graphTenant()).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "common" : t
    }
    private static var urlToken: URL? {
        URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token")
    }

    static func desconectar() {
        lock.lock(); acceso = nil; lock.unlock()   // de la cuenta actual
        SecretosKeychain.borrar(cuenta: cuentaLlavero)
        Log.write("correo Microsoft: cuenta desconectada")
    }

    // MARK: Inicio de sesión (código de dispositivo)

    /// Pide el código; `mostrar` recibe lo que el usuario debe ver; `fin` llega
    /// en main con el resultado (nil = conectado; si no, el motivo en español).
    static func conectar(mostrar: @escaping (CodigoDispositivo) -> Void,
                         fin: @escaping (String?) -> Void) {
        guard !clientID.isEmpty else { fin("Falta el identificador de la aplicación (client ID)."); return }
        guard let url = URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/devicecode") else {
            fin("El directorio (tenant) no es válido."); return
        }
        post(url, ["client_id": clientID, "scope": alcances]) { codigo, json in
            guard codigo == 200, let json, let c = leerCodigoDispositivo(json) else {
                DispatchQueue.main.async { fin(mensajeError(json, codigo: codigo)) }
                return
            }
            DispatchQueue.main.async { mostrar(c) }
            lock.lock(); esperandoCodigo = true; lock.unlock()
            esperarAutorizacion(c, limite: Date().addingTimeInterval(c.expira), fin: fin)
        }
    }

    static func cancelarConexion() { lock.lock(); esperandoCodigo = false; lock.unlock() }

    private static func esperarAutorizacion(_ c: CodigoDispositivo, limite: Date,
                                            intervalo: Double? = nil,
                                            fin: @escaping (String?) -> Void) {
        let espera = max(2, intervalo ?? c.intervalo)
        DispatchQueue.global().asyncAfter(deadline: .now() + espera) {
            lock.lock(); let sigue = esperandoCodigo; lock.unlock()
            guard sigue else { DispatchQueue.main.async { fin("Conexión cancelada.") }; return }
            guard Date() < limite, let url = urlToken else {
                DispatchQueue.main.async { fin("El código venció. Vuelve a pulsar Conectar.") }; return
            }
            post(url, ["grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                       "client_id": clientID, "device_code": c.codigoDispositivo]) { codigo, json in
                let error = json?["error"] as? String
                if codigo == 200, let json, guardarTokens(json) {
                    lock.lock(); esperandoCodigo = false; lock.unlock()
                    Log.write("correo Microsoft: cuenta conectada")
                    anotarCorreoDeLaCuenta()
                    DispatchQueue.main.async { fin(nil) }
                } else if error == "authorization_pending" {
                    esperarAutorizacion(c, limite: limite, intervalo: espera, fin: fin)
                } else if error == "slow_down" {
                    esperarAutorizacion(c, limite: limite, intervalo: espera + 5, fin: fin)
                } else {
                    lock.lock(); esperandoCodigo = false; lock.unlock()
                    DispatchQueue.main.async { fin(mensajeError(json, codigo: codigo)) }
                }
            }
        }
    }

    // MARK: Lectura

    /// Correos de la bandeja de entrada de los últimos `dias` (1–7). En main.
    static func leerBandeja(dias: Int, ahora: Date = Date(),
                            fin: @escaping (Result<[CorreoLeido], ErrorGraph>) -> Void) {
        guard disponible else { DispatchQueue.main.async { fin(.failure(.sinCuenta)) }; return }
        conToken { token in
            guard let token else { DispatchQueue.main.async { fin(.failure(.sesionVencida)) }; return }
            guard let url = urlBandeja(dias: dias, ahora: ahora) else {
                DispatchQueue.main.async { fin(.failure(.respuesta("dirección inválida"))) }; return
            }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 20
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let r: Result<[CorreoLeido], ErrorGraph>
                if error != nil { r = .failure(.sinRed) }
                else if codigo == 401 { r = .failure(.sesionVencida) }
                else if codigo == 403 { r = .failure(.sinPermiso) }
                else if codigo == 200, let data, let correos = leerCorreos(data) { r = .success(correos) }
                else { r = .failure(.respuesta("HTTP \(codigo)")) }
                if case .failure(let e) = r { Log.write("correo Microsoft: no se pudo leer — \(e.mensaje)") }
                DispatchQueue.main.async { fin(r) }
            }.resume()
        }
    }

    /// Guarda en el registro el correo de la cuenta recién conectada (para nombrarla).
    private static func anotarCorreoDeLaCuenta() {
        guard var c = cuenta else { return }
        llamar("GET", "/me", query: [URLQueryItem(name: "$select", value: "mail,userPrincipalName")]) { codigo, json in
            guard codigo == 200, let j = json as? [String: Any] else { return }
            let correo = (j["mail"] as? String) ?? (j["userPrincipalName"] as? String) ?? ""
            guard !correo.isEmpty else { return }
            c.correo = correo
            CuentasNube.actualizar(c)
        }
    }

    enum ErrorGraph: Error, Equatable {
        case sinCuenta, sesionVencida, sinPermiso, sinRed, respuesta(String)
        var mensaje: String {
            switch self {
            case .sinCuenta: return "No hay una cuenta de correo conectada. Conéctala en Ajustes, Asistente."
            case .sesionVencida: return "La sesión de esa cuenta venció. Vuelve a conectarla en Ajustes, Asistente."
            case .sinPermiso: return "El servicio no dio permiso para eso. Puede que tu organización lo bloquee."
            case .sinRed: return "No pude conectarme. Revisa la conexión a internet."
            case .respuesta(let m): return "El servicio respondió con un error (\(m))."
            }
        }
    }

    static func conToken(_ listo: @escaping (String?) -> Void) {
        lock.lock(); let a = acceso; lock.unlock()
        if let a, a.vence > Date().addingTimeInterval(60) { listo(a.token); return }
        guard let refresco = SecretosKeychain.leer(cuenta: cuentaLlavero), let url = urlToken else { listo(nil); return }
        post(url, ["grant_type": "refresh_token", "client_id": clientID,
                   "refresh_token": refresco, "scope": alcances]) { codigo, json in
            guard codigo == 200, let json, guardarTokens(json) else { listo(nil); return }
            lock.lock(); let t = acceso?.token; lock.unlock()
            listo(t)
        }
    }

    @discardableResult
    private static func guardarTokens(_ json: [String: Any]) -> Bool {
        guard let token = json["access_token"] as? String, !token.isEmpty else { return false }
        let vence = Date().addingTimeInterval((json["expires_in"] as? Double) ?? Double((json["expires_in"] as? Int) ?? 3600))
        lock.lock(); acceso = (token, vence); lock.unlock()
        if let r = json["refresh_token"] as? String, !r.isEmpty {
            SecretosKeychain.guardar(r, cuenta: cuentaLlavero)
        }
        return true
    }

    private static func post(_ url: URL, _ campos: [String: String],
                             _ fin: @escaping (Int, [String: Any]?) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formulario(campos).data(using: .utf8)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            fin(codigo, json)
        }.resume()
    }

    // MARK: Puras (probadas)

    static func formulario(_ campos: [String: String]) -> String {
        var permitidos = CharacterSet.alphanumerics
        permitidos.insert(charactersIn: "-._~")
        return campos.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: permitidos) ?? "")"
        }.joined(separator: "&")
    }

    static func urlBandeja(dias: Int, ahora: Date) -> URL? {
        let d = min(7, max(1, dias))
        // Desde el inicio del día (d-1) días atrás: «ayer y hoy» = 2.
        let inicio = Calendar.current.startOfDay(for: ahora.addingTimeInterval(-Double(d - 1) * 86_400))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        var c = URLComponents(string: "https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages")
        c?.queryItems = [
            URLQueryItem(name: "$filter", value: "receivedDateTime ge \(f.string(from: inicio))"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$top", value: "40"),
            URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview,importance,isRead"),
        ]
        return c?.url
    }

    static func leerCorreos(_ data: Data) -> [CorreoLeido]? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lista = j["value"] as? [[String: Any]] else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return lista.compactMap { m in
            let correo = ((m["from"] as? [String: Any])?["emailAddress"] as? [String: Any])
            let nombre = (correo?["name"] as? String) ?? ""
            let direccion = (correo?["address"] as? String) ?? ""
            guard let fechaTexto = m["receivedDateTime"] as? String, let fecha = f.date(from: fechaTexto) else { return nil }
            return CorreoLeido(id: (m["id"] as? String) ?? "",
                               de: nombre.isEmpty ? direccion : "\(nombre) <\(direccion)>",
                               asunto: (m["subject"] as? String) ?? "(sin asunto)",
                               fecha: fecha,
                               vistaPrevia: String(((m["bodyPreview"] as? String) ?? "").prefix(300)),
                               importante: (m["importance"] as? String) == "high",
                               leido: (m["isRead"] as? Bool) ?? false)
        }
    }

    static func leerCodigoDispositivo(_ j: [String: Any]) -> CodigoDispositivo? {
        guard let dc = j["device_code"] as? String, let uc = j["user_code"] as? String,
              let url = j["verification_uri"] as? String else { return nil }
        func num(_ k: String, _ d: Double) -> Double { (j[k] as? Double) ?? (j[k] as? Int).map(Double.init) ?? d }
        return CodigoDispositivo(codigoDispositivo: dc, codigoUsuario: uc, url: url,
                                 intervalo: num("interval", 5), expira: num("expires_in", 900))
    }

    static func mensajeError(_ j: [String: Any]?, codigo: Int) -> String {
        let e = (j?["error"] as? String) ?? ""
        switch e {
        case "access_denied", "authorization_declined": return "La autorización se rechazó."
        case "expired_token": return "El código venció. Vuelve a pulsar Conectar."
        case "invalid_client", "unauthorized_client":
            return "Microsoft no reconoce esa aplicación (client ID) o no admite este inicio de sesión."
        case "": return codigo == 0 ? "No pude conectarme a Microsoft." : "Microsoft respondió HTTP \(codigo)."
        default: return "Microsoft respondió «\(e)»."
        }
    }

    /// Los correos como datos para la IA: acotados y marcados como no confiables.
    static func paraIA(_ correos: [CorreoLeido]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d 'a las' HH:mm"
        return correos.prefix(40).enumerated().map { i, c in
            let marcas = [c.importante ? "importancia alta" : nil, c.leido ? nil : "sin leer"]
                .compactMap { $0 }.joined(separator: ", ")
            return "\(i + 1). De: \(c.de) · \(f.string(from: c.fecha))\(marcas.isEmpty ? "" : " · \(marcas)")\n"
                + "   Asunto: \(c.asunto)\n   Inicio: \(c.vistaPrevia.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")
    }
}
