import Foundation
import Network

// MARK: - API local: que otros programas de la máquina usen los motores
//
// BtoDicta es el único sitio del equipo con los motores de transcripción
// instalados y configurados. Cuando otro proyecto necesitó transcribir, la
// alternativa era duplicar gigabytes de modelos o alcanzar estos recursos desde
// fuera leyendo sus carpetas — que funciona hasta el día en que algo se mueve de
// sitio y el consumidor se rompe sin avisar.
//
// Esto es la puerta con contrato: se pide por HTTP en loopback y se recibe el
// texto. Por dentro usa la MISMA cascada, el MISMO troceo y las MISMAS
// cuarentenas que un dictado, porque un camino paralelo envejecería distinto y
// acabaría comportándose distinto.
//
// **El riesgo de esto no es que falle: es que la puerta quede abierta.** En esta
// máquina hay certificados de firma y credenciales de veintitrés proveedores. De
// ahí las cinco cerraduras de abajo, cada una con su prueba negativa.

enum ApiLocal {

    // MARK: Cerradura 1 — dónde escucha

    /// Loopback y nada más. Ni `0.0.0.0` ni la red local: solo procesos de este
    /// mismo equipo pueden llegar.
    static let host = "127.0.0.1"

    static func puerto() -> UInt16 {
        let p = (Config.json0("api_local_puerto") as? Int) ?? 8787
        return UInt16(min(65535, max(1024, p)))
    }

    /// Apagada de fábrica. Quien no la use no tiene nada abierto.
    static func activa() -> Bool {
        (Config.json0("api_local_activa") as? Bool) ?? false
    }

    // MARK: Cerradura 2 — el token

    static var archivoToken: URL { Config.dir.appendingPathComponent("api-token") }

    /// Lee el token, y lo crea si no había. Permisos 0600: solo su dueño.
    @discardableResult
    static func token() -> String {
        if let t = try? String(contentsOf: archivoToken, encoding: .utf8) {
            let limpio = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !limpio.isEmpty { return limpio }
        }
        return regenerarToken()
    }

    @discardableResult
    static func regenerarToken() -> String {
        // 32 bytes de aleatoriedad del sistema, no de un generador cualquiera.
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let nuevo = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        Config.asegurarDirSeguro()
        try? nuevo.write(to: archivoToken, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: archivoToken.path)
        return nuevo
    }

    /// Compara en tiempo CONSTANTE.
    ///
    /// Una comparación normal se detiene en el primer byte distinto, y esa
    /// diferencia de tiempo —minúscula pero medible— permite adivinar el token
    /// byte a byte probando muchas veces. Aquí se recorren siempre los mismos
    /// bytes y se acumula la diferencia.
    static func tokenValido(_ recibido: String) -> Bool {
        let esperado = Array(token().utf8)
        let dado = Array(recibido.utf8)
        // La longitud sí se puede comparar de golpe: no dice nada del contenido.
        guard esperado.count == dado.count, !esperado.isEmpty else { return false }
        var diferencia: UInt8 = 0
        for i in 0..<esperado.count { diferencia |= esperado[i] ^ dado[i] }
        return diferencia == 0
    }

    // MARK: Cerradura 3 — qué archivos se pueden leer

    /// Carpetas desde las que se acepta transcribir.
    ///
    /// De fábrica: la carpeta temporal del sistema y la de descargas, que es
    /// donde un consumidor deja un audio para que lo transcribamos. **No** el
    /// disco entero: una ruta arbitraria convertiría esta API en un lector
    /// universal de archivos para cualquier proceso que tenga el token.
    static func carpetasPermitidas() -> [String] {
        if let l = Config.json0("api_local_carpetas") as? [String], !l.isEmpty {
            return l.map { ($0 as NSString).expandingTildeInPath }
        }
        let inicio = FileManager.default.homeDirectoryForCurrentUser
        return [FileManager.default.temporaryDirectory.path,
                inicio.appendingPathComponent("Downloads").path,
                inicio.appendingPathComponent("Documents").path]
    }

    enum Rechazo: String, Error, Equatable {
        case sinToken = "falta la cabecera de autorización"
        case tokenMalo = "el token no es válido"
        case rutaFuera = "el archivo está fuera de las carpetas permitidas"
        case noExiste = "el archivo no existe"
        case cuerpoGrande = "la petición es demasiado grande"
        case malFormada = "la petición no se entiende"
        case demasiadas = "demasiadas peticiones seguidas: espera unos segundos"
        case apagada = "la API local está apagada"
    }

