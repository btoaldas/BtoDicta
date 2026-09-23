import Foundation

/// Cuándo puede la bitácora volver a pedir el micrófono después de un fallo.
///
/// Por qué existe
/// --------------
/// La bitácora reintenta con espera creciente —2,5 s, 5, 10…—, pero cada
/// arranque fallido cambia el estado del micrófono, ese cambio vuelve a pedirle
/// el micrófono a la bitácora, y ese pedido entraba **sin esperar**. Resultado,
/// medido el 2026-09-23 en una reunión: los seis reintentos y la rendición en el
/// mismo segundo, y vuelta a empezar, ~7 600 líneas de error y el hilo principal
/// un tercio del tiempo montando motores de audio.
///
/// Aquí vive la espera, y todo pedido pasa por ella: el de un reintento
/// programado, el de un cambio de estado y el de después de un dictado.
struct EsperaMicrofono {
    /// Reintentos seguidos antes de rendirse y enfriar.
    static let tope = 6
    /// Tras rendirse, cuánto se espera antes de volver a intentarlo.
    static let enfriamiento: TimeInterval = 60

    enum TrasFallo: Equatable {
        /// Reintento programado dentro de estos segundos.
        case reintentar(numero: Int, en: TimeInterval)
        /// Se rinde: no vuelve a intentar hasta que pase el enfriamiento.
        case enfriar(tras: Int, durante: TimeInterval)
    }

    enum Pedido: Equatable {
        /// Adelante.
        case arrancar
        /// Ya hay un reintento programado: ese se encargará.
        case descartar
        /// Enfriando: que se intente cuando termine, dentro de estos segundos.
        case aplazar(TimeInterval)
    }

    private(set) var intentos = 0
    private(set) var noAntesDe = Date.distantPast
    private(set) var enfriando = false
    /// Hay un reintento programado que todavía no ha corrido. Se mira el
    /// reintento, no el reloj: un pedido que llega justo cuando vence la espera,
    /// un instante antes que el reintento, hacía dos intentos donde tocaba uno.
    private(set) var reintentoPendiente = false

    mutating func fallo(en ahora: Date) -> TrasFallo {
        intentos += 1
        guard intentos <= Self.tope else {
            let n = intentos
            intentos = 0
            enfriando = true
            reintentoPendiente = false
            noAntesDe = ahora.addingTimeInterval(Self.enfriamiento)
            return .enfriar(tras: n, durante: Self.enfriamiento)
        }
        // Espera creciente de verdad: 2,5 s, 5 s, 10 s, 20 s…
        let espera = min(60.0, 2.5 * pow(2.0, Double(intentos - 1)))
        enfriando = false
        reintentoPendiente = true
        noAntesDe = ahora.addingTimeInterval(espera)
        return .reintentar(numero: intentos, en: espera)
    }

    /// Llegó audio de verdad, o el micrófono cambió de dueño (el dictado lo tomó):
    /// es otra situación, y el siguiente pedido entra sin esperar.
    mutating func reiniciar() {
        intentos = 0
        enfriando = false
        reintentoPendiente = false
        noAntesDe = .distantPast
    }

    /// El reintento programado empieza: a partir de aquí manda su resultado.
    mutating func reintentoLlega() {
        reintentoPendiente = false
    }

    /// Un pedido que no viene de un reintento programado.
    func pedido(en ahora: Date) -> Pedido {
        if reintentoPendiente { return .descartar }
        if enfriando, ahora < noAntesDe { return .aplazar(noAntesDe.timeIntervalSince(ahora)) }
        return .arrancar
    }
}
