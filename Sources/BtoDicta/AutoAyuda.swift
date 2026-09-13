import AppKit

extension Notification.Name {
    static let betoAutoAyudaCambio = Notification.Name("BtoDictaAutoAyudaCambio")
}

// MARK: - Catálogo de explicaciones breves

/// Convierte el nombre visible de un control en una explicación corta y útil.
/// Las ayudas escritas a mano con `.help(...)` siempre ganan; este catálogo es
/// el respaldo para controles actuales, dinámicos y futuros.
enum AutoAyudaCatalogo {
    enum Tipo {
        case boton
        case enlace
        case interruptor
    }

    static func texto(etiqueta: String,
                      tipo: Tipo = .boton,
                      simbolo: String? = nil,
                      explicita: String? = nil) -> String {
        if let explicita = limpia(explicita), !explicita.isEmpty { return explicita }

        let nombre = limpia(etiqueta) ?? ""
        let normal = normalizar(nombre)
        let icono = normalizar(simbolo ?? "")

        if tipo == .enlace {
            let destino = nombre.isEmpty ? "este enlace" : "«\(nombre)»"
            return "Abre \(destino) en tu navegador predeterminado. No cambia tus ajustes en BtoDicta."
        }
        if tipo == .interruptor {
            let opcion = nombre.isEmpty ? "esta opción" : "«\(nombre)»"
            return "Activa o desactiva \(opcion). El cambio se guarda automáticamente."
        }

        if let ayudaIcono = ayudaParaIcono(icono.isEmpty ? normal : icono) {
            return ayudaIcono
        }

        // Casos donde el verbo por sí solo no explica suficientemente el efecto.
        if contiene(normal, ["conseguir clave", "obtener clave", "api key"]) {
            return "Abre la página oficial del proveedor para crear o administrar tu clave de API."
        }
        if contiene(normal, ["invitame un cafe", "github sponsors", "paypal"]) {
            return "Abre la página oficial de apoyo a BtoDicta en tu navegador. No realiza ningún pago automáticamente."
        }
        if contiene(normal, ["abrir plataforma api", "datos meteorologicos", "open-meteo"]) {
            return "Abre el sitio oficial indicado en tu navegador predeterminado."
        }
        if contiene(normal, ["poner por defecto"]) {
            return "Convierte esta opción en la predeterminada para los próximos dictados."
        }
        if contiene(normal, ["aplicar sugerencia"]) {
            return "Aplica el orden recomendado; después puedes cambiarlo manualmente."
        }
        if contiene(normal, ["ver el manual", "abrir manual"]) {
            return "Abre el manual de BtoDicta con instrucciones y ejemplos de uso."
        }
        if contiene(normal, ["revisar todas las novedades"]) {
            return "Muestra el historial completo de cambios y funciones nuevas."
        }
        if contiene(normal, ["abrir estadisticas", "estadisticas"]) {
            return "Abre el detalle de uso, tiempos y costos registrados por BtoDicta."
        }
        if contiene(normal, ["borrar memoria"]) {
            return "Olvida el contexto conversacional corto del asistente; no borra tus dictados."
        }
        if contiene(normal, ["nueva conversacion"]) {
            return "Empieza una conversación limpia sin reutilizar el contexto anterior."
        }
        if contiene(normal, ["probar sin dejar nota"]) {
            return "Comprueba el permiso y la conexión con Notas sin crear contenido permanente."
        }
        if contiene(normal, ["probar clima"]) {
            return "Consulta el clima ahora para comprobar ubicación, red y respuesta del servicio."
        }
        if contiene(normal, ["ver todos los resultados", "ver en finder", "mostrar en finder"]) {
            return "Abre Finder mostrando los resultados o el archivo seleccionado."
        }
        if contiene(normal, ["automatico"]) {
            return "Quita la elección manual y deja que BtoDicta seleccione esta opción automáticamente."
        }
        if contiene(normal, ["limpiar hechas", "limpiar completadas"]) {
            return "Elimina de la lista las tareas que ya marcaste como completadas."
        }
        if contiene(normal, ["actualizar estado", "actualizar lista", "refrescar", "recargar"]) {
            return "Vuelve a leer el estado actual sin cambiar tus datos."
        }
        if contiene(normal, ["solicitar permiso", "ajustes de ubicacion", "ajustes de notificaciones"]) {
            return "Abre o solicita el permiso de macOS necesario para usar esta función."
        }

        // Familias de acciones. El orden importa: «Reinstalar» antes de «Instalar».
        if empieza(normal, ["reinstalar"]) {
            return "Vuelve a instalar este componente para repararlo o actualizarlo, conservando tu configuración."
        }
        if empieza(normal, ["instalar"]) {
            return "Instala el componente necesario en tu Mac; macOS puede pedir autorización."
        }
        if empieza(normal, ["descargar", "bajar"]) {
            return "Descarga este recurso a tu Mac para poder usarlo localmente."
        }
        if empieza(normal, ["preparar"]) {
            return "Prepara dependencias y archivos requeridos antes de ejecutar el proceso principal."
        }
        if empieza(normal, ["entrenar"]) || contiene(normal, ["entrenar una voz", "entrenar voz"]) {
            return "Inicia el entrenamiento con los parámetros elegidos. Puede tardar y podrás revisar su progreso."
        }
        if empieza(normal, ["reanudar", "continuar"]) {
            return "Continúa el proceso desde el último punto seguro guardado, sin empezar de cero."
        }
        if empieza(normal, ["detener", "parar"]) {
            return "Detiene el proceso actual de forma segura; si admite reanudación, conserva el avance."
        }
        if empieza(normal, ["validar"]) {
            return "Evalúa los resultados disponibles y muestra datos para ayudarte a elegir el mejor."
        }
        if empieza(normal, ["probar"]) {
            return "Ejecuta una prueba controlada y muestra el resultado sin cambiar tu flujo normal."
        }
        if empieza(normal, ["comprobar", "verificar"]) {
            return "Comprueba el estado real de esta conexión o función y actualiza el resultado mostrado."
        }
        if empieza(normal, ["conectar"]) {
            return "Inicia la conexión o autorización indicada; no sustituye tus otras conexiones."
        }
        if empieza(normal, ["importar", "subir"]) {
            return "Selecciona un archivo y añade sus datos o recursos a BtoDicta."
        }
        if empieza(normal, ["exportar", "descargar paquete"]) || contiene(normal, ["paquete trabajo", "paquete universidad", "paquete casa", "mis recetas", "toda la biblioteca"]) {
            return "Guarda una copia portable para respaldarla, compartirla o importarla en otra instalación."
        }
        if empieza(normal, ["guardar", "poner valor"]) {
            return "Guarda los cambios de esta sección en tu configuración local."
        }
        if empieza(normal, ["usar", "elegir", "seleccionar"]) {
            return "Selecciona esta opción para usarla en BtoDicta."
        }
        if empieza(normal, ["agregar", "anadir", "nueva", "nuevo"]) || contiene(normal, ["agregar a la cascada"]) {
            return "Añade un elemento nuevo; podrás configurarlo o quitarlo después."
        }
        if empieza(normal, ["crear", "recrear", "hacer propia", "generar"]) {
            return "Crea el recurso indicado con los datos y parámetros actuales."
        }
        if empieza(normal, ["programar"]) {
            return "Asigna una fecha y hora para que BtoDicta pueda avisarte."
        }
        if empieza(normal, ["restablecer"]) {
            return "Restaura el valor recomendado de esta opción."
        }
        if empieza(normal, ["borrar", "eliminar", "quitar", "descartar"]) {
            return "Quita este elemento de BtoDicta. Úsalo solo si ya no necesitas sus datos o su configuración local."
        }
        if empieza(normal, ["copiar"]) {
            return "Copia el resultado al portapapeles para pegarlo en otra aplicación."
        }
        if empieza(normal, ["abrir", "ver "]) {
            return "Abre \(nombre.isEmpty ? "el elemento seleccionado" : "«\(nombre)»") sin enviarlo ni modificarlo automáticamente."
        }
        if empieza(normal, ["reproducir", "escuchar"]) {
            return "Reproduce una vista previa para que puedas comprobarla antes de elegirla."
        }
        if empieza(normal, ["cancelar", "cerrar"]) || normal == "entendido" {
            return "Cierra esta acción o ventana sin aplicar cambios pendientes."
        }
        if empieza(normal, ["atras"]) {
            return "Regresa al paso anterior sin perder lo que ya configuraste."
        }
        if empieza(normal, ["siguiente", "empezar"]) {
            return "Avanza al siguiente paso del asistente de configuración."
        }
        if empieza(normal, ["finalizar"]) {
            return "Guarda la configuración del asistente y termina este recorrido."
        }
        if contiene(normal, ["arriba", "subir prioridad"]) {
            return "Sube esta opción una posición para darle mayor prioridad."
        }
        if contiene(normal, ["abajo", "bajar prioridad"]) {
            return "Baja esta opción una posición para darle menor prioridad."
        }

        let accion = nombre.isEmpty ? "este control" : "«\(nombre)»"
        return "Ejecuta \(accion). El resultado se mostrará en esta ventana antes de cualquier paso adicional."
    }

