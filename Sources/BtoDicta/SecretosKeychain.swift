import Foundation
import Security

// MARK: - Secretos de conexiones API: Keychain primero, archivo como respaldo VISIBLE
//
// El secreto (API key / clave) de cada conexión vive en el Llavero de macOS
// (service fijo, account = id del modo), accesible solo con la sesión
// desbloqueada y solo en este equipo. Si el Llavero falla (firma ad-hoc en
// builds locales puede provocarlo), NO hay degradación silenciosa: se usa un
// archivo 0600 y la función lo DICE, para que la UI se lo muestre al usuario.

enum SecretosKeychain {
    static let servicio = "BtoDicta-Conexion"
    /// Servicio con el que se guardaron las claves antes del cambio de nombre.
    /// Se lee como respaldo y lo leído se reescribe con el nombre nuevo, así
    /// nadie tiene que volver a teclear una sola credencial.
    static let servicioAnterior = "BetoDicta-Conexion"

    enum Almacen: String { case keychain = "Llavero de macOS", archivo = "archivo local (~/.btodicta)" }

    private static var urlRespaldo: URL {
        Config.dir.appendingPathComponent("conexiones_secretos.json")
    }

    private static func consulta(_ cuenta: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: servicio,
         kSecAttrAccount as String: cuenta]
    }

    /// Guarda (o reemplaza) el secreto. Devuelve DÓNDE quedó, para que la UI
    /// nunca oculte que se cayó al archivo.
    @discardableResult
    static func guardar(_ secreto: String, cuenta: String) -> (ok: Bool, donde: Almacen) {
        let s = secreto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { borrar(cuenta: cuenta); return (true, .keychain) }
        SecItemDelete(consulta(cuenta) as CFDictionary)
        lockCache.lock(); cache[cuenta] = s; lockCache.unlock()
        var attrs = consulta(cuenta)
        attrs[kSecValueData as String] = Data(s.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecSuccess {
            borrarDeArchivo(cuenta)   // no dejar una copia vieja en el respaldo
            return (true, .keychain)
        }
        Log.write("secretos: Keychain devolvió \(status) — respaldo en archivo 0600")
        return (guardarEnArchivo(s, cuenta: cuenta), .archivo)
    }

    /// Lo ya leído en esta ejecución: macOS pide la clave del Mac en cada lectura
    /// del Llavero de una app sin Team ID recién compilada; así pide una sola vez.
    private static var cache: [String: String] = [:]
    private static let lockCache = NSLock()

    /// ¿Hay secreto? Solo mira los atributos, sin abrir el valor: no pide la clave del Mac.
    static func existe(cuenta: String) -> Bool {
        lockCache.lock(); let enCache = cache[cuenta] != nil; lockCache.unlock()
        if enCache { return true }
        var q = consulta(cuenta)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess { return true }
        var viejo = q
        viejo[kSecAttrService as String] = servicioAnterior
        if SecItemCopyMatching(viejo as CFDictionary, &out) == errSecSuccess { return true }
        return leerDeArchivo(cuenta) != nil
    }

    /// Lee el secreto (Keychain primero, luego el respaldo). nil si no hay.
    static func leer(cuenta: String) -> String? {
        lockCache.lock(); let enCache = cache[cuenta]; lockCache.unlock()
        if let enCache { return enCache }
        let s = leerSinCache(cuenta)
        if let s { lockCache.lock(); cache[cuenta] = s; lockCache.unlock() }
        return s
    }

    private static func leerSinCache(_ cuenta: String) -> String? {
        var q = consulta(cuenta)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let d = out as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty {
            return s
        }
        // Guardado con el nombre anterior de la app: se lee y se reescribe con
        // el nuevo. Migración transparente: ninguna credencial hay que teclearla
        // otra vez por un cambio de nombre.
        var viejo: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: servicioAnterior,
                                    kSecAttrAccount as String: cuenta,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var salidaVieja: CFTypeRef?
        if SecItemCopyMatching(viejo as CFDictionary, &salidaVieja) == errSecSuccess,
           let d = salidaVieja as? Data, let s = String(data: d, encoding: .utf8), !s.isEmpty {
            viejo.removeValue(forKey: kSecReturnData as String)
            viejo.removeValue(forKey: kSecMatchLimit as String)
            guardar(s, cuenta: cuenta)
            SecItemDelete(viejo as CFDictionary)
            Log.write("secretos: credencial migrada al nombre nuevo (\(cuenta))")
            return s
        }
        return leerDeArchivo(cuenta)
    }

    /// ¿Dónde está guardado hoy? nil = no hay secreto. Para el letrero de la UI.
    static func donde(cuenta: String) -> Almacen? {
        var q = consulta(cuenta)
        q[kSecReturnAttributes as String] = true   // sin abrir el valor: no pide la clave del Mac
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess { return .keychain }
        return leerDeArchivo(cuenta) != nil ? .archivo : nil
    }

    /// Purga total (se llama también al borrar el modo dueño de la conexión).
    static func borrar(cuenta: String) {
        lockCache.lock(); cache[cuenta] = nil; lockCache.unlock()
        SecItemDelete(consulta(cuenta) as CFDictionary)
        borrarDeArchivo(cuenta)
    }

    // MARK: respaldo en archivo (0600, JSON {cuenta: secreto})

    private static func mapaArchivo() -> [String: String] {
        (try? Data(contentsOf: urlRespaldo))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    private static func guardarEnArchivo(_ secreto: String, cuenta: String) -> Bool {
        var m = mapaArchivo(); m[cuenta] = secreto
        guard let d = try? JSONEncoder().encode(m) else { return false }
        Config.asegurarDirSeguro()
        do { try d.write(to: urlRespaldo, options: .atomic) } catch { return false }
        Config.protegerSecreto(urlRespaldo)
        return true
    }

    private static func leerDeArchivo(_ cuenta: String) -> String? {
        let s = mapaArchivo()[cuenta]
        return (s?.isEmpty == false) ? s : nil
    }

    private static func borrarDeArchivo(_ cuenta: String) {
        var m = mapaArchivo()
        guard m.removeValue(forKey: cuenta) != nil else { return }
        if m.isEmpty { try? FileManager.default.removeItem(at: urlRespaldo); return }
        if let d = try? JSONEncoder().encode(m) {
            try? d.write(to: urlRespaldo, options: .atomic)
            Config.protegerSecreto(urlRespaldo)
        }
    }
}
