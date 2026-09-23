import Foundation
import CoreGraphics

/// ¿Puede BtoDicta registrar su icono en la barra? (spec 011)
///
/// Por qué existe
/// --------------
/// macOS 26 anota el icono de la barra a nombre del **proceso responsable** de la
/// aplicación. Si la abre el sistema —Dock, Finder, Spotlight, el inicio de sesión,
/// `open`, el actualizador— la aplicación es responsable de sí misma. Si su binario
/// se ejecuta directamente desde una terminal, el responsable es el programa dueño
/// de esa terminal, y el icono queda apuntado en SU fila.
///
/// Si ese programa está bloqueado en la barra, el icono desaparece. Y el apunte se
/// queda guardado: abierta después de forma normal, sigue oculta. Se midió con una
/// aplicación desechable de identificador propio, en las tres situaciones.
///
/// En BtoDicta lo provocaban las pruebas, que ejecutaban el binario del paquete. Un
/// script lo reparaba reescribiendo los ajustes de la barra, y la siguiente prueba
/// lo volvía a romper. Esto no repara: impide que se produzca.
enum IconoBarra {

    /// Solo se registra el icono si a la aplicación la lanzó el sistema, es decir,
    /// si su proceso padre es `launchd` (pid 1).
    ///
    /// No se usa la API privada que pregunta por el «proceso responsable»: puede
    /// cambiar sin aviso. El padre es público, y se midió en los caminos reales:
    /// Dock, Finder, `open` y el relanzamiento tras actualizarse dan pid 1; el
    /// binario ejecutado desde una terminal da el pid de esa terminal.
    ///
    /// **No hay interruptor para saltárselo**, a propósito. Cualquier herramienta lo
    /// activaría para «que funcione» y volvería a envenenar el icono. Lo que necesita
    /// el icono de verdad —una prueba incluida— se abre como lo abre el sistema.
    static func debeRegistrar(padre: pid_t) -> Bool { padre == 1 }

    /// El motivo, para el registro, cuando no se registra.
    static func motivoParaNoRegistrar(padre: pid_t) -> String {
        "icono barra: NO se registra — a esta copia no la lanzó el sistema (proceso padre \(padre), no launchd). "
            + "macOS apuntaría el icono a nombre de quien la lanzó y, si ese programa está bloqueado en la barra, "
            + "lo escondería también en los arranques normales. Ábrela desde el Dock, el Finder o con `open`."
    }
}

// MARK: - ¿Se ve el icono? (spec 012)

/// Una pantalla reducida a lo que hace falta para saber si un icono de la barra se
/// ve: su marco, la parte que deja libre la barra y, si tiene muesca, las dos
/// zonas útiles a sus lados. Rectángulos en coordenadas globales de AppKit (origen
/// abajo a la izquierda), para poder probarlo sin pantallas de verdad.
struct PantallaBarra: Equatable {
    var marco: CGRect
    var visible: CGRect
    var muescaIzquierda: CGRect? = nil
    var muescaDerecha: CGRect? = nil
}

enum VisibilidadIcono: Equatable {
    case visible
    /// No se ve, y no es porque la barra esté escondida. El texto dice dónde está.
    case oculto(String)
    /// No se puede saber: la barra no está en pantalla (pantalla completa,
    /// ocultación automática). No es un fallo y no se avisa.
    case noSeSabe(String)
}

extension IconoBarra {

    /// Dónde está la ventana del icono, y si eso es «a la vista».
    ///
    /// Por la **posición**, no por la oclusión de la ventana: la oclusión también
    /// dice «no visible» con la pantalla dormida o bloqueada, y avisaría en falso
    /// cada noche. El icono escondido que se midió (spec 011) estaba en el borde
    /// inferior de la pantalla, fuera de la franja de la barra.
    ///
    /// - `barraEnPantalla`: si la barra de menús está dibujada ahora. Con una app a
    ///   pantalla completa no lo está, y entonces no se sabe nada del icono.
    static func visibilidad(ventana: CGRect?, pantallas: [PantallaBarra],
                            barraEnPantalla: Bool = true) -> VisibilidadIcono {
        guard barraEnPantalla else { return .noSeSabe("la barra no está en pantalla") }
        guard let v = ventana, v.width > 0, v.height > 0 else { return .oculto("sin ventana") }
        let centro = CGPoint(x: v.midX, y: v.midY)
        guard let p = pantallas.first(where: { $0.marco.contains(centro) }) else {
            return .oculto("fuera de toda pantalla (\(Int(v.minX)), \(Int(v.minY)))")
        }
        // La franja de la barra: lo que queda entre la parte útil y el borde
        // superior. Sin franja, la barra se oculta sola: no se sabe.
        let alto = p.marco.maxY - p.visible.maxY
        guard alto >= 10 else { return .noSeSabe("la barra se oculta sola") }
        guard centro.y >= p.visible.maxY - 1, centro.y <= p.marco.maxY + 1 else {
            return .oculto("fuera de la barra (\(Int(v.minX)), \(Int(v.minY)))")
        }
        if let izq = p.muescaIzquierda, let der = p.muescaDerecha {
            // Las zonas de la muesca pueden venir en coordenadas de la pantalla:
            // si no caen dentro de su marco, se desplazan a él.
            let dx = p.marco.intersects(izq) ? 0 : p.marco.minX
            let desde = izq.maxX + dx, hasta = der.minX + (p.marco.intersects(der) ? 0 : p.marco.minX)
            if desde < hasta, centro.x > desde, centro.x < hasta {
                return .oculto("bajo la muesca (x = \(Int(centro.x)))")
            }
        }
        return .visible
    }
}

