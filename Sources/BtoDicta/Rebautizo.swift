import Foundation

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
            } catch {
                NSLog("BtoDicta: no pude renombrar %@ (%@) — sigo usando la carpeta anterior",
                      viejo, error.localizedDescription)
                // Sin carpeta nueva la app arrancaría vacía: se enlaza la vieja
                // para que todo siga en su sitio hasta poder mover de verdad.
                try? fm.createSymbolicLink(at: destino, withDestinationURL: origen)
            }
        }
    }
}
