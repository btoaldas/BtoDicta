import XCTest
@testable import BtoDicta

/// Correo II (spec 019, fase 2): marcas, carpetas, adjuntos y límites.
final class CorreoAccionesTests: XCTestCase {
    func testMarcaDesdePalabras() {
        XCTAssertEqual(MarcaCorreo.desde("leído"), .leido)
        XCTAssertEqual(MarcaCorreo.desde("márcalos como no leídos"), .noLeido)
        XCTAssertEqual(MarcaCorreo.desde("sin leer"), .noLeido)
        XCTAssertEqual(MarcaCorreo.desde("ponle estrella"), .destacado)
        XCTAssertEqual(MarcaCorreo.desde("quita el destacado"), .sinDestacar)
        XCTAssertNil(MarcaCorreo.desde("hola"))
    }

    func testNombreSeguroDeAdjunto() {
        XCTAssertEqual(CorreoAcciones.nombreSeguro("../../.ssh/id_rsa"), "id_rsa")
        XCTAssertEqual(CorreoAcciones.nombreSeguro(".oculto"), "oculto")
        XCTAssertEqual(CorreoAcciones.nombreSeguro("   "), "adjunto")
        XCTAssertEqual(CorreoAcciones.nombreSeguro("informe final.pdf"), "informe final.pdf")
    }

    func testGuardarNoSobrescribe() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("adj-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = AdjuntoCorreo(nombre: "informe.pdf", datos: Data("1".utf8))
        let u1 = try CorreoAcciones.guardar(a, en: dir), u2 = try CorreoAcciones.guardar(a, en: dir)
        XCTAssertEqual(u1.lastPathComponent, "informe.pdf")
        XCTAssertEqual(u2.lastPathComponent, "informe-2.pdf")
    }

    func testElegirCarpeta() {
        let cs: [(id: String, nombre: String)] = [("1", "Bandeja de entrada"), ("2", "Proyectos"), ("3", "Facturas 2026")]
        XCTAssertEqual(CorreoAcciones.elegirCarpeta("proyectos", entre: cs)?.id, "2")
        XCTAssertEqual(CorreoAcciones.elegirCarpeta("facturas", entre: cs)?.id, "3")
        XCTAssertNil(CorreoAcciones.elegirCarpeta("viajes", entre: cs))
        XCTAssertNil(CorreoAcciones.elegirCarpeta("", entre: cs))
    }

    func testArchivoSensibleYFueraDeCasa() {
        XCTAssertTrue(CorreoAcciones.archivoSensible(URL(fileURLWithPath: "/Users/x/firma.p12")))
        XCTAssertTrue(CorreoAcciones.archivoSensible(URL(fileURLWithPath: "/Users/x/.ssh/config")))
        XCTAssertTrue(CorreoAcciones.archivoSensible(URL(fileURLWithPath: "/Users/x/id_ed25519")))
        XCTAssertFalse(CorreoAcciones.archivoSensible(URL(fileURLWithPath: "/Users/x/Downloads/informe.pdf")))
        XCTAssertNil(CorreoAcciones.archivoParaAdjuntar("/etc/hosts"))
    }

    func testAdjuntosMicrosoftYPartesGmail() {
        let ms: [String: Any] = ["value": [
            ["@odata.type": "#microsoft.graph.fileAttachment", "name": "a.txt", "contentBytes": Data("hola".utf8).base64EncodedString()],
            ["@odata.type": "#microsoft.graph.itemAttachment", "name": "correo adjunto"]]]
        XCTAssertEqual(MicrosoftGraph.leerAdjuntos(ms), [AdjuntoCorreo(nombre: "a.txt", datos: Data("hola".utf8))])
        let p: [String: Any] = ["mimeType": "multipart/mixed", "parts": [
            ["mimeType": "text/plain", "filename": "", "body": ["data": "eA"]],
            ["mimeType": "application/pdf", "filename": "f.pdf", "body": ["attachmentId": "A1"]]]]
        let partes = GoogleCuenta.partesAdjuntas(p)
        XCTAssertEqual(partes.count, 1); XCTAssertEqual(partes.first?.nombre, "f.pdf"); XCTAssertEqual(partes.first?.id, "A1")
    }

    func testMimeConAdjunto() {
        let raw = GoogleCuenta.mime(para: ["a@x.example"], asunto: "Hola", cuerpo: "Texto",
                                    adjuntos: [AdjuntoCorreo(nombre: "f.txt", datos: Data("123".utf8))], limite: "LIM")
        let t = String(decoding: GoogleCuenta.base64url(raw)!, as: UTF8.self)
        XCTAssertTrue(t.contains("multipart/mixed; boundary=\"LIM\""))
        XCTAssertTrue(t.contains("Content-Disposition: attachment"))
        XCTAssertTrue(t.contains(Data("123".utf8).base64EncodedString()))
        XCTAssertTrue(t.hasSuffix("--LIM--\r\n"))
    }

    func testCarpetasMicrosoftConHijas() {
        let j: [String: Any] = ["value": [["id": "i1", "displayName": "Proyectos",
                                           "childFolders": [["id": "i2", "displayName": "UEA"]]]]]
        XCTAssertEqual(MicrosoftGraph.leerCarpetas(j).map(\.nombre), ["Proyectos", "UEA"])
    }

    func testPlanHerramientasNuevas() {
        for h in ["marcar_correo", "mover_correo", "papelera_correo", "adjuntos_correo", "adjuntar_archivo"] {
            XCTAssertEqual(AgenteTerminal.planGraph(#"{"capacidad":{"tipo":"herramienta","clave":"\#(h)","contenido":"1"}}"#)?.herramienta, h)
        }
    }
}
