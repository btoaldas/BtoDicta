import AppKit
import CoreImage
import ScreenCaptureKit
import UniformTypeIdentifiers

// MARK: - Bitácora continua: pantalla
//
// Capturas periódicas al intervalo que elija el usuario (5 s … 1 h).
//
// Se usa `SCScreenshotManager` en vez de un `SCStream` permanente: para un
// intervalo de 30 s o de un minuto, mantener un flujo vivo todo el día solo
// gastaría memoria y CPU. Aquí se pide una imagen, se decide si aporta algo y
// se suelta.
//
// Nada se guarda si la pantalla está bloqueada o dormida, ni si la imagen es
// prácticamente idéntica a la anterior. Cada N minutos se fuerza una aunque no
// haya cambios, para que la línea de tiempo no quede en blanco.

@available(macOS 14.0, *)
final class ContinuoPantalla {

    static let shared = ContinuoPantalla()

    private var reloj: Timer?
    private var capturando = false
    private var inicioIntento = Date.distantPast
    private var capturaLentaAvisada = false
    /// Por monitor: comparar la huella de una pantalla contra la de OTRA haría
    /// que la deduplicación no funcionara nunca (o siempre) con varias.
    /// CONFINADOS a la cola `escribir`: los muta el Task de captura (executor
    /// global) y los vacía `detener()` desde main; además el rescate de 30 s
    /// de `tic()` puede solapar dos capturas vivas. Mutar un Dictionary desde
    /// dos hilos corrompe su almacenamiento CoW y tumba la app.
    private var huellaPrevia: [Int: [UInt8]] = [:]
    private var ultimaEscritura: [Int: Date] = [:]
    private let contexto = CIContext(options: [.useSoftwareRenderer: false])
    private let escribir = DispatchQueue(label: "btodicta.continuo.pantalla", qos: .utility)

    private(set) var activo = false

    private init() {}

    // MARK: Ciclo de vida

