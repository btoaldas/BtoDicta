import Foundation
import AVFoundation

// MARK: - TTS (texto → voz) — Fase 7.1: el sistema puede HABLARTE
//
// Primer ladrillo del Modo Agente. Motor por defecto = voz de macOS
// (AVSpeechSynthesizer): gratis, local, sin setup. Parametrizable (voz + velocidad).
// A futuro: ElevenLabs (nube) y voz clonada local, con failover — misma idea que STT.

enum TTS {
    private static let synth = AVSpeechSynthesizer()

    /// Voces en español instaladas en el Mac (para el selector).
    static func voces() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
            .sorted { $0.name < $1.name }
    }

    static func detener() { if synth.isSpeaking { synth.stopSpeaking(at: .immediate) } }
    static var hablando: Bool { synth.isSpeaking }

    /// Dice el texto con la voz/velocidad configuradas. `completion` al terminar.
    static func hablar(_ texto: String, completion: (() -> Void)? = nil) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { completion?(); return }
        // Trazable: antes no había forma de saber desde el log si el respaldo habló.
        Log.log(.ia, "TTS voz de macOS: hablando (\(t.count) caracteres)")
        DispatchQueue.main.async {
            detener()
            let u = AVSpeechUtterance(string: t)
            if !Config.ttsVoz().isEmpty, let v = AVSpeechSynthesisVoice(identifier: Config.ttsVoz()) {
                u.voice = v
            } else {
                u.voice = AVSpeechSynthesisVoice(language: "es-MX")
                    ?? AVSpeechSynthesisVoice(language: "es-ES")
                    ?? AVSpeechSynthesisVoice(language: "es")
            }
            u.rate = Float(Config.ttsVelocidad())   // 0 (min) … 1 (max); ~0.5 = normal
            if let completion { delegado.alTerminar = completion; synth.delegate = delegado }
            synth.speak(u)
        }
    }

    private static let delegado = TTSDelegate()
}

private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var alTerminar: (() -> Void)?
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let cb = alTerminar; alTerminar = nil; DispatchQueue.main.async { cb?() }
    }
}