/// Decide cuándo avisar de que el icono no se ve, y cuándo recordar que el modo
/// reunión sigue puesto con el icono escondido (spec 012).
///
/// Pura: recibe cada lectura con su hora. Quien la usa pone el reloj.
struct VigiaIconoOculto {
    enum Evento: Equatable { case avisar, recordar }

    /// Segundos oculto sin interrupción antes de avisar.
    var gracia: TimeInterval
    /// Cada cuánto recordar el modo reunión con el icono oculto. 0 = nunca.
    var intervaloRecordatorio: TimeInterval

    private(set) var ocultoDesde: Date?
    private(set) var avisado = false
    private(set) var recordatorioDesde: Date?

    init(gracia: TimeInterval, intervaloRecordatorio: TimeInterval) {
        self.gracia = gracia
        self.intervaloRecordatorio = intervaloRecordatorio
    }

    /// El aviso no llegó a mostrarse —el icono volvió a verse mientras se
    /// esperaba a que acabara el dictado—: que pueda salir la próxima vez.
    mutating func rearmarAviso() { avisado = false }

    /// `true` si lleva oculto al menos la gracia.
    func confirmado(en ahora: Date) -> Bool {
        guard let d = ocultoDesde else { return false }
        return ahora.timeIntervalSince(d) >= gracia
    }

    mutating func observar(_ v: VisibilidadIcono, reunion: Bool, noVolverAAvisar: Bool,
                           en ahora: Date) -> [Evento] {
        switch v {
        case .visible:
            // Se ve: todo vuelve a empezar. Si se vuelve a esconder, se vuelve a
            // contar la gracia; el aviso, en cambio, es uno por sesión.
            ocultoDesde = nil
            recordatorioDesde = nil
            return []
        case .noSeSabe:
            // Ni avanza ni reinicia: pantalla completa no dice nada del icono.
            return []
        case .oculto:
            if ocultoDesde == nil { ocultoDesde = ahora }
        }
        var eventos: [Evento] = []
        guard confirmado(en: ahora) else { return [] }
        if !avisado, !noVolverAAvisar {
            avisado = true
            eventos.append(.avisar)
        }
        if reunion, intervaloRecordatorio > 0 {
            // El primer recordatorio llega un intervalo después de que coincidan
            // las dos cosas, no en el acto: el aviso acaba de salir.
            if let desde = recordatorioDesde {
                if ahora.timeIntervalSince(desde) >= intervaloRecordatorio {
                    recordatorioDesde = ahora
                    eventos.append(.recordar)
                }
            } else {
                recordatorioDesde = ahora
            }
        } else {
            recordatorioDesde = nil
        }
        return eventos
    }
}

// MARK: - Lo que se le dice al usuario (spec 012)

extension VisibilidadIcono {
    /// Para el registro y para el aviso.
    var texto: String {
        switch self {
        case .visible: return "visible"
        case .oculto(let m): return "oculto: \(m)"
        case .noSeSabe(let m): return "no se sabe: \(m)"
        }
    }
}

extension IconoBarra {
    /// Cómo seguir sin el icono. Depende de si BtoDicta está en el Dock: su menú
    /// allí es una copia del del icono (spec 010).
    static func comoSeguir(enDock: Bool) -> String {
        enDock
            ? "Mientras tanto, el menú de BtoDicta en el Dock tiene los mismos controles, y fn fn fn pone o quita el modo reunión (abre también un dictado; otra fn lo cierra)."
            : "Mientras tanto, fn fn fn pone o quita el modo reunión (abre también un dictado; otra fn lo cierra), y abrir BtoDicta otra vez desde Spotlight muestra sus ajustes, donde puedes ponerla en el Dock."
    }

    /// El aviso, una vez (RF-01): qué pasa y cómo se arregla.
    static func textoAviso(_ v: VisibilidadIcono, enDock: Bool) -> (titulo: String, cuerpo: String) {
        let donde: String
        if case .oculto(let m) = v { donde = " (\(m))" } else { donde = "" }
        return ("El icono de BtoDicta no se ve en la barra",
                "BtoDicta sigue abierta y funcionando, pero macOS tiene su icono escondido\(donde).\n\n"
                + "Para que vuelva: Ajustes del Sistema → Barra de menús → en «Permitir en la barra de menús», "
                + "activa BtoDicta. Si ya lo está, la barra puede ir llena: quita algún icono que no uses.\n\n"
                + comoSeguir(enDock: enDock))
    }

    /// El recordatorio del modo reunión con el icono escondido (RF-06).
    static func textoRecordatorio(enDock: Bool) -> (titulo: String, cuerpo: String) {
        ("El modo reunión sigue puesto",
         "El icono de BtoDicta no se ve, así que no hay otra forma de saberlo: el dictado no se cortará por silencio. "
            + (enDock ? "Quítalo desde el menú de BtoDicta en el Dock, o con fn fn fn."
                      : "Quítalo con fn fn fn: abre también un dictado, que otra fn cierra."))
    }
}
