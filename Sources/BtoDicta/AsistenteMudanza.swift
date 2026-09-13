import AppKit

// MARK: - Asistente de mudanza para quien tenía la app con el nombre anterior
//
// La aplicación cambió de nombre, y con él su identificador. Para macOS es otra
// aplicación distinta, así que la actualización automática de una instalación
// antigua no puede limitarse a reemplazar el bundle: buscaría dentro del paquete
// una app con el nombre viejo y, al no encontrarla, cancelaría.
//
// La solución es este puente: el paquete incluye también una app con el nombre y
// el identificador ANTIGUOS cuyo único cometido es explicar la mudanza y
// hacerla. La instalación automática de la versión vieja la encuentra, la
// instala y la abre; el usuario ve este asistente en vez de un error.
//
// El puente NO toca los datos de nadie: solo instala la aplicación nueva, que ya
// se encarga de mudar sus propias carpetas cuando arranca.
@MainActor
final class AsistenteMudanza: NSObject, NSApplicationDelegate {

    /// Identificador con el que se publicó la aplicación antes del cambio.
    static let identificadorAnterior = "ec.bto.betodicta"

    /// ¿Este bundle es el puente? Se decide por el identificador, no por el
    /// nombre del archivo: el usuario puede haber renombrado la aplicación.
    /// Se consulta desde `main` antes de que exista aplicación, así que vive
    /// fuera del aislamiento del hilo principal.
    nonisolated static var esPuente: Bool {
        Bundle.main.bundleIdentifier == identificadorAnterior
    }

    private var ventana: NSWindow!
    private var titulo: NSTextField!
    private var cuerpo: NSTextField!
    private var progreso: NSProgressIndicator!
    private var botonPrincipal: NSButton!
    private var botonSecundario: NSButton!
    private var instalando = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        construirVentana()
        mostrarBienvenida()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    // MARK: Ventana

