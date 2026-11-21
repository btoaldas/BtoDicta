import Foundation

// MARK: - Varias cuentas de Microsoft y Google (spec 018)
//
// Registro en ~/.btodicta/cuentas.json (0600). Cada cuenta guarda su sesión en
// el Llavero, en su propia entrada. La cuenta Microsoft de antes (una sola) se
// migra la primera vez, sin reconectar.

enum ProveedorNube: String, Codable, CaseIterable {
    case microsoft, google
    var nombre: String { self == .microsoft ? "Microsoft" : "Google" }
}

struct CuentaNube: Codable, Equatable, Identifiable {
    var id: String
    var proveedor: ProveedorNube
    var alias: String
    var correo: String
    var clientID: String
    var tenant: String
    var llavero: String
    var predeterminada: Bool

    var etiqueta: String { correo.isEmpty ? alias : "\(alias) (\(correo))" }
}

enum CuentasNube {
    static var archivo: URL { Config.dir.appendingPathComponent("cuentas.json") }
    static let llaveroMicrosoftAnterior = "microsoft-graph-refresh"
    private static let lock = NSLock()

    static func todas() -> [CuentaNube] {
        lock.lock(); defer { lock.unlock() }
        if let d = try? Data(contentsOf: archivo),
           let c = try? JSONDecoder().decode([CuentaNube].self, from: d) { return c }
        // Migración: la única cuenta Microsoft de antes pasa al registro.
        let id = Config.graphClientID().trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, SecretosKeychain.leer(cuenta: llaveroMicrosoftAnterior) != nil else { return [] }
        let migrada = CuentaNube(id: "microsoft-1", proveedor: .microsoft, alias: "Microsoft", correo: "",
                                 clientID: id, tenant: Config.graphTenant(), llavero: llaveroMicrosoftAnterior,
                                 predeterminada: true)
        escribir([migrada])
        Log.write("cuentas: migrada la cuenta Microsoft anterior al registro")
        return [migrada]
    }

    static func guardar(_ c: [CuentaNube]) { lock.lock(); escribir(c); lock.unlock() }

    private static func escribir(_ c: [CuentaNube]) {
        guard let d = try? JSONEncoder().encode(c) else { return }
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        try? d.write(to: archivo, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archivo.path)
    }

    @discardableResult
    static func agregar(proveedor: ProveedorNube, alias: String, clientID: String, tenant: String) -> CuentaNube {
        var lista = todas()
        let id = "\(proveedor.rawValue)-\(UUID().uuidString.prefix(8).lowercased())"
        let c = CuentaNube(id: id, proveedor: proveedor, alias: alias.isEmpty ? proveedor.nombre : alias, correo: "",
                           clientID: clientID.trimmingCharacters(in: .whitespaces),
                           tenant: tenant.trimmingCharacters(in: .whitespaces),
                           llavero: "cuenta-\(id)-refresh", predeterminada: lista.isEmpty)
        lista.append(c); guardar(lista)
        return c
    }

    static func actualizar(_ c: CuentaNube) {
        var lista = todas()
        guard let i = lista.firstIndex(where: { $0.id == c.id }) else { return }
        lista[i] = c; guardar(lista)
    }

    /// Quita la cuenta y SOLO su sesión del Llavero (y su secreto, si tiene).
    static func quitar(_ id: String) {
        var lista = todas()
        guard let i = lista.firstIndex(where: { $0.id == id }) else { return }
        let c = lista.remove(at: i)
        SecretosKeychain.borrar(cuenta: c.llavero)
        SecretosKeychain.borrar(cuenta: llaveSecreto(c))
        if c.predeterminada, !lista.isEmpty { lista[0].predeterminada = true }
        guardar(lista)
        Log.write("cuentas: quitada una cuenta de \(c.proveedor.nombre)")
    }

    static func predeterminar(_ id: String) {
        guardar(todas().map { var c = $0; c.predeterminada = ($0.id == id); return c })
    }

    static func conectada(_ c: CuentaNube) -> Bool { SecretosKeychain.leer(cuenta: c.llavero) != nil }
    static func llaveSecreto(_ c: CuentaNube) -> String { "cuenta-\(c.id)-secreto" }

    static var conectadas: [CuentaNube] { todas().filter(conectada) }

    /// La cuenta que nombra el usuario (nombre corto, correo o proveedor); si no
    /// nombra ninguna, la predeterminada conectada.
    static func elegir(_ pista: String?, entre lista: [CuentaNube] = conectadas) -> CuentaNube? {
        let p = PerfilAgente.normalizar(pista ?? "")
        if !p.isEmpty {
            if let c = lista.first(where: { PerfilAgente.normalizar($0.alias) == p || $0.correo.lowercased() == p }) { return c }
            if let c = lista.first(where: { p.contains(PerfilAgente.normalizar($0.alias)) && !$0.alias.isEmpty }) { return c }
            if let c = lista.first(where: { !$0.correo.isEmpty && p.contains($0.correo.lowercased()) }) { return c }
            let deProveedor = lista.filter { p.contains($0.proveedor.rawValue) || (p.contains("gmail") && $0.proveedor == .google)
                || ((p.contains("outlook") || p.contains("office")) && $0.proveedor == .microsoft) }
            if let c = deProveedor.first(where: \.predeterminada) ?? deProveedor.first { return c }
        }
        return lista.first(where: \.predeterminada) ?? lista.first
    }

