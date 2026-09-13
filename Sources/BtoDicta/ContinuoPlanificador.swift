import AppKit

// MARK: - Bitácora continua: planificador
//
// Decide CUÁNDO corre la tanda diferida. Cinco disparadores, combinables:
//
//   intervalo  cada N minutos
//   hora       a una hora fija del día
//   arranque   al abrir la app
//   apagado    al cerrar sesión o apagar el equipo
//   manual     el botón de la pestaña, siempre disponible
//
// El reloj vive DENTRO del proceso, no en launchd. Motivo práctico: cambiar la
// hora desde los ajustes se aplica al instante, sin reescribir un plist ni
// recargar nada. Es el mismo enfoque que ya usa el actualizador de la app.
//
// Contrapartida honesta: con la app cerrada no corre nada. Para el caso de uso
// —la bitácora solo graba mientras la app está abierta— eso no quita cobertura.

enum ContinuoPlanificador {

    private static var reloj: Timer?
    private static var ultimaHoraDisparada: String?
    private static var observadorApagado: NSObjectProtocol?

    // MARK: Arranque

    static func arrancar() {
        guard Config.continuoActivo() else { return }
        let disparadores = Config.continuoLoteDisparadores()

        // Un solo reloj de un minuto atiende `intervalo` y `hora`: comprobar una
        // condición cada 60 s no cuesta nada y evita dos temporizadores que
        // haya que mantener sincronizados.
        DispatchQueue.main.async {
            reloj?.invalidate()
            let hayRutinas = !ContinuoRutinas.activas().isEmpty
            guard disparadores.contains("intervalo") || disparadores.contains("hora") || hayRutinas else { return }
            let t = Timer(timeInterval: 60, repeats: true) { _ in tic() }
            RunLoop.main.add(t, forMode: .common)
            reloj = t
        }

        if disparadores.contains("apagado") { observarApagado() }

        if disparadores.contains("arranque") {
            // Con retraso: al abrir, la app tiene cosas más urgentes que hacer
            // y el micrófono todavía se está asentando.
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
                ContinuoLote.ejecutar()
            }
        }

        Log.log(.sistema, "bitácora: planificador con [\(disparadores.joined(separator: ", "))]")
    }

    static func detener() {
        DispatchQueue.main.async {
            reloj?.invalidate()
            reloj = nil
        }
        if let o = observadorApagado {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            observadorApagado = nil
        }
    }

    static func reconfigurar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { arrancar() }
    }

    // MARK: Disparadores por tiempo

    private static func tic() {
        guard Config.continuoActivo() else { return }
        // Rutinas de documentos: independientes de la tanda global y entre sí.
        for rutina in ContinuoRutinas.vencidas() {
            ContinuoRutinas.ejecutar(rutina)
        }
        guard !ContinuoLote.ocupado else { return }
        let disparadores = Config.continuoLoteDisparadores()

        if disparadores.contains("hora") {
            let cal = Calendar.current
            let ahora = Date()
            let minutoActual = cal.component(.hour, from: ahora) * 60 + cal.component(.minute, from: ahora)
            let sello = selloDelDia(ahora)
            // La marca por día evita repetir la tanda si el minuto se comprueba
            // dos veces, y evita perderla si el equipo estaba dormido a esa hora:
            // en cuanto despierta y ya pasó la hora, se dispara una sola vez.
            if minutoActual >= Config.continuoLoteMinutoDelDia(), ultimaHoraDisparada != sello {
                ultimaHoraDisparada = sello
                ContinuoLote.ejecutar()
                return
            }
        }

        if disparadores.contains("intervalo") {
            let minutos = Config.continuoLoteIntervaloMinutos()
            let transcurridos = Int(Date().timeIntervalSince(ultimaTanda) / 60)
            if transcurridos >= minutos {
                ultimaTanda = Date()
                ContinuoLote.ejecutar()
            }
        }
    }

    private static var ultimaTanda = Date()

    private static func selloDelDia(_ f: Date) -> String {
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"
        return d.string(from: f)
    }

    // MARK: Apagado

    /// Al cerrar sesión o apagar, macOS da un margen corto. No se intenta una
    /// tanda completa: se arranca y lo que alcance quedará hecho, y lo que no,
    /// sigue pendiente para la próxima. El índice lo hace reanudable.
    private static func observarApagado() {
        guard observadorApagado == nil else { return }
        observadorApagado = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in
            Log.log(.sistema, "bitácora: el equipo se apaga, intento una tanda corta")
            ContinuoLote.ejecutar()
        }
    }

    // MARK: Texto para la interfaz

    static func descripcion() -> String {
        let d = Config.continuoLoteDisparadores()
        if d.isEmpty { return "Solo cuando lo pidas a mano." }
        var partes: [String] = []
        if d.contains("intervalo") { partes.append("cada \(Config.continuoLoteIntervaloMinutos()) min") }
        if d.contains("hora") {
            let m = Config.continuoLoteMinutoDelDia()
            partes.append(String(format: "a las %02d:%02d", m / 60, m % 60))
        }
        if d.contains("arranque") { partes.append("al abrir la app") }
        if d.contains("apagado") { partes.append("al apagar el equipo") }
        return partes.joined(separator: " · ")
    }
}