    /// Resuelve la ruta y comprueba que cae dentro de lo permitido.
    ///
    /// **Se resuelve ANTES de comparar.** Comparar el texto tal cual deja pasar
    /// un `/tmp/../Users/bto/.ssh/id_rsa`: empieza por una carpeta permitida y
    /// acaba donde no debe. `standardized` colapsa esos saltos.
    static func rutaPermitida(_ ruta: String) -> Result<URL, Rechazo> {
        let url = URL(fileURLWithPath: (ruta as NSString).expandingTildeInPath).standardizedFileURL
        let resuelta = url.resolvingSymlinksInPath().standardizedFileURL
        let dentro = carpetasPermitidas().contains { base in
            let baseURL = URL(fileURLWithPath: base).resolvingSymlinksInPath().standardizedFileURL
            // Con la barra final, para que `/tmp2` no cuele como si fuera `/tmp`.
            let prefijo = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
            return resuelta.path == baseURL.path || resuelta.path.hasPrefix(prefijo)
        }
        guard dentro else { return .failure(.rutaFuera) }
        guard FileManager.default.fileExists(atPath: resuelta.path) else { return .failure(.noExiste) }
        return .success(resuelta)
    }

    // MARK: Cerradura 5 — tamaño

    /// Tope del cuerpo de una petición. El audio va por ruta, así que aquí solo
    /// viaja un JSON pequeño; un megabyte es de sobra y evita que nadie llene la
    /// memoria mandando basura.
    static let topeCuerpo = 1_048_576

    // MARK: Cerradura 6 — cuántas peticiones por minuto

    /// Tope de peticiones por minuto.
    ///
    /// Sin esto, un consumidor con un bucle mal escrito —o con prisa— vacía el
    /// saldo de nube en minutos. El aviso de saldo bajo avisa, pero DESPUÉS. No
    /// es una defensa contra un atacante, que ya tendría el token: es la red
    /// contra el programa propio que se equivoca, que es lo que pasa de verdad.
    static func topePorMinuto() -> Int {
        max(0, (Config.json0("api_local_tope_minuto") as? Int) ?? 30)
    }

    private static let candadoRitmo = NSLock()
    private static var marcas: [Date] = []

    /// `true` si esta petición cabe dentro del tope.
    static func cabeOtraPeticion(ahora: Date = Date()) -> Bool {
        let tope = topePorMinuto()
        guard tope > 0 else { return true }   // 0 = sin tope, decisión del usuario
        candadoRitmo.lock(); defer { candadoRitmo.unlock() }
        marcas.removeAll { ahora.timeIntervalSince($0) > 60 }
        guard marcas.count < tope else { return false }
        marcas.append(ahora)
        return true
    }

    /// Solo para las pruebas: olvida lo contado.
    static func olvidarRitmoQA() {
        candadoRitmo.lock(); marcas.removeAll(); candadoRitmo.unlock()
    }

    // MARK: Servidor

    private static var escucha: NWListener?
    private static let cola = DispatchQueue(label: "red.bto.btodicta.apilocal")

    static func arrancar() {
        guard activa() else { return }
        detener()
        guard let puertoNW = NWEndpoint.Port(rawValue: puerto()) else { return }
        let opciones = NWProtocolTCP.Options()
        opciones.noDelay = true
        let params = NWParameters(tls: nil, tcp: opciones)
        // Aquí es donde se ata a loopback: sin esto escucharía en todas las
        // interfaces, incluida la de la red local.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host),
                                                           port: puertoNW)
        params.allowLocalEndpointReuse = true

