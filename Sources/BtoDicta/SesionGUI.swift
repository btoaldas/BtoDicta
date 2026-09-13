import CoreGraphics
import Foundation

/// Detecta si el proceso corre dentro de una sesión gráfica (Aqua) válida.
/// Lanzado por SSH, por launchd de fondo o dentro del sandbox de un agente
/// (Codex/ChatGPT) no hay sesión: AppKit aborta en _RegisterApplication al
/// primer contacto con la barra de menú (SIGABRT, 10 crashes el 17–18 jul).
/// CGSessionCopyCurrentDictionary devuelve nil sin abortar, por eso es la
/// sonda segura; SSH_CONNECTION cubre el caso remoto por si la sesión
/// heredada aún respondiera.
enum SesionGUI {
    static let disponible: Bool = {
        guard ProcessInfo.processInfo.environment["SSH_CONNECTION"] == nil else { return false }
        guard let sesion = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        // Sesión en consola = dueña del WindowServer (no loginwindow/FUS).
        return (sesion[kCGSessionOnConsoleKey] as? Bool) ?? false
    }()
}
