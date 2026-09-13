import AppKit
import Darwin
import Foundation

// MARK: - Atajos instalados como herramientas explícitas

enum RiesgoAtajoApple: String, Codable, CaseIterable, Identifiable {
    case lectura, reversible, cambioLocal = "cambio_local", externo, destructivo

    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .lectura: return "Solo lectura"
        case .reversible: return "Reversible"
        case .cambioLocal: return "Cambio local"
        case .externo: return "Acción externa"
        case .destructivo: return "Destructivo"
        }
    }
    var agente: RiesgoAgente {
        switch self {
        case .lectura: return .lectura
        case .reversible: return .reversible
        case .cambioLocal: return .cambioLocal
        case .externo: return .externo
        case .destructivo: return .destructivo
        }
    }
}

struct AtajoAppleDescubierto: Codable, Identifiable, Equatable {
    var id: String                 // UUID estable de Shortcuts, o nombre normalizado
    var nombre: String
    var habilitado: Bool
    var riesgo: RiesgoAtajoApple
    var disponible: Bool

    init(id: String, nombre: String, habilitado: Bool = false,
         riesgo: RiesgoAtajoApple = .externo, disponible: Bool = true) {
        self.id = id; self.nombre = nombre; self.habilitado = habilitado
        self.riesgo = riesgo; self.disponible = disponible
    }
}

enum AppleAtajosCatalogo {
    private static var url: URL { Config.dir.appendingPathComponent("atajos_apple.json") }
    private static let lock = NSLock()

    private static func leerSinLock() -> [AtajoAppleDescubierto] {
        guard let d = try? Data(contentsOf: url),
              let x = try? JSONDecoder().decode([AtajoAppleDescubierto].self, from: d) else { return [] }
        return x
    }

    static func todos() -> [AtajoAppleDescubierto] {
        lock.lock(); defer { lock.unlock() }; return leerSinLock()
    }

    static func guardar(_ items: [AtajoAppleDescubierto]) {
        lock.lock(); defer { lock.unlock() }
        Config.asegurarDirSeguro()
        guard let d = try? JSONEncoder().encode(items) else { return }
        try? d.write(to: url, options: .atomic); Config.protegerSecreto(url)
    }

    private static func riesgoSugerido(_ nombre: String) -> RiesgoAtajoApple {
        let n = PerfilAgente.normalizar(nombre)
        if n.contains("dictation") || n.contains("clipboard") || n.contains("consulta") {
            return .lectura
        }
        if n.contains("musica") || n.contains("abrir") || n.contains("buscar") {
            return .reversible
        }
        if n.contains("home") || n.contains("luces") || n.contains("foco")
            || n.contains("concentracion") || n.contains("modo oficina") || n.contains("modo noche") {
            return .externo
        }
        return .externo
    }

    /// Conserva la decisión del usuario por UUID. Un Atajo recién descubierto
    /// aparece apagado; jamás se convierte en herramienta por el solo hecho de
    /// existir en la biblioteca de macOS.
    static func fusionar(_ encontrados: [(id: String, nombre: String)]) -> [AtajoAppleDescubierto] {
        let previos = todos()
        var porID = Dictionary(uniqueKeysWithValues: previos.map { ($0.id, $0) })
        let porNombre = Dictionary(grouping: previos, by: { PerfilAgente.normalizar($0.nombre) })
        var salida: [AtajoAppleDescubierto] = []
        for e in encontrados {
            var item: AtajoAppleDescubierto
            if let exacto = porID.removeValue(forKey: e.id) {
                item = exacto
            } else if let anterior = porNombre[PerfilAgente.normalizar(e.nombre)]?.first {
                item = anterior
                porID.removeValue(forKey: anterior.id)
            } else {
                item = AtajoAppleDescubierto(id: e.id, nombre: e.nombre,
                                             riesgo: riesgoSugerido(e.nombre))
            }
            item.id = e.id; item.nombre = e.nombre; item.disponible = true
            salida.append(item)
        }
        // Un Atajo borrado conserva su política para reconocerlo si vuelve, pero
        // no puede ejecutarse mientras no esté disponible.
        for var viejo in porID.values {
            viejo.disponible = false; salida.append(viejo)
        }
        salida.sort {
            if $0.disponible != $1.disponible { return $0.disponible && !$1.disponible }
            return $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
        }
        guardar(salida)
        return salida
    }

    static func refrescar(completion: @escaping ([AtajoAppleDescubierto]) -> Void) {
        AppleAtajos.descubrir { completion(fusionar($0)) }
    }

    static func item(nombre: String) -> AtajoAppleDescubierto? {
        let n = PerfilAgente.normalizar(nombre)
        return todos().first { PerfilAgente.normalizar($0.nombre) == n }
    }

    static func permitido(nombre: String) -> Bool {
        guard Config.agenteHerramientaAtajos() else { return false }
        if let x = item(nombre: nombre) { return x.disponible && x.habilitado }
        // Compatibilidad: elegir explícitamente un atajo en los campos antiguos
        // sigue siendo consentimiento, aunque todavía no se haya refrescado lista.
        let n = PerfilAgente.normalizar(nombre)
        return !n.isEmpty && [Config.agenteAtajoApple(), Config.musicaAtajoApple()]
            .contains { PerfilAgente.normalizar($0) == n }
    }

