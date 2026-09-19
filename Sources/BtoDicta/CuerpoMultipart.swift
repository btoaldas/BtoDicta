import Foundation

// MARK: - El cuerpo de la subida, en disco y no en memoria
//
// Los doce motores de transcripción armaban su `multipart/form-data` en una
// `Data`: cabeceras + el audio entero + cierre. Con el audio ya cargado en otra
// `Data`, un dictado de seis horas necesitaba ~1,4 GB en el instante del envío
// —691 MB del audio y otros tantos del cuerpo que lo contiene—.
//
// Aquí el cuerpo se escribe a un archivo temporal copiando el audio del origen
// por ventanas, así que en ningún momento hay más de una ventana en memoria. El
// llamador sube con `uploadTask(with:fromFile:)`, que transmite desde disco.
//
// Por qué un temporal y no `httpBodyStream`: un flujo no se puede rebobinar, y
// esta aplicación reintenta en cascada por diseño. El primer reintento mandaría
// un cuerpo vacío. Detalle en `docs/adr/001-cuerpo-de-subida-en-disco.md`.

enum CuerpoMultipart {

    /// Cuánto se copia de una vez. 64 KB es el compromiso habitual: bastante
    /// para que la llamada al sistema no domine, poco para que la huella no se
    /// note.
    static let ventana = 64 * 1024

    /// De dónde sale el audio. `archivo` es el camino que ahorra memoria;
    /// `datos` queda para quien ya lo tiene en memoria por otra razón —un tramo
    /// que el troceo acaba de partir, por ejemplo—.
    enum Origen {
        case archivo(URL)
        case datos(Data)

        /// El audio en memoria. **Solo para quien no pueda evitarlo**: leerlo
        /// es justamente lo que esta spec quita. Cada llamada que quede es una
        /// copia completa del dictado.
        func leer() -> Data {
            switch self {
            case .archivo(let u): return (try? Data(contentsOf: u)) ?? Data()
            case .datos(let d): return d
            }
        }

        /// Los primeros `n` bytes, sin cargar el resto. Sirve para mirar una
        /// cabecera —si es un WAV, por ejemplo— sin pagar una copia completa.
        func primerosBytes(_ n: Int) -> Data {
            switch self {
            case .datos(let d): return d.prefix(n)
            case .archivo(let u):
                guard let h = try? FileHandle(forReadingFrom: u) else { return Data() }
                defer { try? h.close() }
                return (try? h.read(upToCount: n)) ?? Data()
            }
        }

        /// Una ruta en la carpeta temporal que apunta al MISMO audio, sin
        /// copiarlo: un enlace duro cuando el sistema lo permite.
        ///
        /// Los binarios locales escriben su salida junto al archivo de entrada,
        /// así que no se les puede dar el del historial —les ensuciaría la
        /// carpeta—, pero tampoco hace falta duplicar seiscientos megas para
        /// eso. Un enlace duro es una entrada de directorio más apuntando a los
        /// mismos bloques: cuesta lo mismo con un segundo de audio que con seis
        /// horas. Si el sistema no lo permite —otro volumen— se copia, que es lo
        /// que se hacía siempre.
        ///
        /// Devuelve la ruta y si hay que retirarla al terminar.
        func enlaceTemporal(prefijo: String) -> (url: URL, retirar: Bool)? {
            let fm = FileManager.default
            let destino = fm.temporaryDirectory
                .appendingPathComponent("\(prefijo)-\(UUID().uuidString).wav")
            if let propio = archivoURL {
                if (try? fm.linkItem(at: propio, to: destino)) != nil { return (destino, true) }
                if (try? fm.copyItem(at: propio, to: destino)) != nil { return (destino, true) }
                return nil
            }
            guard (try? leer().write(to: destino)) != nil else { return nil }
            return (destino, true)
        }

        /// Ejecuta el bloque con una RUTA de archivo, venga el audio de donde
        /// venga. Si ya está en disco se usa el suyo tal cual; si está en
        /// memoria se escribe un temporal y se retira al salir.
        ///
        /// Para los motores locales, que pasan el audio a un binario o a un
        /// servidor y necesitan un archivo: antes leían los bytes y los volvían
        /// a escribir, o sea dos copias completas de algo que ya estaba en disco.
        func conArchivo<T>(_ bloque: (URL) throws -> T) rethrows -> T? {
            switch self {
            case .archivo(let u):
                return try bloque(u)
            case .datos(let d):
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("btodicta-local-\(UUID().uuidString).wav")
                guard (try? d.write(to: tmp)) != nil else { return nil }
                defer { try? FileManager.default.removeItem(at: tmp) }
                return try bloque(tmp)
            }
        }

