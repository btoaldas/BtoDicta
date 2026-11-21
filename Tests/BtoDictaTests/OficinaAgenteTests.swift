import XCTest
@testable import BtoDicta

/// Oficina (spec 019, fase 5): documentos, páginas, sesiones de IA.
final class OficinaAgenteTests: XCTestCase {
    func testURLPublicaBloqueaRedLocal() {
        XCTAssertEqual(OficinaAgente.urlPublica("example.com/nota")?.absoluteString, "https://example.com/nota")
        XCTAssertNotNil(OficinaAgente.urlPublica("http://www.example.org"))
        for mala in ["http://localhost:8787", "http://127.0.0.1", "http://192.168.1.1", "http://10.0.0.5", "http://172.16.1.66",
                     "http://169.254.169.254/latest", "file:///etc/passwd", "http://impresora.local", "ftp://example.com"] {
            XCTAssertNil(OficinaAgente.urlPublica(mala), mala)
        }
        for mala in ["http://127.1", "http://0x7f.0.0.1", "http://017.0.0.1", "http://localhost.", "http://224.0.0.1", "http://[::1]"] {
            XCTAssertNil(OficinaAgente.urlPublica(mala), mala)
        }
        XCTAssertNotNil(OficinaAgente.urlPublica("http://8.8.8.8"))
        XCTAssertNotNil(OficinaAgente.urlPublica("https://cafe.example.com"))   // letras hex en el nombre: no es IP
    }

    func testIPv6Privadas() {
        func b(_ s: String) -> [UInt8] { var a = in6_addr(); inet_pton(AF_INET6, s, &a); return withUnsafeBytes(of: a) { Array($0) } }
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("::1")))
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("fe80::1")))
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("fd00::1")))
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("::ffff:192.168.1.1")))
        XCTAssertFalse(OficinaAgente.ipv6Privada(b("2606:4700::1111")))
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("64:ff9b::7f00:1")))       // NAT64 → 127.0.0.1
        XCTAssertFalse(OficinaAgente.ipv6Privada(b("64:ff9b::808:808")))     // NAT64 → 8.8.8.8
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("64:ff9b:1::1")))
        XCTAssertTrue(OficinaAgente.ipv6Privada(b("2002:c0a8:0101::1")))     // 6to4 → 192.168.1.1
        XCTAssertTrue(OficinaAgente.ipPrivada([198, 18, 0, 1]))
        XCTAssertTrue(OficinaAgente.ipPrivada([192, 0, 0, 8]))
        XCTAssertFalse(OficinaAgente.direccionPublica("127.0.0.1"))
        XCTAssertFalse(OficinaAgente.direccionPublica("fe80::1%en0"))
        XCTAssertTrue(OficinaAgente.direccionPublica("8.8.8.8"))
    }

    func testNombreQueResuelveALocalSeRechaza() {
        XCTAssertFalse(OficinaAgente.hostResuelvePublico("localhost"))
        XCTAssertFalse(OficinaAgente.hostResuelvePublico("127.0.0.1"))
    }

    func testTextoDeHTML() {
        let h = "<html><head><title>x</title></head><body><script>alert(1)</script><p>Hola &amp; adiós</p><p>Dos</p></body></html>"
        XCTAssertEqual(OficinaAgente.textoDeHTML(h), "Hola & adiós\nDos")
    }

    func testExcelCadenasYFilas() {
        let ss = "<sst><si><t>Gasto</t></si><si><t xml:space=\"preserve\">Valor</t></si><si><r><t>Trans</t></r><r><t>porte</t></r></si></sst>"
        let c = OficinaAgente.cadenasCompartidas(ss)
        XCTAssertEqual(c, ["Gasto", "Valor", "Transporte"])
        let hoja = "<sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row>"
            + "<row r=\"2\"><c r=\"A2\" t=\"s\"><v>2</v></c><c r=\"B2\"><v>10</v></c></row>"
            + "<row r=\"3\"><c r=\"A3\" t=\"inlineStr\"><is><t>Otro</t></is></c><c r=\"B3\"><f>B2*2</f><v>20</v></c></row></sheetData>"
        XCTAssertEqual(OficinaAgente.filasDeHoja(hoja, compartidas: c), [["Gasto", "Valor"], ["Transporte", "10"], ["Otro", "20"]])
    }

    func testSesionIADesdePalabras() {
        XCTAssertEqual(OficinaAgente.SesionIA.desde("abre Claude Code"), .claudeCode)
        XCTAssertEqual(OficinaAgente.SesionIA.desde("cloud code"), .claudeCode)
        XCTAssertEqual(OficinaAgente.SesionIA.desde("Codex"), .codex)
        XCTAssertEqual(OficinaAgente.SesionIA.desde("chat gpt"), .chatgpt)
        XCTAssertEqual(OficinaAgente.SesionIA.desde("Claude"), .claude)
        XCTAssertNil(OficinaAgente.SesionIA.desde("Word"))
    }

    func testCarpetaProyectoYDocumentoReciente() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("of-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent("Developer/BtoDicta"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Developer/quipux-docker"), withIntermediateDirectories: true)
        XCTAssertEqual(OficinaAgente.carpetaProyecto("Bto Dicta", home: home)?.lastPathComponent, "BtoDicta")
        XCTAssertEqual(OficinaAgente.carpetaProyecto("quipux", home: home)?.lastPathComponent, "quipux-docker")
        XCTAssertNil(OficinaAgente.carpetaProyecto("inexistente", home: home))

        let desc = home.appendingPathComponent("Downloads")
        try fm.createDirectory(at: desc, withIntermediateDirectories: true)
        try "gastos".write(to: desc.appendingPathComponent("gastos_noviembre.csv"), atomically: true, encoding: .utf8)
        try "otro".write(to: desc.appendingPathComponent("informe.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(OficinaAgente.documentoParaLeer("gastos", home: home)?.lastPathComponent, "gastos_noviembre.csv")
        XCTAssertNil(OficinaAgente.documentoParaLeer("/etc/hosts", home: home))
        XCTAssertNil(OficinaAgente.documentoParaLeer("informe", extensiones: ["pdf"], home: home))
    }

    func testLeerWordReal() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let html = tmp.appendingPathComponent("a.html"), docx = tmp.appendingPathComponent("a.docx")
        try "<p>Memo de prueba para el equipo</p>".write(to: html, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        p.arguments = ["-convert", "docx", html.path, "-output", docx.path]; try p.run(); p.waitUntilExit()
        XCTAssertEqual(OficinaAgente.leer(docx), "Memo de prueba para el equipo")
    }

    func testPlanHerramientasDeOficina() {
        for h in ["leer_documento", "resumir_pagina", "abrir_sesion_ia", "firmar_documento"] {
            XCTAssertEqual(AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"\#(h)","contenido":"x"}}"#)?.herramienta, h)
        }
    }
}

