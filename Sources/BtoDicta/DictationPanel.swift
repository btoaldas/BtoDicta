import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Panel flotante en el notch (no roba el foco)

/// Label que acepta clic (izquierdo o derecho) para abrir el selector de motor.
final class MotorLabel: NSTextField {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}

/// Fondo del notch que acepta clic → cancelar lo que esté en curso (grabación/agente/voz).
final class ClickableBackground: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Botón AppKit con cierre, útil dentro del NSPanel no activante sin añadir un
/// controlador de ventana solo para una acción breve.
final class PanelActionButton: NSButton {
    var onPress: (() -> Void)?

    init(_ title: String) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        target = self
        action = #selector(pulsar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pulsar() { onPress?() }
}

/// Geometría pura y testeable del modal del notch. Todos los bloques se apilan desde
/// abajo con separación explícita; así un texto corto nunca recibe un alto mínimo que
/// invada el título (el bug visible de las letras montadas).
struct ConfirmationLayout {
    let strip: CGFloat
    let title: NSRect
    let body: NSRect
    let context: NSRect
    let footer: NSRect

    var sinSolapes: Bool {
        let margen: CGFloat = 5
        let contextoOK = context.height == 0 || footer.maxY + margen <= context.minY
        let cuerpoOK = context.height == 0
            ? footer.maxY + margen <= body.minY
            : context.maxY + margen <= body.minY
        return contextoOK && cuerpoOK && body.maxY + margen <= title.minY
            && title.maxY < strip
    }
}