    func arrancar() {
        guard Config.continuoActivo(), Config.continuoPantallaActiva() else { return }
        guard !activo else { return }
        let intervalo = Double(Config.continuoPantallaIntervaloSegundos())
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloj?.invalidate()
            self.reloj = Timer.scheduledTimer(withTimeInterval: intervalo, repeats: true) { [weak self] _ in
                self?.tic()
            }
            self.activo = true
            Log.log(.sistema, "bitácora: pantalla cada \(Int(intervalo)) s")
        }
    }

    func detener() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloj?.invalidate()
            self.reloj = nil
            self.activo = false
            // En su cola, no aquí: una captura en vuelo puede estar mutando el
            // diccionario en este mismo instante.
            self.escribir.async { [weak self] in self?.huellaPrevia = [:] }
        }
    }

    /// Aplica un cambio de intervalo sin reiniciar la app.
    func reconfigurar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arrancar() }
    }

    // MARK: Captura

    private func tic() {
        // `capturando` no puede quedarse pegado: si `SCShareableContent` se
        // queda esperando (permiso de grabación de pantalla sin conceder tras
        // reinstalar el binario), sin este rescate el módulo enmudece para
        // siempre y sin un solo error en el registro.
        if capturando {
            let espera = Date().timeIntervalSince(inicioIntento)
            if espera > 90 {
                // Con el equipo cargado (una tanda transcribiendo en local) una
                // captura puede tardar más que el intervalo sin estar colgada:
                // por eso el umbral es holgado y el mensaje distingue ese caso
                // del permiso pendiente, que sí deja a SCShareableContent mudo.
                let causa = ContinuoLote.ocupado
                    ? "tanda en curso: el equipo está cargado"
                    : "¿permiso de grabación de pantalla pendiente?"
                Log.log(.sistema, "bitácora: la captura anterior lleva \(Int(espera)) s sin terminar (\(causa)) — reintento")
                capturando = false
            } else {
                if espera > 30, !capturaLentaAvisada {
                    capturaLentaAvisada = true
                    Log.debug("bitácora: captura lenta (\(Int(espera)) s), espero a que termine")
                }
                return
            }
        }
        guard Config.continuoActivo(), Config.continuoPantallaActiva() else { return }
        if Config.continuoPantallaPausarEnTanda(), ContinuoLote.ocupado {
            Log.debug("bitácora: tanda en curso y el ajuste pide pausar la pantalla, no capturo")
            return
        }
        if Config.continuoPantallaPausarBloqueada(), Self.pantallaNoDisponible() {
            Log.debug("bitácora: pantalla bloqueada o dormida, no capturo")
            return
        }
        if Config.continuoSoloConCorriente(), !EnergiaMac.conCorriente() {
            Log.debug("bitácora: con batería y el ajuste pide corriente, no capturo")
            return
        }
        capturando = true
        inicioIntento = Date()
        capturaLentaAvisada = false
        Task { [weak self] in
            await self?.capturar()
            self?.capturando = false
        }
    }

    private func capturar() async {
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: true)
            let elegidos = Self.monitoresElegidos(de: contenido)
            guard !elegidos.isEmpty else { return }

            let excluidas = Config.continuoPantallaAppsExcluidas()
            let apps = contenido.applications.filter { excluidas.contains($0.bundleIdentifier) }

            for pantalla in elegidos {
                // El fallo de UNA pantalla no puede abortar las demás del
                // ciclo: con monitores que entran y salen en caliente, la que
                // se desconectó a mitad de la enumeración lanzaría y las
                // siguientes perderían su captura sin motivo.
                do {
                    let filtro = SCContentFilter(display: pantalla,
                                                 excludingApplications: apps,
                                                 exceptingWindows: [])
                    let conf = SCStreamConfiguration()
                    let escala = Config.continuoPantallaEscala()
                    // `pointPixelScale` da los píxeles reales del panel: sin él,
                    // en una Retina se captura a media resolución y el texto
                    // queda ilegible para un OCR posterior.
                    let anchoReal = Double(pantalla.width) * Double(filtro.pointPixelScale)
                    let altoReal = Double(pantalla.height) * Double(filtro.pointPixelScale)
                    conf.width = max(2, Int(anchoReal * escala) & ~1)
                    conf.height = max(2, Int(altoReal * escala) & ~1)
                    conf.showsCursor = false
                    conf.captureResolution = .best

                    let imagen = try await SCScreenshotManager.captureImage(contentFilter: filtro,
                                                                           configuration: conf)
                    procesar(imagen, monitor: Int(pantalla.displayID))
                } catch {
                    Log.log(.sistema, "bitácora: la pantalla \(pantalla.displayID) no se pudo capturar (\(error.localizedDescription)) — sigo con las demás")
                }
            }
        } catch {
            Log.log(.sistema, "bitácora: captura de pantalla falló (\(error.localizedDescription))")
        }
    }

    private func procesar(_ imagen: CGImage, monitor: Int) {
        let ahora = Date()
        // Todo dentro de `escribir`: es la única dueña de huellaPrevia y
        // ultimaEscritura, así dos capturas solapadas o un detener() en main
        // nunca los tocan a la vez.
        escribir.async { [weak self] in
            guard let self else { return }
            let forzarMin = Config.continuoPantallaForzarMinutos()
            let ultima = self.ultimaEscritura[monitor] ?? .distantPast
            let forzado = forzarMin > 0 && ahora.timeIntervalSince(ultima) >= Double(forzarMin) * 60

            // La deduplicación se salta cuando toca fotograma forzado: primero se
            // decide si es obligatorio guardar, y solo si no lo es se compara.
            if !forzado, Config.continuoPantallaDeduplicar() {
                let huella = Self.huella(de: imagen)
                if let previa = self.huellaPrevia[monitor], Self.diferencia(previa, huella) < Config.continuoPantallaUmbralCambio() {
                    return
                }
                self.huellaPrevia[monitor] = huella
            } else {
                self.huellaPrevia[monitor] = Self.huella(de: imagen)
            }

            self.ultimaEscritura[monitor] = ahora
            let frente = NSWorkspace.shared.frontmostApplication
            let app = frente?.localizedName
            let ventana = Self.tituloVentanaAlFrente()

            // Segunda capa, sobre la exclusión que ya hace el sistema por
            // aplicación: un navegador se llama igual esté donde esté, y lo que
            // distingue la pestaña del banco es su TÍTULO. Se comprueba antes de
            // escribir nada, porque una captura que no debe existir no debe
            // existir tampoco un instante en disco.
            if let motivo = Self.motivoParaNoCapturar(app: app, ventana: ventana) {
                // Se anota QUE se omitió, nunca QUÉ se vio: decir el título sería
                // filtrar por el registro justo lo que se está protegiendo.
                Self.avisarOmision(motivo)
                return
            }
            let visibles = Config.continuoPantallaAppsVisibles()
                ? Self.appsALaVista(excluyendo: app)
                : []

            guard let url = self.guardar(imagen, instante: ahora, monitor: monitor) else { return }
            ContinuoIndice.shared.registrarPantalla(ruta: url, instante: ahora,
                                                    app: app, ventana: ventana,
                                                    monitor: monitor, visibles: visibles)
        }
    }

    private func guardar(_ imagen: CGImage, instante: Date, monitor: Int) -> URL? {
        let carpeta = ContinuoAudio.carpetaDelDia(instante, sub: "pantalla")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

        let formato = Config.continuoPantallaFormato()
        let extensiones = ["jpeg": "jpg", "heic": "heic", "png": "png"]
        let tipos: [String: UTType] = ["jpeg": .jpeg, "heic": .heic, "png": .png]
        let ext = extensiones[formato] ?? "jpg"
        // El identificador del monitor va en el nombre: tres pantallas en el
        // mismo segundo no pueden pisarse el archivo.
        let url = carpeta.appendingPathComponent(ContinuoAudio.sello(instante) + "-m\(monitor)." + ext)

        guard let destino = CGImageDestinationCreateWithURL(url as CFURL,
                                                            (tipos[formato] ?? .jpeg).identifier as CFString,
                                                            1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if formato != "png" {
            props[kCGImageDestinationLossyCompressionQuality] = Config.continuoPantallaCalidad()
        }
        CGImageDestinationAddImage(destino, imagen, props as CFDictionary)
        guard CGImageDestinationFinalize(destino) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: Deduplicación

    /// Miniatura de 16×16 en gris. Comparar dos de estas cuesta microsegundos y
    /// basta para saber si la pantalla cambió de verdad.
    /// Por qué no se guarda esta captura, o `nil` si sí se puede.
    ///
    /// La exclusión POR APLICACIÓN la hace el sistema al componer la imagen
    /// (`SCContentFilter`), así que aquí solo se mira el título de la ventana,
    /// que es lo que el sistema no puede filtrar.
    static func motivoParaNoCapturar(app: String?, ventana: String?) -> String? {
        // Lo que ya había: títulos que el usuario protege (banca, contraseñas).
        let titulo = (ventana ?? "").lowercased()
        if !titulo.isEmpty {
            for palabra in Config.continuoPantallaTitulosExcluidos()
            where !palabra.isEmpty && titulo.contains(palabra.lowercased()) {
                return "título excluido"
            }
        }
        // Y lo que no interesa para la bitácora: un juego, un vídeo, una red
        // social. Mismo filtro que gobierna el audio del sistema, para que una
        // regla escrita una vez valga para las dos pistas — no tiene sentido
        // excluir el sonido de un juego y seguir guardando sus capturas.
        if case .fuera(let motivo) = FiltroBitacora.decidir(app: app, ventana: ventana) {
            return motivo
        }
        return nil
    }

    /// Una sola línea cada diez minutos: si no, una tarde con el gestor de
    /// contraseñas abierto llena el registro de avisos idénticos.
    private static var ultimoAvisoOmision = Date.distantPast
    private static func avisarOmision(_ motivo: String) {
        guard Date().timeIntervalSince(ultimoAvisoOmision) > 600 else { return }
        ultimoAvisoOmision = Date()
        Log.log(.sistema, "bitácora: no capturo la pantalla (\(motivo)) — es una de las que decidiste proteger")
    }

    private static func huella(de imagen: CGImage) -> [UInt8] {
        let lado = 16
        var pixeles = [UInt8](repeating: 0, count: lado * lado)
        guard let espacio = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(data: &pixeles, width: lado, height: lado,
                                  bitsPerComponent: 8, bytesPerRow: lado,
                                  space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return pixeles }
        ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: lado, height: lado))
        return pixeles
    }

    /// Diferencia media normalizada entre dos huellas (0 = idénticas).
    private static func diferencia(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var suma = 0
        for i in 0..<a.count { suma += abs(Int(a[i]) - Int(b[i])) }
        return Double(suma) / Double(a.count) / 255.0
    }

    // MARK: Estado de la pantalla

    /// `true` si está bloqueada, dormida o con el salvapantallas puesto: no hay
    /// nada que valga la pena guardar.
    static func pantallaNoDisponible() -> Bool {
        if let info = CGSessionCopyCurrentDictionary() as? [String: Any],
           let bloqueada = info["CGSSessionScreenIsLocked"] as? Int, bloqueada == 1 {
            return true
        }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    private static func monitoresElegidos(de contenido: SCShareableContent) -> [SCDisplay] {
        // Con «todas» activo (el valor de fábrica), cada pantalla conectada se
        // captura: quien enchufa tres monitores espera ver los tres en la
        // bitácora, no solo el principal.
        if Config.continuoPantallaTodosMonitores() {
            return contenido.displays
        }
        let pedidos = Config.continuoPantallaMonitores()
        if pedidos.isEmpty {
            if let principal = contenido.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
                return [principal]
            }
            return Array(contenido.displays.prefix(1))
        }
        return contenido.displays.filter { pedidos.contains(Int($0.displayID)) }
    }

    /// Aplicaciones con ventanas a la vista, de delante hacia atrás, sin la
    /// activa (que ya va en su propio campo). Es el «qué más había abierto»
    /// que da contexto a la captura.
    private static func appsALaVista(excluyendo activa: String?) -> [String] {
        guard let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return [] }
        var vistas: [String] = []
        for v in lista {
            // Solo la capa normal de ventanas: fuera menús, Dock y adornos.
            guard let capa = v[kCGWindowLayer as String] as? Int, capa == 0,
                  let nombre = v[kCGWindowOwnerName as String] as? String,
                  !nombre.isEmpty, nombre != activa,
                  !vistas.contains(nombre) else { continue }
            vistas.append(nombre)
            if vistas.count >= 6 { break }   // el contexto útil se agota pronto
        }
        return vistas
    }

    /// Título de la ventana al frente, si el permiso de accesibilidad lo permite.
    /// Es contexto útil para buscar después; su ausencia no es un fallo.
    static func tituloVentanaAlFrente() -> String? {
        guard let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] else { return nil }
        let pidFrente = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for v in lista {
            guard let pid = v[kCGWindowOwnerPID as String] as? pid_t, pid == pidFrente,
                  let nombre = v[kCGWindowName as String] as? String, !nombre.isEmpty else { continue }
            return nombre
        }
        return nil
    }
}
