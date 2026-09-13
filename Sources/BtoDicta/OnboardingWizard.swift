import AppKit
import SwiftUI
import AVFoundation
import Carbon.HIToolbox

// MARK: - Asistente de primer arranque (wizard)
//
// La primera vez que la app corre en una máquina (o hasta que el usuario lo
// termine), muestra un asistente paso a paso. 9 pasos:
//   0 Bienvenida · 1 Permisos · 2 IA nube · 3 IA local · 4 Failover ·
//   5 Aprendizaje + glosario · 6 Preferencias · 7 Asistente + Atajos ·
//   8 Listo (+ donar)
//
// Robusto al reinicio de accesibilidad: el flag "wizard_completado" SOLO se
// pone al pulsar "Finalizar". Si el usuario activa accesibilidad y la app se
// reinicia a mitad, el asistente vuelve al MISMO paso con los permisos ya en
// verde ("check activado, check activado").

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)

final class WizardWindowController {
    static let shared = WizardWindowController()
    private var window: NSWindow?

    static var debeMostrarse: Bool { !Config.wizardCompletado() }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Bienvenido a BtoDicta"
            w.styleMask = [.titled, .closable]
            w.setContentSize(NSSize(width: 660, height: 680))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
    }

    func close() { window?.close() }

    /// Reinicia BtoDicta (necesario tras conceder Accesibilidad para que los
    /// taps de teclado/pegado se re-registren con el permiso ya activo).
    static func reiniciarApp() {
        let ruta = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "sleep 0.6; open \"\(ruta)\""]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }
}

// MARK: - Modal de novedades (tras actualizar)

final class NovedadesWindowController {
    static let shared = NovedadesWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: NovedadesView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Novedades de BtoDicta"
            w.styleMask = [.titled, .closable]
            w.setContentSize(NSSize(width: 460, height: 440))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
    }
    func close() { window?.close() }
}

struct NovedadesView: View {
    private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)
    private var ultima: (version: String, fecha: String, cambios: [String])? { Version.historial.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img).resizable().frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Novedades").font(.title).bold()
                    if let u = ultima { Text("Versión \(u.version) · \(u.fecha)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ultima?.cambios ?? [], id: \.self) { c in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkle").foregroundStyle(acento).font(.caption)
                            Text(c).font(.subheadline)
                        }
                    }
                }
            }
            Spacer()
            HStack {
                Button("Ver el manual") { if let u = URL(string: "https://github.com/btoaldas/BtoDicta/blob/main/docs/MANUAL.md") { NSWorkspace.shared.open(u) } }
                    .buttonStyle(.link)
                Button("Revisar todas las novedades") {
                    NovedadesWindowController.shared.close()
                    SettingsWindowController.shared.show(irA: "Créditos")
                }.buttonStyle(.link)
                Spacer()
                Button("Entendido") { NovedadesWindowController.shared.close() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                    .buttonStyle(.borderedProminent).tint(acento)
            }
        }
        .padding(24).frame(width: 460, height: 440)
    }
}

// MARK: - Render simple de Markdown (para "Ver novedades" del release)

struct MarkdownSimple: View {
    let texto: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                linea(String(raw))
            }
        }
    }
    @ViewBuilder private func linea(_ l: String) -> some View {
        let t = l.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("### ") { Text(inline(String(t.dropFirst(4)))).font(.subheadline).bold().padding(.top, 4) }
        else if t.hasPrefix("## ") { Text(inline(String(t.dropFirst(3)))).font(.headline).bold().padding(.top, 4) }
        else if t.hasPrefix("# ") { Text(inline(String(t.dropFirst(2)))).font(.title3).bold() }
        else if t.hasPrefix("- ") || t.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) { Text("•").foregroundStyle(.secondary); Text(inline(String(t.dropFirst(2)))) }
        } else if t.isEmpty { Color.clear.frame(height: 3) }
        else { Text(inline(t)) }
    }
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - Opción de modelo local (unifica tcpp / whisper / exótico)

private struct LocalOpt: Identifiable {
    let id: String
    let nombre: String
    let nota: String
    let tamañoMB: Int
    let claves: [String]                 // para cancelar la descarga
    let descargado: () -> Bool
    let progreso: () -> Double?
    let descargar: () -> Void
    let usar: () -> Void
    let enUso: () -> Bool
}

// MARK: - Vista del asistente

