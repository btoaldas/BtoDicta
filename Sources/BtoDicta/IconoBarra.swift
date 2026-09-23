import Foundation

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
