import AppKit
import AVFoundation
import Speech

// MARK: - Confirmar por voz (spec 020)
//
// El cuadro de confirmación sigue ahí (es la red de seguridad), pero además Beto
// pregunta en voz alta y escucha «sí» o «no» con el reconocimiento local de
// Apple. Cualquier «no» gana. Si el reconocimiento no está disponible, queda
// solo el cuadro, como siempre.

final class EscuchaSiNo {
    private let motor = AVAudioEngine()
    private var peticion: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var decidido = false
    var alDecidir: ((Bool) -> Void)?

    static let palabrasNo: Set<String> = ["no", "cancela", "cancelar", "cancelalo", "espera", "alto", "detente", "negativo", "nunca"]
    static let palabrasSi: Set<String> = ["si", "dale", "confirmo", "confirmado", "adelante", "hazlo", "envialo", "claro",
                                          "ok", "okay", "acepto", "procede", "correcto", "listo", "vale", "afirmativo"]

    /// «sí» → true, «no» → false, nada claro → nil. Cualquier negación gana (puro).
    static func decision(_ texto: String) -> Bool? {
        let n = PerfilAgente.normalizar(texto)
        let palabras = Set(n.split(separator: " ").map(String.init))
        if !palabras.isDisjoint(with: palabrasNo) { return false }
        if !palabras.isDisjoint(with: palabrasSi) || n.contains("de acuerdo") || n.contains("por supuesto") { return true }
        return nil
    }

    /// Empieza a escuchar. false si no se puede (sin permiso, sin modelo o sin micrófono).
    func iniciar() -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            // Primera vez: macOS pregunta; esta confirmación queda con el cuadro y las siguientes ya escuchan.
            SFSpeechRecognizer.requestAuthorization { _ in }
            return false
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let rec = SFSpeechRecognizer(locale: Locale(identifier: "es-ES")), rec.isAvailable else { return false }
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { p.requiresOnDeviceRecognition = true }
        p.contextualStrings = ["sí", "no", "dale", "cancela", "adelante"]
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { return false }
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { b, _ in p.append(b) }
        motor.prepare()
        do { try motor.start() } catch { entrada.removeTap(onBus: 0); return false }
        peticion = p
        tarea = rec.recognitionTask(with: p) { [weak self] r, _ in
            guard let t = r?.bestTranscription.formattedString, let d = EscuchaSiNo.decision(t) else { return }
            DispatchQueue.main.async {
                guard let self, !self.decidido else { return }
                self.decidido = true
                Log.write("confirmación por voz: \(d ? "sí" : "no")")
                self.alDecidir?(d)
            }
        }
        return true
    }

    func detener() {
        if motor.isRunning { motor.stop() }
        motor.inputNode.removeTap(onBus: 0)
        peticion?.endAudio(); tarea?.cancel()
        peticion = nil; tarea = nil
    }
}

enum ConfirmacionVoz {
    /// Igual que `ConfirmacionSegura.pedir`, pero Beto pregunta y se puede contestar de viva voz.
    static func pedir(_ titulo: String, detalle: String, pregunta: String, boton: String = "Aceptar") -> Bool {
        guard Config.agenteConfirmarVoz(), Thread.isMainThread else {
            return ConfirmacionSegura.pedir(titulo, detalle: detalle, boton: boton)
        }
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        alerta.messageText = titulo
        alerta.informativeText = detalle + "\n\n🎙️ También puedes decir «sí» o «no»."
        alerta.addButton(withTitle: boton)
        alerta.addButton(withTitle: "Cancelar")
        let escucha = EscuchaSiNo()
        var abierto = true
        escucha.alDecidir = { si in
            guard abierto else { return }
            NSApp.stopModal(withCode: si ? .alertFirstButtonReturn : .alertSecondButtonReturn)
        }
        // Escucha solo cuando Beto terminó de preguntar: así no se oye a sí mismo.
        Voz.decir(pregunta, completion: {
            RunLoop.main.perform(inModes: [.modalPanel, .default]) { if abierto { _ = escucha.iniciar() } }
        })
        NSApp.activate(ignoringOtherApps: true)
        let r = alerta.runModal()
        abierto = false
        escucha.detener()
        Voz.cancelar()
        return r == .alertFirstButtonReturn
    }
}
