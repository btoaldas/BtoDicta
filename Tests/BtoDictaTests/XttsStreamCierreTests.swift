import XCTest
@testable import BtoDicta

/// El proceso puede salir antes de que se drene su stdout: la captura debe
/// esperar EOF + salida y no perder la cola del audio.
final class XttsStreamCierreTests: XCTestCase {

    func testNoPierdeLaColaSiElProcesoSaleAntesDelEOF() {
        // Escribe 4096 bytes, sale con 0 y deja a un hijo que escribe otros
        // 4096 medio segundo después con el mismo stdout abierto.
        let c = XttsStreamTTS()
        var f32 = Data()
        c.onPCM = { f32.append($0) }
        let fin = expectation(description: "fin")
        var ok = false
        c.done = { ok = $0; fin.fulfill() }
        c.lanzar(ejecutable: URL(fileURLWithPath: "/bin/sh"),
                 argumentos: ["-c", "head -c 4096 /dev/zero; (sleep 0.5; head -c 4096 /dev/zero) & exit 0"])
        wait(for: [fin], timeout: 5)
        XCTAssertTrue(ok)
        XCTAssertEqual(f32.count, 8192)
    }
}