    static func riesgo(nombre: String) -> RiesgoAgente {
        item(nombre: nombre)?.riesgo.agente ?? .externo
    }
}

extension AppleAtajos {
    static func parsearListadoConIdentificadores(_ s: String) -> [(id: String, nombre: String)] {
        let re = try? NSRegularExpression(pattern: #"^(.*)\s+\(([0-9A-Fa-f-]{36})\)$"#)
        return s.split(separator: "\n").compactMap { linea -> (String, String)? in
            let x = String(linea).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !x.isEmpty else { return nil }
            let ns = x as NSString
            guard let m = re?.firstMatch(in: x, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 3 else { return (PerfilAgente.normalizar(x), x) }
            return (ns.substring(with: m.range(at: 2)).uppercased(),
                    ns.substring(with: m.range(at: 1)))
        }.map { (id: $0.0, nombre: $0.1) }
    }

    /// `shortcuts list --show-identifiers` evita confundir dos Atajos con el
    /// mismo nombre. El parser tolera nombres con paréntesis y Unicode.
    static func descubrir(completion: @escaping ([(id: String, nombre: String)]) -> Void) {
        guard disponible else { completion([]); return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["list", "--show-identifiers"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch {
                DispatchQueue.main.async { completion([]) }; return
            }
            let limite = Date().addingTimeInterval(10)
            while p.isRunning, Date() < limite { Thread.sleep(forTimeInterval: 0.05) }
            if p.isRunning {
                p.terminate(); Thread.sleep(forTimeInterval: 0.2)
                if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
            }
            let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                DispatchQueue.main.async { completion([]) }; return
            }
            let s = String(data: data, encoding: .utf8) ?? ""
            let items = parsearListadoConIdentificadores(s)
            DispatchQueue.main.async { completion(items) }
        }
    }

    /// Ejecución comprobable por CLI. A diferencia del esquema shortcuts://,
    /// devuelve código de salida y, si el Atajo produce texto/JSON, lo incorpora
    /// como evidencia. El timeout es finito y los archivos temporales son 0600.
    static func ejecutarVerificado(nombre: String, texto: String, simular: Bool = false,
                                   completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else {
            completion(.init(ok: false, mensaje: "Falta el nombre del Atajo Apple.")); return
        }
        guard AppleAtajosCatalogo.permitido(nombre: n) else {
            completion(.init(ok: false,
                mensaje: "El Atajo «\(n)» no está habilitado como herramienta en Ajustes → Asistente.")); return
        }
        if simular {
            completion(.init(ok: true, mensaje: "Ejecutaría el Atajo habilitado «\(n)».",
                             evidencia: ["atajo": n, "simulado": "true"])); return
        }
        guard disponible else {
            completion(.init(ok: false, mensaje: "La app Atajos no está disponible.")); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let dir = Config.dir.appendingPathComponent("atajos-temp", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            let token = UUID().uuidString
            let input = dir.appendingPathComponent("\(token).txt")
            let output = dir.appendingPathComponent("\(token)-salida.txt")
            let t = String(texto.prefix(20_000))
            if !t.isEmpty {
                try? Data(t.utf8).write(to: input, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
            }
            defer { try? fm.removeItem(at: input); try? fm.removeItem(at: output) }

            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            var args = ["run", n]
            if !t.isEmpty { args += ["--input-path", input.path] }
            args += ["--output-path", output.path]
            p.arguments = args
            let err = Pipe(); p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(.init(ok: false,
                    mensaje: "No pude ejecutar «\(n)»: \(error.localizedDescription)")) }
                return
            }
            let limite = Date().addingTimeInterval(30)
            while p.isRunning, Date() < limite { Thread.sleep(forTimeInterval: 0.05) }
            let expiro = p.isRunning
            if expiro {
                p.terminate(); Thread.sleep(forTimeInterval: 0.2)
                if p.isRunning { Darwin.kill(p.processIdentifier, SIGKILL) }
            }
            p.waitUntilExit()
            if fm.fileExists(atPath: output.path) {
                try? fm.setAttributes([.posixPermissions: 0o600],
                                      ofItemAtPath: output.path)
            }
            let errorData = err.fileHandleForReading.readDataToEndOfFile()
            let errorTexto = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let salida = (try? String(contentsOf: output, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = !expiro && p.terminationStatus == 0
            let mensaje: String
            if expiro { mensaje = "El Atajo «\(n)» excedió 30 segundos y se detuvo." }
            else if ok { mensaje = salida.isEmpty ? "Atajo «\(n)» completado." : salida }
            else { mensaje = errorTexto.isEmpty
                ? "El Atajo «\(n)» terminó con código \(p.terminationStatus)."
                : "El Atajo «\(n)» falló: \(String(errorTexto.prefix(500)))" }
            let evidencia = ["atajo": n, "codigo": "\(p.terminationStatus)",
                              "salida": String(salida.prefix(2_000)), "timeout": "\(expiro)"]
            AgenteLog.registrar("atajo_apple_verificado", ["atajo": n, "ok": ok,
                "codigo": p.terminationStatus, "timeout": expiro,
                "salida": String(salida.prefix(2_000))])
            DispatchQueue.main.async {
                completion(.init(ok: ok, mensaje: mensaje, evidencia: evidencia))
            }
        }
    }
}
