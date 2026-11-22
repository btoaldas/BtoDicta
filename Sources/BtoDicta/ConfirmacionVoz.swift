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
    private var ultimo = ""
    /// Alto riesgo: la voz solo aprueba con «confirmo» exacto.
    let estricta: Bool
    var alDecidir: ((Bool) -> Void)?

    init(estricta: Bool) { self.estricta = estricta }

    static let palabrasNo: Set<String> = ["no", "cancela", "cancelar", "cancelalo", "espera", "alto", "detente", "negativo", "nunca"]
    static let palabrasSi: Set<String> = ["si", "dale", "confirmo", "confirmado", "adelante", "hazlo", "envialo", "claro",
                                          "ok", "okay", "acepto", "procede", "correcto", "listo", "vale", "afirmativo"]

    /// «sí» → true, «no» → false, nada claro → nil (puro). Cualquier negación gana.
    /// Aprobar exige una respuesta corta (máx. 3 palabras); en modo estricto, «confirmo» exacto.
    static func decision(_ texto: String, estricta: Bool = false) -> Bool? {
        let n = PerfilAgente.normalizar(texto)
        let lista = n.split(separator: " ").map(String.init)
        let palabras = Set(lista)
        if !palabras.isDisjoint(with: palabrasNo) { return false }
        guard (1...3).contains(lista.count) else { return nil }
        if estricta { return palabras == ["confirmo"] || palabras == ["si", "confirmo"] ? true : nil }
        if !palabras.isDisjoint(with: palabrasSi) || n == "de acuerdo" || n == "por supuesto" { return true }
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
        p.contextualStrings = ["sí", "no", "dale", "cancela", "adelante", "confirmo"]
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { return false }
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { b, _ in p.append(b) }
        motor.prepare()
        do { try motor.start() } catch { entrada.removeTap(onBus: 0); return false }
        peticion = p
        tarea = rec.recognitionTask(with: p) { [weak self] r, _ in
            guard let t = r?.bestTranscription.formattedString else { return }
            DispatchQueue.main.async {
                guard let self, !self.decidido else { return }
                self.ultimo = t
                guard let d = EscuchaSiNo.decision(t, estricta: self.estricta) else { return }
                // Un «no» corta al instante; un «sí» solo vale si la frase no cambia en 0,9 s
                // (no es el comienzo de «sí… pero no»).
                if !d { self.decidir(false); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self, !self.decidido, self.ultimo == t else { return }
                    self.decidir(true)
                }
            }
        }
        return true
    }

    private func decidir(_ si: Bool) {
        decidido = true
        Log.write("confirmación por voz: \(si ? "sí" : "no")")
        alDecidir?(si)
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
    static func pedir(_ titulo: String, detalle: String, pregunta: String, boton: String = "Aceptar",
                      estricta: Bool = true) -> Bool {
        guard Config.agenteConfirmarVoz(), Thread.isMainThread else {
            return ConfirmacionSegura.pedir(titulo, detalle: detalle, boton: boton)
        }
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        alerta.messageText = titulo
        alerta.informativeText = detalle + (estricta ? "\n\n🎙️ Para aceptar de viva voz di «confirmo»; «no» cancela."
                                                     : "\n\n🎙️ También puedes decir «sí» o «no».")
        alerta.addButton(withTitle: boton)
        alerta.addButton(withTitle: "Cancelar")
        let escucha = EscuchaSiNo(estricta: estricta)
        var abierto = true
        escucha.alDecidir = { si in
            guard abierto else { return }
            NSApp.stopModal(withCode: si ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            // stopModal fuera de un evento no cierra hasta el próximo evento: se envía uno vacío.
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: true)
            }
        }
        // Escucha solo cuando Beto terminó de preguntar: así no se oye a sí mismo.
        Voz.decir(pregunta + (estricta ? " Di «confirmo» o «no»." : ""), completion: {
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
