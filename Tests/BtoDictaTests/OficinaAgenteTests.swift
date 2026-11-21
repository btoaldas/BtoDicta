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
