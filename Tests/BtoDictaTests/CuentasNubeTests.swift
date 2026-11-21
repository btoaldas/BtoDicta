import XCTest
@testable import BtoDicta

/// Varias cuentas de Microsoft y Google, partes puras (spec 018).
final class CuentasNubeTests: XCTestCase {
    private func cuenta(_ id: String, _ p: ProveedorNube, _ alias: String, _ correo: String = "",
                        predeterminada: Bool = false) -> CuentaNube {
        CuentaNube(id: id, proveedor: p, alias: alias, correo: correo, clientID: "x", tenant: "",
                   llavero: "cuenta-\(id)-refresh", predeterminada: predeterminada)
    }

    private var lista: [CuentaNube] {
        [cuenta("m1", .microsoft, "Trabajo", "persona@empresa.example", predeterminada: true),
         cuenta("g1", .google, "Personal", "persona@gmail.example"),
         cuenta("m2", .microsoft, "Empresa")]
    }

    func testSinPistaUsaLaPredeterminada() {
        XCTAssertEqual(CuentasNube.elegir(nil, entre: lista)?.id, "m1")
        XCTAssertEqual(CuentasNube.elegir("revisa mis correos de hoy", entre: lista)?.id, "m1")
    }

    func testEligePorNombreCortoDentroDelPedido() {
        XCTAssertEqual(CuentasNube.elegir("revisa mi correo personal", entre: lista)?.id, "g1")   // RF-01
        XCTAssertEqual(CuentasNube.elegir("Empresa", entre: lista)?.id, "m2")
    }

    func testEligePorCorreoYPorProveedor() {
        XCTAssertEqual(CuentasNube.elegir("persona@gmail.example", entre: lista)?.id, "g1")
        XCTAssertEqual(CuentasNube.elegir("lo que llegó al gmail", entre: lista)?.id, "g1")
        XCTAssertEqual(CuentasNube.elegir("mi outlook", entre: lista)?.id, "m1")
    }

    func testSinCuentasNoHayEleccion() {
        XCTAssertNil(CuentasNube.elegir("personal", entre: []))
    }

    func testParaIANombraCuentasSinSecretos() {
        let t = CuentasNube.paraIA(lista)
        XCTAssertTrue(t.contains("Personal — Google, persona@gmail.example"))
        XCTAssertTrue(t.contains("(predeterminada)"))
        XCTAssertFalse(t.contains("refresh"))
    }

    func testPlanTraeLaCuenta() {
        let p = AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"leer_correo","contenido":"1","cuenta":"Personal"}}"#)
        XCTAssertEqual(p?.cuenta, "Personal")
    }

    func testCatalogoListaLasCuentas() {
        XCTAssertTrue(AgenteTerminal.catalogoGraph(ahora: Date(), cuentas: "Personal — Google").contains("Personal — Google"))
    }
}