struct OnboardingView: View {
    @StateObject private var m = SettingsModel()
    @StateObject private var pm = ProvidersModel()          // cascada + descargas locales
    @StateObject private var glosario = KeytermsStore()
    @StateObject private var permisosSistema = PermisosSistemaModel()
    @ObservedObject private var descargas = Descargas.shared
    @State private var paso: Int = {
        if let valor = ProcessInfo.processInfo.environment["BTODICTA_WIZARD_STEP"],
           let pasoQA = Int(valor) { return min(8, max(0, pasoQA)) }
        return Config.wizardPaso()
    }()

    // Permisos (refresco cada segundo).
    @State private var mic: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var ax: Bool = AXIsProcessTrusted()
    @State private var axAlArrancar: Bool = AXIsProcessTrusted()
    @State private var nuevaPalabra = ""

    // Nombre/presencia y puentes portables. Ningún Atajo se importa solo: el
    // wizard abre cada instalador y macOS conserva el consentimiento final.
    @State private var agenteActivo = Config.agenteNucleoActivo()
    @State private var nombreAgente = Config.agenteNombre()
    @State private var activadoresAgente = FrasesConfigurables.formatear(Config.agenteActivadores())
    @State private var manosLibres = Config.agenteActivacionReposo()
    @State private var acuseAgente = Config.agenteActivacionAcuse()
    @State private var formatoAcuseAgente = Config.agenteActivacionAcuseFormato()
    @State private var siriCompatibilidadLocal = Config.agenteCompatibilidadSiriLocal()
    @State private var atajosInstalados: [String] = []
    @State private var avisoAtajos = ""

