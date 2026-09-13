import AppKit
import AVFoundation
import CoreGraphics
import Darwin
import Foundation

// MARK: - Capturas y grabaciones nativas de macOS
//
// La interpretación es local y determinista. La ejecución delega en
// /usr/sbin/screencapture, la interfaz nativa de macOS: no se simulan clics ni
// se intenta leer la pantalla por otra vía. Una captura destinada a WhatsApp
// se copia y, si el contacto es inequívoco, aplica la política visible elegida:
// portapapeles, preparar sin enviar o autoenviar explícitamente.

enum TipoCapturaMac: String {
    case imagen, video
}

enum AreaCapturaMac: String {
    case completa
    case principal
    case seleccion
    case ventana
    case superiorIzquierda = "superior_izquierda"
    case superiorDerecha = "superior_derecha"
    case inferiorIzquierda = "inferior_izquierda"
    case inferiorDerecha = "inferior_derecha"
}

enum DestinoCapturaMac: String, CaseIterable, Identifiable {
    case escritorio, descargas, documentos, preguntar

    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .escritorio: return "Escritorio"
        case .descargas: return "Descargas"
        case .documentos: return "Documentos"
        case .preguntar: return "Preguntar cada vez"
        }
    }
}

struct SolicitudCapturaMac {
    var tipo: TipoCapturaMac
    var area: AreaCapturaMac
    var destino: DestinoCapturaMac
    var nombre: String?
    var guardar: Bool
    var copiar: Bool
    var abrir: Bool
    var duracion: Int?
    var microfono: Bool
    var mostrarClics: Bool
    var compartirWhatsApp: Bool
    var contactoWhatsApp: String?

    /// Duración que realmente puede aplicar `screencapture -V`. Una selección o
    /// ventana necesita primero la barra interactiva de macOS y, por tanto, se
    /// detiene manualmente aunque la frase mencione un tiempo.
    var duracionAutomatica: Int? {
        guard tipo == .video, ![.seleccion, .ventana].contains(area) else { return nil }
        return duracion
    }

    /// La pantalla completa, principal y los cuadrantes pueden grabarse sin la
    /// barra interactiva de macOS. BtoDicta conserva la ruta solicitada y
    /// permite detener con una sola pulsación de la tecla de dictado.
    var controlContinuoBtoDicta: Bool {
        tipo == .video && duracion == nil && ![.seleccion, .ventana].contains(area)
    }

    var detencion: String {
        guard tipo == .video else { return "no_aplica" }
        if let segundos = duracionAutomatica { return "automatica_\(segundos)s" }
        return controlContinuoBtoDicta ? "continua_btodicta" : "manual_macos"
    }

    var detallePlan: String {
        let base: String
        if tipo == .imagen {
            base = "Capturar la pantalla"
        } else if let segundos = duracionAutomatica {
            base = "Grabar la pantalla durante \(segundos) segundo\(segundos == 1 ? "" : "s")"
        } else if controlContinuoBtoDicta {
            base = "Grabar la pantalla hasta que pulses una vez la tecla de dictado o Detener y guardar"
        } else {
            base = "Elegir qué grabar y detener desde el control de macOS"
        }
        var extras: [String] = []
        if guardar || tipo == .video { extras.append("guardar en \(destino.nombre)") }
        if copiar { extras.append("copiar al portapapeles") }
        if abrir { extras.append("abrir al terminar") }
        if compartirWhatsApp {
            let contacto = contactoWhatsApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            extras.append(contacto.isEmpty ? "preparar para WhatsApp"
                                           : "preparar para WhatsApp a \(contacto)")
        }
        return ([base] + extras).joined(separator: "; ")
    }

