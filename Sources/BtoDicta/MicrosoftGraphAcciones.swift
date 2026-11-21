import Foundation

// MARK: - Correo, agenda y personas con Microsoft Graph (spec 016)
//
// Todo con permisos delegados: solo la cuenta del usuario y solo mientras su
// sesión es válida. Enviar exige confirmación en quien llama (AppDelegate).

struct PersonaGraph: Equatable {
    let nombre: String
    let correo: String
    let cargo: String
}

struct BorradorGraph: Equatable {
    let id: String
    let asunto: String
    let para: [String]
    let enlace: String
    let inicio: String
    /// Cuerpo completo cuando se conoce (Gmail lo necesita para cambiar solo el asunto).
    var cuerpo: String = ""
}

struct EventoGraph: Equatable {
    let asunto: String
    let inicio: Date
    let fin: Date
    let lugar: String
    let organizador: String
    let todoElDia: Bool
}

extension MicrosoftGraph {
    typealias Fin<T> = (Result<T, ErrorGraph>) -> Void

    // MARK: Llamada genérica (respuesta en main)

    static func llamar(_ metodo: String, _ ruta: String, query: [URLQueryItem] = [],
                       cuerpo: [String: Any]? = nil, cabeceras: [String: String] = [:],
                       fin: @escaping (Int, Any?) -> Void) {
        guard disponible else { DispatchQueue.main.async { fin(-1, nil) }; return }
        conToken { token in
            guard let token else { DispatchQueue.main.async { fin(401, nil) }; return }
            var c = URLComponents(string: "https://graph.microsoft.com/v1.0" + ruta)
            if !query.isEmpty { c?.queryItems = query }
            guard let url = c?.url else { DispatchQueue.main.async { fin(0, nil) }; return }
            var req = URLRequest(url: url)
            req.httpMethod = metodo
            req.timeoutInterval = 25
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            cabeceras.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
            if let cuerpo {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: cuerpo)
            }
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let codigo = error != nil ? 0 : ((resp as? HTTPURLResponse)?.statusCode ?? 0)
                let json = data.flatMap { $0.isEmpty ? nil : try? JSONSerialization.jsonObject(with: $0) }
                if !(200..<300).contains(codigo) {
                    Log.write("correo Microsoft: \(metodo) \(ruta.prefix(40)) → HTTP \(codigo)")
                }
                DispatchQueue.main.async { fin(codigo, json) }
            }.resume()
        }
    }

    static func error(_ codigo: Int) -> ErrorGraph {
        switch codigo {
        case -1: return .sinCuenta
        case 0: return .sinRed
        case 401: return .sesionVencida
        case 403: return .sinPermiso
        default: return .respuesta("HTTP \(codigo)")
        }
    }

    // MARK: Correo

    static func buscarCorreo(_ texto: String, fin: @escaping Fin<[CorreoLeido]>) {
        let q = texto.replacingOccurrences(of: "\"", with: " ").trimmingCharacters(in: .whitespaces)
        llamar("GET", "/me/messages", query: [
            URLQueryItem(name: "$search", value: "\"\(q)\""),
            URLQueryItem(name: "$top", value: "15"),
            URLQueryItem(name: "$select", value: "id,subject,from,receivedDateTime,bodyPreview,importance,isRead"),
        ]) { codigo, json in
            guard codigo == 200, let json,
                  let data = try? JSONSerialization.data(withJSONObject: json),
                  let correos = leerCorreos(data) else { fin(.failure(error(codigo))); return }
            fin(.success(correos))
        }
    }

    static func crearBorrador(para: [String], asunto: String, cuerpo: String, fin: @escaping Fin<BorradorGraph>) {
        llamar("POST", "/me/messages", cuerpo: cuerpoBorrador(para: para, asunto: asunto, cuerpo: cuerpo)) { codigo, json in
            guard codigo == 201, let b = leerBorrador(json) else { fin(.failure(error(codigo))); return }
            fin(.success(b))
        }
    }

    static func modificarBorrador(_ id: String, asunto: String?, cuerpo: String?, fin: @escaping Fin<BorradorGraph>) {
        var c: [String: Any] = [:]
        if let asunto { c["subject"] = asunto }
        if let cuerpo { c["body"] = ["contentType": "Text", "content": cuerpo] }
        llamar("PATCH", "/me/messages/\(id)", cuerpo: c) { codigo, json in
            guard codigo == 200, let b = leerBorrador(json) else { fin(.failure(error(codigo))); return }
            fin(.success(b))
        }
    }

    static func crearRespuesta(_ idMensaje: String, texto: String, fin: @escaping Fin<BorradorGraph>) {
        llamar("POST", "/me/messages/\(idMensaje)/createReply", cuerpo: ["comment": texto]) { codigo, json in
            guard codigo == 201, let b = leerBorrador(json) else { fin(.failure(error(codigo))); return }
            fin(.success(b))
        }
    }

    /// Mueve el correo a la carpeta Archivo (se deshace moviéndolo de vuelta).
    static func archivar(_ idMensaje: String, fin: @escaping Fin<Void>) {
        llamar("POST", "/me/messages/\(idMensaje)/move", cuerpo: ["destinationId": "archive"]) { codigo, _ in
            codigo == 201 ? fin(.success(())) : fin(.failure(error(codigo)))
        }
    }

    static func crearReenvio(_ idMensaje: String, para: String, comentario: String, fin: @escaping Fin<BorradorGraph>) {
        llamar("POST", "/me/messages/\(idMensaje)/createForward", cuerpo: [
            "comment": comentario,
            "toRecipients": [["emailAddress": ["address": para]]],
        ]) { codigo, json in
            guard codigo == 201, let b = leerBorrador(json) else { fin(.failure(error(codigo))); return }
            fin(.success(b))
        }
    }

    /// Lo que se va a enviar de verdad, leído del buzón justo antes: todos los
    /// destinatarios y el texto completo (acotado). nil si no se pudo leer.
    static func detalleParaEnviar(_ id: String, fin: @escaping (String?) -> Void) {
        llamar("GET", "/me/messages/\(id)", query: [
            URLQueryItem(name: "$select", value: "subject,toRecipients,ccRecipients,bccRecipients,body"),
        ], cabeceras: ["Prefer": "outlook.body-content-type=\"text\""]) { codigo, json in
            fin(codigo == 200 ? detalleEnvio(json) : nil)
        }
    }

    static func detalleEnvio(_ json: Any?) -> String? {
        guard let j = json as? [String: Any] else { return nil }
        func lista(_ k: String) -> String {
            ((j[k] as? [[String: Any]]) ?? []).compactMap {
                ($0["emailAddress"] as? [String: Any])?["address"] as? String
            }.joined(separator: ", ")
        }
        let para = lista("toRecipients")
        guard !para.isEmpty else { return nil }
        var t = "Para: \(para)"
        let cc = lista("ccRecipients"), cco = lista("bccRecipients")
        if !cc.isEmpty { t += "\nCC: \(cc)" }
        if !cco.isEmpty { t += "\nCCO: \(cco)" }
        t += "\nAsunto: \((j["subject"] as? String) ?? "")"
        let cuerpo = ((j["body"] as? [String: Any])?["content"] as? String ?? "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        t += "\n\n" + (cuerpo.count > 1500 ? String(cuerpo.prefix(1500)) + "…" : cuerpo)
        return t
    }

    /// Envía un borrador. Quien llama YA pidió la confirmación del usuario.
    static func enviarBorrador(_ id: String, fin: @escaping Fin<Void>) {
        llamar("POST", "/me/messages/\(id)/send") { codigo, _ in
            codigo == 202 ? fin(.success(())) : fin(.failure(error(codigo)))
        }
    }

    // MARK: Personas

    /// Primero personas frecuentes; si no hay nadie con correo, el directorio.
    static func buscarPersonas(_ nombre: String, fin: @escaping Fin<[PersonaGraph]>) {
        let n = nombre.replacingOccurrences(of: "\"", with: " ").trimmingCharacters(in: .whitespaces)
        llamar("GET", "/me/people", query: [
            URLQueryItem(name: "$search", value: "\"\(n)\""),
            URLQueryItem(name: "$top", value: "5"),
            URLQueryItem(name: "$select", value: "displayName,scoredEmailAddresses,jobTitle"),
        ]) { codigo, json in
            let frecuentes = codigo == 200 ? leerPersonas(json) : []
            if !frecuentes.isEmpty { fin(.success(frecuentes)); return }
            llamar("GET", "/users", query: [
                URLQueryItem(name: "$search", value: "\"displayName:\(n)\""),
                URLQueryItem(name: "$top", value: "5"),
                URLQueryItem(name: "$select", value: "displayName,mail,jobTitle"),
            ], cabeceras: ["ConsistencyLevel": "eventual"]) { c2, j2 in
                guard c2 == 200 else { fin(codigo == 200 ? .success([]) : .failure(error(c2))); return }
                fin(.success(leerUsuarios(j2)))
            }
        }
    }

    // MARK: Agenda

    static func agenda(dias: Int, ahora: Date = Date(), fin: @escaping Fin<[EventoGraph]>) {
        let d = min(7, max(1, dias))
        let inicio = Calendar.current.startOfDay(for: ahora)
        let final = inicio.addingTimeInterval(Double(d) * 86_400)
        llamar("GET", "/me/calendarView", query: [
            URLQueryItem(name: "startDateTime", value: utc(inicio)),
            URLQueryItem(name: "endDateTime", value: utc(final)),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: "50"),
            URLQueryItem(name: "$select", value: "subject,start,end,location,organizer,isAllDay"),
        ]) { codigo, json in
            guard codigo == 200 else { fin(.failure(error(codigo))); return }
            fin(.success(leerEventos(json)))
        }
    }

    /// Evento propio, sin invitados (invitar enviaría correos).
    static func crearEvento(asunto: String, inicio: Date, fin finEvento: Date, lugar: String?,
                            fin: @escaping Fin<EventoGraph>) {
        var c: [String: Any] = ["subject": asunto,
                                "start": ["dateTime": utc(inicio, conZona: false), "timeZone": "UTC"],
                                "end": ["dateTime": utc(finEvento, conZona: false), "timeZone": "UTC"]]
        if let lugar, !lugar.isEmpty { c["location"] = ["displayName": lugar] }
        llamar("POST", "/me/events", cuerpo: c) { codigo, json in
            guard codigo == 201 else { fin(.failure(error(codigo))); return }
            fin(.success(leerEventos(["value": [json ?? [:]]]).first
                ?? EventoGraph(asunto: asunto, inicio: inicio, fin: finEvento, lugar: lugar ?? "",
                               organizador: "", todoElDia: false)))
        }
    }

    // MARK: Puras (probadas)

    static func utc(_ d: Date, conZona: Bool = true) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = conZona ? "yyyy-MM-dd'T'HH:mm:ss'Z'" : "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: d)
    }

    static func cuerpoBorrador(para: [String], asunto: String, cuerpo: String) -> [String: Any] {
        ["subject": asunto,
         "body": ["contentType": "Text", "content": cuerpo],
         "toRecipients": para.map { ["emailAddress": ["address": $0]] }]
    }

    static func leerBorrador(_ json: Any?) -> BorradorGraph? {
        guard let j = json as? [String: Any], let id = j["id"] as? String, !id.isEmpty else { return nil }
        let para = ((j["toRecipients"] as? [[String: Any]]) ?? []).compactMap {
            ($0["emailAddress"] as? [String: Any])?["address"] as? String
        }
        let cuerpo = ((j["body"] as? [String: Any])?["content"] as? String) ?? (j["bodyPreview"] as? String) ?? ""
        return BorradorGraph(id: id, asunto: (j["subject"] as? String) ?? "", para: para,
                             enlace: (j["webLink"] as? String) ?? "",
                             inicio: String(cuerpo.prefix(200)), cuerpo: cuerpo)
    }

    static func leerPersonas(_ json: Any?) -> [PersonaGraph] {
        guard let lista = (json as? [String: Any])?["value"] as? [[String: Any]] else { return [] }
        return lista.compactMap { p in
            let correo = ((p["scoredEmailAddresses"] as? [[String: Any]])?.first?["address"] as? String) ?? ""
            guard !correo.isEmpty else { return nil }
            return PersonaGraph(nombre: (p["displayName"] as? String) ?? correo, correo: correo,
                                cargo: (p["jobTitle"] as? String) ?? "")
        }
    }

    static func leerUsuarios(_ json: Any?) -> [PersonaGraph] {
        guard let lista = (json as? [String: Any])?["value"] as? [[String: Any]] else { return [] }
        return lista.compactMap { u in
            guard let correo = u["mail"] as? String, !correo.isEmpty else { return nil }
            return PersonaGraph(nombre: (u["displayName"] as? String) ?? correo, correo: correo,
                                cargo: (u["jobTitle"] as? String) ?? "")
        }
    }

    static func leerEventos(_ json: Any?) -> [EventoGraph] {
        guard let lista = (json as? [String: Any])?["value"] as? [[String: Any]] else { return [] }
        func fecha(_ o: Any?) -> Date? {
            guard let d = o as? [String: Any], let t = d["dateTime"] as? String else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")   // sin «Prefer», Graph devuelve UTC
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f.date(from: String(t.prefix(19)))
        }
        return lista.compactMap { e in
            guard let i = fecha(e["start"]), let f = fecha(e["end"]) else { return nil }
            let org = (((e["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any])?["name"] as? String) ?? ""
            return EventoGraph(asunto: (e["subject"] as? String) ?? "(sin título)", inicio: i, fin: f,
                               lugar: ((e["location"] as? [String: Any])?["displayName"] as? String) ?? "",
                               organizador: org, todoElDia: (e["isAllDay"] as? Bool) ?? false)
        }
    }

    static func agendaParaIA(_ eventos: [EventoGraph]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEEE d 'de' MMMM, HH:mm"
        return eventos.prefix(50).enumerated().map { i, e in
            "\(i + 1). \(e.todoElDia ? "Todo el día" : f.string(from: e.inicio)) — \(e.asunto)"
                + (e.lugar.isEmpty ? "" : " · \(e.lugar)") + (e.organizador.isEmpty ? "" : " · organiza \(e.organizador)")
        }.joined(separator: "\n")
    }

    static func personasHabladas(_ p: [PersonaGraph]) -> String {
        p.prefix(3).map { "\($0.nombre)\($0.cargo.isEmpty ? "" : ", \($0.cargo)"), \($0.correo)" }
            .joined(separator: "; ")
    }
}
