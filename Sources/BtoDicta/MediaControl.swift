import AppKit

// MARK: - Control multimedia (pausa REAL vía mediaremote-adapter)

/// Pausa/reanuda lo que suene usando el adapter de Jonas van den Berg
/// (github.com/ungive/mediaremote-adapter, BSD-3). macOS 15.4+ bloqueó
/// MediaRemote para apps de terceros; el truco es invocar `/usr/bin/perl`
/// (binario del sistema con el entitlement) que carga el framework y ejecuta
/// el comando. Así se lee el estado REAL y se pausa explícitamente —cero bug
/// del toggle, sin tocar el navegador—. Bundle: Resources/mediaremote-adapter.pl
/// + Resources/MediaRemoteAdapter.framework.
private enum MediaAdapter {
    static let play = 0
    static let pause = 1
    static let stop = 3
    static let next = 4
    static let previous = 5

    typealias Ahora = (reproduciendo: Bool, titulo: String, artista: String, id: String?)

    private static var scriptPath: String? {
        Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl")
    }
    private static var frameworkPath: String? {
        Bundle.main.path(forResource: "MediaRemoteAdapter", ofType: "framework")
    }

    /// ¿Hay algo reproduciéndose ahora? (lee "playing" del JSON del adapter)
    static func isPlaying() -> Bool {
        ahora()?.reproduciendo ?? false
    }

    /// Metadatos reales del centro multimedia. `uniqueIdentifier` coincide con
    /// el trackId del catálogo Apple y permite verificar incluso durante el
    /// breve instante en que Music aún no expone `current track` por AppleScript.
    static func ahora(timeout: TimeInterval = 3) -> Ahora? {
        guard let out = run(["get", "--no-artwork"], timeout: timeout),
              let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playing = json["playing"] as? Bool else { return nil }
        let titulo = json["title"] as? String ?? ""
        let artista = json["artist"] as? String ?? ""
        let id = json["uniqueIdentifier"].map { String(describing: $0) }
        return (playing, titulo, artista, id)
    }

    @discardableResult
    static func send(_ command: Int) -> Bool {
        run(["send", String(command)]) != nil
    }

    private static func run(_ args: [String], timeout: TimeInterval = 3) -> String? {
        guard let scriptPath, let frameworkPath else {
            Log.debug("adapter: recursos no encontrados en el bundle")
            return nil
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [scriptPath, frameworkPath] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // El adapter normalmente responde al instante. El límite sí es
            // efectivo: una falla de MediaRemote nunca puede congelar el hilo.
            let deadline = Date().addingTimeInterval(max(0.5, timeout))
            while task.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if task.isRunning { task.terminate() }
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            Log.debug("adapter: no se pudo lanzar perl: \(error.localizedDescription)")
            return nil
        }
    }
}

final class MediaControl {
    private var pausedMedia = false
    // Respaldo por mute (opcional, config "silenciar_ademas")
    private var previousVolume: Int?
    private var wasMuted = false
    private var didMute = false

    /// Reanuda el reproductor que macOS considera activo. Sirve para “pon
    /// música” sin consulta: no adivina una canción ni simula teclas.
    @discardableResult
    static func reproducirActual() -> Bool {
        guard MediaAdapter.send(MediaAdapter.play) else { return false }
        Thread.sleep(forTimeInterval: 0.12)
        return MediaAdapter.isPlaying()
    }

    static func estadoActual(timeout: TimeInterval = 3) -> (reproduciendo: Bool,
                                   titulo: String, artista: String, id: String?)? {
        MediaAdapter.ahora(timeout: timeout)
    }

    @discardableResult
    static func pausarActual() -> Bool {
        guard MediaAdapter.isPlaying(), MediaAdapter.send(MediaAdapter.pause) else { return false }
        Thread.sleep(forTimeInterval: 0.16)
        return !MediaAdapter.isPlaying()
    }

    @discardableResult
    static func detenerActual() -> Bool {
        guard MediaAdapter.ahora(timeout: 1) != nil,
              MediaAdapter.send(MediaAdapter.stop) else { return false }
        Thread.sleep(forTimeInterval: 0.16)
        return !MediaAdapter.isPlaying()
    }

    @discardableResult
    static func siguienteActual() -> Bool { cambiarPista(MediaAdapter.next) }

    @discardableResult
    static func anteriorActual() -> Bool { cambiarPista(MediaAdapter.previous) }

    private static func cambiarPista(_ comando: Int) -> Bool {
        guard let antes = MediaAdapter.ahora(timeout: 1), MediaAdapter.send(comando) else { return false }
        for espera in [0.18, 0.28, 0.42] {
            Thread.sleep(forTimeInterval: espera)
            guard let despues = MediaAdapter.ahora(timeout: 1) else { continue }
            if despues.id != antes.id || despues.titulo != antes.titulo { return true }
        }
        return false
    }

    /// Al empezar a dictar: pausa REAL lo que suene.
    func dictationStarted() {
        guard Config.duckMedia() else { return }

        if MediaAdapter.isPlaying() {
            let ok = MediaAdapter.send(MediaAdapter.pause)
            pausedMedia = ok
            Log.write("multimedia: PAUSADO (adapter, ok=\(ok))")
        } else {
            Log.debug("multimedia: nada reproduciendose")
        }

        // Baja el volumen a 0 (respaldo visible para audio que no pausa y para
        // que se vea el nivel bajar). Se restaura EXACTO al terminar.
        if Config.muteToo() {
            previousVolume = readVolume()
            setVolume(0)
            didMute = true
            Log.debug("multimedia: volumen \(previousVolume ?? -1) → 0")
        }
    }

    /// Al terminar o cancelar: reanuda solo lo que ESTA app pausó.
    func dictationEnded() {
        if pausedMedia {
            MediaAdapter.send(MediaAdapter.play)
            pausedMedia = false
            Log.write("multimedia: reanudado (adapter)")
        }
        if didMute {
            didMute = false
            if let v = previousVolume {
                setVolume(v)
                Log.debug("multimedia: volumen restaurado a \(v)")
                previousVolume = nil
            }
        }
    }

    private func readVolume() -> Int {
        Int(runOSA("output volume of (get volume settings)")?.int32Value ?? 50)
    }
    private func readMuted() -> Bool {
        runOSA("output muted of (get volume settings)")?.booleanValue ?? false
    }
    private func setVolume(_ value: Int) { _ = runOSA("set volume output volume \(max(0, min(100, value)))") }
    private func setMuted(_ muted: Bool) { _ = runOSA("set volume output muted \(muted)") }

    @discardableResult
    private func runOSA(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error)
    }
}