        /// La ruta, si la hay. Permite subir con `fromFile:` sin pasar por RAM.
        var archivoURL: URL? {
            if case .archivo(let u) = self { return u }
            return nil
        }

        var bytes: Int {
            switch self {
            case .archivo(let u):
                return ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int) ?? 0
            case .datos(let d):
                return d.count
            }
        }
    }

    /// Un cuerpo listo para subir. **Hay que llamar a `limpiar()`** pase lo que
    /// pase: éxito, error o cancelación.
    struct Preparado {
        let url: URL
        let boundary: String
        let bytes: Int

        func limpiar() {
            try? FileManager.default.removeItem(at: url)
            CuerpoMultipart.contarBorrado()
        }
    }

    // MARK: Contadores, para poder comprobar que no se queda ninguno

    private static let candado = NSLock()
    private static var creados = 0
    private static var borrados = 0

    static func contarBorrado() {
        candado.lock(); borrados += 1; candado.unlock()
    }

    /// Cuántos temporales se crearon y cuántos se borraron en esta sesión. Si no
    /// coinciden al final de una tanda, la limpieza falla aunque la memoria
    /// salga bien.
    static func balance() -> (creados: Int, borrados: Int) {
        candado.lock(); defer { candado.unlock() }
        return (creados, borrados)
    }

    // MARK: Carpeta

    static var carpeta: URL {
        Config.dir.appendingPathComponent("tmp", isDirectory: true)
    }

    /// Barre los temporales que hayan quedado de una sesión anterior —un cierre
    /// inesperado, un corte de luz—. Solo toca lo que crea esta función: el
    /// prefijo y la carpeta son suyos.
    @discardableResult
    static func barrerHuerfanos() -> Int {
        let fm = FileManager.default
        guard let lista = try? fm.contentsOfDirectory(at: carpeta,
                                                      includingPropertiesForKeys: nil) else { return 0 }
        var n = 0
        for u in lista where u.lastPathComponent.hasPrefix("subida-") {
            if (try? fm.removeItem(at: u)) != nil { n += 1 }
        }
        if n > 0 { Log.log(.sistema, "subida: barridos \(n) cuerpos temporales de una sesión anterior") }
        return n
    }

    // MARK: Construcción

    enum Fallo: Error, LocalizedError {
        case noPudeCrear(String)
        case noPudeLeerAudio(String)

        var errorDescription: String? {
            switch self {
            case .noPudeCrear(let p): return "no pude preparar el envío en disco (\(p))"
            case .noPudeLeerAudio(let p): return "no pude leer el audio a enviar (\(p))"
            }
        }
    }

    /// Escribe el cuerpo completo a un temporal y devuelve dónde quedó.
    ///
    /// - `campos`: los pares nombre/valor que van antes del archivo, **en orden**.
    /// - `nombreCampo`, `nombreArchivo`, `tipo`: lo que describía el `Content-Disposition`
    ///   del archivo en el camino anterior.
    ///
    /// El resultado es byte a byte el mismo cuerpo que producía la versión en
    /// memoria; `BTODICTA_SUBIDATEST` lo comprueba.
    static func construir(boundary: String,
                          campos: [(String, String)],
                          nombreCampo: String = "file",
                          nombreArchivo: String,
                          tipo: String,
                          audio: Origen,
                          camposDespues: [(String, String, String?)] = []) throws -> Preparado {
        let fm = FileManager.default
        Config.asegurarDirSeguro()
        try? fm.createDirectory(at: carpeta, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        let destino = carpeta.appendingPathComponent("subida-\(UUID().uuidString).bin")
        guard fm.createFile(atPath: destino.path, contents: nil,
                            attributes: [.posixPermissions: 0o600]),
              let salida = try? FileHandle(forWritingTo: destino) else {
            throw Fallo.noPudeCrear(destino.lastPathComponent)
        }
        candado.lock(); creados += 1; candado.unlock()

        // Si algo sale mal a mitad, el temporal no se queda: se borra y se
        // cuenta, para que el balance siga cuadrando.
        var completado = false
        defer {
            try? salida.close()
            if !completado {
                try? fm.removeItem(at: destino)
                contarBorrado()
            }
        }

        func escribir(_ s: String) throws {
            try salida.write(contentsOf: Data(s.utf8))
        }

        for (nombre, valor) in campos {
            try escribir("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombre)\"\r\n\r\n\(valor)\r\n")
        }
        try escribir("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombreCampo)\"; filename=\"\(nombreArchivo)\"\r\nContent-Type: \(tipo)\r\n\r\n")

        switch audio {
        case .datos(let d):
            try salida.write(contentsOf: d)
        case .archivo(let origen):
            guard let entrada = try? FileHandle(forReadingFrom: origen) else {
                throw Fallo.noPudeLeerAudio(origen.lastPathComponent)
            }
            defer { try? entrada.close() }
            // El bucle es lo que evita los 691 MB: nunca hay más de una ventana
            // en memoria, y `autoreleasepool` impide que se acumulen entre vueltas.
            while true {
                let trozo = autoreleasepool { () -> Data in
                    (try? entrada.read(upToCount: ventana)) ?? Data()
                }
                if trozo.isEmpty { break }
                try salida.write(contentsOf: trozo)
            }
        }
        // Algunas API ponen campos DESPUÉS del archivo (Azure manda ahí su
        // `definition`), y el orden de las partes no es indiferente para ellas.
        if camposDespues.isEmpty {
            try escribir("\r\n--\(boundary)--\r\n")
        } else {
            for (nombre, valor, tipoCampo) in camposDespues {
                let cabeceraTipo = tipoCampo.map { "Content-Type: \($0)\r\n" } ?? ""
                try escribir("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombre)\"\r\n\(cabeceraTipo)\r\n\(valor)")
            }
            try escribir("\r\n--\(boundary)--\r\n")
        }
        try? salida.synchronize()

        let bytes = ((try? fm.attributesOfItem(atPath: destino.path))?[.size] as? Int) ?? 0
        completado = true
        return Preparado(url: destino, boundary: boundary, bytes: bytes)
    }

    // MARK: Subida

    /// Sube un cuerpo ya preparado y **limpia el temporal pase lo que pase**.
    /// Es el único sitio donde se llama a `uploadTask(with:fromFile:)`, para que
    /// no se pueda olvidar la limpieza en ningún motor.
    static func subir(_ req: URLRequest, cuerpo: Preparado,
                      sesion: URLSession? = nil,
                      completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        (sesion ?? RedDictado.sesion()).uploadTask(with: req, fromFile: cuerpo.url) { d, r, e in
            cuerpo.limpiar()
            completion(d, r, e)
        }.resume()
    }

    /// Sube el audio TAL CUAL, sin envolverlo en multipart: lo piden las APIs
    /// que reciben los bytes del WAV en el cuerpo. Si viene de un archivo se
    /// transmite desde disco; si ya está en memoria, se manda como estaba.
    static func subirCrudo(_ req: URLRequest, audio: Origen,
                           completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        if let url = audio.archivoURL {
            RedDictado.sesion().uploadTask(with: req, fromFile: url) { d, r, e in
                completion(d, r, e)
            }.resume()
        } else {
            RedDictado.sesion().uploadTask(with: req, from: audio.leer()) { d, r, e in
                completion(d, r, e)
            }.resume()
        }
    }

    /// El mismo cuerpo, pero en memoria. Es el camino ANTERIOR, conservado solo
    /// para que `BTODICTA_SUBIDATEST` pueda comparar contra él. No lo usa ningún
    /// motor.
    static func construirEnMemoria(boundary: String,
                                   campos: [(String, String)],
                                   nombreCampo: String = "file",
                                   nombreArchivo: String,
                                   tipo: String,
                                   audio: Data) -> Data {
        var body = Data()
        for (nombre, valor) in campos {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombre)\"\r\n\r\n\(valor)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(nombreCampo)\"; filename=\"\(nombreArchivo)\"\r\nContent-Type: \(tipo)\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
