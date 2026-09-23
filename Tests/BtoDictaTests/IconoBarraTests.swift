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

/// ¿Se ve el icono? Por su posición (spec 012, T01). Geometría medida en el equipo
/// de desarrollo el 2026-09-22: pantalla 1512 × 982, barra de y = 949 a 982,
/// muesca de x = 663 a 848.
final class VisibilidadIconoTests: XCTestCase {

    let portatil = PantallaBarra(
        marco: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visible: CGRect(x: 0, y: 55, width: 1512, height: 894),
        muescaIzquierda: CGRect(x: 0, y: 950, width: 663, height: 32),
        muescaDerecha: CGRect(x: 848, y: 950, width: 664, height: 32))

    /// El icono de BtoDicta, visible, estaba en x = 1152, 24 × 33.
    func testEnLaBarraSeVe() {
        let v = IconoBarra.visibilidad(ventana: CGRect(x: 1152, y: 949, width: 24, height: 33),
                                       pantallas: [portatil])
        XCTAssertEqual(v, .visible)
    }

    /// El escondido que se midió (spec 011): (2, 981) contado desde arriba, es
    /// decir, en el borde inferior. Sea cual sea su alto, no está en la barra.
    func testEnElBordeInferiorNoSeVe() {
        for alto: CGFloat in [1, 22, 33] {
            let v = IconoBarra.visibilidad(ventana: CGRect(x: 2, y: 982 - 981 - alto, width: 24, height: alto),
                                           pantallas: [portatil])
            guard case .oculto = v else { return XCTFail("alto \(alto): \(v)") }
        }
    }

    func testEnMitadDeLaPantallaNoSeVe() {
        let v = IconoBarra.visibilidad(ventana: CGRect(x: 600, y: 500, width: 24, height: 33), pantallas: [portatil])
        guard case .oculto(let m) = v else { return XCTFail("\(v)") }
        XCTAssertTrue(m.contains("fuera de la barra"), m)
    }

    func testFueraDeTodaPantallaNoSeVe() {
        let v = IconoBarra.visibilidad(ventana: CGRect(x: -500, y: 2000, width: 24, height: 33), pantallas: [portatil])
        guard case .oculto(let m) = v else { return XCTFail("\(v)") }
        XCTAssertTrue(m.contains("fuera de toda pantalla"), m)
    }

    func testSinVentanaNoSeVe() {
        XCTAssertEqual(IconoBarra.visibilidad(ventana: nil, pantallas: [portatil]), .oculto("sin ventana"))
        XCTAssertEqual(IconoBarra.visibilidad(ventana: .zero, pantallas: [portatil]), .oculto("sin ventana"))
    }

    /// «Cuando está bajo la muesca significa que está mal.»
    func testBajoLaMuescaNoSeVe() {
        let v = IconoBarra.visibilidad(ventana: CGRect(x: 700, y: 949, width: 24, height: 33), pantallas: [portatil])
        guard case .oculto(let m) = v else { return XCTFail("\(v)") }
        XCTAssertTrue(m.contains("muesca"), m)
        // Justo a los lados de la muesca, sí se ve.
        XCTAssertEqual(IconoBarra.visibilidad(ventana: CGRect(x: 630, y: 949, width: 24, height: 33),
                                              pantallas: [portatil]), .visible)
        XCTAssertEqual(IconoBarra.visibilidad(ventana: CGRect(x: 850, y: 949, width: 24, height: 33),
                                              pantallas: [portatil]), .visible)
    }

    /// RF-02 / RNF-03: con la barra fuera de pantalla no se sabe, nunca «oculto».
    func testConLaBarraEscondidaNoSeSabe() {
        for ventana in [CGRect(x: 1152, y: 949, width: 24, height: 33), CGRect(x: 2, y: -21, width: 24, height: 22), nil] {
            let v = IconoBarra.visibilidad(ventana: ventana, pantallas: [portatil], barraEnPantalla: false)
            guard case .noSeSabe = v else { return XCTFail("\(String(describing: ventana)): \(v)") }
        }
    }

    /// Barra que se oculta sola: la parte útil llega al borde superior.
    func testBarraQueSeOcultaSolaNoSeSabe() {
        var p = portatil
        p.visible = CGRect(x: 0, y: 55, width: 1512, height: 927)
        let v = IconoBarra.visibilidad(ventana: CGRect(x: 1152, y: 949, width: 24, height: 33), pantallas: [p])
        guard case .noSeSabe = v else { return XCTFail("\(v)") }
    }