/// Google: PKCE, redirección local y lectura de respuestas (spec 018).
final class GoogleCuentaTests: XCTestCase {
    func testDesafioPKCEConVectorDelEstandar() {
        // RFC 7636, apéndice B.
        XCTAssertEqual(GoogleCuenta.desafio("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(GoogleCuenta.verificador().count, 64)
    }

    func testURLAutorizacionPideOfflineYS256() throws {
        let u = try XCTUnwrap(GoogleCuenta.urlAutorizacion(clientID: "id", redireccion: "http://127.0.0.1:5000",
                                                           desafio: "d", estado: "e")).absoluteString
        XCTAssertTrue(u.contains("code_challenge_method=S256"))
        XCTAssertTrue(u.contains("access_type=offline"))
        XCTAssertTrue(u.contains("gmail.compose"))
    }

    func testLeerRedireccion() {
        let r = GoogleCuenta.leerRedireccion("GET /?state=abc&code=4/xyz&scope=email HTTP/1.1")
        XCTAssertEqual(r.codigo, "4/xyz"); XCTAssertEqual(r.estado, "abc"); XCTAssertNil(r.error)
        XCTAssertEqual(GoogleCuenta.leerRedireccion("GET /?error=access_denied&state=abc HTTP/1.1").error, "access_denied")
        XCTAssertNil(GoogleCuenta.leerRedireccion("basura").codigo)
    }

    private func base64url(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func decodificar(_ s: String) -> String {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return String(decoding: Data(base64Encoded: b)!, as: UTF8.self)
    }

    func testMimeCodificaAsuntoYNoAdmiteCabecerasInyectadas() {
        let m = decodificar(GoogleCuenta.mime(para: ["a@x.example\r\nBcc: espia@x.example"], asunto: "Reunión", cuerpo: "Hola ñandú"))
        XCTAssertTrue(m.hasPrefix("To: a@x.exampleBcc: espia@x.example\r\nSubject: =?UTF-8?B?"))
        XCTAssertFalse(m.contains("\r\nBcc:"))
        XCTAssertTrue(m.contains(Data("Hola ñandú".utf8).base64EncodedString()))
    }

    func testLeerMensaje() throws {
        let j: [String: Any] = ["id": "m1", "snippet": "Hola", "internalDate": "1763740800000",
                                "labelIds": ["INBOX", "UNREAD", "IMPORTANT"],
                                "payload": ["headers": [["name": "From", "value": "Ana <ana@x.example>"],
                                                        ["name": "Subject", "value": "Informe"]]]]
        let c = try XCTUnwrap(GoogleCuenta.leerMensaje(j))
        XCTAssertEqual(c.id, "m1"); XCTAssertEqual(c.de, "Ana <ana@x.example>"); XCTAssertEqual(c.asunto, "Informe")
        XCTAssertFalse(c.leido); XCTAssertTrue(c.importante)
        XCTAssertEqual(c.fecha, Date(timeIntervalSince1970: 1_763_740_800))
    }

    func testTextoDeBuscaLaParteDeTexto() {
        let p: [String: Any] = ["mimeType": "multipart/alternative", "parts": [
            ["mimeType": "text/html", "body": ["data": base64url("<b>no</b>")]],
            ["mimeType": "text/plain", "body": ["data": base64url("Texto plano ¿sí?")]]]]
        XCTAssertEqual(GoogleCuenta.textoDe(p), "Texto plano ¿sí?")
    }

    func testLeerEventosConHoraYDeDiaCompleto() {
        let j: [String: Any] = ["items": [
            ["summary": "Reunión", "location": "Sala 1", "organizer": ["email": "o@x.example"],
             "start": ["dateTime": "2026-11-21T15:00:00Z"], "end": ["dateTime": "2026-11-21T16:00:00Z"]],
            ["start": ["date": "2026-11-22"], "end": ["date": "2026-11-23"]]]]
        let e = GoogleCuenta.leerEventos(j)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].asunto, "Reunión"); XCTAssertEqual(e[0].organizador, "o@x.example"); XCTAssertFalse(e[0].todoElDia)
        XCTAssertEqual(e[1].asunto, "(sin título)"); XCTAssertTrue(e[1].todoElDia)
    }

    func testLeerContactosDescartaSinCorreo() {
        let j: [String: Any] = ["results": [
            ["person": ["names": [["displayName": "Ana Pérez"]], "emailAddresses": [["value": "ana@x.example"]],
                        "organizations": [["title": "Analista"]]]],
            ["person": ["names": [["displayName": "Sin correo"]]]]]]
        XCTAssertEqual(GoogleCuenta.leerContactos(j), [PersonaGraph(nombre: "Ana Pérez", correo: "ana@x.example", cargo: "Analista")])
    }
}

/// El estado «conectada» no abre el secreto; lo leído queda en memoria.
final class SecretosKeychainExisteTests: XCTestCase {
    func testExisteSinLeerYCacheSeLimpiaAlBorrar() {
        let cuenta = "prueba-existe-\(UUID().uuidString.prefix(8))"
        defer { SecretosKeychain.borrar(cuenta: cuenta) }
        XCTAssertFalse(SecretosKeychain.existe(cuenta: cuenta))
        XCTAssertTrue(SecretosKeychain.guardar("valor-de-prueba", cuenta: cuenta).ok)
        XCTAssertTrue(SecretosKeychain.existe(cuenta: cuenta))
        XCTAssertNotNil(SecretosKeychain.donde(cuenta: cuenta))
        XCTAssertEqual(SecretosKeychain.leer(cuenta: cuenta), "valor-de-prueba")
        SecretosKeychain.borrar(cuenta: cuenta)
        XCTAssertFalse(SecretosKeychain.existe(cuenta: cuenta))
        XCTAssertNil(SecretosKeychain.leer(cuenta: cuenta))
    }
}

/// «Los tres últimos correos»: se respeta la cantidad pedida.
final class CantidadCorreosTests: XCTestCase {
    func testCantidadPedida() {
        XCTAssertEqual(AgenteTerminal.cantidadPedida("revisa en mi correo personal los tres últimos correos", numero: nil), 3)
        XCTAssertEqual(AgenteTerminal.cantidadPedida("léeme los 5 últimos", numero: nil), 5)
        XCTAssertEqual(AgenteTerminal.cantidadPedida("dime el último correo", numero: nil), 1)
        XCTAssertNil(AgenteTerminal.cantidadPedida("revisa los últimos correos", numero: nil))
        XCTAssertEqual(AgenteTerminal.cantidadPedida("dime el último correo", numero: 1), 1)
        XCTAssertEqual(AgenteTerminal.cantidadPedida("cualquier cosa", numero: 4), 4)
        XCTAssertNil(AgenteTerminal.cantidadPedida("revisa los correos de los últimos dos días", numero: nil))
        XCTAssertNil(AgenteTerminal.cantidadPedida("revisa mis correos de hoy", numero: nil))
        XCTAssertNil(AgenteTerminal.cantidadPedida("x", numero: 900))
    }
}

/// Qué correos de la última lista se archivan.
final class ArchivarCorreosTests: XCTestCase {
    func testIndicesArchivar() {
        XCTAssertEqual(AgenteTerminal.indicesArchivar("todos", numero: nil, total: 3), [0, 1, 2])
        XCTAssertEqual(AgenteTerminal.indicesArchivar("1, 3", numero: nil, total: 3), [0, 2])
        XCTAssertEqual(AgenteTerminal.indicesArchivar("", numero: 2, total: 3), [1])
        XCTAssertEqual(AgenteTerminal.indicesArchivar("2, 9, 2", numero: nil, total: 3), [1])   // fuera de rango y repetidos fuera
        XCTAssertEqual(AgenteTerminal.indicesArchivar("", numero: nil, total: 3), [])          // sin decir cuáles: no archiva
        XCTAssertEqual(AgenteTerminal.indicesArchivar("todos", numero: nil, total: 0), [])
    }

