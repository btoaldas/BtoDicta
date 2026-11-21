import XCTest
@testable import BtoDicta

/// Habilidades externas (spec 019, fase 1): lectura, duplicados y selección.
final class HabilidadesExternasTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func skill(_ carpeta: String, _ nombre: String, _ desc: String, cuerpo: String = "Pasos.") throws {
        let d = tmp.appendingPathComponent(carpeta).appendingPathComponent(nombre)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try "---\nname: \(nombre)\ndescription: \"\(desc)\"\n---\n\n\(cuerpo)\n"
            .write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    func testCabeceraYCuerpo() {
        let t = "---\nname: firmar-pdf\ndescription: \"Firmar PDF con FirmaEC\"\n---\n# Título\nTexto"
        XCTAssertEqual(HabilidadesExternas.cabecera(t)?.nombre, "firmar-pdf")
        XCTAssertEqual(HabilidadesExternas.cabecera(t)?.descripcion, "Firmar PDF con FirmaEC")
        XCTAssertEqual(HabilidadesExternas.cuerpo(t), "# Título\nTexto")
        XCTAssertNil(HabilidadesExternas.cabecera("sin cabecera"))
    }

    func testEscanearSinDuplicadosYGanaLaPrimeraCarpeta() throws {
        try skill("a", "firmar-pdf", "Firmar PDF con la firma electrónica oficial", cuerpo: "versión A")
        try skill("b", "firmar-pdf", "otra", cuerpo: "versión B")
        try skill("b", "transcribir", "Transcribir audio a texto con motor local")
        let l = HabilidadesExternas.escanear([tmp.appendingPathComponent("a"), tmp.appendingPathComponent("b"),
                                              tmp.appendingPathComponent("no-existe")])
        XCTAssertEqual(l.map(\.nombre), ["firmar-pdf", "transcribir"])
        XCTAssertEqual(l[0].descripcion, "Firmar PDF con la firma electrónica oficial")
    }

    func testSeleccionarPorNombreYDescripcion() throws {
        try skill("a", "firmar-pdf", "Firmar electrónicamente documentos PDF con certificado")
        try skill("a", "transcribir", "Transcribir audio a texto con motor local")
        try skill("a", "overlay-obs", "Crear overlays animados para OBS")
        let l = HabilidadesExternas.escanear([tmp.appendingPathComponent("a")])
        XCTAssertEqual(HabilidadesExternas.seleccionar("fírmame este documento pdf", de: l).map(\.nombre), ["firmar-pdf"])
        XCTAssertEqual(HabilidadesExternas.seleccionar("transcribe este audio", de: l).first?.nombre, "transcribir")
        XCTAssertTrue(HabilidadesExternas.seleccionar("¿qué hora es?", de: l).isEmpty)
    }
}

extension HabilidadesExternasTests {
    func testConFichaDeBtoDictaPideCoincidenciaFuerte() throws {
        try skill("a", "correo-outlook", "Correo Outlook institucional: leer y redactar")
        let l = HabilidadesExternas.escanear([tmp.appendingPathComponent("a")])
        XCTAssertEqual(HabilidadesExternas.seleccionar("revisa mi correo", de: l).count, 1)
        XCTAssertTrue(HabilidadesExternas.seleccionar("revisa mi correo", de: l, minimo: 4).isEmpty)
    }
}
