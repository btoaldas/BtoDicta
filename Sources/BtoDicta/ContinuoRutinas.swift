import Foundation

// MARK: - Bitácora continua: rutinas de documentos
//
// Cada rutina es una orden permanente: «a las 23:00, el resumen del día
// entero» o «cada 3 horas, las ideas principales de las últimas 3». Pueden
// convivir varias a la vez —mediodía y noche, por ejemplo— porque cada una
// tiene su propio horario, su propio prompt y su propio rango de material.
//
// Nada se pisa: cada documento sale con la hora en el nombre si ya existe uno
// del mismo prompt ese día. Y la ejecución manual de la pestaña sigue aparte.
//
// Se guardan en `~/.btodicta/continuo-rutinas.json`, siguiendo el precedente
// de la biblioteca de prompts.

struct RutinaResumen: Identifiable, Codable, Equatable {
    var id: String
    var activa: Bool
    /// Prompt de la biblioteca que ejecuta.
    var promptId: String
    /// `hora` = a una hora fija del día; `intervalo` = cada N minutos.
    var cuando: String
    /// Con `hora`: minutos desde medianoche (1380 = 23:00).
    var minutoDelDia: Int
    /// Con `intervalo`: cada cuántos minutos.
    var cadaMinutos: Int
    /// `dia` = todo el día hasta ahora; `horas` = solo las últimas N.
    var rango: String
    var rangoHoras: Int

    static func nueva() -> RutinaResumen {
        RutinaResumen(id: UUID().uuidString, activa: true,
                      promptId: "resumen_diario",
                      cuando: "hora", minutoDelDia: 23 * 60, cadaMinutos: 180,
                      rango: "dia", rangoHoras: 3)
    }

    /// Texto corto para la lista: «23:00 · Resumen del día · todo el día».
    var descripcion: String {
        let momento = cuando == "hora"
            ? String(format: "%02d:%02d", minutoDelDia / 60, minutoDelDia % 60)
            : (cadaMinutos % 60 == 0 ? "cada \(cadaMinutos / 60) h" : "cada \(cadaMinutos) min")
        let nombre = ContinuoPrompts.porId(promptId)?.nombre ?? promptId
        let material = rango == "dia" ? "todo el día" : "últimas \(rangoHoras) h"
        return "\(momento) · \(nombre) · \(material)"
    }
}

enum ContinuoRutinas {

    private static var archivo: URL {
        Config.dir.appendingPathComponent("continuo-rutinas.json")
    }

    static func todas() -> [RutinaResumen] {
        guard let data = try? Data(contentsOf: archivo),
              let lista = try? JSONDecoder().decode([RutinaResumen].self, from: data) else { return [] }
        return lista
    }

    static func activas() -> [RutinaResumen] {
        todas().filter(\.activa)
    }

    static func guardar(_ lista: [RutinaResumen]) {
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? cod.encode(lista) else { return }
        try? data.write(to: archivo, options: .atomic)
        Log.log(.config, "bitácora: \(lista.count) rutinas guardadas (\(lista.filter(\.activa).count) activas)")
    }

    // MARK: Disparo

    /// Marcas de último disparo, por rutina, en memoria. Con `hora` la marca es
    /// el día (una vez por día); con `intervalo`, el instante. La semántica al
    /// despertar es la misma que la tanda: si el equipo dormía a la hora
    /// fijada, se dispara una vez al volver — tarde es mejor que nunca.
    private static var ultimoDia: [String: String] = [:]
    private static var ultimoInstante: [String: Date] = [:]
    private static let candado = NSLock()

