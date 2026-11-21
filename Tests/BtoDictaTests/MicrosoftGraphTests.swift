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

/// Herramientas de Graph de la spec 016, partes puras.
final class MicrosoftGraphAccionesTests: XCTestCase {
    func testPlanGraph() throws {
        let r = #"{"respuesta":"x","capacidad":{"tipo":"herramienta","clave":"herramienta:borrador_correo","contenido":"Hola","destinatario":"Ana Pérez","asunto":"Reunión"}}"#
        let p = try XCTUnwrap(AgenteTerminal.planGraph(r))
        XCTAssertEqual(p.herramienta, "borrador_correo")
        XCTAssertEqual(p.destinatario, "Ana Pérez")
        XCTAssertEqual(p.asunto, "Reunión")
        let e = try XCTUnwrap(AgenteTerminal.planGraph(#"{"capacidad":{"clave":"crear_evento","contenido":"Dentista","inicio":"2026-11-22T10:30","numero":2}}"#))
        XCTAssertEqual(e.numero, 2)
        let comps = Calendar.current.dateComponents([.hour, .minute, .day], from: try XCTUnwrap(e.inicio))
        XCTAssertEqual(comps.hour, 10); XCTAssertEqual(comps.minute, 30); XCTAssertEqual(comps.day, 22)
        XCTAssertNil(AgenteTerminal.planGraph(#"{"capacidad":{"clave":"buscar","contenido":"x"}}"#))
        XCTAssertEqual(AgenteTerminal.dias("3 días"), 3)
        XCTAssertEqual(AgenteTerminal.dias("", porDefecto: 1), 1)
    }

    func testBorrador() throws {
        let c = MicrosoftGraph.cuerpoBorrador(para: ["a@b.com"], asunto: "Hola", cuerpo: "Texto")
        let to = try XCTUnwrap(c["toRecipients"] as? [[String: Any]])
        XCTAssertEqual((to.first?["emailAddress"] as? [String: String])?["address"], "a@b.com")
        let b = try XCTUnwrap(MicrosoftGraph.leerBorrador(["id": "M1", "subject": "Hola", "webLink": "https://x",
                                                           "toRecipients": [["emailAddress": ["address": "a@b.com"]]],
                                                           "body": ["content": "Texto"]]))
        XCTAssertEqual(b.para, ["a@b.com"]); XCTAssertEqual(b.inicio, "Texto")
        XCTAssertNil(MicrosoftGraph.leerBorrador(["subject": "sin id"]))
    }

    func testPersonas() {
        let p = MicrosoftGraph.leerPersonas(["value": [["displayName": "Ana", "jobTitle": "Docente",
                                                        "scoredEmailAddresses": [["address": "ana@x.edu"]]],
                                                       ["displayName": "Sin correo"]]])
        XCTAssertEqual(p, [PersonaGraph(nombre: "Ana", correo: "ana@x.edu", cargo: "Docente")])
        let u = MicrosoftGraph.leerUsuarios(["value": [["displayName": "Luis", "mail": "luis@x.edu"]]])
        XCTAssertEqual(u.first?.correo, "luis@x.edu")
        XCTAssertEqual(MicrosoftGraph.personasHabladas(p), "Ana, Docente, ana@x.edu")
    }

    func testEventosYFechas() throws {
        let ev = MicrosoftGraph.leerEventos(["value": [["subject": "Consejo", "isAllDay": false,
            "start": ["dateTime": "2026-11-22T15:00:00.0000000", "timeZone": "UTC"],
            "end": ["dateTime": "2026-11-22T16:00:00.0000000", "timeZone": "UTC"],
            "location": ["displayName": "Sala 1"]]]])
        let e = try XCTUnwrap(ev.first)
        XCTAssertEqual(e.fin.timeIntervalSince(e.inicio), 3600)
        XCTAssertEqual(MicrosoftGraph.utc(e.inicio), "2026-11-22T15:00:00Z")
        XCTAssertEqual(MicrosoftGraph.utc(e.inicio, conZona: false), "2026-11-22T15:00:00")
        XCTAssertTrue(MicrosoftGraph.agendaParaIA(ev).contains("Consejo · Sala 1"))
    }

    func testCatalogoGraphEnPrompt() {
        let p = AgenteTerminal.promptMixto(pedido: "x", contexto: "", catalogo: "", correo: true)
        for h in ["borrador_correo", "enviar_borrador", "ver_agenda", "buscar_persona"] { XCTAssertTrue(p.contains(h)) }
    }
}
