import SwiftUI
import AppKit

// MARK: - GUI del entrenador PIPER (voz fija rápida .onnx)
//
// Flujo: preparar entrenador → elegir carpeta + nombre + persona/prompt → plan
// recomendado (editable) → Entrenar (fine-tune CPU en background, RESUMIBLE) → progreso
// en vivo → checkpoints (escuchar / elegir el mejor / exportar como voz ⚡ / descartar).
// Si se apaga la compu, al volver ofrece REANUDAR el proyecto a medias.

final class EntrenadorPiperWindow {
    static var win: NSWindow?
    static func show() {
        if let w = win { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Entrenar una voz Piper (rápida) · BtoDicta"
        w.center(); w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: EntrenadorPiperView())
        win = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct EntrenadorPiperView: View {
    @State private var listo = EntrenadorPiper.listo
    @State private var preparando = false
    @State private var progresoPrep = ""

    @State private var carpeta: URL?
    @State private var nombre = ""
    @State private var persona = ""
    @State private var minutos: Double = 0
    @State private var plan: PlanEntrenamiento?
    @State private var etapas = 0

    @State private var entrenando = false
    @State private var faseTxt = ""
    @State private var proyecto: URL?
    @State private var timer: Timer?
    @State private var pasoActual = 0
    @State private var pctVivo: Double = 0
    @State private var snap: EntrenadorPiper.Snapshot?
    @State private var deteniendo = false
    @State private var pulso = false

    @State private var checkpoints: [(paso: Int, url: URL)] = []
    @State private var ranking: [EntrenadorPiper.RankPiper] = []
    @State private var validando = false
    @State private var valEstado = ""
    @State private var estado = ""
    @State private var reanudable: URL?
    @State private var calidad = "medium"
    @State private var bajandoBase = false
    @State private var baseListaTick = 0   // fuerza refresco tras descargar base
    private let acento = Color.accentColor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Entrenar una voz Piper (rápida)").font(.title3).bold()
                Text("Piper hornea una voz FIJA que luego habla casi al instante (~5× tiempo real, sin torch). XTTS se queda para clonar al vuelo con más calidad.")
                    .font(.caption2).foregroundStyle(.secondary)

                // 0) Motor de entrenamiento Piper (vits/monotonic)
                if !listo {
                    grupo {
                        Text("El entrenador de Piper no está listo (falta preparar vits/monotonic).").font(.caption)
                        if preparando { Text(progresoPrep).font(.caption2).foregroundStyle(.secondary) }
                        Button("⬇︎ Preparar el entrenador") {
                            preparando = true; progresoPrep = "Empezando…"
                            EntrenadorPiper.preparar(onProgreso: { progresoPrep = $0 },
                                completion: { ok, msg in preparando = false; progresoPrep = msg; listo = EntrenadorPiper.listo })
                        }.disabled(preparando)
                    }
                }

                // 0b) Reanudar un proyecto a medias (tras apagón)
                if let r = reanudable, !entrenando {
                    grupo {
                        Text("Hay un entrenamiento a medias: \(r.lastPathComponent).").font(.caption)
                        Button("▶︎ Reanudar donde quedó") { reanudar(r) }.controlSize(.small)
                    }
                }

                // 1) Carpeta + nombre + persona + plan
                grupo {
                    HStack {
                        Button("📁 Elegir carpeta de audios") { elegirCarpeta() }
                        Text(carpeta?.lastPathComponent ?? "ninguna").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Nombre:").font(.caption).frame(width: 70, alignment: .leading)
                        TextField("ej. Mi voz rápida", text: $nombre).textFieldStyle(.roundedBorder).frame(width: 240)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Persona / prompt (cómo habla — opcional):").font(.caption)
                        TextEditor(text: $persona).frame(height: 54).font(.caption2)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                        Text("Si lo dejas vacío, se genera de los audios.").font(.caption2).foregroundStyle(.secondary)
                    }
                    // Calidad (parametrizable: media / alta / baja)
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Picker("Calidad:", selection: $calidad) {
                            ForEach(EntrenadorPiper.calidades, id: \.id) { c in Text(c.etiqueta).tag(c.id) }
                        }.pickerStyle(.segmented).frame(width: 340)
                        Text(EntrenadorPiper.calidad(calidad).nota).font(.caption2).foregroundStyle(.secondary)
                        let _ = baseListaTick   // engancha el refresco
                        if !EntrenadorPiper.baseListo(calidad) {
                            HStack {
                                Button("⬇︎ Descargar base (\(EntrenadorPiper.calidad(calidad).etiqueta))") { bajarBase() }
                                    .disabled(bajandoBase).controlSize(.small)
                                if bajandoBase { ProgressView().controlSize(.mini) }
                            }
                            Text("Se baja una sola vez (~0.8–1 GB) desde rhasspy/piper-checkpoints, con tu permiso.").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("✓ Base de calidad \(EntrenadorPiper.calidad(calidad).etiqueta) lista.").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    if let plan {
                        Divider()
                        Text("\(String(format: "%.0f", minutos)) min de audio — \(plan.tier)").font(.subheadline)
                        Text(plan.aviso).font(.caption2).foregroundStyle(.secondary)
                        if plan.permitido {
                            HStack {
                                Text("Etapas:").font(.caption)
                                TextField("", value: $etapas, format: .number).textFieldStyle(.roundedBorder).frame(width: 70)
                                Text("(recomendado \(plan.etapasRecomendadas))").font(.caption2).foregroundStyle(.secondary)
                            }
                            Text("Estimado ~\(String(format: "%.1f", EntrenadorPiper.horasEstimadas(etapas: etapas))) h (CPU, fine-tune sobre la base). El sistema recomienda, tú decides.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button(entrenando ? "Entrenando…" : "🚀 Entrenar") { entrenar() }
                                .disabled(entrenando || nombre.isEmpty || !listo || !EntrenadorPiper.baseListo(calidad))
                        }
                    }
                }

                // 2) Bitácora VIVA (fase + % + métricas + registro que se imprime solo)
                if entrenando || !faseTxt.isEmpty {
                    grupo {
                        HStack {
                            Text(snap.map { "Bitácora · Fase \($0.fase)/2" } ?? "Bitácora").font(.subheadline)
                            Spacer()
                            if let s = snap, s.activo {
                                Circle().fill(.green).frame(width: 8, height: 8)
                                    .opacity(pulso ? 1 : 0.25)
                                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulso)
                                Text("procesando").font(.caption2).foregroundStyle(.green)
                            }
                        }
                        // Avance GLOBAL (todo el trabajo) + avance de la FASE actual
                        if let s = snap {
                            barra("Avance global", s.avanceGlobal, .green)
                            barra("Fase \(s.fase)/2 · \(s.subfase)", s.avanceFase, acento)
                        } else if entrenando { ProgressView().controlSize(.small) }
                        Text(faseTxt).font(.caption).monospacedDigit().foregroundStyle(.secondary)

                        // Métricas vivas (contadores + recursos + latencia)
                        if let s = snap {
                            let cols = [GridItem(.adaptive(minimum: 104), spacing: 6)]
                            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                                metrica("Motor", s.motor, "gearshape")
                                if s.fase == 2 {
                                    metrica("Paso", "\(s.paso) / \(s.total)", "figure.walk")
                                    metrica("Época", "\(s.epoca)", "repeat")
                                    metrica("Velocidad", s.itPerSec > 0 ? String(format: "%.2f pasos/s", s.itPerSec) : "calculando…", "speedometer")
                                    metrica("Transcurrido", tiempo(s.transcurridoMin), "timer")
                                    metrica("ETA", s.etaMin > 0 ? "~\(tiempo(s.etaMin))" : "—", "clock")
                                    metrica("Fin estimado", s.finEstimada?.formatted(date: .omitted, time: .shortened) ?? "—", "calendar.badge.clock")
                                    metrica("Checkpoints", "\(s.hitos) hitos" + (s.seguroPaso > 0 ? " · seguro \(s.seguroPaso)" : ""), "flag.checkered")
                                } else {
                                    metrica("Archivos", "\(s.paso) / \(s.total)", "waveform")
                                    metrica("Fragmentos", "\(s.clips)", "scissors")
                                    if !s.rechazos.isEmpty { metrica("Rechazos", s.rechazos, "trash") }
                                }
                                metrica("CPU", s.cpuNucleos > 0 ? String(format: "%.1f de %d núcleos (%.0f%%)", s.cpuNucleos, s.nucleos, s.cpuNucleos/Double(max(s.nucleos,1))*100) : "—", "cpu")
                                metrica("RAM", s.ramGB > 0 ? String(format: "%.1f GB", s.ramGB) : "—", "memorychip")
                                metrica("GPU", s.gpu, "display")
                                metrica("IA (Neural Engine)", s.ia, "brain")
                                metrica("Disco", s.discoGB > 0 ? String(format: "%.1f GB", s.discoGB) : "—", "internaldrive")
                                metrica("Errores", "\(s.errores)", s.errores > 0 ? "exclamationmark.triangle" : "checkmark.seal")
                            }
                            // El REGISTRO en vivo (últimas líneas del log activo)
                            if !s.bitacora.isEmpty {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 1) {
                                        ForEach(Array(s.bitacora.enumerated()), id: \.offset) { _, l in
                                            Text(l).font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(l.contains("[!]") || l.lowercased().contains("error") ? .red : .secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }.padding(6)
                                }.frame(height: 150)
                                .background(Color.black.opacity(0.04)).cornerRadius(6)
                            }
                        }

                        if entrenando {
                            Button(deteniendo ? "Deteniendo…" : "⏹ Detener del todo") {
                                deteniendo = true; faseTxt = "Deteniendo todo (matando procesos)…"; timer?.invalidate()
                                if let p = proyecto {
                                    EntrenadorPiper.detenerProyecto(p) { ok in
                                        deteniendo = false; entrenando = false; snap = nil; pctVivo = 0
                                        faseTxt = ok ? "✓ Detenido del todo — nada quedó corriendo. Ya puedes reentrenar."
                                                     : "⚠ Algo sigue vivo. Vuelve a pulsar Detener."
                                        if !ok { reanudable = p }
                                    }
                                } else { EntrenadorPiper.detener(); deteniendo = false; entrenando = false; faseTxt = "Detenido." }
                            }.controlSize(.small).disabled(deteniendo)
                            Text("“Detener del todo” mata el entrenamiento de raíz (y sus procesos). Puedes cerrar la ventana o salir de BtoDicta: sigue en segundo plano y al reabrir la bitácora vuelve. Todo queda en dataset.log y piper.log.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // 3) Elegir el mejor — validar (Whisper + d-vector) + gráfica + ranking
                if let proyecto, !checkpoints.isEmpty {
                    grupo {
                        HStack {
                            Text("Elegir el mejor").font(.subheadline); Spacer()
                            Button(validando ? "Validando…" : "📊 Validar y graficar") {
                                validando = true; valEstado = "Generando muestras y midiendo…"; ranking = []
                                EntrenadorPiper.validar(proyecto, onProgreso: { valEstado = $0 },
                                    onFin: { ok in
                                        validando = false; ranking = EntrenadorPiper.rankingPiper(proyecto)
                                        valEstado = !ok ? "No se pudo validar"
                                            : (ranking.first.map { $0.inteligible >= 0.5 ? "✓ El mejor está marcado 🏆" : "⚠ Entrenamiento rechazado: revisa dataset/base; no sumes pasos a ciegas" } ?? "")
                                    })
                            }.controlSize(.small).disabled(validando)
                        }
                        Text("Mide inteligibilidad (Whisper) + parecido de voz (d-vector) de cada checkpoint. Así no eliges a ciegas entre basura.").font(.caption2).foregroundStyle(.secondary)
                        if !valEstado.isEmpty {
                            Text(valEstado).font(.caption2)
                                .foregroundStyle(validando ? Color.secondary : ((ranking.first?.inteligible ?? 0) >= 0.5 ? Color.green : Color.orange))
                        }
                        if let png = EntrenadorPiper.graficaValidacion(proyecto), let img = NSImage(contentsOf: png) {
                            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 220).cornerRadius(6)
                        }
                        if !ranking.isEmpty {
                            ForEach(Array(ranking.enumerated()), id: \.offset) { i, r in
                                HStack(spacing: 6) {
                                    Text("\(i == 0 && r.inteligible >= 0.5 ? "🏆 " : "")paso \(r.paso)").font(.caption)
                                    Text(r.inteligible >= 0.5 ? "✓ ok" : "basura").font(.caption2)
                                        .foregroundStyle(r.inteligible >= 0.5 ? .green : .red)
                                    Text("intel \(Int(r.inteligible*100))% · voz \(Int(r.parecido*100))%").font(.caption2).foregroundStyle(.secondary)
                                    Spacer()
                                    if let u = r.ckpt {
                                        Button("🔊") { escuchar(u) }.controlSize(.mini)
                                        Button("Usar") { exportar(u) }.controlSize(.mini).disabled(r.inteligible < 0.5)
                                        Button("🗑") { borrar(u) }.controlSize(.mini)
                                    }
                                }
                            }
                        } else {
                            Text("Escucha cualquiera, o pulsa Validar para puntuarlos y graficarlos.").font(.caption2).foregroundStyle(.secondary)
                            ForEach(Array(checkpoints.enumerated()), id: \.offset) { _, c in
                                HStack {
                                    Text("paso \(c.paso)").font(.caption); Spacer()
                                    Button("🔊") { escuchar(c.url) }.controlSize(.mini)
                                    Button("Usar este") { exportar(c.url) }.controlSize(.mini)
                                    Button("🗑") { borrar(c.url) }.controlSize(.mini).help("Descartar")
                                }
                            }
                        }
                    }
                }

                if !estado.isEmpty { Text(estado).font(.caption).foregroundStyle(.secondary) }
            }.padding(16)
        }
        .onAppear {
            // ¿Hay un entrenamiento trabajando AHORA (aunque hayas cerrado la app antes)?
            // → re-engancha el progreso en vivo. Si no, ¿hay uno a medias para reanudar?
            if let act = EntrenadorPiper.proyectoActivo() {
                proyecto = act; marcaFija = "run"
                if nombre.isEmpty { nombre = EntrenadorPiper.nombreDeProyecto(act) }
                if etapas == 0 { etapas = EntrenadorPiper.etapasDe(act) }
                entrenando = true; reanudable = nil
                seguirProgreso()
            } else {
                reanudable = EntrenadorPiper.proyectoReanudable()
            }
        }
    }

    @ViewBuilder private func grupo<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { c() }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06)).cornerRadius(8)
    }

    @ViewBuilder private func barra(_ titulo: String, _ valor: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(titulo).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(Int(min(1, max(0, valor)) * 100))%").font(.caption2).monospacedDigit().bold()
            }
            ProgressView(value: min(1, max(0, valor))).tint(color)
        }
    }

    @ViewBuilder private func metrica(_ titulo: String, _ valor: String, _ icono: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icono).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(titulo).font(.system(size: 8)).foregroundStyle(.secondary)
                Text(valor).font(.system(size: 10, weight: .medium)).monospacedDigit().lineLimit(1)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08)).cornerRadius(5)
    }

    private func elegirCarpeta() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        guard p.runModal() == .OK, let u = p.url else { return }
        carpeta = u; if nombre.isEmpty { nombre = u.lastPathComponent }
        estado = "Midiendo la duración del audio…"
        DispatchQueue.global().async {
            let m = EntrenadorPiper.duracionMinutos(u)
            DispatchQueue.main.async {
                minutos = m; let pl = EntrenadorPiper.recomendar(minutos: m); plan = pl
                etapas = pl.etapasRecomendadas; estado = ""
            }
        }
    }

    @State private var marcaFija = ""
    private func marca() -> String { if marcaFija.isEmpty { marcaFija = "run" }; return marcaFija }

    private func entrenar() {
        guard let carpeta else { return }
        entrenando = true; faseTxt = "Preparando…"; checkpoints = []
        EntrenadorPiper.entrenar(carpeta: carpeta, nombre: nombre, stamp: marca(), etapas: etapas,
                                 calidadId: calidad, reanudar: false,
            onProgreso: { p in faseTxt = p.texto; pasoActual = p.paso },
            onArranco: { ok, msg, proj in
                faseTxt = msg; proyecto = proj
                if ok { seguirProgreso() } else { entrenando = false }
            })
    }

    private func bajarBase() {
        bajandoBase = true; estado = "Descargando base…"
        EntrenadorPiper.descargarBase(calidadId: calidad, onProgreso: { estado = $0 },
            completion: { ok, msg in bajandoBase = false; estado = msg; baseListaTick += 1 })
    }

    private func reanudar(_ proj: URL) {
        entrenando = true; faseTxt = "Reanudando…"; proyecto = proj; reanudable = nil
        // Nombre desde la carpeta del proyecto (slug_run) — usa el prefijo.
        let nom = proj.lastPathComponent.replacingOccurrences(of: "_run", with: "")
        if nombre.isEmpty { nombre = nom }
        EntrenadorPiper.entrenar(carpeta: nil, nombre: nombre.isEmpty ? nom : nombre, stamp: "run",
                                 etapas: etapas > 0 ? etapas : 3000, reanudar: true,
            onProgreso: { p in faseTxt = p.texto; pasoActual = p.paso },
            onArranco: { ok, msg, _ in faseTxt = msg; if ok { seguirProgreso() } else { entrenando = false } })
    }

    private func seguirProgreso() {
        timer?.invalidate()
        pulso = true   // arranca el latido del punto "procesando"
        tick()   // pinta de inmediato
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in tick() }
    }

    private func tick() {
        guard let proyecto else { return }
        let etapasAhora = etapas
        // Todo el IO (leer logs, pgrep/ps/du) va en BACKGROUND; solo publicamos a @State en main.
        DispatchQueue.global(qos: .utility).async {
            let s = EntrenadorPiper.snapshot(proyecto, etapas: etapasAhora)
            let cks = EntrenadorPiper.checkpoints(proyecto)
            DispatchQueue.main.async {
                guard entrenando || snap != nil else { return }
                snap = s; pctVivo = s.pct; faseTxt = s.texto; pasoActual = s.paso; checkpoints = cks
                if s.termino {
                    entrenando = false; timer?.invalidate()
                    faseTxt = "✓ Terminó — escucha y elige el mejor checkpoint abajo."
                } else if !s.activo {
                    entrenando = false; timer?.invalidate()
                    if !cks.isEmpty { reanudable = proyecto
                        faseTxt = "Se detuvo — elige un checkpoint abajo o pulsa Reanudar." }
                    else { faseTxt = "Se detuvo (revisa la bitácora)." }
                }
            }
        }
    }

    private func tiempo(_ minutos: Int) -> String {
        guard minutos > 0 else { return "—" }
        let h = minutos / 60, m = minutos % 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    private func escuchar(_ ckpt: URL) {
        guard let proyecto else { return }
        estado = "Generando muestra…"
        EntrenadorPiper.muestra(proyecto: proyecto, checkpoint: ckpt,
                                texto: "Hola, esta es una muestra de mi voz entrenada en Piper.", stamp: "\(ckpt.lastPathComponent)") { wav in
            estado = ""
            if let wav { NSSound(contentsOf: wav, byReference: true)?.play() } else { estado = "No pude generar la muestra." }
        }
    }

    private func exportar(_ ckpt: URL) {
        guard let proyecto else { return }
        estado = "Exportando y registrando la voz…"
        EntrenadorPiper.exportarYregistrar(proyecto: proyecto, checkpoint: ckpt, nombre: nombre,
                                           prompt: persona, stamp: "final") { voz, msg in
            estado = msg
        }
    }

    private func borrar(_ ckpt: URL) {
        guard ConfirmacionSegura.pedir("¿Enviar este checkpoint Piper a la Papelera?",
            detalle: "Se conservarán el resto de checkpoints, el proyecto y cualquier ONNX ya registrada.",
            boton: "Enviar a Papelera") else { return }
        NSWorkspace.shared.recycle([ckpt]) { _, error in
            DispatchQueue.main.async {
                if let error { estado = "No se quitó: \(error.localizedDescription)" }
                else {
                    checkpoints.removeAll { $0.url == ckpt }
                    estado = "Checkpoint enviado a la Papelera de macOS."
                }
            }
        }
    }
}
