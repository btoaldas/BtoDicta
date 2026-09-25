import XCTest
@testable import BtoDicta

/// La rotación semanal del registro no puede perder una semana (21-09-2026).
final class RotacionRegistroTests: XCTestCase {

    func testLaMismaSemanaNoRota() {
        XCTAssertEqual(Log.decisionRotacion(enMemoria: "2026-W39", enDisco: "2026-W39", actual: "2026-W39"), .nada)
    }

    /// El caso que perdió la semana: un proceso con la semana vieja en memoria,
    /// cuando otro ya rotó. Tiene que adoptar la nueva, no volver a rotar.
    func testSiOtroProcesoYaRotoSeAdopta() {
        XCTAssertEqual(Log.decisionRotacion(enMemoria: "2026-W38", enDisco: "2026-W39", actual: "2026-W39"), .adoptar)
    }

    func testCambioDeSemanaSinRotarAunRota() {
        XCTAssertEqual(Log.decisionRotacion(enMemoria: "2026-W38", enDisco: "2026-W38", actual: "2026-W39"), .rotar)
        XCTAssertEqual(Log.decisionRotacion(enMemoria: "2026-W38", enDisco: nil, actual: "2026-W39"), .rotar)
    }

    /// Y si aun así dos procesos rotan la misma semana, el segundo no pisa al primero.
    func testUnArchivoDeSemanaNuncaSeSobrescribe() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let a = Log.destinoLibre("btodicta-2026-W38", en: d)
        XCTAssertEqual(a.lastPathComponent, "btodicta-2026-W38.log.gz")
        try Data("semana entera".utf8).write(to: a)
        let b = Log.destinoLibre("btodicta-2026-W38", en: d)
        XCTAssertEqual(b.lastPathComponent, "btodicta-2026-W38-2.log.gz")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "semana entera")
    }
}
