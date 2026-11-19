import XCTest
@testable import BtoDicta

/// El proceso puede salir antes de que se drene su stdout: la captura debe
/// esperar EOF + salida y no perder la cola del audio.
final class XttsStreamCierreTests: XCTestCase {

    private func capturar(_ script: String, timeout: TimeInterval) -> (ok: Bool, bytes: Int) {
        let c = XttsStreamTTS()
        var f32 = Data()
        c.onPCM = { f32.append($0) }
        let fin = expectation(description: "fin")
        var ok = false
        c.done = { ok = $0; fin.fulfill() }
        c.lanzar(ejecutable: URL(fileURLWithPath: "/bin/sh"), argumentos: ["-c", script])
        withExtendedLifetime(c) { wait(for: [fin], timeout: timeout) }
        return (ok, f32.count)
    }

    func testNoPierdeLaColaSiElProcesoSaleAntesDelEOF() {
        // Escribe 4096 bytes, sale con 0 y deja a un hijo que escribe otros
        // 4096 medio segundo después con el mismo stdout abierto.
        let r = capturar("head -c 4096 /dev/zero; (sleep 0.5; head -c 4096 /dev/zero) & exit 0", timeout: 5)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.bytes, 8192)
    }

    func testNoCuelgaSiUnHijoRetieneStdout() {
        // Un hijo que nunca suelta stdout no puede dejar la frase sin terminar.
        let r = capturar("head -c 4096 /dev/zero; sleep 30 & exit 0", timeout: 5)
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.bytes, 4096)
    }

    func testUnaInstanciaNuevaCortaElProcesoDeLaAnterior() {
        let marca = "sleep 31.7"
        let a = XttsStreamTTS.nuevo()
        a.lanzar(ejecutable: URL(fileURLWithPath: "/bin/sh"), argumentos: ["-c", "exec \(marca)"])
        Thread.sleep(forTimeInterval: 0.3)
        _ = XttsStreamTTS.nuevo()
        Thread.sleep(forTimeInterval: 0.3)
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-f", marca]
        pg.standardOutput = FileHandle.nullDevice
        try? pg.run(); pg.waitUntilExit()
        XttsStreamTTS.cancelar()
        XCTAssertNotEqual(pg.terminationStatus, 0, "el proceso de la instancia anterior sigue vivo")
    }
}
