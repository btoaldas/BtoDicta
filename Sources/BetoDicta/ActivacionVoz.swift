import AppKit
import AVFoundation
import Foundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Activación manos libres (frases configuradas por el usuario)
//
// Siri usa un detector privilegiado de muy bajo consumo que macOS no expone a
// aplicaciones de terceros. BetoDicta usa únicamente APIs públicas: un
// DictationTranscriber local escucha las frases que el usuario configuró y, al
// reconocer una al inicio de un segmento, suelta por completo el micrófono antes
// de arrancar el Recorder normal. Nunca sustituye la cascada STT elegida.
//
// Privacidad: antes de la frase solo existe un búfer circular pequeño EN RAM.
// No se escribe audio/texto, no se registra el ambiente y no se llama a la red.

extension Notification.Name {
    static let betoActivacionVozConfiguracionCambio =
        Notification.Name("BetoDictaActivacionVozConfiguracionCambio")
    static let betoActivacionVozEstadoCambio =
        Notification.Name("BetoDictaActivacionVozEstadoCambio")
}

final class ActivacionVoz: @unchecked Sendable {
    static let shared = ActivacionVoz()

    struct Despertar {
        enum Forma: String {
            /// Compatibilidad avanzada: frase y orden dentro de la misma toma.
            case ordenCorrida = "orden_corrida"
            /// Dijo únicamente la frase y pausó: acusar recibo y abrir otro turno.
            case turnoNuevo = "turno_nuevo"
        }
        enum Origen: String {
            case reposoAppleLocal = "reposo_apple_local"
            /// BetoDicta ya poseía el micrófono y reconoció localmente la frase
            /// exacta «Oye Siri» + nombre configurado. No se atribuye a Siri.
            case pasarelaSiriLocal = "pasarela_siri_local"
            case atajoSiri = "atajo_siri"
        }

        let id: UUID
        let frase: String
        /// PCM16 mono 16 kHz. Incluye la frase y, si el usuario habló seguido,
        /// el comienzo de su orden; el Recorder lo antepone al dictado real.
        let audioPrevio: Data
        let fecha: Date
        let forma: Forma
        let origen: Origen

        var soloFrase: Bool { forma == .turnoNuevo }
    }

    enum Estado: Equatable {
        case desactivado
        case preparando
        case escuchando
        case pausado
        case sinFrases
        case sinPermiso
        case noDisponible
        case error(String)

        var descripcion: String {
            switch self {
            case .desactivado: return "Desactivado"
            case .preparando: return "Preparando Apple Speech local…"
            case .escuchando: return "Escuchando localmente la frase de presencia"
            case .pausado: return "En pausa mientras BetoDicta usa el micrófono o habla"
            case .sinFrases: return "Agrega al menos una frase segura de dos palabras"
            case .sinPermiso: return "Activa el acceso al micrófono para BetoDicta en Privacidad y seguridad"
            case .noDisponible: return "Requiere macOS 26 y el modelo local de Apple Speech"
            case .error(let s): return "No se pudo escuchar: \(s)"
            }
        }

        var activo: Bool {
            if case .escuchando = self { return true }
            return false
        }
    }

    static var disponible: Bool { AppleSpeechSTT.disponible }

    /// La primera consulta de `inputNode` debe ocurrir en main en macOS 26.
    /// El contenedor permite llevar después ambos objetos a la cola serial de
    /// audio sin volver a cruzar sincrónicamente main↔cola.
    private final class RecursosAudio: @unchecked Sendable {
        let engine: AVAudioEngine
        let input: AVAudioInputNode

        @MainActor init() {
            engine = AVAudioEngine()
            input = engine.inputNode
        }
    }

    private let cola = DispatchQueue(label: "betodicta.activacion-voz", qos: .utility)
    private let candadoEstado = NSLock()
    private var estadoGuardado: Estado = .desactivado

    var estado: Estado {
        candadoEstado.lock(); defer { candadoEstado.unlock() }
        return estadoGuardado
    }

    /// Incluye `.preparando`: una pulsación fn debe cancelar también un arranque
    /// asíncrono para que nunca aparezcan dos taps sobre el mismo micrófono.
    var ocupaMicrofono: Bool {
        switch estado {
        case .preparando, .escuchando: return true
        default: return false
        }
    }

