import Foundation

// MARK: - QA del Modo Tarea multi-sección + recordatorio periódico
//
//   BTODICTA_TAREASQA=1 → pruebas PURAS (parser, ranking, horas quietas,
//   resumen por alcance). No toca ~/.btodicta/pendientes.json del usuario.

enum TareasQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_TAREASQA"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("TAREASQA \(pasa ? "OK" : "✗") \(nombre)")
        }

        // 1. Parser de comandos.
        check("crear por defecto", TareasComando.interpretar("comprar la comida") == .crear)
        check("completar por texto",
              TareasComando.interpretar("quita la tarea de comprar la comida") == .completar("comprar la comida"))
        check("completar con 'ya terminé'",
              TareasComando.interpretar("ya terminé el informe mensual") == .completar("el informe mensual"))
        check("completar con 'marca'",
              TareasComando.interpretar("marca la tarea llamar al banco") == .completar("llamar al banco"))
        check("modificar con 'a'",
              TareasComando.interpretar("cambia la tarea de comprar pan a comprar leche")
              == .modificar("comprar pan", "comprar leche"))
        check("modificar con 'por'",
              TareasComando.interpretar("modifica la tarea llamar al banco por llamar a la aseguradora")
              == .modificar("llamar al banco", "llamar a la aseguradora"))
        check("resumen hoy",
              TareasComando.interpretar("dame un resumen de las tareas de hoy") == .resumen(.hoy))
        check("resumen semana",
              TareasComando.interpretar("resumen de la semana") == .resumen(.semana))
        check("resumen pendientes",
              TareasComando.interpretar("resumen de todas las pendientes") == .resumen(.pendientes))
        check("resumen genérico → pendientes",
              TareasComando.interpretar("qué tareas tengo") == .resumen(.pendientes))
        check("modificar sin separador cae a crear",
              TareasComando.interpretar("cambia el mundo") == .crear)

        // 2. Ranking difuso (sin disco).
        func tarea(_ t: String, hecho: Bool = false) -> Pendiente {
            var p = Pendiente(tipo: "tarea", texto: t); p.hecho = hecho; return p
        }
        let lista = [tarea("comprar la comida para la semana"),
                     tarea("llamar al banco por el crédito"),
                     tarea("enviar el informe a dirección")]
        check("encuentra por palabras clave",
              NotasStore.rankearPendientes("comprar comida", pendientes: lista).tarea?.texto.contains("comida") == true)
        check("encuentra con mal-escucha leve",
              NotasStore.rankearPendientes("llamar banco", pendientes: lista).tarea?.texto.contains("banco") == true)
        check("consulta sin match no inventa",
              NotasStore.rankearPendientes("pasear al perro", pendientes: lista).tarea == nil)
        check("ignora las ya hechas",
              NotasStore.rankearPendientes("informe", pendientes: [tarea("enviar informe", hecho: true)]).tarea == nil)
        let ambig = [tarea("revisar el correo de la mañana"), tarea("revisar el correo de la tarde")]
        check("dos casi iguales = ambiguo",
              NotasStore.rankearPendientes("revisar el correo", pendientes: ambig).ambiguo == true)

        // 3. Horas quietas (ventana que cruza medianoche).
        check("2am dentro de 22:00-07:00",
              TareasRecordatorios.enHorasQuietas(minutosAhora: 120, desde: 1320, hasta: 420))
        check("15:00 fuera de 22:00-07:00",
              !TareasRecordatorios.enHorasQuietas(minutosAhora: 900, desde: 1320, hasta: 420))
        check("23:00 dentro",
              TareasRecordatorios.enHorasQuietas(minutosAhora: 1380, desde: 1320, hasta: 420))
        check("07:00 justo fuera (fin exclusivo)",
              !TareasRecordatorios.enHorasQuietas(minutosAhora: 420, desde: 1320, hasta: 420))
        check("ventana normal 13-14",
              TareasRecordatorios.enHorasQuietas(minutosAhora: 810, desde: 780, hasta: 840))

        // 4. Toca resumen periódico (intervalo).
        let ahora = Date(timeIntervalSince1970: 1_000_000)
        check("toca si pasó el intervalo",
              TareasRecordatorios.tocaResumenPeriodico(activo: true, horas: 1,
                  ultimo: ahora.timeIntervalSince1970 - 3_700, ahora: ahora))
        check("no toca si no pasó",
              !TareasRecordatorios.tocaResumenPeriodico(activo: true, horas: 1,
                  ultimo: ahora.timeIntervalSince1970 - 600, ahora: ahora))
        check("no toca si está apagado",
              !TareasRecordatorios.tocaResumenPeriodico(activo: false, horas: 1,
                  ultimo: 0, ahora: ahora))

        // 5. Resumen por alcance (solo pendientes, filtrado por fecha).
        let hoy = Date()
        let cal = Calendar.current
        func conFecha(_ t: String, _ f: Date?) -> Pendiente {
            Pendiente(tipo: "tarea", texto: t, fechaObjetivo: f)
        }
        let mezcla = [
            conFecha("tarea de hoy", cal.date(bySettingHour: 19, minute: 0, second: 0, of: hoy)),
            conFecha("tarea en 3 días", cal.date(byAdding: .day, value: 3, to: hoy)),
            conFecha("tarea en 20 días", cal.date(byAdding: .day, value: 20, to: hoy)),
            conFecha("tarea sin fecha", nil),
        ]
        let rHoy = TareasRecordatorios.resumenAlcance(.hoy, items: mezcla, ahora: hoy, incluirSinFecha: true)
        check("resumen hoy solo incluye la de hoy",
              rHoy.contains("tarea de hoy") && !rHoy.contains("20 días"))
        let rSemana = TareasRecordatorios.resumenAlcance(.semana, items: mezcla, ahora: hoy, incluirSinFecha: true)
        check("resumen semana incluye hoy y 3 días, no 20",
              rSemana.contains("tarea de hoy") && rSemana.contains("3 días") && !rSemana.contains("20 días"))
        let rPend = TareasRecordatorios.resumenAlcance(.pendientes, items: mezcla, ahora: hoy, incluirSinFecha: true)
        check("resumen pendientes incluye todas", rPend.contains("20 días") && rPend.contains("sin fecha"))
        check("resumen NO cuenta las hechas",
              TareasRecordatorios.resumenAlcance(.pendientes,
                  items: [tarea("ya hecha", hecho: true)], ahora: hoy, incluirSinFecha: true)
                  == "No tienes tareas pendientes.")

        print(fallos == 0 ? "TAREASQA TODO OK" : "TAREASQA ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 3)
    }
}
