import Foundation
import AVFoundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Preview EN VIVO de lo que dices (notch) — transcriptor nativo de Apple
//
// Mientras grabas, una COPIA del audio (el mismo chunk PCM16 16 kHz del Recorder) va al
// DictationTranscriber nativo de macOS 26 → el notch muestra lo que vas diciendo EN VIVO.
// Es SOLO visual: la transcripción REAL sigue siendo la cascada elegida (Groq, Whisper
// local, etc.) al soltar la tecla, y esa es la que se pega/pule. El preview jamás se pega.
//
// Falla suave: si no es macOS 26, el idioma no tiene modelo bajado, o algo falla, no hay
// preview y nada se detiene. Solo se usa cuando el motor real NO tiene ya su propio texto
// en vivo. Parametrizable: Config.previewVivo() (default ON).

// La instancia cruza Tasks/Dispatch, pero su estado mutable está confinado a `cola`.
final class PreviewVivo: @unchecked Sendable {
    /// `activo` y TODO el estado mutable de cada instancia viven en esta cola. Así el
    /// callback de audio, la UI y las Tasks de Speech nunca leen/escriben a la vez.
    private static var activo: PreviewVivo?
    private static let cola = DispatchQueue(label: "btodicta.previewvivo")

    static var disponible: Bool { AppleSpeechSTT.disponible }

