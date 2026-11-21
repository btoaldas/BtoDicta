import XCTest
@testable import BtoDicta

/// Herramientas deterministas del asistente (spec 017, fase 3). Solo carpetas temporales.
final class DocumentosAgenteTests: XCTestCase {
    private func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    func testPlantillaNumeracionEnBlancoYEscapes() {
        let o = DocumentosAgente.html(tipo: "oficio", asunto: "Permiso", para: "Director", de: nil, cuerpo: "Uno\n\nDos <b>")
        XCTAssertTrue(o.contains("OFICIO N.° ____")); XCTAssertTrue(o.contains("Atentamente"))
        XCTAssertTrue(o.contains("&lt;b&gt;")); XCTAssertFalse(o.contains("<b>Dos"))
        let i = DocumentosAgente.html(tipo: "informe", asunto: "x", para: nil, de: nil, cuerpo: "y")
        XCTAssertTrue(i.contains("<b>INFORME</b>")); XCTAssertFalse(i.contains("N.°"))
    }

    func testNombreLibreNuncaSobrescribe() throws {
        let d = try tmp()
        let f = Date(timeIntervalSince1970: 2_000_000_000)
        let a = DocumentosAgente.nombreLibre("oficio Permiso de salida", extension: "docx", en: d, fecha: f)
        try "x".write(to: a, atomically: true, encoding: .utf8)
        let b = DocumentosAgente.nombreLibre("oficio Permiso de salida", extension: "docx", en: d, fecha: f)
        XCTAssertNotEqual(a, b); XCTAssertTrue(b.lastPathComponent.contains("-2"))
    }

    func testCSV() {
        let c = DocumentosAgente.csv([["Concepto", "Monto"], ["Almuerzo, cena", "8"]])
        XCTAssertTrue(c.hasPrefix("\u{FEFF}Concepto,Monto\n")); XCTAssertTrue(c.contains("\"Almuerzo, cena\",8"))
    }

    func testBuscarHistorial() throws {
        let d = try tmp()
        let ahora = Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: ahora)
        let dia = d.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
        try FileManager.default.createDirectory(at: dia, withIntermediateDirectories: true)
        try "Revisar el switch de la red del laboratorio".write(to: dia.appendingPathComponent("10-05-00.txt"), atomically: true, encoding: .utf8)
        try "Comprar pan".write(to: dia.appendingPathComponent("11-00-00.txt"), atomically: true, encoding: .utf8)
        let r = DocumentosAgente.buscarHistorial("red laboratorio", ahora: ahora, dir: d)
        XCTAssertEqual(r.count, 1); XCTAssertTrue(r[0].texto.contains("switch"))
        XCTAssertTrue(DocumentosAgente.buscarHistorial("inexistente palabra", ahora: ahora, dir: d).isEmpty)
    }

    func testArchivoParaTranscribirEligeElMasReciente() throws {
        let home = try tmp()
        let dl = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        let viejo = dl.appendingPathComponent("viejo.m4a"), nuevo = dl.appendingPathComponent("nuevo.mp3")
        try Data([1]).write(to: viejo); try Data([1]).write(to: nuevo)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: viejo.path)
        try Data([1]).write(to: dl.appendingPathComponent("documento.pdf"))
        XCTAssertEqual(DocumentosAgente.archivoParaTranscribir("", home: home)?.lastPathComponent, "nuevo.mp3")
        XCTAssertEqual(DocumentosAgente.archivoParaTranscribir(viejo.path, home: home)?.lastPathComponent, "viejo.m4a")
    }

    func testPlanConFilas() throws {
        let p = try XCTUnwrap(AgenteTerminal.planGraph(#"{"capacidad":{"clave":"crear_hoja","asunto":"Gastos","filas":[["Concepto","Monto"],["Transporte",10]]}}"#))
        XCTAssertEqual(p.filas, [["Concepto", "Monto"], ["Transporte", "10"]])
    }
}
