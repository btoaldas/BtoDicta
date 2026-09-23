import XCTest
@testable import BtoDicta

/// fn fn fn pone o quita el modo reunión (spec 012, T03).
final class TriplePulsacionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let ventana = 0.45

    /// Solo se arma tras la segunda que arrancó, en modo toque y sin otra tecla.
    func testSeArmaSoloTrasUnDobleQueArranco() {
        XCTAssertTrue(TriplePulsacionPolicy.armarAlSoltar(activoPorDoble: true, usadoConTecla: false, pushToTalk: false))
        XCTAssertFalse(TriplePulsacionPolicy.armarAlSoltar(activoPorDoble: false, usadoConTecla: false, pushToTalk: false))
        XCTAssertFalse(TriplePulsacionPolicy.armarAlSoltar(activoPorDoble: true, usadoConTecla: true, pushToTalk: false))
        XCTAssertFalse(TriplePulsacionPolicy.armarAlSoltar(activoPorDoble: true, usadoConTecla: false, pushToTalk: true))
    }

    /// RF-03 y RF-05: dentro de la ventana es triple; fuera, no; y no dura.
    func testDentroDeLaVentanaEsTriple() {
        var tercera = DoublePressGate()
        tercera.armar(en: t0)
        XCTAssertTrue(tercera.consumirSiCorresponde(en: t0.addingTimeInterval(0.2), ventana: ventana))
        XCTAssertFalse(tercera.consumirSiCorresponde(en: t0.addingTimeInterval(0.3), ventana: ventana),
                       "consumida: la cuarta no es otra triple")
        tercera.armar(en: t0)
        XCTAssertFalse(tercera.consumirSiCorresponde(en: t0.addingTimeInterval(0.46), ventana: ventana),
                       "tardía: detiene, como siempre")
        XCTAssertFalse(tercera.armada, "la marca vencida se limpia")
    }

    /// RF-04: la segunda arranca al bajar sin mirar la tercera. Se recorre fn fn fn
    /// con las mismas dos compuertas y en el mismo orden que el monitor de fn.
    func testElDobleNoEsperaALaTercera() {
        var doble = DoublePressGate(), tercera = DoublePressGate()
        var arrancoEn: Date?
        // 1: baja y suelta → arma el doble.
        doble.armar(en: t0.addingTimeInterval(0.08))
        // 2: baja → el doble arranca AHÍ. La tercera no está armada todavía.
        let bajaSegunda = t0.addingTimeInterval(0.20)
        XCTAssertFalse(tercera.armada)
        if doble.consumirSiCorresponde(en: bajaSegunda, ventana: ventana) { arrancoEn = bajaSegunda }
        XCTAssertEqual(arrancoEn, bajaSegunda, "arranca en la bajada de la segunda: 0 ms añadidos")
        // 2: suelta → se arma la tercera.
        if TriplePulsacionPolicy.armarAlSoltar(activoPorDoble: true, usadoConTecla: false, pushToTalk: false) {
            tercera.armar(en: t0.addingTimeInterval(0.28))
        }
        // 3: baja → triple.
        XCTAssertTrue(tercera.consumirSiCorresponde(en: t0.addingTimeInterval(0.40), ventana: ventana))
    }
}
