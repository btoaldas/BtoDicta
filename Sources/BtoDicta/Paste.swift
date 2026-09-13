import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox

/// Evita que un Enter programado por otro dictado caiga sobre un adjunto de
/// WhatsApp recién pegado. El autoenvío explícito usa el botón AX Enviar y no
/// pasa por este mecanismo.
enum SeguridadTeclado {
    private static let lock = NSLock()
    private static var retornoBloqueadoHasta = Date.distantPast

    static func bloquearRetorno(durante segundos: TimeInterval) {
        lock.lock()
        retornoBloqueadoHasta = max(retornoBloqueadoHasta,
                                    Date().addingTimeInterval(max(0, segundos)))
        lock.unlock()
    }

    static var retornoPermitido: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() >= retornoBloqueadoHasta
    }
}

// MARK: - Pegado (clipboard + Cmd+V, restaurando lo que había)

func copyText(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func pasteText(_ text: String, restaurar: Bool = true) {
    if !AXIsProcessTrusted() {
        Log.write("⚠️ PEGADO BLOQUEADO: falta permiso de Accesibilidad para BtoDicta")
    }
    let pb = NSPasteboard.general
    let previous = pb.string(forType: .string)
    pb.clearContents()
    pb.setString(text, forType: .string)

    let src = CGEventSource(stateID: .combinedSessionState)
    let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    vDown?.flags = .maskCommand
    vUp?.flags = .maskCommand
    vDown?.post(tap: .cghidEventTap)
    vUp?.post(tap: .cghidEventTap)

    if restaurar {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let previous {
                pb.clearContents()
                pb.setString(previous, forType: .string)
            }
        }
    }
}

/// Pega exactamente lo que YA está en el portapapeles (texto, imagen o archivo).
/// Se usa al abrir un chat resuelto de WhatsApp. Nunca pulsa Return/Enviar.
@discardableResult
func presionarPegarPortapapeles() -> Bool {
    guard AXIsProcessTrusted() else {
        Log.write("⚠️ PEGADO DE ARCHIVO BLOQUEADO: falta permiso de Accesibilidad")
        return false
    }
    let src = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: src,
                             virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
          let up = CGEvent(keyboardEventSource: src,
                           virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
    down.flags = .maskCommand; up.flags = .maskCommand
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    return true
}

/// Pulsa ⌘N (nuevo ítem) — para las acciones que crean nota/recordatorio/documento.
func presionarNuevo() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: false)
    down?.flags = .maskCommand; up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

/// Abre Spotlight (⌘Espacio) — para el modo Buscar en la Mac.
func abrirSpotlight() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
    down?.flags = .maskCommand; up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

/// Pulsa Return (o Shift+Return) — para los flags "Enter / Shift+Enter al
/// terminar el dictado". Se llama con un pequeño retraso tras pegar.
func presionarRetorno(shift: Bool) {
    guard SeguridadTeclado.retornoPermitido else {
        Log.write("↳ Enter automático omitido: hay un adjunto sensible en preparación")
        return
    }
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
    if shift { down?.flags = .maskShift; up?.flags = .maskShift }
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}
