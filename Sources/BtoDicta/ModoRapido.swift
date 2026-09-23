import Foundation
import UserNotifications

/// Los controles rápidos del icono: modo reunión y pausa de la bitácora
/// (spec 010, T01 y T04).
///
/// Por qué existen
/// ---------------
/// Lo que cuesta ir a Ajustes, no se hace. En una reunión de una hora el dictado
/// se cerraba cada pocos segundos, y evitarlo exigía abrir Ajustes y mover un
/// deslizador delante de la gente. No se hizo, y la reunión quedó troceada en
/// once grabaciones. Por el otro lado, apagar la bitácora un rato exigía entrar,
/// buscar el interruptor y acordarse de encenderla después: nadie lo hacía.
///
/// Dos reglas que no se negocian
/// -----------------------------
/// 1. **Ninguno de los dos escribe en los ajustes del usuario.** El modo reunión
///    los IGNORA mientras está puesto; no pone el corte de silencio a cero. Un
///    modo que escribe en los ajustes los pierde el día que la aplicación se
///    cierra mal (spec 010, RF-08, D-4).
/// 2. **La pausa guarda el INSTANTE en que vence, no los minutos que faltan.**
///    Una cuenta atrás se congela con la aplicación cerrada o el equipo
///    suspendido: «media hora» se convertiría en media hora de uso, no de reloj
///    (D-1). Con un instante, cerrar, reiniciar o suspender no altera nada.
enum ModoRapido {

    static let claveReunion = "modo_reunion"
    static let clavePausa = "bitacora_pausada_hasta"
    /// Las únicas dos claves que esto escribe. El QA compara todas las demás
    /// antes y después, y falla si alguna cambió.
    static let clavesDeEstado: Set<String> = [claveReunion, clavePausa]

    /// Se avisa aquí de cualquier cambio, para que el icono y el menú se pongan
    /// al día sin que esto tenga que conocerlos.
    static let cambio = Notification.Name("ModoRapidoCambio")

    // MARK: - Modo reunión

    static var enReunion: Bool { (Config.json0(claveReunion) as? Bool) ?? false }

    static func ponerReunion(_ si: Bool) {
        guard si != enReunion else { return }
        Config.set(claveReunion, to: si)
        Log.log(.sistema, si
            ? "modo reunión: puesto — el dictado no se cortará por silencio ni por duración hasta quitarlo"
            : "modo reunión: quitado — vuelven el corte por silencio, el tope y los avisos")
        avisarCambio()
    }

    // MARK: - Pausa: la parte pura
    //
    // Todo lo que decide recibe `ahora` como parámetro. Así se prueba una pausa
    // de media hora, un reinicio o una suspensión de dos horas en milisegundos,
    // y sin tocar la configuración real de nadie.

    /// Cómo se guarda el vencimiento. Recibe `ahora` aunque no lo use: es la
    /// firma que tendría una cuenta atrás, y la prueba del reinicio la sabotea
    /// justo ahí para demostrar por qué no se hace así.
    static func aGuardar(hasta: Date?, ahora: Date) -> Double {
        hasta?.timeIntervalSince1970 ?? 0
    }

    static func alCargar(_ v: Any?, ahora: Date) -> Date? {
        guard let s = v as? Double, s > 0 else { return nil }
        return Date(timeIntervalSince1970: s)
    }

    static func vigente(hasta: Date?, ahora: Date) -> Bool {
        guard let h = hasta else { return false }
        return ahora < h
    }

    static func hasta(minutos: Double, desde ahora: Date) -> Date {
        ahora.addingTimeInterval(minutos * 60)
    }

    /// «Hasta mañana» es mañana a las ocho, no dentro de veinticuatro horas: quien
    /// lo elige a las once de la noche no quiere estar sin bitácora hasta las
    /// once de la noche siguiente.
    static func hastaManana(desde ahora: Date, hora: Int = 8,
                            calendario: Calendar = .current) -> Date {
        let manana = calendario.date(byAdding: .day, value: 1, to: ahora) ?? ahora
        return calendario.date(bySettingHour: hora, minute: 0, second: 0, of: manana) ?? manana
    }

    // MARK: - Pausa: contra la configuración

    static var pausadaHasta: Date? { alCargar(Config.json0(clavePausa), ahora: Date()) }

    static func pausaVigente(ahora: Date = Date()) -> Bool {
        vigente(hasta: pausadaHasta, ahora: ahora)
    }

