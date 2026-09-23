import XCTest
@testable import BtoDicta

/// Solo se registra el icono si lanzó la aplicación el sistema (spec 011, T01).
final class IconoBarraTests: XCTestCase {

    /// Dock, Finder, `open`, el inicio de sesión y el actualizador: padre 1.
    func testLanzadaPorElSistemaRegistraElIcono() {
        XCTAssertTrue(IconoBarra.debeRegistrar(padre: 1))
    }

    /// Cualquier otro padre es una terminal, un agente o un depurador: el icono
    /// quedaría apuntado a su nombre. Se prueban valores típicos, no uno solo.
    func testLanzadaPorOtroProgramaNoRegistraElIcono() {
        for padre: pid_t in [0, 2, 42, 18418, 99_999] {
            XCTAssertFalse(IconoBarra.debeRegistrar(padre: padre), "padre \(padre)")
        }
    }

    /// El motivo tiene que decir qué hacer, no solo que no se hizo.
    func testElMotivoDiceComoArreglarlo() {
        let m = IconoBarra.motivoParaNoRegistrar(padre: 18418)
        XCTAssertTrue(m.contains("18418"))
        XCTAssertTrue(m.contains("open"))
    }
}
