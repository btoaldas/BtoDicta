import Foundation

/// Autoridad única de captura. Una generación invalida callbacks de ventanas
/// anteriores sin perder el permiso para incorporar después su dictado.
final class ContinuoCapturaSesion {
    struct Preferencias {
        var activo: Bool
        var soloGrabaciones: Bool
        var pausada: Bool
    }

    struct Contexto: Equatable, Sendable {
        let sesion: String?
        let generacion: UInt64
        let inicio: Date
    }

    private struct Ventana {
        let inicio: Date
        var fin: Date?
        var dictadoCompleto = true
    }

    static let shared = ContinuoCapturaSesion(preferencias: {
        Preferencias(activo: Config.continuoActivo(),
                     soloGrabaciones: Config.continuoSoloGrabaciones(),
                     pausada: ModoRapido.pausaVigente())
    })

    private let bloqueo = NSLock()
    private let preferencias: () -> Preferencias
    private let reloj: () -> Date
    private var grabando = false
    private var generacion: UInt64 = 0
    private var inicioGeneracion: Date
    private var contexto: Contexto?
    private var ventanas: [String: Ventana] = [:]

    /// Las dependencias permiten probar el contrato sin micrófono ni ajustes reales.
    init(preferencias: @escaping () -> Preferencias, reloj: @escaping () -> Date = Date.init) {
        self.preferencias = preferencias
        self.reloj = reloj
        inicioGeneracion = reloj()
    }

    @discardableResult
    func iniciarGrabacion() -> Contexto? {
        let p = preferencias(), ahora = reloj()
        bloqueo.lock(); defer { bloqueo.unlock() }
        cerrarVentana(ahora, dictadoCompleto: false)
        grabando = true
        return abrirVentana(si: p.activo && !p.pausada, ahora: ahora)
    }

    func cerrarGrabacion() {
        let ahora = reloj()
        bloqueo.lock(); defer { bloqueo.unlock() }
        grabando = false
        cerrarVentana(ahora)
    }

    /// Pausar o cambiar ajustes cierra la ventana, pero el grabador puede seguir.
    func suspenderCaptura() {
        let ahora = reloj()
        bloqueo.lock(); defer { bloqueo.unlock() }
        cerrarVentana(ahora, dictadoCompleto: false)
    }

    func reanudarCapturaSiGrabando() {
        let p = preferencias(), ahora = reloj()
        bloqueo.lock(); defer { bloqueo.unlock() }
        guard grabando, contexto == nil else { return }
        _ = abrirVentana(si: p.activo && !p.pausada, ahora: ahora)
    }

    func contextoActual() -> Contexto? {
        let p = preferencias()
        guard p.activo, !p.pausada else { return nil }
        bloqueo.lock(); defer { bloqueo.unlock() }
        if let contexto { return contexto }
        guard !p.soloGrabaciones else { return nil }
        return Contexto(sesion: nil, generacion: generacion, inicio: inicioGeneracion)
    }

    func vigente(_ contexto: Contexto) -> Bool { contextoActual() == contexto }

    func sesionAutorizada(_ sesion: String) -> Bool {
        bloqueo.lock(); defer { bloqueo.unlock() }
        return ventanas[sesion]?.dictadoCompleto == true
    }

    /// Un POST tardío se valida contra el instante original, nunca contra otra
    /// grabación que haya empezado después. No se acepta material futuro.
    func admiteMaterial(sesion: String?, instante: Date) -> Bool {
        let ahora = reloj()
        guard instante <= ahora else { return false }
        if let sesion, !sesion.isEmpty {
            bloqueo.lock(); defer { bloqueo.unlock() }
            guard let ventana = ventanas[sesion] else { return false }
            return instante >= ventana.inicio && instante <= (ventana.fin ?? ahora)
        }
        guard let actual = contextoActual(), actual.sesion == nil else { return false }
        return instante >= actual.inicio
    }

    private func cerrarVentana(_ ahora: Date, dictadoCompleto: Bool = true) {
        if let sesion = contexto?.sesion {
            ventanas[sesion]?.fin = ahora
            ventanas[sesion]?.dictadoCompleto = dictadoCompleto
        }
        contexto = nil
        generacion &+= 1
        inicioGeneracion = ahora
    }

    private func abrirVentana(si permitida: Bool, ahora: Date) -> Contexto? {
        guard permitida else { return nil }
        let sesion = UUID().uuidString
        ventanas[sesion] = Ventana(inicio: ahora, fin: nil)
        let nueva = Contexto(sesion: sesion, generacion: generacion, inicio: ahora)
        contexto = nueva
        return nueva
    }
}
