import Foundation

/// Estado mínimo para reconocer una doble pulsación sin temporizadores ni
/// bloquear el hilo del teclado. La primera pulsación completa arma la puerta;
/// la segunda debe empezar dentro de la ventana configurada.
struct DoublePressGate {
    private(set) var primera: Date?

    var armada: Bool { primera != nil }

    mutating func armar(en fecha: Date = Date()) {
        primera = fecha
    }

    /// Consume la primera pulsación solo cuando la segunda llegó a tiempo.
    /// Una marca vencida también se limpia para que no pueda activarse después.
    mutating func consumirSiCorresponde(en fecha: Date = Date(), ventana: TimeInterval) -> Bool {
        guard let primera else { return false }
        self.primera = nil
        let lapso = fecha.timeIntervalSince(primera)
        return lapso >= 0 && lapso <= ventana
    }

    mutating func reiniciar() {
        primera = nil
    }
}

/// La confirmación de un modo tiene prioridad sobre la activación con doble fn.
/// También cubre la carrera en que la pregunta aparece DESPUÉS de bajar fn pero
/// ANTES de soltarla. La misma pulsación solo puede confirmar si no empezó como
/// la orden de detener una grabación: detener nunca debe aceptar a ciegas el
/// modal que produzca ese dictado unos milisegundos después.
enum ConfirmacionFnPolicy {
    static func aceptarAlBajar(hayConfirmacion: Bool) -> Bool {
        hayConfirmacion
    }

    static func aceptarAlSoltar(confirmacionConsumidaAlBajar: Bool,
                                hayConfirmacionAhora: Bool,
                                inicioGrabando: Bool) -> Bool {
        !confirmacionConsumidaAlBajar && hayConfirmacionAhora && !inicioGrabando
    }
}