    static func interpretar(_ texto: String, duracionPredeterminada: Int? = nil,
                            tipoForzado: TipoCapturaMac? = nil) -> SolicitudCapturaMac {
        let normal = PerfilAgente.normalizar(texto)
        let pideGrabar = normal.contains("graba") || normal.contains("grabar")
            || normal.contains("grabacion") || normal.contains("video")
        let objetoVisible = normal.contains("pantalla") || normal.contains("ventana")
            || normal.contains("seccion") || normal.contains("seleccion") || normal.contains("area")
        let esVideo = tipoForzado == .video
            || (tipoForzado == nil && pideGrabar && objetoVisible)

        let area: AreaCapturaMac
        if normal.contains("ventana") {
            area = .ventana
        } else if normal.contains("cuarto superior izquierdo")
                    || normal.contains("cuadrante superior izquierdo") {
            area = .superiorIzquierda
        } else if normal.contains("cuarto superior derecho")
                    || normal.contains("cuadrante superior derecho") {
            area = .superiorDerecha
        } else if normal.contains("cuarto inferior izquierdo")
                    || normal.contains("cuadrante inferior izquierdo") {
            area = .inferiorIzquierda
        } else if normal.contains("cuarto inferior derecho")
                    || normal.contains("cuadrante inferior derecho") {
            area = .inferiorDerecha
        } else if normal.contains("seccion") || normal.contains("seleccion")
                    || normal.contains("una parte") || normal.contains("un area")
                    || normal.contains("un cuarto") {
            area = .seleccion
        } else if normal.contains("pantalla principal") || normal.contains("monitor principal") {
            area = .principal
        } else {
            area = .completa
        }

        let destino: DestinoCapturaMac
        if normal.contains("en descargas") || normal.contains("a descargas") {
            destino = .descargas
        } else if normal.contains("en documentos") || normal.contains("a documentos")
                    || normal.contains("mis documentos") {
            destino = .documentos
        } else if normal.contains("en el escritorio") || normal.contains("al escritorio") {
            destino = .escritorio
        } else if normal.contains("elige la ubicacion") || normal.contains("pregunta donde")
                    || normal.contains("en otra carpeta") {
            destino = .preguntar
        } else {
            destino = DestinoCapturaMac(rawValue: Config.capturaDestino()) ?? .escritorio
        }

        let comparte = normal.contains("whatsapp")
        // "Cópiala" ya expresa inequívocamente que la captura debe quedar en el
        // portapapeles; no obligues a la persona a añadir "al portapapeles".
        // También toleramos la separación frecuente del STT: "copia la y ábrela".
        let pideCopiar = normal.contains("portapapeles")
            || normal.range(of: #"\b(?:copiala|copialo|copiarla|copiarlo|copia\s+la|copia\s+lo)\b"#,
                            options: .regularExpression) != nil
        var copiar = Config.capturaCopiarPortapapeles() || pideCopiar || comparte
        var guardar = Config.capturaGuardarArchivo()
        if normal.contains("guarda") || normal.contains("guardar") { guardar = true }
        if normal.contains("sin guardar") || normal.contains("solo al portapapeles") { guardar = false }
        // Una grabación siempre necesita archivo. No descartes "cópialo" ni
        // WhatsApp: el video terminado también puede viajar como URL de archivo
        // en el portapapeles.
        if esVideo { guardar = true; copiar = Config.capturaCopiarPortapapeles() || pideCopiar || comparte }

        let duracionDicha = esVideo ? extraerDuracion(texto) : nil
        let manualExplicito = normal.contains("hasta que la detenga")
            || normal.contains("hasta que yo la detenga")
            || normal.contains("hasta que termine")
            || normal.contains("hasta que yo termine")
            || normal.contains("detener manualmente")
            || normal.contains("sin duracion")
        let predeterminada = min(3_600, max(0,
            duracionPredeterminada ?? Config.capturaDuracionPredeterminada()))
        let duracionFinal: Int? = esVideo
            ? (manualExplicito ? nil : (duracionDicha ?? (predeterminada > 0 ? predeterminada : nil)))
            : nil

        return SolicitudCapturaMac(
            tipo: esVideo ? .video : .imagen,
            area: area,
            destino: destino,
            nombre: extraerNombre(texto),
            guardar: guardar,
            copiar: copiar,
            abrir: Config.capturaAbrirAlTerminar()
                || normal.range(of: #"\b(?:abrela|abrelo|abrirla|abrirlo|abre\s+(?:la|lo|el\s+archivo)|abrir\s+el\s+archivo)\b"#,
                                options: .regularExpression) != nil
                || normal.contains("guarda y abre"),
            duracion: duracionFinal,
            microfono: esVideo && (Config.capturaGrabarMicrofono()
                || normal.contains("con microfono") || normal.contains("con audio")),
            mostrarClics: esVideo && (Config.capturaMostrarClics() || normal.contains("muestra los clics")),
            compartirWhatsApp: comparte,
            contactoWhatsApp: comparte ? extraerContactoWhatsApp(texto) : nil
        )
    }

    private static func capturar(_ patron: String, en texto: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]),
              let m = re.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: texto) else { return nil }
        let s = String(texto[r]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,.;:¡!¿?\"'"))
        return s.isEmpty ? nil : s
    }

    private static func extraerNombre(_ texto: String) -> String? {
        guard let capturado = capturar(
            #"(?:con\s+el\s+nombre(?:\s+de)?|ll[aá]m(?:ala|alo)|n[oó]mbr(?:ala|alo))\s+[\"“”']?(.+?)[\"“”']?(?=\s+(?:y\s*[,;:]?\s*(?:(?:por\s+favor)\s*[,;:]?\s*)?(?:c[oó]p(?:iala|ialo|iarla|iarlo|ia\s+(?:la|lo))|[aá]br(?:ela|elo|irla|irlo|e\s+(?:la|lo))|gu[aá]rd(?:ala|alo))|en\s+(?:descargas|documentos|el\s+escritorio)|por\s+whatsapp)|[,.;]|$)"#,
            en: texto) else { return nil }
        // Si el STT puso la coma después de la conjunción (“informe y,
        // por favor…”), la expresión termina capturando esa `y` suelta.
        return capturado.replacingOccurrences(of: #"\s+y$"#, with: "",
                                               options: .regularExpression)
    }

    private static func extraerDuracion(_ texto: String) -> Int? {
        guard let cantidad = capturar(#"(?:durante|por)?\s*(\d{1,3})\s*(?:segundos?|mins?|minutos?)"#, en: texto),
              let n = Int(cantidad) else { return nil }
        let esMinuto = texto.range(of: #"\b\d{1,3}\s*(?:mins?|minutos?)\b"#,
                                   options: [.regularExpression, .caseInsensitive]) != nil
        return min(3_600, max(1, esMinuto ? n * 60 : n))
    }

    private static func extraerContactoWhatsApp(_ texto: String) -> String? {
        capturar(#"(?:env[ií](?:a|ala|alo)?\s+)?(?:por\s+)?whatsapp\s+(?:del\s+grupo\s+de|para|al|a)?\s*(.+?)(?=\s+(?:con\s+el\s+nombre|y\s+(?:gu[aá]rd|[aá]br|cop))|[,.;]|$)"#, en: texto)
    }
}

struct ResultadoCapturaMac {
    let ok: Bool
    let mensaje: String
    let archivo: URL?
    let solicitud: SolicitudCapturaMac
}

/// Decisión pura del pegado en WhatsApp. Separarla del temporizador permite
/// probar el contrato sin abrir WhatsApp ni tocar el portapapeles del usuario.
enum PoliticaWhatsAppCaptura: String, CaseIterable, Identifiable {
    case portapapeles
    case preparar
    case enviar

    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .portapapeles: return "Solo abrir el chat y dejar en portapapeles"
        case .preparar: return "Pegar en el chat, sin enviar (recomendado)"
        case .enviar: return "Pegar y enviar automáticamente"
        }
    }
}

enum DecisionPegadoWhatsApp: Equatable {
    case pegar(autoEnviar: Bool), esperar, manual
}

