import XCTest
@testable import BtoDicta

/// Integra el escritor real, la política compartida y SQLite con audio
/// sintético. Exige perfil aislado antes de tocar cualquier configuración.
final class BitacoraGrabacionesHistorialTests: XCTestCase {
    func testFinalizacionTardiaConservaAudioYTextoSinOtraTranscripcion() throws {
        guard let perfil = ProcessInfo.processInfo.environment["BTODICTA_DIR"], !perfil.isEmpty else {
            throw XCTSkip("Requiere BTODICTA_DIR aislado")
        }
        let raiz = URL(fileURLWithPath: perfil).appendingPathComponent("historial-qa-" + UUID().uuidString)
        Config.set("continuo_activo", to: true)
        Config.set("continuo_solo_grabaciones", to: true)
        Config.set("continuo_audio_adoptar_dictado", to: true)
        Config.set("continuo_carpeta", to: raiz.path)
        ContinuoIndice.shared.abrir()
        defer {
            ContinuoCapturaSesion.shared.cerrarGrabacion()
            ContinuoIndice.shared.cerrar()
            Config.set("continuo_activo", to: false)
        }

        let escritor = HistoryWriter()
        let inicial = try XCTUnwrap(ContinuoCapturaSesion.shared.iniciarGrabacion())
        escritor.autorizarBitacora(inicial)
        ContinuoCapturaSesion.shared.cerrarGrabacion()
        let siguiente = try XCTUnwrap(ContinuoCapturaSesion.shared.iniciarGrabacion())
        XCTAssertNotEqual(inicial.sesion, siguiente.sesion)
        let audio = HistoryWriter.wavData(pcm: Data(repeating: 0, count: 32_000))
        let texto = "Transcripción sintética ya completada."
        escritor.finish(wav: audio, finalText: texto)

        XCTAssertEqual(try Data(contentsOf: escritor.wavURL), audio)
        XCTAssertEqual(try String(contentsOf: escritor.txtURL, encoding: .utf8), texto)
        XCTAssertTrue(ContinuoIndice.shared.pendientes(material: .audio, soloGrabaciones: true).isEmpty,
                      "El dictado con texto no vuelve a STT")
        let piezas = ContinuoIndice.shared.materialEntre(desde: inicial.inicio.addingTimeInterval(-1),
                                                        hasta: Date().addingTimeInterval(1), incluirPantalla: true)
        XCTAssertEqual(piezas.map(\.texto), [texto])
        XCTAssertEqual(piezas.first?.instante.timeIntervalSince1970 ?? 0,
                       inicial.inicio.timeIntervalSince1970, accuracy: 0.001)
    }
}