    /// Línea para el prompt: qué cuentas hay y cuál es la predeterminada.
    static func paraIA(_ lista: [CuentaNube] = conectadas) -> String {
        lista.map { "\($0.alias) — \($0.proveedor.nombre)\($0.correo.isEmpty ? "" : ", \($0.correo)")\($0.predeterminada ? " (predeterminada)" : "")" }
            .joined(separator: "; ")
    }
}

// MARK: - Operaciones comunes de correo, agenda y personas

/// Las mismas operaciones para Microsoft y Google, sobre una cuenta concreta.
struct OperacionesCorreo {
    typealias ErrorG = MicrosoftGraph.ErrorGraph
    typealias Fin<T> = (Result<T, ErrorG>) -> Void
    let cuenta: CuentaNube?

    private var google: CuentaNube? { cuenta?.proveedor == .google ? cuenta : nil }
    private func usarMicrosoft() { if cuenta?.proveedor == .microsoft { MicrosoftGraph.usar(cuenta) } }
    private func noGmail<T>(_ fin: Fin<T>) { fin(.failure(.respuesta("todavía no disponible en Gmail"))) }

    func leerBandeja(dias: Int, fin: @escaping Fin<[CorreoLeido]>) {
        if let g = google { GoogleCuenta.leerBandeja(g, dias: dias, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.leerBandeja(dias: dias, fin: fin) }
    }
    func buscarCorreo(_ t: String, fin: @escaping Fin<[CorreoLeido]>) {
        if let g = google { GoogleCuenta.buscarCorreo(g, t, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.buscarCorreo(t, fin: fin) }
    }
    func buscarPersonas(_ n: String, fin: @escaping Fin<[PersonaGraph]>) {
        if let g = google { GoogleCuenta.buscarPersonas(g, n, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.buscarPersonas(n, fin: fin) }
    }
    func crearBorrador(para: [String], asunto: String, cuerpo: String, fin: @escaping Fin<BorradorGraph>) {
        if let g = google { GoogleCuenta.crearBorrador(g, para: para, asunto: asunto, cuerpo: cuerpo, fin: fin) }
        else { usarMicrosoft(); MicrosoftGraph.crearBorrador(para: para, asunto: asunto, cuerpo: cuerpo, fin: fin) }
    }
    func modificarBorrador(_ b: BorradorGraph, asunto: String?, cuerpo: String?, fin: @escaping Fin<BorradorGraph>) {
        if let g = google { GoogleCuenta.modificarBorrador(g, b, asunto: asunto, cuerpo: cuerpo, fin: fin) }
        else { usarMicrosoft(); MicrosoftGraph.modificarBorrador(b.id, asunto: asunto, cuerpo: cuerpo, fin: fin) }
    }
    func crearRespuesta(_ id: String, texto: String, fin: @escaping Fin<BorradorGraph>) {
        if google != nil { noGmail(fin) } else { usarMicrosoft(); MicrosoftGraph.crearRespuesta(id, texto: texto, fin: fin) }
    }
    func crearReenvio(_ id: String, para: String, comentario: String, fin: @escaping Fin<BorradorGraph>) {
        if google != nil { noGmail(fin) } else { usarMicrosoft(); MicrosoftGraph.crearReenvio(id, para: para, comentario: comentario, fin: fin) }
    }
    func detalleParaEnviar(_ id: String, fin: @escaping (String?) -> Void) {
        if let g = google { GoogleCuenta.detalleParaEnviar(g, id, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.detalleParaEnviar(id, fin: fin) }
    }
    func enviarBorrador(_ id: String, fin: @escaping Fin<Void>) {
        if let g = google { GoogleCuenta.enviarBorrador(g, id, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.enviarBorrador(id, fin: fin) }
    }
    func agenda(dias: Int, fin: @escaping Fin<[EventoGraph]>) {
        if let g = google { GoogleCuenta.agenda(g, dias: dias, fin: fin) } else { usarMicrosoft(); MicrosoftGraph.agenda(dias: dias, fin: fin) }
    }
    func crearEvento(asunto: String, inicio: Date, fin finEv: Date, lugar: String?, fin: @escaping Fin<EventoGraph>) {
        if let g = google { GoogleCuenta.crearEvento(g, asunto: asunto, inicio: inicio, fin: finEv, lugar: lugar, fin: fin) }
        else { usarMicrosoft(); MicrosoftGraph.crearEvento(asunto: asunto, inicio: inicio, fin: finEv, lugar: lugar, fin: fin) }
    }
}

extension CuentasNube {
    /// ¿Hay alguna cuenta lista para el asistente?
    static var hayDisponible: Bool { Config.agenteGraphActivo() && !conectadas.isEmpty }
}