enum PegadoWhatsApp {
    static func decidir(politica: PoliticaWhatsAppCaptura, appDisponible: Bool,
                        bundleFrente: String?, bundleEsperado: String,
                        intento: Int, maxIntentos: Int) -> DecisionPegadoWhatsApp {
        guard politica != .portapapeles, appDisponible else { return .manual }
        if bundleFrente == bundleEsperado { return .pegar(autoEnviar: politica == .enviar) }
        return intento < maxIntentos ? .esperar : .manual
    }
}

/// Evidencia mínima de la interfaz de WhatsApp antes/después de pegar. El
/// autoenvío exige que haya aparecido una vista nueva compatible con un adjunto;
/// encontrar solamente el botón normal «Enviar» no basta.
struct EstadoAdjuntoWhatsApp: Equatable {
    var imagenes = 0
    var dialogos = 0
    var marcadores = 0
    var botonesEnviar = 0
}

/// Autoenvío deliberado: solo pulsa un botón AX cuyo rótulo sea exactamente
/// Enviar/Send dentro de WhatsApp Y después de comprobar que el pegado cambió
/// la interfaz a una vista de adjunto. Nunca usa Return a ciegas, porque podría
/// mandar texto previo si la vista del adjunto no llegó a abrirse.
enum WhatsAppAccesibilidad {
    private static func atributo<T>(_ e: AXUIElement, _ nombre: CFString) -> T? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, nombre, &valor) == .success else { return nil }
        return valor as? T
    }

    private static let marcadoresAdjunto: [String] = [
        "anadir comentario", "anade un comentario", "agregar comentario",
        "add a caption", "caption", "vista previa", "preview",
        "editar foto", "edit photo", "recortar", "crop",
    ]

    private static func inspeccionarRaiz() -> (EstadoAdjuntoWhatsApp, [AXUIElement])? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: Acciones.bundle("whatsapp")).first,
              app.isActive else { return nil }
        let raiz = AXUIElementCreateApplication(app.processIdentifier)
        var cola: [AXUIElement] = [raiz]
        var vistos = Set<CFHashCode>()
        var estado = EstadoAdjuntoWhatsApp()
        var botones: [AXUIElement] = []
        var indice = 0
        while indice < cola.count, indice < 1_500 {
            let e = cola[indice]; indice += 1
            guard vistos.insert(CFHash(e)).inserted else { continue }
            let rol: String = atributo(e, kAXRoleAttribute as CFString) ?? ""
            if rol == kAXImageRole as String { estado.imagenes += 1 }
            if rol == kAXSheetRole as String || rol == "AXDialog" {
                estado.dialogos += 1
            }
            let textos: [String] = [
                atributo(e, kAXTitleAttribute as CFString),
                atributo(e, kAXDescriptionAttribute as CFString),
                atributo(e, kAXHelpAttribute as CFString),
                atributo(e, kAXValueAttribute as CFString),
            ].compactMap { $0 }
            let normalizados = textos.map(PerfilAgente.normalizar)
            if normalizados.contains(where: { texto in
                marcadoresAdjunto.contains(where: { texto.contains($0) })
            }) {
                estado.marcadores += 1
            }
            if rol == kAXButtonRole as String {
                if normalizados.contains(where: {
                    $0 == "enviar" || $0 == "send"
                }) {
                    estado.botonesEnviar += 1
                    botones.append(e)
                }
            }
            if let hijos: [AXUIElement] = atributo(e, kAXChildrenAttribute as CFString) {
                cola.append(contentsOf: hijos.prefix(100))
            }
        }
        return (estado, botones)
    }

    static func estadoVisible() -> EstadoAdjuntoWhatsApp? {
        inspeccionarRaiz()?.0
    }

    static func adjuntoConfirmado(antes: EstadoAdjuntoWhatsApp,
                                  despues: EstadoAdjuntoWhatsApp) -> Bool {
        guard despues.botonesEnviar > 0 else { return false }
        return despues.imagenes > antes.imagenes
            || despues.dialogos > antes.dialogos
            || despues.marcadores > antes.marcadores
    }

    static func pulsarEnviarAdjuntoVisible(desde antes: EstadoAdjuntoWhatsApp) -> Bool {
        guard let (despues, botones) = inspeccionarRaiz(),
              adjuntoConfirmado(antes: antes, despues: despues),
              botones.count == 1, let boton = botones.first else { return false }
        return AXUIElementPerformAction(boton, kAXPressAction as CFString) == .success
    }
}

enum CapturaMac {
    private final class SesionContinua {
        let id: UUID
        let solicitud: SolicitudCapturaMac
        let archivoFinal: URL
        let carpetaRecuperacion: URL
        let inicio = Date()
        let segundosPorParte: Int
        let completion: (ResultadoCapturaMac) -> Void
        var partes: [URL] = []
        var indice = 0
        var deteniendo = false
        var proceso: Process?
        var avisoFallo: String?
        var corteProgramado: DispatchWorkItem?

        init(id: UUID = UUID(), solicitud: SolicitudCapturaMac, archivoFinal: URL,
             carpetaRecuperacion: URL, segundosPorParte: Int,
             completion: @escaping (ResultadoCapturaMac) -> Void) {
            self.id = id
            self.solicitud = solicitud
            self.archivoFinal = archivoFinal
            self.carpetaRecuperacion = carpetaRecuperacion
            self.segundosPorParte = segundosPorParte
            self.completion = completion
        }
    }

    private static let lock = NSLock()
    private static var proceso: Process?
    private static var cancelada = false
    private static var sesionContinua: SesionContinua?
    private static var recuperando = false

    private static var raizRecuperacion: URL {
        Config.dir.appendingPathComponent("grabaciones-en-curso", isDirectory: true)
    }

    static var enCurso: Bool {
        lock.lock(); defer { lock.unlock() }
        return sesionContinua != nil || (proceso?.isRunning ?? false)
    }