/// Lectura real de una página (solo con BTODICTA_RED=1: usa internet).
final class OficinaPaginaRealTests: XCTestCase {
    func testLeePaginaPublicaYRechazaLocal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BTODICTA_RED"] == "1")
        let e1 = expectation(description: "pública"), e2 = expectation(description: "local")
        OficinaAgente.leerPagina(URL(string: "https://example.com")!) { t in
            XCTAssertTrue(t?.contains("documentation examples") == true, t ?? "nil"); e1.fulfill()
        }
        OficinaAgente.leerPagina(URL(string: "http://localhost.:8787/")!) { t in XCTAssertNil(t); e2.fulfill() }
        wait(for: [e1, e2], timeout: 20)
    }
}

/// YouTube: primer video y navegador pedido.
final class YouTubeTests: XCTestCase {
    func testPrimerVideo() {
        XCTAssertEqual(OficinaAgente.primerVideo(#"..."videoId":"dQw4w9WgXcQ","x":1,"videoId":"aaaaaaaaaaa""#), "dQw4w9WgXcQ")
        XCTAssertNil(OficinaAgente.primerVideo("sin videos"))
    }

    func testNavegadorPedido() {
        XCTAssertEqual(OficinaAgente.navegador("ábrelo en Safari")?.lastPathComponent, "Safari.app")
        XCTAssertNil(OficinaAgente.navegador("pon música"))
    }

    func testResultadosRealesTraenVideo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BTODICTA_RED"] == "1")
        let e = expectation(description: "youtube")
        var req = URLRequest(url: URL(string: "https://www.youtube.com/results?search_query=musica+alegre")!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { d, _, _ in
            XCTAssertNotNil(d.flatMap { String(data: $0, encoding: .utf8) }.flatMap(OficinaAgente.primerVideo)); e.fulfill()
        }.resume()
        wait(for: [e], timeout: 15)
    }
}

/// Delegar a Claude Code o Codex con el encargo bien citado.
final class DelegarAgenteTests: XCTestCase {
    func testOrdenTerminalCitaElEncargo() {
        let c = URL(fileURLWithPath: "/Users/x/Developer/Mi Proyecto")
        XCTAssertEqual(OficinaAgente.ordenTerminal(.claudeCode, carpeta: c, encargo: nil), "cd '/Users/x/Developer/Mi Proyecto' && claude")
        XCTAssertEqual(OficinaAgente.ordenTerminal(.codex, carpeta: c, encargo: "haz la proforma de O'Brien; rm -rf ~"),
                       "cd '/Users/x/Developer/Mi Proyecto' && codex 'haz la proforma de O'\\''Brien; rm -rf ~'")
    }

    func testPlanDelegar() {
        XCTAssertEqual(AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"delegar_agente","contenido":"x"}}"#)?.herramienta,
                       "delegar_agente")
    }
}