    /// Segunda pantalla sin muesca, a la derecha; y una con las zonas de la muesca
    /// en coordenadas propias, que hay que desplazar.
    func testSegundaPantalla() {
        let externa = PantallaBarra(marco: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                                    visible: CGRect(x: 1512, y: 0, width: 1920, height: 1055))
        XCTAssertEqual(IconoBarra.visibilidad(ventana: CGRect(x: 3000, y: 1055, width: 24, height: 25),
                                              pantallas: [portatil, externa]), .visible)
        let conMuescaLocal = PantallaBarra(marco: CGRect(x: 1512, y: 0, width: 1512, height: 982),
                                           visible: CGRect(x: 1512, y: 0, width: 1512, height: 949),
                                           muescaIzquierda: CGRect(x: 0, y: 950, width: 663, height: 32),
                                           muescaDerecha: CGRect(x: 848, y: 950, width: 664, height: 32))
        let v = IconoBarra.visibilidad(ventana: CGRect(x: 1512 + 700, y: 949, width: 24, height: 33),
                                       pantallas: [portatil, conMuescaLocal])
        guard case .oculto = v else { return XCTFail("\(v)") }
    }
}

/// Cuándo avisar y cuándo recordar (spec 012, T02).
final class VigiaIconoOcultoTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let oculto = VisibilidadIcono.oculto("prueba")
    func en(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// RF-01: avisa tras la gracia, y una sola vez.
    func testAvisaTrasLaGraciaYUnaVez() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(0)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(29)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(30)), [.avisar])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(32)), [])
        // Aunque se vea y se vuelva a esconder: uno por sesión.
        XCTAssertEqual(v.observar(.visible, reunion: false, noVolverAAvisar: false, en: en(40)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(50)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(200)), [])
    }

    /// Un instante oculto y de vuelta no avisa: hace falta la gracia seguida.
    func testUnInstanteNoAvisa() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        _ = v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(0))
        _ = v.observar(.visible, reunion: false, noVolverAAvisar: false, en: en(20))
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(35)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(64)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(65)), [.avisar])
    }

    func testNoVolverAAvisar() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        for s in stride(from: 0.0, through: 600, by: 2) {
            XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: true, en: en(s)), [])
        }
    }

    /// RF-02: lo que no se sabe no avisa, y tampoco borra lo que ya se sabía.
    func testLoQueNoSeSabeNiAvisaNiReinicia() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        _ = v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(0))
        XCTAssertEqual(v.observar(.noSeSabe("pantalla completa"), reunion: false, noVolverAAvisar: false, en: en(40)), [])
        XCTAssertEqual(v.observar(.noSeSabe("pantalla completa"), reunion: false, noVolverAAvisar: false, en: en(400)), [])
        XCTAssertEqual(v.observar(oculto, reunion: false, noVolverAAvisar: false, en: en(402)), [.avisar])
        // Y solo con «no se sabe», nunca.
        var w = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        for s in stride(from: 0.0, through: 600, by: 2) {
            XCTAssertEqual(w.observar(.noSeSabe("x"), reunion: true, noVolverAAvisar: false, en: en(s)), [])
        }
    }

    /// RF-06: con la reunión puesta y el icono oculto, un recordatorio por intervalo.
    func testRecordatorioConReunion() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 1800)
        _ = v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(0))
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(30)), [.avisar])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(30 + 1799)), [])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(30 + 1800)), [.recordar])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(30 + 3599)), [])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: false, en: en(30 + 3600)), [.recordar])
    }

    /// «No volver a avisar» es del aviso; el recordatorio de la reunión sigue.
    func testRecordatorioAunqueNoSeAvise() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 60)
        _ = v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(0))
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(30)), [])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(90)), [.recordar])
    }

    func testSinReunionOVisibleOApagadoNoRecuerda() {
        var sin = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 60)
        var visible = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 60)
        var apagado = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 0)
        for s in stride(from: 0.0, through: 900, by: 2) {
            XCTAssertFalse(sin.observar(oculto, reunion: false, noVolverAAvisar: true, en: en(s)).contains(.recordar))
            XCTAssertEqual(visible.observar(.visible, reunion: true, noVolverAAvisar: false, en: en(s)), [])
            XCTAssertFalse(apagado.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(s)).contains(.recordar))
        }
    }

    /// Poner la reunión más tarde: el primero, un intervalo después.
    func testReunionPuestaMasTarde() {
        var v = VigiaIconoOculto(gracia: 30, intervaloRecordatorio: 60)
        _ = v.observar(oculto, reunion: false, noVolverAAvisar: true, en: en(0))
        _ = v.observar(oculto, reunion: false, noVolverAAvisar: true, en: en(500))
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(502)), [])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(561)), [])
        XCTAssertEqual(v.observar(oculto, reunion: true, noVolverAAvisar: true, en: en(562)), [.recordar])
    }
}