    static var grabacionContinuaEnCurso: Bool {
        lock.lock(); defer { lock.unlock() }
        return sesionContinua != nil
    }

    static var segundosGrabacionContinua: Int {
        lock.lock(); defer { lock.unlock() }
        guard let inicio = sesionContinua?.inicio else { return 0 }
        return max(0, Int(Date().timeIntervalSince(inicio)))
    }

    /// Detiene la grabación continua sin descartarla. SIGINT hace que
    /// `screencapture` cierre el contenedor QuickTime antes de salir.
    @discardableResult
    static func detenerGrabacion() -> Bool {
        lock.lock()
        guard let sesion = sesionContinua, !sesion.deteniendo else {
            lock.unlock(); return false
        }
        sesion.deteniendo = true
        sesion.corteProgramado?.cancel()
        sesion.corteProgramado = nil
        let actual = sesion.proceso
        lock.unlock()
        AgenteLog.registrar("grabacion_detener", [
            "sesion": sesion.id.uuidString, "segundos": Int(Date().timeIntervalSince(sesion.inicio)),
            "partes_cerradas": sesion.partes.count,
        ])
        if let actual {
            // Aunque ya figure detenido, su terminationHandler puede estar
            // pendiente de añadir la última parte. No consolidar antes de él.
            if actual.isRunning {
                return Darwin.kill(actual.processIdentifier, SIGINT) == 0
            }
            return true
        }
        DispatchQueue.main.async { finalizarContinua(sesion) }
        return true
    }

    static func cancelar() {
        // Una grabación larga se preserva incluso si la app recibe Cancelar o
        // está cerrándose. Las capturas puntuales conservan la semántica antigua.
        if grabacionContinuaEnCurso { _ = detenerGrabacion(); return }
        lock.lock()
        cancelada = true
        let p = proceso
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }

    static func permisoConcedido() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func solicitarPermiso() -> Bool { CGRequestScreenCaptureAccess() }

    private static func directorio(_ destino: DestinoCapturaMac) -> URL? {
        let fm = FileManager.default
        switch destino {
        case .escritorio: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .descargas: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .documentos: return fm.urls(for: .documentDirectory, in: .userDomainMask).first
        case .preguntar: return nil
        }
    }

    static func nombreSeguro(_ nombre: String?, tipo: TipoCapturaMac) -> String {
        let base: String
        if let nombre, !nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = nombre
        } else {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            base = tipo == .video ? "Grabación BtoDicta \(f.string(from: Date()))"
                                  : "Captura BtoDicta \(f.string(from: Date()))"
        }
        let limpio = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let esperada = tipo == .video ? "mov" : "png"
        let actual = (limpio as NSString).pathExtension.lowercased()
        if actual == esperada { return limpio }

