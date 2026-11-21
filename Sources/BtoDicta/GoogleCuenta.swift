import AppKit
import CryptoKit
import Foundation
import Network

// MARK: - Cuentas de Google: Gmail, Calendar y Contactos (spec 018)
//
// Inicio de sesión oficial de «aplicación de escritorio» con PKCE y redirección a
// 127.0.0.1 (el flujo de dispositivo de Google no admite Gmail). BtoDicta nunca ve
// la contraseña. Sesión en el Llavero por cuenta; acceso solo en memoria.

enum GoogleCuenta {
    static let alcances = ["openid", "email",
                           "https://www.googleapis.com/auth/gmail.readonly",
                           "https://www.googleapis.com/auth/gmail.compose",
                           "https://www.googleapis.com/auth/calendar.events",
                           "https://www.googleapis.com/auth/contacts.readonly"]
    typealias ErrorG = MicrosoftGraph.ErrorGraph
    typealias Fin<T> = (Result<T, ErrorG>) -> Void

    private static let lock = NSLock()
    private static var accesos: [String: (token: String, vence: Date)] = [:]
    private static var escucha: NWListener?

    // MARK: PKCE (puro)

    static func verificador() -> String {
        let c = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in c.randomElement()! })
    }

    static func desafio(_ verificador: String) -> String {
        Data(SHA256.hash(data: Data(verificador.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func urlAutorizacion(clientID: String, redireccion: String, desafio: String, estado: String) -> URL? {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        c?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redireccion),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: alcances.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: desafio),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: estado),
        ]
        return c?.url
    }

    /// Código y estado de la primera línea de la petición HTTP de la redirección.
    static func leerRedireccion(_ primeraLinea: String) -> (codigo: String?, estado: String?, error: String?) {
        let partes = primeraLinea.split(separator: " ")
        guard partes.count >= 2, let c = URLComponents(string: "http://127.0.0.1" + partes[1]) else { return (nil, nil, nil) }
        func v(_ k: String) -> String? { c.queryItems?.first { $0.name == k }?.value }
        return (v("code"), v("state"), v("error"))
    }

    // MARK: Conectar

    /// Abre el navegador para autorizar y espera la redirección local (5 min).
    static func conectar(_ cuenta: CuentaNube, secreto: String, fin: @escaping (String?) -> Void) {
        guard !cuenta.clientID.isEmpty, !secreto.isEmpty else { fin("Faltan el identificador y el secreto de la aplicación de Google."); return }
        SecretosKeychain.guardar(secreto, cuenta: CuentasNube.llaveSecreto(cuenta))
        let verif = verificador(), estado = UUID().uuidString
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { fin("No pude abrir la escucha local."); return }
        lock.lock(); escucha?.cancel(); escucha = l; lock.unlock()
        var terminado = false
        let terminar: (String?) -> Void = { m in
            DispatchQueue.main.async {
                guard !terminado else { return }
                terminado = true; l.cancel(); fin(m)
            }
        }
        l.newConnectionHandler = { con in
            con.start(queue: .global())
            con.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let peticion = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let r = leerRedireccion(peticion.components(separatedBy: "\r\n").first ?? "")
                let ok = r.codigo != nil && r.estado == estado
                let html = ok ? "Listo. Ya puedes volver a BtoDicta." : "No se completó la autorización. Vuelve a intentarlo desde BtoDicta."
                let cuerpo = "<html><body style='font-family:-apple-system;padding:40px'><h2>\(html)</h2></body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(cuerpo.utf8.count)\r\nConnection: close\r\n\r\n\(cuerpo)"
                con.send(content: Data(resp.utf8), completion: .contentProcessed { _ in con.cancel() })
                guard ok, let codigo = r.codigo else { terminar(r.error.map { "Google respondió «\($0)»." } ?? "No se completó la autorización."); return }
                intercambiar(cuenta, secreto: secreto, codigo: codigo, verificador: verif,
                             redireccion: redireccionDe(l)) { e in terminar(e) }
            }
        }
        l.stateUpdateHandler = { st in
            if case .ready = st, let url = urlAutorizacion(clientID: cuenta.clientID, redireccion: redireccionDe(l),
                                                           desafio: desafio(verif), estado: estado) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
            if case .failed = st { terminar("La escucha local falló.") }
        }
        l.start(queue: .global())
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { terminar("Se acabó el tiempo para autorizar. Vuelve a pulsar Conectar.") }
    }

    private static func redireccionDe(_ l: NWListener) -> String { "http://127.0.0.1:\(l.port?.rawValue ?? 0)" }

    private static func intercambiar(_ cuenta: CuentaNube, secreto: String, codigo: String, verificador: String,
                                     redireccion: String, fin: @escaping (String?) -> Void) {
        post(["client_id": cuenta.clientID, "client_secret": secreto, "code": codigo, "code_verifier": verificador,
              "grant_type": "authorization_code", "redirect_uri": redireccion]) { c, json in
            guard c == 200, let json, guardarTokens(cuenta, json) else { fin(MicrosoftGraph.mensajeError(json, codigo: c)); return }
            Log.write("google: cuenta conectada")
            anotarCorreo(cuenta)
            fin(nil)
        }
    }

    private static func anotarCorreo(_ cuenta: CuentaNube) {
        llamar(cuenta, "GET", "https://openidconnect.googleapis.com/v1/userinfo") { c, json in
            guard c == 200, let correo = (json as? [String: Any])?["email"] as? String else { return }
            var cu = cuenta; cu.correo = correo; CuentasNube.actualizar(cu)
        }
    }

    // MARK: Tokens

    @discardableResult
    private static func guardarTokens(_ cuenta: CuentaNube, _ json: [String: Any]) -> Bool {
        guard let token = json["access_token"] as? String, !token.isEmpty else { return false }
        let vence = Date().addingTimeInterval((json["expires_in"] as? Double) ?? Double((json["expires_in"] as? Int) ?? 3600))
        lock.lock(); accesos[cuenta.llavero] = (token, vence); lock.unlock()
        if let r = json["refresh_token"] as? String, !r.isEmpty { SecretosKeychain.guardar(r, cuenta: cuenta.llavero) }
        return true
    }

    static func conToken(_ cuenta: CuentaNube, _ listo: @escaping (String?) -> Void) {
        lock.lock(); let a = accesos[cuenta.llavero]; lock.unlock()
        if let a, a.vence > Date().addingTimeInterval(60) { listo(a.token); return }
        guard let r = SecretosKeychain.leer(cuenta: cuenta.llavero),
              let s = SecretosKeychain.leer(cuenta: CuentasNube.llaveSecreto(cuenta)) else { listo(nil); return }
        post(["client_id": cuenta.clientID, "client_secret": s, "refresh_token": r, "grant_type": "refresh_token"]) { c, json in
            guard c == 200, let json, guardarTokens(cuenta, json) else { listo(nil); return }
            lock.lock(); let t = accesos[cuenta.llavero]?.token; lock.unlock()
            listo(t)
        }
    }

    private static func post(_ campos: [String: String], _ fin: @escaping (Int, [String: Any]?) -> Void) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = MicrosoftGraph.formulario(campos).data(using: .utf8)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            fin((resp as? HTTPURLResponse)?.statusCode ?? 0,
                data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        }.resume()
    }

    /// Llamada a una API de Google con la sesión de la cuenta. Respuesta en main.
    static func llamar(_ cuenta: CuentaNube, _ metodo: String, _ url: String, query: [URLQueryItem] = [],
                       cuerpo: [String: Any]? = nil, fin: @escaping (Int, Any?) -> Void) {
        conToken(cuenta) { token in
            guard let token else { DispatchQueue.main.async { fin(401, nil) }; return }
            var c = URLComponents(string: url)
            if !query.isEmpty { c?.queryItems = query }
            guard let u = c?.url else { DispatchQueue.main.async { fin(0, nil) }; return }
            var req = URLRequest(url: u)
            req.httpMethod = metodo; req.timeoutInterval = 25
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let cuerpo {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
            }
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let codigo = error != nil ? 0 : ((resp as? HTTPURLResponse)?.statusCode ?? 0)
                let json = data.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0) }
                if !(200..<300).contains(codigo) { Log.write("google: \(metodo) \(u.path.prefix(50)) → HTTP \(codigo)") }
                DispatchQueue.main.async { fin(codigo, json) }
            }.resume()
        }
    }

    // MARK: Gmail

    private static let gmail = "https://gmail.googleapis.com/gmail/v1/users/me"

    static func leerBandeja(_ cuenta: CuentaNube, dias: Int, fin: @escaping Fin<[CorreoLeido]>) {
        listarCorreos(cuenta, consulta: "in:inbox newer_than:\(min(7, max(1, dias)))d", fin: fin)
    }

    static func buscarCorreo(_ cuenta: CuentaNube, _ texto: String, fin: @escaping Fin<[CorreoLeido]>) {
        listarCorreos(cuenta, consulta: texto, fin: fin)
    }

    private static func listarCorreos(_ cuenta: CuentaNube, consulta: String, fin: @escaping Fin<[CorreoLeido]>) {
        llamar(cuenta, "GET", gmail + "/messages", query: [URLQueryItem(name: "q", value: consulta),
                                                           URLQueryItem(name: "maxResults", value: "25")]) { c, json in
            guard c == 200 else { fin(.failure(MicrosoftGraph.error(c))); return }
            let ids = (((json as? [String: Any])?["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
            guard !ids.isEmpty else { fin(.success([])); return }
            var correos: [CorreoLeido?] = Array(repeating: nil, count: ids.count)
            let grupo = DispatchGroup()
            for (i, id) in ids.enumerated() {
                grupo.enter()
                llamar(cuenta, "GET", gmail + "/messages/\(id)", query: [
                    URLQueryItem(name: "format", value: "metadata"),
                    URLQueryItem(name: "metadataHeaders", value: "From"),
                    URLQueryItem(name: "metadataHeaders", value: "Subject"),
                ]) { c2, j2 in
                    if c2 == 200 { correos[i] = leerMensaje(j2) }
                    grupo.leave()
                }
            }
            grupo.notify(queue: .main) { fin(.success(correos.compactMap { $0 })) }
        }
    }

    /// Un mensaje de Gmail (formato metadata) como correo leído. Puro.
    static func leerMensaje(_ json: Any?) -> CorreoLeido? {
        guard let j = json as? [String: Any], let id = j["id"] as? String else { return nil }
        let cab = ((j["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        func h(_ n: String) -> String { (cab.first { ($0["name"] as? String)?.lowercased() == n }?["value"] as? String) ?? "" }
        let etiquetas = (j["labelIds"] as? [String]) ?? []
        let ms = Double((j["internalDate"] as? String) ?? "") ?? 0
        return CorreoLeido(id: id, de: h("from"), asunto: h("subject").isEmpty ? "(sin asunto)" : h("subject"),
                           fecha: Date(timeIntervalSince1970: ms / 1000),
                           vistaPrevia: String(((j["snippet"] as? String) ?? "").prefix(300)),
                           importante: etiquetas.contains("IMPORTANT"), leido: !etiquetas.contains("UNREAD"))
    }

    /// Mensaje RFC 822 en base64url (puro): asunto en UTF-8 y cuerpo en base64.
    static func mime(para: [String], asunto: String, cuerpo: String) -> String {
        let a = "=?UTF-8?B?\(Data(asunto.utf8).base64EncodedString())?="
        // Sin saltos de línea en destinatarios: evita inyectar cabeceras (CC/CCO ocultos).
        let destinos = para.map { $0.components(separatedBy: .newlines).joined() }
        let texto = "To: \(destinos.joined(separator: ", "))\r\nSubject: \(a)\r\nMIME-Version: 1.0\r\n"
            + "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + Data(cuerpo.utf8).base64EncodedString(options: .lineLength76Characters)
        return Data(texto.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func crearBorrador(_ cuenta: CuentaNube, para: [String], asunto: String, cuerpo: String,
                              fin: @escaping Fin<BorradorGraph>) {
        llamar(cuenta, "POST", gmail + "/drafts",
               cuerpo: ["message": ["raw": mime(para: para, asunto: asunto, cuerpo: cuerpo)]]) { c, json in
            guard c == 200, let id = (json as? [String: Any])?["id"] as? String else { fin(.failure(MicrosoftGraph.error(c))); return }
            fin(.success(BorradorGraph(id: id, asunto: asunto, para: para, enlace: "https://mail.google.com/mail/#drafts",
                                       inicio: String(cuerpo.prefix(200)), cuerpo: cuerpo)))
        }
    }

    static func modificarBorrador(_ cuenta: CuentaNube, _ b: BorradorGraph, asunto: String?, cuerpo: String?,
                                  fin: @escaping Fin<BorradorGraph>) {
        let a = asunto ?? b.asunto, cu = cuerpo ?? b.cuerpo
        llamar(cuenta, "PUT", gmail + "/drafts/\(b.id)",
               cuerpo: ["id": b.id, "message": ["raw": mime(para: b.para, asunto: a, cuerpo: cu)]]) { c, _ in
            guard c == 200 else { fin(.failure(MicrosoftGraph.error(c))); return }
            fin(.success(BorradorGraph(id: b.id, asunto: a, para: b.para, enlace: b.enlace,
                                       inicio: String(cu.prefix(200)), cuerpo: cu)))
        }
    }

    /// Lo que se enviará, leído de Gmail justo antes: destinatarios, asunto y texto.
    static func detalleParaEnviar(_ cuenta: CuentaNube, _ id: String, fin: @escaping (String?) -> Void) {
        llamar(cuenta, "GET", gmail + "/drafts/\(id)", query: [URLQueryItem(name: "format", value: "full")]) { c, json in
            guard c == 200, let msg = (json as? [String: Any])?["message"] as? [String: Any] else { fin(nil); return }
            let payload = msg["payload"] as? [String: Any] ?? [:]
            let cab = (payload["headers"] as? [[String: Any]]) ?? []
            func h(_ n: String) -> String { (cab.first { ($0["name"] as? String)?.lowercased() == n }?["value"] as? String) ?? "" }
            guard !h("to").isEmpty else { fin(nil); return }
            var t = "Para: \(h("to"))"
            if !h("cc").isEmpty { t += "\nCC: \(h("cc"))" }
            if !h("bcc").isEmpty { t += "\nCCO: \(h("bcc"))" }
            t += "\nAsunto: \(h("subject"))\n\n" + textoDe(payload)
            fin(t.count > 1700 ? String(t.prefix(1700)) + "…" : t)
        }
    }

    /// Texto plano de un payload de Gmail (busca la parte text/plain). Puro.
    static func textoDe(_ payload: [String: Any]) -> String {
        if (payload["mimeType"] as? String) == "text/plain",
           let d = (payload["body"] as? [String: Any])?["data"] as? String {
            var b = d.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            return Data(base64Encoded: b).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        for p in (payload["parts"] as? [[String: Any]]) ?? [] {
            let t = textoDe(p)
            if !t.isEmpty { return t }
        }
        return ""
    }

    static func enviarBorrador(_ cuenta: CuentaNube, _ id: String, fin: @escaping Fin<Void>) {
        llamar(cuenta, "POST", gmail + "/drafts/send", cuerpo: ["id": id]) { c, _ in
            c == 200 ? fin(.success(())) : fin(.failure(MicrosoftGraph.error(c)))
        }
    }

    // MARK: Calendar

    private static let calendario = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

    static func agenda(_ cuenta: CuentaNube, dias: Int, ahora: Date = Date(), fin: @escaping Fin<[EventoGraph]>) {
        let ini = Calendar.current.startOfDay(for: ahora)
        let finRango = ini.addingTimeInterval(Double(min(7, max(1, dias))) * 86_400)
        llamar(cuenta, "GET", calendario, query: [
            URLQueryItem(name: "timeMin", value: MicrosoftGraph.utc(ini)),
            URLQueryItem(name: "timeMax", value: MicrosoftGraph.utc(finRango)),
            URLQueryItem(name: "singleEvents", value: "true"), URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]) { c, json in
            guard c == 200 else { fin(.failure(MicrosoftGraph.error(c))); return }
            fin(.success(leerEventos(json)))
        }
    }

    /// Eventos de Google Calendar (puro): dateTime con zona, o date para todo el día.
    static func leerEventos(_ json: Any?) -> [EventoGraph] {
        let items = ((json as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        let iso = ISO8601DateFormatter()
        let dia = DateFormatter(); dia.dateFormat = "yyyy-MM-dd"; dia.locale = Locale(identifier: "en_US_POSIX")
        func f(_ o: Any?) -> (Date, Bool)? {
            guard let d = o as? [String: Any] else { return nil }
            if let t = d["dateTime"] as? String, let x = iso.date(from: t) { return (x, false) }
            if let t = d["date"] as? String, let x = dia.date(from: t) { return (x, true) }
            return nil
        }
        return items.compactMap { e in
            guard let (i, todo) = f(e["start"]), let (fi, _) = f(e["end"]) else { return nil }
            let org = (e["organizer"] as? [String: Any]).flatMap { ($0["displayName"] as? String) ?? ($0["email"] as? String) } ?? ""
            return EventoGraph(asunto: (e["summary"] as? String) ?? "(sin título)", inicio: i, fin: fi,
                               lugar: (e["location"] as? String) ?? "", organizador: org, todoElDia: todo)
        }
    }

    static func crearEvento(_ cuenta: CuentaNube, asunto: String, inicio: Date, fin finEv: Date, lugar: String?,
                            fin: @escaping Fin<EventoGraph>) {
        var c: [String: Any] = ["summary": asunto,
                                "start": ["dateTime": MicrosoftGraph.utc(inicio)],
                                "end": ["dateTime": MicrosoftGraph.utc(finEv)]]
        if let lugar, !lugar.isEmpty { c["location"] = lugar }
        llamar(cuenta, "POST", calendario, cuerpo: c) { codigo, _ in
            guard codigo == 200 else { fin(.failure(MicrosoftGraph.error(codigo))); return }
            fin(.success(EventoGraph(asunto: asunto, inicio: inicio, fin: finEv, lugar: lugar ?? "", organizador: "", todoElDia: false)))
        }
    }

    // MARK: Contactos

    static func buscarPersonas(_ cuenta: CuentaNube, _ nombre: String, fin: @escaping Fin<[PersonaGraph]>) {
        let url = "https://people.googleapis.com/v1/people:searchContacts"
        let mascara = URLQueryItem(name: "readMask", value: "names,emailAddresses,organizations")
        // Google pide una consulta vacía previa para preparar la caché de búsqueda.
        llamar(cuenta, "GET", url, query: [URLQueryItem(name: "query", value: ""), mascara]) { _, _ in
            llamar(cuenta, "GET", url, query: [URLQueryItem(name: "query", value: nombre), mascara]) { c, json in
                guard c == 200 else { fin(.failure(MicrosoftGraph.error(c))); return }
                fin(.success(leerContactos(json)))
            }
        }
    }

    static func leerContactos(_ json: Any?) -> [PersonaGraph] {
        let res = ((json as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        return res.compactMap { r in
            guard let p = r["person"] as? [String: Any],
                  let correo = ((p["emailAddresses"] as? [[String: Any]])?.first?["value"] as? String) else { return nil }
            let nombre = ((p["names"] as? [[String: Any]])?.first?["displayName"] as? String) ?? correo
            let cargo = ((p["organizations"] as? [[String: Any]])?.first?["title"] as? String) ?? ""
            return PersonaGraph(nombre: nombre, correo: correo, cargo: cargo)
        }
    }
}
