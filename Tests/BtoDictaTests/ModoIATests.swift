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

    func testRouterAceptaClaveConPrefijoDeTipo() {
        let caps = [Capacidad(tipo: "modo", clave: "buscar", nombre: "Buscar", descripcion: "busca",
                              frases: [], riesgo: .reversible, fuente: "", hijos: [])]
        let d = RouterGlobalIA.interpretar(#"{"tipo":"modo","clave":"modo:buscar","contenido":"x","confianza":1}"#,
                                           catalogo: caps, texto: "x")
        XCTAssertEqual(d?.clave, "buscar")
    }

    func testModeloFijadoGanaAlDePulido() throws {
        let zai = try XCTUnwrap(ChatIA.catalogo.first { $0.id == "zai" })
        Config.set("pulido_modelos", to: ["zai": "glm-4.5-flash"])
        defer { Config.set("pulido_modelos", to: [String: String]()) }
        XCTAssertEqual(zai.modeloEfectivo, "glm-4.5-flash")
        XCTAssertEqual(zai.conModelo("glm-4.7").modeloEfectivo, "glm-4.7")
        XCTAssertEqual(zai.conModelo("").modeloEfectivo, zai.modeloEfectivo)
    }

    func testResumenErrorSoloCodigoYMensaje() {
        let d = #"{"error":{"code":"1309","message":"plan vencido","detalle":"texto del pedido"}}"#.data(using: .utf8)
        XCTAssertEqual(RouterGlobalIA.resumenError(d), "1309: plan vencido")
        XCTAssertEqual(RouterGlobalIA.resumenError("<html>x</html>".data(using: .utf8)), "(cuerpo de 14 bytes)")
    }

    func testCamposMixtos() {
        let r = #"{"respuesta":"Abro el borrador","capacidad":{"tipo":"modo","clave":"x","contenido":"Hola","destinatario":"a@b.com","asunto":"Prueba"},"comandos":[]}"#
        let c = AgenteTerminal.camposMixtos(r)
        XCTAssertEqual(c.destinatario, "a@b.com")
        XCTAssertEqual(c.asunto, "Prueba")
        XCTAssertNil(AgenteTerminal.camposMixtos(#"{"capacidad":{"clave":"x","asunto":" "}}"#).asunto)
    }

    func testRecordatorioDelPlanTieneHora() {
        let p = AppleAgenda.interpretar("Comprobar que la inteligencia artificial de BetoDicta está funcionando correctamente, en 15 minutos")
        XCTAssertNil(p.error)
        XCTAssertNotNil(p.fecha)
        if let f = p.fecha { XCTAssertEqual(f.timeIntervalSinceNow, 15 * 60, accuracy: 90) }
        XCTAssertFalse(p.titulo.contains("15 minutos"))
    }

    func testPlazosRelativos() {
        let ahora = Date(timeIntervalSince1970: 2_000_000_000)
        func plazo(_ t: String) -> Double? { AppleAgenda.interpretar(t, ahora: ahora).fecha?.timeIntervalSince(ahora) }
        XCTAssertEqual(plazo("llamar a Ana en 15 minutos"), 900)
        XCTAssertEqual(plazo("dentro de 2 horas revisar el correo"), 7200)
        XCTAssertEqual(plazo("tomar agua en media hora"), 1800)
        XCTAssertEqual(plazo("en una hora salir"), 3600)
        XCTAssertEqual(plazo("en veinte minutos apagar el horno"), 1200)
        XCTAssertEqual(AppleAgenda.interpretar("llamar a Ana en 15 minutos", ahora: ahora).titulo, "llamar a Ana")
        XCTAssertNil(plazo("pensar en dos cosas"))
    }

    func testCierreHablado() {
        XCTAssertEqual(AgenteTerminal.cierreHablado("Abrí el borrador en Mail", ok: true),
                       "Abrí el borrador en Mail. ¿Está bien así o cambio algo?")
        XCTAssertEqual(AgenteTerminal.cierreHablado("", ok: false),
                       "No pude hacerlo. ¿Quieres que lo intente de otra forma?")
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
        XCTAssertTrue(AgenteTerminal.esSoloLectura("ps aux | grep -i Safari | head -n 5"))
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
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ps -eE"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ps -AE"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("grep -ri clave ."))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("grep --recursive x Documents"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("grep -i error log.txt"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("cat notas.txt"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep -d recurse x ."))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep --rec x"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep x archivo"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep -v 0 archivo"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep x 123"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | head 123"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("ls | grep -n x 5"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("ls | tail -n 3"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("defaults read com.app"))
        XCTAssertFalse(AgenteTerminal.esSoloLectura("launchctl print system"))
        XCTAssertTrue(AgenteTerminal.esSoloLectura("ls -la Downloads | wc -l"))
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

/// Prueba real contra ZCode (solo con BTODICTA_ZCODE_REAL=1): el plan mixto
/// elige una capacidad del catálogo para pedidos de acción.
final class ModoIAZCodeRealTests: XCTestCase {
    func testPlanMixtoEligeCapacidad() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BTODICTA_ZCODE_REAL"] == "1")
        let caps = CatalogoCapacidades.todas()
        for pedido in ["Haz un borrador de correo para persona@ejemplo.com con asunto Prueba y texto: esto es una prueba.",
                       "Abre el navegador y busca información sobre seguridad de los autos BMW."] {
            let e = expectation(description: pedido)
            AgenteZCode.preguntar(AgenteTerminal.promptMixto(pedido: pedido, contexto: "",
                                                             catalogo: CatalogoCapacidades.paraIA(caps)),
                                  timeout: 120) { r in
                print("ZCODE PEDIDO:", pedido)
                print("ZCODE RESPUESTA:", r ?? "nil")
                let cj = r.flatMap(AgenteTerminal.capacidadMixta)
                let d = cj.flatMap { RouterGlobalIA.interpretar($0, catalogo: caps, texto: pedido) }
                print("ZCODE DECISION:", d.map { "\($0.tipo)/\($0.clave): \($0.contenido)" } ?? "ninguna")
                // Hace algo: una capacidad del catálogo o comandos (p. ej. open "mailto:…").
                let comandos = r.flatMap(AgenteTerminal.interpretar)?.comandos ?? []
                XCTAssertTrue(d != nil || !comandos.isEmpty)
                e.fulfill()
            }
            wait(for: [e], timeout: 150)
        }
    }
}

/// Prueba real por API (solo con BTODICTA_IA_REAL=<id de proveedor>, p. ej. zai):
/// el plan mixto hace algo con la IA configurada del usuario.
final class ModoIAAPIRealTests: XCTestCase {
    func testPlanMixtoPorAPI() throws {
        let id = ProcessInfo.processInfo.environment["BTODICTA_IA_REAL"] ?? ""
        try XCTSkipIf(id.isEmpty)
        let base = try XCTUnwrap(ChatIA.catalogo.first { $0.id == id })
        let modelo = ProcessInfo.processInfo.environment["BTODICTA_IA_MODELO"] ?? ""
        let ia = modelo.isEmpty ? base : base.conModelo(modelo)
        try XCTSkipIf(ia.key == nil, "sin clave para \(id)")
        let caps = CatalogoCapacidades.todas()
        let propio = ProcessInfo.processInfo.environment["BTODICTA_IA_PEDIDO"] ?? ""
        let pedidos = propio.isEmpty
            ? ["Haz un borrador de correo para persona@ejemplo.com con asunto Prueba y texto: esto es una prueba.",
               "Abre el navegador y busca información sobre seguridad de los autos BMW."]
            : [propio]
        for pedido in pedidos {
            let e = expectation(description: pedido)
            let inicio = Date()
            let ctx = ProcessInfo.processInfo.environment["BTODICTA_IA_CONTEXTO"] ?? ""
            let p = AgenteTerminal.promptMixto(pedido: pedido, contexto: ctx, catalogo: CatalogoCapacidades.paraIA(caps))
            RouterGlobalIA.llamarIA(ia, prompt: p, textLen: p.count) { r in
                print(String(format: "IAREAL %.1f s:", Date().timeIntervalSince(inicio)), r ?? "nil")
                let d = r.flatMap(AgenteTerminal.capacidadMixta).flatMap { RouterGlobalIA.interpretar($0, catalogo: caps, texto: pedido) }
                let comandos = r.flatMap(AgenteTerminal.interpretar)?.comandos ?? []
                XCTAssertTrue(d != nil || !comandos.isEmpty)
                e.fulfill()
            }
            wait(for: [e], timeout: 60)
        }
    }
}