    private func construirVentana() {
        ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        ventana.title = "Actualización de BetoDicta"
        ventana.center()
        ventana.isReleasedWhenClosed = false

        let fondo = NSView(frame: ventana.contentView!.bounds)
        fondo.autoresizingMask = [.width, .height]

        titulo = NSTextField(labelWithString: "")
        titulo.font = .systemFont(ofSize: 20, weight: .semibold)
        titulo.frame = NSRect(x: 32, y: 352, width: 556, height: 30)
        titulo.autoresizingMask = [.width, .minYMargin]

        cuerpo = NSTextField(wrappingLabelWithString: "")
        cuerpo.font = .systemFont(ofSize: 13)
        cuerpo.frame = NSRect(x: 32, y: 96, width: 556, height: 248)
        cuerpo.autoresizingMask = [.width, .height]

        progreso = NSProgressIndicator(frame: NSRect(x: 32, y: 70, width: 556, height: 16))
        progreso.style = .bar
        progreso.isIndeterminate = false
        progreso.minValue = 0
        progreso.maxValue = 1
        progreso.isHidden = true
        progreso.autoresizingMask = [.width, .minYMargin]

        botonPrincipal = NSButton(title: "", target: self, action: #selector(accionPrincipal))
        botonPrincipal.bezelStyle = .rounded
        botonPrincipal.keyEquivalent = "\r"
        botonPrincipal.frame = NSRect(x: 388, y: 24, width: 200, height: 32)
        botonPrincipal.autoresizingMask = [.minXMargin, .maxYMargin]

        botonSecundario = NSButton(title: "", target: self, action: #selector(accionSecundaria))
        botonSecundario.bezelStyle = .rounded
        botonSecundario.frame = NSRect(x: 200, y: 24, width: 176, height: 32)
        botonSecundario.autoresizingMask = [.minXMargin, .maxYMargin]

        for v in [titulo!, cuerpo!, progreso!, botonPrincipal!, botonSecundario!] as [NSView] {
            fondo.addSubview(v)
        }
        ventana.contentView = fondo
        ventana.makeKeyAndOrderFront(nil)
    }

    // MARK: Pasos

    private func mostrarBienvenida() {
        titulo.stringValue = "BetoDicta ahora se llama BtoDicta"
        cuerpo.stringValue = """
        Esta ventana aparece porque la aplicación cambió de nombre. No es un error \
        y no has perdido nada.

        Para macOS, un cambio de nombre convierte la aplicación en otra distinta, \
        así que hay que instalarla una vez. Este asistente lo hace por ti:

        1. Descarga BtoDicta y comprueba su firma.
        2. La instala en tu carpeta de Aplicaciones y la abre.
        3. Al abrirse, BtoDicta mueve sola tus ajustes, modelos, voces, historial \
        y bitácora a su sitio nuevo, y recupera tus claves guardadas. No tienes que \
        volver a escribir ninguna.

        Después de instalarla, macOS te pedirá de nuevo permiso de micrófono, \
        accesibilidad y automatización: para el sistema es una aplicación nueva y \
        solo lo pide la primera vez.

        Necesitas conexión a internet. Tarda menos de un minuto.
        """
        botonPrincipal.title = "Instalar BtoDicta"
        botonPrincipal.isEnabled = true
        botonSecundario.title = "Descargar a mano"
        botonSecundario.isHidden = false
        progreso.isHidden = true
    }

    private func mostrarError(_ detalle: String) {
        instalando = false
        titulo.stringValue = "No pude completar la instalación"
        cuerpo.stringValue = """
        \(detalle)

        Puedes instalarla tú mismo en un minuto:

        1. Pulsa «Descargar a mano»: se abre la página de descargas.
        2. Baja el archivo BtoDicta.dmg y ábrelo.
        3. Arrastra BtoDicta a tu carpeta de Aplicaciones.
        4. Ábrela. Tus datos y tus claves se mudan solos.

        Si macOS dice que la aplicación no se puede abrir, ve a Ajustes del \
        Sistema, entra en Privacidad y seguridad y pulsa «Abrir de todos modos». \
        Solo hace falta la primera vez.
        """
        botonPrincipal.title = "Reintentar"
        botonPrincipal.isEnabled = true
        botonSecundario.title = "Descargar a mano"
        botonSecundario.isHidden = false
        progreso.isHidden = true
    }

    private func mostrarInstalando(_ fraccion: Double?) {
        titulo.stringValue = "Instalando BtoDicta…"
        cuerpo.stringValue = """
        Descargando y comprobando la firma del paquete.

        Cuando termine, BtoDicta se abrirá sola y esta ventana se cerrará. \
        No cierres el ordenador mientras tanto.
        """
        botonPrincipal.isEnabled = false
        botonSecundario.isHidden = true
        progreso.isHidden = false
        if let f = fraccion {
            progreso.isIndeterminate = false
            progreso.doubleValue = f
        } else {
            progreso.isIndeterminate = true
            progreso.startAnimation(nil)
        }
    }

    // MARK: Acciones

    @objc private func accionPrincipal() {
        guard !instalando else { return }
        instalando = true
        mostrarInstalando(nil)
        Updater.verificar { [weak self] estado in
            guard let self else { return }
            switch estado {
            case .disponible(_, let dmg, _):
                self.instalar(dmg)
            case .alDia:
                // La última publicada coincide con la versión de este puente:
                // se instala igualmente desde la página, que siempre existe.
                self.mostrarError("La descarga automática no encontró una versión nueva que instalar.")
            case .error(let m):
                self.mostrarError("No pude consultar las descargas: \(m).")
            default:
                self.mostrarError("La comprobación de descargas no respondió.")
            }
        }
    }

    private func instalar(_ dmg: URL) {
        Updater.actualizar(dmg: dmg) { [weak self] estado in
            guard let self else { return }
            switch estado {
            case .descargando(let f):
                self.mostrarInstalando(f)
            case .error(let m):
                self.mostrarError("La instalación automática falló: \(m).")
            default:
                break
            }
        }
        // Cuando la instalación llega al final, el instalador abre BtoDicta y
        // cierra este puente: no hay más pasos que dar aquí.
    }

    @objc private func accionSecundaria() {
        if let u = URL(string: "https://github.com/btoaldas/BtoDicta/releases/latest") {
            NSWorkspace.shared.open(u)
        }
    }
}
