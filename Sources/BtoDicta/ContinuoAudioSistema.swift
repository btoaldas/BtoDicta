import AVFoundation
import ScreenCaptureKit

// MARK: - Bitácora continua: audio del sistema
//
// Graba lo que SUENA en el equipo: la otra parte de una videollamada, un vídeo,
// una reunión. Es la mitad que el micrófono no puede capturar bien.
//
// Va por ScreenCaptureKit, que es la única vía en macOS moderno para tomar el
// audio de salida sin instalar un controlador de sonido virtual. Como exige un
// flujo con vídeo, se pide el mínimo posible y a la frecuencia más baja: lo que
// interesa es la pista de audio.
//
// Se excluye el audio de la propia aplicación a propósito: si no, la bitácora
// grabaría su propia voz sintetizada y se escucharía a sí misma.
//
// Pista SEPARADA de la del micrófono. En la línea de tiempo aparece marcada
// como «audio del sistema», para que luego se distinga quién dijo qué.

@available(macOS 13.0, *)
final class ContinuoAudioSistema: NSObject {

    static let shared = ContinuoAudioSistema()

    private let cola = DispatchQueue(label: "btodicta.continuo.sistema")
    private var flujo: SCStream?
    /// Cuántas veces seguidas se ha intentado recuperar tras un error. Se
    /// pone a cero en cuanto vuelve a entrar audio.
    private var reintentosTrasError = 0

    private var mano: FileHandle?
    private var rutaTrozo: URL?
    /// Quién tenía el foco al empezar el trozo. Se compara con quién lo tiene al
    /// cerrarlo: solo se descarta si coinciden, porque un cambio de aplicación a
    /// mitad significa que en esos 30 s pasó algo más que el juego.
    private var focoAlAbrir: (app: String?, pista: String?) = (nil, nil)
    private var inicioTrozo = Date()
    private var bytesTrozo = 0

