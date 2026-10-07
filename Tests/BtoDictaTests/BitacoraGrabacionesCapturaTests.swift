import XCTest
@testable import BtoDicta

/// La adopción usa archivos sintéticos y un índice propio. No solicita audio,
/// permisos, red, modelos ni configuración personal.
final class BitacoraGrabacionesCapturaTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var carpeta: URL!
    private var indice: ContinuoIndice!

    override func setUpWithError() throws {
        carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-adopcion-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        indice = ContinuoIndice()
        indice.abrir(carpeta: carpeta)
    }

    override func tearDown() {
        indice.cerrar()
        // Los fixtures quedan aislados para inspección; ninguna prueba borra
        // archivos del usuario ni depende de una limpieza al terminar.
    }

    private func politica() -> ContinuoCapturaSesion {
        ContinuoCapturaSesion(preferencias: {
            .init(activo: true, soloGrabaciones: true, pausada: false)
        }, reloj: { self.t0 })
    }

    private func fixture(texto: String? = nil) throws -> URL {
        let wav = carpeta.appendingPathComponent(UUID().uuidString + ".wav")
        try Data(repeating: 0x31, count: 32_044).write(to: wav)
        if let texto {
            try texto.write(to: wav.deletingPathExtension().appendingPathExtension("txt"),
                            atomically: true, encoding: .utf8)
        }
        return wav
    }

    private func adoptar(_ wav: URL, sesion: String?, politica: ContinuoCapturaSesion,
                         activa: Bool = true, habilitada: Bool = true,
                         soloGrabaciones: Bool = true, transcripcionCompleta: Bool = true) -> Int64? {
        ContinuoAudio.adoptar(wav: wav, instante: t0, sesion: sesion, indice: indice,
            politica: politica, ajustes: .init(activa: activa, adoptarDictado: habilitada,
                                               soloGrabaciones: soloGrabaciones),
            transcripcionCompleta: transcripcionCompleta)
    }

    func testSesionCerradaAdoptaSuTextoSinReabrirCaptura() throws {
        let politica = politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        politica.cerrarGrabacion()
        let segunda = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        XCTAssertNotEqual(sesion, segunda)
        let texto = "Texto existente de una grabación de prueba."
        let wav = try fixture(texto: texto)
        let audioOriginal = try Data(contentsOf: wav)
        let txt = wav.deletingPathExtension().appendingPathExtension("txt")
        let textoOriginal = try Data(contentsOf: txt)

        XCTAssertNotNil(adoptar(wav, sesion: sesion, politica: politica))
        XCTAssertTrue(indice.pendientes(material: .audio).isEmpty,
                      "el dictado ya transcrito no entra en otra tanda STT")
        XCTAssertEqual(indice.materialEntre(desde: t0, hasta: t0.addingTimeInterval(1),
                                            incluirPantalla: false).map(\.texto), [texto])
        XCTAssertEqual(try Data(contentsOf: wav), audioOriginal)
        XCTAssertEqual(try Data(contentsOf: txt), textoOriginal)
        XCTAssertEqual(politica.contextoActual()?.sesion, segunda,
                       "incorporar el resultado viejo no cambia la captura actual")
    }

    func testTranscripcionAusenteConservaPendienteYSesion() throws {
        let politica = politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        politica.cerrarGrabacion()
        let wav = try fixture()
        let original = try Data(contentsOf: wav)

        XCTAssertNotNil(adoptar(wav, sesion: sesion, politica: politica))
        let pendientes = indice.pendientes(material: .audio, soloGrabaciones: true)
        XCTAssertEqual(pendientes.count, 1)
        XCTAssertEqual(pendientes.first?.sesion, sesion)
        XCTAssertEqual(pendientes.first?.ruta, wav)
        XCTAssertEqual(try Data(contentsOf: wav), original)
        XCTAssertNil(politica.contextoActual())
    }

    func testTextoVacioNoMarcaProcesado() throws {
        let politica = politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        let wav = try fixture(texto: " \n\t ")
        XCTAssertNotNil(adoptar(wav, sesion: sesion, politica: politica))
        XCTAssertEqual(indice.pendientes(material: .audio).count, 1)
    }

    func testFalloFinalConTextoParcialConservaPendiente() throws {
        let politica = self.politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        politica.cerrarGrabacion()
        let wav = try fixture(texto: "Texto parcial previo al fallo final.")
        let txt = wav.deletingPathExtension().appendingPathExtension("txt")
        let original = try Data(contentsOf: txt)
        XCTAssertNotNil(adoptar(wav, sesion: sesion, politica: politica, transcripcionCompleta: false))
        XCTAssertEqual(indice.pendientes(material: .audio).count, 1)
        XCTAssertTrue(indice.materialEntre(desde: t0, hasta: t0.addingTimeInterval(1),
                                           incluirPantalla: false).isEmpty)
        XCTAssertEqual(try Data(contentsOf: txt), original)
    }

    func testSinSesionOConSesionDesconocidaNoIncorporaAudio() throws {
        let politica = politica()
        let wav = try fixture(texto: "Texto de prueba.")
        XCTAssertNil(adoptar(wav, sesion: nil, politica: politica))
        XCTAssertNil(adoptar(wav, sesion: "sesion-desconocida", politica: politica))
        XCTAssertEqual(indice.resumen().audio, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path))
    }

    func testMaestroYFuenteApagadosNoAdoptan() throws {
        let politica = politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        let wav = try fixture(texto: "Texto de prueba.")
        XCTAssertNil(adoptar(wav, sesion: sesion, politica: politica, activa: false))
        XCTAssertNil(adoptar(wav, sesion: sesion, politica: politica, habilitada: false))
        XCTAssertEqual(indice.resumen().audio, 0)
    }

    func testContinuoConservaAdopcionLegacySinSesion() throws {
        let politica = politica()
        let wav = try fixture(texto: "Texto del modo continuo.")
        XCTAssertNotNil(adoptar(wav, sesion: nil, politica: politica, soloGrabaciones: false))
        XCTAssertEqual(indice.resumen().audio, 1)
        XCTAssertTrue(indice.pendientes(material: .audio).isEmpty)
    }

    func testPausaImpideAdoptarWavCompletoInclusoEnContinuo() throws {
        let politica = politica()
        let sesion = try XCTUnwrap(politica.iniciarGrabacion()?.sesion)
        politica.suspenderCaptura()
        let wav = try fixture(texto: "Texto de una sesión interrumpida.")
        XCTAssertNil(adoptar(wav, sesion: sesion, politica: politica))
        XCTAssertNil(adoptar(wav, sesion: sesion, politica: politica, soloGrabaciones: false))
        XCTAssertEqual(indice.resumen().audio, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path))
    }
}