    func testPlanArchivar() {
        let p = AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"archivar_correo","contenido":"todos"}}"#)
        XCTAssertEqual(p?.herramienta, "archivar_correo")
    }

    func testGooglePideElPermisoDeModificar() {
        XCTAssertTrue(GoogleCuenta.alcances.contains("https://www.googleapis.com/auth/gmail.modify"))
    }
}

/// Buzón compartido o delegado de Microsoft (spec 019, fase 3).
final class BuzonDelegadoTests: XCTestCase {
    func testRutasVanAlBuzonDelegado() {
        XCTAssertEqual(MicrosoftGraph.ruta("/me/messages/1/move", buzon: "sec@x.example"), "/users/sec@x.example/messages/1/move")
        XCTAssertEqual(MicrosoftGraph.ruta("/me/mailFolders/inbox/messages", buzon: "sec@x.example"), "/users/sec@x.example/mailFolders/inbox/messages")
        XCTAssertEqual(MicrosoftGraph.ruta("/me/calendarView", buzon: "sec@x.example"), "/users/sec@x.example/calendarView")
        XCTAssertEqual(MicrosoftGraph.ruta("/me/people", buzon: "sec@x.example"), "/me/people")   // personas: del usuario
        XCTAssertEqual(MicrosoftGraph.ruta("/me", buzon: "sec@x.example"), "/me")
        XCTAssertEqual(MicrosoftGraph.ruta("/me/messages", buzon: nil), "/me/messages")
        XCTAssertEqual(MicrosoftGraph.ruta("/me/messages", buzon: "a/../b@x"), "/users/a%2F..%2Fb@x/messages")
    }

    func testSoloElBuzonDelegadoPidePermisosShared() {
        var c = CuentaNube(id: "m", proveedor: .microsoft, alias: "Secretaría", correo: "", clientID: "x", tenant: "",
                           llavero: "l", predeterminada: false)
        XCTAssertFalse(MicrosoftGraph.alcances(de: c).contains("Shared"))
        c.buzon = "sec@x.example"
        XCTAssertTrue(MicrosoftGraph.alcances(de: c).contains("Mail.ReadWrite.Shared"))
    }

    func testRegistroViejoSinBuzonSeLeeIgual() throws {
        let j = #"[{"id":"m","proveedor":"microsoft","alias":"A","correo":"","clientID":"x","tenant":"","llavero":"l","predeterminada":true}]"#
        let l = try JSONDecoder().decode([CuentaNube].self, from: Data(j.utf8))
        XCTAssertNil(l[0].buzon); XCTAssertFalse(l[0].esBuzonDelegado)
    }
}
