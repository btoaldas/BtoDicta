import Foundation
import Network

/// ¿Tiene red ESTE equipo? (2026-09-24)
///
/// Por qué existe
/// --------------
/// Con el equipo dormido o sin Wi-Fi, cada fallo de conexión se le apuntaba al
/// proveedor de IA de turno, y su cuarentena subía —un minuto, cinco, quince—
/// aunque el proveedor estuviera perfecto: el de pulido preferido quedó apartado
/// quince minutos DESPUÉS de volver la red. Y los trabajos de fondo —el correo
/// de las 07:00, las rutinas de la bitácora— se lanzaban sin red, gastaban una
/// ronda de llamadas y lo reintentaban a los dos minutos, cinco veces seguidas.
///
/// Lo que falla por NUESTRA red no es culpa de nadie más: no aparta a ningún
/// proveedor, y lo de fondo espera a que vuelva.
final class EstadoRed {
    static let shared = EstadoRed()

    private let monitor = NWPathMonitor()
    private let cola = DispatchQueue(label: "btodicta.estado-red")
    private let candado = NSLock()
    /// Hasta saber lo contrario, hay red: sin monitor (pruebas, arranque) nada
    /// cambia de comportamiento.
    private var _hayRed = true
    private var arrancado = false
    private var alVolver: [() -> Void] = []

    var hayRed: Bool {
        candado.lock(); defer { candado.unlock() }
        return _hayRed
    }

    func arrancar() {
        candado.lock()
        guard !arrancado else { candado.unlock(); return }
        arrancado = true
        candado.unlock()
        monitor.pathUpdateHandler = { [weak self] ruta in
            self?.actualizar(ruta.status == .satisfied)
        }
        monitor.start(queue: cola)
    }

    /// También para la prueba propia: simula que la red se va o vuelve.
    func actualizar(_ hay: Bool) {
        candado.lock()
        let antes = _hayRed
        _hayRed = hay
        let pendientes = hay && !antes ? alVolver : []
        if hay && !antes { alVolver.removeAll() }
        candado.unlock()
        guard hay != antes else { return }
        Log.log(.sistema, hay ? "red: vuelve la conexión\(pendientes.isEmpty ? "" : " — retomo \(pendientes.count) trabajo(s) que esperaban")"
                              : "red: este equipo se quedó sin conexión — lo de fondo espera y no se aparta a ningún proveedor")
        for p in pendientes { DispatchQueue.main.async(execute: p) }
    }

    /// Ahora si hay red; si no, en cuanto vuelva (una sola vez).
    func cuandoHayaRed(_ trabajo: @escaping () -> Void) {
        candado.lock()
        if _hayRed { candado.unlock(); DispatchQueue.main.async(execute: trabajo); return }
        alVolver.append(trabajo)
        candado.unlock()
    }
}
