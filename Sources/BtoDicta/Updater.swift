import AppKit
import CryptoKit
import Foundation
import Security

// MARK: - Actualización desde la app (GitHub Releases)
//
// "Verificar actualización" consulta el último release del repo; si hay
// versión nueva descarga el DMG, lo monta, se reemplaza en /Applications
// y se relanza. Si no, avisa que ya estás al día.

enum Updater {
    static let repo = "btoaldas/BtoDicta"

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease, draft, body, assets
        }
    }

    enum Estado: Equatable {
        case reposo
        case buscando
        case alDia
        case disponible(version: String, dmg: URL, notas: String)
        case descargando(Double)     // 0..1
        case error(String)
    }

    /// Resultado de la búsqueda al arrancar (si hubo). Lo lee el pie del panel
    /// de Ajustes (para mostrar "Actualización disponible" sin volver a buscar)
    /// y el menú de la barra (para el ítem "Actualización disponible"). Se
    /// setea solo cuando hay versión nueva.
    static var disponibleAlArrancar: Estado?
    /// Último resultado de cualquier búsqueda: arranque, manual o periódica.
    /// Permite que una ventana abierta deje de mostrar eternamente "al día".
    static private(set) var ultimoEstado: Estado = .reposo
    static private(set) var ultimaRevision: Date?
    /// Aviso a la UI de que cambió `disponibleAlArrancar` (menú/panel refrescan).
    static let notificacion = Notification.Name("betoUpdateDisponible")
    /// ¿Hay un dictado en curso? Lo inyecta AppDelegate. Sirve para NO
    /// auto-instalar (que reinicia la app) a mitad de una grabación.
    static var estaGrabando: () -> Bool = { false }
    private static var timerRevision: Timer?
    private static var verificando = false
    private static var completionsPendientes: [(Estado) -> Void] = []
    private static var reverificarPorCambioDeCanal = false

    /// Búsqueda al abrir la app (silenciosa). Todo esto corre en el hilo main
    /// (verificar completa en main), así que `disponibleAlArrancar` no compite
    /// con las lecturas de la UI/menú.
    static func buscarAlArrancar() {
        guard Config.buscarUpdateAlAbrir() else { return }
        verificar { manejarAutomatico($0, origen: "arranque") }
    }

    /// Revisión tipo cron dentro de la app. Se reprograma al cambiar el ajuste;
    /// Timer usa el run loop común para seguir funcionando con menús abiertos.
    static func iniciarMonitoreo() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { iniciarMonitoreo() }
            return
        }
        timerRevision?.invalidate()
        timerRevision = nil
        guard Config.actualizacionPeriodica() else {
            Log.log(.sistema, "actualización periódica: desactivada")
            return
        }
        let segundos = Config.actualizacionIntervaloHoras() * 3_600
        let t = Timer(timeInterval: segundos, repeats: true) { _ in
            verificar { manejarAutomatico($0, origen: "periódica") }
        }
        t.tolerance = min(300, segundos * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timerRevision = t
        Log.log(.sistema, "actualización periódica: cada \(Config.actualizacionIntervaloHoras()) h")
    }

    /// Cambiar de canal mientras una consulta está en vuelo no debe reutilizar
    /// el resultado del canal anterior: agenda una nueva ronda al terminar.
    static func verificarTrasCambiarCanal() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { verificarTrasCambiarCanal() }
            return
        }
        if verificando {
            reverificarPorCambioDeCanal = true
        } else {
            verificar { _ in }
        }
    }

    private static func manejarAutomatico(_ estado: Estado, origen: String) {
        guard case .disponible(let v, let dmg, _) = estado else { return }
        // Autoactualizar nunca corta un dictado. Si estaba grabando, la versión
        // permanece visible y la próxima ronda vuelve a intentarlo.
        if Config.autoactualizar(), !estaGrabando() {
            Log.log(.sistema, "autoactualizar (\(origen)): bajando e instalando v\(v)…")
            actualizar(dmg: dmg) { _ in }
        } else if Config.autoactualizar() {
            Log.log(.sistema, "autoactualizar diferido: hay un dictado en curso")
        } else {
            Log.log(.sistema, "actualización v\(v) disponible (\(origen))")
        }
    }

    /// Consulta releases estables Y prereleases. GitHub `/releases/latest`
    /// excluye betas y devuelve 404 cuando todos son beta; por eso el canal beta
    /// usa la lista general y el estable conserva `latest` con failover a lista.
    /// Las llamadas simultáneas se consolidan en una sola consulta.
    static func verificar(completion: @escaping (Estado) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { verificar(completion: completion) }
            return
        }
        completionsPendientes.append(completion)
        guard !verificando else { return }
        verificando = true

        let incluyeBeta: Bool
        switch Config.canalActualizaciones() {
        case "beta": incluyeBeta = true
        case "estable": incluyeBeta = false
        default: incluyeBeta = Version.numero.contains("-")
        }
        let lista = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!
        let estable = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        let endpoints = incluyeBeta ? [lista, estable] : [estable, lista]
        consultar(endpoints, indice: 0, incluyeBeta: incluyeBeta) { estado in
            DispatchQueue.main.async { finalizarVerificacion(estado) }
        }
    }

    private static func consultar(_ endpoints: [URL], indice: Int, incluyeBeta: Bool,
                                  completion: @escaping (Estado) -> Void) {
        guard indice < endpoints.count else {
            completion(.error("no pude consultar GitHub")); return
        }
        let endpoint = endpoints[indice]
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("BtoDicta/\(Version.numero)", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // (sin `Connection: close`: ver nota abajo)
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, status == 200, let data else {
                Log.log(.sistema, "actualización: endpoint \(endpoint.lastPathComponent) falló HTTP \(status) \(error?.localizedDescription ?? "") — failover")
                consultar(endpoints, indice: indice + 1, incluyeBeta: incluyeBeta, completion: completion)
                return
            }
            let decoder = JSONDecoder()
            let releases: [Release]
            if let lista = try? decoder.decode([Release].self, from: data) {
                releases = lista
            } else if let uno = try? decoder.decode(Release.self, from: data) {
                releases = [uno]
            } else {
                Log.log(.sistema, "actualización: respuesta inválida — failover")
                consultar(endpoints, indice: indice + 1, incluyeBeta: incluyeBeta, completion: completion)
                return
            }

            guard let release = seleccionar(releases, incluyeBeta: incluyeBeta) else {
                // Un latest válido sin candidato puede ocurrir por metadatos
                // incoherentes; prueba la lista antes de concluir.
                if indice + 1 < endpoints.count {
                    consultar(endpoints, indice: indice + 1, incluyeBeta: incluyeBeta, completion: completion)
                } else {
                    completion(.alDia)
                }
                return
            }
            let remota = normalizar(release.tagName)
            guard esMasNueva(remota, que: Version.numero) else {
                Log.log(.sistema, "actualización: al día v\(Version.numero), canal \(incluyeBeta ? "beta" : "estable")")
                completion(.alDia); return
            }
            let asset = release.assets.first(where: { $0.name == "BtoDicta.dmg" })
                ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
            guard let asset, let url = URL(string: asset.browserDownloadURL), url.scheme == "https" else {
                completion(.error("el release v\(remota) no trae DMG")); return
            }
            Log.log(.sistema, "actualización disponible: v\(remota) [\(release.prerelease ? "beta" : "estable")]")
            completion(.disponible(version: remota, dmg: url, notas: release.body ?? ""))
        }.resume()
    }

    /// Una sola regla compartida por red y QA: estable excluye cualquier
    /// prerelease (por metadata O sufijo); beta ve ambos y elige por SemVer.
    private static func seleccionar(_ releases: [Release], incluyeBeta: Bool) -> Release? {
        releases.filter { r in
            guard !r.draft else { return false }
            if incluyeBeta { return true }
            return !r.prerelease && !normalizar(r.tagName).contains("-")
        }.max(by: { compararVersiones($0.tagName, $1.tagName) < 0 })
    }

    /// Fixture local del selector multicanal. Prueba la MISMA función usada con
    /// GitHub, sin tocar la preferencia del usuario ni depender del release vigente.
    static func probarCanalesQA() -> (ok: Bool, detalle: String) {
        let fixture = [
            Release(tagName: "v0.44.0", prerelease: false, draft: false, body: nil, assets: []),
            Release(tagName: "v0.45.0-beta", prerelease: true, draft: false, body: nil, assets: []),
            Release(tagName: "v0.45.0", prerelease: false, draft: true, body: nil, assets: []),
            // Metadata incoherente: estable debe rechazar también por el sufijo.
            Release(tagName: "v0.46.0-rc1", prerelease: false, draft: false, body: nil, assets: []),
        ]
        let estable = seleccionar(fixture, incluyeBeta: false).map { normalizar($0.tagName) }
        let beta = seleccionar(fixture, incluyeBeta: true).map { normalizar($0.tagName) }
        let mismaBase = seleccionar([
            Release(tagName: "v1.0.0-beta", prerelease: true, draft: false, body: nil, assets: []),
            Release(tagName: "v1.0.0", prerelease: false, draft: false, body: nil, assets: []),
        ], incluyeBeta: true).map { normalizar($0.tagName) }
        let ok = estable == "0.44.0" && beta == "0.46.0-rc1" && mismaBase == "1.0.0"
        return (ok, "estable=\(estable ?? "nil") beta=\(beta ?? "nil") mismaBase=\(mismaBase ?? "nil")")
    }

    private static func finalizarVerificacion(_ estado: Estado) {
        verificando = false
        ultimaRevision = Date()
        ultimoEstado = estado
        if case .disponible = estado { disponibleAlArrancar = estado }
        if case .alDia = estado { disponibleAlArrancar = nil }
        let callbacks = completionsPendientes
        completionsPendientes.removeAll()
        callbacks.forEach { $0(estado) }
        NotificationCenter.default.post(name: notificacion, object: nil)
        if reverificarPorCambioDeCanal {
            reverificarPorCambioDeCanal = false
            verificar { _ in }
        }
    }

    /// Descarga el DMG y se auto-reemplaza: monta, copia a /Applications,
    /// desmonta y relanza. El último paso lo hace un script externo que
    /// sobrevive al cierre de la app.
    private static var obsDescarga: NSKeyValueObservation?
    /// Candado de reentrancia: si ya hay una descarga/instalación en curso,
    /// una segunda llamada (p.ej. clic manual mientras autoactualizar baja) no
    /// arranca otra (evita dos scripts y sobrescribir obsDescarga).
    private static var instalando = false
    static func actualizar(dmg: URL, completion: @escaping (Estado) -> Void) {
        guard !instalando else { return }
        instalando = true
        let task = URLSession.shared.downloadTask(with: dmg) { tmp, _, err in
            DispatchQueue.main.async {
                guard let tmp, err == nil else {
                    instalando = false
                    completion(.error("descarga falló: \(err?.localizedDescription ?? "")")); return
                }
                let dmgLocal = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BtoDicta-update.dmg")
                try? FileManager.default.removeItem(at: dmgLocal)
                do { try FileManager.default.moveItem(at: tmp, to: dmgLocal) } catch {
                    instalando = false
                    completion(.error("no pude guardar el DMG")); return
                }

                // El certificado propio conserva la identidad/TCC, pero al ser
                // autofirmado no es una raíz pública confiable en otros Macs.
                // La integridad distribuible se ancla con una firma Ed25519
                // separada del DMG. La clave pública viaja dentro de BtoDicta;
                // la privada de releases nunca está en GitHub ni en la app.
                descargarFirmaYContinuar(dmgRemoto: dmg, dmgLocal: dmgLocal,
                                          completion: completion)
            }
        }
        // Progreso de descarga → % en la UI ("Descargando 42%").
        obsDescarga = task.progress.observe(\.fractionCompleted) { prog, _ in
            DispatchQueue.main.async { completion(.descargando(prog.fractionCompleted)) }
        }
        task.resume()
    }

    private static func descargarFirmaYContinuar(dmgRemoto: URL, dmgLocal: URL,
                                                   completion: @escaping (Estado) -> Void) {
        guard dmgRemoto.scheme?.lowercased() == "https" else {
            instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
            completion(.error("la firma del release no usa HTTPS")); return
        }
        let firmaURL = dmgRemoto.appendingPathExtension("sig")
        var req = URLRequest(url: firmaURL)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("BtoDicta/\(Version.numero)", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // (sin `Connection: close`: ver nota abajo)
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let data, data.count == 64 else {
                    instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
                    Log.log(.sistema, "actualización RECHAZADA: falta la firma Ed25519 del DMG")
                    completion(.error("firma del release no disponible — actualización cancelada")); return
                }
                guard firmaDMGValida(dmgLocal, firma: data) else {
                    instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
                    Log.log(.sistema, "actualización RECHAZADA: la firma Ed25519 del DMG no es válida")
                    completion(.error("firma del release no válida — actualización cancelada")); return
                }
                instalarDMGVerificado(dmgLocal, completion: completion)
            }
        }.resume()
    }

    private static func instalarDMGVerificado(_ dmgLocal: URL,
                                               completion: @escaping (Estado) -> Void) {
        guard let vol = montarDMG(dmgLocal) else {
            instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
            completion(.error("no pude montar el DMG")); return
        }
        let appNueva = URL(fileURLWithPath: vol).appendingPathComponent("BtoDicta.app")
        // El DMG completo ya pasó Ed25519 y está montado solo lectura. Esa es
        // la autenticidad distribuible; el certificado autofirmado fija además
        // la identidad del bundle sin exigir instalarlo como raíz de confianza.
        guard firmaConfiable(appNueva, contenidoAutenticado: true) else {
            desmontarDMG(vol)
            instalando = false; try? FileManager.default.removeItem(at: dmgLocal)
            Log.log(.sistema, "actualización RECHAZADA: el bundle no conserva la identidad de BtoDicta")
            completion(.error("identidad de la app no válida — actualización cancelada")); return
        }

        // DMG e identidad OK: copia desde el volumen YA montado y verificado
        // (sin re-montar y sin quitar quarantine). Rutas por argv, no interpoladas.
        let script = """
        sleep 1.5
        rm -rf /Applications/BtoDicta.app
        ditto "$1/BtoDicta.app" /Applications/BtoDicta.app
        hdiutil detach "$1" >/dev/null 2>&1
        rm -f "$2"
        open /Applications/BtoDicta.app
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", script, "btodicta-update", vol, dmgLocal.path]
        do {
            try p.run()
            Log.log(.sistema, "actualización: DMG firmado e identidad verificadas ✓ — instalando y reiniciando…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        } catch {
            desmontarDMG(vol)
            instalando = false
            completion(.error("no pude lanzar el instalador"))
        }
    }

    /// SemVer suficiente para estable/beta: 0.39.0 es posterior a
    /// 0.39.0-beta; 0.40.0-beta es posterior a cualquier 0.39.x.
    static func esMasNueva(_ a: String, que b: String) -> Bool {
        compararVersiones(a, b) > 0
    }

    private static func normalizar(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        return s
    }

    private static func compararVersiones(_ a: String, _ b: String) -> Int {
        func partes(_ raw: String) -> ([Int], String?) {
            let sinBuild = normalizar(raw).split(separator: "+", maxSplits: 1).first.map(String.init) ?? "0"
            let p = sinBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let numeros = p[0].split(separator: ".").map { comp -> Int in
                Int(comp.prefix { $0.isNumber }) ?? 0
            }
            return (numeros, p.count > 1 && !p[1].isEmpty ? String(p[1]) : nil)
        }
        let (na, prea) = partes(a), (nb, preb) = partes(b)
        for i in 0..<max(na.count, nb.count) {
            let x = i < na.count ? na[i] : 0
            let y = i < nb.count ? nb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        if prea == nil, preb != nil { return 1 }
        if prea != nil, preb == nil { return -1 }
        guard let prea, let preb else { return 0 }
        let ia = prea.split(separator: ".").map(String.init)
        let ib = preb.split(separator: ".").map(String.init)
        for i in 0..<max(ia.count, ib.count) {
            if i >= ia.count { return -1 }
            if i >= ib.count { return 1 }
            if ia[i] == ib[i] { continue }
            if let x = Int(ia[i]), let y = Int(ib[i]) { return x < y ? -1 : 1 }
            if Int(ia[i]) != nil { return -1 } // identificador numérico precede al textual
            if Int(ib[i]) != nil { return 1 }
            return ia[i] < ib[i] ? -1 : 1
        }
        return 0
    }

    // MARK: - Verificación de firma e integridad del DMG

    /// Firma Ed25519 sobre SHA-256(DMG). El recurso es una SubjectPublicKeyInfo
    /// DER de 44 bytes; los últimos 32 son la representación cruda de Ed25519.
    private static func clavePublicaActualizacion() -> Curve25519.Signing.PublicKey? {
        guard let url = Bundle.main.url(forResource: "update-public-key", withExtension: "der"),
              let der = try? Data(contentsOf: url), der.count >= 32 else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: Data(der.suffix(32)))
    }

    private static func sha256Archivo(_ url: URL) -> Data? {
        guard let input = InputStream(url: url) else { return nil }
        input.open(); defer { input.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let n = input.read(&buffer, maxLength: buffer.count)
            if n < 0 { return nil }
            if n == 0 { break }
            hasher.update(data: Data(buffer[0..<n]))
        }
        return Data(hasher.finalize())
    }

    /// Visible para el hook QA del pipeline. No acepta firma ausente, truncada
    /// ni una clave pública sustituida por configuración del usuario.
    static func firmaDMGValida(_ dmg: URL, firma: Data) -> Bool {
        guard firma.count == 64, let clave = clavePublicaActualizacion(),
              let digest = sha256Archivo(dmg) else { return false }
        return clave.isValidSignature(firma, for: digest)
    }

    /// Monta un DMG de solo lectura y devuelve su punto de montaje (o nil).
    private static func montarDMG(_ dmg: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-nobrowse", "-readonly", "-plist", dmg.path]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let ents = plist["system-entities"] as? [[String: Any]] else { return nil }
        return ents.compactMap { $0["mount-point"] as? String }.first
    }

    private static func desmontarDMG(_ vol: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", vol]
        try? p.run(); p.waitUntilExit()
    }

    /// SHA-256 del certificado LÍDER (hoja) que firma un bundle. Anclar por el
    /// SHA del cert (no por su Common Name, que es falsificable) es lo que da
    /// la garantía: solo quien tiene la clave privada puede producir una firma
    /// válida contra ese certificado.
    private static func certLiderSHA(_ code: SecStaticCode) -> Data? {
        var infoCF: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else { return nil }
        var leaf = (info[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first
        // Un leaf autofirmado no confiado puede omitirse de `certificates`, pero
        // Security sí lo conserva dentro de su SecTrust. Extraerlo no lo declara
        // confiable: solo permite comparar su huella pública fijada.
        if leaf == nil, let raw = info[kSecCodeInfoTrust as String] {
            let cf = raw as CFTypeRef
            if CFGetTypeID(cf) == SecTrustGetTypeID() {
                let trust = unsafeBitCast(cf, to: SecTrust.self)
                leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
            }
        }
        guard let leaf else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return Data(SHA256.hash(data: der))
    }

    private static func certReleaseSHA() -> Data? {
        guard let url = Bundle.main.url(forResource: "code-signing-cert", withExtension: "der"),
              let der = try? Data(contentsOf: url), !der.isEmpty else { return nil }
        return Data(SHA256.hash(data: der))
    }

    /// Segunda barrera DESPUÉS de verificar criptográficamente el DMG completo:
    /// exige bundle id, firma interna íntegra y el leaf público fijado dentro
    /// de BtoDicta.
    /// No usa la confianza pública del certificado autofirmado (no existe en una
    /// instalación normal); la autenticidad fuerte ya la da Ed25519 sobre el DMG.
    static func firmaConfiable(_ app: URL, contenidoAutenticado: Bool = false) -> Bool {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "ec.bto.btodicta",
              let ejecutable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: ejecutable.path) else { return false }
        var nuevoCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &nuevoCode) == errSecSuccess,
              let nuevo = nuevoCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard let esperado = certReleaseSHA(), let shaNuevo = certLiderSHA(nuevo) else { return false }
        guard esperado == shaNuevo else { return false }

        let estado = SecStaticCodeCheckValidity(nuevo, flags, nil)
        if estado == errSecSuccess { return true }

        // Un certificado autofirmado NO es una raíz pública y, correctamente,
        // macOS devuelve CSSMERR_TP_NOT_TRUSTED (-2147409622) aunque la firma y
        // su leaf sean los esperados. Solo aceptamos ese caso cuando el llamador
        // ya autenticó TODO el DMG con Ed25519 y lo montó read-only. No se usa
        // como bypass general para una app descargada o modificable.
        let autofirmadoNoConfiado: OSStatus = -2147409622
        return contenidoAutenticado && estado == autofirmadoNoConfiado
    }
}
