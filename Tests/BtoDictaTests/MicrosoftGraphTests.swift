import XCTest
@testable import BtoDicta

/// Correo de Microsoft por Graph, partes puras (spec 015).
final class MicrosoftGraphTests: XCTestCase {
    func testFormularioCodificaYOrdena() {
        XCTAssertEqual(MicrosoftGraph.formulario(["scope": "offline_access Mail.Read", "client_id": "a-b"]),
                       "client_id=a-b&scope=offline_access%20Mail.Read")
    }

    func testURLBandejaDesdeInicioDelDia() throws {
        let ahora = ISO8601DateFormatter().date(from: "2026-11-21T15:00:00Z")!
        let url = try XCTUnwrap(MicrosoftGraph.urlBandeja(dias: 2, ahora: ahora))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let filtro = try XCTUnwrap(c.queryItems?.first { $0.name == "$filter" }?.value)
        let inicio = Calendar.current.startOfDay(for: ahora.addingTimeInterval(-86_400))
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(filtro, "receivedDateTime ge \(f.string(from: inicio))")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages"))
        // Fuera de rango se acota a 1–7.
        let u30 = try XCTUnwrap(MicrosoftGraph.urlBandeja(dias: 30, ahora: ahora))
        let f30 = URLComponents(url: u30, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "$filter" }?.value
        XCTAssertEqual(f30, "receivedDateTime ge \(f.string(from: Calendar.current.startOfDay(for: ahora.addingTimeInterval(-6 * 86_400))))")
    }

    func testLeerCorreos() throws {
        let json = #"""
        {"value":[{"subject":"Informe","receivedDateTime":"2026-11-21T10:00:00Z","bodyPreview":"Hola, adjunto el informe","importance":"high","isRead":false,
          "from":{"emailAddress":{"name":"Ana","address":"ana@ejemplo.com"}}},
          {"subject":"Sin fecha"}]}
        """#.data(using: .utf8)!
        let c = try XCTUnwrap(MicrosoftGraph.leerCorreos(json))
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].de, "Ana <ana@ejemplo.com>")
        XCTAssertTrue(c[0].importante)
        XCTAssertFalse(c[0].leido)
        XCTAssertTrue(MicrosoftGraph.paraIA(c).contains("importancia alta, sin leer"))
        XCTAssertNil(MicrosoftGraph.leerCorreos("{}".data(using: .utf8)!))
    }

    func testCodigoDispositivoYErrores() {
        let c = MicrosoftGraph.leerCodigoDispositivo(["device_code": "d", "user_code": "ABC123",
                                                      "verification_uri": "https://microsoft.com/devicelogin",
                                                      "interval": 5, "expires_in": 900])
        XCTAssertEqual(c?.codigoUsuario, "ABC123")
        XCTAssertEqual(c?.intervalo, 5)
        XCTAssertNil(MicrosoftGraph.leerCodigoDispositivo(["user_code": "x"]))
        XCTAssertEqual(MicrosoftGraph.mensajeError(["error": "expired_token"], codigo: 400),
                       "El código venció. Vuelve a pulsar Conectar.")
        XCTAssertEqual(MicrosoftGraph.mensajeError(nil, codigo: 0), "No pude conectarme a Microsoft.")
    }

    func testCapacidadLeerCorreo() {
        XCTAssertEqual(AgenteTerminal.diasLeerCorreo(#"{"capacidad":{"tipo":"herramienta","clave":"leer_correo","contenido":"2"}}"#), 2)
        XCTAssertEqual(AgenteTerminal.diasLeerCorreo(#"{"capacidad":{"clave":"herramienta:leer_correo","contenido":"9 días"}}"#), 7)
        XCTAssertNil(AgenteTerminal.diasLeerCorreo(#"{"capacidad":{"clave":"buscar","contenido":"x"}}"#))
        XCTAssertTrue(AgenteTerminal.promptMixto(pedido: "x", contexto: "", catalogo: "", correo: true).contains("leer_correo"))
        XCTAssertFalse(AgenteTerminal.promptMixto(pedido: "x", contexto: "", catalogo: "", correo: false).contains("leer_correo"))
    }

    func testSinCuentaNoSeOfrece() {
        Config.set("agente_graph_activo", to: false)
        XCTAssertFalse(MicrosoftGraph.disponible)
    }
}