    /// Llamado por el planificador una vez por minuto. Devuelve las rutinas que
    /// tocan AHORA (y deja registrada la marca para no repetirlas).
    static func vencidas(ahora: Date = Date()) -> [RutinaResumen] {
        let cal = Calendar.current
        let minutoActual = cal.component(.hour, from: ahora) * 60 + cal.component(.minute, from: ahora)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let hoy = f.string(from: ahora)

        candado.lock(); defer { candado.unlock() }
        var listas: [RutinaResumen] = []
        for r in activas() {
            switch r.cuando {
            case "hora":
                // La nota de «ya se disparó hoy» va a DISCO: en memoria se
                // perdía al cerrar la aplicación, y al reabrirla después de la
                // hora la rutina volvía a dispararse. Se vieron tres resúmenes
                // del mismo día, cada uno con su llamada a la IA.
                if minutoActual >= r.minutoDelDia,
                   !MemoriaPersistente.yaHechoHoy(tema: "rutinas-hora", clave: r.id, ahora: ahora) {
                    listas.append(r)
                }
            case "intervalo":
                // Aquí el fallo era el contrario: al arrancar se contaba desde
                // cero, así que una rutina «cada 3 h» no se disparaba nunca si la
                // aplicación se reiniciaba antes. Ahora la cuenta sigue donde
                // estaba, aunque se haya cerrado por medio.
                guard let ultimo = MemoriaPersistente.ultimaVez(tema: "rutinas-intervalo", clave: r.id) else {
                    MemoriaPersistente.anotarAhora(tema: "rutinas-intervalo", clave: r.id, ahora: ahora)
                    continue
                }
                if ahora.timeIntervalSince(ultimo) >= Double(r.cadaMinutos) * 60 {
                    MemoriaPersistente.anotarAhora(tema: "rutinas-intervalo", clave: r.id, ahora: ahora)
                    listas.append(r)
                }
            default:
                continue
            }
        }
        return listas
    }

    /// Ejecuta una rutina: primero la tanda (para que el material esté
    /// transcrito y leído al minuto) y después el documento con su prompt y su
    /// rango. En seco (variable de entorno) se detiene justo antes de llamar a
    /// la IA: deja la mecánica verificable sin enviar nada a nadie.
    static func ejecutar(_ r: RutinaResumen) {
        // El interruptor maestro del resumen con IA manda sobre las rutinas:
        // es el consentimiento de que el material pueda salir hacia un modelo.
        // Con él apagado, ninguna rutina envía nada.
        guard Config.continuoResumenActivo() else {
            Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» omitida — el resumen con IA está desactivado")
            return
        }
        Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» disparada")
        ContinuoLote.ejecutar(alTerminar: { _ in }, huboTanda: { corrio in
            guard corrio else {
                // Otra tanda está transcribiendo justo ahora. Generar el
                // documento con lo que hay sería resumir un día a medio
                // transcribir: se reintenta en unos minutos, cuando el material
                // esté completo.
                Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» aplazada 5 min — hay una tanda transcribiendo")
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) { ejecutar(r) }
                return
            }
            let desde: Date? = r.rango == "horas"
                ? Date().addingTimeInterval(-Double(r.rangoHoras) * 3600)
                : nil
            if ProcessInfo.processInfo.environment["BTODICTA_RUTINA_SECO"] == "1" {
                Log.log(.sistema, "bitácora: rutina en seco — habría generado «\(r.promptId)» (rango \(r.rango)) sin enviar nada")
                return
            }
            ContinuoResumen.generar(promptId: r.promptId, desde: desde) { resultado in
                switch resultado {
                case .success(let url):
                    Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» → \(url.lastPathComponent)")
                case .failure(let e):
                    // Sin material en el rango (la rutina de madrugada, un día
                    // sin usar el equipo) no es un fallo: se omite y punto.
                    // Registrarlo como «falló» hacía ruido y escondía los reales.
                    if let er = e as? ContinuoResumen.ErrorResumen, er == .sinMaterial {
                        Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» omitida — sin material en el rango")
                    } else {
                        Log.log(.sistema, "bitácora: rutina «\(r.descripcion)» falló — \(e.localizedDescription)")
                    }
                }
            }
        })
    }
}