        // El puerto va SOLO en `requiredLocalEndpoint`, no también en `on:`.
        // Dárselo por las dos vías hace que el oyente ni siquiera se cree, y el
        // error que se ve es «no pude abrir el puerto», que manda a buscar un
        // conflicto que no existe.
        let l: NWListener
        do { l = try NWListener(using: params) }
        catch {
            Log.log(.sistema, "api local: no pude abrir el puerto \(puerto()) — \(error.localizedDescription)")
            return
        }
        l.newConnectionHandler = { conexion in atender(conexion) }
        l.stateUpdateHandler = { estado in
            if case .ready = estado {
                Log.log(.sistema, "api local: escuchando en \(host):\(puerto()) — solo este equipo, y solo con token")
            }
            if case .failed(let e) = estado {
                Log.log(.sistema, "api local: el puerto falló — \(e.localizedDescription)")
            }
        }
        l.start(queue: cola)
        escucha = l
        token()   // se genera ya, para que esté listo cuando alguien lo pida
    }

    static func detener() {
        escucha?.cancel()
        escucha = nil
    }

    static func reconfigurar() {
        detener()
        if activa() { arrancar() }
    }

    // MARK: Atender una petición

    private static func atender(_ conexion: NWConnection) {
        conexion.start(queue: cola)
        recibir(conexion, acumulado: Data())
    }

    private static func recibir(_ conexion: NWConnection, acumulado: Data) {
        conexion.receive(minimumIncompleteLength: 1, maximumLength: 65536) { datos, _, fin, error in
            if error != nil { conexion.cancel(); return }
            var todo = acumulado
            if let datos { todo.append(datos) }

            guard todo.count <= topeCuerpo else {
                responder(conexion, 413, ["error": Rechazo.cuerpoGrande.rawValue])
                return
            }
            // ¿Están ya las cabeceras y el cuerpo entero?
            if let corte = rangoFinCabeceras(todo) {
                let cabeceras = String(data: todo[..<corte.lowerBound], encoding: .utf8) ?? ""
                let cuerpo = todo[corte.upperBound...]
                let largo = largoDeclarado(cabeceras) ?? 0
                if cuerpo.count >= largo {
                    procesar(conexion, cabeceras: cabeceras, cuerpo: Data(cuerpo.prefix(largo)))
                    return
                }
            }
            if fin { conexion.cancel(); return }
            recibir(conexion, acumulado: todo)
        }
    }

    private static func rangoFinCabeceras(_ d: Data) -> Range<Data.Index>? {
        d.range(of: Data("\r\n\r\n".utf8)) ?? d.range(of: Data("\n\n".utf8))
    }

    private static func largoDeclarado(_ cabeceras: String) -> Int? {
        cabecera("Content-Length", en: cabeceras).flatMap(Int.init)
    }

    /// Busca una cabecera sin distinguir mayúsculas.
    ///
    /// Se hace a mano y no con `split`: las cabeceras vienen separadas por
    /// `\r\n` y algunas —`Host: 127.0.0.1:8787`— llevan dos puntos en su valor,
    /// así que hay que cortar por el PRIMERO y limpiar el retorno de carro.
    private static func cabecera(_ nombre: String, en cabeceras: String) -> String? {
        let buscado = nombre.lowercased() + ":"
        for linea in cabeceras.components(separatedBy: .newlines) {
            let limpia = linea.trimmingCharacters(in: .whitespacesAndNewlines)
            guard limpia.lowercased().hasPrefix(buscado) else { continue }
            return String(limpia.dropFirst(buscado.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func procesar(_ conexion: NWConnection, cabeceras: String, cuerpo: Data) {
        let primera = cabeceras.split(separator: "\n").first.map(String.init) ?? ""
        let trozos = primera.split(separator: " ")
        let metodo = trozos.first.map(String.init) ?? ""
        let ruta = trozos.count > 1 ? String(trozos[1]) : ""

        // `/estado` no pide token: solo dice si hay alguien escuchando, que es
        // justo lo que un consumidor necesita saber ANTES de tener credenciales.
        if metodo == "GET", ruta == "/estado" {
            responder(conexion, 200, ["version": Version.numero,
                                      "listo": true,
                                      "motores": Providers.cadena().count])
            return
        }

        let auth = cabecera("Authorization", en: cabeceras) ?? ""
        guard auth.hasPrefix("Bearer ") else {
            rechazar(conexion, 401, .sinToken); return
        }
        guard tokenValido(String(auth.dropFirst("Bearer ".count))) else {
            rechazar(conexion, 401, .tokenMalo); return
        }

        guard let json = try? JSONSerialization.jsonObject(with: cuerpo) as? [String: Any] else {
            rechazar(conexion, 400, .malFormada); return
        }

        guard cabeOtraPeticion() else {
            rechazar(conexion, 429, .demasiadas); return
        }

        switch (metodo, ruta) {
        case ("POST", "/transcribir"): transcribir(conexion, json)
        case ("POST", "/pulir"):       pulir(conexion, json)
        default:
            responder(conexion, 404, ["error": "no existe \(metodo) \(ruta)"])
        }
    }

    // MARK: Operaciones

    private static func transcribir(_ conexion: NWConnection, _ json: [String: Any]) {
        guard let ruta = json["archivo"] as? String else {
            rechazar(conexion, 400, .malFormada); return
        }
        let url: URL
        switch rutaPermitida(ruta) {
        case .success(let u): url = u
        case .failure(let r): rechazar(conexion, r == .noExiste ? 404 : 403, r); return
        }

        // Vocabulario de contexto: sin él, las siglas propias salen mal. Se
        // pone y se quita alrededor de ESTA petición, para no tocar el glosario
        // del usuario: es suyo, y una petición externa no tiene por qué
        // cambiárselo de forma permanente.
        let vocabulario = (json["vocabulario"] as? [String]) ?? []
        if !vocabulario.isEmpty { Config.glosarioExtraTemporal = vocabulario }

        let motor = (json["motor"] as? String) ?? "automatico"
        let cadena: [Provider]
        switch motor {
        case "local": cadena = Providers.cadena().filter { $0.tipo == "local" }
        case "nube":  cadena = Providers.cadena().filter { $0.tipo != "local" }
        default:      cadena = Providers.cadena()
        }
        guard !cadena.isEmpty else {
            responder(conexion, 503, ["error": "no hay ningún motor \(motor) configurado"]); return
        }

        let t0 = Date()
        // Por RUTA, no por bytes: transcribir un archivo largo desde fuera no
        // tiene por qué cargarlo en memoria (spec 001).
        Failover.transcribe(wav: .archivo(url), cadena: cadena) { r in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if !vocabulario.isEmpty { Config.glosarioExtraTemporal = [] }
            switch r {
            case .success(let (texto, proveedor, modelo)):
                Log.log(.ia, "api local: transcrito \(url.lastPathComponent) con \(proveedor) en \(ms) ms")
                responder(conexion, 200, ["texto": texto, "motor": proveedor,
                                          "modelo": modelo, "ms": ms])
            case .failure(let e):
                Log.log(.ia, "api local: no se pudo transcribir \(url.lastPathComponent) — \(e.localizedDescription)")
                responder(conexion, 502, ["error": e.localizedDescription])
            }
        }
    }

    private static func pulir(_ conexion: NWConnection, _ json: [String: Any]) {
        guard let texto = json["texto"] as? String, !texto.isEmpty else {
            rechazar(conexion, 400, .malFormada); return
        }
        // La MISMA cascada de pulido del dictado, con su failover y su plazo.
        // Si ninguna IA responde devuelve el original, no un error: el texto sin
        // pulir sigue siendo el texto, y perderlo sería peor.
        let proveedor = ChatIA.cadenaPulido().first?.nombre ?? "ninguno"
        LLMPostProcess.enhance(texto) { pulido in
            responder(conexion, 200, ["texto": pulido,
                                      "proveedor": proveedor,
                                      "pulido": pulido != texto])
        }
    }

    // MARK: Respuestas

    private static func rechazar(_ conexion: NWConnection, _ codigo: Int, _ r: Rechazo) {
        // Se anota el motivo, nunca el token recibido ni la ruta pedida: dejar
        // eso en el registro filtraría justo lo que se está protegiendo.
        Log.log(.sistema, "api local: petición rechazada — \(r.rawValue)")
        responder(conexion, codigo, ["error": r.rawValue])
    }

    private static func responder(_ conexion: NWConnection, _ codigo: Int, _ cuerpo: [String: Any]) {
        let datos = (try? JSONSerialization.data(withJSONObject: cuerpo)) ?? Data("{}".utf8)
        let texto = """
        HTTP/1.1 \(codigo) \(codigo == 200 ? "OK" : "Error")\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(datos.count)\r
        Connection: close\r
        \r

        """
        var salida = Data(texto.utf8)
        salida.append(datos)
        conexion.send(content: salida, completion: .contentProcessed { _ in conexion.cancel() })
    }
}