    private static func ayudaParaIcono(_ valor: String) -> String? {
        if contiene(valor, ["trash", "papelera", "🗑"]) {
            return "Elimina este elemento de la lista."
        }
        if contiene(valor, ["plus", "add", "➕"]) {
            return "Añade un elemento nuevo a esta sección."
        }
        if contiene(valor, ["minus.circle", "menos"]) {
            return "Quita este elemento de la sección."
        }
        if contiene(valor, ["xmark", "close", "cancel"]) {
            return "Cancela o cierra esta acción sin aplicar cambios pendientes."
        }
        if contiene(valor, ["chevron.up", "flecha arriba"]) {
            return "Sube este elemento una posición para darle mayor prioridad."
        }
        if contiene(valor, ["chevron.down", "flecha abajo"]) {
            return "Baja este elemento una posición para darle menor prioridad."
        }
        if contiene(valor, ["arrow.down.circle", "⬇︎", "download"]) {
            return "Descarga este recurso a tu Mac."
        }
        if contiene(valor, ["arrow.clockwise", "refresh", "reload"]) {
            return "Actualiza la información mostrada con el estado más reciente."
        }
        if contiene(valor, ["play.circle", "play", "🔊", "speaker"]) {
            return "Reproduce una vista previa de este audio."
        }
        if contiene(valor, ["brain", "🧠"]) {
            return "Genera o actualiza el perfil de estilo de esta voz."
        }
        if contiene(valor, ["eye.slash"]) {
            return "Oculta el valor sensible de este campo."
        }
        if valor == "eye" || contiene(valor, ["mostrar contrasena", "mostrar clave"]) {
            return "Muestra temporalmente el valor sensible de este campo."
        }
        if contiene(valor, ["doc.on.clipboard", "clipboard"]) {
            return "Copia el resultado al portapapeles."
        }
        if contiene(valor, ["square.and.arrow.down", "save"]) {
            return "Guarda el resultado en un archivo elegido por ti."
        }
        if contiene(valor, ["wand.and.stars"]) {
            return "Analiza el uso de los modos y propone mejoras configurables."
        }
        if contiene(valor, ["doc.text.magnifyingglass"]) {
            return "Abre el registro detallado de modos para revisar qué reconoció BtoDicta."
        }
        return nil
    }