    private var conversor: AVAudioConverter?
    private let formatoSalida = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16000, channels: 1, interleaved: true)!

    private(set) var activo = false
    private var montando = false
    private var avisadoDeFormato = false
    /// Sube en cada detener(): un montaje que termina después de un apagado es
    /// de una generación vieja y debe soltar el flujo, no publicarlo.
    private var generacion: UInt64 = 0

    /// Último nivel medido de la salida, legible desde cualquier hilo. Es la
    /// señal que usa el micrófono para su puerta anti-eco.
    private static let candadoNivel = NSLock()
    private static var _nivelActual: Double = 0
    static var nivelActual: Double {
        candadoNivel.lock(); defer { candadoNivel.unlock() }
        return _nivelActual
    }
    private static func publicarNivel(_ v: Double) {
        candadoNivel.lock(); _nivelActual = v; candadoNivel.unlock()
    }

    private override init() { super.init() }

    // MARK: Ciclo de vida

    func arrancar() {
        guard Config.continuoActivo(), Config.continuoSistemaActivo() else { return }
        cola.async { [weak self] in self?.arrancarEnCola() }
    }

    func detener() {
        cola.async { [weak self] in self?.detenerEnCola() }
    }

    func reconfigurar() {
        detener()
        cola.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.arrancarEnCola() }
    }

    private func arrancarEnCola() {
        guard !activo, !montando else { return }
        if Config.continuoSoloConCorriente(), !EnergiaMac.conCorriente() { return }
        montando = true
        let gen = generacion
        Task { [weak self] in
            await self?.montar(gen: gen)
            self?.cola.async { self?.montando = false }
        }
    }

    private func montar(gen: UInt64) async {
        do {
            let contenido = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: true)
            guard let pantalla = contenido.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? contenido.displays.first else { return }

            let conf = SCStreamConfiguration()
            conf.capturesAudio = true
            // Sin esto, la bitácora grabaría la voz sintetizada de la propia
            // aplicación y se escucharía a sí misma.
            conf.excludesCurrentProcessAudio = Config.continuoSistemaExcluirPropia()
            conf.sampleRate = 48_000
            conf.channelCount = 2
            // El vídeo es obligatorio en el flujo, pero aquí no interesa: se
            // pide el mínimo y a un fotograma cada varios segundos, para que no
            // cueste nada. Las capturas de pantalla las hace otro módulo.
            conf.width = 2
            conf.height = 2
            conf.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            conf.showsCursor = false

            // El audio de las aplicaciones excluidas NI SIQUIERA SE CAPTURA.
            //
            // Esto es lo que hace que el filtro funcione de verdad, y no solo
            // cuando la aplicación tiene el foco. Mirar quién tiene el foco es
            // un mal sustituto de saber quién está sonando, y se rompe en los
            // casos normales: música en un monitor mientras se trabaja en otro,
            // un juego minimizado que sigue sonando, un vídeo en una ventana de
            // atrás. El sistema sabe qué aplicación produce cada sonido; aquí se
            // le pide que deje fuera las que no interesan.
            //
            // La lista admite el nombre («Dota 2») o el identificador del
            // paquete: quien la escribe no tiene por qué saber cuál es cuál.
            let excluidas = FiltroBitacora.appsExcluidas()
            let apps = excluidas.isEmpty ? [] : contenido.applications.filter { a in
                excluidas.contains { e in
                    let ee = e.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                    let nombre = a.applicationName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                    return nombre.contains(ee) || a.bundleIdentifier.lowercased().contains(e.lowercased())
                }
            }
            if !apps.isEmpty {
                Log.log(.sistema, "bitácora: no grabo el sonido de \(apps.map { $0.applicationName }.joined(separator: ", "))")
            }
            let filtro = SCContentFilter(display: pantalla,
                                         excludingApplications: apps,
                                         exceptingWindows: [])
            let s = SCStream(filter: filtro, configuration: conf, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: cola)
            try await s.startCapture()

            cola.async { [weak self] in
                guard let self else { Task { try? await s.stopCapture() }; return }
                // Si mientras montábamos hubo un detener() (el usuario apagó el
                // ajuste, o una reconfiguración), este flujo es de una
                // generación vieja: se detiene aquí mismo en vez de quedar
                // huérfano capturando con el indicador encendido.
                guard self.generacion == gen, Config.continuoActivo(), Config.continuoSistemaActivo() else {
                    Task { try? await s.stopCapture() }
                    Log.log(.sistema, "bitácora: montaje del audio del sistema descartado (apagado durante el arranque)")
                    return
                }
                self.flujo = s
                self.activo = true
                Log.log(.sistema, "bitácora: audio del sistema en marcha")
            }
        } catch {
            Log.log(.sistema, "bitácora: no pude capturar el audio del sistema — \(error.localizedDescription)")
        }
    }

    private func detenerEnCola() {
        generacion &+= 1
        Self.publicarNivel(0)
        guard let s = flujo else { cerrarTrozo(); return }
        flujo = nil
        activo = false
        Task { try? await s.stopCapture() }
        cerrarTrozo()
        conversor = nil
    }

    // MARK: Escritura

    fileprivate func recibir(_ muestra: CMSampleBuffer) {
        guard activo, Config.continuoSistemaActivo() else { return }
        guard !ModoRapido.pausaVigente() else { return }   // pausa del usuario (spec 010)
        guard let pcm = convertir(muestra) else { return }

        let n = nivel(pcm)
        Self.publicarNivel(n)
        // Puerta de silencio: casi todo el día el equipo no suena, y guardar
        // ceros llenaría el disco sin aportar nada.
        if Config.continuoSistemaSoloConSonido() {
            guard n >= Config.continuoSistemaUmbral() else { return }
        }
        escribir(pcm)
    }

    /// De lo que entrega ScreenCaptureKit (48 kHz estéreo en coma flotante) al
    /// mismo formato que usa el resto de la aplicación: 16 kHz mono, 16 bits.
    private func convertir(_ muestra: CMSampleBuffer) -> Data? {
        guard let desc = CMSampleBufferGetFormatDescription(muestra),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee,
              let entrada = AVAudioFormat(streamDescription: [asbd].withUnsafeBufferPointer { $0.baseAddress! })
        else { return nil }

        if conversor == nil || conversor?.inputFormat != entrada {
            conversor = AVAudioConverter(from: entrada, to: formatoSalida)
            if entrada.channelCount > 1 { conversor?.channelMap = [0] }
            if !avisadoDeFormato {
                avisadoDeFormato = true
                Log.log(.sistema, "bitácora: audio del sistema a \(Int(entrada.sampleRate)) Hz, \(entrada.channelCount) can")
            }
        }
        guard let conv = conversor else { return nil }

        let marcos = AVAudioFrameCount(CMSampleBufferGetNumSamples(muestra))
        guard marcos > 0,
              let origen = AVAudioPCMBuffer(pcmFormat: entrada, frameCapacity: marcos) else { return nil }
        origen.frameLength = marcos
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
                muestra, at: 0, frameCount: Int32(marcos),
                into: origen.mutableAudioBufferList) == noErr else { return nil }

        let razon = formatoSalida.sampleRate / entrada.sampleRate
        let capacidad = AVAudioFrameCount(Double(marcos) * razon) + 64
        guard let salida = AVAudioPCMBuffer(pcmFormat: formatoSalida, frameCapacity: capacidad) else { return nil }
        var servido = false
        conv.convert(to: salida, error: nil) { _, estado in
            if servido { estado.pointee = .noDataNow; return nil }
            servido = true
            estado.pointee = .haveData
            return origen
        }
        guard salida.frameLength > 0, let ch = salida.int16ChannelData else { return nil }
        return Data(bytes: ch[0], count: Int(salida.frameLength) * 2)
    }

    private func nivel(_ pcm: Data) -> Double {
        let n = pcm.count / 2
        guard n > 0 else { return 0 }
        return pcm.withUnsafeBytes { bytes -> Double in
            guard let base = bytes.bindMemory(to: Int16.self).baseAddress else { return 0 }
            var suma = 0.0
            for i in 0..<n {
                let v = Double(base[i]) / 32768.0
                suma += v * v
            }
            return (suma / Double(n)).squareRoot()
        }
    }

    private func escribir(_ datos: Data) {
        if mano == nil { abrirTrozo() }
        // write(contentsOf:) LANZA en vez de abortar el proceso: con el disco
        // lleno, la grabación continua no puede llevarse la app (y el dictado)
        // por delante. Se cierra el trozo y se deja constancia.
        do {
            try mano?.write(contentsOf: datos)
            bytesTrozo += datos.count
        } catch {
            Log.log(.sistema, "bitácora: no pude escribir audio (\(error.localizedDescription)) — ¿disco lleno? Cierro el trozo")
            cerrarTrozo()
            return
        }
        if Date().timeIntervalSince(inicioTrozo) >= Double(Config.continuoAudioSegmentoSegundos()) {
            cerrarTrozo()
            abrirTrozo()
        }
    }

    private func abrirTrozo() {
        if mano != nil { cerrarTrozo() }
        let ahora = Date()
        let carpeta = ContinuoAudio.carpetaDelDia(ahora, sub: "sistema")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appendingPathComponent(ContinuoAudio.sello(ahora) + ".pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        mano = try? FileHandle(forWritingTo: url)
        rutaTrozo = url
        inicioTrozo = ahora
        focoAlAbrir = FiltroBitacora.contextoDelFrente()
        bytesTrozo = 0
    }

    private func cerrarTrozo() {
        try? mano?.close()
        mano = nil
        guard let url = rutaTrozo else { return }
        rutaTrozo = nil
        let inicio = inicioTrozo
        let bytes = bytesTrozo
        guard bytes > 16_000 else { try? FileManager.default.removeItem(at: url); return }
        let duracion = Double(bytes) / 32_000.0

        // ¿Esto es trabajo o es una partida?
        //
        // El audio del sistema es TODO lo que suena por los altavoces, y ahí cabe
        // el anunciador de un juego o el diálogo de una película, que luego
        // aparecen en el resumen del día como si fueran actividad laboral.
        //
        // Quien lo distingue es el foco: se mira al abrir y al cerrar el trozo, y
        // solo se aparta si AMBAS coinciden en una aplicación o título excluido.
        // Si cambiaste de aplicación a mitad, en esos treinta segundos pasó algo
        // más y el trozo se conserva — ante la duda, se guarda.
        if FiltroBitacora.hayReglas {
            let ahoraFoco = FiltroBitacora.contextoDelFrente()
            let alAbrir = FiltroBitacora.decidirConNavegador(app: focoAlAbrir.app, pista: focoAlAbrir.pista)
            let alCerrar = FiltroBitacora.decidirConNavegador(app: ahoraFoco.app, pista: ahoraFoco.pista)
            if case .fuera(let motivo) = alAbrir, case .fuera = alCerrar {
                // No se borra: se aparta a la papelera de la bitácora, donde se
                // puede recuperar unos días. Lo que hoy no interesa puede
                // interesar mañana, y el coste de guardarlo unos días es bajo.
                ContinuoLote.apartarPorFiltro(url, motivo: motivo)
                return
            }
        }

        // `origen: "sistema"` es lo que hace que en la línea de tiempo aparezca
        // como «audio del sistema» y no se confunda con lo que dijo la persona.
        ContinuoIndice.shared.registrarAudio(ruta: url, instante: inicio,
                                             duracion: duracion, origen: "sistema")
    }
}

