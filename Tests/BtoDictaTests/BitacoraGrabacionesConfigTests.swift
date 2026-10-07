import XCTest
@testable import BtoDicta

/// Fixtures neutras: no se consulta ni se modifica la configuración instalada.
final class BitacoraGrabacionesConfigTests: XCTestCase {
    private func reiniciar(_ preferencias: [String: Any]) throws -> [String: Any] {
        let datos = try JSONSerialization.data(withJSONObject: preferencias, options: [.sortedKeys])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: datos) as? [String: Any])
    }

    func testInstalacionNuevaAdoptaSoloGrabacionesSinActivarMaestro() {
        let nueva: [String: Any] = [:]
        XCTAssertTrue(Config.continuoSoloGrabaciones(en: nueva))
        XCTAssertNil(nueva["continuo_activo"])
        XCTAssertNil(nueva["continuo_solo_grabaciones"])
    }

    func testActualizarConservaAmbosValoresDelMaestroSinReescribir() throws {
        for maestro in [false, true] {
            let anterior: [String: Any] = ["continuo_activo": maestro, "continuo_audio_modo": "dictado"]
            let antes = try JSONSerialization.data(withJSONObject: anterior, options: [.sortedKeys])
            let cargada = try reiniciar(anterior)
            XCTAssertTrue(Config.continuoSoloGrabaciones(en: cargada))
            XCTAssertEqual(cargada["continuo_activo"] as? Bool, maestro)
            XCTAssertEqual(cargada["continuo_audio_modo"] as? String, "dictado")
            XCTAssertNil(cargada["continuo_solo_grabaciones"])
            XCTAssertEqual(antes, try JSONSerialization.data(withJSONObject: cargada, options: [.sortedKeys]))
        }
    }

    func testEleccionExplicitaPersisteTrasDosReiniciosYActualizaciones() throws {
        for elegida in [false, true] {
            for maestro in [false, true] {
                var preferencias: [String: Any] = ["continuo_activo": maestro, "continuo_solo_grabaciones": elegida]
                for _ in 0..<2 {
                    preferencias = try reiniciar(preferencias)
                    XCTAssertEqual(Config.continuoSoloGrabaciones(en: preferencias), elegida)
                    XCTAssertEqual(preferencias["continuo_activo"] as? Bool, maestro)
                }
            }
        }
    }

    func testPreferenciaInvalidaConservaDefaultSeguro() {
        for invalida in ["false" as Any, NSNull(), [false]] {
            XCTAssertTrue(Config.continuoSoloGrabaciones(en: ["continuo_solo_grabaciones": invalida]))
        }
    }
}