    private static func limpia(_ valor: String?) -> String? {
        valor?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizar(_ valor: String) -> String {
        valor.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contiene(_ valor: String, _ patrones: [String]) -> Bool {
        patrones.contains { valor.contains($0) }
    }

    private static func empieza(_ valor: String, _ patrones: [String]) -> Bool {
        patrones.contains { valor.hasPrefix($0) }
    }
}

// MARK: - Tooltip instantáneo para controles AppKit y SwiftUI

@MainActor
final class AutoAyudaControles: NSObject {
    static let shared = AutoAyudaControles()

    private struct Objetivo {
        let vista: NSView
        let ayuda: String
        let clave: ObjectIdentifier
    }

    private var monitor: Any?
    private var observadores: [NSObjectProtocol] = []
    private var pendiente: DispatchWorkItem?
    private var claveActual: ObjectIdentifier?
    private let ayudasGeneradas = NSMapTable<NSView, NSString>.weakToStrongObjects()
    private let burbuja = AutoAyudaPanel()

    private override init() { super.init() }

    func activar() {
        guard monitor == nil else {
            actualizarHabilitacion()
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .mouseEntered, .mouseExited,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .keyDown
        ]) { [weak self] evento in
            guard let self else { return evento }
            if evento.type == .mouseMoved || evento.type == .mouseEntered {
                self.procesarMovimiento(evento)
            } else {
                self.ocultar()
            }
            return evento
        }

        let centro = NotificationCenter.default
        for nombre in [NSWindow.didBecomeKeyNotification,
                       NSWindow.didBecomeMainNotification,
                       NSApplication.didBecomeActiveNotification] {
            observadores.append(centro.addObserver(forName: nombre, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.prepararVentanas() }
            })
        }
        observadores.append(centro.addObserver(forName: NSApplication.didResignActiveNotification,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.ocultar() }
        })
        observadores.append(centro.addObserver(forName: .betoAutoAyudaCambio,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.actualizarHabilitacion() }
        })
        prepararVentanas()
    }

    func detener() {
        pendiente?.cancel(); pendiente = nil
        ocultar()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        observadores.forEach(NotificationCenter.default.removeObserver)
        observadores.removeAll()
    }

    /// El interruptor desactiva solo la burbuja visual. La descripción AX se
    /// conserva para VoiceOver y otras tecnologías de asistencia.
    func actualizarHabilitacion() {
        if !Config.autoAyudaControles() { ocultar() }
        prepararVentanas()
    }

    func prepararVentanas() {
        for ventana in NSApp.windows where ventana !== burbuja {
            ventana.acceptsMouseMovedEvents = true
            if let contenido = ventana.contentView { preparar(vista: contenido) }
        }
    }

    /// QA de interfaz: cuenta controles accionables que AppKit expone y cuáles
    /// siguen sin descripción de accesibilidad después del barrido.
    func diagnostico(ventanas: [NSWindow]? = nil) -> (controles: Int, sinAyuda: [String]) {
        var total = 0
        var faltan: [String] = []
        for ventana in ventanas ?? NSApp.windows where ventana !== burbuja {
            guard let contenido = ventana.contentView else { continue }
            preparar(vista: contenido)
            auditar(vista: contenido, total: &total, faltan: &faltan)
        }
        return (total, faltan)
    }

    /// Verifica que la burbuja instantánea pueda presentar una ayuda real sin
    /// activar ni robar el foco a la ventana auditada.
    func probarBurbujaQA(_ completion: @escaping (Bool, String) -> Void) {
        prepararVentanas()
        var elegido: (NSWindow, NSView, String)?
        // En apps LSUIElement, `isVisible` puede permanecer en false unos ciclos
        // aunque System Events ya vea la ventana. El control y su `window` son la
        // evidencia estable que necesitamos para probar el panel no activante.
        for ventana in NSApp.windows where ventana !== burbuja {
            guard let contenido = ventana.contentView,
                  let control = primerAccionable(en: contenido),
                  let d = descriptor(control) else { continue }
            elegido = (ventana, control, d.ayuda)
            break
        }
        guard let (ventana, _, ayuda) = elegido else {
            completion(false, "sin control visible para probar")
            return
        }
        let eraClave = ventana.isKeyWindow
        burbuja.mostrar(ayuda, cercaDe: NSPoint(x: ventana.frame.midX, y: ventana.frame.midY))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak ventana] in
            guard let self, let ventana else {
                completion(false, "la ventana desapareció")
                return
            }
            let pantalla = ventana.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let visible = self.burbuja.isVisible
            let noTomaFoco = !self.burbuja.isKeyWindow && ventana.isKeyWindow == eraClave
            let dentro = pantalla.intersects(self.burbuja.frame)
            let ok = visible && noTomaFoco && dentro
            let detalle = "visible=\(visible) foco_intacto=\(noTomaFoco) dentro_pantalla=\(dentro)"
            self.burbuja.orderOut(nil)
            completion(ok, detalle)
        }
    }

    private func preparar(vista: NSView) {
        if esAccionable(vista), let d = descriptor(vista) {
            let actual = vista.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if actual.isEmpty || esAyudaGenerada(actual, en: vista) {
                fijarAyudaGenerada(d.ayuda, en: vista)
            }
        }
        vista.subviews.forEach(preparar)
    }

    private func auditar(vista: NSView, total: inout Int, faltan: inout [String]) {
        if esAccionable(vista) {
            total += 1
            let ayuda = vista.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if ayuda.isEmpty {
                faltan.append(etiqueta(de: vista).isEmpty ? String(describing: type(of: vista)) : etiqueta(de: vista))
            }
        }
        for hija in vista.subviews { auditar(vista: hija, total: &total, faltan: &faltan) }
    }

    private func primerAccionable(en vista: NSView) -> NSView? {
        if esAccionable(vista) { return vista }
        for hija in vista.subviews {
            if let encontrada = primerAccionable(en: hija) { return encontrada }
        }
        return nil
    }

    private func procesarMovimiento(_ evento: NSEvent) {
        guard Config.autoAyudaControles(), let ventana = evento.window,
              ventana !== burbuja, let contenido = ventana.contentView else {
            ocultar(); return
        }
        let punto = contenido.convert(evento.locationInWindow, from: nil)
        guard let tocada = contenido.hitTest(punto), let objetivo = buscarObjetivo(desde: tocada) else {
            ocultar(); return
        }
        guard objetivo.clave != claveActual else { return }

        pendiente?.cancel()
        burbuja.orderOut(nil)
        claveActual = objetivo.clave
        let tarea = DispatchWorkItem { [weak self, weak vista = objetivo.vista] in
            guard let self, let vista, self.claveActual == objetivo.clave,
                  vista.window != nil, Config.autoAyudaControles() else { return }
            self.burbuja.mostrar(objetivo.ayuda, cercaDe: NSEvent.mouseLocation)
        }
        pendiente = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: tarea)
    }

    private func buscarObjetivo(desde vista: NSView) -> Objetivo? {
        var actual: NSView? = vista
        while let candidata = actual {
            if esAccionable(candidata), let d = descriptor(candidata) {
                let actual = candidata.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if actual.isEmpty || esAyudaGenerada(actual, en: candidata) {
                    fijarAyudaGenerada(d.ayuda, en: candidata)
                }
                return Objetivo(vista: candidata, ayuda: d.ayuda,
                                clave: ObjectIdentifier(candidata))
            }
            actual = candidata.superview
        }
        return nil
    }

    private func descriptor(_ vista: NSView) -> (ayuda: String, tipo: AutoAyudaCatalogo.Tipo)? {
        let explicita = ayudaExplicita(desde: vista)
        let tipo = tipoControl(vista)
        let nombre = etiqueta(de: vista)
        let simbolo = simbolo(de: vista)
        let ayuda = AutoAyudaCatalogo.texto(etiqueta: nombre, tipo: tipo,
                                             simbolo: simbolo, explicita: explicita)
        return ayuda.isEmpty ? nil : (ayuda, tipo)
    }

    private func ayudaExplicita(desde vista: NSView) -> String? {
        var actual: NSView? = vista
        while let v = actual {
            if let t = v.toolTip?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            if let h = v.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines),
               !h.isEmpty, !esAyudaGenerada(h, en: v) { return h }
            // La ayuda de SwiftUI puede terminar en una vista hija inmediata.
            for hija in v.subviews {
                if let t = hija.toolTip?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
                if let h = hija.accessibilityHelp()?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !h.isEmpty, !esAyudaGenerada(h, en: hija) { return h }
            }
            if esAccionable(v), v !== vista { break }
            actual = v.superview
        }
        return nil
    }

    private func fijarAyudaGenerada(_ ayuda: String, en vista: NSView) {
        vista.setAccessibilityHelp(ayuda)
        ayudasGeneradas.setObject(ayuda as NSString, forKey: vista)
    }

    private func esAyudaGenerada(_ ayuda: String, en vista: NSView) -> Bool {
        (ayudasGeneradas.object(forKey: vista) as String?) == ayuda
    }

    private func esAccionable(_ vista: NSView) -> Bool {
        if vista is NSButton { return true }
        guard let role = vista.accessibilityRole()?.rawValue else { return false }
        return ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton",
                "AXMenuButton", "AXPopUpButton"].contains(role)
    }

    private func tipoControl(_ vista: NSView) -> AutoAyudaCatalogo.Tipo {
        let role = vista.accessibilityRole()?.rawValue ?? ""
        if role == "AXLink" { return .enlace }
        if role == "AXCheckBox" || role == "AXRadioButton" { return .interruptor }
        return .boton
    }

    private func etiqueta(de vista: NSView) -> String {
        if let boton = vista as? NSButton {
            let titulo = boton.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !titulo.isEmpty { return titulo }
        }
        if let label = vista.accessibilityLabel()?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let titulo = vista.accessibilityTitle()?.trimmingCharacters(in: .whitespacesAndNewlines), !titulo.isEmpty {
            return titulo
        }
        return ""
    }

    private func simbolo(de vista: NSView) -> String? {
        if let boton = vista as? NSButton {
            if let d = boton.image?.accessibilityDescription, !d.isEmpty { return d }
            if let id = boton.image?.name(), !id.isEmpty { return id }
        }
        return vista.identifier?.rawValue
    }

    private func ocultar() {
        pendiente?.cancel(); pendiente = nil
        claveActual = nil
        burbuja.orderOut(nil)
    }
}

