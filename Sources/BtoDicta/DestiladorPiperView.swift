import SwiftUI
import AppKit

final class DestiladorPiperWindow {
    static var win: NSWindow?
    static var vozID = ""

    static func show(voz: VozLocal) {
        if let w = win, vozID == voz.id {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        win?.close(); vozID = voz.id
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Crear versión rápida ONNX · BtoDicta"
        w.center(); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: DestiladorPiperView(vozID: voz.id))
        win = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct DestiladorPiperView: View {
    let vozID: String
    @State private var cantidad = 600
    @State private var etapas = 3000
    @State private var calidad = "medium"
    @State private var preparando = false
    @State private var bajando = false
    @State private var trabajando = false
    @State private var generandoDataset = false
    @State private var validando = false
    @State private var fase = ""
    @State private var estado = ""
    @State private var proyecto: URL?
    @State private var snap: EntrenadorPiper.Snapshot?
    @State private var checkpoints: [(paso: Int, url: URL)] = []
    @State private var ranking: [EntrenadorPiper.RankPiper] = []
    @State private var timer: Timer?
    @State private var refresco = 0
    // Continuación tras un APAGADO: qué quedó a medias y qué toca al pulsar «Continuar».
    private enum Continuacion { case dataset, entrenar, validar }
    @State private var pendiente: Continuacion?
    @State private var pendienteTxt = ""

    private var voz: VozLocal? { VocesLocales.todas().first { $0.id == vozID } }
    private var opcion: DestiladorPiper.Tamano {
        DestiladorPiper.tamanos.first { $0.id == cantidad } ?? DestiladorPiper.tamanos[1]
    }
    private var motorListo: Bool { let _ = refresco; return VozEngine.estado() == .listo }
    private var entrenadorListo: Bool { let _ = refresco; return EntrenadorPiper.listo }
    private var baseLista: Bool { let _ = refresco; return EntrenadorPiper.baseListo(calidad) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crear versión rápida ONNX").font(.title3).bold()
                Text("Voz de origen: \(voz?.nombre ?? "no encontrada")").font(.subheadline)
                Text("No se cambia el archivo XTTS. BtoDicta hace una destilación local: XTTS habla frases conocidas, Piper aprende de ese audio limpio y se exporta a ONNX. La voz conserva sus dos variantes: Calidad XTTS y Rápida ONNX.")
                    .font(.caption).foregroundStyle(.secondary)

                // Continuación tras un apagado: nada se pierde, se retoma donde quedó.
                if pendiente != nil, !trabajando {
                    grupo {
                        Label("Hay una tanda a medias de esta voz", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).bold()
                        Text(pendienteTxt).font(.caption).foregroundStyle(.secondary)
                        Button("▶︎ Continuar donde quedó") {
                            let que = pendiente; pendiente = nil
                            switch que {
                            case .dataset: iniciar()
                            case .entrenar: reanudar()
                            case .validar: trabajando = true; generandoDataset = false; validarYVincular()
                            case .none: break
                            }
                        }.disabled(voz == nil || !entrenadorListo || !baseLista)
                    }
                }

                grupo {
                    Label("1. Herramientas locales", systemImage: "shippingbox")
                        .font(.subheadline).bold()
                    if !motorListo {
                        Text("Falta el motor local aislado de BtoDicta.").font(.caption)
                        Button(preparando ? "Instalando…" : "Instalar motor local") {
                            preparando = true; estado = "Preparando Python aislado…"
                            VozEngine.instalar(onProgreso: { s in DispatchQueue.main.async { estado = s } }) { _, msg in
                                preparando = false; estado = msg; refresco += 1
                            }
                        }.disabled(preparando)
                    } else if !entrenadorListo {
                        Text("El motor XTTS está listo; falta habilitar el entrenador Piper.").font(.caption)
                        Button(preparando ? "Preparando…" : "Preparar entrenador Piper") {
                            preparando = true; estado = "Preparando…"
                            EntrenadorPiper.preparar(onProgreso: { s in DispatchQueue.main.async { estado = s } }) { _, msg in
                                preparando = false; estado = msg; refresco += 1
                            }
                        }.disabled(preparando)
                    } else {
                        Text("✓ XTTS y entrenador Piper listos.").font(.caption).foregroundStyle(.green)
                    }
                    if entrenadorListo, !baseLista {
                        Button(bajando ? "Descargando…" : "Descargar base \(EntrenadorPiper.calidad(calidad).etiqueta)") {
                            bajando = true; estado = "Descargando base…"
                            EntrenadorPiper.descargarBase(calidadId: calidad, onProgreso: { s in DispatchQueue.main.async { estado = s } }) { _, msg in
                                bajando = false; estado = msg; refresco += 1
                            }
                        }.disabled(bajando)
                        Text("Se descarga una sola vez y solo al pulsar este botón.").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                grupo {
                    Label("2. Plan de destilación", systemImage: "slider.horizontal.3")
                        .font(.subheadline).bold()
                    Picker("Corpus", selection: $cantidad) {
                        ForEach(DestiladorPiper.tamanos) { t in Text(t.etiqueta).tag(t.id) }
                    }.pickerStyle(.segmented)
                        .onChange(of: cantidad) { _, _ in etapas = opcion.etapas }
                    Text(opcion.detalle).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Text("Actualizaciones:").font(.caption)
                        TextField("", value: $etapas, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 80)
                        Text("recomendadas \(opcion.etapas); tú decides").font(.caption2).foregroundStyle(.secondary)
                    }
                    Picker("Base", selection: $calidad) {
                        ForEach(EntrenadorPiper.calidades, id: \.id) { Text($0.etiqueta).tag($0.id) }
                    }.pickerStyle(.segmented)
                    Text(EntrenadorPiper.calidad(calidad).nota).font(.caption2).foregroundStyle(.secondary)
                    Text("Puedes cerrar esta ventana o BtoDicta: el entrenamiento continúa y se puede reanudar desde un checkpoint.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                grupo {
                    Label("3. Crear y comprobar", systemImage: "bolt.fill")
                        .font(.subheadline).bold()
                    if trabajando {
                        if let snap {
                            ProgressView(value: snap.avanceFase)
                            Text(snap.texto).font(.caption).monospacedDigit()
                            PiperAvanceMiniChart(puntos: snap.checkpointPuntos,
                                                  actual: snap.paso, total: snap.total)
                            let cols = [GridItem(.adaptive(minimum: 128), spacing: 6)]
                            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                                kpi("Paso real", "\(snap.paso) / \(snap.total)", "figure.walk")
                                kpi("Velocidad", snap.itPerSec > 0 ? String(format: "%.2f pasos/s", snap.itPerSec) : "calculando…", "speedometer")
                                kpi("Transcurrido", duracion(snap.transcurridoMin), "timer")
                                kpi("Falta", snap.etaMin > 0 ? "~\(duracion(snap.etaMin))" : "calculando…", "hourglass")
                                kpi("Fin estimado", snap.finEstimada?.formatted(date: .omitted, time: .shortened) ?? "—", "clock")
                                kpi("Checkpoints", "\(snap.hitos) hitos" + (snap.seguroPaso > 0 ? " · seguro \(snap.seguroPaso)" : ""), "flag.checkered")
                            }
                        } else {
                            ProgressView()
                            Text(fase).font(.caption)
                        }
                        Button("Detener (se puede continuar después)") { detener() }.controlSize(.small)
                    } else {
                        HStack {
                            Button(voz?.onnx.isEmpty == false ? "Recrear versión rápida" : "Crear versión rápida") { iniciar() }
                                .disabled(voz == nil || !entrenadorListo || !baseLista || etapas < 50)
                            if let p = proyecto, EntrenadorPiper.ultimoCheckpoint(p) != nil, !EntrenadorPiper.termino(p) {
                                Button("Reanudar") { reanudar() }
                            }
                            Button("Vista avanzada") { EntrenadorPiperWindow.show() }.controlSize(.small)
                        }
                    }
                    if validando { Text("Validando inteligibilidad y parecido antes de activar…").font(.caption) }
                    if !ranking.isEmpty, let r = ranking.first {
                        Text("Mejor corte: paso \(r.paso) · inteligibilidad \(Int(r.inteligible*100))% · parecido \(Int(r.parecido*100))%")
                            .font(.caption)
                    }
                    if !estado.isEmpty { Text(estado).font(.caption).foregroundStyle(.secondary) }
                    if let p = proyecto {
                        Text("Proyecto: \(p.path)").font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                    }
                }

                if voz?.onnx.isEmpty == false {
                    Label("Esta voz ya tiene XTTS + ONNX. Elige cuál usar en la biblioteca de voces.", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }.padding(16)
        }
        .onAppear {
            guard let v = voz else { return }
            let p = DestiladorPiper.proyecto(v); proyecto = p

            // Restaurar PRIMERO el plan exacto. El archivo se guarda antes del primer clip;
            // calidad.txt y piper.log lo sustituyen cuando el entrenamiento ya arrancó.
            let planGuardado = DestiladorPiper.planGuardado(p)
            if let plan = planGuardado {
                if plan.cantidad > 0 { cantidad = plan.cantidad }
                etapas = min(100_000, max(50, plan.etapas))
                if EntrenadorPiper.calidades.contains(where: { $0.id == plan.calidad }) {
                    calidad = plan.calidad
                }
            }
            let corpusTxt = (try? String(contentsOf: p.appendingPathComponent("corpus-xtts.txt"), encoding: .utf8)) ?? ""
            let total = corpusTxt.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            if total > 0 { cantidad = total }
            if planGuardado == nil,
               FileManager.default.fileExists(atPath: p.appendingPathComponent("piper.log").path) {
                etapas = EntrenadorPiper.etapasDe(p)
            } else if planGuardado == nil,
                      let t = DestiladorPiper.tamanos.first(where: { $0.id == total }) {
                etapas = t.etapas
            }
            if let cal = (try? String(contentsOf: p.appendingPathComponent("calidad.txt"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               EntrenadorPiper.calidades.contains(where: { $0.id == cal }) { calidad = cal }

            if DestiladorPiper.procesoVivo(p) {
                trabajando = true; generandoDataset = true
                fase = "XTTS está creando el dataset exacto…"
                estado = "La destilación siguió viva; retomé su progreso sin lanzar otra copia."
                seguirDatasetActivo(total: max(total, cantidad))
                return
            }
            if EntrenadorPiper.procesoVivo(p) {
                trabajando = true; generandoDataset = false; fase = "Entrenando"; seguir()
                return
            }
            // Tras un APAGADO nada queda vivo, pero TODO queda en disco (clips válidos,
            // checkpoints). Detectamos en qué quedó la tanda y dejamos la vista lista
            // para CONTINUAR sin perder nada — respetando el tamaño y la calidad
            // ORIGINALES (el corpus es determinista: mismo tamaño → corpus idéntico).
            guard total > 0 else { return }
            let clips = DestiladorPiper.clipsListos(p)
            let cks = EntrenadorPiper.checkpoints(p)
            let tieneCkpt = EntrenadorPiper.ultimoCheckpoint(p) != nil
            if tieneCkpt, EntrenadorPiper.termino(p), voz?.onnx.isEmpty ?? true {
                pendiente = .validar
                pendienteTxt = "El entrenamiento TERMINÓ; falta validar, elegir el mejor corte y activar la voz."
            } else if tieneCkpt {
                pendiente = .entrenar
                let paso = EntrenadorPiper.pasoUltimoCheckpoint(p)
                pendienteTxt = cks.isEmpty
                    ? "Entrenamiento a medias (seguro en el paso \(paso)). Continúa sin empezar de cero."
                    : "Entrenamiento a medias (\(cks.count) cortes; último seguro: paso \(paso)). Continúa desde el más reciente."
            } else if clips < total {
                pendiente = .dataset
                pendienteTxt = "Dataset a medias: \(clips) de \(total) frases ya generadas — se reutilizan, no se pierde nada."
            } else {
                pendiente = .dataset   // dataset completo: iniciar() lo detecta y pasa directo a entrenar
                pendienteTxt = "Dataset completo (\(clips) frases). Falta el entrenamiento."
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    @ViewBuilder private func grupo<C: View>(@ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) { contenido() }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06)).cornerRadius(8)
    }

    @ViewBuilder private func kpi(_ titulo: String, _ valor: String, _ icono: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icono).foregroundStyle(.secondary).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(valor).font(.caption2).monospacedDigit().lineLimit(1)
            }
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05)).cornerRadius(6)
    }

    private func duracion(_ minutos: Int) -> String {
        guard minutos > 0 else { return "—" }
        let h = minutos / 60, m = minutos % 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    private func iniciar() {
        guard let v = voz else { return }
        let p = DestiladorPiper.proyecto(v)
        do {
            try DestiladorPiper.guardarPlan(
                .init(cantidad: cantidad, etapas: etapas, calidad: calidad), en: p
            )
        } catch {
            estado = "No pude guardar el plan de destilación: \(error.localizedDescription)"
            trabajando = false
            return
        }
        trabajando = true; generandoDataset = true; snap = nil; ranking = []; fase = "XTTS está creando el dataset exacto…"
        estado = "Los clips válidos existentes se reutilizan."
        DestiladorPiper.prepararDataset(voz: v, cantidad: cantidad, calidadId: calidad,
            onProgreso: { estado = $0 }, completion: { ok, msg, p, _ in
                timer?.invalidate(); timer = nil
                proyecto = p; estado = msg; generandoDataset = false
                guard ok else { trabajando = false; return }
                arrancarEntreno(v, reanudar: false)
            })
    }

    private func arrancarEntreno(_ v: VozLocal, reanudar: Bool) {
        fase = reanudar ? "Reanudando Piper…" : "Entrenando Piper con optimizadores frescos…"
        EntrenadorPiper.entrenar(carpeta: nil, nombre: v.nombre, stamp: DestiladorPiper.stamp(v),
                                 etapas: etapas, calidadId: calidad, reanudar: reanudar,
            onProgreso: { fase = $0.texto },
            onArranco: { ok, msg, p in
                proyecto = p; estado = msg
                if ok { fase = "Entrenando Piper"; seguir() }
                else { trabajando = false }
            })
    }

    private func reanudar() {
        guard let v = voz else { return }
        trabajando = true; generandoDataset = false; arrancarEntreno(v, reanudar: true)
    }

    private func seguir() {
        timer?.invalidate(); tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in tick() }
    }

    private func seguirDatasetActivo(total: Int) {
        timer?.invalidate()
        func revisar() {
            guard let p = proyecto else { return }
            DispatchQueue.global(qos: .utility).async {
                let clips = DestiladorPiper.clipsListos(p)
                let vivo = DestiladorPiper.procesoVivo(p)
                DispatchQueue.main.async {
                    guard generandoDataset else { return }
                    estado = "Dataset: \(clips) de \(total) frases listas."
                    guard !vivo else { return }
                    timer?.invalidate(); trabajando = false; generandoDataset = false
                    pendiente = .dataset
                    pendienteTxt = clips >= total
                        ? "Dataset completo (\(clips) frases). Falta iniciar el entrenamiento."
                        : "Dataset a medias: \(clips) de \(total) frases — continúa sin repetir las válidas."
                }
            }
        }
        revisar()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in revisar() }
    }

    private func tick() {
        guard let p = proyecto else { return }
        let total = etapas
        DispatchQueue.global(qos: .utility).async {
            let s = EntrenadorPiper.snapshot(p, etapas: total)
            let ck = EntrenadorPiper.checkpoints(p)
            DispatchQueue.main.async {
                snap = s; checkpoints = ck
                if s.termino {
                    timer?.invalidate(); validarYVincular()
                } else if !s.activo, EntrenadorPiper.ultimoCheckpoint(p) != nil {
                    timer?.invalidate(); trabajando = false
                    estado = "El entrenamiento se detuvo. Puedes reanudarlo desde el último checkpoint."
                }
            }
        }
    }

    private func validarYVincular() {
        guard !validando, let p = proyecto, let v = voz else { return }
        validando = true; fase = "Validando el resultado"; estado = "BtoDicta no activará una voz ininteligible."
        EntrenadorPiper.validar(p, onProgreso: { estado = $0 }) { ok in
            ranking = ok ? EntrenadorPiper.rankingPiper(p) : []
            guard let mejor = ranking.first, let ckpt = mejor.ckpt, mejor.inteligible >= 0.75 else {
                validando = false; trabajando = false
                estado = "No se vinculó: ningún corte superó 75% de inteligibilidad. No sigas sumando pasos a ciegas; revisa la vista avanzada."
                return
            }
            estado = "Exportando el mejor corte a ONNX…"
            EntrenadorPiper.exportarYregistrar(proyecto: p, checkpoint: ckpt, nombre: v.nombre,
                                               prompt: v.persona, stamp: "destila-final",
                                               vozExistenteId: v.id) { _, msg in
                validando = false; trabajando = false; fase = "Completado"; estado = msg; refresco += 1
            }
        }
    }

    private func detener() {
        timer?.invalidate()
        if generandoDataset {
            DestiladorPiper.detener(); trabajando = false; estado = "Destilación detenida; los clips válidos quedaron guardados."
        } else if let p = proyecto {
            EntrenadorPiper.detenerProyecto(p) { _ in
                trabajando = false; estado = "Entrenamiento detenido; puedes reanudarlo después."
            }
        }
    }
}

/// Línea pequeña y honesta: muestra PASOS contra TIEMPO. No pretende medir calidad;
/// esa curva aparece únicamente después de validar los cortes con Whisper + d-vector.
private struct PiperAvanceMiniChart: View {
    let puntos: [EntrenadorPiper.CheckpointInfo]
    let actual: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Avance por tiempo · la calidad se valida aparte")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Canvas { context, size in
                let orden = puntos.sorted { $0.fecha < $1.fecha }
                let muestras = orden.map { ($0.fecha, $0.paso, $0.seguro) }
                    + [(Date(), actual, false)]
                guard !muestras.isEmpty, total > 0 else { return }
                let t0 = muestras.first!.0.timeIntervalSinceReferenceDate
                let t1 = max(t0 + 1, muestras.last!.0.timeIntervalSinceReferenceDate)
                func punto(_ fecha: Date, _ paso: Int) -> CGPoint {
                    let x = (fecha.timeIntervalSinceReferenceDate - t0) / (t1 - t0)
                    let y = min(1, max(0, Double(paso) / Double(total)))
                    return CGPoint(x: 5 + x * (size.width - 10), y: size.height - 5 - y * (size.height - 10))
                }
                var linea = Path()
                for (i, m) in muestras.enumerated() {
                    let p = punto(m.0, m.1)
                    if i == 0 { linea.move(to: p) } else { linea.addLine(to: p) }
                }
                context.stroke(linea, with: .color(.accentColor), lineWidth: 2)
                for m in muestras {
                    let p = punto(m.0, m.1)
                    let r = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: r), with: .color(m.2 ? .orange : .accentColor))
                }
            }.frame(height: 54)
            if !puntos.isEmpty {
                Text(puntos.sorted { $0.paso < $1.paso }.map {
                    $0.seguro ? "seguro \($0.paso)" : "hito \($0.paso)"
                }.joined(separator: "  ·  "))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }.padding(6).background(Color.secondary.opacity(0.035)).cornerRadius(6)
    }
}
