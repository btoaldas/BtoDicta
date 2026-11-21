import XCTest
@testable import BtoDicta

/// Obsidian (spec 021): anotar en carpeta propia y buscar sin secretos.
final class ObsidianAgenteTests: XCTestCase {
    private var b: URL!
    override func setUpWithError() throws {
        b = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: b.appendingPathComponent("Proyectos"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b.appendingPathComponent("Credenciales"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: b) }

    func testAnotarSoloEnSuCarpetaYSinPisar() throws {
        let f = ISO8601DateFormatter().date(from: "2026-11-21T15:00:00Z")!
        let u1 = try ObsidianAgente.anotar("El switch quedó configurado", en: b, ahora: f)
        let u2 = try ObsidianAgente.anotar("Llamar a Ana", en: b, ahora: f)
        XCTAssertEqual(u1, u2)
        XCTAssertTrue(u1.path.contains("/BtoDicta/Notas de voz/"))
        let t = try String(contentsOf: u1, encoding: .utf8)
        XCTAssertTrue(t.contains("autor: agente (BtoDicta)"))
        XCTAssertTrue(t.contains("El switch quedó configurado") && t.contains("Llamar a Ana"))
    }

    func testBuscarSaltaCredencialesYQuitaClaves() throws {
        try "---\ntipo: decision\n---\nRutaWiFi: decidimos usar MikroTik v7 en los buses.\nclave del router: xyz123\n"
            .write(to: b.appendingPathComponent("Proyectos/RutaWiFi decisiones.md"), atomically: true, encoding: .utf8)
        try "RutaWiFi router admin, usuario root".write(to: b.appendingPathComponent("Credenciales/RutaWiFi router.md"),
                                                     atomically: true, encoding: .utf8)
        try "---\ncontiene_secretos: sí\n---\nRutaWiFi token".write(to: b.appendingPathComponent("Proyectos/otra RutaWiFi.md"),
                                                                atomically: true, encoding: .utf8)
        let h = ObsidianAgente.buscar("¿qué decidimos sobre RutaWiFi?", en: b)
        XCTAssertEqual(h.map(\.titulo), ["RutaWiFi decisiones"])
        XCTAssertTrue(h[0].extracto.contains("MikroTik v7"))
        XCTAssertFalse(h[0].extracto.contains("xyz123"))
    }

    func testPlanesObsidian() {
        for h in ["obsidian_anotar", "obsidian_buscar"] {
            XCTAssertEqual(AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"\#(h)","contenido":"x"}}"#)?.herramienta, h)
        }
    }
}

/// Bóveda real (solo con BTODICTA_OBSIDIAN=1): cuánto tarda y cuántas notas trae, sin mostrar contenido.
final class ObsidianRealTests: XCTestCase {
    func testBusquedaEnBovedaReal() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BTODICTA_OBSIDIAN"] == "1")
        let b = try XCTUnwrap(ObsidianAgente.boveda())
        let t0 = Date()
        let h = ObsidianAgente.buscar("RutaWiFi MikroTik", en: b)
        print("OBS \(h.count) notas en \(String(format: "%.1f", Date().timeIntervalSince(t0))) s: " + h.map(\.titulo).joined(separator: " | "))
    }
}
