import Foundation

// MARK: - Modo AHORRO global (filosofía: si no lo usas, ¿para qué gasta recursos?)
//
// Un solo reloj de inactividad. Si BtoDicta no se usa en N minutos, DUERME lo pesado:
//   • el clon local (mata el server → libera ~2 GB de RAM),
//   • el latido de red (deja de pinguear cada 15s).
// Al grabar (fn) se DESPIERTA todo. La tecla es el latido que revive el sistema.
//
// Umbral = ttsXttsDormirMin (los "minutos de inactividad", parametrizables). Cada pieza
// respeta su propio toggle (ttsXttsDormir para el clon), pero el master es ahorroGlobal.
// Extensible: aquí se agregan más subsistemas que consuman recursos.

enum Ahorro {
    private static var ultimaActividad = Date()
    private static var protegidoHasta = Date.distantPast
    private static var dormido = false
    private static var reloj: Timer?

    static func iniciar() {
        reloj?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { _ in revisar() }
        RunLoop.main.add(t, forMode: .common); reloj = t
    }

    /// Se llama al usar BtoDicta (grabar/fn): resetea el reloj y DESPIERTA si dormía.
    static func marcarActividad() {
        ultimaActividad = Date()
        protegidoHasta = .distantPast
        if dormido { despertar() }
    }

    /// Evita que el ahorro global deshaga la precarga inicial antes de la primera orden.
    /// Al primer uso real, `marcarActividad` cambia a la ventana post-uso normal.
    static func protegerArranque(minutos: Double) {
        guard minutos > 0 else { return }
        protegidoHasta = max(protegidoHasta, Date().addingTimeInterval(minutos * 60))
    }

    private static func revisar() {
        guard Config.ahorroGlobal(), !dormido else { return }
        guard Date() >= protegidoHasta else { return }
        let umbral = max(1, minutosMotorActivo()) * 60
        if Date().timeIntervalSince(ultimaActividad) > umbral { dormir() }
    }

    private static func minutosMotorActivo() -> Double {
        guard Config.ttsProveedor() == "xtts_local", let voz = VocesLocales.activa() else {
            return Config.ttsXttsDormirMin()
        }
        return voz.variante == "mlx" ? Config.ttsMlxDormirMin() : Config.ttsXttsDormirMin()
    }

    private static func dormir() {
        dormido = true
        Log.log(.config, "modo ahorro: durmiendo lo pesado (libera RAM/CPU); fn despierta")
        CalientaRed.detenerLatido()
        if Config.ttsXttsDormir() { XttsServer.detener() }
        if Config.ttsMlxDormir() { MlxVozServer.detener() }
        // (futuro: aquí se sueltan más subsistemas — embeddings locales, etc.)
    }

    private static func despertar() {
        dormido = false
        Log.log(.config, "modo ahorro: despertando (fn)")
        if Config.calentarRed() { CalientaRed.iniciarLatido() }
        Voz.preactivarLocal()
    }
}