    /// Pausa hasta un instante. Pausar estando pausada SUSTITUYE el plazo, no lo
    /// acumula: quien elige «30 min» quiere media hora desde ahora.
    static func pausar(hasta: Date, ahora: Date = Date()) {
        Config.set(clavePausa, to: aGuardar(hasta: hasta, ahora: ahora))
        ContinuoBitacora.detener()
        Log.log(.sistema, "bitácora: en pausa hasta las \(horaLegible(hasta)) — no se graba audio ni pantalla")
        // Avisa al EMPEZAR, no solo al volver: quien pulsó sin querer tiene que
        // enterarse en el acto de que se dejó de mirar.
        avisarUsuario(titulo: "Bitácora en pausa",
                      cuerpo: "No se graba audio ni pantalla hasta las \(horaLegible(hasta)). Vuelve sola.")
        vigilar()
        avisarCambio()
    }

    static func pausar(minutos: Double) { pausar(hasta: hasta(minutos: minutos, desde: Date())) }

    /// Reanuda ya, o porque venció. Deja escrito por qué.
    static func reanudar(motivo: String) {
        let estaba = pausadaHasta != nil
        Config.set(clavePausa, to: 0.0)
        detenerVigia()
        guard estaba else { return }
        Log.log(.sistema, "bitácora: pausa terminada (\(motivo)) — vuelve a mirar")
        ContinuoBitacora.arrancar()
        avisarUsuario(titulo: "La bitácora vuelve a mirar",
                      cuerpo: motivo == "venció"
                        ? "Terminó la pausa que pusiste. Se graba audio y pantalla otra vez."
                        : "Pausa quitada. Se graba audio y pantalla otra vez.")
        avisarCambio()
    }

    // MARK: - El vigía del vencimiento (T04)
    //
    // `DispatchSourceTimer` en su propia cola, no `Timer` en el bucle principal.
    // Ese error ya se pagó en este proyecto: un `Timer` añadido desde un hilo de
    // fondo a veces no quedaba registrado, y el apagado del motor de embeddings
    // «funcionaba a ratos», que es la peor forma de fallar.
    //
    // Compara contra el RELOJ en cada vuelta. Así despertar de una suspensión no
    // necesita tratamiento especial: o ya venció, o no.

    private static let cola = DispatchQueue(label: "btodicta.modorapido.vigia")
    private static var vigia: DispatchSourceTimer?

    /// Cada cuánto se comprueba. 15 s de fábrica: el vencimiento llega con menos
    /// de 60 s de retraso (RNF-02). Una prueba puede acortarlo.
    static var intervaloVigia: Double {
        if let v = ProcessInfo.processInfo.environment["BTODICTA_PAUSA_INTERVALO"],
           let s = Double(v), s > 0 { return s }
        return 15
    }

    /// Arranca el vigía si hay una pausa guardada. Se llama al arrancar la app
    /// y al pausar. Si la pausa venció con la aplicación cerrada, se reanuda ya.
    static func vigilar() {
        cola.async {
            guard vigia == nil else { return }
            guard let h = pausadaHasta else { return }
            if !vigente(hasta: h, ahora: Date()) {
                DispatchQueue.main.async { reanudar(motivo: "venció") }
                return
            }
            let t = DispatchSource.makeTimerSource(queue: cola)
            t.schedule(deadline: .now() + intervaloVigia, repeating: intervaloVigia)
            t.setEventHandler {
                if !pausaVigente() {
                    DispatchQueue.main.async { reanudar(motivo: "venció") }
                }
            }
            vigia = t
            t.resume()
        }
    }

    private static func detenerVigia() {
        cola.async {
            vigia?.cancel()
            vigia = nil
        }
    }

    // MARK: - Avisos

    private static func avisarCambio() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: cambio, object: nil) }
    }

    /// Aviso del sistema. Una pausa que vuelve sin decirlo es casi tan mala como
    /// una que no vuelve: el usuario tiene que saber que otra vez se está mirando.
    private static func avisarUsuario(titulo: String, cuerpo: String) {
        Log.log(.sistema, "aviso: \(titulo) — \(cuerpo)")
        guard Bundle.main.bundleIdentifier != nil,
              ProcessInfo.processInfo.environment["BTODICTA_DIR"] == nil else { return }
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = cuerpo
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pausa-\(UUID().uuidString)", content: c, trigger: nil))
    }

    /// «● Grabando 12:34 · 18,3 MB por transcribir» (spec 010, RF-07). Pura, para
    /// poder probar una sesión de veinte horas sin grabar veinte horas.
    static func textoGrabacion(segundos: Int, bytes: Int, reunion: Bool) -> String {
        let s = max(segundos, 0)
        let reloj = s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
        let mb = Double(max(bytes, 0)) / 1_048_576
        // Coma decimal: se lee en español.
        let cifra = String(format: "%.1f", locale: Locale(identifier: "es_EC"), mb)
        return "● Grabando \(reloj) · \(cifra) MB por transcribir"
            + (reunion ? " · modo reunión" : "")
    }

    static func horaLegible(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_EC")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: d)
    }
}
