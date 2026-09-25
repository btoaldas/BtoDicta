import XCTest
@testable import BtoDicta

/// La bitácora no puede volver a pedir el micrófono en ráfaga tras un fallo.
final class EsperaMicrofonoTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    func en(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// La espera crece: 2,5, 5, 10, 20, 40, 60 s; al séptimo fallo, enfría 60 s.
    func testEsperaCrecienteYEnfriamiento() {
        var e = EsperaMicrofono()
        let esperas = (1...6).map { _ -> TimeInterval in
            guard case .reintentar(_, let s) = e.fallo(en: t0) else { XCTFail(); return -1 }
            return s
        }
        XCTAssertEqual(esperas, [2.5, 5, 10, 20, 40, 60])
        XCTAssertEqual(e.fallo(en: t0), .enfriar(tras: 7, durante: 60))
        XCTAssertTrue(e.enfriando)
    }

    /// El fallo del 2026-09-23: con un reintento programado, los pedidos por
    /// cambio de estado NO arrancan otra vez. Cien pedidos en 2 s, cero arranques.
    func testConReintentoProgramadoLosPedidosSeDescartan() {
        var e = EsperaMicrofono()
        _ = e.fallo(en: t0)                          // reintento en 2,5 s
        let arranques = stride(from: 0.0, to: 2.4, by: 0.024)
            .filter { e.pedido(en: en($0)) == .arrancar }.count
        XCTAssertEqual(arranques, 0)
        XCTAssertEqual(e.pedido(en: en(1)), .descartar)
        // Vencida la espera pero sin haber corrido el reintento: sigue siendo
        // suyo. Visto en la prueba: el pedido se colaba un instante antes.
        XCTAssertEqual(e.pedido(en: en(2.6)), .descartar)
        e.reintentoLlega()
        XCTAssertEqual(e.pedido(en: en(2.6)), .arrancar, "corrido el reintento, un pedido nuevo puede")
    }

    /// Rendida, un pedido no se pierde: se aplaza al final del enfriamiento.
    func testEnfriandoSeAplaza() {
        var e = EsperaMicrofono()
        for _ in 1...7 { _ = e.fallo(en: t0) }
        XCTAssertFalse(e.reintentoPendiente, "rendida no hay reintento en camino")
        XCTAssertEqual(e.pedido(en: en(10)), .aplazar(50))
        XCTAssertEqual(e.pedido(en: en(60)), .arrancar)
    }

    /// Audio de verdad, o el dictado tomó el micrófono: el siguiente pedido entra.
    /// Si no, al terminar un dictado la bitácora no volvería hasta la espera.
    func testReiniciarDejaPasar() {
        var e = EsperaMicrofono()
        for _ in 1...3 { _ = e.fallo(en: t0) }
        XCTAssertEqual(e.pedido(en: en(1)), .descartar)
        e.reiniciar()
        XCTAssertEqual(e.pedido(en: en(1)), .arrancar)
        XCTAssertEqual(e.intentos, 0)
        guard case .reintentar(1, 2.5) = e.fallo(en: en(2)) else { return XCTFail("vuelve a empezar desde el primero") }
    }

    /// Sin fallos, nunca estorba.
    func testSinFallosSiempreArranca() {
        let e = EsperaMicrofono()
        XCTAssertEqual(e.pedido(en: t0), .arrancar)
    }
}

/// Un corte de red de ESTE equipo no aparta al proveedor de pulido (2026-09-24).
final class CuarentenaSinRedTests: XCTestCase {

    /// Lo que pasó a las 07:53: el equipo sin red, y el proveedor preferido
    /// apartado 60, 300 y 900 s por fallos que no eran suyos.
    func testSinRedLocalNoSeApartaAlProveedor() {
        CuarentenaPulido.reiniciarContadores()
        let c = CuarentenaPulido()
        let id = "prueba-sin-red|x|m|h"
        for _ in 1...3 {
            let s = c.registrar(id, local: false, codigo: -1, cuerpo: "",
                                error: URLError(.networkConnectionLost), redLocal: false)
            XCTAssertEqual(s, 0)
        }
        XCTAssertEqual(CuarentenaPulido.fallosSeguidos(id), 0, "la cuenta no sube")
        XCTAssertFalse(c.activa(id, local: false, ahora: Date().addingTimeInterval(20)),
                       "pasado el salto breve de la nube, el proveedor está disponible")
    }

    /// Con red, un proveedor que corta la conexión sí se aparta, y sube.
    func testConRedElFalloSiEsDelProveedor() {
        CuarentenaPulido.reiniciarContadores()
        let c = CuarentenaPulido()
        let id = "prueba-con-red|x|m|h"
        let a = c.registrar(id, local: false, codigo: -1, cuerpo: "", error: URLError(.networkConnectionLost), redLocal: true)
        let b = c.registrar(id, local: false, codigo: -1, cuerpo: "", error: URLError(.networkConnectionLost), redLocal: true)
        XCTAssertEqual([a, b], [60, 300])
    }

    /// Un 429 sin red no existe; un HTTP con respuesta no depende de la red local.
    func testRespuestaHTTPNoSeConfundeConFaltaDeRed() {
        CuarentenaPulido.reiniciarContadores()
        let c = CuarentenaPulido()
        let s = c.registrar("prueba-429|x|m|h", local: false, codigo: 429,
                            cuerpo: "insufficient_quota", error: nil, redLocal: false)
        XCTAssertEqual(s, 1800)
    }
}