final class DictationPanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    let meter: LevelMeterView
    private let keycap = NSTextField(labelWithString: "fn")
    private let motorLabel = MotorLabel(labelWithString: "")
    private let modoLabel = MotorLabel(labelWithString: "")   // arriba-izq: modo activo
    /// Cuánto llevas grabando, bajo las barras de voz. Mientras hablas no hay
    /// otra forma de saberlo, y en un dictado largo es justo el dato que hace
    /// falta para decidir si cortar ya o seguir.
    private let cronoLabel = NSTextField(labelWithString: "")
    private var cronoInicio: Date?
    private var cronoTimer: Timer?
    private(set) var modoMostradoID = "dictado"                // observable por QA
    private let confirmTitle = NSTextField(labelWithString: "")
    private let confirmBody = NSTextField(wrappingLabelWithString: "")
    // Detalles LARGOS (propuestas de conexiones API): mismo rect que el body,
    // pero con scroll — el visto bueno puede leerlo TODO, nada se trunca.
    private let confirmScroll = NSScrollView()
    private let confirmTexto = NSTextView()
    private var confirmTextoCompleto = ""   // lo que mide la geometría (cap 10 líneas)
    private let confirmAlternatives = NSTextField(wrappingLabelWithString: "")
    private let confirmFooter = NSTextField(labelWithString: "")
    private let resultadoFinder = PanelActionButton("Ver en Finder")
    private let resultadoCerrar = PanelActionButton("Cerrar")
    private var fondo: NSView?                                 // forma negra (para el latido "pensando")

    /// Clic sobre el letrero del motor (o el fn): abrir el selector rápido.
    var onMotorClick: (() -> Void)? {
        didSet { motorLabel.onClick = onMotorClick }
    }
    /// Clic sobre el letrero del MODO (arriba-izq): abrir el selector de modo.
    var onModoClick: (() -> Void)? {
        didSet { modoLabel.onClick = onModoClick }
    }
    /// Clic sobre el cuerpo del notch (fuera de las etiquetas): CANCELAR lo que esté en curso.
    var onCancelar: (() -> Void)?

    private let wing: CGFloat = 48      // alas a los lados del notch
    private let strip: CGFloat = 24     // línea de texto bajo el notch
    private var confirmStrip: CGFloat = 126 // pregunta expandida HACIA ABAJO
    private var confirmLayout: ConfirmationLayout?
    private var confirmando = false
    private(set) var resultadoCapturaPersistenteActivo = false
    private(set) var resultadoCapturaRuta = ""
    private var resultadoFinderAccion: (() -> Void)?
    private var stripActual: CGFloat { confirmando ? confirmStrip : strip }
    private var width: CGFloat = 400
    private var height: CGFloat = 60
    private var notchHeight: CGFloat = 36
    /// Invalida cierres diferidos de una presentación anterior. Sin esta
    /// generación, un `hide(after:)` viejo podía ocultar el dictado nuevo.
    private var presentacionID: UInt64 = 0
    /// Mientras macOS captura o graba la pantalla, el notch queda fuera del
    /// Window Server visible. No basta con `orderOut` una vez: un flash o una
    /// respuesta tardía también deben tener prohibido volver a mostrarlo.
    private(set) var capturaPrivadaActiva = false

    init() {
        // Geometría real del notch (áreas útiles a sus lados)
        var notchRect = NSRect(x: 0, y: 0, width: 210, height: 36)
        if let screen = NSScreen.main {
            notchHeight = max(screen.safeAreaInsets.top, 28)
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            if let left, let right {
                notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - notchHeight,
                                   width: right.minX - left.maxX, height: notchHeight)
            } else {
                notchRect = NSRect(x: screen.frame.midX - 105, y: screen.frame.maxY - notchHeight,
                                   width: 210, height: notchHeight)
            }
        }
        width = notchRect.width + wing * 2
        height = notchHeight + strip
        meter = LevelMeterView(frame: NSRect(x: 8, y: strip + 7, width: wing - 16, height: notchHeight - 14))

        panel = NSPanel(contentRect: NSRect(x: notchRect.minX - wing,
                                            y: notchRect.maxY - height,
                                            width: width, height: height),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true

        // Forma negra que abraza el notch: alas arriba + tira de texto abajo.
        // Clickeable: tocar el notch (fuera de las etiquetas) CANCELA lo que esté en curso.
        let background = ClickableBackground(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.onClick = { [weak self] in self?.onCancelar?() }
        background.setAccessibilityRole(.button)
        background.setAccessibilityLabel("Cancelar la acción actual")
        background.setAccessibilityHelp("Cancela la grabación, el procesamiento o la respuesta que esté en curso.")
        background.toolTip = "Cancelar la grabación o acción actual"
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.cgColor
        background.layer?.cornerRadius = 12
        background.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.contentView = background
        fondo = background

        // Ala izquierda: el latido (a la altura del notch)
        background.addSubview(meter)

        // Ala derecha: tecla fn estilo keycap
        keycap.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        keycap.textColor = .white
        keycap.alignment = .center
        keycap.wantsLayer = true
        keycap.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1).cgColor
        keycap.layer?.cornerRadius = 5
        keycap.layer?.borderWidth = 1
        keycap.layer?.borderColor = NSColor(calibratedWhite: 0.4, alpha: 1).cgColor
        // Keycap abajo + letrero del motor arriba, adaptado al alto del ala
        // (36 pt con notch real, ~28 pt en pantallas externas).
        let capW: CGFloat = 30
        let capH: CGFloat = notchHeight >= 34 ? 18 : 14
        keycap.font = NSFont.systemFont(ofSize: capH >= 18 ? 12 : 10, weight: .semibold)
        keycap.frame = NSRect(x: width - wing + (wing - capW) / 2,
                              y: strip + 2,
                              width: capW, height: capH)
        background.addSubview(keycap)

        // Encima del fn: con qué MOTOR se está dictando ahora mismo
        // (rota en vivo cuando el failover conmuta de proveedor).
        motorLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        motorLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        motorLabel.alignment = .center
        motorLabel.maximumNumberOfLines = 1
        motorLabel.setAccessibilityRole(.button)
        motorLabel.setAccessibilityLabel("Cambiar motor de transcripción")
        motorLabel.setAccessibilityHelp("Abre la cascada de motores para cambiar el transcriptor, incluso durante un dictado.")
        motorLabel.toolTip = "Cambiar el motor de transcripción"
        let motorH = max(8, notchHeight - capH - 7)
        motorLabel.frame = NSRect(x: width - wing + 1,
                                  y: strip + capH + 4,
                                  width: wing - 2, height: min(motorH, 10))
        background.addSubview(motorLabel)

        // Tira inferior: UNA línea de texto delgadita, alineada a la DERECHA
        // (lo último dicho queda pegado al borde, a la altura del fn) y el
        // texto viejo se recorta por la IZQUIERDA con "…". Así nunca se oculta
        // lo último que se habla.
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .right
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingHead
        label.frame = NSRect(x: 8, y: 4, width: width - 16, height: 15)
        background.addSubview(label)

        // Confirmación de intención: no compite con el karaoke. Cuando aparece,
        // el panel crece hacia abajo y usa varias líneas con una jerarquía clara.
        confirmTitle.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        confirmTitle.textColor = .white
        confirmTitle.alignment = .left
        confirmTitle.isHidden = true
        background.addSubview(confirmTitle)
        confirmBody.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        confirmBody.textColor = .white
        confirmBody.maximumNumberOfLines = 0
        confirmBody.lineBreakMode = .byWordWrapping
        confirmBody.isHidden = true
        background.addSubview(confirmBody)
        confirmTexto.isEditable = false
        confirmTexto.isSelectable = true
        confirmTexto.drawsBackground = false
        confirmTexto.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        confirmTexto.textColor = .white
        confirmTexto.textContainerInset = NSSize(width: 0, height: 2)
        confirmScroll.documentView = confirmTexto
        confirmScroll.hasVerticalScroller = true
        confirmScroll.autohidesScrollers = true
        confirmScroll.drawsBackground = false
        confirmScroll.isHidden = true
        background.addSubview(confirmScroll)
        confirmAlternatives.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        confirmAlternatives.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        confirmAlternatives.maximumNumberOfLines = 4
        confirmAlternatives.lineBreakMode = .byWordWrapping
        confirmAlternatives.isHidden = true
        background.addSubview(confirmAlternatives)
        confirmFooter.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        confirmFooter.textColor = NSColor(calibratedRed: 0.55, green: 0.88, blue: 1, alpha: 1)
        confirmFooter.alignment = .center
        confirmFooter.isHidden = true
        background.addSubview(confirmFooter)
        resultadoFinder.isHidden = true
        resultadoFinder.onPress = { [weak self] in self?.resultadoFinderAccion?() }
        background.addSubview(resultadoFinder)
        resultadoCerrar.isHidden = true
        resultadoCerrar.onPress = { [weak self] in self?.closeCaptureResult() }
        background.addSubview(resultadoCerrar)

        // Ala IZQUIERDA, arriba (sobre el audio): el MODO activo. Clic para
        // cambiarlo — igual que el letrero del motor a la derecha.
        modoLabel.font = NSFont.systemFont(ofSize: 7, weight: .bold)
        modoLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        modoLabel.alignment = .center
        modoLabel.maximumNumberOfLines = 1
        modoLabel.setAccessibilityRole(.button)
        modoLabel.setAccessibilityLabel("Cambiar modo")
        modoLabel.setAccessibilityHelp("Abre la lista de modos para elegir qué hacer con el dictado.")
        modoLabel.toolTip = "Cambiar qué hará BtoDicta con este dictado"
        modoLabel.frame = NSRect(x: 1, y: strip + notchHeight - 11, width: wing - 2, height: 10)
        modoLabel.onClick = onModoClick
        background.addSubview(modoLabel)   // encima del meter (z-order)

        // Ala IZQUIERDA, abajo (bajo las barras de voz): cuánto llevas grabando.
        // Cifras de ancho fijo para que el rótulo no baile al pasar de 9 a 10.
        cronoLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        cronoLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        cronoLabel.alignment = .center
        cronoLabel.maximumNumberOfLines = 1
        cronoLabel.setAccessibilityLabel("Tiempo grabado")
        cronoLabel.toolTip = "Cuánto llevas grabando"
        cronoLabel.frame = .zero
        background.addSubview(cronoLabel)
        setModo(ModosStore.activo())
    }

    // MARK: Cronómetro de grabación

    /// Empieza a contar. Se llama al abrir el micrófono, no al mostrar el panel:
    /// lo que interesa es el audio grabado, no el tiempo en pantalla.
    func iniciarCronometro() {
        cronoInicio = Date()
        cronoLabel.stringValue = "0:00"
        relayout()
        cronoTimer?.invalidate()
        // Cada medio segundo: el rótulo cambia una vez por segundo, pero así no
        // se ve saltar dos unidades cuando el reloj y el temporizador se
        // desfasan.
        cronoTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let inicio = self.cronoInicio else { return }
            self.cronoLabel.stringValue = Self.reloj(Date().timeIntervalSince(inicio))
        }
        if let t = cronoTimer { RunLoop.main.add(t, forMode: .common) }
    }

    /// ¿El notch está a la vista? Lo usa la prueba propia.
    var visibleQA: Bool { panel.isVisible }
    /// Lo que dice ahora mismo la línea de texto. Lo usa la prueba propia.
    var textoQA: String { label.stringValue }

    /// Lo que se lee ahora mismo en el cronómetro. Lo usa la prueba propia.
    var cronoTextoQA: String { cronoLabel.stringValue }

    /// Para el contador y devuelve lo que duró, para poder decirlo al entregar.
    @discardableResult
    func detenerCronometro() -> TimeInterval {
        cronoTimer?.invalidate(); cronoTimer = nil
        let duracion = cronoInicio.map { Date().timeIntervalSince($0) } ?? 0
        cronoInicio = nil
        cronoLabel.stringValue = ""
        relayout()
        return duracion
    }

    /// `m:ss` hasta la hora, `h:mm:ss` a partir de ahí. Un dictado de dos horas
    /// existe —la bitácora graba de continuo— y «120:00» no se lee.
    static func reloj(_ segundos: TimeInterval) -> String {
        let t = max(0, Int(segundos.rounded(.down)))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// Fija el letrero del modo activo (arriba-izq del notch).
    func setModo(_ modo: Modo) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setModo(modo) }
            return
        }
        modoMostradoID = modo.id
        let txt = modo.id == "dictado" ? "dictado" : modo.nombre.lowercased()
        modoLabel.stringValue = txt
        // Cada modo tiene SU color (el usuario puede fijarlo; si no, paleta estable) y
        // el fondo del notch se TIÑE suave con él → sabes en qué modo estás de un vistazo.
        modoLabel.textColor = ColorModo.de(modo)
        if let capa = fondo?.layer {
            capa.removeAnimation(forKey: "modoVivoPulso")
            capa.backgroundColor = ColorModo.fondo(modo).cgColor
            if !enRespuestaIA { capa.opacity = 1 }
        }
    }

    /// Cambio de modo EN VIVO (dijiste "modo X" mientras hablabas): aplica el color y da
    /// un doble parpadeo corto — el "sí te caché" — sin interrumpir la grabación.
    func setModoVivo(_ modo: Modo) {
        guard !enRespuestaIA else { return }
        setModo(modo)
        guard let capa = fondo?.layer else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0; a.toValue = 0.45
        a.duration = 0.18; a.autoreverses = true; a.repeatCount = 2
        capa.add(a, forKey: "modoVivoPulso")
    }

    // Un "flash" (aviso breve, ej. "📚 Aprendí…") tiene prioridad sobre el
    // texto del dictado hasta que caduca — así se alcanza a ver sin tapar.
    private var flashHasta = Date.distantPast

    func show(_ text: String) {
        guard Config.panelVisible(), !capturaPrivadaActiva,
              !resultadoCapturaPersistenteActivo else { return }
        presentacionID &+= 1
        if !enRespuestaIA { fondo?.layer?.opacity = 1 }
        reposicionar()
        update(text)
        panel.orderFrontRegardless()
    }

    /// Pregunta contextual. El panel conserva el borde superior pegado al notch y
    /// expande el cuerpo hacia abajo; `fn` confirma y `X` descarta SOLO el plan.
    func showConfirmation(title: String, details: [String], content: String,
                          alternatives: [String], modoNormal: String,
                          footer: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showConfirmation(title: title, details: details, content: content,
                                       alternatives: alternatives, modoNormal: modoNormal,
                                       footer: footer)
            }
            return
        }
        guard Config.panelVisible(), !capturaPrivadaActiva,
              !resultadoCapturaPersistenteActivo else { return }
        // Hasta 8 etapas se muestran como siempre; más (la tabla de una
        // propuesta de conexión API) van COMPLETAS en un área con scroll.
        let usarScroll = details.count > 8
        let visibles = usarScroll ? details : Array(details.prefix(8))
        let sobrantes = max(0, details.count - visibles.count)
        confirmando = true
        presentacionID &+= 1
        flashHasta = .distantPast
        label.isHidden = true
        confirmTitle.isHidden = false
        confirmBody.isHidden = false
        confirmAlternatives.isHidden = true
        confirmFooter.isHidden = false
        confirmTitle.stringValue = title
        var lineas = visibles.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if sobrantes > 0 { lineas.append("… y \(sobrantes) etapa\(sobrantes == 1 ? "" : "s") más") }
        confirmTextoCompleto = lineas.joined(separator: "\n")
        if usarScroll {
            confirmBody.stringValue = ""
            confirmBody.isHidden = true
            confirmTexto.string = confirmTextoCompleto
            confirmScroll.isHidden = false
        } else {
            confirmBody.stringValue = confirmTextoCompleto
            confirmScroll.isHidden = true
        }
        let compacto = content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let extracto = compacto.count > 180 ? String(compacto.prefix(177)) + "…" : compacto
        confirmAlternatives.stringValue = "Texto: “\(extracto)”"
            + (alternatives.isEmpty ? "" : "\nOtras lecturas: " + alternatives.joined(separator: " · "))
        confirmAlternatives.isHidden = confirmAlternatives.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        confirmFooter.stringValue = footer
            ?? "\(Config.hotkey()) (una vez)  CONFIRMAR   ·   X  SEGUIR EN \(modoNormal.uppercased())"
        recalcularConfirmacion()
        relayout()
        reposicionar()
        panel.orderFrontRegardless()
    }

    func closeConfirmation() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.closeConfirmation() }
            return
        }
        guard confirmando else { return }
        confirmando = false
        label.isHidden = false
        confirmTitle.isHidden = true
        confirmBody.isHidden = true
        confirmScroll.isHidden = true
        confirmTextoCompleto = ""
        confirmAlternatives.isHidden = true
        confirmFooter.isHidden = true
        resultadoFinder.isHidden = true
        resultadoCerrar.isHidden = true
        resultadoCapturaPersistenteActivo = false
        resultadoCapturaRuta = ""
        resultadoFinderAccion = nil
        confirmLayout = nil
        relayout()
        reposicionar()
    }

    /// Resultado de una grabación que NO desaparece por temporizador. Durante la
    /// captura el notch está oculto y en silencio; esta tarjeta confirma de forma
    /// inequívoca dónde quedó el archivo y ofrece una acción real para encontrarlo.
    func showCaptureResult(title: String = "✓ Grabación guardada", message: String,
                           file: URL, onReveal: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showCaptureResult(title: title, message: message,
                                        file: file, onReveal: onReveal)
            }
            return
        }
        guard Config.panelVisible(), !capturaPrivadaActiva else { return }
        if confirmando { closeConfirmation() }
        resultadoCapturaPersistenteActivo = true
        resultadoCapturaRuta = file.path
        resultadoFinderAccion = onReveal ?? {
            if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                NSWorkspace.shared.open(file.deletingLastPathComponent())
            }
        }
        confirmando = true
        presentacionID &+= 1
        flashHasta = .distantPast
        fondo?.layer?.removeAllAnimations()
        fondo?.layer?.opacity = 1
        label.isHidden = true
        confirmTitle.isHidden = false
        confirmBody.isHidden = false
        confirmAlternatives.isHidden = false
        confirmFooter.isHidden = true
        resultadoFinder.isHidden = false
        resultadoCerrar.isHidden = false
        confirmTitle.stringValue = title
        confirmBody.stringValue = message
        confirmAlternatives.stringValue = "Ruta:\n\(file.path)"
        recalcularConfirmacion()
        relayout()
        reposicionar()
        panel.orderFrontRegardless()
    }

    func closeCaptureResult() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.closeCaptureResult() }
            return
        }
        guard resultadoCapturaPersistenteActivo else { return }
        closeConfirmation()
        presentacionID &+= 1
        panel.orderOut(nil)
    }

    /// Hook interno: verifica el botón real sin abrir Finder durante QA.
    func activarVerEnFinderParaQA() { resultadoFinder.performClick(nil) }
    var resultadoCapturaSinSolapes: Bool { confirmLayout?.sinSolapes == true }

    /// Captura interna para QA visual sin depender del permiso de grabación de pantalla.
    /// Solo rasteriza el contenido del propio panel; no ve ninguna otra app ni pantalla.
    func guardarSnapshotQA(_ url: URL) -> Bool {
        guard Thread.isMainThread, let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url, options: .atomic); return true }
        catch { return false }
    }

    /// Muestra un aviso breve por N segundos, por encima del texto del dictado.
    /// Aviso breve que NO esconde el notch: al terminar recupera lo que decía.
    ///
    /// `flash` programa su propio cierre, y eso estaba mal para avisar a mitad
    /// de un dictado: el aviso salía y acto seguido desaparecía el panel entero
    /// —con el texto en vivo, el cronómetro y el medidor— aunque se siguiera
    /// grabando. Si sigues hablando, el notch se queda.
    func avisoSinCerrar(_ texto: String, segundos: TimeInterval) {
        guard Config.panelVisible(), !capturaPrivadaActiva, !enRespuestaIA,
              !resultadoCapturaPersistenteActivo else { return }
        let previo = label.stringValue
        label.stringValue = texto
        panel.orderFrontRegardless()
        let id = presentacionID
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
            guard let self, self.presentacionID == id else { return }
            // Solo se restaura si nadie escribió algo más entretanto: el texto
            // en vivo manda sobre el aviso.
            if self.label.stringValue == texto { self.label.stringValue = previo }
        }
    }

    func flash(_ text: String, segundos: TimeInterval = 2.5) {
        guard Config.panelVisible(), !capturaPrivadaActiva, !enRespuestaIA,
              !resultadoCapturaPersistenteActivo else { return }
        presentacionID &+= 1
        reposicionar()
        flashHasta = Date().addingTimeInterval(segundos)
        label.stringValue = text
        panel.orderFrontRegardless()
        // El flash programa SU PROPIO cierre: al subir presentacionID canceló cualquier
        // hide anterior — sin esto, un flash tras un hide dejaba el notch pegado.
        hide(after: segundos)
    }

    /// La pantalla con notch, o la que tenga el ratón, o la principal.
    /// Al cerrar/abrir el portátil o mover de monitor, la pantalla activa
    /// cambia — sin esto el panel se queda pegado a coordenadas viejas
    /// (aparecía abajo a la izquierda tras dormir/despertar el Mac).
    private func pantallaActiva() -> NSScreen? {
        if let conNotch = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return conNotch
        }
        let raton = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(raton, $0.frame, false) } ?? NSScreen.main
    }

    /// Recalcula geometría del notch y recoloca el panel en la pantalla
    /// activa AHORA (se llama en cada aparición, no solo al arrancar).
    private func reposicionar() {
        guard let screen = pantallaActiva() else { return }
        var notchRect = NSRect(x: screen.frame.midX - 105,
                               y: screen.frame.maxY - 36, width: 210, height: 36)
        notchHeight = max(screen.safeAreaInsets.top, 28)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchRect = NSRect(x: left.maxX, y: screen.frame.maxY - notchHeight,
                               width: right.minX - left.maxX, height: notchHeight)
        } else {
            notchRect = NSRect(x: screen.frame.midX - 105, y: screen.frame.maxY - notchHeight,
                               width: 210, height: notchHeight)
        }
        let nuevoAncho = notchRect.width + wing * 2
        let cambioAncho = abs(nuevoAncho - width) > 0.5
        if cambioAncho {
            width = nuevoAncho
            if confirmando { recalcularConfirmacion() }
        }
        let nuevoAlto = notchHeight + stripActual
        let cambioAlto = abs(nuevoAlto - height) > 0.5
        // Si cambió el tamaño (notch ↔ pantalla externa), relayout completo.
        if cambioAncho || cambioAlto {
            height = nuevoAlto
            relayout()
        }
        panel.setFrame(NSRect(x: notchRect.minX - wing, y: notchRect.maxY - height,
                              width: width, height: height), display: true)
    }

    /// Reajusta los subviews cuando cambia el tamaño (cambio de pantalla).
    private func relayout() {
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let inferior = stripActual
        // El medidor cede diez puntos por abajo para el cronómetro. Solo ocupan
        // sitio cuando hay algo que contar: si no se graba, el rótulo va vacío.
        let altoCrono: CGFloat = cronoInicio == nil ? 0 : 10
        meter.frame = NSRect(x: 8, y: inferior + 7 + altoCrono,
                             width: wing - 16, height: notchHeight - 14 - altoCrono)
        cronoLabel.frame = altoCrono == 0 ? .zero
            : NSRect(x: 2, y: inferior + 2, width: wing - 4, height: altoCrono)
        let capW: CGFloat = 30
        let capH: CGFloat = notchHeight >= 34 ? 18 : 14
        keycap.font = NSFont.systemFont(ofSize: capH >= 18 ? 12 : 10, weight: .semibold)
        keycap.frame = NSRect(x: width - wing + (wing - capW) / 2, y: inferior + 2, width: capW, height: capH)
        let motorH = max(8, notchHeight - capH - 7)
        motorLabel.frame = NSRect(x: width - wing + 1, y: inferior + capH + 4,
                                  width: wing - 2, height: min(motorH, 10))
        modoLabel.frame = NSRect(x: 1, y: inferior + notchHeight - 11, width: wing - 2, height: 10)
        label.frame = NSRect(x: 8, y: 4, width: width - 16, height: 15)
        if confirmando {
            if confirmLayout == nil { recalcularConfirmacion() }
            if let g = confirmLayout {
                confirmTitle.frame = g.title
                if confirmScroll.isHidden {
                    confirmBody.frame = g.body; confirmScroll.frame = .zero
                } else {
                    confirmScroll.frame = g.body; confirmBody.frame = .zero
                    confirmTexto.textContainer?.containerSize = NSSize(width: g.body.width - 14,
                                                                       height: .greatestFiniteMagnitude)
                    confirmTexto.textContainer?.widthTracksTextView = false
                }
                confirmAlternatives.frame = g.context; confirmFooter.frame = g.footer
                if resultadoCapturaPersistenteActivo {
                    let separacion: CGFloat = 8
                    let finderW: CGFloat = 118
                    let cerrarW: CGFloat = 72
                    let total = finderW + separacion + cerrarW
                    let x = g.footer.midX - total / 2
                    resultadoFinder.frame = NSRect(x: x, y: g.footer.minY,
                                                    width: finderW, height: g.footer.height)
                    resultadoCerrar.frame = NSRect(x: x + finderW + separacion,
                                                    y: g.footer.minY,
                                                    width: cerrarW, height: g.footer.height)
                } else {
                    resultadoFinder.frame = .zero; resultadoCerrar.frame = .zero
                }
            }
        } else {
            confirmTitle.frame = .zero; confirmBody.frame = .zero
            confirmAlternatives.frame = .zero; confirmFooter.frame = .zero
            resultadoFinder.frame = .zero; resultadoCerrar.frame = .zero
        }
    }

    private func recalcularConfirmacion() {
        let g = Self.geometriaConfirmacion(ancho: width,
                                           detalles: confirmTextoCompleto,
                                           contexto: confirmAlternatives.isHidden ? "" : confirmAlternatives.stringValue,
                                           footerHeight: resultadoCapturaPersistenteActivo ? 26 : 15)
        confirmLayout = g; confirmStrip = g.strip
    }

    /// Pública dentro del módulo para el hook QA; no depende de una ventana ni de una
    /// pantalla real y permite probar textos de 1 a 8 etapas reproduciblemente.
    static func geometriaConfirmacion(ancho: CGFloat, detalles: String,
                                      contexto: String, footerHeight: CGFloat = 15) -> ConfirmationLayout {
        let margenX: CGFloat = 12
        let anchoTexto = max(120, ancho - margenX * 2)
        func alto(_ texto: String, fuente: NSFont, linea: CGFloat, maxLineas: Int) -> CGFloat {
            guard !texto.isEmpty else { return 0 }
            let r = (texto as NSString).boundingRect(
                with: NSSize(width: anchoTexto, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: fuente])
            return min(CGFloat(maxLineas) * linea, max(linea, ceil(r.height)))
        }

        let footer = NSRect(x: 8, y: 7, width: max(120, ancho - 16),
                            height: max(15, footerHeight))
        var y = footer.maxY + 7
        let contextoH = alto(contexto, fuente: NSFont.systemFont(ofSize: 9), linea: 13, maxLineas: 4)
        let contextoRect = NSRect(x: margenX, y: y, width: anchoTexto, height: contextoH)
        if contextoH > 0 { y = contextoRect.maxY + 8 }
        let bodyH = alto(detalles, fuente: NSFont.systemFont(ofSize: 11, weight: .medium),
                         linea: 17, maxLineas: 10)
        let body = NSRect(x: margenX, y: y, width: anchoTexto, height: max(17, bodyH))
        y = body.maxY + 8
        let title = NSRect(x: margenX, y: y, width: anchoTexto, height: 18)
        let strip = min(310, title.maxY + 10)
        return ConfirmationLayout(strip: strip, title: title, body: body,
                                  context: contextoRect, footer: footer)
    }

    /// Teleprompter de una línea: siempre muestra el FINAL (lo último dicho).
    /// El truncado por la cabeza (.byTruncatingHead) + alineación derecha se
    /// encargan de recortar lo viejo; no hace falta cortar a mano.
    func update(_ text: String) {
        // No pisar un aviso breve todavía vigente ni la respuesta de la IA.
        guard !capturaPrivadaActiva, !enRespuestaIA, !confirmando,
              Date() >= flashHasta else { return }
        label.stringValue = text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Update que SÍ pisa el flash (para la entrega final del dictado).
    func updateForzado(_ text: String) {
        guard !capturaPrivadaActiva, !enRespuestaIA, !confirmando else { return }
        flashHasta = .distantPast
        label.stringValue = text.replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Notch de RESPUESTA DE IA (distinto al de dictado)
    //
    // Al revés del dictado: aquí aparece lo que la IA RESPONDE (mientras habla), no lo
    // que tú dictas. Look propio (🤖, color azul, sin medidor de mic) para reconocerlo,
    // y NO se comporta como el dictado (no lo pisan update/flash, no muestra nivel).

    private(set) var enRespuestaIA = false
    private let colorIA = NSColor(calibratedRed: 0.45, green: 0.72, blue: 1.0, alpha: 1)

    /// El agente está PENSANDO: notch late (pulso) + con qué IA trabaja (local/Hermes/
    /// OpenClaw). Súper básico — solo se ve que está pensando. `ia` = nombre a mostrar.
    func pensando(ia: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.pensando(ia: ia) }
            return
        }
        guard Config.panelVisible(), !capturaPrivadaActiva,
              !resultadoCapturaPersistenteActivo else { return }
        presentacionID &+= 1
        enRespuestaIA = true
        reposicionar()
        meter.isHidden = true
        modoLabel.stringValue = "🤖 IA"
        motorLabel.stringValue = ia.uppercased()
        motorLabel.textColor = colorIA
        label.textColor = colorIA
        label.stringValue = "pensando…"
        panel.orderFrontRegardless()
        pulsar(true)
    }

    private var revelarTimer: Timer?
    private var palabrasIA: [String] = []
    private var idxIA = 0

    /// Muestra la RESPUESTA de la IA REVELÁNDOLA palabra por palabra, al ritmo aproximado
    /// del habla (para que el texto AVANCE como va hablando, no que se pegue todo de una).
    func respuestaIA(_ texto: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.respuestaIA(texto) }
            return
        }
        guard Config.panelVisible(), !capturaPrivadaActiva,
              !resultadoCapturaPersistenteActivo else { return }
        if !enRespuestaIA { pensando(ia: "local") }   // por si no pasó por "pensando"
        label.textColor = colorIA
        let limpio = texto.replacingOccurrences(of: "\n", with: " ")
        palabrasIA = limpio.split(separator: " ").map(String.init)
        idxIA = 0
        revelarTimer?.invalidate()
        // Duración estimada del habla ≈ chars × ~0.058s (≈17 car/s). Reparte las palabras
        // en ese tiempo → el texto termina más o menos cuando termina la voz.
        let dur = max(1.5, Double(limpio.count) * 0.058)
        let intervalo = max(0.12, dur / Double(max(1, palabrasIA.count)))
        label.stringValue = ""
        panel.orderFrontRegardless()
        let t = Timer(timeInterval: intervalo, repeats: true) { [weak self] tm in
            guard let self else { tm.invalidate(); return }
            guard self.idxIA < self.palabrasIA.count else { tm.invalidate(); return }
            self.idxIA += 1
            self.label.stringValue = self.palabrasIA[0..<self.idxIA].joined(separator: " ")
        }
        RunLoop.main.add(t, forMode: .common)
        revelarTimer = t
    }

    /// Latido del notch entero (pulso de opacidad). "Está pensando/hablando".
    private func pulsar(_ on: Bool) {
        guard let l = fondo?.layer else { return }
        if on {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0; a.toValue = 0.55; a.duration = 0.75
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(a, forKey: "pulso")
        } else { l.removeAnimation(forKey: "pulso"); l.opacity = 1 }
    }

    /// Actualiza el texto de la respuesta (si la IA lo entrega en trozos).
    func actualizarRespuestaIA(_ texto: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.actualizarRespuestaIA(texto) }
            return
        }
        guard enRespuestaIA else { return }
        label.stringValue = texto.replacingOccurrences(of: "\n", with: " ")
    }

    /// Cierra el modo respuesta de IA y vuelve el notch a lo normal.
    func finRespuestaIA() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.finRespuestaIA() }
            return
        }
        guard enRespuestaIA else { return }
        enRespuestaIA = false
        revelarTimer?.invalidate(); revelarTimer = nil
        if !palabrasIA.isEmpty { label.stringValue = palabrasIA.joined(separator: " ") }  // revela lo que falte
        pulsar(false)
        label.textColor = .white
        motorLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        meter.isHidden = false
        setModo(ModosStore.activo())   // restaura el letrero de modo
        hide(after: 1.5)
    }

    /// Letrero del motor activo, encima del fn. Verde = texto en vivo;
    /// gris = se transcribe al soltar la tecla. Clic = selector rápido.
    func setMotor(_ nombre: String, enVivo: Bool) {
        motorLabel.stringValue = nombre.uppercased()
        motorLabel.textColor = enVivo
            ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

    /// Menú emergente anclado al letrero del motor (para el selector rápido).
    func popUpMotorMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: motorLabel.frame.minX, y: motorLabel.frame.minY - 4),
                   in: panel.contentView)
    }
    func popUpModoMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: modoLabel.frame.minX, y: modoLabel.frame.minY - 4),
                   in: panel.contentView)
    }

    var esVisible: Bool { panel.isVisible }

    /// Saca el notch de la pantalla y bloquea cualquier reaparición mientras
    /// `screencapture` está vivo. Se llama antes de iniciar tanto fotos como video.
    func comenzarCapturaPrivada() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.comenzarCapturaPrivada() }
            return
        }
        // Una acción puede llegar justo cuando termina una respuesta o una
        // confirmación. Normaliza ese estado antes de ocultar para que, al
        // restaurar, no reaparezca una pregunta/latido viejo.
        if confirmando { closeConfirmation() }
        if enRespuestaIA { finRespuestaIA() }
        capturaPrivadaActiva = true
        presentacionID &+= 1
        flashHasta = .distantPast
        meter.reset()
        fondo?.layer?.removeAllAnimations()
        panel.orderOut(nil)
    }

    /// Libera el bloqueo, pero no reaparece por sí solo. El llamador decide si
    /// muestra el resultado o permanece oculto.
    func terminarCapturaPrivada() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.terminarCapturaPrivada() }
            return
        }
        capturaPrivadaActiva = false
        presentacionID &+= 1 // invalida cierres/respuestas diferidos del estado anterior
    }

    func hide(after seconds: TimeInterval = 0) {
        guard !resultadoCapturaPersistenteActivo else { return }
        meter.reset()
        // Red de seguridad: si un camino de salida no paró el contador, aquí no
        // se queda un temporizador vivo contra un panel escondido.
        if cronoInicio != nil { detenerCronometro() }
        if seconds == 0 {
            presentacionID &+= 1
            panel.orderOut(nil)
        } else {
            let id = presentacionID
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, self.presentacionID == id else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

/// Espera bloqueante corta para las pruebas propias: deja correr el bucle
/// principal, que es quien restaura el aviso, sin dormir el hilo.
func XCTEsperaQA(_ segundos: TimeInterval) -> Bool {
    let hasta = Date().addingTimeInterval(segundos)
    while Date() < hasta {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return true
}