    /// Arranca el preview. `onParcial` llega en MAIN con el texto dicho hasta ahora.
    static func iniciar(onParcial: @escaping (String) -> Void) {
        guard disponible, Config.previewVivo() else { return }
        #if canImport(Speech)
        if #available(macOS 26, *) {
            cola.async {
                activo?.cerrarEnCola()
                let p = PreviewVivo(onParcial: onParcial)
                activo = p
                p.arrancarEnCola()
            }
        }
        #endif
    }

    /// Alimenta un chunk PCM16 mono 16 kHz (mismo formato que produce el Recorder).
    /// Barato: se encola a una cola propia; el hilo de audio no espera.
    static func alimentar(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        cola.async { activo?.encolarEnCola(chunk) }
    }

    static func detener() {
        cola.async {
            let p = activo
            activo = nil
            p?.cerrarEnCola()
        }
    }

    // MARK: instancia (estado confinado a `cola`)

    private let onParcial: (String) -> Void
    private var tarea: Task<Void, Never>?
    private var lector: Task<Void, Never>?
    private var cerrado = false
    private let fmt16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                      channels: 1, interleaved: true)!

    private init(onParcial: @escaping (String) -> Void) {
        self.onParcial = onParcial
    }

    #if canImport(Speech)
    // Tipos de macOS 26 guardados como Any para poder declararlos en la clase
    // sin @available a nivel de propiedad almacenada.
    private var _continuation: Any?
    private var _analyzer: Any?
    private var _converter: AVAudioConverter?
    private var _fmtDestino: AVAudioFormat?

    private static let debug = ProcessInfo.processInfo.environment["BTODICTA_PREVIEWTEST"] != nil
    private static func dbg(_ s: String) { if debug { print("[PV] \(s)") } }

    @available(macOS 26, *)
    private func arrancarEnCola() {
        tarea = Task { [weak self] in
            guard let self else { return }
            let lang = Config.appleSpeechIdioma()
            guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: lang)) else {
                Self.dbg("sin locale para \(lang)")
                self.abortarArranque()
                return
            }
            guard !Task.isCancelled else { self.abortarArranque(); return }
            Self.dbg("locale \(loc.identifier(.bcp47))")

            // DictationTranscriber = el módulo del DICTADO EN VIVO del sistema (el que
            // escribe mientras hablas con doble-fn). Preset progresivo largo: volátiles
            // + finalización frecuente. SpeechTranscriber (batch) NO emite en vivo.
            let transcriber = DictationTranscriber(locale: loc, preset: .progressiveLongDictation)
            let estado = await AssetInventory.status(forModules: [transcriber])
            Self.dbg("assets \(estado)")
            guard !Task.isCancelled else { self.abortarArranque(); return }
            guard estado == .installed else {
                Log.log(.ia, "preview vivo: modelo de idioma no instalado — sin preview")
                self.abortarArranque()
                return
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let destino = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) ?? fmt16
            guard !Task.isCancelled else { self.abortarArranque(); return }
            Self.dbg("formato destino \(destino)")
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()

            // Publicar analyzer/continuation y vaciar los chunks iniciales EN ORDEN dentro
            // de la cola. Si detener ganó la carrera, no se arranca nada ni queda huérfano.
            // `sync` es deliberado: publica el estado sin introducir un punto `await`.
            // DictationTranscriber es sensible al orden lector→start (ver prueba real).
            let aceptado: Bool = Self.cola.sync {
                guard !self.cerrado, Self.activo === self else { return false }
                self._continuation = cont
                self._analyzer = analyzer
                self._fmtDestino = destino
                if destino != self.fmt16 {
                    self._converter = AVAudioConverter(from: self.fmt16, to: destino)
                }
                self.vaciarPendientesEnCola(cont)
                return true
            }
            guard aceptado else {
                cont.finish()
                await analyzer.cancelAndFinishNow()
                return
            }
            guard !Task.isCancelled else {
                cont.finish(); await analyzer.cancelAndFinishNow(); return
            }

            // IMPORTANTE: no puede haber una suspensión entre crear este lector y llamar
            // `analyzer.start`. Si el lector consume `results` antes de arrancar el analyzer,
            // Apple cierra la secuencia sin emitir nada. Este orden se verifica con audio real.
            let lee = Task { [weak self] in
                var fijo = ""
                do {
                    for try await r in transcriber.results {
                        let t = String(r.text.characters)
                        Self.dbg("result final=\(r.isFinal) '\(t.prefix(40))'")
                        var visible = fijo
                        if r.isFinal { fijo += t; visible = fijo } else { visible = fijo + t }
                        let limpio = visible.replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !limpio.isEmpty {
                            DispatchQueue.main.async { [weak self] in self?.onParcial(limpio) }
                        }
                    }
                    Self.dbg("results terminó")
                } catch { Self.dbg("results error \(error)") }
            }
            Self.cola.async { [weak self] in
                guard let self, !self.cerrado else { lee.cancel(); return }
                self.lector = lee
            }

            do {
                Self.dbg("analyzer.start…")
                try await analyzer.start(inputSequence: stream)
                Self.dbg("analyzer.start retornó")
            } catch {
                if !Task.isCancelled {
                    Log.log(.ia, "preview vivo: no arrancó (\(error.localizedDescription))")
                    Self.dbg("start error \(error)")
                }
                lee.cancel()
            }
        }
    }
    #endif

    private var pendientes: [Data] = []
    private var pendientesBytes = 0
    private let maxPendientesBytes = 4 * 1024 * 1024   // ~2 min de PCM16/16 kHz
    private var entregados = 0

    /// Convierte el chunk PCM16→buffer del formato del transcriptor y lo entrega.
    private func encolarEnCola(_ chunk: Data) {
        #if canImport(Speech)
        guard !cerrado else { return }
        if #available(macOS 26, *) {
            guard let cont = _continuation as? AsyncStream<AnalyzerInput>.Continuation else {
                pendientes.append(chunk)
                pendientesBytes += chunk.count
                // Un modelo ausente/lento jamás puede hacer crecer RAM sin límite.
                while pendientesBytes > maxPendientesBytes, let primero = pendientes.first {
                    pendientesBytes -= primero.count
                    pendientes.removeFirst()
                }
                return
            }
            vaciarPendientesEnCola(cont)
            entregarBufferEnCola(chunk, cont)
        }
        #endif
    }

    #if canImport(Speech)
    @available(macOS 26, *)
    private func vaciarPendientesEnCola(_ cont: AsyncStream<AnalyzerInput>.Continuation) {
        guard !pendientes.isEmpty else { return }
        let acum = pendientes
        pendientes.removeAll(keepingCapacity: false)
        pendientesBytes = 0
        Self.dbg("vaciando \(acum.count) chunks pendientes")
        for c in acum { entregarBufferEnCola(c, cont) }
    }

    @available(macOS 26, *)
    private func entregarBufferEnCola(_ chunk: Data, _ cont: AsyncStream<AnalyzerInput>.Continuation) {
        let frames = AVAudioFrameCount(chunk.count / 2)
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt16, frameCapacity: frames) else { return }
        buf.frameLength = frames
        chunk.withUnsafeBytes { raw in
            if let base = raw.baseAddress, let ch = buf.int16ChannelData {
                memcpy(ch[0], base, chunk.count)
            }
        }
        var entrega = buf
        if let conv = _converter, let destino = _fmtDestino {
            let cap = AVAudioFrameCount(Double(frames) * destino.sampleRate / fmt16.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: destino, frameCapacity: cap) else { return }
            var served = false
            conv.convert(to: out, error: nil) { _, status in
                if served { status.pointee = .noDataNow; return nil }
                served = true; status.pointee = .haveData; return buf
            }
            guard out.frameLength > 0 else { return }
            entrega = out
        }
        cont.yield(AnalyzerInput(buffer: entrega))
        entregados += 1
        if entregados <= 2 || entregados % 10 == 0 { Self.dbg("entregados \(entregados)") }
    }
    #endif

    /// Se llama desde una Task cuando el idioma/assets no permiten arrancar. La limpieza
    /// vuelve a `cola`, suelta de inmediato el audio acumulado y deja el dictado intacto.
    private func abortarArranque() {
        Self.cola.async { [weak self] in
            guard let self else { return }
            if Self.activo === self { Self.activo = nil }
            self.cerrarEnCola()
        }
    }

    /// Solo se llama dentro de `cola`.
    private func cerrarEnCola() {
        guard !cerrado else { return }
        cerrado = true
        pendientes.removeAll(keepingCapacity: false)
        pendientesBytes = 0
        #if canImport(Speech)
        if #available(macOS 26, *) {
            (_continuation as? AsyncStream<AnalyzerInput>.Continuation)?.finish()
            if let a = _analyzer as? SpeechAnalyzer {
                Task { await a.cancelAndFinishNow() }
            }
        }
        #endif
        _continuation = nil
        _analyzer = nil
        _converter = nil
        _fmtDestino = nil
        lector?.cancel(); lector = nil
        tarea?.cancel(); tarea = nil
    }
}