@MainActor
private final class AutoAyudaPanel: NSPanel {
    private let etiqueta = NSTextField(wrappingLabelWithString: "")

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]

        let fondo = NSVisualEffectView()
        fondo.material = .popover
        fondo.blendingMode = .behindWindow
        fondo.state = .active
        fondo.wantsLayer = true
        fondo.layer?.cornerRadius = 9
        fondo.layer?.borderWidth = 0.5
        fondo.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        contentView = fondo

        etiqueta.font = .systemFont(ofSize: 12.5, weight: .regular)
        etiqueta.textColor = .labelColor
        etiqueta.maximumNumberOfLines = 0
        etiqueta.lineBreakMode = .byWordWrapping
        fondo.addSubview(etiqueta)
    }

    func mostrar(_ texto: String, cercaDe cursor: NSPoint) {
        let fuente = etiqueta.font ?? .systemFont(ofSize: 12.5)
        let atributos: [NSAttributedString.Key: Any] = [.font: fuente]
        let maxTexto: CGFloat = 300
        let primera = NSAttributedString(string: texto, attributes: atributos)
            .boundingRect(with: NSSize(width: maxTexto, height: 1_000),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let ancho = min(324, max(175, ceil(primera.width) + 24))
        let medida = NSAttributedString(string: texto, attributes: atributos)
            .boundingRect(with: NSSize(width: ancho - 24, height: 1_000),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let alto = max(38, ceil(medida.height) + 20)

        etiqueta.stringValue = texto
        etiqueta.frame = NSRect(x: 12, y: 10, width: ancho - 24, height: alto - 20)
        setContentSize(NSSize(width: ancho, height: alto))

        let pantalla = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
            ?? NSScreen.main
        let visible = pantalla?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = cursor.x + 14
        var y = cursor.y - alto - 14
        if x + ancho > visible.maxX { x = visible.maxX - ancho - 6 }
        if x < visible.minX { x = visible.minX + 6 }
        if y < visible.minY { y = min(visible.maxY - alto - 6, cursor.y + 18) }
        if y + alto > visible.maxY { y = visible.maxY - alto - 6 }
        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }
}

// MARK: - Prueba pura y rápida

enum AutoAyudaQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_HELPTEST"] == "1" else { return }
        let casos: [(String, AutoAyudaCatalogo.Tipo, String?, String?)] = [
            ("Guardar", .boton, nil, nil),
            ("Usar este", .boton, nil, nil),
            ("Reinstalar Atajo…", .boton, nil, nil),
            ("Descargar base", .boton, nil, nil),
            ("Entrenar", .boton, nil, nil),
            ("Reanudar donde quedó", .boton, nil, nil),
            ("Detener del todo", .boton, nil, nil),
            ("Validar y graficar", .boton, nil, nil),
            ("Probar clima ahora", .boton, nil, nil),
            ("Importar JSON…", .boton, nil, nil),
            ("Exportar CSV", .boton, nil, nil),
            ("Agregar paso", .boton, nil, nil),
            ("Quitar motor", .boton, nil, nil),
            ("Restablecer", .boton, nil, nil),
            ("Conectar en navegador", .boton, nil, nil),
            ("Actualizar lista", .boton, nil, nil),
            ("Abrir Estadísticas", .boton, nil, nil),
            ("Cancelar", .boton, nil, nil),
            ("Atrás", .boton, nil, nil),
            ("Siguiente", .boton, nil, nil),
            ("Finalizar", .boton, nil, nil),
            ("Conseguir clave", .boton, nil, nil),
            ("☕ Invítame un café", .boton, nil, nil),
            ("💜 GitHub Sponsors", .boton, nil, nil),
            ("Abrir plataforma API", .enlace, nil, nil),
            ("Mostrar el panel", .interruptor, nil, nil),
            ("", .boton, "trash", nil),
            ("", .boton, "chevron.up", nil),
            ("Acción propia", .boton, nil, nil),
        ]
        var fallos = 0
        for (etiqueta, tipo, simbolo, explicita) in casos {
            let ayuda = AutoAyudaCatalogo.texto(etiqueta: etiqueta, tipo: tipo,
                                                 simbolo: simbolo, explicita: explicita)
            let ok = ayuda.count >= 18
            if !ok { fallos += 1 }
            print("HELPTEST \(ok ? "OK" : "FALLA") \(etiqueta.isEmpty ? simbolo ?? "sin-etiqueta" : etiqueta) → \(ayuda)")
        }
        let manual = "Ayuda específica que debe conservarse."
        let preservada = AutoAyudaCatalogo.texto(etiqueta: "Guardar", explicita: manual) == manual
        if !preservada { fallos += 1 }
        print("HELPTEST \(preservada ? "OK" : "FALLA") prioridad de ayuda explícita")
        print("HELPTEST \(fallos == 0 ? "TODO OK" : "\(fallos) FALLOS")")
        fflush(stdout)
        exit(fallos == 0 ? 0 : 3)
    }
}
