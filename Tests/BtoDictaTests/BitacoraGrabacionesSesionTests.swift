import XCTest
@testable import BtoDicta

final class BitacoraGrabacionesSesionTests: XCTestCase {
    private final class Entorno {
        var ahora = Date(timeIntervalSince1970: 1_800_000_000)
        var p = ContinuoCapturaSesion.Preferencias(activo: true, soloGrabaciones: true, pausada: false)
        lazy var politica = ContinuoCapturaSesion(preferencias: { self.p }, reloj: { self.ahora })
    }

    func testReposoCierraTodasLasVentanasYNoAceptaMaterialSinSesion() {
        let e = Entorno()
        XCTAssertNil(e.politica.contextoActual())
        e.ahora.addTimeInterval(60)
        XCTAssertNil(e.politica.contextoActual())
        XCTAssertFalse(e.politica.admiteMaterial(sesion: nil, instante: e.ahora))
        XCTAssertFalse(e.politica.sesionAutorizada("inventada"))
    }

    func testCierreInvalidaCallbacksPeroConservaProcedenciaDelDictado() throws {
        let e = Entorno()
        let c = try XCTUnwrap(e.politica.iniciarGrabacion())
        let sesion = try XCTUnwrap(c.sesion)
        e.ahora.addTimeInterval(0.1)
        let capturada = e.ahora
        XCTAssertTrue(e.politica.vigente(c))
        e.politica.cerrarGrabacion()
        e.ahora.addTimeInterval(1)
        XCTAssertFalse(e.politica.vigente(c))
        XCTAssertNil(e.politica.contextoActual())
        XCTAssertTrue(e.politica.sesionAutorizada(sesion))
        XCTAssertTrue(e.politica.admiteMaterial(sesion: sesion, instante: capturada))
        XCTAssertFalse(e.politica.admiteMaterial(sesion: sesion, instante: e.ahora))
        XCTAssertFalse(e.politica.admiteMaterial(sesion: sesion, instante: c.inicio.addingTimeInterval(-0.001)))
    }

    func testDosDictadosConsecutivosNoAutorizanCallbacksCruzados() throws {
        let e = Entorno()
        let a = try XCTUnwrap(e.politica.iniciarGrabacion())
        e.ahora.addTimeInterval(0.01)
        e.politica.cerrarGrabacion()
        e.ahora.addTimeInterval(0.01)
        let b = try XCTUnwrap(e.politica.iniciarGrabacion())
        XCTAssertNotEqual(a.sesion, b.sesion)
        XCTAssertNotEqual(a.generacion, b.generacion)
        XCTAssertFalse(e.politica.vigente(a))
        XCTAssertTrue(e.politica.vigente(b))
        XCTAssertFalse(e.politica.admiteMaterial(sesion: a.sesion, instante: b.inicio))
        XCTAssertTrue(e.politica.admiteMaterial(sesion: a.sesion, instante: a.inicio))
    }

    func testPausaYCambioDeAjustesReabrenSoloSiElGrabadorSigueActivo() throws {
        let e = Entorno()
        let a = try XCTUnwrap(e.politica.iniciarGrabacion())
        e.p.pausada = true
        e.politica.suspenderCaptura()
        XCTAssertNil(e.politica.contextoActual())
        e.politica.reanudarCapturaSiGrabando()
        XCTAssertNil(e.politica.contextoActual())
        e.ahora.addTimeInterval(5)
        e.p.pausada = false
        e.politica.reanudarCapturaSiGrabando()
        let b = try XCTUnwrap(e.politica.contextoActual())
        XCTAssertNotEqual(a.sesion, b.sesion)
        XCTAssertFalse(e.politica.vigente(a))
        XCTAssertFalse(e.politica.sesionAutorizada(try XCTUnwrap(a.sesion)),
                       "El audio completo atraviesa una pausa; permanece solo en historial")
        XCTAssertTrue(e.politica.admiteMaterial(sesion: a.sesion, instante: a.inicio),
                      "La captura anterior a la pausa conserva autorización")
        e.politica.cerrarGrabacion()
        e.politica.reanudarCapturaSiGrabando()
        XCTAssertNil(e.politica.contextoActual())
    }

    func testMaestroApagadoNoSeEnciendeAlDictarYNuevaInstanciaNoRecuperaVentanas() throws {
        let e = Entorno()
        e.p.activo = false
        XCTAssertNil(e.politica.iniciarGrabacion())
        XCTAssertNil(e.politica.contextoActual())
        e.p.activo = true
        e.politica.reanudarCapturaSiGrabando()
        let c = try XCTUnwrap(e.politica.contextoActual())
        let reinicio = ContinuoCapturaSesion(preferencias: { e.p }, reloj: { e.ahora })
        XCTAssertNil(reinicio.contextoActual())
        XCTAssertFalse(reinicio.sesionAutorizada(try XCTUnwrap(c.sesion)))
    }

    func testContinuoEsExplicitoYUnCambioInvalidaSuGeneracion() throws {
        let e = Entorno()
        e.p.soloGrabaciones = false
        let c = try XCTUnwrap(e.politica.contextoActual())
        XCTAssertNil(c.sesion)
        XCTAssertTrue(e.politica.admiteMaterial(sesion: nil, instante: e.ahora))
        e.p.soloGrabaciones = true
        e.politica.suspenderCaptura()
        XCTAssertFalse(e.politica.vigente(c))
        XCTAssertNil(e.politica.contextoActual())
        e.p.soloGrabaciones = false
        XCTAssertNotEqual(e.politica.contextoActual()?.generacion, c.generacion)
        XCTAssertFalse(e.politica.admiteMaterial(sesion: nil, instante: e.ahora.addingTimeInterval(1)))
    }

    func testGuardiaDeFailoverYPorteroDeniegaSinLeerAudioNiInvocarMotores() {
        var completada = false
        Failover.transcribe(wav: .archivo(URL(fileURLWithPath: "/audio-inexistente")),
                            cadena: [], permitirSolicitud: { false }) { resultado in
            if case .failure = resultado { completada = true }
        }
        XCTAssertTrue(completada)
        XCTAssertEqual(PorteroVoz.hayVoz(en: URL(fileURLWithPath: "/audio-inexistente"),
                                        motores: ["apple_speech"], permitirSolicitud: { false }), .noSePudo)
    }
}