    private var engine: AVAudioEngine?
    /// `AVAudioEngine.inputNode` puede bloquear al inicializarse por primera vez
    /// fuera del hilo principal (reproducido en macOS 26). Se obtiene una vez en
    /// main y se conserva para que cierre/arranque no vuelvan a pedir la propiedad.
    private var inputNode: AVAudioInputNode?
    private var inputConverter: AVAudioConverter?
    private var speechConverter: AVAudioConverter?
    private var formatoSpeech: AVAudioFormat?
    private let formatoPCM = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: true)!
    private var anillo = Data()
    private var maxAnilloBytes = 128_000
    private var bytesAudioTotales = 0
    /// Última voz real observada en PCM. DictationTranscriber progresivo puede
    /// mantener un resultado como parcial aun tras varios segundos; esta señal
    /// acústica confirma la pausa sin depender de `isFinal`.
    private var ultimaVozAudio = Date.distantPast
    private var generacion = UUID()
    private var preparando = false
    private var detectado = false
    private var candidatoAcuse: (token: UUID, inv: PerfilAgente.Invocacion,
                                 inicioSegmento: Double)?
    private var habilitadoAnterior = false
    private var solicitandoPermiso = false
    private var proximoIntento = Date.distantPast
    private var activadores: [String] = []
    private var alDespertar: ((Despertar) -> Void)?
    private var tarea: Task<Void, Never>?
    private var lector: Task<Void, Never>?

    #if canImport(Speech)
    // Se guardan como Any para que la clase siga compilando con deployment 14.
    private var _continuation: Any?
    private var _analyzer: Any?
    #endif

    private init() {}

    private static var debug: Bool {
        ProcessInfo.processInfo.environment["BETODICTA_WAKELIVETEST"] == "1"
    }
    private static func dbg(_ texto: String) {
        guard debug else { return }
        print("[WAKE] \(texto)"); fflush(stdout)
    }

    /// Concilia el deseo del usuario con el estado real de la app. Es idempotente
    /// y barato; AppDelegate lo llama al cambiar ajustes y con un reloj liviano.
    func reconciliar(habilitado: Bool, puedeEscuchar: Bool,
                     activadores nuevos: [String],
                     alDespertar: @escaping (Despertar) -> Void) {
        let seguros = FrasesConfigurables.activadoresSeguros(nuevos)
        cola.async { [weak self] in
            guard let self else { return }
            self.alDespertar = alDespertar
            if habilitado != self.habilitadoAnterior {
                self.proximoIntento = .distantPast
                self.habilitadoAnterior = habilitado
            }
            let cambiaron = seguros.map(PerfilAgente.normalizar)
                != self.activadores.map(PerfilAgente.normalizar)
            if cambiaron { self.proximoIntento = .distantPast }
            self.activadores = seguros
            self.maxAnilloBytes = Int(Config.agenteActivacionPrebuffer() * 32_000)

            guard habilitado else {
                self.cerrarEnCola()
                self.publicar(.desactivado)
                return
            }
            guard Self.disponible else {
                self.cerrarEnCola()
                self.publicar(.noDisponible)
                return
            }
            guard !seguros.isEmpty else {
                self.cerrarEnCola()
                self.publicar(.sinFrases)
                return
            }
            guard puedeEscuchar else {
                self.cerrarEnCola()
                self.publicar(.pausado)
                return
            }
            // El listener no puede quedarse indefinidamente en "Preparando" si
            // TCC aún no respondió. La solicitud se hace una sola vez y el flujo
            // se reanuda únicamente tras recibir la decisión de macOS.
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.solicitandoPermiso = false
            case .notDetermined:
                self.cerrarEnCola()
                self.publicar(.preparando)
                guard !self.solicitandoPermiso else { return }
                self.solicitandoPermiso = true
                DispatchQueue.main.async {
                    AVCaptureDevice.requestAccess(for: .audio) { [weak self] permitido in
                        self?.cola.async { [weak self] in
                            guard let self else { return }
                            self.solicitandoPermiso = false
                            self.proximoIntento = .distantPast
                            self.publicar(permitido ? .pausado : .sinPermiso)
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .betoActivacionVozConfiguracionCambio,
                                    object: nil)
                            }
                        }
                    }
                }
                return
            case .denied, .restricted:
                self.cerrarEnCola()
                self.publicar(.sinPermiso)
                return
            @unknown default:
                self.cerrarEnCola()
                self.publicar(.error("estado de permiso de micrófono desconocido"))
                return
            }
            if cambiaron, self.engine != nil || self.preparando {
                self.cerrarEnCola()
            }
            guard self.engine == nil, !self.preparando else { return }
            guard Date() >= self.proximoIntento else { return }
            self.arrancarEnCola()
        }
    }

    /// Suelta el dispositivo antes de que el Recorder normal lo tome. El callback
    /// llega en main únicamente cuando el tap y el AVAudioEngine ya terminaron.
    func suspender(completion: (() -> Void)? = nil) {
        // Si manos libres está habilitado, pasar SIEMPRE por la cola aunque el
        // estado público todavía diga `pausado`: puede existir un arranque
        // encolado por el timer. Esta barrera garantiza que ese arranque ocurra
        // antes del cierre y que Recorder reciba el micrófono completamente libre.
        // Con manos libres apagado conservamos el camino instantáneo de fn.
        let listenerHabilitado = Config.agenteNucleoActivo()
            && Config.agenteActivacionReposo()
        guard ocupaMicrofono || listenerHabilitado else {
            if let completion {
                if Thread.isMainThread { completion() }
                else { DispatchQueue.main.async(execute: completion) }
            }
            return
        }
        cola.async { [weak self] in
            self?.cerrarEnCola()
            self?.publicar(.pausado)
            guard let completion else { return }
            DispatchQueue.main.async(execute: completion)
        }
    }

    func apagar() {
        cola.sync {
            cerrarEnCola()
            publicar(.desactivado)
            alDespertar = nil
        }
    }

    /// Una acción recién terminada puede coincidir con el cierre asíncrono del
    /// Recorder/TTS y producir un error de dispositivo ocupado. AppDelegate usa
    /// esta señal de forma acotada para no obligar al usuario a esperar todo el
    /// backoff de 15 s. No arranca nada por sí sola ni ignora permisos.
    func permitirReintentoInmediato() {
        cola.async { [weak self] in self?.proximoIntento = .distantPast }
    }

    private func publicar(_ nuevo: Estado) {
        candadoEstado.lock()
        let cambio = estadoGuardado != nuevo
        estadoGuardado = nuevo
        candadoEstado.unlock()
        guard cambio else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .betoActivacionVozEstadoCambio,
                                            object: nil)
        }
    }

    private func arrancarEnCola() {
        #if canImport(Speech)
        guard #available(macOS 26, *) else {
            publicar(.noDisponible); return
        }
        preparando = true
        detectado = false
        anillo.removeAll(keepingCapacity: true)
        bytesAudioTotales = 0
        ultimaVozAudio = .distantPast
        generacion = UUID()
        let gen = generacion
        let frases = activadores
        publicar(.preparando)

        tarea = Task { [weak self] in
            guard let self else { return }
            do {
                Self.dbg("resolviendo idioma")
                let lang = Config.appleSpeechIdioma()
                guard let locale = await SpeechTranscriber.supportedLocale(
                    equivalentTo: Locale(identifier: lang)) else {
                    throw ErrorLocal.idioma
                }
                Self.dbg("locale \(locale.identifier(.bcp47))")
                guard !Task.isCancelled else { return }
                let transcriber = DictationTranscriber(locale: locale,
                                                        preset: .progressiveLongDictation)
                var estadoAssets = await AssetInventory.status(forModules: [transcriber])
                Self.dbg("assets \(estadoAssets)")
                if estadoAssets == .supported || estadoAssets == .downloading {
                    Self.dbg("solicitando assets")
                    if let req = try await AssetInventory.assetInstallationRequest(
                        supporting: [transcriber]) {
                        try await req.downloadAndInstall()
                    }
                    estadoAssets = await AssetInventory.status(forModules: [transcriber])
                    Self.dbg("assets después \(estadoAssets)")
                }
                guard estadoAssets == .installed else { throw ErrorLocal.assets }
                guard !Task.isCancelled else { return }

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let destino = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]) ?? self.formatoPCM
                Self.dbg("formato \(destino)")
                Self.dbg("creando AVAudioEngine + inputNode en main")
                let audio = await MainActor.run { RecursosAudio() }
                guard !Task.isCancelled else { return }
                let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()

                // Igual que PreviewVivo: crear el lector y llamar a start sin un
                // `await` intermedio. DictationTranscriber necesita ese orden.
                let lee = Task { [weak self] in
                    do {
                        for try await r in transcriber.results {
                            let texto = String(r.text.characters)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !texto.isEmpty else { continue }
                            let inicio = CMTimeGetSeconds(r.range.start)
                            let final = r.isFinal
                            self?.cola.async { [weak self] in
                                self?.evaluarEnCola(texto, frases: frases,
                                                   generacion: gen,
                                                   inicioSegmento: inicio,
                                                   final: final)
                            }
                        }
                    } catch {
                        self?.falloAsync(error, generacion: gen)
                    }
                }

                var errorMicrofono: Swift.Error?
                Self.dbg("publicando analyzer")
                let aceptado: Bool = self.cola.sync {
                    guard self.generacion == gen, self.preparando else { return false }
                    self._continuation = cont
                    self._analyzer = analyzer
                    self.formatoSpeech = destino
                    if destino != self.formatoPCM {
                        self.speechConverter = AVAudioConverter(from: self.formatoPCM,
                                                                to: destino)
                    }
                    self.lector = lee
                    do {
                        Self.dbg("arrancando micrófono")
                        try self.arrancarMicrofonoEnCola(generacion: gen,
                                                         recursos: audio)
                        Self.dbg("micrófono arrancó")
                        self.preparando = false
                        self.proximoIntento = .distantPast
                        self.publicar(.escuchando)
                        return true
                    } catch {
                        errorMicrofono = error
                        return false
                    }
                }
                guard aceptado else {
                    lee.cancel(); cont.finish()
                    await analyzer.cancelAndFinishNow()
                    if let errorMicrofono {
                        self.falloAsync(errorMicrofono, generacion: gen)
                    }
                    return
                }
                do {
                    Self.dbg("analyzer.start")
                    try await analyzer.start(inputSequence: stream)
                    Self.dbg("analyzer terminó")
                } catch {
                    self.falloAsync(error, generacion: gen)
                }
            } catch {
                self.falloAsync(error, generacion: gen)
            }
        }
        #else
        publicar(.noDisponible)
        #endif
    }

    private enum ErrorLocal: LocalizedError {
        case idioma, assets
        var errorDescription: String? {
            switch self {
            case .idioma: return "idioma no compatible"
            case .assets: return "modelo de idioma no instalado"
            }
        }
    }

    private func falloAsync(_ error: Swift.Error, generacion gen: UUID) {
        cola.async { [weak self] in
            guard let self, self.generacion == gen else { return }
            Log.log(.ia, "activación por voz local: \(error.localizedDescription)")
            self.cerrarEnCola()
            // Un asset ausente o un dispositivo ocupado no debe generar un
            // bucle de arranque cada 400 ms. Reintenta solo después de una pausa
            // o inmediatamente si el usuario apaga/enciende o cambia frases.
            self.proximoIntento = Date().addingTimeInterval(15)
            self.publicar(.error(error.localizedDescription))
        }
    }

    private func arrancarMicrofonoEnCola(generacion gen: UUID,
                                          recursos: RecursosAudio) throws {
        let engine = recursos.engine
        let input = recursos.input
        Self.dbg("inputNode listo; quitando tap anterior")
        input.removeTap(onBus: 0)
        Self.dbg("resolviendo micrófono elegido")
        Microfono.aplicar(a: input.audioUnit)
        Self.dbg("leyendo formato de entrada")
        let entrada = input.outputFormat(forBus: 0)
        Self.dbg("formato entrada \(entrada)")
        guard let conv = AVAudioConverter(from: entrada, to: formatoPCM) else {
            throw NSError(domain: "BetoDicta.ActivacionVoz", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "formato del micrófono incompatible"])
        }
        inputConverter = conv
        Self.dbg("instalando tap")
        input.installTap(onBus: 0, bufferSize: 4096, format: entrada) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = self.formatoPCM.sampleRate / entrada.sampleRate
            let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.formatoPCM,
                                             frameCapacity: capacidad) else { return }
            var servido = false
            conv.convert(to: out, error: nil) { _, status in
                if servido { status.pointee = .noDataNow; return nil }
                servido = true; status.pointee = .haveData; return buffer
            }
            guard out.frameLength > 0, let canal = out.int16ChannelData else { return }
            let chunk = Data(bytes: canal[0], count: Int(out.frameLength) * 2)
            self.cola.async { [weak self] in
                self?.recibirPCMEnCola(chunk, generacion: gen)
            }
        }
        Self.dbg("engine.prepare")
        engine.prepare()
        Self.dbg("engine.start")
        do { try engine.start() }
        catch {
            input.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
        self.inputNode = input
    }

    private func recibirPCMEnCola(_ chunk: Data, generacion gen: UUID) {
        guard generacion == gen, !detectado, !chunk.isEmpty else { return }
        if Self.contieneVoz(chunk) { ultimaVozAudio = Date() }
        bytesAudioTotales += chunk.count
        anillo.append(chunk)
        if anillo.count > maxAnilloBytes {
            anillo.removeFirst(anillo.count - maxAnilloBytes)
        }
        #if canImport(Speech)
        if #available(macOS 26, *),
           let cont = _continuation as? AsyncStream<AnalyzerInput>.Continuation {
            entregarSpeechEnCola(chunk, cont)
        }
        #endif
    }

    #if canImport(Speech)
    @available(macOS 26, *)
    private func entregarSpeechEnCola(_ chunk: Data,
                                      _ cont: AsyncStream<AnalyzerInput>.Continuation) {
        let frames = AVAudioFrameCount(chunk.count / 2)
        guard frames > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: formatoPCM,
                                         frameCapacity: frames) else { return }
        buf.frameLength = frames
        chunk.withUnsafeBytes { raw in
            if let base = raw.baseAddress, let canal = buf.int16ChannelData {
                memcpy(canal[0], base, chunk.count)
            }
        }
        var entrega = buf
        if let conv = speechConverter, let destino = formatoSpeech {
            let cap = AVAudioFrameCount(Double(frames) * destino.sampleRate /
                                        formatoPCM.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: destino,
                                             frameCapacity: cap) else { return }
            var servido = false
            conv.convert(to: out, error: nil) { _, status in
                if servido { status.pointee = .noDataNow; return nil }
                servido = true; status.pointee = .haveData; return buf
            }
            guard out.frameLength > 0 else { return }
            entrega = out
        }
        cont.yield(AnalyzerInput(buffer: entrega))
    }
    #endif

    private func evaluarEnCola(_ texto: String, frases: [String],
                               generacion gen: UUID, inicioSegmento: Double,
                               final: Bool) {
        guard generacion == gen, !detectado else { return }
        switch Self.decisionParcial(texto, frases: frases, final: final,
                                    permitirOrdenCorrida: Config.agenteActivacionOrdenCorrida()) {
        case .ignorar:
            // Si el parcial creció a “frase + contenido” (o Apple corrigió la
            // frase a otra cosa), ya no es el timbre aislado: cancelar el reloj.
            candidatoAcuse = nil
            return
        case .entregar(let inv, let forma):
            candidatoAcuse = nil
            entregarDespertarEnCola(inv, forma: forma,
                                    generacion: gen, inicioSegmento: inicioSegmento)
        case .esperar(let inv):
            // No reiniciar el reloj por cada parcial idéntico. Si después llega
            // contenido, `.ignorar` lo cancela antes de que venza la pausa.
            guard candidatoAcuse == nil else { return }
            let token = UUID()
            candidatoAcuse = (token, inv, inicioSegmento)
            programarAcuseTrasSilencio(token: token, generacion: gen,
                                       demora: Config.agenteActivacionEsperaAcuse())
        }
    }

    private func programarAcuseTrasSilencio(token: UUID, generacion gen: UUID,
                                             demora: Double) {
        cola.asyncAfter(deadline: .now() + max(0.05, demora)) { [weak self] in
            guard let self, self.generacion == gen, !self.detectado,
                  self.candidatoAcuse?.token == token,
                  let candidato = self.candidatoAcuse else { return }
            let espera = Config.agenteActivacionEsperaAcuse()
            let transcurrido = Date().timeIntervalSince(self.ultimaVozAudio)
            if transcurrido < espera {
                self.programarAcuseTrasSilencio(token: token, generacion: gen,
                                                demora: espera - transcurrido)
                return
            }
            self.candidatoAcuse = nil
            self.entregarDespertarEnCola(candidato.inv, forma: .turnoNuevo,
                                         generacion: gen,
                                         inicioSegmento: candidato.inicioSegmento)
        }
    }

    /// Misma escala que `Recorder.onLevel`. Muestrear reduce CPU en escucha
    /// continua; el umbral conservador evita que ruido tenue reinicie la pausa.
    private static func contieneVoz(_ pcm16: Data) -> Bool {
        guard pcm16.count >= 2 else { return false }
        var suma = 0.0
        var n = 0
        pcm16.withUnsafeBytes { raw in
            let muestras = raw.bindMemory(to: Int16.self)
            for i in stride(from: 0, to: muestras.count, by: 4) {
                let v = Double(muestras[i]) / 32768.0
                suma += v * v; n += 1
            }
        }
        let rms = sqrt(suma / Double(max(1, n)))
        return sqrt(min(rms * 12.0, 1.0)) > 0.15
    }

    private enum DecisionParcial {
        case ignorar
        case esperar(PerfilAgente.Invocacion)
        case entregar(PerfilAgente.Invocacion, Despertar.Forma)
    }

    /// La política predeterminada es un timbre: solo una frase finalizada y sin
    /// contenido despierta. La orden corrida existe como compatibilidad opt-in.
    private static func decisionParcial(_ texto: String, frases: [String], final: Bool,
                                        permitirOrdenCorrida: Bool) -> DecisionParcial {
        guard let inv = PerfilAgente.invocacionTolerante(en: texto,
                                                         activadores: frases) else {
            return .ignorar
        }
        if inv.contenido.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return final ? .entregar(inv, .turnoNuevo) : .esperar(inv)
        }
        return permitirOrdenCorrida ? .entregar(inv, .ordenCorrida) : .ignorar
    }

    private func entregarDespertarEnCola(_ inv: PerfilAgente.Invocacion,
                                          forma: Despertar.Forma,
                                          generacion gen: UUID,
                                          inicioSegmento: Double) {
        guard generacion == gen, !detectado else { return }
        detectado = true
        // `r.range.start` marca dónde empezó este segmento de Apple Speech. Como
        // la frase solo se acepta al inicio del segmento, podemos eliminar con
        // precisión conversación anterior del anillo. Se conserva 0,35 s de
        // margen y al menos el último segundo ante cualquier reloj anómalo.
        let previo = forma == .ordenCorrida
            ? Self.recortarPrebuffer(anillo, bytesTotales: bytesAudioTotales,
                                     inicioSegmento: inicioSegmento)
            : Data()
        let despertar = Despertar(id: UUID(), frase: inv.frase, audioPrevio: previo,
                                  fecha: Date(), forma: forma,
                                  origen: .reposoAppleLocal)
        let callback = alDespertar
        // No escribir `texto`: podría contener conversación ambiental. Solo la
        // frase deliberada y el tamaño técnico del búfer pasan al diagnóstico.
        AgenteLog.registrar("activacion_reposo_detectada", [
            "frase": inv.frase,
            "audio_ms": Int(Double(previo.count) / 32.0),
            "motor": "apple_local",
            "forma": forma.rawValue,
        ])
        cerrarEnCola()
        publicar(.pausado)
        DispatchQueue.main.async { callback?(despertar) }
    }

    private static func recortarPrebuffer(_ anillo: Data, bytesTotales: Int,
                                           inicioSegmento: Double) -> Data {
        var previo = anillo
        let totalSeg = Double(bytesTotales) / 32_000.0
        let inicioAnillo = totalSeg - Double(anillo.count) / 32_000.0
        if inicioSegmento.isFinite, inicioSegmento >= 0,
           inicioSegmento <= totalSeg + 0.25 {
            let desde = max(0, inicioSegmento - 0.35 - inicioAnillo)
            let deseado = Int(desde * 32_000) & ~1
            let maximo = max(0, anillo.count - 32_000)
            let quitar = min(deseado, maximo)
            if quitar > 0 { previo.removeFirst(quitar) }
        }
        return previo
    }

    /// Solo se llama dentro de `cola` (o desde `apagar`, que hace cola.sync).
    private func cerrarEnCola() {
        generacion = UUID()
        preparando = false
        detectado = false
        candidatoAcuse = nil
        if let engine {
            inputNode?.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputNode = nil
        inputConverter = nil
        speechConverter = nil
        formatoSpeech = nil
        anillo.removeAll(keepingCapacity: true)
        bytesAudioTotales = 0
        ultimaVozAudio = .distantPast
        #if canImport(Speech)
        if #available(macOS 26, *) {
            (_continuation as? AsyncStream<AnalyzerInput>.Continuation)?.finish()
            if let analyzer = _analyzer as? SpeechAnalyzer {
                Task { await analyzer.cancelAndFinishNow() }
            }
        }
        _continuation = nil
        _analyzer = nil
        #endif
        lector?.cancel(); lector = nil
        tarea?.cancel(); tarea = nil
    }

    // MARK: QA sin micrófono

    static func ejecutarQA() -> (Bool, [String]) {
        // Nombres deliberadamente ajenos al producto: comprueba que la lógica
        // depende de la lista inyectada y no de Bto ni del nombre de esta Mac.
        let nombreQA = "Atenea"
        let fraseQA = "Oye \(nombreQA)"
        let fraseAlternaQA = "Hola Nicanor"
        let frases = [fraseQA, fraseAlternaQA, "Escucha Ñusta"]
        var lineas: [String] = []
        func caso(_ nombre: String, _ ok: @autoclosure () -> Bool) -> Bool {
            let valor = ok(); lineas.append("\(valor ? "OK" : "FALLA") \(nombre)")
            return valor
        }
        let a = caso("puntuación", PerfilAgente.invocacion(
            en: "Oye, \(nombreQA): abre el calendario",
            activadores: frases)?.contenido == "abre el calendario")
        let b = caso("nombre configurable", PerfilAgente.invocacion(
            en: "\(fraseAlternaQA) pon música",
            activadores: frases)?.frase == fraseAlternaQA)
        let c = caso("no aparece en mitad", PerfilAgente.invocacion(
            en: "Ayer dije \(fraseQA) en una película", activadores: frases) == nil)
        let d = caso("una palabra insegura", PerfilAgente.invocacion(
            en: "Oye qué pasó", activadores: ["Oye"]) == nil)
        let e = caso("recorta prebuffer", PerfilAgente.invocacionDedicada(
            en: "ruido anterior. Oye, \(nombreQA), dime mis tareas",
            frase: fraseQA)?.contenido == "dime mis tareas")
        let f = caso("no recorta si STT omitió frase", PerfilAgente.invocacionDedicada(
            en: "dime mis tareas", frase: fraseQA) == nil)
        let g = caso("nombre raro con una letra extra", PerfilAgente.invocacionTolerante(
            en: "Oye Ateneaa dime mis tareas",
            activadores: [fraseQA])?.contenido == "dime mis tareas")
        let h = caso("no confunde una palabra vecina", PerfilAgente.invocacionTolerante(
            en: "Oye Andrea revisa el informe", activadores: [fraseQA]) == nil)
        let muestra = Data(repeating: 1, count: 128_000) // segundos 6…10 del flujo
        let recortada = recortarPrebuffer(muestra, bytesTotales: 320_000,
                                          inicioSegmento: 8)
        let i = caso("recorte temporal conserva margen", recortada.count == 75_200)
        let minima = recortarPrebuffer(muestra, bytesTotales: 320_000,
                                       inicioSegmento: 9.9)
        let j = caso("recorte temporal conserva al menos un segundo", minima.count == 32_000)
        let invalida = recortarPrebuffer(muestra, bytesTotales: 320_000,
                                         inicioSegmento: .nan)
        let k = caso("rango temporal inválido no destruye audio", invalida == muestra)
        let l = caso("parcial de frase sola todavía no despierta", {
            if case .esperar(let inv) = decisionParcial(fraseQA, frases: [fraseQA],
                                                        final: false,
                                                        permitirOrdenCorrida: false) {
                return inv.frase == fraseQA && inv.contenido.isEmpty
            }
            return false
        }())
        let m = caso("frase sola final abre un turno limpio", {
            if case .entregar(let inv, .turnoNuevo) = decisionParcial(
                fraseQA, frases: [fraseQA], final: true,
                permitirOrdenCorrida: false) {
                return inv.frase == fraseQA && inv.contenido.isEmpty
            }
            return false
        }())
        let n = caso("timbre predeterminado rechaza contenido pegado", {
            if case .ignorar = decisionParcial("\(fraseQA), abre el calendario",
                                               frases: [fraseQA], final: true,
                                               permitirOrdenCorrida: false) { return true }
            return false
        }())
        let o = caso("orden corrida solo funciona al habilitarla", {
            if case .entregar(let inv, .ordenCorrida) = decisionParcial(
                "\(fraseQA), abre el calendario", frases: [fraseQA], final: false,
                permitirOrdenCorrida: true) {
                return inv.contenido == "abre el calendario"
            }
            return false
        }())
        let p = caso("un activador distinto no despierta", {
            if case .ignorar = decisionParcial("Oye Octavio abre el calendario",
                                               frases: [fraseQA], final: true,
                                               permitirOrdenCorrida: true) { return true }
            return false
        }())
        var voz = [Int16](repeating: 0, count: 800)
        for i in voz.indices { voz[i] = i.isMultiple(of: 2) ? 7_000 : -7_000 }
        let datosVoz = voz.withUnsafeBytes { Data($0) }
        let p2 = caso("compuerta acústica distingue voz de silencio",
                      contieneVoz(datosVoz)
                        && !contieneVoz(Data(repeating: 0, count: 1_600)))
        let canales = [
            Config.canalesAcuse(formato: "texto", ttsDisponible: true),
            Config.canalesAcuse(formato: "texto_voz", ttsDisponible: true),
            Config.canalesAcuse(formato: "voz", ttsDisponible: true),
            Config.canalesAcuse(formato: "voz", ttsDisponible: false),
        ]
        let q = caso("acuse cubre texto, ambos, voz y respaldo sin TTS",
                     canales[0] == (true, false)
                        && canales[1] == (true, true)
                        && canales[2] == (false, true)
                        && canales[3] == (true, false))
        let tokenQA = "0123456789abcdef0123456789abcdef"
        let r = caso("pasarela Siri solo acepta ruta y capacidad local exactas",
                     PasarelaSiriBeto.esOrdenEscuchar(
                        PasarelaSiriBeto.urlEscuchar(token: tokenQA),
                        tokenEsperado: tokenQA))
        let s = caso("pasarela Siri rechaza ruta, token y credenciales ajenas",
                     !PasarelaSiriBeto.esOrdenEscuchar(
                        URL(string: "betodicta://agente/borrar?t=\(tokenQA)")!,
                        tokenEsperado: tokenQA)
                        && !PasarelaSiriBeto.esOrdenEscuchar(
                            URL(string: "betodicta://usuario:clave@agente/escuchar?t=\(tokenQA)")!,
                            tokenEsperado: tokenQA)
                        && !PasarelaSiriBeto.esOrdenEscuchar(
                            URL(string: "betodicta://agente/escuchar")!,
                            tokenEsperado: tokenQA)
                        && !PasarelaSiriBeto.esOrdenEscuchar(
                            URL(string: "betodicta://agente/escuchar?t=incorrecto")!,
                            tokenEsperado: tokenQA))
        let t = caso("respaldo Siri deriva el nombre y sus variantes",
                     PasarelaSiriBeto.esActivadorLocal("Oye Siri, Atenea",
                                                       nombreAgente: nombreQA)
                        && PasarelaSiriBeto.esActivadorLocal("Oye Siri dile a Atenea",
                                                            nombreAgente: nombreQA)
                        && !PasarelaSiriBeto.esActivadorLocal("Oye Siri Gloria",
                                                             nombreAgente: nombreQA))
        let u = caso("respaldo Siri no roba órdenes generales",
                     !PasarelaSiriBeto.esActivadorLocal("Oye Siri pon música",
                                                       nombreAgente: nombreQA)
                        && !PasarelaSiriBeto.esActivadorLocal("Oye Siri",
                                                             nombreAgente: nombreQA))
        return ([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, p2, q, r, s, t, u]
            .allSatisfy { $0 }, lineas)
    }
}
