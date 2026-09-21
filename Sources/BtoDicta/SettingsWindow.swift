import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

extension Notification.Name {
    static let betoHotkeyChanged = Notification.Name("BtoDictaHotkeyChanged")
}

private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)  // púrpura sobrio del logo

// MARK: - Sección plegable cuyo TÍTULO completo (no solo la flechita) abre/cierra

struct SeccionPlegable<Content: View>: View {
    let titulo: String
    var icono: String?
    @State private var abierto: Bool
    let content: () -> Content

    init(_ titulo: String, icono: String? = nil, abierto: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.titulo = titulo; self.icono = icono; self.content = content
        _abierto = State(initialValue: abierto)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { abierto.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: abierto ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                    if let icono { Image(systemName: icono).foregroundStyle(acento) }
                    Text(titulo).font(.headline).foregroundStyle(acento)
                    Spacer()
                }.contentShape(Rectangle())   // toda la fila es clicable
            }.buttonStyle(.plain)
                .help(abierto ? "Ocultar la sección \(titulo)" : "Mostrar la sección \(titulo)")
            if abierto { content() }
        }
    }
}

// MARK: - Modelo observable (lee/escribe ~/.btodicta/config.json)

final class SettingsModel: ObservableObject {
    @Published var tecla: String {
        didSet {
            Config.set("tecla", to: tecla)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
    @Published var modelo: String { didSet { Config.set("modelo", to: modelo) } }
    @Published var microfono: String { didSet { Config.set("microfono", to: microfono) } }
    @Published var aprender: Bool { didSet { Config.set("aprender_correcciones", to: aprender) } }
    @Published var porSonido: Bool { didSet { Config.set("correccion_por_sonido", to: porSonido) } }
    @Published var atajoAprender: String {
        didSet {
            Config.set("atajo_aprender", to: atajoAprender)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
    @Published var silencioMax: Double { didSet { Config.set("silencio_max_seg", to: silencioMax) } }
    @Published var sonidos: Bool { didSet { Config.set("sonidos", to: sonidos) } }
    @Published var escCancela: Bool { didSet { Config.set("esc_cancela", to: escCancela) } }
    @Published var escDoble: Bool { didSet { Config.set("esc_doble", to: escDoble) } }
    @Published var smtpHost: String { didSet { Config.set("smtp_host", to: smtpHost) } }
    @Published var smtpPuerto: Int { didSet { Config.set("smtp_puerto", to: smtpPuerto) } }
    @Published var smtpUsuario: String { didSet { Config.set("smtp_usuario", to: smtpUsuario) } }
    @Published var smtpRemitente: String { didSet { Config.set("smtp_remitente", to: smtpRemitente) } }
    @Published var smtpClave: String { didSet { ApiKeys.set("SMTP_PASSWORD", smtpClave) } }
    @Published var correoDest: String { didSet { Config.set("correo_destinatarios", to: correoDest) } }
    @Published var correoAuto: Bool { didSet { Config.set("correo_automatico", to: correoAuto) } }
    @Published var correoReglas: [ResumenCorreo.Regla] { didSet { ResumenCorreo.guardarReglas(correoReglas) } }
    @Published var correoPrueba = ""
    @Published var cancelarConfirma: Bool { didSet { Config.set("cancelar_confirma", to: cancelarConfirma) } }
    @Published var cancelarConserva: Double { didSet { Config.set("cancelar_conserva_desde_s", to: cancelarConserva) } }
    @Published var dictadosDias: Double { didSet { Config.set("dictados_conservar_dias", to: Int(dictadosDias)) } }
    @Published var registroTexto: Bool { didSet { Config.set("registro_incluye_texto", to: registroTexto) } }
    @Published var apiActiva: Bool { didSet { Config.set("api_local_activa", to: apiActiva); ApiLocal.reconfigurar() } }
    /// Aviso cuando alguna extensión cargada se quedó en una versión anterior.
    /// Una extensión cargada a mano no se actualiza sola: si nadie lo dice, se
    /// sigue usando una vieja sin enterarse.
    var avisoExtension: String {
        let viejas = EstadoNavegadores.desactualizadas()
        guard let v = viejas.first else { return "" }
        return "La extensión de \(v.navegador) es la \(v.tiene) y esta versión trae la \(v.deberia). Vuelve a sacarla y pulsa «Actualizar» en la página de extensiones."
    }
    @Published var apiToken: String = ApiLocal.token()
    @Published var pausarMultimedia: Bool { didSet { Config.set("atenuar_multimedia", to: pausarMultimedia) } }
    @Published var bajarVolumen: Bool { didSet { Config.set("silenciar_ademas", to: bajarVolumen) } }
    @Published var postProceso: Bool { didSet { Config.set("post_proceso", to: postProceso) } }
    @Published var pulidoProveedor: String { didSet { Config.set("pulido_proveedor", to: pulidoProveedor) } }
    @Published var promptPulido: String { didSet { Config.set("prompt_pulido", to: promptPulido) } }
    @Published var panelVisible: Bool { didSet { Config.set("panel_visible", to: panelVisible) } }
    @Published var autoAyuda: Bool {
        didSet {
            Config.set("autoayuda_controles", to: autoAyuda)
            NotificationCenter.default.post(name: .betoAutoAyudaCambio, object: nil)
        }
    }
    @Published var mostrarEnDock: Bool {
        didSet {
            Config.set("mostrar_en_dock", to: mostrarEnDock)
            NSApp.setActivationPolicy(mostrarEnDock ? .regular : .accessory)
        }
    }
    @Published var arrancarInicio: Bool {
        didSet {
            let s = SMAppService.mainApp
            if arrancarInicio { try? s.register() } else { try? s.unregister() }
        }
    }
    @Published var modoDesarrollo: Bool { didSet { Config.set("modo_desarrollo", to: modoDesarrollo) } }
    @Published var pulidoTimeout: Double { didSet { Config.set("pulido_timeout_seg", to: pulidoTimeout) } }
    @Published var buscarUpdateAlAbrir: Bool { didSet { Config.set("buscar_update_al_abrir", to: buscarUpdateAlAbrir) } }
    @Published var autoactualizar: Bool { didSet { Config.set("autoactualizar", to: autoactualizar) } }
    @Published var canalActualizaciones: String {
        didSet {
            Config.set("canal_actualizaciones", to: canalActualizaciones)
            Updater.verificarTrasCambiarCanal()
        }
    }
    @Published var actualizacionPeriodica: Bool {
        didSet {
            Config.set("actualizacion_periodica", to: actualizacionPeriodica)
            Updater.iniciarMonitoreo()
        }
    }
    @Published var actualizacionIntervalo: Double {
        didSet {
            Config.set("actualizacion_intervalo_horas", to: actualizacionIntervalo)
            Updater.iniciarMonitoreo()
        }
    }
    @Published var avisoNube: Bool { didSet { Config.set("aviso_privacidad_nube", to: avisoNube) } }
    @Published var salvaguardaInyeccion: Bool { didSet { Config.set("salvaguarda_inyeccion", to: salvaguardaInyeccion) } }
    @Published var sttStreaming: Bool { didSet { Config.set("stt_streaming", to: sttStreaming) } }
    @Published var busquedaSemantica: Bool { didSet { Config.set("busqueda_semantica", to: busquedaSemantica) } }
    @Published var glosarioInteligente: Bool { didSet { Config.set("glosario_inteligente", to: glosarioInteligente) } }
    @Published var modoVivo: Bool { didSet { Config.set("modo_vivo", to: modoVivo) } }
    @Published var modoVivoPausa: Bool { didSet { Config.set("modo_vivo_pausa", to: modoVivoPausa) } }
    @Published var modoVivoPausaSegundos: Double { didSet { Config.set("modo_vivo_pausa_seg", to: modoVivoPausaSegundos) } }
    @Published var modoVivoPalabras: Double { didSet { Config.set("modo_vivo_palabras", to: Int(modoVivoPalabras)) } }
    @Published var modoSemantico: Bool { didSet { Config.set("modo_semantico", to: modoSemantico) } }
    @Published var modoSemPalabras: Double { didSet { Config.set("modo_sem_palabras", to: Int(modoSemPalabras)) } }
    @Published var modoSemUmbral: Double { didSet { Config.set("modo_sem_umbral", to: modoSemUmbral) } }
    @Published var modoSemMargen: Double { didSet { Config.set("modo_sem_margen", to: modoSemMargen) } }
    @Published var modoGramatical: Bool { didSet { Config.set("modo_gramatical", to: modoGramatical) } }
    @Published var modoConfirmacionSeg: Double { didSet { Config.set("modo_confirmacion_seg", to: modoConfirmacionSeg) } }
    @Published var modoAutoMejora: Bool { didSet { Config.set("modo_auto_mejora", to: modoAutoMejora) } }
    @Published var modoIAEnrutamiento: Bool { didSet { Config.set("modo_ia_enrutamiento", to: modoIAEnrutamiento) } }
    @Published var modoIAProveedor: String { didSet { Config.set("modo_ia_proveedor", to: modoIAProveedor) } }
    @Published var modoIATimeout: Double { didSet { Config.set("modo_ia_timeout", to: modoIATimeout) } }
    @Published var modoIAPalabras: Double { didSet { Config.set("modo_ia_palabras", to: Int(modoIAPalabras)) } }
    @Published var logModos: Bool { didSet { Config.set("log_modos", to: logModos) } }
    @Published var calentarRed: Bool { didSet { Config.set("calentar_red", to: calentarRed) } }
    @Published var ahorroGlobal: Bool { didSet { Config.set("ahorro_global", to: ahorroGlobal) } }
    @Published var ttsActivo: Bool { didSet { Config.set("tts_activo", to: ttsActivo) } }
    @Published var ttsVoz: String { didSet { Config.set("tts_voz", to: ttsVoz) } }
    @Published var ttsVelocidad: Double { didSet { Config.set("tts_velocidad", to: ttsVelocidad) } }
    @Published var ttsProveedor: String { didSet { Config.set("tts_proveedor", to: ttsProveedor); Voz.preactivarLocal() } }
    @Published var agentePega: Bool { didSet { Config.set("agente_pega", to: agentePega) } }
    @Published var agenteMotor: String { didSet { Config.set("agente_motor", to: agenteMotor) } }
    @Published var ttsElevenVoz: String { didSet { Config.set("tts_eleven_voz", to: ttsElevenVoz) } }
    @Published var ttsElevenStreaming: Bool { didSet { Config.set("tts_eleven_streaming", to: ttsElevenStreaming) } }
    @Published var ttsXttsCmd: String { didSet { Config.set("tts_xtts_cmd", to: ttsXttsCmd) } }
    @Published var pushToTalk: Bool { didSet { Config.set("hold_para_hablar", to: pushToTalk) } }
    @Published var doblePulsacion: Bool {
        didSet {
            Config.set("doble_pulsacion_activar", to: doblePulsacion)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
    @Published var doblePulsacionVentana: Double {
        didSet {
            Config.set("doble_pulsacion_ventana", to: doblePulsacionVentana)
            NotificationCenter.default.post(name: .betoHotkeyChanged, object: nil)
        }
    }
    @Published var previewVivo: Bool {
        didSet {
            Config.set("preview_vivo", to: previewVivo)
            if !previewVivo { PreviewVivo.detener() }
        }
    }
    @Published var espacioAlTerminar: Bool { didSet { Config.set("espacio_al_terminar", to: espacioAlTerminar) } }
    @Published var enterAlTerminar: Bool {
        didSet { Config.set("enter_al_terminar", to: enterAlTerminar); if enterAlTerminar { shiftEnterAlTerminar = false } }
    }
    @Published var shiftEnterAlTerminar: Bool {
        didSet { Config.set("shift_enter_al_terminar", to: shiftEnterAlTerminar); if shiftEnterAlTerminar { enterAlTerminar = false } }
    }

    init() {
        tecla = Config.hotkey()
        modelo = Config.model()
        microfono = Config.microfono()
        aprender = Config.aprender()
        atajoAprender = Config.atajoAprender()
        porSonido = Config.correccionPorSonido()
        silencioMax = Config.maxSilence()
        sonidos = Config.sounds()
        escCancela = Config.escCancels()
        escDoble = Config.escDoble()
        smtpHost = Config.smtpHost()
        smtpPuerto = Config.smtpPuerto()
        smtpUsuario = Config.smtpUsuario()
        smtpRemitente = Config.smtpRemitente()
        smtpClave = ApiKeys.get("SMTP_PASSWORD")
        correoDest = (Config.json0("correo_destinatarios") as? String) ?? ""
        correoAuto = Config.correoAutomatico()
        correoReglas = ResumenCorreo.reglas()
        cancelarConfirma = Config.cancelarConfirma()
        cancelarConserva = Config.cancelarConservaDesdeSegundos()
        dictadosDias = Double(Config.dictadosConservarDias())
        registroTexto = Config.registroIncluyeTexto()
        apiActiva = ApiLocal.activa()
        pausarMultimedia = Config.duckMedia()
        bajarVolumen = Config.muteToo()
        postProceso = Config.postProcess()
        pulidoProveedor = Config.pulidoProveedor()
        promptPulido = Config.customPrompt() ?? ""
        panelVisible = Config.panelVisible()
        autoAyuda = Config.autoAyudaControles()
        mostrarEnDock = Config.showInDock()
        arrancarInicio = SMAppService.mainApp.status == .enabled
        modoDesarrollo = Config.devMode()
        pulidoTimeout = Config.pulidoTimeout()
        buscarUpdateAlAbrir = Config.buscarUpdateAlAbrir()
        autoactualizar = Config.autoactualizar()
        canalActualizaciones = Config.canalActualizaciones()
        actualizacionPeriodica = Config.actualizacionPeriodica()
        actualizacionIntervalo = Config.actualizacionIntervaloHoras()
        avisoNube = Config.avisoNube()
        salvaguardaInyeccion = Config.salvaguardaInyeccion()
        sttStreaming = Config.sttStreaming()
        busquedaSemantica = Config.busquedaSemantica()
        glosarioInteligente = Config.glosarioInteligente()
        modoVivo = Config.modoVivo()
        modoVivoPausa = Config.modoVivoPausa()
        modoVivoPausaSegundos = Config.modoVivoPausaSegundos()
        modoVivoPalabras = Double(Config.modoVivoPalabras())
        modoSemantico = Config.modoSemantico()
        modoSemPalabras = Double(Config.modoSemanticoPalabras())
        modoSemUmbral = Config.modoSemanticoUmbral()
        modoSemMargen = Config.modoSemanticoMargen()
        modoGramatical = Config.modoGramatical()
        modoConfirmacionSeg = Config.modoConfirmacionSegundos()
        modoAutoMejora = Config.modoAutoMejora()
        modoIAEnrutamiento = Config.modoIAEnrutamiento()
        modoIAProveedor = Config.modoIAProveedor()
        modoIATimeout = Config.modoIATimeout()
        modoIAPalabras = Double(Config.modoIAPalabras())
        logModos = Config.logModos()
        calentarRed = Config.calentarRed()
        ahorroGlobal = Config.ahorroGlobal()
        ttsActivo = Config.ttsActivo()
        ttsVoz = Config.ttsVoz()
        ttsVelocidad = Config.ttsVelocidad()
        ttsProveedor = Config.ttsProveedor()
        agentePega = Config.agentePega()
        agenteMotor = Config.agenteMotor()
        ttsElevenVoz = Config.ttsElevenVoz()
        ttsElevenStreaming = Config.ttsElevenStreaming()
        ttsXttsCmd = Config.ttsXttsCmd()
        pushToTalk = Config.pushToTalk()
        doblePulsacion = Config.doblePulsacionActivar()
        doblePulsacionVentana = Config.doblePulsacionVentana()
        previewVivo = Config.previewVivo()
        espacioAlTerminar = Config.espacioAlTerminar()
        enterAlTerminar = Config.enterAlTerminar()
        shiftEnterAlTerminar = Config.shiftEnterAlTerminar()
    }
}

// MARK: - Grabador de atajo (captura tecla + modificadores)

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var value: String

    func makeNSView(context: Context) -> RecorderButton {
        let b = RecorderButton()
        b.onCapture = { value = $0 }
        return b
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.display(value)
    }

    final class RecorderButton: NSButton {
        var onCapture: ((String) -> Void)?
        private var recording = false
        private var monitor: Any?
        private var timeout: Timer?
        private var previo = "fn"   // último valor mostrado (para cancelar)

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        deinit { stop() }

        func display(_ v: String) {
            if !recording { title = pretty(v) + "  ✎"; previo = v }
        }
        private func pretty(_ v: String) -> String {
            v.split(separator: "+").map { p -> String in
                switch p.lowercased() {
                case "cmd", "command": return "⌘"
                case "ctrl", "control": return "⌃"
                case "opt", "alt", "option": return "⌥"
                case "shift": return "⇧"
                case "fn": return "fn"
                case "space": return "␣"
                default: return p.uppercased()
                }
            }.joined(separator: "")
        }

        @objc private func startRecording() {
            guard !recording else { return }
            recording = true
            title = "Pulsa… (Esc cancela)"   // previo ya tiene el valor actual
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                self?.handle(event)
                return nil  // consume solo mientras grabamos
            }
            // Auto-cancelar tras 5s para no dejar el teclado atrapado
            timeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                self?.cancel()
            }
        }

        private func stop() {
            timeout?.invalidate(); timeout = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            recording = false
        }

        private func cancel() {
            stop()
            display(previo)  // restaura lo que había, no cambia nada
        }

        private func finish(_ combo: String) {
            stop()
            onCapture?(combo)
            display(combo)
        }

        private func mods(_ f: NSEvent.ModifierFlags) -> [String] {
            var p: [String] = []
            if f.contains(.control) { p.append("ctrl") }
            if f.contains(.option) { p.append("opt") }
            if f.contains(.command) { p.append("cmd") }
            if f.contains(.shift) { p.append("shift") }
            return p
        }

        /// Atajos prohibidos: colisionan con el sistema o con la app.
        private static let prohibidos: Set<String> = [
            "cmd+v", "cmd+c", "cmd+x", "cmd+a", "cmd+z", "cmd+q", "cmd+w",
            "cmd+s", "cmd+tab", "cmd+space", "space",
        ]

        private var maxModsVistos: [String] = []
        private var vioFn = false

        private func handle(_ event: NSEvent) {
            guard recording else { return }

            if event.type == .keyDown {
                if event.keyCode == 53 { cancel(); return }  // Esc cancela
                guard let key = AppDelegate.keyName(for: Int(event.keyCode)) else { return }
                let m = mods(event.modifierFlags)
                let esFuncion = key.hasPrefix("f") && key.count <= 3
                // Letra/espacio sin modificador no es atajo global; F1..F12 sí.
                guard esFuncion || !m.isEmpty else {
                    title = "Añade ⌘/⌃/⌥ a esa tecla"
                    return
                }
                let combo = (m + [key]).joined(separator: "+")
                guard !Self.prohibidos.contains(combo) else {
                    title = "Ese atajo está reservado"; return
                }
                finish(combo)   // tecla+modificadores (ej. cmd+shift+d)

            } else if event.type == .flagsChanged {
                let f = event.modifierFlags
                let m = mods(f)
                if f.contains(.function) { vioFn = true }
                if m.count > maxModsVistos.count { maxModsVistos = m }
                // Al SOLTAR todo sin haber pulsado una tecla → capturar el combo
                // de puros modificadores (o fn) que se mantuvo.
                if m.isEmpty && !f.contains(.function) {
                    if maxModsVistos.count >= 2 {
                        finish(maxModsVistos.prefix(2).joined(separator: "+"))
                    } else if vioFn {
                        finish("fn")
                    }
                    maxModsVistos = []; vioFn = false
                }
            }
        }
    }
}

// MARK: - Vista principal (sidebar + detalle, escala a más secciones)

/// Secciones de la ventana. Para sumar una nueva: agregar el caso aquí y su
/// vista en `detalle` — el sidebar crece solo, sin apretar nada.
private enum Seccion: String, CaseIterable, Identifiable {
    case ajustes = "Ajustes"
    case modelos = "Modelos"
    case modos = "Modos"
    case asistente = "Asistente"
    case pendientes = "Tareas y notas"
    case historial = "Historial"
    case bitacora = "Bitácora"
    case acciones = "Acciones"
    case transcribir = "Transcribir"
    case salud = "Salud"
    case estadisticas = "Estadísticas"
    case creditos = "Créditos"

    var id: String { rawValue }
    var icono: String {
        switch self {
        case .ajustes: return "gearshape.fill"
        case .modelos: return "cpu.fill"
        case .modos: return "wand.and.stars"
        case .asistente: return "brain.head.profile"
        case .pendientes: return "checklist"
        case .historial: return "clock.arrow.circlepath"
        case .bitacora: return "record.circle"
        case .acciones: return "bolt.fill"
        case .transcribir: return "waveform.badge.mic"
        case .salud: return "heart.text.square.fill"
        case .estadisticas: return "chart.bar.fill"
        case .creditos: return "heart.fill"
        }
    }
}

/// Navegación programática a una sección (p. ej. desde el modal de novedades).
final class NavAjustes: ObservableObject {
    static let shared = NavAjustes()
    @Published var ir: String?
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    @ObservedObject private var nav = NavAjustes.shared
    @State private var seccion: Seccion

    init() {
        // Pruebas de UI: BTODICTA_SECCION=Modelos abre esa sección directo.
        let pedida = ProcessInfo.processInfo.environment["BTODICTA_SECCION"] ?? ""
        _seccion = State(initialValue: Seccion(rawValue: pedida) ?? .ajustes)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detalle
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity,
               minHeight: 560, idealHeight: 640, maxHeight: .infinity)
        .onChange(of: nav.ir) { _, v in
            if let v, let s = Seccion(rawValue: v) { seccion = s; nav.ir = nil }
        }
    }

    @ViewBuilder
    private var detalle: some View {
        switch seccion {
        case .modelos: ModelsView()
        case .modos: ModosView()
        case .asistente: AgenteView()
        case .pendientes: NotasView()
        case .historial: HistorialView()
        case .bitacora: ContinuoView()
        case .acciones: acciones
        case .transcribir: TranscribeView()
        case .salud: SaludView()
        case .estadisticas: StatsView()
        case .creditos: creditos
        case .ajustes: ajustes
        }
    }

    // ---- Sidebar ----
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            encabezado
            ForEach(Seccion.allCases) { s in
                Button { seccion = s } label: {
                    HStack(spacing: 9) {
                        Image(systemName: s.icono)
                            .font(.system(size: 13))
                            .frame(width: 22)
                            .foregroundStyle(seccion == s ? .white : acento)
                        Text(s.rawValue)
                            .font(.system(size: 13, weight: seccion == s ? .semibold : .regular))
                            .foregroundStyle(seccion == s ? .white : .primary)
                        Spacer()
                    }
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .background(seccion == s ? acento : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Abrir la sección \(s.rawValue) de BtoDicta")
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }
            Spacer()
            pieActualizacion
        }
        .frame(width: 190)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // ---- Pie del sidebar: versión + actualización con un clic ----
    @State private var estadoUpdate: Updater.Estado = Updater.ultimoEstado
    @State private var mostrarNotas = false
    @State private var keyInputs: [String: String] = [:]
    @State private var detectTrigger = 0
    @State private var descubriendoMod = false
    @State private var msgMod: String?
    @State private var msgModId: String?
    @State private var msgModOK = false
    @State private var buscandoLocales = false
    @State private var buscoLocales = false
    @State private var precioIn = ""
    @State private var precioOut = ""

    private var pieActualizacion: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("v\(Version.numero)")
                .font(.caption2).foregroundStyle(.tertiary)
            switch estadoUpdate {
            case .reposo:
                Button("Verificar actualización") {
                    estadoUpdate = .buscando
                    Updater.verificar { estadoUpdate = $0 }
                }
                .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
            case .buscando:
                Label("Buscando…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            case .alDia:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Ya estás en la última versión", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                    if let ultima = Updater.ultimaRevision {
                        Text("Revisado \(ultima.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Comprobar de nuevo") {
                        estadoUpdate = .buscando
                        Updater.verificar { estadoUpdate = $0 }
                    }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
                }
            case .disponible(let v, let dmg, let notas):
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        estadoUpdate = .descargando(0)
                        Updater.actualizar(dmg: dmg) { estadoUpdate = $0 }
                    } label: {
                        Label("Actualizar a v\(v)", systemImage: "arrow.down.circle.fill")
                            .font(.caption2).bold()
                    }
                    .buttonStyle(.borderedProminent).tint(acento).controlSize(.small)
                    if !notas.isEmpty {
                        Button("Ver novedades") { mostrarNotas = true }
                            .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
                            .popover(isPresented: $mostrarNotas, arrowEdge: .trailing) {
                                ScrollView {
                                    MarkdownSimple(texto: notas).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                }.frame(width: 360, height: 300)
                            }
                    }
                }
            case .descargando(let p):
                VStack(alignment: .leading, spacing: 3) {
                    Label(p >= 0.99 ? "Instalando… se reiniciará sola" : "Descargando… \(Int(p * 100))%",
                          systemImage: "arrow.down.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: p).frame(width: 140).tint(acento)
                }
            case .error(let msg):
                VStack(alignment: .leading, spacing: 3) {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                    Button("Reintentar") {
                        estadoUpdate = .buscando
                        Updater.verificar { estadoUpdate = $0 }
                    }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(acento)
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .onAppear {
            // "Apenas se abre": si está activado y aún no buscamos, revisa solo.
            if case .reposo = estadoUpdate, Config.buscarUpdateAlAbrir() {
                estadoUpdate = .buscando
                Updater.verificar { estadoUpdate = $0 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Updater.notificacion)) { _ in
            // Arranque, revisión periódica o cambio de canal: refleja cualquier
            // resultado, no solo cuando existe una versión nueva.
            estadoUpdate = Updater.ultimoEstado
        }
    }

    private var encabezado: some View {
        HStack(spacing: 10) {
            if let logo = NSImage(contentsOfFile:
                Bundle.main.path(forResource: "logo-original", ofType: "png") ?? "") {
                Image(nsImage: logo).resizable().frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("BtoDicta").font(.headline).bold()
                Text("Dictado por voz").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
    }

    // ---- Ajustes ----
    private var ajustes: some View {
        Group {
            tarjeta("General", "gearshape") {
                fila("Tecla de dictado") {
                    HotkeyRecorder(value: $m.tecla).frame(width: 120, height: 24)
                }
                Toggle("Mantener presionado para hablar (push-to-talk)", isOn: $m.pushToTalk)
                Text(m.pushToTalk
                     ? "Grabas mientras tengas la tecla presionada; al soltarla, termina y transcribe. Funciona con fn o combinaciones de modificadores (ctrl+opt…), no con F1–F12."
                     : "Modo toque: un toque empieza, otro toque termina. Actívalo para grabar solo mientras mantienes la tecla (fn o modificadores).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Doble pulsación para activar", isOn: $m.doblePulsacion)
                if m.doblePulsacion {
                    HStack {
                        Text("Rapidez del doble toque")
                        Slider(value: $m.doblePulsacionVentana, in: 0.25...1.0, step: 0.05)
                        Text(String(format: "%.2f s", m.doblePulsacionVentana))
                            .monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    Text(m.pushToTalk
                         ? "Toca una vez; en la segunda pulsación mantén la tecla para grabar y suéltala para terminar."
                         : "En reposo, dos pulsaciones rápidas inician. Una sola pulsación detiene el dictado.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Ver en vivo lo que dices (notch)", isOn: $m.previewVivo)
                if m.previewVivo {
                    Text("Mientras grabas, el notch muestra lo que vas diciendo (💬, transcriptor nativo de Apple, macOS 26). Es solo visual: la transcripción real sigue siendo tu cascada de modelos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                fila("Micrófono") {
                    Picker("", selection: $m.microfono) {
                        Text("Integrado del Mac (recomendado)").tag("")
                        Text("Automático (el del sistema)").tag("auto")
                        ForEach(Microfono.disponibles().filter { !$0.integrado }) { d in
                            Text(d.nombre).tag(d.uid)
                        }
                    }.labelsHidden().frame(width: 230)
                }
                Text("Fijo al integrado, el iPhone cercano ya no roba el micrófono a media grabación.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Sonidos de inicio y fin", isOn: $m.sonidos)
                Toggle("Cancelar con Esc", isOn: $m.escCancela)
                Toggle("Pedir dos pulsaciones para cancelar", isOn: $m.escDoble)
                    .disabled(!m.escCancela).padding(.leading, 18)
                Text("Mientras grabas, Esc queda capturado en todo el sistema: si lo pulsas para cerrar una ventana cualquiera, cortabas el dictado. Con esto la primera pulsación solo avisa en el notch y hace falta repetirla.")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 18)
                Toggle("Confirmar también al cancelar tocando el notch", isOn: $m.cancelarConfirma)
                    .padding(.leading, 18)
                HStack {
                    Text("Guardar lo cancelado desde")
                    Stepper(value: $m.cancelarConserva, in: 0...60, step: 1) {
                        Text(m.cancelarConserva == 0 ? "siempre" : "\(Int(m.cancelarConserva)) s")
                            .monospacedDigit()
                    }
                }.padding(.leading, 18)
                Text("Cancelar NUNCA borra lo grabado: queda en el historial y lo recuperas desde Transcribir. Por debajo de este tiempo se descarta, porque es una pulsación sin nada dentro.")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 18)

                Divider().padding(.vertical, 6)
                Text("Audio de trabajo").font(.headline)
                HStack {
                    Text("Conservar el audio de cada dictado")
                    Stepper(value: $m.dictadosDias, in: 0...365, step: 1) {
                        Text(m.dictadosDias == 0 ? "siempre" : "\(Int(m.dictadosDias)) días")
                            .monospacedDigit()
                    }
                }
                Text("Mientras dictas, el audio se escribe a disco en vez de acumularse en memoria: así una grabación de horas no hace crecer la aplicación. Ese archivo de trabajo se barre pasados estos días. NO es el del historial, que se guarda aparte y no se toca nunca. Ronda los 115 MB por hora dictada; con 0 no se barre nada.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider().padding(.vertical, 6)
                Text("Dejar que otros programas de este Mac transcriban").font(.headline)
                Toggle("Abrir la puerta local", isOn: $m.apiActiva)
                Text("Otros proyectos tuyos pueden pedirle a BtoDicta que transcriba un audio o pula un texto, en vez de instalar sus propios modelos. Escucha SOLO en este equipo (127.0.0.1) y solo atiende a quien traiga el token de abajo. Viene cerrada.")
                    .font(.caption).foregroundStyle(.secondary)
                if m.apiActiva {
                    HStack {
                        Text("Token").font(.caption)
                        TextField("", text: .constant(m.apiToken))
                            .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                            .disabled(true)
                        Button("Copiar") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.apiToken, forType: .string)
                        }
                        Button("Cambiar") { m.apiToken = ApiLocal.regenerarToken() }
                    }
                    Text("Trátalo como una contraseña: quien lo tenga puede transcribir con tus motores y gastar tu saldo. Si lo cambias, los programas que lo usaran dejarán de entrar hasta que les des el nuevo. Prueba: curl 127.0.0.1:\(ApiLocal.puerto())/estado")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Solo puede leer audios de las carpetas de Descargas, Documentos y la temporal del sistema; nada más del disco.")
                        .font(.caption2).foregroundStyle(.secondary)

                }
                }

                Divider().padding(.vertical, 6)
                // FUERA del bloque de la API a propósito.
                //
                // Antes vivía dentro, y con la puerta apagada —que es como viene
                // de fábrica— la extensión era invisible: no había forma de
                // descubrir que existe. Ahora se ve siempre, y si la puerta está
                // cerrada el propio aviso lo dice al exportar.
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Extensión para el navegador").font(.caption).bold()
                    Spacer()
                    Button("Mostrar cómo instalarla…") { ExportarExtension.mostrarParaInstalar() }
                        .disabled(!ExportarExtension.disponible)
                }
                Text("Le cuenta a la bitácora qué pestaña estás mirando y cuál está sonando — eso el sistema no puede verlo solo, y sin ese dato un vídeo de fondo acaba anotado como trabajo. Vive en ~/.btodicta/extension y BtoDicta la mantiene al día ahí: instálala desde esa carpeta y recibirá las mejoras. Es opcional: BtoDicta funciona igual sin ella.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !m.avisoExtension.isEmpty {
                    Text(m.avisoExtension)
                        .font(.caption2).foregroundStyle(.orange)
    
                Divider().padding(.vertical, 6)
                Toggle("Guardar el texto dictado en el registro", isOn: $m.registroTexto)
                Text("El registro es local, rota cada semana y no sale de tu equipo; a cambio es lo único que permite reconstruir después qué dictaste y qué devolvió cada motor —así se ve, por ejemplo, que un pulido te recortó el texto—. Apágalo si compartes pantalla a menudo o dictas datos de terceros: las líneas siguen, con la medida en vez del contenido.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider().padding(.vertical, 6)
                Text("Resumen de la bitácora por correo").font(.headline)
                Text("BtoDicta junta lo transcrito del periodo, lo consolida con tu IA en un solo texto sin repetir ideas y te lo manda. Nada sale de tu equipo hasta que pongas un destinatario.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Servidor (mail.tudominio.com)", text: $m.smtpHost)
                    TextField("Puerto", value: $m.smtpPuerto, format: .number).frame(width: 70)
                }
                TextField("Usuario (tu correo completo)", text: $m.smtpUsuario)
                SecureField("Clave", text: $m.smtpClave)
                TextField("Remitente (si difiere del usuario)", text: $m.smtpRemitente)
                TextField("Destinatarios, separados por coma", text: $m.correoDest)
                Text("Puerto 465 con SSL. Con Gmail hace falta una «contraseña de aplicación», no la de tu cuenta.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Probar envío") {
                        m.correoPrueba = "Enviando…"
                        CorreoSMTP.enviar(ResumenCorreo.cuenta(),
                                          para: Config.correoDestinatarios(),
                                          asunto: "BtoDicta — prueba de correo",
                                          cuerpo: "Si lees esto, la configuración de correo de BtoDicta funciona.") { r in
                            switch r {
                            case .success: m.correoPrueba = "✓ Enviado. Revisa la bandeja."
                            case .failure(let e): m.correoPrueba = "✗ \(e.localizedDescription)\n→ \(e.consejo)"
                            }
                        }
                    }
                    Text(m.correoPrueba).font(.caption)
                        .foregroundStyle(m.correoPrueba.hasPrefix("✓") ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Enviarlo solo, a su hora", isOn: $m.correoAuto)
                if m.correoAuto {
                    Text("Cada línea es un envío independiente: su hora, su periodo y los días en que toca. Puedes tener los que quieras.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($m.correoReglas) { $r in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $r.activa).labelsHidden()
                            TextField("07:00", text: $r.hora).frame(width: 58)
                            Picker("", selection: $r.periodo) {
                                Text("de hoy").tag("hoy")
                                Text("de ayer").tag("ayer")
                                Text("de la semana").tag("semana")
                            }.labelsHidden().frame(width: 130)
                            Picker("", selection: $r.dias) {
                                Text("cada día").tag("diario")
                                Text("lunes").tag("lun")
                                Text("martes").tag("mar")
                                Text("miércoles").tag("mie")
                                Text("jueves").tag("jue")
                                Text("viernes").tag("vie")
                                Text("sábados").tag("sab")
                                Text("domingos").tag("dom")
                                Text("entre semana").tag("lun,mar,mie,jue,vie")
                            }.labelsHidden().frame(width: 130)
                            Button {
                                m.correoReglas.removeAll { $0.id == r.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Quitar este envío")
                        }
                    }
                    Button {
                        m.correoReglas.append(ResumenCorreo.Regla(hora: "07:00", periodo: "ayer", dias: "diario"))
                    } label: { Label("Añadir envío", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                    if m.correoReglas.isEmpty {
                        Text("Sin envíos configurados: no se mandará nada solo.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Text("También puedes mandarlo cuando quieras desde el menú de la barra: «Enviar resumen por correo».")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Mostrar el panel al dictar", isOn: $m.panelVisible)
                Toggle("Mostrar autoayuda rápida al pasar el cursor", isOn: $m.autoAyuda)
                Text("Explica al instante para qué sirve cada botón o enlace. VoiceOver conserva estas descripciones aunque ocultes la burbuja.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Mostrar en el Dock", isOn: $m.mostrarEnDock)
                Toggle("Arrancar al iniciar sesión", isOn: $m.arrancarInicio)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-cerrar tras \(Int(m.silencioMax)) s de silencio").font(.subheadline)
                    Slider(value: $m.silencioMax, in: 15...300, step: 15).tint(acento)
                }
            }
            tarjeta("Al terminar el dictado", "return") {
                Toggle("Añadir un espacio al final", isOn: $m.espacioAlTerminar)
                Text("Separa dictados seguidos (si no, quedan pegados).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pulsar Enter al terminar", isOn: $m.enterAlTerminar)
                Text("Envía en chats (WhatsApp, Slack…) o salta de línea en editores.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pulsar Shift+Enter al terminar", isOn: $m.shiftEnterAlTerminar)
                Text("Salto de línea suave (sin enviar). Excluyente con Enter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Pulido con IA", "waveform") {
                Toggle("Pulir el texto con IA", isOn: $m.postProceso)
                if m.postProceso {
                    let _ = detectTrigger        // re-render tras detectar/conectar
                    let conectadas = ChatIA.conectadasPulido
                    if conectadas.isEmpty {
                        Text("Conecta una IA de chat (abajo) para usar el pulido.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        fila("IA para pulido y traducción") {
                            Picker("", selection: $m.pulidoProveedor) {
                                ForEach(conectadas, id: \.id) { Text($0.etiqueta).tag($0.id) }
                            }.labelsHidden().frame(width: 300)
                        }
                        Text("Muestra el proveedor y el modelo activo. Se usa para pulir y traducir.")
                            .font(.caption).foregroundStyle(.secondary)
                        // Selector de MODELO del proveedor elegido (cualquiera:
                        // gateway, nube o local). Elige al vuelo + Descubrir.
                        if let sel = conectadas.first(where: { $0.id == m.pulidoProveedor }) {
                            selectorModelo(sel)
                        }
                        // Failover: cascada ordenada de respaldo (si el 1º cae, el 2º…)
                        if conectadas.count > 1 {
                            SeccionPlegable("Failover de pulido (respaldo si uno cae)") {
                                let _ = detectTrigger
                                let orden = ChatIA.cadenaPulido()
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("El 1º es la IA elegida arriba. Si no responde, se prueban los respaldos en este orden.")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    ForEach(Array(orden.enumerated()), id: \.element.id) { i, ia in
                                        HStack(spacing: 6) {
                                            Text("\(i + 1).").font(.caption).foregroundStyle(.secondary)
                                            Text(ia.etiqueta).font(.caption).lineLimit(1)
                                            Spacer()
                                            Button { moverCascada(orden.map { $0.id }, i, -1) } label: { Image(systemName: "chevron.up") }
                                                .buttonStyle(.plain).disabled(i <= 1)
                                                .help("Subir esta IA en el failover de pulido")
                                            Button { moverCascada(orden.map { $0.id }, i, 1) } label: { Image(systemName: "chevron.down") }
                                                .buttonStyle(.plain).disabled(i == 0 || i == orden.count - 1)
                                                .help("Bajar esta IA en el failover de pulido")
                                        }
                                    }
                                }.padding(.top, 4)
                            }
                        }
                    }
                    // Conectar IAs de nube por key (OpenRouter, DeepSeek, xAI…)
                    SeccionPlegable("Conectar más IAs de chat") {
                        VStack(alignment: .leading, spacing: 8) {
                            CodexCuentaConexionView { detectTrigger += 1 }
                            Divider()
                            ForEach([("OPENROUTER_API_KEY", "OpenRouter"), ("GEMINI_API_KEY", "Gemini (Google)"),
                                     ("ANTHROPIC_API_KEY", "Anthropic (Claude)"), ("DEEPSEEK_API_KEY", "DeepSeek"),
                                     ("XAI_API_KEY", "xAI (Grok)"), ("OPENAI_API_KEY", "OpenAI"),
                                     ("MOONSHOT_API_KEY", "Moonshot AI · Kimi API"),
                                     ("KIMI_CODE_API_KEY", "Kimi Code · cuenta/plan"),
                                     ("MISTRAL_API_KEY", "Mistral"),
                                     ("CEREBRAS_API_KEY", "Cerebras (gratis)"), ("GITHUB_MODELS_KEY", "GitHub Models (gratis)"),
                                     ("NVIDIA_API_KEY", "NVIDIA NIM (gratis)"), ("TOGETHER_API_KEY", "Together AI"),
                                     ("NOVITA_API_KEY", "Novita AI"), ("ZAI_CHAT_API_KEY", "Z.ai (GLM, gratis)"),
                                     ("SILICONFLOW_API_KEY", "SiliconFlow")], id: \.0) { env, nombre in
                                if ApiKeys.get(env).isEmpty {
                                    HStack(spacing: 8) {
                                        SecureField("API key de \(nombre)", text: Binding(
                                            get: { keyInputs[env] ?? "" }, set: { keyInputs[env] = $0 }))
                                            .textFieldStyle(.roundedBorder)
                                        Button("Conectar") {
                                            ApiKeys.set(env, keyInputs[env] ?? ""); keyInputs[env] = ""; detectTrigger += 1
                                        }.disabled((keyInputs[env] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                        AyudaKey(env: env)   // ayuda (tooltip) + "Conseguir clave"
                                    }
                                } else {
                                    HStack {
                                        Label("\(nombre) conectado", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                                        AyudaKey(env: env, soloIcono: true)
                                        Spacer()
                                        Button("Quitar") { ApiKeys.set(env, ""); detectTrigger += 1 }.controlSize(.small)
                                    }
                                }
                            }
                            Text("Acceso por cuenta solo cuando el proveedor lo autoriza oficialmente. Kimi Code usa una key de tu membresía y su cuota; para pulido/producto general, Moonshot API es la vía recomendada. BtoDicta nunca reutiliza cookies ni contraseñas del navegador.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Divider()
                            Button("IA personalizada (gateway propio)…") { IAPersonalizadaWindow.show() }
                            HStack(spacing: 8) {
                                Text("Locales: LM Studio / Ollama se detectan solos si están corriendo.")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Button(buscandoLocales ? "Buscando…" : "Buscar") {
                                    buscandoLocales = true
                                    ChatIA.detectarLocales { buscandoLocales = false; buscoLocales = true; detectTrigger += 1 }
                                }.controlSize(.small).disabled(buscandoLocales)
                            }
                            let locales = ["lmstudio", "ollama"].filter { ChatIA.modelosLocales[$0] != nil }
                            ForEach(locales, id: \.self) { lid in
                                Text("• \(lid == "lmstudio" ? "LM Studio" : "Ollama") ✓ (\(ChatIA.modelosLocales[lid] ?? ""))")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            if buscoLocales && locales.isEmpty && !buscandoLocales {
                                Text("Ninguno corriendo. Abre LM Studio / Ollama con un modelo de CHAT cargado y pulsa Buscar (no necesitan API key).")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        .padding(.top, 6)
                        // Auto-detecta al abrir esta sección (sin tener que pulsar
                        // Buscar): sondeo EN VIVO con sesión fresca.
                        .onAppear { ChatIA.detectarLocales { buscoLocales = true; detectTrigger += 1 } }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estilo del pulido (opcional)").font(.subheadline)
                        TextField("ej: trato formal de usted", text: $m.promptPulido, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }
                }
                Text("Los modelos y proveedores se configuran en la pestaña Modelos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Aprendizaje", "brain.head.profile") {
                Toggle("Aprender de mis correcciones", isOn: $m.aprender)
                Text("Cuando corriges el texto dictado ahí donde lo pegaste (antes de enviarlo), la app aprende la regla sola (ej: Sentrix → Zentrix). 100% local.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("• Automático en apps nativas (Notas, Mail, Word, Pages…).")
                    .font(.caption).foregroundStyle(.secondary)
                fila("Atajo: aprender de la selección") {
                    HotkeyRecorder(value: $m.atajoAprender).frame(width: 120, height: 24)
                }
                Text("• En Claude Code CLI, terminales o cualquier app: corrige, SELECCIONA el texto corregido y pulsa este atajo — aprende de tu selección.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Corrección por sonido (fonética)", isOn: $m.porSonido)
                Text("Corrige palabras que SUENAN como un término, aunque no sea una variante ya conocida (ej: cualquier cosa que suene a Zentrix). Actívala por término en Editar reemplazos (casilla 🔊). Más potente pero puede sobre-corregir: revisa lo que hizo en Estadísticas (con Modo desarrollo) y revierte apagando el término.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Multimedia", "speaker.wave.2") {
                Toggle("Pausar música y videos al dictar", isOn: $m.pausarMultimedia)
                Toggle("Bajar el volumen al dictar", isOn: $m.bajarVolumen)
                Text("Al terminar, todo se reanuda y el volumen vuelve exacto.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Avanzado: plegado por defecto; el TÍTULO completo abre/cierra.
            VStack(alignment: .leading, spacing: 10) {
                SeccionPlegable("Avanzado", icono: "wrench.and.screwdriver") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Modo desarrollo (notas de depuración)", isOn: $m.modoDesarrollo)
                        Divider()
                        Toggle("Buscar actualización al abrir", isOn: $m.buscarUpdateAlAbrir)
                        Text("Al arrancar, revisa en silencio si hay versión nueva y te lo muestra aquí abajo. Nunca instala nada sin permiso.")
                            .font(.caption).foregroundStyle(.secondary)
                        fila("Canal de actualizaciones") {
                            Picker("", selection: $m.canalActualizaciones) {
                                Text("Automático (recomendado)").tag("auto")
                                Text("Solo estables").tag("estable")
                                Text("Estables y beta").tag("beta")
                            }.labelsHidden().frame(width: 220)
                        }
                        Text("Automático sigue betas si esta copia ya es beta; cuando uses una versión estable, no te ofrece betas. Así el paso a producción no rompe el actualizador.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Revisar periódicamente mientras BtoDicta está abierto", isOn: $m.actualizacionPeriodica)
                        if m.actualizacionPeriodica {
                            fila("Cada") {
                                Picker("", selection: $m.actualizacionIntervalo) {
                                    Text("1 hora").tag(1.0)
                                    Text("3 horas").tag(3.0)
                                    Text("6 horas").tag(6.0)
                                    Text("12 horas").tag(12.0)
                                    Text("24 horas").tag(24.0)
                                }.labelsHidden().frame(width: 120)
                            }
                        }
                        Toggle("Autoactualizar (instalar sola la versión nueva)", isOn: $m.autoactualizar)
                            .disabled(!m.buscarUpdateAlAbrir && !m.actualizacionPeriodica)
                        Text("Si encuentra una actualización al abrir o en una revisión periódica, la baja e instala sola (la app se reinicia). Si está apagado, solo te avisa y tú decides.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Avisos de privacidad al pulir con IA de nube/terceros", isOn: $m.avisoNube)
                        Text("Muestra un recordatorio cuando el pulido usa una IA de nube o un gateway de terceros (tu texto sale de tu Mac). Apágalo si ya lo tienes claro.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Salvaguarda anti-inyección (extra, para IAs de terceros)", isOn: $m.salvaguardaInyeccion)
                        Text("Si el texto pulido por la IA se dispara de tamaño o mete comandos de shell que tú no dictaste, pega tu dictado ORIGINAL en vez del pulido. Nunca bloquea ni borra: en el peor caso pierdes el pulido, no tus palabras. Útil si usas gateways de terceros y dictas en terminales. Default apagado.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("STT en vivo para la nube (WebSocket)", isOn: $m.sttStreaming)
                        Text("Si tu motor #1 lo soporta (Deepgram, Soniox, AssemblyAI, Speechmatics o Gladia), transcribe EN VIVO por WebSocket — ves el texto mientras hablas — en vez de esperar a soltar la tecla. Necesita la key de ese proveedor. Apagado, transcriben por lotes como el resto. Default apagado.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Búsqueda por significado en el Historial (semántica)", isOn: $m.busquedaSemantica)
                        Text("Activa el modo de buscar por IDEA (no por palabra exacta) en el Historial, con embeddings. Elige con cuál IA se calculan:")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("Voz del asistente (texto → voz)").font(.subheadline)
                        Toggle("Que BtoDicta pueda HABLARTE (TTS)", isOn: $m.ttsActivo)
                        Text("La identidad, personalidad, cerebro, autonomía y memoria se configuran en la pestaña Asistente. Aquí eliges únicamente con qué voz habla. Si un motor falla, la cascada termina en la voz de macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                        if m.ttsActivo {
                            fila("Motor") {
                                Picker("", selection: $m.ttsProveedor) {
                                    Text("Voz de macOS (gratis, local)").tag("apple")
                                    Text("ElevenLabs — tu voz clonada (nube)").tag("elevenlabs")
                                    Text("Clon local (XTTS / Qwen3‑MLX / ONNX)").tag("xtts_local")
                                    ForEach(TTSCloud.catalogo) { p in Text("\(p.nombre) (nube)").tag(p.id) }
                                }.labelsHidden().frame(width: 300)
                            }
                            if m.ttsProveedor == "apple" {
                                fila("Voz") {
                                    Picker("", selection: $m.ttsVoz) {
                                        Text("Automática (español)").tag("")
                                        ForEach(TTS.voces(), id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
                                    }.labelsHidden().frame(width: 260)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Velocidad: \(String(format: "%.2f", m.ttsVelocidad))").font(.caption)
                                    Slider(value: $m.ttsVelocidad, in: 0.2...0.7, step: 0.02).tint(acento).frame(width: 260)
                                }
                            }
                            if m.ttsProveedor == "elevenlabs" {
                                fila("voice_id") {
                                    TextField("qoHnXuIkkICzacInt72I", text: $m.ttsElevenVoz)
                                        .textFieldStyle(.roundedBorder).frame(width: 260)
                                }
                                Toggle("Streaming por WebSocket (suena mientras se genera)", isOn: $m.ttsElevenStreaming)
                                Text("Tu voz clonada de ElevenLabs (usa tu ELEVENLABS_API_KEY de la pestaña Modelos). Modelo eleven_flash_v2_5 (baja latencia). Con streaming, el audio empieza a sonar en ~75-130ms (PCM por WebSocket); si falla, cae al modo normal.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if m.ttsProveedor == "xtts_local" {
                                VocesLocalesEditor()
                            }
                            if TTSCloud.proveedor(m.ttsProveedor) != nil {
                                TTSNubeConfig(id: m.ttsProveedor)
                            }
                            Button("🔊 Probar voz") {
                                Voz.decir("Hola. Soy BtoDicta y ya puedo hablarte con el motor que elegiste.")
                            }.controlSize(.small)
                        }
                        Divider()
                        Toggle("Modo AHORRO: dormir lo pesado tras inactividad (fn despierta)", isOn: $m.ahorroGlobal)
                        Text("Si no usas BtoDicta por unos minutos (los de 'dormir el clon'), libera lo que consume recursos: el clon local (~2 GB de RAM) y el latido de red. Al grabar (fn) revive todo. Para no cargar la Mac cuando no lo usas.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Toggle("Despertar la red al grabar (mitiga latencia con VPN)", isOn: $m.calentarRed)
                        Text("Si usas VPN (WireGuard/OpenVPN/etc.) que 'duerme' cuando está inactiva, el 1er dictado podía tardar ~14s. Esto despierta la red mientras hablas. Es un pedido diminuto, nunca frena el dictado, y funciona con cualquier VPN o ninguna. Apágalo si no lo quieres.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Registro detallado de modos (para analizar y mejorar)", isOn: $m.logModos)
                        Text("Guarda cada decisión de modos/acciones (por voz/cadena/contexto/semántico, con score) en ~/.btodicta/logs/modos.jsonl — para revisar qué reconoció bien y afinar. Ábrelo desde Ajustes → Modos (icono de lupa). 100% local.")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        EmbeddingMotorPicker().disabled(!m.busquedaSemantica && !m.glosarioInteligente && !m.modoSemantico)
                        Toggle("Glosario inteligente (pulido más rápido)", isOn: $m.glosarioInteligente)
                        Text("En el pulido, envía a la IA SOLO los términos del glosario afines a lo que dictaste (con embeddings), no los 80+. Prompt más corto = más rápido, y escala aunque tu glosario crezca. Usa el motor de embeddings de arriba; la 1ª vez calienta los vectores en segundo plano (mientras, usa el glosario normal).")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("Entender pedidos naturales y cadenas de acciones", isOn: $m.modoGramatical)
                        Text("Entiende «por favor traduce esto y envíalo por correo» sin exigir la palabra modo. Analiza relaciones verbales, no sustantivos sueltos; antes de ejecutar muestra un plan claro para confirmar.")
                            .font(.caption).foregroundStyle(.secondary)
                        if m.modoGramatical {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tiempo para leer la confirmación: \(Int(m.modoConfirmacionSeg)) s").font(.caption)
                                Slider(value: $m.modoConfirmacionSeg, in: 6...30, step: 1)
                                    .tint(acento).frame(width: 260)
                                Text("Fn confirma con una sola pulsación. X, clic o esperar descartan únicamente el plan y continúan con el modo normal.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Cambiar el modo EN VIVO mientras hablo", isOn: $m.modoVivo)
                        Text("Si el dictado empieza con \"modo agente\", \"modo traducir quichua\", etc., el nombre y color del notch cambian apenas se reconoce. Solo examina el inicio y cada grabación conserva su propia decisión.")
                            .font(.caption).foregroundStyle(.secondary)
                        if m.modoVivo {
                            Toggle("Confirmar el modo cuando hago una pausa", isOn: $m.modoVivoPausa)
                            Text("Puedes decir \"modo agente\", quedarte callado y continuar: la pausa confirma el comando, pero NO termina la grabación.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if m.modoVivoPausa {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pausa para confirmar: \(String(format: "%.1f", m.modoVivoPausaSegundos)) s").font(.caption)
                                    Slider(value: $m.modoVivoPausaSegundos, in: 0.8...4, step: 0.2)
                                        .tint(acento).frame(width: 260)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Máximo del inicio a escuchar: \(Int(m.modoVivoPalabras)) palabras").font(.caption)
                                Slider(value: $m.modoVivoPalabras, in: 3...14, step: 1)
                                    .tint(acento).frame(width: 260)
                                Text("Evita interpretar como comando algo dicho después dentro del contenido.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Reconocimiento inteligente de modos por voz (semántico)", isOn: $m.modoSemantico)
                        Text("Entiende el llamado de un modo aunque lo digas de mil formas (\"modo mándale un WhatsApp…\", \"por favor necesito traducir…\"). En comandos explícitos exige una separación clara entre el 1.º y 2.º candidato; en pedidos naturales pregunta antes de actuar. Si no hay coincidencia, sigue como texto normal. Usa el motor de embeddings; la 1ª vez calienta en 2º plano. Agrega tus propias frases por modo en Ajustes → Modos.")
                            .font(.caption).foregroundStyle(.secondary)
                        if m.modoSemantico {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Palabras del inicio a analizar: \(Int(m.modoSemPalabras))").font(.caption)
                                Slider(value: $m.modoSemPalabras, in: 2...10, step: 1).tint(acento).frame(width: 260)
                                Text("Cuántas palabras del comando se miran (menos = intención más limpia; más = frases largas).").font(.caption2).foregroundStyle(.secondary)
                                Text("Sensibilidad (umbral): \(String(format: "%.2f", m.modoSemUmbral))").font(.caption)
                                Slider(value: $m.modoSemUmbral, in: 0.35...0.75, step: 0.05).tint(acento).frame(width: 260)
                                Text("Más alto = más estricto (menos falsos, pero puede no reconocer). Más bajo = más permisivo.").font(.caption2).foregroundStyle(.secondary)
                                Text("Separación entre 1.º y 2.º candidato: \(String(format: "%.2f", m.modoSemMargen))").font(.caption)
                                Slider(value: $m.modoSemMargen, in: 0.02...0.20, step: 0.01).tint(acento).frame(width: 260)
                                Text("Si dos modos quedan demasiado cerca, no adivina: muestra la ambigüedad en la confirmación.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Aprender de mis Sí/No y afinar el umbral", isOn: $m.modoAutoMejora)
                        Text("Guarda solo estadísticas locales y mueve el umbral semántico en pasos pequeños (0,02 máx.). Las acciones externas siempre se confirman.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Toggle("Usar una IA activa solo como último árbitro", isOn: $m.modoIAEnrutamiento)
                        if m.modoIAEnrutamiento {
                            VStack(alignment: .leading, spacing: 2) {
                                Picker("IA para desempatar", selection: $m.modoIAProveedor) {
                                    Text("La IA activa de Pulido").tag("")
                                    ForEach(ChatIA.conectadasPulido.filter { !$0.esCuentaCodex }, id: \.id) { ia in
                                        Text(ia.etiqueta).tag(ia.id)
                                    }
                                }.frame(maxWidth: 430)
                                Text("Máximo que puede leer del inicio: \(Int(m.modoIAPalabras)) palabras").font(.caption)
                                Slider(value: $m.modoIAPalabras, in: 6...30, step: 1).tint(acento).frame(width: 260)
                                Text("Espera máxima del árbitro: \(String(format: "%.1f", m.modoIATimeout)) s").font(.caption)
                                Slider(value: $m.modoIATimeout, in: 1.5...8, step: 0.5).tint(acento).frame(width: 260)
                                Text("Solo recibe la zona de intención y el catálogo de modos. Este árbitro de pocos segundos usa una API/local directa; Codex CLI queda disponible para ejecutar el Modo, pero no para este desempate estricto. Si no hay IA, falla o tarda, continúa sin bloquear.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Espera base del pulido: \(Int(m.pulidoTimeout)) s por proveedor").font(.subheadline)
                            Slider(value: $m.pulidoTimeout, in: 5...60, step: 1).tint(acento)
                            Text("Textos cortos: salto rápido al siguiente modelo. Texto o contexto largo: se amplía automáticamente hasta 120 s. Sin conexión o cuota, el proveedor entra en cuarentena temporal. Si ninguno responde, se conserva el original.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // ---- Acciones ----
    private var acciones: some View {
        Group {
            tarjeta("Glosario", "text.book.closed") {
                boton("Editar palabras del glosario", "pencil") { EditorWindows.showKeyterms() }
                boton("Editar reemplazos", "arrow.left.arrow.right") { EditorWindows.showRules() }
            }
            tarjeta("Dictados", "doc.text") {
                boton("Copiar último dictado", "doc.on.clipboard") { AppActions.copyLast() }
                boton("Exportar dictados de hoy", "square.and.arrow.up") { AppActions.exportToday() }
                boton("Abrir historial", "folder") { AppActions.openHistory() }
            }
            tarjeta("Diagnóstico", "stethoscope") {
                boton("Ver registro (log)", "doc.plaintext") { AppActions.openLog() }
            }
        }
    }

    // ---- Créditos ----
    private var creditos: some View {
        VStack(alignment: .leading, spacing: 16) {
            tarjeta("BtoDicta", "mic") {
                HStack(spacing: 8) {
                    Text("Versión \(Version.numero)").font(.subheadline).bold()
                    Text(Version.fecha).font(.caption).foregroundStyle(.secondary)
                }
                Text("Dictado por voz para macOS, hecho en Ecuador 🇪🇨 para el español latino.")
                    .font(.subheadline)
                link("Página oficial — btodicta.eztic.ec", "https://btodicta.eztic.ec/")
                link("Repositorio en GitHub", "https://github.com/btoaldas/BtoDicta")
                Text("Licencia GPL-3.0 · libre para siempre").font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Apoya el proyecto ☕", "cup.and.saucer.fill") {
                Text("BtoDicta es gratis y libre. Si te sirve, invítame un cafecito para seguir programando (y pagar la IA que ayuda a construirlo). Cualquier aporte suma.")
                    .font(.subheadline)
                link("☕ Invítame un café (tarjeta · Apple Pay · Google Pay)", "https://btodicta.eztic.ec/apoyar")
                link("💜 GitHub Sponsors", "https://github.com/sponsors/btoaldas")
                link("💳 PayPal", "https://btodicta.eztic.ec/apoyar")
                Text("Más formas (transferencia, cripto, etc.) en la página de apoyo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            tarjeta("Ayuda", "questionmark.circle") {
                link("Manual de usuario completo", "https://github.com/btoaldas/BtoDicta/blob/main/docs/MANUAL.md")
                Text("Instalación, cada pestaña, cada motor, cada ajuste — todo explicado con capturas.")
                    .font(.caption).foregroundStyle(.secondary)
                link("Reportar un problema", "https://github.com/btoaldas/BtoDicta/issues/new")
                Text("Se abre el formulario en GitHub: cuenta qué hiciste, qué esperabas y qué pasó.")
                    .font(.caption).foregroundStyle(.secondary)
                boton("Volver a ver el asistente de configuración", "wand.and.stars") {
                    WizardWindowController.shared.show()
                }
            }
            tarjeta("Créditos", "heart") {
                Text("Creado por Alberto Aldás en compañía de Claude (Anthropic), programado a pura voz. Inspirado en el corazón open source de Handy (@cjpais).")
                    .font(.subheadline)
                link("Handy — inspiración open source", "https://github.com/cjpais/Handy")
            }
            tarjeta("Motores y librerías de código abierto", "shippingbox") {
                ForEach(Self.creditosOpenSource, id: \.0) { link($0.0, $0.1) }
            }
            tarjeta("Voz y clonación (motores locales)", "waveform.badge.mic") {
                Text("El asistente por voz y la clonación local se apoyan en estos proyectos. Se descargan bajo demanda (con tu permiso), no vienen en el instalador. Ver CREDITS.md.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Self.creditosVozClon, id: \.0) { link($0.0, $0.1) }
            }
            tarjeta("Servicios de transcripción (voz)", "waveform") {
                Text("Los motores de nube que puedes conectar para pasar tu voz a texto:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Self.creditosVoz, id: \.0) { link($0.0, $0.1) }
            }
            tarjeta("Servicios de IA para pulir y traducir", "sparkles") {
                Text("Las IAs que puedes conectar para limpiar puntuación, muletillas y traducir:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Self.creditosPulido, id: \.0) { link($0.0, $0.1) }
            }
            tarjeta("Datos y otras fuentes", "tablecells") {
                ForEach(Self.creditosDatos, id: \.0) { link($0.0, $0.1) }
            }
            tarjeta("Historial de versiones", "clock.arrow.circlepath") {
                ForEach(Version.historial, id: \.version) { v in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("v\(v.version)").font(.caption).bold().foregroundStyle(acento)
                            Text(v.fecha).font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(v.cambios, id: \.self) { c in
                            Text("· \(c)").font(.caption).foregroundStyle(.primary.opacity(0.85))
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // Fuentes de terceros que usa BtoDicta (nombre, enlace) — para los Créditos.
    static let creditosOpenSource: [(String, String)] = [
        ("whisper.cpp — Whisper local (ggml-org)", "https://github.com/ggml-org/whisper.cpp"),
        ("llama.cpp — Voxtral local (ggml-org)", "https://github.com/ggml-org/llama.cpp"),
        ("transcribe.cpp — streaming local en vivo", "https://github.com/handy-computer/transcribe.cpp"),
        ("mediaremote-adapter — pausa de multimedia", "https://github.com/ungive/mediaremote-adapter"),
        ("Ollama — IA local (chat, embeddings, whisper)", "https://ollama.com"),
        ("LM Studio — IA local", "https://lmstudio.ai"),
    ]
    // Voz y clonación (motores locales de texto→voz y entrenamiento). Con gratitud.
    static let creditosVozClon: [(String, String)] = [
        ("Coqui XTTS v2 — clonación de voz (código MPL-2.0; modelo CPML no-comercial)", "https://github.com/idiap/coqui-ai-TTS"),
        ("Piper — TTS rápido VITS/ONNX (GPL-3.0, rhasspy/OHF-Voice)", "https://github.com/OHF-Voice/piper1-gpl"),
        ("Piper voices — voces donadas (rhasspy/piper-voices)", "https://huggingface.co/rhasspy/piper-voices"),
        ("PyTorch (BSD-3) · Lightning (Apache-2.0)", "https://pytorch.org"),
        ("Resemblyzer — elegir el mejor clon (Apache-2.0)", "https://github.com/resemble-ai/Resemblyzer"),
        ("uv + python-build-standalone — motor aislado (Astral)", "https://github.com/astral-sh/uv"),
    ]
    static let creditosVoz: [(String, String)] = [
        ("ElevenLabs Scribe", "https://elevenlabs.io"),
        ("Groq Whisper (gratis)", "https://groq.com"),
        ("OpenAI (Whisper / gpt-4o-transcribe)", "https://openai.com"),
        ("Mistral (Voxtral)", "https://mistral.ai"),
        ("Fireworks AI (Whisper)", "https://fireworks.ai"),
        ("Hugging Face (Whisper, gratis)", "https://huggingface.co"),
        ("Deepgram (Nova)", "https://deepgram.com"),
        ("AssemblyAI (Universal)", "https://www.assemblyai.com"),
        ("Gladia", "https://www.gladia.io"),
        ("Speechmatics", "https://www.speechmatics.com"),
        ("Cloudflare Workers AI", "https://developers.cloudflare.com/workers-ai/"),
        ("Soniox", "https://soniox.com"),
        ("Azure AI Speech", "https://azure.microsoft.com/products/ai-services/ai-speech"),
    ]
    static let creditosPulido: [(String, String)] = [
        ("OpenRouter (cientos de modelos, muchos gratis)", "https://openrouter.ai"),
        ("Anthropic (Claude)", "https://www.anthropic.com"),
        ("Google Gemini", "https://ai.google.dev"),
        ("DeepSeek", "https://www.deepseek.com"),
        ("xAI (Grok)", "https://x.ai"),
        ("Moonshot AI / Kimi", "https://platform.kimi.ai"),
        ("Kimi Code (cuenta)", "https://www.kimi.com/code"),
        ("Cerebras (gratis)", "https://www.cerebras.ai"),
        ("GitHub Models (gratis)", "https://github.com/marketplace/models"),
        ("NVIDIA NIM (gratis)", "https://build.nvidia.com"),
        ("Together AI", "https://www.together.ai"),
        ("Novita AI", "https://novita.ai"),
        ("Z.ai (GLM, gratis)", "https://z.ai"),
        ("SiliconFlow", "https://www.siliconflow.com"),
    ]
    static let creditosDatos: [(String, String)] = [
        ("LiteLLM — precios de modelos que se actualizan solos", "https://github.com/BerriAI/litellm"),
        ("Open-Meteo + GeoNames — clima y geocodificación", "https://open-meteo.com/"),
        ("Whisper (OpenAI) — modelos ggml de ggerganov/whisper.cpp", "https://huggingface.co/ggerganov/whisper.cpp"),
        ("Voxtral (Mistral) — GGUF de ggml-org / handy-computer", "https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF"),
        ("Nemotron y Canary (NVIDIA) — GGUF de handy-computer", "https://huggingface.co/handy-computer"),
        ("bge-m3 (BAAI) — embeddings de la búsqueda semántica", "https://huggingface.co/BAAI/bge-m3"),
    ]

    // ---- helpers de UI ----
    @ViewBuilder
    private func tarjeta<Content: View>(_ titulo: String, _ icono: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(acento)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    private func fila<T: View>(_ label: String, @ViewBuilder _ trailing: () -> T) -> some View {
        HStack { Text(label); Spacer(); trailing() }
    }

    // MARK: - Selector de modelo (para CUALQUIER proveedor de pulido)

    /// Lista de modelos elegibles del proveedor: gateway → los guardados en su
    /// JSON; fijo/local → los descubiertos en caché (modelosPorProveedor).
    private func modelosDe(_ sel: ChatIA) -> [String] {
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            let ids = PersonalizadaStore.cargar().first(where: { $0.id == gid })?.modelos ?? []
            return ChatIA.modelosAptosParaPulido(ids)
        }
        return ChatIA.modelosAptosParaPulido(ChatIA.modelosPorProveedor[sel.id] ?? [])
    }
    /// "modelo · precio" — precio manual del usuario, o el publicado por el
    /// proveedor, o el curado (aprox.).
    private func conPrecio(_ sel: ChatIA, _ modelo: String) -> String {
        if let p = ChatIA.precioDe(sel.id, modelo) { return "\(modelo) · \(p)" }
        return modelo
    }
    /// Reordena la cascada de failover de pulido (persiste el orden completo).
    private func moverCascada(_ ids: [String], _ i: Int, _ d: Int) {
        var a = ids; let j = i + d
        // La posición 1 pertenece al selector de IA principal. Aquí solo se
        // reordenan sus respaldos, para que ambas configuraciones no se contradigan.
        guard i > 0, j > 0, j < a.count else { return }
        a.swapAt(i, j)
        Config.set("pulido_cascada", to: a)
        detectTrigger += 1
    }

    @ViewBuilder private func selectorModelo(_ sel: ChatIA) -> some View {
        if sel.esCuentaCodex {
            VStack(alignment: .leading, spacing: 4) {
                fila("Modelo") {
                    Picker("", selection: Binding(
                        get: { Config.codexCuentaModelo() },
                        set: {
                            Config.set("codex_cuenta_modelo", to: $0)
                            detectTrigger += 1
                        })) {
                        ForEach(AgenteCodex.modelosDisponibles()) { modelo in
                            Text(modelo.nombre + (modelo.oculto ? " · compatibilidad" : ""))
                                .tag(modelo.id)
                        }
                    }.labelsHidden().frame(width: 300)
                }
                fila("Razonamiento") {
                    Picker("", selection: Binding(
                        get: { Config.codexCuentaEsfuerzo() },
                        set: {
                            Config.set("codex_cuenta_esfuerzo", to: $0)
                            detectTrigger += 1
                        })) {
                        ForEach(AgenteCodex.esfuerzosDisponibles) { esfuerzo in
                            Text(esfuerzo.nombre).tag(esfuerzo.id)
                        }
                    }.labelsHidden().frame(width: 300)
                }
                Text(AgenteCodex.descripcionModelo(Config.codexCuentaModelo()))
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Modelo global de la cuenta para pulido, traducción, Modos y Asistente. En Automático, Codex puede elegir uno distinto según la solicitud; con un modelo explícito siempre se pide ese modelo.")
                    .font(.caption2).foregroundStyle(.secondary)
                avisoPrivacidad(sel)
            }
        } else {
            let _ = detectTrigger
            let lista = modelosDe(sel)
            let activo = sel.modeloEfectivo
            // Incluye el activo aunque no esté en la lista (evita Picker sin tag).
            let opciones = (lista.contains(activo) || activo.isEmpty) ? lista : [activo] + lista
            VStack(alignment: .leading, spacing: 4) {
                fila("Modelo") {
                    HStack(spacing: 8) {
                        if opciones.count > 1 {
                            Picker("", selection: Binding(
                                get: { activo },
                                set: { elegirModelo(sel, $0); detectTrigger += 1 })) {
                                ForEach(opciones, id: \.self) { m in
                                    Text(conPrecio(sel, m)).tag(m)
                                }
                            }.labelsHidden().frame(width: 300)
                        } else {
                            Text(activo.isEmpty ? "—" : conPrecio(sel, activo)).font(.caption).foregroundStyle(.secondary)
                        }
                        Button(descubriendoMod && msgModId == sel.id ? "Buscando…" : "Descubrir") {
                            descubriendoMod = true; msgMod = nil; msgModId = sel.id
                            descubrirModelosDe(sel)
                        }.controlSize(.small).disabled(descubriendoMod)
                    }
                }
                if msgModId == sel.id, let mm = msgMod {
                    Text(mm).font(.caption2).foregroundStyle(msgModOK ? .green : .orange)
                }
                Text(sel.id.hasPrefix("custom:")
                     ? "Modelos del gateway. Cambia el activo cuando quieras, aquí mismo."
                     : "Elige el modelo de este proveedor. 'Descubrir' trae la lista completa (con precio si el proveedor lo publica).")
                    .font(.caption).foregroundStyle(.secondary)
                // Precio del modelo activo + editor manual (por si el proveedor no lo
                // publica, o para poner el tuyo). Prioridad: manual > publicado > curado.
                if !activo.isEmpty { precioManual(sel, activo) }
                // Aviso de privacidad: al usar nube/gateway, el texto SALE de tu Mac.
                avisoPrivacidad(sel)
            }
        }
    }
    @ViewBuilder private func precioManual(_ sel: ChatIA, _ modelo: String) -> some View {
        let _ = detectTrigger
        let key = "\(sel.id)::\(modelo)"
        let actual = ChatIA.precioDe(sel.id, modelo)
        let esManual = Config.precioManual(key) != nil
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Precio \(esManual ? "(tuyo)" : "($/1M):")").font(.caption2).foregroundStyle(.secondary)
                Text(actual ?? "sin dato").font(.caption2)
                    .foregroundStyle(actual == nil ? .orange : .secondary)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("Poner a mano:").font(.caption2).foregroundStyle(.secondary)
                TextField("entrada", text: $precioIn).frame(width: 60).textFieldStyle(.roundedBorder)
                Text("/").font(.caption2)
                TextField("salida", text: $precioOut).frame(width: 60).textFieldStyle(.roundedBorder)
                Button("Guardar") {
                    if let i = Double(precioIn.replacingOccurrences(of: ",", with: ".")),
                       let o = Double(precioOut.replacingOccurrences(of: ",", with: ".")) {
                        Config.setPrecioManual(key, (i, o)); precioIn = ""; precioOut = ""; detectTrigger += 1
                    }
                }.controlSize(.small)
                if esManual {
                    Button("Quitar") { Config.setPrecioManual(key, nil); detectTrigger += 1 }.controlSize(.small)
                }
            }
        }
    }
    /// Aviso de privacidad/seguridad al pulir con una IA que NO es local.
    @ViewBuilder private func avisoPrivacidad(_ sel: ChatIA) -> some View {
        if !sel.local && Config.avisoNube() {
            let esGateway = sel.id.hasPrefix("custom:")
            let inseguro = esGateway && !sel.baseSegura   // gateway por http://
            VStack(alignment: .leading, spacing: 2) {
                if inseguro {
                    Label("Este gateway usa http SIN cifrar: por seguridad NO se envían tus credenciales (ni la API key ni los encabezados). El pulido no funcionará hasta que uses https.",
                          systemImage: "lock.open.trianglebadge.exclamationmark")
                        .font(.caption2).foregroundStyle(.red)
                } else {
                    Label("Tu texto dictado se ENVÍA a \(sel.proveedorCorto)\(esGateway ? " (gateway de terceros)" : " (nube)") para pulir/traducir. No dictes datos sensibles (claves, tarjetas) con un proveedor de terceros.",
                          systemImage: "exclamationmark.shield")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text("Para que NADA salga de tu Mac, usa una IA local (LM Studio / Ollama). Puedes ocultar este aviso en Avanzado.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }
    private func elegirModelo(_ sel: ChatIA, _ nuevo: String) {
        guard ChatIA.modeloAptoParaPulido(nuevo) else {
            msgModId = sel.id
            msgMod = "Ese modelo no genera texto y no puede pulir dictados."
            msgModOK = false
            return
        }
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            var a = PersonalizadaStore.cargar()
            if let k = a.firstIndex(where: { $0.id == gid }) { a[k].modelo = nuevo; PersonalizadaStore.guardar(a) }
        } else {
            Config.setPulidoModelo(sel.id, nuevo)
        }
    }
    private func descubrirModelosDe(_ sel: ChatIA) {
        if sel.id.hasPrefix("custom:") {
            let gid = String(sel.id.dropFirst(7))
            guard let snap = PersonalizadaStore.cargar().first(where: { $0.id == gid }) else { descubriendoMod = false; return }
            PersonalizadaStore.descubrirModelos(snap) { ids, msg in
                let aptos = ChatIA.modelosAptosParaPulido(ids)
                let omitidos = ids.count - aptos.count
                // Recarga FRESCO dentro del callback y aplica solo la mutación
                // puntual: no pisa ediciones a otros gateways hechas mientras se
                // descubría (el editor es otra ventana no modal).
                if !aptos.isEmpty {
                    var fresh = PersonalizadaStore.cargar()
                    if let k = fresh.firstIndex(where: { $0.id == gid }) {
                        fresh[k].modelos = aptos
                        if !ChatIA.modeloAptoParaPulido(fresh[k].modelo) { fresh[k].modelo = aptos[0] }
                        PersonalizadaStore.guardar(fresh)
                    }
                }
                let detalle = omitidos > 0
                    ? "\(aptos.count) aptos para pulido · \(omitidos) omitidos (audio, embeddings o clasificación)"
                    : msg
                descubriendoMod = false; msgMod = detalle; msgModOK = !aptos.isEmpty; detectTrigger += 1
            }
        } else {
            ChatIA.descubrirProveedor(sel) { ids, msg in
                descubriendoMod = false; msgMod = msg; msgModOK = !ids.isEmpty; detectTrigger += 1
            }
        }
    }
    private func boton(_ titulo: String, _ icono: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icono).frame(width: 20); Text(titulo); Spacer() }
        }.buttonStyle(.plain)
    }
    private func link(_ titulo: String, _ url: String) -> some View {
        Button(action: { NSWorkspace.shared.open(URL(string: url)!) }) {
            HStack(spacing: 6) { Image(systemName: "arrow.up.right.square"); Text(titulo) }
                .foregroundStyle(acento)
        }.buttonStyle(.plain)
    }
    private func open(_ file: String) {
        NSWorkspace.shared.open(Config.dir.appendingPathComponent(file))
    }
}

// MARK: - Estadísticas (odómetro con barras)

struct StatsView: View {
    private let t = UsageLog.totales()
    private let tp = PulidoLog.totales()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Uso de dictado", systemImage: "chart.bar.xaxis").font(.headline).foregroundStyle(acento)

            // KPIs
            HStack(spacing: 10) {
                kpi("Hoy", fmt(t.hoyMin), "mic.fill")
                kpi("Semana", fmt(t.semanaMin), "calendar")
                kpi("Mes", fmt(t.mesMin), "calendar.badge.clock")
            }
            HStack(spacing: 10) {
                kpi("Dictados hoy", "\(t.dictadosHoy)", "waveform")
                kpi("Costo del mes", String(format: "$%.2f", t.mesCosto), "dollarsign.circle")
                kpi("Total año", fmt(t.añoMin), "star.fill")
            }

            // Gráfica de barras: últimos 7 días
            VStack(alignment: .leading, spacing: 8) {
                Text("Últimos 7 días").font(.subheadline).bold()
                barras
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(UsageLog.referenciaPrecios)
                .font(.caption).foregroundStyle(.secondary)

            // Gasto de PULIDO/traducción con IA (tokens → costo estimado).
            if tp.mesCosto > 0 || tp.pulidosMes > 0 {
                Label("Gasto de pulido con IA", systemImage: "sparkles").font(.headline).foregroundStyle(acento)
                HStack(spacing: 10) {
                    kpi("Hoy", String(format: "$%.3f", tp.hoyCosto), "dollarsign.circle")
                    kpi("Semana", String(format: "$%.3f", tp.semanaCosto), "calendar")
                    kpi("Mes", String(format: "$%.3f", tp.mesCosto), "calendar.badge.clock")
                }
                HStack(spacing: 10) {
                    kpi("Pulidos hoy", "\(tp.pulidosHoy)", "sparkles")
                    kpi("Tokens hoy", "\(tp.tokensHoy)", "number")
                    kpi("Pulidos mes", "\(tp.pulidosMes)", "sum")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gasto de pulido — últimos 7 días").font(.subheadline).bold()
                    barrasCosto
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Estimado con el precio (manual/publicado/curado ~) del modelo que se usó. Con IA LOCAL el costo es $0.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Bitácora de aprendizajes — solo con Modo desarrollo activo.
            if Config.devMode() {
                AprendizajesDebugView()
            }
        }
    }

    private var barrasCosto: some View {
        let maxV = max(tp.costoPorDia.max() ?? 0.001, 0.0001)
        let dias = diasEtiquetas()
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(tp.costoPorDia[i] >= 0.0005 ? String(format: "$%.3f", tp.costoPorDia[i]) : "")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(i == 6 ? 1 : 0.55))
                        .frame(height: max(4, CGFloat(tp.costoPorDia[i] / maxV) * 90))
                    Text(dias[i]).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130)
    }

    private var barras: some View {
        let maxV = max(t.porDiaSemana.max() ?? 1, 0.1)
        let dias = diasEtiquetas()
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(t.porDiaSemana[i] >= 0.05 ? String(format: "%.0f", t.porDiaSemana[i]) : "")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(acento.opacity(i == 6 ? 1 : 0.55))
                        .frame(height: max(4, CGFloat(t.porDiaSemana[i] / maxV) * 90))
                    Text(dias[i]).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 130)
    }

    private func kpi(_ titulo: String, _ valor: String, _ icono: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icono).foregroundStyle(acento)
            Text(valor).font(.system(.title3, design: .rounded)).bold()
            Text(titulo).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fmt(_ min: Double) -> String {
        if min >= 60 { return String(format: "%.1f h", min / 60) }
        return String(format: "%.0f min", min)
    }
    private func diasEtiquetas() -> [String] {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "EEEEE"
        let cal = Calendar.current
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: -(6 - i), to: Date())!
            return f.string(from: d).uppercased()
        }
    }
}

// MARK: - Bitácora de aprendizajes con reversión (debug)

private let acentoStats = Color(red: 0.36, green: 0.28, blue: 0.62)

struct AprendizajesDebugView: View {
    @State private var entradas: [(fecha: Date, de: String, a: String, sonido: Bool)] = []
    private let f: DateFormatter = { let d = DateFormatter(); d.locale = Locale(identifier: "es"); d.dateFormat = "HH:mm:ss"; return d }()

    var body: some View {
        let unDia = Date().addingTimeInterval(-86400)
        let recientes = entradas.filter { $0.fecha >= unDia }
        VStack(alignment: .leading, spacing: 8) {
            Label("Aprendizaje (debug)", systemImage: "brain.head.profile")
                .font(.subheadline).bold().foregroundStyle(acentoStats)
            if !Config.aprender() {
                Text("El aprendizaje está APAGADO (Ajustes → Aprendizaje). No aprenderá nada hasta activarlo.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if recientes.isEmpty {
                Text("Nada aprendido en las últimas 24 h. Corrige una palabra rara donde la pegaste (antes de enviar) y vuelve a dictar.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(recientes.count) corrección(es) hoy (🔊 = por sonido). Quita la que no quieras:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(recientes.enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Text(f.string(from: e.fecha)).font(.caption2).foregroundStyle(.tertiary)
                        Text("\(e.sonido ? "🔊 " : "")\(e.de) → \(e.a)").font(.caption).bold()
                        Spacer()
                        Button {
                            Aprendizaje.revertir(de: e.de, a: e.a)
                            entradas = Aprendizaje.historial()
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.red)
                        }.buttonStyle(.plain).help("Deshacer este aprendizaje")
                    }
                }
            }
            Text("Total histórico: \(entradas.count) reglas aprendidas.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { entradas = Aprendizaje.historial() }
    }
}

// MARK: - Puente a las acciones del AppDelegate

enum AppActions {
    static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    static func copyLast() { delegate?.copyLastDictationPublic() }
    static func exportToday() { delegate?.exportTodayPublic() }
    static func openHistory() { delegate?.openHistoryPublic() }
    static func openLog() { delegate?.openLogPublic() }
}

// MARK: - Ventana

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "BtoDicta"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 640))
            w.minSize = NSSize(width: 720, height: 560)
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
    /// Abre la Configuración en una sección concreta (ej. "Créditos").
    func show(irA seccion: String) {
        show()
        NavAjustes.shared.ir = seccion
    }

    /// Captura únicamente el contenido de ESTA ventana para QA visual; no exige
    /// permiso de grabación de pantalla ni puede ver otras aplicaciones.
    @discardableResult
    func guardarSnapshotQA(_ url: URL) -> Bool {
        guard Thread.isMainThread, let view = window?.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url, options: .atomic); return true }
        catch { return false }
    }
}

// MARK: - Selector del motor de embeddings (con cuál IA se calculan)
//
// NO se hardcodea Ollama: se detecta qué motores están listos (Ollama corriendo
// con un modelo de embeddings, o una key de nube puesta) y se ofrecen. El
// usuario elige; los inactivos se muestran con la pista de cómo activarlos.
struct EmbeddingMotorPicker: View {
    @State private var estado: [String: Bool] = [:]   // id → disponible
    @State private var sel = Config.embeddingProveedor()
    private let acento = Color(red: 0.36, green: 0.28, blue: 0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Motor de embeddings:").font(.caption)
                Picker("", selection: $sel) {
                    ForEach(EmbeddingSearch.motores) { m in
                        Text(etiqueta(m)).tag(m.id)
                    }
                    Text("Personalizado (avanzado)").tag("custom")
                }
                .labelsHidden().frame(width: 280)
                .onChange(of: sel) { _, nuevo in Config.set("embedding_proveedor", to: nuevo) }
            }
            pista
            Text("ChatGPT por cuenta (Codex) no aparece como motor aquí porque no entrega vectores de embeddings. Para reconocimiento semántico usa Interno de BtoDicta/Ollama; OpenAI text-embedding-3-small requiere API y facturación separadas.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear {
            EmbeddingSearch.detectar { res in
                estado = Dictionary(uniqueKeysWithValues: res.map { ($0.0.id, $0.1) })
            }
        }
    }

    private func etiqueta(_ m: EmbeddingSearch.Motor) -> String {
        guard let ok = estado[m.id] else { return m.nombre }
        return "\(ok ? "✓" : "○") \(m.nombre)\(ok ? "" : (m.local ? " — sin modelo" : " — sin key"))"
    }

    @State private var bajandoInterno = false
    @State private var msgInterno = ""

    @ViewBuilder private var pista: some View {
        if sel == "custom" {
            Text("Personalizado: se usa la base/modelo/key de embeddings que configures (avanzado).")
                .font(.caption2).foregroundStyle(.secondary)
        } else if sel == "interno", estado["interno"] == false {
            VStack(alignment: .leading, spacing: 3) {
                Text("El motor interno usa el llama-server que ya trae BtoDicta + el modelo bge-m3 (mismo modelo y calidad que Ollama). Solo falta descargar el modelo, una vez.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button(bajandoInterno ? "Descargando…" : "⬇︎ Descargar modelo (~417 MB)") {
                        bajandoInterno = true; msgInterno = "Descargando…"
                        EmbeddingServer.descargar(onProgreso: { msgInterno = $0 },
                            completion: { ok, msg in
                                bajandoInterno = false; msgInterno = msg
                                estado["interno"] = ok
                            })
                    }.controlSize(.small).disabled(bajandoInterno)
                    if bajandoInterno { ProgressView().controlSize(.mini) }
                }
                if !msgInterno.isEmpty { Text(msgInterno).font(.caption2).foregroundStyle(.secondary) }
            }
        } else if let m = EmbeddingSearch.motores.first(where: { $0.id == sel }), estado[m.id] == false {
            Text(m.local
                 ? "Ollama no tiene un modelo de embeddings. Corre Ollama y haz: ollama pull \(m.modelo)"
                 : "Falta la key de \(m.nombre). Ponla en Modelos → Proveedores en la nube (\(m.keyEnv)).")
                .font(.caption2).foregroundStyle(.orange)
        } else {
            Text("El elegido usa \(EmbeddingSearch.motorActual.modelo). Cambiar de motor re-indexa (los vectores no son compatibles entre motores).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
