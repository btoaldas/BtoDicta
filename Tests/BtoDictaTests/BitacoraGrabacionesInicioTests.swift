import XCTest
@testable import BtoDicta

/// El primer dictado no depende del arranque diferido. Las fuentes físicas
/// permanecen apagadas y el índice vive dentro de un perfil de prueba aislado.
final class BitacoraGrabacionesInicioTests: XCTestCase {
    private let claves = ["continuo_activo", "continuo_solo_grabaciones",
                          "continuo_pantalla_activa", "continuo_sistema_activo",
                          "continuo_carpeta", ModoRapido.clavePausa]
    private var anteriores: [String: Any] = [:]
    private var raiz: URL!

    override func setUpWithError() throws {
        guard let perfil = ProcessInfo.processInfo.environment["BTODICTA_DIR"], !perfil.isEmpty else {
            throw XCTSkip("Requiere BTODICTA_DIR aislado")
        }
        anteriores = Dictionary(uniqueKeysWithValues: claves.map { ($0, Config.json0($0) ?? NSNull()) })
        raiz = URL(fileURLWithPath: perfil).appendingPathComponent("inicio-qa-" + UUID().uuidString)
        ContinuoIndice.shared.cerrar()
        ContinuoCapturaSesion.shared.cerrarGrabacion()
        Config.set("continuo_activo", to: true)
        Config.set("continuo_solo_grabaciones", to: true)
        Config.set("continuo_pantalla_activa", to: false)
        Config.set("continuo_sistema_activo", to: false)
        Config.set("continuo_carpeta", to: raiz.path)
        Config.set(ModoRapido.clavePausa, to: 0)
    }

    override func tearDownWithError() throws {
        guard raiz != nil else { return }
        ContinuoCapturaSesion.shared.cerrarGrabacion()
        ContinuoIndice.shared.cerrar()
        for clave in claves { Config.set(clave, to: anteriores[clave] ?? NSNull()) }
    }

    func testPrimerDictadoAbreIndiceCerradoYSegundoInicioConservaMaterial() throws {
        let audio = raiz.appendingPathComponent("audio-sintetico.pcm")
        XCTAssertNil(ContinuoIndice.shared.registrarAudio(ruta: audio, instante: Date(), duracion: 1),
                     "La condición inicial reproduce el índice cerrado antes del arranque diferido")
        XCTAssertFalse(FileManager.default.fileExists(atPath: raiz.appendingPathComponent("bitacora.sqlite").path))

        let primera = try XCTUnwrap(ContinuoBitacora.iniciarGrabacion())
        try Data([0, 0, 0, 0]).write(to: audio)
        let id = try XCTUnwrap(ContinuoIndice.shared.registrarAudio(ruta: audio, instante: primera.inicio,
            duracion: 1, origen: "sistema", sesion: primera.sesion))
        XCTAssertEqual(ContinuoIndice.shared.pendientes(material: .audio, soloGrabaciones: true).map(\.id), [id])

        ContinuoBitacora.terminarGrabacion()
        let segunda = try XCTUnwrap(ContinuoBitacora.iniciarGrabacion())
        XCTAssertNotEqual(primera.sesion, segunda.sesion)
        let pendientes = ContinuoIndice.shared.pendientes(material: .audio, soloGrabaciones: true)
        XCTAssertEqual(pendientes.map(\.id), [id], "La apertura idempotente conserva el primer registro")
        XCTAssertEqual(pendientes.first?.sesion, primera.sesion)
    }

    func testDictadoSinBitacoraNoCreaIndice() {
        Config.set("continuo_activo", to: false)
        XCTAssertNil(ContinuoBitacora.iniciarGrabacion())
        XCTAssertFalse(FileManager.default.fileExists(atPath: raiz.appendingPathComponent("bitacora.sqlite").path))
    }
}
