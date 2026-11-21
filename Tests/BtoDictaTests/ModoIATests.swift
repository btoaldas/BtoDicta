import AppKit
import XCTest
@testable import BtoDicta

/// Modo IA por tecla propia (spec 014).
final class ModoIATests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    /// Un toque de Control: baja (keyCode 59 con .control) y sube.
    private func toque(_ g: inout GestoTeclaIA, en s: Double, codigo: UInt16 = 59,
                       tecla: String = "ctrl", dura: Double = 0.08) -> GestoTeclaIA.Resultado {
        _ = g.evento(keyCode: codigo, flags: .control, tecla: tecla, ventana: 0.4, ahora: t0 + s)
        return g.evento(keyCode: codigo, flags: [], tecla: tecla, ventana: 0.4, ahora: t0 + s + dura)
    }

    func testDobleToqueDentroDeLaVentana() {
        var g = GestoTeclaIA()
        XCTAssertEqual(toque(&g, en: 0), .toque)
        XCTAssertEqual(toque(&g, en: 0.25), .doble)
    }

    func testDosToquesSeparadosNoSonDoble() {
        var g = GestoTeclaIA()
        XCTAssertEqual(toque(&g, en: 0), .toque)
        XCTAssertEqual(toque(&g, en: 1.0), .toque)
    }

    func testMantenerNoEsToque() {
        var g = GestoTeclaIA()
        XCTAssertEqual(toque(&g, en: 0, dura: 0.6), .nada)
        XCTAssertEqual(toque(&g, en: 0.7), .toque)
    }

    func testControlConOtraTeclaNoCuenta() {
        var g = GestoTeclaIA()
        XCTAssertEqual(toque(&g, en: 0), .toque)
        _ = g.evento(keyCode: 59, flags: .control, tecla: "ctrl", ventana: 0.4, ahora: t0 + 0.2)
        g.otraTecla()   // Control+C
        XCTAssertEqual(g.evento(keyCode: 59, flags: [], tecla: "ctrl", ventana: 0.4, ahora: t0 + 0.3), .nada)
    }

    func testControlConOtroModificadorNoCuenta() {
        var g = GestoTeclaIA()
        _ = g.evento(keyCode: 59, flags: [.control, .shift], tecla: "ctrl", ventana: 0.4, ahora: t0)
        XCTAssertEqual(g.evento(keyCode: 59, flags: .shift, tecla: "ctrl", ventana: 0.4, ahora: t0 + 0.1), .nada)
    }

    func testSoloLadoDerecho() {
        var g = GestoTeclaIA()
        XCTAssertEqual(toque(&g, en: 0, codigo: 59, tecla: "ctrl_der"), .nada)
        XCTAssertEqual(toque(&g, en: 0.2, codigo: 62, tecla: "ctrl_der"), .toque)
        XCTAssertEqual(toque(&g, en: 0.4, codigo: 62, tecla: "ctrl_der"), .doble)
    }

    func testOrdenesDirectas() {
        XCTAssertTrue(AgenteOrdenes.esCallar("Cállate."))
        XCTAssertTrue(AgenteOrdenes.esCallar("silencio"))
        XCTAssertFalse(AgenteOrdenes.esCallar("calla a mi hermano en el grupo"))
        XCTAssertEqual(AgenteOrdenes.tareaACompletar("tacha comprar pan"), "comprar pan")
        XCTAssertEqual(AgenteOrdenes.tareaACompletar("marca como hecha la tarea de pagar la luz"), "pagar la luz")
        XCTAssertEqual(AgenteOrdenes.tareaACompletar("marca como hecho el informe"), "el informe")
        XCTAssertNil(AgenteOrdenes.tareaACompletar("quita el volumen"))
        XCTAssertNil(AgenteOrdenes.tareaACompletar("marca a Juan"))
    }

    func testInterpretarPlanTerminal() {
        let r = """
        Claro: {"respuesta":"Reviso el disco","comandos":[{"cmd":"df -h","sudo":false,"proposito":"espacio"},{"cmd":"sudo purge","proposito":"memoria"}]}
        """
        let p = AgenteTerminal.interpretar(r)
        XCTAssertEqual(p?.respuesta, "Reviso el disco")
        XCTAssertEqual(p?.comandos.count, 2)
        XCTAssertEqual(p?.comandos[1], ComandoTerminal(cmd: "purge", sudo: true, proposito: "memoria"))
        XCTAssertNil(AgenteTerminal.interpretar("no hay json"))
    }

    func testSoloLectura() {
        XCTAssertTrue(AgenteTerminal.esSoloLectura("df -h"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("ps aux | grep Safari | head -5"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("pmset -g batt"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("rm -rf ~/x"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls; rm x"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("echo hola > archivo"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find . -name '*.tmp' -delete"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("defaults write com.x y 1"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("echo $(whoami)"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("open ~/Desktop/x.command"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("sort -o ~/.zshrc lista"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("printenv"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ifconfig en0 down"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("sysctl kern.x=1"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("cat $HOME/.ssh/id_rsa"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find . -fprint salida"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls |"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("date +%H:%M"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("cat ~/.ssh/id_ed25519"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls /Users/x/Library/Keychains"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("cat .env"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find . '-delete'"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find . -newerXY x -fls out"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls *"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find .\t-delete"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("find .\u{00A0}-delete"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("file -C -m x"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("find /tmp -maxdepth 1 -type f -name x.log"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("cat .codex/auth.json"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls Library/../.config"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ps eww"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ps -E"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("ps aux"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("sysctl -f archivo"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("sysctl -n hw.ncpu"))
    }

    func testModosDeConfirmacion() {
        let leer = ComandoTerminal(cmd: "df -h", sudo: false, proposito: "")
        let borrar = ComandoTerminal(cmd: "rm x", sudo: false, proposito: "")
        let sudoLeer = ComandoTerminal(cmd: "ls /var/root", sudo: true, proposito: "")
        XCTAssertTrue(AgenteTerminal.requiereAutorizacion(leer, modo: "aprobacion"))
        XCTAssertFalse(AgenteTerminal.requiereAutorizacion(leer, modo: "auto"))
        XCTAssertTrue(AgenteTerminal.requiereAutorizacion(borrar, modo: "auto"))
        XCTAssertTrue(AgenteTerminal.requiereAutorizacion(sudoLeer, modo: "auto"))
        XCTAssertFalse(AgenteTerminal.requiereAutorizacion(borrar, modo: "omitir"))
    }

    func testComillas() {
        XCTAssertEqual(AgenteTerminal.comillasShell("echo 'a'"), "'echo '\\''a'\\'''")
        XCTAssertEqual(AgenteTerminal.escaparAppleScript("a \"b\" \\c"), "a \\\"b\\\" \\\\c")
    }

    func testCancelarMataElComandoEnCurso() {
        let e = expectation(description: "cancela")
        let inicio = Date()
        AgenteTerminal.ejecutar(ComandoTerminal(cmd: "sleep 30", sudo: false, proposito: ""), timeout: 60) { r in
            XCTAssertNotEqual(r.codigo, 0)
            XCTAssertLessThan(Date().timeIntervalSince(inicio), 10)
            e.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { AgenteTerminal.cancelar() }
        wait(for: [e], timeout: 20)
    }

    func testEjecutarDevuelveSalida() {
        let e = expectation(description: "ejecuta")
        AgenteTerminal.ejecutar(ComandoTerminal(cmd: "echo hola", sudo: false, proposito: ""), timeout: 10) { r in
            XCTAssertEqual(r.codigo, 0)
            XCTAssertEqual(r.salida, "hola")
            e.fulfill()
        }
        wait(for: [e], timeout: 15)
    }
}
