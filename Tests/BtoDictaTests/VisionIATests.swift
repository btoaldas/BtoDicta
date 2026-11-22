import XCTest
@testable import BtoDicta

/// Mirar la pantalla con un modelo que ve (spec 023).
final class VisionIATests: XCTestCase {
    func testModeloPorProveedor() throws {
        let zai = try XCTUnwrap(ChatIA.catalogo.first { $0.id == "zai" })
        XCTAssertEqual(VisionIA.modelo(para: zai), Config.agenteVisionModelo().isEmpty ? "glm-4.6v" : VisionIA.modelo(para: zai))
        XCTAssertNil(VisionIA.modelo(para: nil).flatMap { Config.agenteVisionModelo().isEmpty ? $0 : nil })
    }

    func testCuerpoConImagenYSinRazonamientoEnZai() throws {
        let c = VisionIA.cuerpo(modelo: "glm-4.6v", pregunta: "¿qué ves?", jpeg: Data([1, 2, 3]), proveedor: "zai")
        let msg = try XCTUnwrap((c["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        XCTAssertEqual(msg[0]["text"] as? String, "¿qué ves?")
        XCTAssertEqual((msg[1]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,AQID")
        XCTAssertNotNil(c["thinking"])
        XCTAssertNil(VisionIA.cuerpo(modelo: "m", pregunta: "x", jpeg: Data(), proveedor: "openai")["thinking"])
    }

    func testJpegReducido() throws {
        let png = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/img/acciones.png")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: png.path))
        let j = try XCTUnwrap(VisionIA.jpeg(png, lado: 400))
        let img = try XCTUnwrap(NSBitmapImageRep(data: j))
        XCTAssertLessThanOrEqual(max(img.pixelsWide, img.pixelsHigh), 400)
    }
}
