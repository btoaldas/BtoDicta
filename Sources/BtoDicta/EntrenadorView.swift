import SwiftUI
import AppKit

// MARK: - GUI del entrenador de clones de voz
//
// Flujo: motor listo → elegir carpeta + nombre → analizar duración → plan recomendado
// (editable) → Entrenar (background, progreso) → Validar → ranking (escuchar/elegir el
// mejor) → Emitir paquete. Sistema recomienda, usuario decide.

final class EntrenadorWindow {
    static var win: NSWindow?
    static func show() {
        if let w = win { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Entrenar una voz · BtoDicta"
        w.center(); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: EntrenadorView())
        win = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct EntrenadorView: View {
    @State private var motor = VozEngine.entrenoListo
    @State private var instalando = false
    @State private var progresoMotor = ""

    @State private var carpeta: URL?
    @State private var nombre = ""
    @State private var minutos: Double = 0
    @State private var plan: PlanEntrenamiento?
    @State private var etapas = 0

    @State private var entrenando = false
    @State private var faseTxt = ""
    @State private var proyecto: URL?
    @State private var timer: Timer?

    @State private var ranking: [Entrenador.RankCheckpoint] = []
    @State private var estado = ""
    @State private var prog = Entrenador.Progreso(fase: "", paso: 0, total: 0, texto: "")
    private let acento = Color.accentColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Entrenar una voz clonada").font(.title3).bold()

                // 1) Motor de entrenamiento
                if !motor {
                    grupo {
                        Text("El motor de entrenamiento (Whisper + entrenador XTTS) no está listo.").font(.caption)
                        if instalando { Text(progresoMotor).font(.caption2).foregroundStyle(.secondary) }
                        Button("⬇︎ Preparar el entrenamiento") {
                            instalando = true; progresoMotor = "Empezando…"
                            VozEngine.instalarEntrenamiento(onProgreso: { l in progresoMotor = l },
                                completion: { ok, msg in instalando = false; progresoMotor = msg; motor = VozEngine.entrenoListo })
                        }.disabled(instalando)
                    }
                }

                // 2) Carpeta + nombre + plan
                grupo {
                    HStack {
                        Button("📁 Elegir carpeta de audios") { elegirCarpeta() }
                        Text(carpeta?.lastPathComponent ?? "ninguna").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Nombre:").font(.caption).frame(width: 60, alignment: .leading)
                        TextField("ej. Mi voz", text: $nombre).textFieldStyle(.roundedBorder).frame(width: 240)
                    }
                    if let plan {
                        Divider()
                        Text("\(String(format: "%.0f", minutos)) min de audio — \(plan.tier)").font(.subheadline)
                        Text(plan.aviso).font(.caption2).foregroundStyle(.secondary)
                        if plan.permitido {
                            HStack {
                                Text("Etapas:").font(.caption)
                                TextField("", value: $etapas, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                                Text("(recomendado \(plan.etapasRecomendadas); checkpoints \(plan.checkpoints.map(String.init).joined(separator: "·")))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("Estimado ~\(String(format: "%.1f", Entrenador.horasEstimadas(etapas: etapas))) h (CPU). El sistema recomienda, tú decides.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button(entrenando ? "Entrenando…" : "🚀 Entrenar") { entrenar() }
                                .disabled(entrenando || nombre.isEmpty || !motor)
                        }
                    }
                }

                // 3) Progreso EN VIVO
                if entrenando || !faseTxt.isEmpty {
                    grupo {
                        Text("Progreso").font(.subheadline)
                        if prog.total > 0 {
                            ProgressView(value: Double(prog.paso), total: Double(prog.total)).tint(acento)
                        } else if entrenando {
                            ProgressView().controlSize(.small)
                        }
                        Text(faseTxt).font(.caption).monospacedDigit()
                        if entrenando { Button("Detener") { Entrenador.detener(); entrenando = false; timer?.invalidate() }.controlSize(.small) }
                    }
                }

                // 4) Validación + ranking (elegir el mejor)
                if let proyecto {
                    grupo {
                        HStack {
                            Text("Elegir el mejor").font(.subheadline); Spacer()
                            Button("Validar (comparar checkpoints)") {
                                estado = "Validando… (genera y compara, tarda)"
                                Entrenador.validar(proyecto: proyecto, onProgreso: { estado = $0 },
                                    onFin: { ok in estado = ok ? "Listo — elige abajo" : "No se pudo validar"
                                        ranking = Entrenador.rankingValidacion(proyecto: proyecto) })
                            }.controlSize(.small)
                        }
                        // Gráfica de validación (validacion.png) si existe.
                        if let img = graficaValidacion() {
                            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 240)
                                .cornerRadius(6)
                        }
                        ForEach(Array(ranking.enumerated()), id: \.offset) { i, c in
                            HStack {
                                Text("\(i == 0 ? "🏆 " : "")checkpoint \(c.etapa)").font(.caption)
                                Text("· \(String(format: "%.3f", c.score))").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                if let r = c.ruta {
                                    Button("🔊") { escuchar(r, etapa: c.etapa) }.controlSize(.mini)
                                    Button("Usar este") { emitir(r) }.controlSize(.mini)
                                    Button("🗑") { borrarCheckpoint(r) }.controlSize(.mini).help("Borrar este descartado")
                                }
                            }
                        }
                    }
                }

                if !estado.isEmpty { Text(estado).font(.caption).foregroundStyle(.secondary) }
            }.padding(16)
        }
    }

    @ViewBuilder private func grupo<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { c() }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06)).cornerRadius(8)
    }

    private func elegirCarpeta() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        guard p.runModal() == .OK, let u = p.url else { return }
        carpeta = u; if nombre.isEmpty { nombre = u.lastPathComponent }
        estado = "Midiendo la duración del audio…"
        DispatchQueue.global().async {
            let m = Entrenador.duracionMinutos(u)
            DispatchQueue.main.async {
                minutos = m; let pl = Entrenador.recomendar(minutos: m); plan = pl
                etapas = pl.etapasRecomendadas; estado = ""
            }
        }
    }

    private func entrenar() {
        guard let carpeta else { return }
        entrenando = true; faseTxt = "Preparando…"
        Entrenador.entrenar(carpeta: carpeta, nombre: nombre, stamp: marca(), etapas: etapas,
            onProgreso: { p in faseTxt = "\(p.fase): \(p.texto)" },
            onArranco: { ok, msg in
                faseTxt = msg
                if ok { proyecto = Entrenador.proyectosDir.appendingPathComponent("\(Entrenador.slug(nombre))_\(marcaFija)")
                    seguirProgreso() } else { entrenando = false }
            })
    }

    @State private var marcaFija = ""
    private func marca() -> String { if marcaFija.isEmpty { marcaFija = "run" }; return marcaFija }

    private func seguirProgreso() {
        timer?.invalidate()
        // Estado del train EN VIVO: relee train.log cada 3s (paso/total/loss + barra).
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            guard let proyecto else { return }
            let p = Entrenador.leerProgreso(proyecto)
            prog = p; faseTxt = "train: \(p.texto)"
        }
    }

    private func escuchar(_ ckpt: URL, etapa: Int) {
        guard let proyecto else { return }
        estado = "Generando muestra del checkpoint \(etapa)…"
        // gen.py directo → wav → reproducir.
        DispatchQueue.global().async {
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("escuchar_\(etapa).wav")
            let clonar = VozEngine.pipelineDir.appendingPathComponent("clonar")
            let pr = Process(); pr.executableURL = VozEngine.pythonURL
            pr.arguments = [clonar.appendingPathComponent("gen.py").path, proyecto.path, ckpt.path,
                            "Hola, esta es una muestra de mi voz.", out.path]
            var env = ProcessInfo.processInfo.environment; env["COQUI_TOS_AGREED"] = "1"; pr.environment = env
            pr.standardOutput = FileHandle.nullDevice; pr.standardError = FileHandle.nullDevice
            try? pr.run(); pr.waitUntilExit()
            DispatchQueue.main.async {
                estado = ""
                if FileManager.default.fileExists(atPath: out.path) { NSSound(contentsOf: out, byReference: true)?.play() }
            }
        }
    }

    private func emitir(_ ckpt: URL) {
        guard let proyecto else { return }
        estado = "Emitiendo el paquete…"
        Entrenador.emitirPaquete(proyecto: proyecto, checkpoint: ckpt, nombre: nombre, stamp: "final") { r in
            switch r {
            case .ok(let v): estado = "✓ Voz “\(v.nombre)” lista y agregada a tu biblioteca."
            case .faltaMuestras(let v): estado = "“\(v.nombre)” agregada; agrega muestras si hace falta."
            case .faltaModelo: estado = "No pude emitir (falta el modelo)."
            }
        }
    }

    private func graficaValidacion() -> NSImage? {
        guard let proyecto else { return nil }
        let png = proyecto.appendingPathComponent("validacion.png")
        return FileManager.default.fileExists(atPath: png.path) ? NSImage(contentsOf: png) : nil
    }

    private func borrarCheckpoint(_ ckpt: URL) {
        guard ConfirmacionSegura.pedir("¿Enviar este checkpoint a la Papelera?",
            detalle: "Checkpoint \(ckpt.deletingPathExtension().lastPathComponent). Las demás etapas, la voz emitida y el proyecto permanecen intactos; macOS permitirá recuperarlo.",
            boton: "Enviar a Papelera") else { return }
        NSWorkspace.shared.recycle([ckpt]) { _, error in
            DispatchQueue.main.async {
                if let error { estado = "No se quitó: \(error.localizedDescription)" }
                else {
                    ranking.removeAll { $0.ruta == ckpt }
                    estado = "Checkpoint enviado a la Papelera de macOS."
                }
            }
        }
    }
}
