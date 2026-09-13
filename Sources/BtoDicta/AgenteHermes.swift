import Foundation

// MARK: - Motor de agente HERMES (BtoDicta = pasarela)
//
// Hermes es un cerebro conversacional opcional: BtoDicta captura la voz, la manda
// al CLI one-shot y recibe SOLO texto. Sus herramientas quedan vacías de forma
// deliberada; toda acción real vuelve al planificador y a la política de BtoDicta.
// La respuesta se muestra en el notch y se habla con la voz elegida.
//
// Sin infra extra (no MCP/plugin que instalar): Hermes ya sabe hacer lo suyo. A futuro,
// vías más ricas: ACP (`hermes acp`, streaming) o el MCP de Hermes. Igual para OpenClaw
// (`hermes claw`). Todo parametrizable; sin Hermes → cae al agente local.

enum AgenteHermes {
    private(set) static var sesion = ""     // session_id para mantener la conversación
    private static var proc: Process?        // proceso hermes en curso (para cancelar)
    private static var cancelado = false

    /// CANCELAR DE RAÍZ. Aunque este perfil no recibe herramientas, matamos el árbol
    /// completo por compatibilidad con procesos auxiliares de Hermes y versiones viejas.
    static func cancelar() {
        cancelado = true
        if let p = proc, p.isRunning { matarArbol(p.processIdentifier) }
        proc = nil
    }
    static var enCurso: Bool { proc?.isRunning ?? false }

    // Verificado por ejecución (2026-07-14, equivalente en Python): matar los GRUPOS de las
    // herramientas MIENTRAS hermes sigue vivo (sus grupos están intactos), y a hermes AL
    // FINAL. Sin SIGSTOP (interfería). Así muere el árbol entero: hermes + tools + nietos.
    private static func matarArbol(_ pid: Int32) {
        // Descendientes (BFS por pgrep -P), con hermes aún vivo.
        var desc: [Int32] = []
        var frontera = [pid]
        while let x = frontera.popLast() {
            for h in hijos(x) where !desc.contains(h) { desc.append(h); frontera.append(h) }
        }
        // Hermes corre CADA herramienta en su PROPIO process group. Matar el grupo entero
        // (kill -pgid) mata también nietos que pgrep -P no alcance. Nunca el grupo de la app.
        let miGrupo = getpgrp()
        let grupoHermes = grupoDe(pid)
        var grupos = Set<Int32>()
        for c in desc { let g = grupoDe(c); if g > 1, g != miGrupo, g != grupoHermes { grupos.insert(g) } }
        for g in grupos { kill(-g, SIGKILL) }            // grupos de herramientas (hermes aún vivo)
        for c in desc.reversed() { kill(c, SIGKILL) }    // + cada descendiente directo
        kill(pid, SIGKILL)                               // + hermes al final (corta el bucle)
    }
    private static func hijos(_ pid: Int32) -> [Int32] {
        salidaDe("/usr/bin/pgrep", ["-P", "\(pid)"]).split(whereSeparator: { $0 == "\n" || $0 == " " }).compactMap { Int32($0) }
    }
    private static func grupoDe(_ pid: Int32) -> Int32 {
        Int32(salidaDe("/bin/ps", ["-o", "pgid=", "-p", "\(pid)"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    private static func salidaDe(_ exe: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }; p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Ruta del binario hermes (parametrizable; por defecto ~/.local/bin/hermes).
    static func binario() -> String {
        let c = Config.hermesBin()
        if !c.isEmpty { return (c as NSString).expandingTildeInPath }
        let d = (NSHomeDirectory() + "/.local/bin/hermes")
        return FileManager.default.isExecutableFile(atPath: d) ? d : "/usr/local/bin/hermes"
    }

    static var disponible: Bool { FileManager.default.isExecutableFile(atPath: binario()) }

    /// Manda el texto a Hermes y devuelve SU respuesta (o nil si falla → agente local).
    static func preguntar(_ texto: String, completion: @escaping (String?) -> Void) {
        guard disponible else { Log.log(.ia, "Hermes: no encuentro el binario"); completion(nil); return }
        cancelado = false
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            proc = p
            p.executableURL = URL(fileURLWithPath: binario())
            // Hermes actúa aquí como CEREBRO de respaldo, no como ejecutor fuera
            // de la política de BtoDicta. Un toolset deliberadamente inexistente
            // produce una lista vacía de herramientas; las acciones reales pasan
            // por Modos, donde sí se clasifican y confirman por riesgo.
            var args = ["chat", "-q", texto, "--quiet", "--toolsets", "btodicta-brain",
                        "--max-turns", "1", "--source", "tool"]
            if !sesion.isEmpty { args += ["--resume", sesion] }   // continuidad de conversación
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (NSHomeDirectory() + "/.local/bin") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            p.environment = env
            // stdout = respuesta limpia; stderr = info de sesión (session_id). Se leen los
            // dos para sacar la respuesta Y el session_id (continuidad).
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { proc = nil; DispatchQueue.main.async { completion(nil) }; return }
            let dOut = out.fileHandleForReading.readDataToEndOfFile()
            let dErr = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            proc = nil
            if cancelado { DispatchQueue.main.async { completion(nil) }; return }   // cancelado por el usuario
            let stdoutTxt = String(data: dOut, encoding: .utf8) ?? ""
            let stderrTxt = String(data: dErr, encoding: .utf8) ?? ""
            let salida = stdoutTxt + "\n" + stderrTxt
            let (resp, sid) = parsear(salida)
            if let sid, !sid.isEmpty { sesion = sid }
            DispatchQueue.main.async { completion(resp.isEmpty ? nil : resp) }
        }
    }

    /// Nueva conversación (olvida la sesión).
    static func reiniciar() { sesion = "" }

    /// Separa el session_id de la respuesta. La salida trae una línea "session_id: <id>"
    /// y el resto es la respuesta.
    private static func parsear(_ salida: String) -> (String, String?) {
        var sid: String?
        var lineas: [String] = []
        for l in salida.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(l)
            if let r = s.range(of: "session_id:") {
                sid = s[r.upperBound...].trimmingCharacters(in: .whitespaces)
            } else {
                lineas.append(s)
            }
        }
        return (lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), sid)
    }
}