        // El reloj del nombre automático termina, por ejemplo, en `17.50.49`:
        // `pathExtension` interpreta erróneamente ese `49` como extensión. Solo
        // sustituimos extensiones multimedia reales; cualquier otro punto forma
        // parte del nombre y recibe al final el `.mov`/`.png` obligatorio.
        let multimedia: Set<String> = [
            "mov", "mp4", "m4v", "avi", "mkv", "webm",
            "png", "jpg", "jpeg", "heic", "gif", "tif", "tiff",
        ]
        if multimedia.contains(actual) {
            return (limpio as NSString).deletingPathExtension + "." + esperada
        }
        return limpio + "." + esperada
    }

    private static func rutaUnica(_ inicial: URL) -> URL {
        guard FileManager.default.fileExists(atPath: inicial.path) else { return inicial }
        let dir = inicial.deletingLastPathComponent()
        let ext = inicial.pathExtension
        let base = inicial.deletingPathExtension().lastPathComponent
        for n in 2...9_999 {
            let nombre = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let u = dir.appendingPathComponent(nombre)
            if !FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return dir.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }

    private static func elegirRuta(_ solicitud: SolicitudCapturaMac) -> URL? {
        let nombre = nombreSeguro(solicitud.nombre, tipo: solicitud.tipo)
        if solicitud.destino != .preguntar, let dir = directorio(solicitud.destino) {
            return rutaUnica(dir.appendingPathComponent(nombre))
        }
        let panel = NSSavePanel()
        panel.title = solicitud.tipo == .video ? "Guardar grabación de pantalla" : "Guardar captura de pantalla"
        panel.nameFieldStringValue = nombre
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url.map(rutaUnica) : nil
    }

    private static func rectangulo(_ area: AreaCapturaMac) -> String? {
        guard [.superiorIzquierda, .superiorDerecha, .inferiorIzquierda, .inferiorDerecha].contains(area) else { return nil }
        // Sin sesión gráfica, consultar la pantalla dispara el aborto de
        // _RegisterApplication (crash de QA bajo el sandbox de Codex).
        guard SesionGUI.disponible else { return nil }
        let b = CGDisplayBounds(CGMainDisplayID())
        guard b.width >= 2, b.height >= 2 else { return nil }
        let w = floor(b.width / 2), h = floor(b.height / 2)
        let derecha = area == .superiorDerecha || area == .inferiorDerecha
        let inferior = area == .inferiorIzquierda || area == .inferiorDerecha
        let x = b.origin.x + (derecha ? w : 0)
        let y = b.origin.y + (inferior ? h : 0)
        return "\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"
    }

    static func argumentos(_ solicitud: SolicitudCapturaMac, archivo: URL?) -> [String] {
        var a: [String] = ["-x"]
        if solicitud.tipo == .imagen {
            a += ["-t", "png"]
            switch solicitud.area {
            case .seleccion: a += ["-i", "-s"]
            case .ventana: a += ["-i", "-w"]
            case .principal: a.append("-m")
            case .completa: break
            default:
                if let r = rectangulo(solicitud.area) { a += ["-R", r] }
                else { a += ["-i", "-s"] } // nunca convertir un cuarto fallido en pantalla completa
            }
            if solicitud.copiar, archivo == nil { a.append("-c") }
        } else {
            if solicitud.microfono { a.append("-g") }
            if solicitud.mostrarClics { a.append("-k") }
            if let segundos = solicitud.duracionAutomatica {
                a.append("-v")
                if solicitud.area == .principal { a.append("-m") }
                else if let r = rectangulo(solicitud.area) { a += ["-R", r] }
                a += ["-V", String(segundos)]
            } else if solicitud.controlContinuoBtoDicta {
                a.append("-v")
                if solicitud.area == .principal { a.append("-m") }
                else if let r = rectangulo(solicitud.area) { a += ["-R", r] }
            } else {
                // La barra nativa permite elegir pantalla/área y detener sin que
                // BtoDicta invente un control de grabación paralelo.
                a += ["-i", "-U", "-J", "video"]
            }
        }
        if let archivo { a.append(archivo.path) }
        return a
    }

    struct ResultadoAccionesPosteriores {
        let copiada: Bool
        let abierta: Bool
        let completo: Bool
    }

    /// Ejecuta y verifica las acciones pedidas DESPUÉS de que `screencapture`
    /// cerró el archivo. Se mantiene separada para poder probar la combinación
    /// guardar → copiar → abrir sin invocar el selector interactivo de macOS.
    static func accionesPosteriores(
        _ solicitud: SolicitudCapturaMac,
        archivo: URL,
        pasteboard: NSPasteboard = .general,
        copiador: ((URL, TipoCapturaMac) -> Bool)? = nil,
        abridor: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> ResultadoAccionesPosteriores {
        let pideCopia = solicitud.copiar || solicitud.compartirWhatsApp
        var copiada = false
        if pideCopia {
            if let copiador { copiada = copiador(archivo, solicitud.tipo) }
            else { copiada = copiar(archivo, tipo: solicitud.tipo, en: pasteboard) }
        }
        let abierta = solicitud.abrir ? abridor(archivo) : false
        let completo = (!pideCopia || copiada) && (!solicitud.abrir || abierta)
        return .init(copiada: copiada, abierta: abierta, completo: completo)
    }

    private static func copiar(_ url: URL, tipo: TipoCapturaMac,
                               en pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        if tipo == .imagen, let imagen = NSImage(contentsOf: url) {
            guard pasteboard.writeObjects([imagen]) else { return false }
            return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
                || pasteboard.data(forType: .tiff)?.isEmpty == false
        }
        guard pasteboard.writeObjects([url as NSURL]) else { return false }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
            || pasteboard.string(forType: .fileURL) != nil
    }

    private static func archivoValido(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = a[.size] as? NSNumber else { return false }
        return n.int64Value > 0
    }

    /// Un `.mov` puede tener bytes y aun así estar incompleto (sin átomo moov).
    /// La recuperación solo acepta partes que AVFoundation pueda reproducir.
    static func videoValido(_ url: URL) -> Bool {
        guard archivoValido(url) else { return false }
        let asset = AVURLAsset(url: url)
        let segundos = CMTimeGetSeconds(asset.duration)
        return asset.isPlayable && segundos.isFinite && segundos > 0
            && !asset.tracks(withMediaType: .video).isEmpty
    }

    private static func segundosPorParte() -> Int {
        if let prueba = ProcessInfo.processInfo.environment["BTODICTA_CAPTURE_SEGMENT_SECONDS"],
           let n = Int(prueba), n >= 1 { return min(60, n) }
        return Config.capturaSegmentoSegundos()
    }

    private static func prepararCarpetaRecuperacion(_ id: UUID) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: raizRecuperacion, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: raizRecuperacion.path)
        let dir = raizRecuperacion.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        return dir
    }

    private static func guardarManifiesto(_ sesion: SesionContinua, pid: Int32) {
        let obj: [String: Any] = [
            "version": 1,
            "destino": sesion.archivoFinal.path,
            "inicio": sesion.inicio.timeIntervalSince1970,
            "pid": Int(pid),
            "segundos_por_parte": sesion.segundosPorParte,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return }
        let url = sesion.carpetaRecuperacion.appendingPathComponent("manifest.json")
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.write("⚠️ grabación: no pude actualizar manifiesto: \(error.localizedDescription)")
        }
    }

    private static func rutaParte(_ sesion: SesionContinua) -> URL {
        sesion.indice += 1
        return sesion.carpetaRecuperacion.appendingPathComponent(
            String(format: "parte-%05d.mov", sesion.indice))
    }

    private static func argumentosParte(_ sesion: SesionContinua, archivo: URL) -> [String] {
        var a: [String] = ["-x"]
        if sesion.solicitud.microfono { a.append("-g") }
        if sesion.solicitud.mostrarClics { a.append("-k") }
        a.append("-v")
        if sesion.solicitud.area == .principal { a.append("-m") }
        else if let r = rectangulo(sesion.solicitud.area) { a += ["-R", r] }
        a.append(archivo.path)
        return a
    }

    private static func iniciarContinua(_ solicitud: SolicitudCapturaMac, archivo: URL,
                                        completion: @escaping (ResultadoCapturaMac) -> Void) {
        do {
            let id = UUID()
            let dir = try prepararCarpetaRecuperacion(id)
            let sesion = SesionContinua(id: id, solicitud: solicitud, archivoFinal: archivo,
                carpetaRecuperacion: dir, segundosPorParte: segundosPorParte(),
                completion: completion)
            lock.lock()
            guard sesionContinua == nil else {
                lock.unlock()
                completion(.init(ok: false,
                    mensaje: "Ya hay una grabación de pantalla en curso.",
                    archivo: nil, solicitud: solicitud))
                return
            }
            cancelada = false; sesionContinua = sesion
            lock.unlock()
            guardarManifiesto(sesion, pid: 0)
            AgenteLog.registrar("grabacion_continua_inicio", [
                "sesion": sesion.id.uuidString, "destino": archivo.path,
                "segmento_segundos": sesion.segundosPorParte,
            ])
            lanzarSiguienteParte(sesion)
        } catch {
            completion(.init(ok: false,
                mensaje: "No pude preparar la grabación continua: \(error.localizedDescription)",
                archivo: nil, solicitud: solicitud))
        }
    }

    private static func lanzarSiguienteParte(_ sesion: SesionContinua) {
        lock.lock()
        guard sesionContinua === sesion else { lock.unlock(); return }
        if sesion.deteniendo {
            lock.unlock(); finalizarContinua(sesion); return
        }
        let parte = rutaParte(sesion)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = argumentosParte(sesion, archivo: parte)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        sesion.proceso = p; proceso = p
        lock.unlock()
        p.terminationHandler = { terminado in
            DispatchQueue.main.async {
                terminarParte(sesion, procesoTerminado: terminado, archivo: parte)
            }
        }
        do {
            try p.run()
            guardarManifiesto(sesion, pid: p.processIdentifier)
            AgenteLog.registrar("grabacion_parte_inicio", [
                "sesion": sesion.id.uuidString, "parte": sesion.indice,
                "pid": Int(p.processIdentifier),
            ])
            let corte = DispatchWorkItem {
                lock.lock()
                guard sesionContinua === sesion, !sesion.deteniendo,
                      sesion.proceso === p, p.isRunning else {
                    lock.unlock(); return
                }
                lock.unlock()
                AgenteLog.registrar("grabacion_parte_corte", [
                    "sesion": sesion.id.uuidString, "parte": sesion.indice,
                ])
                _ = Darwin.kill(p.processIdentifier, SIGINT)
            }
            lock.lock(); sesion.corteProgramado = corte; lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(sesion.segundosPorParte),
                                           execute: corte)
        } catch {
            lock.lock()
            if proceso === p { proceso = nil }
            if sesion.proceso === p { sesion.proceso = nil }
            sesion.deteniendo = true
            sesion.avisoFallo = error.localizedDescription
            lock.unlock()
            finalizarContinua(sesion)
        }
    }

    private static func terminarParte(_ sesion: SesionContinua,
                                      procesoTerminado: Process, archivo: URL) {
        lock.lock()
        guard sesionContinua === sesion else { lock.unlock(); return }
        sesion.corteProgramado?.cancel(); sesion.corteProgramado = nil
        if proceso === procesoTerminado { proceso = nil }
        if sesion.proceso === procesoTerminado { sesion.proceso = nil }
        let deteniendo = sesion.deteniendo
        lock.unlock()

        let valida = videoValido(archivo)
        if valida && !sesion.partes.contains(archivo) { sesion.partes.append(archivo) }
        AgenteLog.registrar("grabacion_parte_fin", [
            "sesion": sesion.id.uuidString, "parte": sesion.indice,
            "ok": valida, "estado": Int(procesoTerminado.terminationStatus),
            "deteniendo": deteniendo,
        ])
        if deteniendo {
            finalizarContinua(sesion)
        } else if procesoTerminado.terminationStatus == 0, valida {
            lanzarSiguienteParte(sesion)
        } else {
            sesion.deteniendo = true
            sesion.avisoFallo = "una parte de la grabación no pudo cerrarse correctamente"
            finalizarContinua(sesion)
        }
    }

    private static func consolidar(_ partes: [URL], destino: URL,
                                   completion: @escaping (Bool, String?) -> Void) {
        let validas = partes.filter(videoValido)
        guard !validas.isEmpty else {
            completion(false, "no quedó ningún fragmento reproducible"); return
        }
        if validas.count == 1 {
            do {
                try FileManager.default.moveItem(at: validas[0], to: destino)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                       ofItemAtPath: destino.path)
                completion(true, nil)
            } catch { completion(false, error.localizedDescription) }
            return
        }

        let composicion = AVMutableComposition()
        guard let videoSalida = composicion.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(false, "no pude crear la pista de video"); return
        }
        let audioSalida = composicion.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        do {
            for (i, url) in validas.enumerated() {
                let asset = AVURLAsset(url: url)
                guard let video = asset.tracks(withMediaType: .video).first else { continue }
                let rango = CMTimeRange(start: .zero, duration: asset.duration)
                try videoSalida.insertTimeRange(rango, of: video, at: cursor)
                if i == 0 { videoSalida.preferredTransform = video.preferredTransform }
                if let audio = asset.tracks(withMediaType: .audio).first, let audioSalida {
                    try audioSalida.insertTimeRange(rango, of: audio, at: cursor)
                }
                cursor = CMTimeAdd(cursor, asset.duration)
            }
        } catch {
            completion(false, "no pude unir los fragmentos: \(error.localizedDescription)"); return
        }
        guard CMTimeGetSeconds(cursor) > 0,
              let exportador = AVAssetExportSession(asset: composicion,
                                                      presetName: AVAssetExportPresetPassthrough) else {
            completion(false, "la grabación consolidada quedó vacía"); return
        }
        exportador.outputURL = destino
        exportador.outputFileType = .mov
        exportador.shouldOptimizeForNetworkUse = false
        exportador.exportAsynchronously {
            if exportador.status == .completed, videoValido(destino) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                       ofItemAtPath: destino.path)
                completion(true, nil)
            } else {
                completion(false, exportador.error?.localizedDescription
                    ?? "AVFoundation no pudo cerrar el video")
            }
        }
    }

    private static func finalizarContinua(_ sesion: SesionContinua) {
        lock.lock()
        guard sesionContinua === sesion else { lock.unlock(); return }
        sesionContinua = nil
        if proceso === sesion.proceso { proceso = nil }
        sesion.proceso = nil
        let partes = sesion.partes
        lock.unlock()
        guardarManifiesto(sesion, pid: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            consolidar(partes, destino: sesion.archivoFinal) { ok, error in
                if ok { try? FileManager.default.removeItem(at: sesion.carpetaRecuperacion) }
                DispatchQueue.main.async {
                    guard ok else {
                        let respaldo = sesion.carpetaRecuperacion.path
                        AgenteLog.registrar("grabacion_continua_fin", [
                            "sesion": sesion.id.uuidString, "ok": false,
                            "error": error ?? "desconocido", "respaldo": respaldo,
                        ])
                        sesion.completion(.init(ok: false,
                            mensaje: "No pude consolidar el video. Conservé los fragmentos en \(respaldo). \(error ?? "")",
                            archivo: nil, solicitud: sesion.solicitud))
                        return
                    }
                    let posteriores = accionesPosteriores(sesion.solicitud,
                                                          archivo: sesion.archivoFinal)
                    var mensaje = "Guardé la grabación en \(sesion.solicitud.destino.nombre): «\(sesion.archivoFinal.lastPathComponent)»."
                    if posteriores.copiada { mensaje += " También quedó en el portapapeles." }
                    else if sesion.solicitud.copiar { mensaje += " No pude copiarla al portapapeles." }
                    if posteriores.abierta { mensaje += " También la abrí." }
                    else if sesion.solicitud.abrir { mensaje += " No pude abrirla automáticamente." }
                    if let aviso = sesion.avisoFallo { mensaje += " Aviso: \(aviso)." }
                    AgenteLog.registrar("grabacion_continua_fin", [
                        "sesion": sesion.id.uuidString, "ok": posteriores.completo,
                        "archivo": sesion.archivoFinal.path, "partes": partes.count,
                        "segundos": Int(Date().timeIntervalSince(sesion.inicio)),
                    ])
                    sesion.completion(.init(ok: posteriores.completo, mensaje: mensaje,
                                            archivo: sesion.archivoFinal,
                                            solicitud: sesion.solicitud))
                }
            }
        }
    }

    /// Tras un cierre inesperado, cada fragmento ya cerrado sigue siendo un MOV
    /// reproducible. Al próximo arranque se consolidan automáticamente; si el
    /// proceso de `screencapture` aún vive, se deja intacto y se reintentará.
    static func recuperarInterrumpidas(completion: @escaping ([URL]) -> Void) {
        lock.lock()
        guard !recuperando else { lock.unlock(); completion([]); return }
        recuperando = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let dirs = ((try? fm.contentsOfDirectory(at: raizRecuperacion,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { $0.hasDirectoryPath }

            func avanzar(_ indice: Int, _ recuperadas: [URL]) {
                guard indice < dirs.count else {
                    lock.lock(); recuperando = false; lock.unlock()
                    DispatchQueue.main.async { completion(recuperadas) }
                    return
                }
                let dir = dirs[indice]
                lock.lock()
                let esActual = sesionContinua?.carpetaRecuperacion == dir
                lock.unlock()
                guard !esActual,
                      let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let path = json["destino"] as? String, !path.isEmpty else {
                    avanzar(indice + 1, recuperadas); return
                }
                let pid = Int32((json["pid"] as? Int) ?? 0)
                if pid > 0, Darwin.kill(pid, 0) == 0 {
                    avanzar(indice + 1, recuperadas); return
                }
                let partes = ((try? fm.contentsOfDirectory(at: dir,
                    includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension.lowercased() == "mov" && videoValido($0) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                guard !partes.isEmpty else {
                    avanzar(indice + 1, recuperadas); return
                }
                let destino = rutaUnica(URL(fileURLWithPath: path))
                consolidar(partes, destino: destino) { ok, error in
                    var salida = recuperadas
                    if ok {
                        try? fm.removeItem(at: dir)
                        salida.append(destino)
                        AgenteLog.registrar("grabacion_recuperada", [
                            "ok": true, "archivo": destino.path, "partes": partes.count,
                        ])
                    } else {
                        AgenteLog.registrar("grabacion_recuperada", [
                            "ok": false, "carpeta": dir.path,
                            "error": error ?? "desconocido",
                        ])
                    }
                    avanzar(indice + 1, salida)
                }
            }
            avanzar(0, [])
        }
    }

    static func ejecutar(_ solicitud: SolicitudCapturaMac, simular: Bool = false,
                         archivoForzado: URL? = nil,
                         completion: @escaping (ResultadoCapturaMac) -> Void) {
        let comenzar = {
            let rutaVisible = solicitud.guardar || solicitud.tipo == .video
            let necesitaTemporal = !rutaVisible
                && (solicitud.copiar || solicitud.compartirWhatsApp || solicitud.abrir)
            let archivo: URL? = rutaVisible
                ? (archivoForzado ?? elegirRuta(solicitud))
                : (necesitaTemporal ? rutaUnica(FileManager.default.temporaryDirectory
                    .appendingPathComponent(nombreSeguro(solicitud.nombre, tipo: solicitud.tipo))) : nil)
            if rutaVisible, archivo == nil {
                completion(.init(ok: false, mensaje: "Cancelaste el selector; no hice la captura.",
                                 archivo: nil, solicitud: solicitud)); return
            }
            if simular {
                completion(.init(ok: true, mensaje: solicitud.tipo == .video
                    ? "Prepararía la grabación de pantalla."
                    : "Prepararía la captura de pantalla.", archivo: archivo, solicitud: solicitud)); return
            }
            guard permisoConcedido() || solicitarPermiso() else {
                completion(.init(ok: false,
                    mensaje: "Autoriza BtoDicta en Privacidad y seguridad → Grabación de pantalla y vuelve a intentarlo.",
                    archivo: nil, solicitud: solicitud)); return
            }

            if solicitud.controlContinuoBtoDicta, let archivo {
                AgenteLog.registrar("captura_solicitud", [
                    "tipo": solicitud.tipo.rawValue, "area": solicitud.area.rawValue,
                    "destino": solicitud.destino.rawValue, "archivo": archivo.lastPathComponent,
                    "guardar": true, "copiar": solicitud.copiar,
                    "abrir": solicitud.abrir, "whatsapp": solicitud.compartirWhatsApp,
                    "duracion_solicitada": 0, "detencion": solicitud.detencion,
                    "segmento_segundos": segundosPorParte(),
                ])
                iniciarContinua(solicitud, archivo: archivo, completion: completion)
                return
            }

            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = argumentos(solicitud, archivo: archivo)
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            AgenteLog.registrar("captura_solicitud", [
                "tipo": solicitud.tipo.rawValue, "area": solicitud.area.rawValue,
                "destino": solicitud.destino.rawValue, "archivo": archivo?.lastPathComponent ?? "",
                "guardar": solicitud.guardar, "copiar": solicitud.copiar,
                "abrir": solicitud.abrir, "whatsapp": solicitud.compartirWhatsApp,
                "duracion_solicitada": solicitud.duracion ?? 0,
                "detencion": solicitud.detencion,
            ])
            let archivoLog = archivo?.lastPathComponent ?? "ninguno"
            Log.write("  captura solicitada: area=\(solicitud.area.rawValue) guardar=\(solicitud.guardar) copiar=\(solicitud.copiar) abrir=\(solicitud.abrir) archivo=\(archivoLog)")
            lock.lock(); cancelada = false; proceso = p; lock.unlock()
            p.terminationHandler = { terminado in
                lock.lock(); let fueCancelada = cancelada; if proceso === terminado { proceso = nil }; lock.unlock()
                DispatchQueue.main.async {
                    let existe = archivo.map(archivoValido)
                        ?? (terminado.terminationStatus == 0)
                    guard terminado.terminationStatus == 0, existe, !fueCancelada else {
                        if let archivo { try? FileManager.default.removeItem(at: archivo) }
                        AgenteLog.registrar("captura_mac", [
                            "tipo": solicitud.tipo.rawValue, "area": solicitud.area.rawValue,
                            "ok": false, "cancelada_btodicta": fueCancelada,
                            "estado_proceso": Int(terminado.terminationStatus),
                            "detencion": solicitud.detencion,
                        ])
                        let falloManual = solicitud.tipo == .video
                            && solicitud.duracionAutomatica == nil && !fueCancelada
                        completion(.init(ok: false, mensaje: fueCancelada
                            ? "Cancelé la captura o grabación."
                            : (falloManual
                                ? "macOS cerró la grabación manual sin crear el video. En la barra nativa pulsa Grabar y, cuando acabes, usa el botón de detener de macOS."
                                : "macOS no completó la captura o la cancelaste."),
                            archivo: nil, solicitud: solicitud)); return
                    }
                    let posteriores = archivo.map {
                        accionesPosteriores(solicitud, archivo: $0)
                    } ?? .init(copiada: false, abierta: false,
                               completo: !solicitud.copiar && !solicitud.abrir)
                    let copiada = posteriores.copiada
                    let abierta = posteriores.abierta
                    let nombre = archivo?.lastPathComponent ?? ""
                    var mensaje: String
                    if solicitud.guardar || solicitud.tipo == .video {
                        mensaje = solicitud.tipo == .video
                            ? "Guardé la grabación en \(solicitud.destino.nombre): «\(nombre)»."
                            : "Guardé la captura en \(solicitud.destino.nombre): «\(nombre)»."
                        if copiada { mensaje += " También quedó en el portapapeles." }
                        else if solicitud.copiar { mensaje += " No pude copiarla al portapapeles." }
                        if abierta { mensaje += " También la abrí." }
                        else if solicitud.abrir { mensaje += " No pude abrirla automáticamente." }
                    } else if solicitud.abrir {
                        mensaje = abierta
                            ? (copiada ? "Abrí la captura temporal y también la copié al portapapeles."
                                      : "Abrí la captura temporal.")
                            : (copiada ? "Copié la captura al portapapeles, pero no pude abrirla."
                                      : "Completé la captura, pero no pude abrirla ni copiarla.")
                    } else {
                        mensaje = copiada ? "Copié la captura al portapapeles."
                                          : "Completé la captura de pantalla."
                    }
                    AgenteLog.registrar("captura_mac", [
                        "tipo": solicitud.tipo.rawValue, "area": solicitud.area.rawValue,
                        "archivo": archivo?.lastPathComponent ?? "", "copiada": copiada,
                        "copia_pedida": solicitud.copiar, "abierta": abierta,
                        "abrir_pedido": solicitud.abrir,
                        "whatsapp": solicitud.compartirWhatsApp,
                        "detencion": solicitud.detencion,
                        "captura_ok": true, "ok": posteriores.completo,
                    ])
                    let estadoCopia = solicitud.copiar ? (copiada ? "OK" : "FALLÓ") : "no pedido"
                    let estadoApertura = solicitud.abrir ? (abierta ? "OK" : "FALLÓ") : "no pedido"
                    Log.write("  captura terminada: archivo=\(nombre) copiar=\(estadoCopia) abrir=\(estadoApertura)")
                    let salida = necesitaTemporal ? nil : archivo
                    if necesitaTemporal, !solicitud.abrir, let archivo {
                        try? FileManager.default.removeItem(at: archivo)
                    }
                    completion(.init(ok: posteriores.completo, mensaje: mensaje,
                                     archivo: salida, solicitud: solicitud))
                }
            }
            do { try p.run() }
            catch {
                lock.lock(); if proceso === p { proceso = nil }; lock.unlock()
                completion(.init(ok: false, mensaje: "No pude iniciar la captura: \(error.localizedDescription)",
                                 archivo: nil, solicitud: solicitud))
            }
        }
        if Thread.isMainThread { comenzar() } else { DispatchQueue.main.async(execute: comenzar) }
    }
}