    private let totalPasos = 9
    private let reloj = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider()
            barraInferior.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 660, height: 680)
        .onReceive(reloj) { _ in
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
            ax = AXIsProcessTrusted()
            if paso == 1 { permisosSistema.refrescar() }
        }
        .onChange(of: paso) { _, nuevo in
            if nuevo == 7 { refrescarAtajosIncluidos() }
        }
        .onChange(of: agenteActivo) { guardarAsistente() }
        .onChange(of: activadoresAgente) { guardarAsistente() }
        .onChange(of: manosLibres) { guardarAsistente() }
        .onChange(of: acuseAgente) { guardarAsistente() }
        .onChange(of: formatoAcuseAgente) { guardarAsistente() }
        .onChange(of: siriCompatibilidadLocal) { guardarAsistente() }
    }

    @ViewBuilder private var contenido: some View {
        switch paso {
        case 0: bienvenida
        case 1: permisos
        case 2: nube
        case 3: local
        case 4: failover
        case 5: aprendizaje
        case 6: preferencias
        case 7: asistenteYAtajos
        default: listo
        }
    }

    // MARK: Paso 0 — Bienvenida
    private var bienvenida: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let img = NSImage(named: "AppIcon") {
                    Image(nsImage: img).resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BtoDicta").font(.largeTitle).bold()
                    Text("Dictado por voz para macOS · español latino 🇪🇨").foregroundStyle(.secondary)
                }
            }
            Text("Pulsas una tecla, hablas, vuelves a pulsar — y el texto aparece donde está tu cursor, en cualquier app.")
                .font(.title3)
            Text("Este asistente te toma un par de minutos. Vamos a:")
                .font(.headline).padding(.top, 4)
            vinieta("1", "Dar permisos", "Micrófono y Accesibilidad para dictar; notificaciones y herramientas adicionales bajo tu control.")
            vinieta("2", "Conectar IA", "Motores de nube (opcional) y motores locales gratis que corren sin internet.")
            vinieta("3", "Ordenar el failover", "Cuál motor va primero, cuál de respaldo — para que nunca pierdas un dictado.")
            vinieta("4", "Que aprenda y tus preferencias", "Vocabulario, corrección automática, sonidos, tecla, Dock… a tu gusto.")
            Spacer()
            Text("Todo se puede cambiar luego en Configuración. Nada es definitivo.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: Paso 1 — Permisos
    private var permisos: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado("Permisos", "activa primero lo esencial y, si quieres, deja listas las herramientas adicionales.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Esenciales para dictar", systemImage: "checkmark.shield.fill")
                        .font(.subheadline).bold().foregroundStyle(acento)
                    permisoFila(icono: "mic.fill", titulo: "Micrófono",
                                para: "Para convertir tu voz en texto.",
                                listo: mic == .authorized, estado: micEstadoTexto,
                                accion: micAccion, etiquetaBoton: micBotonTexto)
                    permisoFila(icono: "accessibility", titulo: "Accesibilidad",
                                para: "Para escribir el texto donde está tu cursor y detectar la tecla de dictado.",
                                listo: ax && axAlArrancar, estado: axEstadoTexto,
                                accion: axAccion, etiquetaBoton: "Abrir Ajustes de Accesibilidad")
                    if ax && !axAlArrancar {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Accesibilidad activada — reinicia BtoDicta para que tome efecto.",
                                  systemImage: "arrow.clockwise.circle.fill")
                                .font(.subheadline).foregroundStyle(acento)
                            Text("El asistente vuelve exactamente a este paso y conserva lo que ya configuraste.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button {
                                Config.set("wizard_paso", to: 1)
                                WizardWindowController.reiniciarApp()
                            } label: { Label("Reiniciar BtoDicta ahora", systemImage: "arrow.clockwise") }
                                .buttonStyle(.borderedProminent).tint(acento)
                        }
                        .padding(12).background(acento.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Divider().padding(.vertical, 2)
                    Label("Funciones adicionales", systemImage: "sparkles")
                        .font(.subheadline).bold().foregroundStyle(acento)
                    Text("Son opcionales y puedes concederlas una por una. Si eliges No permitir, BtoDicta continúa funcionando y podrás cambiarlo después.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(PermisosSistema.adicionales) { permiso in
                        permisoAdicionalFila(permiso)
                    }
                }
                .padding(.trailing, 6)
            }.scrollIndicators(.visible)
            if permisosOK {
                Label("Lo esencial está listo. Puedes activar más permisos o pulsar Siguiente.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.caption)
            }
        }
    }

    // MARK: Paso 2 — IA en la nube
    private var nube: some View {
        VStack(alignment: .leading, spacing: 16) {
            encabezado("Inteligencia en la nube (opcional)",
                       "BtoDicta funciona GRATIS y sin internet con motores locales (siguiente paso). Si quieres la máxima calidad en vivo, conecta un servicio. Pega la clave o deja en blanco para saltar.")
            // Accesibilidad: para máquinas sin fuerza o sin plata para tokens,
            // hay nube GRATIS de verdad (sin tarjeta). Se resalta aquí.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "gift.fill").foregroundStyle(.green)
                Text("¿Máquina sin fuerza o sin presupuesto? Hay nube GRATIS: **Groq Whisper** (2000 transcripciones/día) y **Hugging Face** para voz; para pulido, modelos **:free** de OpenRouter. Sin tarjeta.")
                    .font(.caption)
            }
            .padding(10)
            .background(Color.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ClaveNubeRow(id: "groq", env: "GROQ_API_KEY",
                                 titulo: "Groq Whisper (gratis)", nota: "Muy rápido, 2000/día gratis sin tarjeta. También potencia el pulido y la traducción.",
                                 enlace: "https://console.groq.com/keys", activarPrimero: false, pm: pm)
                    ClaveNubeRow(id: "hf", env: "HF_API_KEY",
                                 titulo: "Hugging Face (Whisper, gratis)", nota: "Transcripción con Whisper en la capa gratuita. Ideal si no tienes máquina potente.",
                                 enlace: "https://huggingface.co/settings/tokens", activarPrimero: false, pm: pm)
                    ClaveNubeRow(id: "elevenlabs", env: "ELEVENLABS_API_KEY",
                                 titulo: "ElevenLabs Scribe", nota: "La mejor calidad, texto EN VIVO. De pago (~$0.22–0.39/h).",
                                 enlace: "https://elevenlabs.io/app/settings/api-keys", activarPrimero: false, pm: pm)
                    DisclosureGroup("Más servicios (OpenAI, Mistral)") {
                        VStack(alignment: .leading, spacing: 14) {
                            ClaveNubeRow(id: "openai", env: "OPENAI_API_KEY",
                                         titulo: "OpenAI", nota: "whisper-1 y gpt-4o-transcribe (~$0.18–0.36/h).",
                                         enlace: "https://platform.openai.com/api-keys", activarPrimero: false, pm: pm)
                            ClaveNubeRow(id: "mistral", env: "MISTRAL_API_KEY",
                                         titulo: "Mistral (Voxtral)", nota: "Voxtral en la nube, sin descargar nada.",
                                         enlace: "https://console.mistral.ai/api-keys", activarPrimero: false, pm: pm)
                        }.padding(.top, 6)
                    }.font(.subheadline)
                }
            }
        }
    }

    // MARK: Paso 3 — IA local (descargas en segundo plano)
    private var local: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Inteligencia local (gratis, sin internet)",
                       "Descarga uno o más motores. La descarga sigue en SEGUNDO PLANO aunque avances o cierres el asistente. Pulsa \"Usar\" para dejarlo listo en tu cascada.")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(opcionesLocales) { localRow($0) }
                }
            }
        }
    }

    // MARK: Paso 4 — Failover / jerarquía
    private var failover: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Orden del failover",
                       "Se usa el motor activo #1; si falla, salta al #2, luego al #3. Enciende los que quieras (uno basta) y ordénalos con las flechas.")
            VStack(alignment: .leading, spacing: 8) {
                Label("Sugerencia: una IA LOCAL de #1 (funciona sin internet) y ElevenLabs de #2 de respaldo.",
                      systemImage: "lightbulb.fill").font(.subheadline).foregroundStyle(acento)
                Button("Aplicar sugerencia (local primero, nube después)") { aplicarSugerencia() }
                    .controlSize(.small)
            }
            .padding(12).background(acento.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(pm.lista.enumerated()), id: \.element.id) { i, p in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(.system(.body, design: .rounded)).bold()
                                .frame(width: 20).foregroundStyle(p.activo ? acento : .secondary)
                            Toggle("", isOn: Binding(get: { p.activo }, set: { _ in pm.toggle(p.id) }))
                                .toggleStyle(.switch).labelsHidden().tint(acento)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(p.nombre).font(.subheadline).bold()
                                    if esEnVivo(p) {
                                        Text("EN VIVO").font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.green.opacity(0.85)).foregroundStyle(.white)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text("\(p.tipo == "nube" ? "☁️ nube" : "💾 local") · \(p.modelo ?? "—")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { pm.subir(i) } label: { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless).disabled(i == 0)
                                .help("Subir este motor una posición en la cascada")
                            Button { pm.bajar(i) } label: { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless).disabled(i == pm.lista.count - 1)
                                .help("Bajar este motor una posición en la cascada")
                        }
                        .padding(10).background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(p.activo ? 1 : 0.55)
                    }
                }
            }
        }
    }

    // MARK: Paso 5 — Aprendizaje + glosario
    private var aprendizaje: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Que aprenda de ti", "la app puede recordar tus correcciones y respetar tu vocabulario. Todo 100% local.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wizToggle("Aprender de mis correcciones", isOn: $m.aprender,
                              nota: "Corriges una palabra donde la pegaste (ej. Sentrix → Zentrix) y la app guarda la regla sola. En la terminal/Claude Code: seleccionas el texto corregido y pulsas ⌘⇧L. Recomendado.")
                    wizToggle("Corrección por sonido (fonética)", isOn: $m.porSonido,
                              nota: "Corrige palabras que SUENAN como un término tuyo. Más potente pero puede pasarse: la activas término por término (casilla 🔊 en Reemplazos) y siempre es reversible.")
                    wizToggle("Pulido con IA (Groq)", isOn: $m.postProceso,
                              nota: "Una IA corrige la puntuación y quita muletillas (\"eh\", \"este…\"). Necesita clave de Groq (paso IA en la nube).")
                    // Glosario inicial
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tu glosario").font(.headline)
                        Text("Palabras que quieres que SIEMPRE escriba bien: nombres, siglas, términos (Zentrix, UNESCO, Pérez…). Tienes \(glosario.activas) ya guardadas.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("Agrega palabras separadas por coma", text: $nuevaPalabra)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { agregarPalabras() }
                            Button("Agregar") { agregarPalabras() }
                                .disabled(nuevaPalabra.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(12).background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: Paso 6 — Preferencias (tecla + micrófono + toggles)
    private var preferencias: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Tus preferencias", "afina cómo se comporta. Los valores de fábrica ya están bien para la mayoría.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Tecla de dictado
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Tecla de dictado").font(.headline)
                            Spacer()
                            HotkeyRecorder(value: $m.tecla).frame(width: 130, height: 26)
                        }
                        Text("La tecla que abre y cierra el dictado. Por defecto fn; puedes poner F1–F12 o combinaciones como ⌘⇧D.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                    // Micrófono
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Micrófono").font(.headline)
                            Spacer()
                            Picker("", selection: $m.microfono) {
                                Text("Integrado del Mac (recomendado)").tag("")
                                Text("Automático (el del sistema)").tag("auto")
                                ForEach(Microfono.disponibles().filter { !$0.integrado }) { d in
                                    Text(d.nombre).tag(d.uid)
                                }
                            }.labelsHidden().frame(width: 240)
                        }
                        Text("Fijo al integrado, el iPhone cercano ya no roba el micrófono a media grabación.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))

                    wizToggle("Sonidos de inicio y fin", isOn: $m.sonidos, nota: "Un \"tink\" al empezar y un \"glass\" al entregar el texto.")
                    wizToggle("Mostrar el panel al dictar", isOn: $m.panelVisible, nota: "El panel negro junto al notch con el latido de tu voz y el texto en vivo. Apágalo para modo ninja.")
                    wizToggle("Cancelar con Esc", isOn: $m.escCancela, nota: "Pulsar Esc a mitad del dictado descarta todo sin escribir nada.")
                    wizToggle("Pausar música y videos al dictar", isOn: $m.pausarMultimedia, nota: "Pausa Spotify/YouTube/Music mientras hablas y los reanuda al terminar.")
                    wizToggle("Bajar el volumen al dictar", isOn: $m.bajarVolumen, nota: "Además baja el volumen del sistema y lo restaura exacto.")
                    wizToggle("Mostrar en el Dock", isOn: $m.mostrarEnDock, nota: "La app vive en la barra de menú (arriba). Enciéndelo si además la quieres en el Dock.")
                    wizToggle("Arrancar al iniciar sesión", isOn: $m.arrancarInicio, nota: "BtoDicta se abre sola al prender el Mac. Cómodo si dictas a diario.")
                    wizToggle("Modo desarrollo (debug)", isOn: $m.modoDesarrollo, nota: "Notas técnicas extra en el registro y desbloquea la bitácora de aprendizaje en Estadísticas.")
                }
            }
        }
    }

    // MARK: Paso 7 — Nombre del asistente + Atajos portables
    private var asistenteYAtajos: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado("Tu asistente y sus Atajos",
                       "Ponle el nombre que quieras. Los instaladores viajan con BtoDicta y puedes reinstalarlos después.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Activar el núcleo del asistente", isOn: $agenteActivo)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("¿Cómo quieres que se llame?").font(.headline)
                        TextField("Bto, Gloria, Jarvis…", text: nombreAgenteBinding)
                            .textFieldStyle(.roundedBorder)
                        Text("Ejemplo: di “Oye \(nombreAgenteLimpio)” al comenzar un dictado.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Frases de activación · una por línea").font(.headline)
                        TextEditor(text: $activadoresAgente)
                            .frame(minHeight: 62, maxHeight: 82)
                            .padding(5).background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("Deben tener al menos dos palabras. La puntuación y las comas no importan.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    wizToggle("Escuchar la frase en reposo (opcional)", isOn: $manosLibres,
                              nota: "Apple Speech trabaja localmente. macOS mostrará su indicador de micrófono; puedes dejarlo apagado y usar fn o Siri.")
                    if manosLibres {
                        wizToggle("Compatibilidad “Oye Siri” mientras BtoDicta escucha",
                                  isOn: $siriCompatibilidadLocal,
                                  nota: "Reconoce localmente solo “Oye Siri” + el nombre elegido. No roba otras órdenes de Siri.")
                    }
                    wizToggle("Responder cuando reconoce la frase", isOn: $acuseAgente,
                              nota: "Confirma rápidamente “Te escucho” antes de abrir el turno limpio.")
                    if acuseAgente {
                        Picker("Respuesta", selection: $formatoAcuseAgente) {
                            Text("Solo texto").tag("texto")
                            Text("Texto y voz").tag("texto_voz")
                            Text("Solo voz").tag("voz")
                        }.pickerStyle(.segmented)
                    }

                    Divider()
                    Text("Atajos incluidos").font(.headline)
                    Text("Importa solo los que quieras. BtoDicta abre el paquete firmado, pero macOS te muestra sus acciones y tú confirmas “Añadir atajo”.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(AtajoIncluidoID.allCases) { id in
                        let info = AtajosIncluidos.info(id, nombreAgente: nombreAgenteLimpio)
                        let instalado = AtajosIncluidos.estaInstalado(
                            id, nombreAgente: nombreAgenteLimpio,
                            nombres: atajosInstalados)
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: instalado ? "checkmark.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(instalado ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.nombre).font(.subheadline).bold()
                                Text(info.detalle).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(instalado ? "Reinstalar…" : "Instalar…") {
                                instalarAtajoIncluido(id)
                            }.controlSize(.small)
                        }
                    }
                    HStack {
                        Button("Actualizar estado") { refrescarAtajosIncluidos() }
                            .controlSize(.small)
                        if !avisoAtajos.isEmpty {
                            Text(avisoAtajos).font(.caption).foregroundStyle(acento)
                        }
                    }
                    Text("Las recetas de trabajo, universidad, casa, resumen, selección y HomeKit se enrutan por BtoDicta Universal; no necesitas veinte copias del mismo puente.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Paso 8 — Listo + donar
    private var listo: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                Spacer() }
            Text("¡Todo listo!").font(.largeTitle).bold().frame(maxWidth: .infinity, alignment: .center)
            Text("Pon el cursor donde quieras escribir y **pulsa \(Config.hotkey()) para tu primer dictado**. Vuelve a pulsar para soltar el texto.")
                .font(.title3).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Label("Busca el ícono de micrófono en la barra de menú (arriba a la derecha) para volver a Configuración.", systemImage: "menubar.arrow.up.rectangle")
                Label("Todo lo que elegiste aquí se puede cambiar cuando quieras.", systemImage: "slider.horizontal.3")
            }.font(.subheadline).foregroundStyle(.secondary)
            // Donar
            VStack(alignment: .leading, spacing: 8) {
                Label("Apoya el proyecto ☕", systemImage: "cup.and.saucer.fill").font(.headline).foregroundStyle(acento)
                Text("BtoDicta es gratis y libre. Si te sirve, un cafecito ayuda a seguir programando (y a pagar la IA que la construye).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button("☕ Invítame un café") { abrir("https://btodicta.eztic.ec/apoyar") }.buttonStyle(.link)
                    Button("💜 GitHub Sponsors") { abrir("https://github.com/sponsors/btoaldas") }.buttonStyle(.link)
                    Button("💳 PayPal") { abrir("https://btodicta.eztic.ec/apoyar") }.buttonStyle(.link)
                }
            }
            .padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer()
        }
    }

    // MARK: Barra inferior
    private var barraInferior: some View {
        HStack {
            if paso > 0 { Button("Atrás") { retroceder() }.controlSize(.large) }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalPasos, id: \.self) { i in
                    Circle().fill(i == paso ? acento : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            if paso < totalPasos - 1 {
                Button(paso == 0 ? "Empezar" : "Siguiente") { avanzar() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                    .disabled(paso == 1 && !permisosOK)
            } else {
                Button("Finalizar") { finalizar() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                    .buttonStyle(.borderedProminent).tint(acento)
            }
        }
    }

    // MARK: Navegación
    private var permisosOK: Bool { mic == .authorized && ax && axAlArrancar }
    private func avanzar() {
        if paso == 7 { guardarAsistente() }
        paso = min(paso + 1, totalPasos - 1)
        Config.set("wizard_paso", to: paso)
    }
    private func retroceder() { paso = max(paso - 1, 0); Config.set("wizard_paso", to: paso) }
    private func finalizar() {
        guardarAsistente()
        Config.set("wizard_completado", to: true)
        Config.set("wizard_paso", to: 0)
        WizardWindowController.shared.close()
    }

    // MARK: Asistente y Atajos
    private var nombreAgenteLimpio: String {
        let n = PasarelaSiriBeto.nombreSugerido(nombreAgente)
        return n.isEmpty ? "Bto" : n
    }

    private func frasesAutomaticas(_ nombre: String) -> [String] {
        let n = PasarelaSiriBeto.nombreSugerido(nombre)
        return ["oye \(n)", "\(n) escucha"]
    }

    private var nombreAgenteBinding: Binding<String> {
        Binding(get: { nombreAgente }, set: { nuevo in
            let anteriores = frasesAutomaticas(nombreAgente).map(PerfilAgente.normalizar)
            let actuales = FrasesConfigurables.parsear(activadoresAgente)
                .map(PerfilAgente.normalizar)
            nombreAgente = nuevo
            if actuales == anteriores {
                activadoresAgente = FrasesConfigurables.formatear(frasesAutomaticas(nuevo))
            }
            guardarAsistente()
        })
    }

    private func guardarAsistente() {
        let nombre = nombreAgenteLimpio
        let frases = FrasesConfigurables.activadoresSeguros(
            FrasesConfigurables.parsear(activadoresAgente))
        Config.set("agente_nucleo_activo", to: agenteActivo)
        Config.set("agente_nombre", to: nombre)
        Config.set("agente_activadores", to: frases.isEmpty ? frasesAutomaticas(nombre) : frases)
        Config.set("agente_activacion_reposo", to: manosLibres)
        Config.set("agente_activacion_acuse", to: acuseAgente)
        Config.set("agente_activacion_acuse_formato", to: formatoAcuseAgente)
        Config.set("agente_siri_compatibilidad_local", to: siriCompatibilidadLocal)
        NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                        object: nil)
    }

    private func refrescarAtajosIncluidos() {
        AppleAtajos.listar { nombres in atajosInstalados = nombres }
    }

    private func instalarAtajoIncluido(_ id: AtajoIncluidoID) {
        guardarAsistente()
        let r = AtajosIncluidos.instalar(id, nombreAgente: nombreAgenteLimpio)
        avisoAtajos = r.mensaje
        if r.ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                refrescarAtajosIncluidos()
            }
        }
    }

    // MARK: Modelos locales
    private var opcionesLocales: [LocalOpt] {
        var out: [LocalOpt] = []
        // tcpp: Voxtral Realtime, Nemotron, Canary
        for (m, prov) in [(ModelCatalog.voxtralRealtime[0], "voxtral_local"),
                          (ModelCatalog.nemotron[0], "nemotron_local"),
                          (ModelCatalog.canary[0], "canary_local")] {
            out.append(LocalOpt(
                id: m.archivo, nombre: m.nombre, nota: "\(m.nota) · \(gb(m.tamañoMB))",
                tamañoMB: m.tamañoMB, claves: [m.archivo],
                descargado: { m.descargado },
                progreso: { Descargas.shared.progreso[m.archivo] },
                descargar: { pm.descargarTcpp(m) },
                usar: { pm.usarTcpp(m, proveedor: prov) },
                enUso: { Providers.modelo(de: prov) == m.archivo && (Providers.load().first { $0.id == prov }?.activo ?? false) }))
        }
        // Whisper Large v3 Turbo (recomendado)
        if let w = ModelCatalog.whisper.first(where: { $0.archivo == "ggml-large-v3-turbo.bin" }) {
            out.append(LocalOpt(
                id: w.archivo, nombre: "Whisper \(w.nombre)", nota: "\(w.nota) · \(gb(w.tamañoMB))",
                tamañoMB: w.tamañoMB, claves: [w.archivo],
                descargado: { w.descargado },
                progreso: { Descargas.shared.progreso[w.archivo] },
                descargar: { pm.descargar(w) },
                usar: { pm.usarModeloLocal(w.archivo) },
                enUso: { pm.modeloLocalActual() == w.archivo && (Providers.load().first { $0.id == "whisper_local" }?.activo ?? false) }))
        }
        // Voxtral Mini 3B (exótico, llama.cpp)
        if let e = ModelCatalog.exoticos.first {
            out.append(LocalOpt(
                id: e.nombre, nombre: e.nombre, nota: "\(e.nota) · \(gb(e.tamañoMB))",
                tamañoMB: e.tamañoMB, claves: e.archivos,
                descargado: { e.descargado },
                progreso: { pm.progresoExotico(e) },
                descargar: { pm.descargarExotico(e) },
                usar: { pm.usarExotico(e) },
                enUso: { Providers.modelo(de: "voxtral_local") == e.archivos[0] && (Providers.load().first { $0.id == "voxtral_local" }?.activo ?? false) }))
        }
        return out
    }

    @ViewBuilder private func localRow(_ o: LocalOpt) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(o.nombre).font(.subheadline).bold()
                Text(o.nota).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = o.progreso() {
                HStack(spacing: 6) {
                    ProgressView(value: p).frame(width: 90)
                    Button { Descargas.shared.cancelar(o.claves) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Cancelar esta descarga")
                }
            } else if o.descargado() {
                if o.enUso() {
                    Label("EN USO", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                } else {
                    Button("Usar") { o.usar(); pm.recargar() }.controlSize(.small).buttonStyle(.borderedProminent).tint(acento)
                }
            } else {
                Button { o.descargar() } label: { Label(gb(o.tamañoMB), systemImage: "arrow.down.circle") }
                    .controlSize(.small).help("Descargar este modelo local (\(gb(o.tamañoMB)))")
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func gb(_ mb: Int) -> String { mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1000) : "\(mb) MB" }
    private func esEnVivo(_ p: Provider) -> Bool {
        TcppStreamClient.esModeloStreaming(p.modelo ?? "")
            || (p.id == "elevenlabs" && (p.modelo ?? "") == "scribe_v2_realtime")
    }

    /// Reordena: motores locales primero (en su orden), luego ElevenLabs, luego el resto.
    private func aplicarSugerencia() {
        let locales = pm.lista.filter { $0.tipo == "local" }
        let eleven = pm.lista.filter { $0.id == "elevenlabs" }
        let resto = pm.lista.filter { $0.tipo != "local" && $0.id != "elevenlabs" }
        pm.lista = locales + eleven + resto
        pm.guardar()
    }

    // MARK: Glosario
    private func agregarPalabras() {
        for parte in nuevaPalabra.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            glosario.add(parte.trimmingCharacters(in: .whitespaces))
        }
        nuevaPalabra = ""
    }

    // MARK: Permisos — helpers
    private var micEstadoTexto: String {
        switch mic {
        case .authorized: return "Activado"
        case .denied, .restricted: return "Bloqueado en Ajustes del Sistema"
        default: return "Sin conceder todavía"
        }
    }
    private var micBotonTexto: String { mic == .denied || mic == .restricted ? "Abrir Ajustes del Sistema" : "Activar micrófono" }
    private func micAccion() {
        switch mic {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio) }
            }
        default:
            abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }
    private var axEstadoTexto: String {
        if ax && !axAlArrancar { return "Activado — falta reiniciar" }
        return ax ? "Activado" : "Sin conceder todavía"
    }
    private func axAccion() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        abrir("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    private func abrir(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

    // MARK: Componentes
    private func encabezado(_ titulo: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.title).bold()
            Text(sub).font(.callout).foregroundStyle(.secondary)
        }
    }
    private func vinieta(_ n: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.subheadline).bold().foregroundStyle(.white)
                .frame(width: 22, height: 22).background(acento).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(.subheadline).bold()
                Text(d).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func permisoFila(icono: String, titulo: String, para: String,
                             listo: Bool, estado: String,
                             accion: @escaping () -> Void, etiquetaBoton: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: listo ? "checkmark.circle.fill" : icono)
                .font(.system(size: 30)).foregroundStyle(listo ? .green : acento).frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(titulo).font(.headline)
                    Text(estado).font(.caption).foregroundStyle(listo ? .green : .secondary)
                }
                Text(para).font(.caption).foregroundStyle(.secondary)
                if !listo { Button(etiquetaBoton, action: accion).controlSize(.regular).padding(.top, 2) }
            }
            Spacer()
        }
        .padding(14).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func permisoAdicionalFila(_ permiso: PermisoBetoID) -> some View {
        let estado = permisosSistema.estados[permiso] ?? PermisosSistema.estado(permiso)
        let color: Color = estado.concedido ? .green
            : (estado.requiereAtencion ? .orange : acento)
        let simbolo = estado.concedido ? "checkmark.circle.fill"
            : (estado.requiereAtencion ? "exclamationmark.triangle.fill" : permiso.icono)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: simbolo).font(.system(size: 22))
                .foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(permiso.titulo).font(.subheadline).bold()
                    if permiso == .notificaciones {
                        Text("RECOMENDADO").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(acento).clipShape(Capsule())
                    }
                    Text(estado.texto).font(.caption2).foregroundStyle(color)
                }
                Text(permiso.detalle).font(.caption2).foregroundStyle(.secondary)
                if let etiqueta = PermisosSistema.etiquetaBoton(permiso, estado: estado) {
                    Button(etiqueta) { permisosSistema.actuar(permiso) }
                        .controlSize(.small).padding(.top, 2)
                        .help("Solicita este permiso o abre su panel correspondiente en Ajustes del Sistema.")
                }
            }
            Spacer()
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func wizToggle(_ titulo: String, isOn: Binding<Bool>, nota: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(titulo, isOn: isOn).font(.headline)
            Text(nota).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Fila de clave de nube (no muestra el secreto existente)

private struct ClaveNubeRow: View {
    let id: String, env: String, titulo: String, nota: String, enlace: String
    let activarPrimero: Bool
    let pm: ProvidersModel

    @State private var clave: String = ""
    @State private var guardado = false
    @State private var yaTenia = false

    private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)
    private var conectado: Bool { yaTenia || guardado }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titulo).font(.headline)
                if conectado {
                    Label("conectado", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Conseguir clave") { if let u = URL(string: enlace) { NSWorkspace.shared.open(u) } }
                    .controlSize(.small).buttonStyle(.link)
            }
            Text(nota).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(conectado ? "Clave guardada — pega otra para reemplazarla"
                                      : "Pega tu API key aquí (o déjalo en blanco)", text: $clave)
                    .textFieldStyle(.roundedBorder)
                Button("Guardar") { guardar() }.controlSize(.regular)
                    .disabled(clave.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { yaTenia = !ApiKeys.get(env).isEmpty }
    }

    private func guardar() {
        let v = clave.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        ApiKeys.set(env, v)
        activarProveedor(id, primero: activarPrimero)
        clave = ""
        withAnimation { guardado = true }
    }
    private func activarProveedor(_ id: String, primero: Bool) {
        var lista = Providers.load()
        guard let i = lista.firstIndex(where: { $0.id == id }) else { return }
        lista[i].activo = true
        if primero { lista[i].orden = (lista.map { $0.orden }.min() ?? 0) - 1 }
        Providers.save(lista)
        pm.recargar()
    }
}
