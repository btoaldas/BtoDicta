import AppKit

/// Confirmación uniforme para operaciones capaces de ocultar, reemplazar o quitar
/// trabajo de voz. Centralizarla evita que un botón nuevo vuelva a quedar destructivo.
enum ConfirmacionSegura {
    static func pedir(_ titulo: String, detalle: String,
                      boton: String = "Continuar") -> Bool {
        let mostrar: () -> Bool = {
            let alerta = NSAlert()
            alerta.alertStyle = .warning
            alerta.messageText = titulo
            alerta.informativeText = detalle
            alerta.addButton(withTitle: boton)
            alerta.addButton(withTitle: "Cancelar")
            return alerta.runModal() == .alertFirstButtonReturn
        }
        if Thread.isMainThread { return mostrar() }
        var respuesta = false
        DispatchQueue.main.sync { respuesta = mostrar() }
        return respuesta
    }

    static func nombreVariante(_ id: String) -> String {
        switch id {
        case "maxima": return "✨ Máxima"
        case "mlx": return "⚖️ Equilibrada"
        case "onnx": return "⚡ Rápida"
        default: return "Calidad XTTS"
        }
    }
}
