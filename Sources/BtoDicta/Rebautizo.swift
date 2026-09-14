import Foundation
import SQLite3

// MARK: - Cambio de nombre: BetoDicta → BtoDicta
//
// La aplicación se rebautizó, y con ella su identificador y sus carpetas. Nada
// de lo que el usuario tiene guardado puede perderse por eso: ni los modelos
// (decenas de gigas), ni las voces, ni el historial, ni la bitácora, ni una
// sola credencial.
//
// Las carpetas se MUEVEN, no se copian: están en el mismo volumen, así que el
// cambio es instantáneo aunque pesen 50 GB. Si algo no se puede mover, se deja
// como está y se registra: nunca se borra nada.
//
// Esto corre una sola vez, antes de que nadie lea configuración.
enum Rebautizo {

    private static let mudanzas: [(String, String)] = [
        (".betodicta", ".btodicta"),
        ("BetoDicta Bitácora", "BtoDicta Bitácora"),
    ]

    /// El índice de la bitácora guarda rutas ABSOLUTAS. Si la carpeta cambia de
    /// nombre y el índice no se entera, cada archivo pasa a estar «perdido» y el
    /// rescate lo da de alta otra vez como pendiente: el resultado es un índice
    /// con todo por duplicado y una tanda que vuelve a transcribir meses de
    /// audio ya transcrito. Medido en una instalación real: 63 567 elementos
    /// dados por pendientes cuando ya estaban hechos. Se corrige aquí, en el
    /// mismo momento de la mudanza y antes de que nadie abra el índice.
    private static func corregirRutasDelIndice(en carpeta: URL, de viejo: String, a nuevo: String) {
        let base = carpeta.appendingPathComponent("bitacora.sqlite")
        guard FileManager.default.fileExists(atPath: base.path) else { return }
        var db: OpaquePointer?
        guard sqlite3_open_v2(base.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close_v2(db) }
        sqlite3_exec(db, "PRAGMA busy_timeout=15000;", nil, nil, nil)
        var cambiadas: Int32 = 0
        for tabla in ["audio", "pantalla"] {
            let sql = "UPDATE \(tabla) SET ruta = ? || substr(ruta, ?) WHERE ruta LIKE ? || '%';"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(st) }
            let transitorio = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(st, 1, nuevo, -1, transitorio)
            sqlite3_bind_int(st, 2, Int32(viejo.utf8.count + 1))
            sqlite3_bind_text(st, 3, viejo, -1, transitorio)
            if sqlite3_step(st) == SQLITE_DONE { cambiadas += sqlite3_changes(db) }
        }
        if cambiadas > 0 {
            NSLog("BtoDicta: %d entradas del índice apuntan ya a la carpeta nueva", cambiadas)
        }
    }

    /// El archivo de registro VIVO también llevaba el nombre anterior, y vive
    /// DENTRO de la carpeta que se acaba de mover, así que la mudanza de
    /// carpetas no lo toca. Si se queda atrás, la semana en curso queda partida
    /// en dos: la rotación semanal solo archiva el nombre nuevo, de modo que la
    /// mitad vieja no se archiva jamás y desaparece de todo diagnóstico.
    /// Medido en una instalación real: 1,5 MB de registro (una semana entera)
    /// invisibles desde el momento del cambio de nombre.
    static func mudarRegistro(en carpeta: URL) {
        let fm = FileManager.default
        let viejo = carpeta.appendingPathComponent("betodicta.log")
        let nuevo = carpeta.appendingPathComponent("btodicta.log")
        let apartado = carpeta.appendingPathComponent("betodicta.log.original")
        guard fm.fileExists(atPath: viejo.path) else { return }
        // Si ya se unió una vez, no se vuelve a unir: duplicaría la historia.
        guard !fm.fileExists(atPath: apartado.path) else { return }
        if !fm.fileExists(atPath: nuevo.path) {
            try? fm.moveItem(at: viejo, to: nuevo)
            NSLog("BtoDicta: el registro de la semana conserva su historia")
            return
        }
        // Existen los dos: lo anterior va DELANTE (es lo más antiguo) y el
        // original se conserva aparte. Aquí no se borra nada nunca. Es seguro
        // reescribir: el registro se abre y se cierra en cada línea, y esto
        // corre antes de que se escriba la primera.
        guard let antes = try? Data(contentsOf: viejo),
              let ahora = try? Data(contentsOf: nuevo) else { return }
        var junto = antes
        junto.append(ahora)
        // Atómica: sin ella, un corte a media escritura dejaría el registro
        // truncado y ya no habría de dónde recuperarlo.
        guard (try? junto.write(to: nuevo, options: .atomic)) != nil else { return }
        try? fm.moveItem(at: viejo, to: apartado)
        NSLog("BtoDicta: el registro anterior (%d bytes) se unió al de la semana en curso",
              antes.count)
    }

    static func aplicar() {
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default
        for (viejo, nuevo) in mudanzas {
            let origen = casa.appendingPathComponent(viejo)
            let destino = casa.appendingPathComponent(nuevo)
            guard fm.fileExists(atPath: origen.path) else { continue }
            if fm.fileExists(atPath: destino.path) {
                // Ya existe la carpeta nueva: no se toca ninguna de las dos.
                // Mezclarlas a ciegas podría pisar datos buenos.
                NSLog("BtoDicta: %@ y %@ existen las dos — dejo ambas intactas", viejo, nuevo)
                continue
            }
            do {
                try fm.moveItem(at: origen, to: destino)
                NSLog("BtoDicta: %@ pasó a llamarse %@", viejo, nuevo)
                corregirRutasDelIndice(en: destino, de: origen.path, a: destino.path)
            } catch {
                NSLog("BtoDicta: no pude renombrar %@ (%@) — sigo usando la carpeta anterior",
                      viejo, error.localizedDescription)
                // Sin carpeta nueva la app arrancaría vacía: se enlaza la vieja
                // para que todo siga en su sitio hasta poder mover de verdad.
                try? fm.createSymbolicLink(at: destino, withDestinationURL: origen)
            }
        }
        // Siempre, aunque la carpeta ya estuviera movida de una versión
        // anterior: el archivo de registro se quedó dentro con el nombre viejo.
        mudarRegistro(en: casa.appendingPathComponent(".btodicta"))
    }
}
