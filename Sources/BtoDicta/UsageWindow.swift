import AppKit
import SwiftUI

/// Detalle desplazable del consumo. El menú principal conserva únicamente las
/// tres filas más usadas para no crecer hasta ocupar toda la pantalla.
struct UsageDetailView: View {
    let lineas: [String]
    private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(acento)
                Text("Consumo de transcripción")
                    .font(.headline)
                Spacer()
                Text("Todos los motores")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lineas.enumerated()), id: \.offset) { indice, linea in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(indice + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(linea)
                                .font(.system(size: 12.5))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        if indice + 1 < lineas.count { Divider().padding(.leading, 34) }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: 270)

            Divider()

            HStack {
                Text("Ordenado por uso acumulado")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Abrir Estadísticas") {
                    SettingsWindowController.shared.show(irA: "Estadísticas")
                }
                .buttonStyle(.borderedProminent)
                .tint(acento)
            }
        }
        .padding(18)
        .frame(width: 700, height: 380)
    }
}

final class UsageWindowController {
    static let shared = UsageWindowController()
    private var window: NSWindow?

    func show() {
        let hosting = NSHostingController(rootView: UsageDetailView(lineas: UsageLog.resumen()))
        if let window {
            window.contentViewController = hosting
        } else {
            let nueva = NSWindow(contentViewController: hosting)
            nueva.title = "Consumo de BtoDicta"
            nueva.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            nueva.setContentSize(NSSize(width: 700, height: 380))
            nueva.minSize = NSSize(width: 580, height: 300)
            nueva.isReleasedWhenClosed = false
            window = nueva
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
