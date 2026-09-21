import AppKit

/// «Sigues grabando» — el borde de la pantalla que late.
///
/// Por qué existe
/// --------------
/// Un dictado quedó abierto **ocho minutos y veinte segundos** sin que nadie
/// hablara. El contador del notch estaba ahí todo el rato y no se miró, que es lo
/// normal: uno mira donde trabaja, no donde está el reloj. Al soltar, ese silencio
/// se transcribe y se paga.
///
/// Por qué un borde y no un cartel
/// -------------------------------
/// El aviso tiene que cumplir tres cosas a la vez, y casi todo falla en alguna:
///
/// - **Verse sin mirar.** Ocupa el perímetro entero de cada pantalla, así que
///   entra por la visión periférica aunque se esté leyendo otra cosa.
/// - **No estorbar.** La ventana no acepta ratón ni teclado: los clics la
///   atraviesan. No roba el foco, no interrumpe lo que se escribe y no aparece
///   por delante de lo que se está leyendo.
/// - **No arruinar una videollamada.** Un destello de pantalla completa se ve
///   igual de bien y sale en la pantalla compartida como un fogonazo. Un borde
///   se nota y no asusta a nadie.
///
/// Sale en **todas** las pantallas: dictar mirando el monitor de al lado es justo
/// el caso en que uno se olvida.
final class AvisoGrabando {

    static let shared = AvisoGrabando()

    private var ventanas: [NSWindow] = []
    private var animando = false

    private init() {}

    /// Toda ventana se toca en el hilo principal. Se garantiza AQUÍ y no en cada
    /// llamada: el aviso se dispara desde un temporizador, desde el cierre del
    /// dictado y desde una alerta modal, y confiar en que los tres estén en main
    /// es la clase de suposición que falla un día y deja una ventana huérfana en
    /// pantalla.
    private func enMain(_ bloque: @escaping () -> Void) {
        if Thread.isMainThread { bloque() } else { DispatchQueue.main.async(execute: bloque) }
    }

    /// Un latido de aviso. `insistente` lo hace más grueso, más lento y más veces.
    func latir(insistente: Bool = false) {
        guard Config.avisoGrabandoBorde() else { return }
        enMain { self.latirEnMain(insistente: insistente) }
    }

    private func latirEnMain(insistente: Bool) {
        montarSiHaceFalta(grosor: insistente ? 22 : 12,
                          color: insistente ? .systemRed : .systemOrange)
        animar(veces: insistente ? 4 : 2, duracion: insistente ? 0.55 : 0.35)
    }

    /// Deja el borde encendido sin parpadear, mientras se espera una respuesta.
    func mantener() {
        guard Config.avisoGrabandoBorde() else { return }
        enMain {
            self.montarSiHaceFalta(grosor: 22, color: .systemRed)
            for v in self.ventanas { v.alphaValue = 1 }
        }
    }

    func apagar() {
        enMain {
            self.animando = false
            for v in self.ventanas { v.orderOut(nil) }
            self.ventanas.removeAll()
        }
    }

    // MARK: Montaje

    private func montarSiHaceFalta(grosor: CGFloat, color: NSColor) {
        // Se rehace en cada aviso a propósito: entre uno y otro puede haberse
        // conectado o quitado un monitor, y un borde que se queda en una pantalla
        // que ya no existe no se ve en ninguna.
        apagar()
        for pantalla in NSScreen.screens {
            let v = NSWindow(contentRect: pantalla.frame, styleMask: .borderless,
                             backing: .buffered, defer: false, screen: pantalla)
            v.isOpaque = false
            v.backgroundColor = .clear
            v.hasShadow = false
            // Por encima de todo, incluidas las apps a pantalla completa.
            v.level = .screenSaver
            // Los clics la ATRAVIESAN: sin esto el aviso secuestraría el ratón.
            v.ignoresMouseEvents = true
            v.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            // Nunca activa la aplicación ni roba el foco del teclado.
            v.styleMask.insert(.nonactivatingPanel)

            let marco = NSView(frame: NSRect(origin: .zero, size: pantalla.frame.size))
            marco.wantsLayer = true
            marco.layer?.borderWidth = grosor
            marco.layer?.borderColor = color.withAlphaComponent(0.9).cgColor
            marco.layer?.cornerRadius = 14
            v.contentView = marco

            v.alphaValue = 0
            v.orderFrontRegardless()
            ventanas.append(v)
        }
    }

    private func animar(veces: Int, duracion: Double) {
        guard !ventanas.isEmpty else { return }
        animando = true
        var restantes = veces
        func pulso() {
            guard animando, restantes > 0 else { apagar(); return }
            restantes -= 1
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duracion / 2
                for v in self.ventanas { v.animator().alphaValue = 1 }
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = duracion / 2
                    for v in self.ventanas { v.animator().alphaValue = 0 }
                }, completionHandler: { pulso() })
            })
        }
        pulso()
    }
}