// MARK: - Recepción del flujo

@available(macOS 13.0, *)
extension ContinuoAudioSistema: SCStreamOutput, SCStreamDelegate {

    func stream(_ stream: SCStream, didOutputSampleBuffer muestra: CMSampleBuffer,
                of tipo: SCStreamOutputType) {
        // Entra audio: la recuperación funcionó, el contador vuelve a cero.
        if reintentosTrasError != 0 { reintentosTrasError = 0 }
        guard tipo == .audio, CMSampleBufferIsValid(muestra) else { return }
        recibir(muestra)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.log(.sistema, "bitácora: el audio del sistema se detuvo — \(error.localizedDescription)")
        cola.async { [weak self] in
            guard let self else { return }
            self.activo = false
            self.flujo = nil
            self.cerrarTrozo()
            // Y SE VUELVE A MONTAR. Antes se quedaba muerto hasta que alguien
            // tocara los ajustes: el usuario no se entera de que dejó de grabar
            // el audio del sistema, porque nada se lo dice. Lo que lo tumba
            // suele ser pasajero —cambiar de salida de audio, una pantalla que
            // se desconecta—, así que reintentar es lo razonable.
            //
            // Con espera creciente y tope, para no insistir en balde si el
            // motivo es permanente.
            self.reintentosTrasError += 1
            guard self.reintentosTrasError <= 5 else {
                Log.log(.sistema, "bitácora: el audio del sistema no se recupera tras 5 intentos — queda apagado hasta reconfigurar")
                return
            }
            let espera = Double(self.reintentosTrasError) * 3
            Log.log(.sistema, "bitácora: reintento el audio del sistema en \(Int(espera)) s (intento \(self.reintentosTrasError) de 5)")
            self.cola.asyncAfter(deadline: .now() + espera) { [weak self] in
                guard let self, Config.continuoActivo() else { return }
                self.arrancar()
            }
        }
    }
}
