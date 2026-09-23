import XCTest
@testable import BtoDicta

/// La pausa de la bitácora (spec 010, T02).
///
/// Todas las pruebas trabajan sobre la parte pura, con el reloj como parámetro:
/// media hora, un reinicio o una suspensión de dos horas se prueban en
/// milisegundos. Ninguna toca la configuración real — la variante que escribe
/// iría al `config.json` de quien corra la suite.
final class ModoRapidoTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func min(_ m: Double) -> TimeInterval { m * 60 }

    /// Guarda y recupera, como haría la aplicación al cerrarse y abrirse.
    private func ciclo(hasta: Date, guardadoEn: Date, cargadoEn: Date) -> Date? {
        let guardado = ModoRapido.aGuardar(hasta: hasta, ahora: guardadoEn)
        return ModoRapido.alCargar(guardado, ahora: cargadoEn)
    }

    func testVenceASuHora() {
        let h = ModoRapido.hasta(minutos: 30, desde: t0)
        XCTAssertTrue(ModoRapido.vigente(hasta: h, ahora: t0.addingTimeInterval(min(29))))
        XCTAssertFalse(ModoRapido.vigente(hasta: h, ahora: t0.addingTimeInterval(min(30))))
    }

    func testNoVenceAntes() {
        let h = ModoRapido.hasta(minutos: 60, desde: t0)
        for m in stride(from: 0.0, to: 60, by: 7) {
            XCTAssertTrue(ModoRapido.vigente(hasta: h, ahora: t0.addingTimeInterval(min(m))),
                          "a los \(m) min de una pausa de 60 debería seguir vigente")
        }
    }

    func testSinPausaNoHayNadaVigente() {
        XCTAssertFalse(ModoRapido.vigente(hasta: nil, ahora: t0))
        XCTAssertNil(ModoRapido.alCargar(0.0, ahora: t0), "0 es «sin pausa»")
        XCTAssertNil(ModoRapido.alCargar(nil, ahora: t0))
        XCTAssertNil(ModoRapido.alCargar("basura", ahora: t0))
    }

    /// **El caso que justifica guardar un instante (D-1).**
    ///
    /// Pausa de una hora a las t0. A los diez minutos la aplicación se cierra, y
    /// vuelve a abrirse treinta minutos después. Le quedan veinte minutos, no
    /// cincuenta: la pausa es de reloj, no de aplicación abierta.
    ///
    /// Con una cuenta atrás —guardar «me quedan 50» y sumarlos al cargar— la
    /// pausa se alargaría treinta minutos por el mero hecho de haber cerrado.
    func testTrasUnReinicioLeQuedaElTiempoDeReloj() {
        let h = ModoRapido.hasta(minutos: 60, desde: t0)
        let recuperado = ciclo(hasta: h, guardadoEn: t0.addingTimeInterval(min(10)),
                               cargadoEn: t0.addingTimeInterval(min(40)))
        XCTAssertNotNil(recuperado)
        let quedan = recuperado!.timeIntervalSince(t0.addingTimeInterval(min(40))) / 60
        XCTAssertEqual(quedan, 20, accuracy: 0.01,
                       "tras cerrar treinta minutos, a una pausa de una hora le quedan veinte")
    }

    /// Suspender el equipo dos horas durante una pausa de media hora: al
    /// despertar ya venció. Sin tratamiento especial: se compara contra el reloj.
    func testTrasUnaSuspensionLargaYaVencio() {
        let h = ModoRapido.hasta(minutos: 30, desde: t0)
        let recuperado = ciclo(hasta: h, guardadoEn: t0, cargadoEn: t0.addingTimeInterval(min(120)))
        XCTAssertFalse(ModoRapido.vigente(hasta: recuperado, ahora: t0.addingTimeInterval(min(120))))
    }

    /// Pausar estando pausada sustituye el plazo. Quien elige «30 min» a las diez,
    /// y luego «15 min» a las diez y cinco, quiere volver a las diez y veinte.
    func testPausarEstandoPausadaSustituyeElPlazo() {
        _ = ModoRapido.hasta(minutos: 30, desde: t0)
        let segunda = ModoRapido.hasta(minutos: 15, desde: t0.addingTimeInterval(min(5)))
        XCTAssertEqual(segunda.timeIntervalSince(t0) / 60, 20, accuracy: 0.01)
    }

    /// «Hasta mañana» es mañana a las ocho, no dentro de veinticuatro horas.
    func testHastaMananaEsManana() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Guayaquil")!
        let noche = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 23, minute: 10))!
        let vuelta = ModoRapido.hastaManana(desde: noche, calendario: cal)
        let c = cal.dateComponents([.day, .hour, .minute], from: vuelta)
        XCTAssertEqual(c.day, 23)
        XCTAssertEqual(c.hour, 8)
        XCTAssertEqual(c.minute, 0)
    }

    // MARK: Lo que enseña el menú durante un dictado largo (RF-07)

    /// A 16 kHz, mono y 16 bits el dictado ocupa 32 000 bytes por segundo. Se
    /// comprueba con esa cifra y no con números al azar: así la prueba dice
    /// también cuánto pesa de verdad una sesión larga.
    private let porSegundo = 32_000

    func testDiezMinutos() {
        XCTAssertEqual(ModoRapido.textoGrabacion(segundos: 600, bytes: 600 * porSegundo, reunion: false),
                       "● Grabando 10:00 · 18,3 MB por transcribir")
    }

    func testTresHorasEnModoReunion() {
        XCTAssertEqual(ModoRapido.textoGrabacion(segundos: 3 * 3600 + 125, bytes: (3 * 3600 + 125) * porSegundo,
                                                 reunion: true),
                       "● Grabando 3:02:05 · 333,4 MB por transcribir · modo reunión")
    }

    /// Veinte horas: lo que se pidió que fuera posible. Unos 2,1 GB que se
    /// transcriben de golpe al soltar, mientras no exista la spec 011.
    func testVeinteHoras() {
        let s = 20 * 3600
        let t = ModoRapido.textoGrabacion(segundos: s, bytes: s * porSegundo, reunion: true)
        XCTAssertTrue(t.hasPrefix("● Grabando 20:00:00 · 2.197,3 MB"), t)
    }

    func testValoresRarosNoRompenElTexto() {
        XCTAssertEqual(ModoRapido.textoGrabacion(segundos: -5, bytes: -1, reunion: false),
                       "● Grabando 0:00 · 0,0 MB por transcribir")
    }

    /// Solo esas dos claves: es lo que el QA excluye al comprobar que no se tocan
    /// los ajustes del usuario.
    func testSoloDosClavesDeEstado() {
        XCTAssertEqual(ModoRapido.clavesDeEstado, ["modo_reunion", "bitacora_pausada_hasta"])
    }
}
