import Foundation

// MARK: - Seguimiento de correos (spec 022)
//
// «Avísame si Paul no me responde hasta el viernes» o «avísame cuando me escriba
// Paul». Se guarda en ~/.btodicta/seguimientos.json y se revisa cada 15 minutos
// con la búsqueda de la cuenta. Sin plazo, se vigila 7 días.

struct Seguimiento: Codable, Equatable {
    var id: String
    var cuenta: String?      // id de la cuenta; nil = la predeterminada
    var persona: String      // nombre o correo, tal como se busca
    var creado: Date
    var hasta: Date
    var conPlazo: Bool       // true = «si no responde hasta…»
}

enum SeguimientoCorreo {
    static var archivo: URL { Config.dir.appendingPathComponent("seguimientos.json") }

    static func todos() -> [Seguimiento] {
        guard let d = try? Data(contentsOf: archivo) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode([Seguimiento].self, from: d)) ?? []
    }

    static func guardar(_ l: [Seguimiento]) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let d = try? enc.encode(l) else { return }
        try? d.write(to: archivo, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archivo.path)
    }

    @discardableResult
    static func agregar(persona: String, cuenta: String?, hasta: Date?, ahora: Date = Date()) -> Seguimiento {
        let s = Seguimiento(id: UUID().uuidString, cuenta: cuenta, persona: persona.trimmingCharacters(in: .whitespacesAndNewlines),
                            creado: ahora, hasta: hasta ?? ahora.addingTimeInterval(7 * 86400), conPlazo: hasta != nil)
        guardar(todos() + [s])
        return s
    }

    static func quitar(_ id: String) { guardar(todos().filter { $0.id != id }) }

    /// Consulta para la búsqueda: el correo tal cual o el nombre (puro).
    static func consulta(_ persona: String) -> String {
        "from:" + persona.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
    }

    enum Resultado: Equatable { case respondio(asunto: String), vencio, sigue }

    /// Qué pasó con un seguimiento según los correos encontrados (puro).
    /// Solo cuenta un correo cuyo remitente es la persona: su dirección exacta si se conoce
    /// (un nombre visible se puede falsificar), o si no, el nombre completo (puro).
    static func esDeLaPersona(_ de: String, persona: String) -> Bool {
        let p = persona.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = de.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un remitente con más de un «<» trae una dirección escondida en el nombre: no cuenta.
        guard t.filter({ $0 == "<" }).count <= 1 else { return false }
        let conAngulos = t.range(of: "<([^<>]+)>$", options: .regularExpression)
        let direccion = conAngulos.map { String(t[$0].dropFirst().dropLast()) } ?? (t.contains("@") ? t : "")
        if p.contains("@") { return direccion.trimmingCharacters(in: .whitespaces).lowercased() == p }
        // Por nombre: el nombre visible completo y exacto (menos seguro: se puede falsificar).
        let nombre = conAngulos.map { String(t[..<$0.lowerBound]) } ?? (t.contains("@") ? "" : t)
        let limpio = nombre.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
        return !limpio.isEmpty && PerfilAgente.normalizar(limpio) == PerfilAgente.normalizar(p)
    }

    static func evaluar(_ s: Seguimiento, correos: [CorreoLeido], ahora: Date = Date()) -> Resultado {
        if let c = correos.filter({ $0.fecha > s.creado && esDeLaPersona($0.de, persona: s.persona) })
            .max(by: { $0.fecha < $1.fecha }) { return .respondio(asunto: c.asunto) }
        return ahora >= s.hasta ? .vencio : .sigue
    }
}
