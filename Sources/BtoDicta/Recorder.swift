import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Grabadora (micrófono → PCM16 16 kHz mono, con chunks y nivel)

final class Recorder {
    /// UN MOTOR NUEVO EN CADA DICTADO (se crea en `arrancarMotor`).
    ///
    /// Era uno solo para toda la vida de la aplicación, y guarda el formato del
    /// micrófono de la primera vez. Cuando otra aplicación cambia la frecuencia
    /// del micrófono (48 000 ↔ 44 100 Hz) o entra un auricular (24 000 en una
    /// llamada), el motor seguía con la vieja y no arrancaba: error -10868, sin
    /// una línea en el registro, y el dictado muerto hasta reiniciar la
    /// aplicación. Visto del 21 al 23 de septiembre de 2026: tres fn fn seguidos
    /// sin grabar, y un reinicio que lo «arreglaba». Crear uno cuesta
    /// milisegundos; reusarlo costaba dictados.
    private var engine = AVAudioEngine()
    /// Ventana reciente de PCM, NO el dictado entero.
    ///
    /// Hasta 0.63.3 esto acumulaba todo lo hablado: seis horas eran 659 MB en
    /// memoria, y `stop()` armaba encima un `.wav` completo desde este mismo
    /// buffer — 1 388 MB medidos en total. Ahora el audio va a disco según
    /// entra y aquí solo se guarda lo que la vista previa en vivo puede pedir.
    private var samples = Data()
    /// Cuánto se conserva en memoria. La vista previa en vivo mira como mucho
    /// los últimos dos minutos; tres da margen sin que cueste: 5,7 MB.
    static let ventanaMemoria = Int(frecuenciaInterna) * 2 * 180
    /// El `.wav` del dictado en curso, escrito según entra el audio.
    private var salida: FileHandle?
    private var urlSalida: URL?
    private var bytesPCM = 0
    // El tap escribe desde el hilo de audio y main lee a mitad de grabación
    // (backlog en vivo): sin este candado es una carrera de datos real.
    private let candado = NSLock()
    private var converter: AVAudioConverter?
    /// Con qué formato se armó el convertidor. Si el micrófono cambia de
    /// frecuencia a mitad de la grabación —pasa al conmutar de dispositivo—, se
    /// rearma solo en vez de convertir con la tasa equivocada.
    private var convertidorDesde: AVAudioFormat?
    /// El formato con el que se está escuchando. Lo usa la prueba propia.
    var formatoEntradaQA: AVAudioFormat? { convertidorDesde }

    /// Bytes de audio escritos en el dictado en curso: lo que se transcribirá al
    /// soltar. Lo enseña el menú mientras se graba (spec 010, RF-07), para que el
    /// coste de una sesión larga se vea ANTES de pagarlo.
    var bytesGrabados: Int {
        candado.lock(); defer { candado.unlock() }
        return bytesPCM
    }

    /// El archivo del dictado en curso. Lo usa la prueba del modo reunión para
    /// comprobar que activarlo a mitad no abre una grabación nueva.
    var archivoEnCurso: URL? {
        candado.lock(); defer { candado.unlock() }
        return urlSalida
    }
    /// Frecuencia INTERNA de la app. El micrófono de cada equipo entrega la
    /// suya —44 100, 48 000, 96 000 Hz…— y el conversor la lleva siempre aquí,
    /// así que nada del resto del código depende del hardware de turno.
    static let frecuenciaInterna: Double = 16000
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Recorder.frecuenciaInterna, channels: 1, interleaved: true)!

    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    /// El RMS CRUDO, sin la amplificación del medidor.
    ///
    /// `onLevel` entrega un valor pensado para PINTAR una barra: `rms * 12`
    /// y luego raíz cuadrada, para que un susurro ya mueva el medidor. Usarlo
    /// para decidir «¿hay voz?» fue un fallo real y caro: con ese transformador,
    /// un RMS de 0,0019 —silencio digital— ya da 0,15, así que el corte por
    /// silencio no podía saltar en ninguna sala del mundo. Un dictado se quedó
    /// abierto ocho minutos sin nadie hablando, y se transcribió y se pagó.
    var onRMS: ((Float) -> Void)?
    private(set) var isRecording = false

    /// PCM crudo acumulado hasta ahora (para transcripción parcial en vivo).
    var pcmAcumulado: Data {
        candado.lock(); defer { candado.unlock() }
        return samples
    }

    /// Buffers recibidos del micrófono en el dictado en curso. Cero tras unos
    /// segundos significa que no está entrando NADA: mejor decirlo que dejar al
    /// usuario hablando contra un micrófono mudo.
    private(set) var buffersRecibidos = 0

    /// Abre el `.wav` del dictado en curso. Si falla no se aborta nada: se
    /// sigue en memoria, porque un dictado con memoria alta es infinitamente
    /// mejor que un dictado que no arranca.
    ///
    /// Está fuera de `start()` para que la prueba de memoria pueda usar el
    /// mismo camino sin abrir el micrófono. Si se volviera a meter dentro, la
    /// prueba mediría otra cosa — que es exactamente cómo se coló el falso
    /// «0 MB en seis horas».
    private func abrirSalida(preload: Data = Data()) {
        Config.asegurarDirSeguro()
        try? FileManager.default.createDirectory(at: Recorder.carpetaDictados,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let destino = Recorder.carpetaDictados
            .appendingPathComponent("dictado-\(UUID().uuidString).wav")
        guard FileManager.default.createFile(atPath: destino.path,
                                             contents: Recorder.cabecera(bytesPCM: 0),
                                             attributes: [.posixPermissions: 0o600]),
              let h = try? FileHandle(forWritingTo: destino) else {
            salida = nil; urlSalida = nil; bytesPCM = 0
            Log.log(.sistema, "dictado: no pude abrir el archivo de audio — grabo en memoria")
            return
        }
        try? h.seekToEnd()
        salida = h
        urlSalida = destino
        bytesPCM = 0
        if !preload.isEmpty {
            try? h.write(contentsOf: preload)
            bytesPCM = preload.count
        }
    }

    /// El `.wav` en curso. Solo para `BTODICTA_MEMTEST`.
    var urlQA: URL? { urlSalida }

    /// Abre el archivo sin tocar el micrófono. Solo para `BTODICTA_MEMTEST`.
    func abrirSalidaQA() { abrirSalida() }

    /// Dónde viven los `.wav` del dictado en curso.
    static var carpetaDictados: URL {
        Config.dir.appendingPathComponent("dictados", isDirectory: true)
    }

    /// Cabecera WAV de 44 bytes. Los tamaños se escriben al cerrar, cuando ya se
    /// sabe cuánto audio hubo.
    private static func cabecera(bytesPCM: Int) -> Data {
        var wav = Data()
        let sampleRate = UInt32(frecuenciaInterna)
        func mete<T>(_ v: T) { withUnsafeBytes(of: v) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        mete(UInt32(36 + bytesPCM).littleEndian)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        mete(UInt32(16).littleEndian)
        mete(UInt16(1).littleEndian)
        mete(UInt16(1).littleEndian)
        mete(sampleRate.littleEndian)
        mete(UInt32(sampleRate * 2).littleEndian)
        mete(UInt16(2).littleEndian)
        mete(UInt16(16).littleEndian)
        wav.append("data".data(using: .ascii)!)
        mete(UInt32(bytesPCM).littleEndian)
        return wav
    }

    /// Solo pruebas: el primer intento, con el micrófono elegido, falla.
    var simularFalloDelElegido = false

    /// Solo pruebas: deja el motor como lo deja un cambio de frecuencia del
    /// micrófono —lo cambian otras aplicaciones, o un auricular que entra—: el
    /// formato del lado de la app sigue en la frecuencia vieja. Devuelve la
    /// frecuencia vieja que quedó puesta.
    func envejecerFormatoParaPrueba() -> Double? {
        guard let au = engine.inputNode.audioUnit else { return nil }
        var asbd = AudioStreamBasicDescription()
        var tam = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioUnitGetProperty(au, kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output, 1, &asbd, &tam) == noErr else { return nil }
        asbd.mSampleRate = asbd.mSampleRate == 44100 ? 48000 : 44100
        guard AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output, 1, &asbd, tam) == noErr else { return nil }
        return asbd.mSampleRate
    }

    func start(preloadPCM: Data = Data()) throws {
        // Blindaje contra doble arranque: un segundo installTap en el mismo
        // bus lanza NSException y tumba la app (crash real del 2026-07-10).
        guard !isRecording else { return }
        candado.lock()
        samples = preloadPCM
        candado.unlock()

        abrirSalida(preload: preloadPCM)

        // El dictado es lo que no puede fallar. Primero con el micrófono elegido;
        // si no arranca, con un motor nuevo y el micrófono del sistema. Y cada
        // fallo queda escrito: antes el de `engine.start()` no dejaba rastro.
        do {
            try arrancarMotor(forzarElegido: true)
        } catch let primero {
            Log.log(.sistema, "micrófono: el dictado no arrancó con el micrófono elegido (\(Recorder.describir(primero))) — pruebo con un motor nuevo y el micrófono del sistema")
            do {
                try arrancarMotor(forzarElegido: false)
                Log.log(.sistema, "micrófono: el dictado arrancó con el micrófono del sistema")
            } catch let segundo {
                Log.log(.sistema, "micrófono: el dictado NO arrancó (\(Recorder.describir(segundo)))")
                throw segundo
            }
        }
        isRecording = true
        // La activación manos libres entrega los últimos segundos que estaban
        // solo en RAM. Pasan por el MISMO historial/preview/backlog que el audio
        // nuevo y la cascada final recibe una única grabación continua.
        if !preloadPCM.isEmpty { onChunk?(preloadPCM) }
    }

    /// Monta un motor NUEVO y lo arranca. Lanza si no arranca, dejándolo parado
    /// y sin escucha puesta.
    private func arrancarMotor(forzarElegido: Bool) throws {
        if forzarElegido, simularFalloDelElegido {
            throw NSError(domain: "prueba", code: -10868,
                          userInfo: [NSLocalizedDescriptionKey: "fallo simulado del micrófono elegido"])
        }
        engine = AVAudioEngine()
        // Cada motor anuncia su formato: así el registro dice con qué frecuencia
        // se grabó cada dictado, que es lo primero que hay que saber si falla.
        convertidorDesde = nil
        let input = engine.inputNode
        input.removeTap(onBus: 0)   // por si quedó un tap de un intento fallido
        // Fijar el micrófono ANTES de leer el formato: sin esto macOS puede
        // enchufarnos el mic del iPhone (Continuity) y grabar silencio.
        if forzarElegido { Microfono.aplicar(a: input.audioUnit) }
        // El formato del micrófono puede llegar INVÁLIDO (0 Hz o 0 canales)
        // cuando el dispositivo está en transición: justo lo que pasa al pulsar
        // la tecla mientras la bitácora acaba de soltar el micrófono. Con ese
        // formato, `installTapOnBus` lanza una NSException que Swift no puede
        // atrapar y la app ABORTA a mitad del dictado (crash real 2026-09-13).
        var inFormat = input.outputFormat(forBus: 0)
        if inFormat.sampleRate <= 0 || inFormat.channelCount == 0 {
            // Un respiro y una segunda lectura: el dispositivo suele asentarse
            // en milisegundos. Si sigue mal, se falla limpio y la cascada
            // normal se encarga; nunca se aborta.
            engine.stop(); engine.reset()
            Thread.sleep(forTimeInterval: 0.15)
            inFormat = input.outputFormat(forBus: 0)
            Log.log(.sistema, "micrófono en transición — releído a \(Int(inFormat.sampleRate)) Hz, \(inFormat.channelCount) can")
        }
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            Log.log(.sistema, "micrófono no disponible (formato \(inFormat.sampleRate) Hz, \(inFormat.channelCount) can) — no arranco el dictado")
            throw ScribeError.ws("el micrófono no está disponible ahora mismo")
        }
        buffersRecibidos = 0
        let instalar = { [weak self] in
        // `format: nil` a propósito. Pasarle el formato que acabamos de leer
        // era la causa del fallo: `Microfono.aplicar` puede CAMBIAR el
        // dispositivo y CoreAudio tarda en conmutar, así que la lectura devuelve
        // el formato del aparato ANTERIOR —44 100 Hz cuando ya está en 48 000, o
        // al revés—. Es un formato válido, así que pasaba la comprobación de
        // 0.54.1, y `installTap` lo rechazaba con «Failed to create tap due to
        // format mismatch»; el dictado no arrancaba y había que reiniciar la
        // aplicación. Con nil, AVAudioEngine resuelve el formato real en el
        // momento de instalar y la discrepancia no puede existir.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            // El convertidor se arma con el formato del PRIMER buffer —el de
            // verdad— y se rearma si cambia a mitad de camino.
            let formatoEntrada = buffer.format
            if self.convertidorDesde?.sampleRate != formatoEntrada.sampleRate
                || self.convertidorDesde?.channelCount != formatoEntrada.channelCount {
                self.converter = AVAudioConverter(from: formatoEntrada, to: self.outFormat)
                self.convertidorDesde = formatoEntrada
                Log.log(.sistema, "micrófono: escuchando a \(Int(formatoEntrada.sampleRate)) Hz, \(formatoEntrada.channelCount) can")
            }
            guard let converter = self.converter else { return }
            self.buffersRecibidos &+= 1
            let ratio = self.outFormat.sampleRate / formatoEntrada.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: self.outFormat, frameCapacity: capacity) else { return }
            var served = false
            converter.convert(to: out, error: nil) { _, status in
                if served {
                    status.pointee = .noDataNow
                    return nil
                }
                served = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
            let chunk = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
            self.candado.lock()
            if let h = self.salida {
                try? h.write(contentsOf: chunk)
                self.bytesPCM += chunk.count
                // En memoria solo la ventana reciente: lo demás ya está en disco.
                self.samples.append(chunk)
                if self.samples.count > Recorder.ventanaMemoria {
                    // `Data(...)` no sobra: `suffix` devuelve una VISTA que
                    // retiene el buffer entero, así que sin copiar aquí la
                    // memoria no baja ni un byte. Es lo que hacía que la ventana
                    // pareciera aplicada y el dictado siguiera vivo en RAM.
                    self.samples = Data(self.samples.suffix(Recorder.ventanaMemoria))
                }
            } else {
                // Sin archivo, el buffer vuelve a ser la única copia.
                self.samples.append(chunk)
                self.bytesPCM += chunk.count
            }
            self.candado.unlock()
            self.onChunk?(chunk)

            var sum: Double = 0
            let n = Int(out.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                sum += v * v
            }
            let rms = Float((sum / Double(max(n, 1))).squareRoot())
            let boosted = Float(pow(Double(min(rms * 12, 1.0)), 0.5))
            self.onLevel?(boosted)   // para el medidor: amplificado a propósito
            self.onRMS?(rms)         // para decidir: el valor real
        }

        }
        // AVFoundation lanza excepciones de Objective-C que `try` no ve: van por
        // el atrapador nativo o se llevan la app por delante.
        // Hasta TRES intentos con un respiro entre ellos. Un micrófono que
        // acaba de cambiar de dueño —la bitácora lo suelta y el dictado lo
        // toma— puede tardar unas décimas en asentarse. Antes se fallaba al
        // primer intento y el dictado no arrancaba: había que cerrar y volver a
        // abrir la aplicación. Medido en el registro: el mismo micrófono que
        // rechazaba la escucha entregaba audio sin problema segundos después.
        var falloInstalar: String?
        for intento in 1...3 {
            falloInstalar = AudioSeguro.atrapar(instalar)
            if falloInstalar == nil { break }
            input.removeTap(onBus: 0)
            guard intento < 3 else { break }
            Log.log(.sistema, "micrófono: la escucha no entró al intento \(intento) (\(falloInstalar ?? "")) — reintento")
            engine.stop(); engine.reset()
            Thread.sleep(forTimeInterval: 0.25)
        }
        if let fallo = falloInstalar {
            input.removeTap(onBus: 0)
            Log.log(.sistema, "micrófono: no pude instalar la escucha tras 3 intentos (\(fallo)) — dictado no iniciado")
            throw ScribeError.ws("el micrófono no está libre; suelta la tecla y vuelve a intentarlo")
        }
        engine.prepare()
        var errorArranque: Error?
        if let fallo = AudioSeguro.atrapar({
            do { try self.engine.start() } catch { errorArranque = error }
        }) {
            input.removeTap(onBus: 0)
            Log.log(.sistema, "micrófono: el motor de audio no arrancó (\(fallo))")
            throw ScribeError.ws("el motor de audio no arrancó")
        }
        if let errorArranque {
            // Sin esto el tap queda huérfano y el próximo start crashea
            // (doble installTap en el mismo bus).
            input.removeTap(onBus: 0)
            engine.stop()
            throw errorArranque
        }
    }

    static func describir(_ e: Error) -> String {
        let n = e as NSError
        return "\(n.domain) \(n.code): \(n.localizedDescription)"
    }

    /// Cierra el dictado y devuelve **la ruta** del `.wav`, no su contenido.
    ///
    /// Devolver los bytes era la segunda mitad del problema de memoria: se
    /// armaba un `.wav` completo desde el buffer, de modo que al soltar la tecla
    /// había dos copias del dictado en RAM. Medido en seis horas: 1 388 MB.
    /// Ahora el archivo ya está escrito y solo hay que cerrarle la cabecera.
    @discardableResult
    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        candado.lock(); defer { candado.unlock() }
        samples = Data()
        guard let h = salida, let url = urlSalida else { return urlSalida }
        // La cabecera se escribió con ceros porque aún no se sabía cuánto audio
        // iba a haber. Ahora sí: se reescriben los 44 bytes del principio.
        try? h.synchronize()
        try? h.seek(toOffset: 0)
        try? h.write(contentsOf: Recorder.cabecera(bytesPCM: bytesPCM))
        try? h.close()
        salida = nil
        return url
    }

    /// Cuánto pesa el `.wav` sin abrirlo. Para calcular la duración no hace
    /// falta cargar el audio, y cargarlo era justamente el problema.
    static func bytes(de url: URL?) -> Int {
        guard let url else { return 0 }
        return ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    /// El `.wav` del dictado que acaba de terminar, en bytes. Solo para quien de
    /// verdad lo necesita en memoria; para enviarlo a un motor, usar la ruta.
    static func datos(de url: URL?) -> Data {
        guard let url else { return Data() }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    /// Barre los `.wav` de trabajo con más días de los que se hayan fijado.
    ///
    /// Tres cerraduras, porque esto borra audio: solo su propia carpeta, solo su
    /// propio prefijo, y solo por encima de la antigüedad configurada. Con el
    /// ajuste en 0 no borra nada en absoluto. El historial guarda su copia
    /// aparte y no se toca aquí.
    @discardableResult
    static func barrerDictadosViejos() -> (archivos: Int, bytes: Int) {
        let dias = Config.dictadosConservarDias()
        guard dias > 0 else { return (0, 0) }
        let fm = FileManager.default
        guard let lista = try? fm.contentsOfDirectory(at: carpetaDictados,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return (0, 0)
        }
        let limite = Date().addingTimeInterval(-Double(dias) * 86_400)
        var n = 0, bytes = 0
        for u in lista where u.lastPathComponent.hasPrefix("dictado-") && u.pathExtension == "wav" {
            guard let fecha = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  fecha < limite else { continue }
            let peso = Recorder.bytes(de: u)
            if (try? fm.removeItem(at: u)) != nil { n += 1; bytes += peso }
        }
        if n > 0 {
            Log.log(.sistema, "dictados: barridos \(n) audios de trabajo de más de \(dias) días (\(bytes / 1_048_576) MB). El historial no se toca")
        }
        return (n, bytes)
    }

    /// Borra el `.wav` de un dictado ya transcrito y guardado.
    static func descartar(_ url: URL?) {
        guard let url, url.path.hasPrefix(carpetaDictados.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Mete un trozo por el mismo camino que el tap del micrófono, sin abrir el
    /// micrófono. Solo la usa `BTODICTA_MEMTEST`: grabar seis horas de verdad
    /// para medir la memoria no es una prueba, es una tarde.
    ///
    /// Tiene que hacer EXACTAMENTE lo que hace el tap. Si se separan, la prueba
    /// vuelve a medir algo que no es el grabador — que es justo el fallo que la
    /// hizo dar 0 MB cuando el grabador sí acumulaba.
    func inyectarQA(_ chunk: Data) {
        candado.lock()
        if let h = salida {
            try? h.write(contentsOf: chunk)
            bytesPCM += chunk.count
            samples.append(chunk)
            if samples.count > Recorder.ventanaMemoria {
                samples = Data(samples.suffix(Recorder.ventanaMemoria))
            }
        } else {
            samples.append(chunk)
            bytesPCM += chunk.count
        }
        candado.unlock()
        onChunk?(chunk)
    }

    /// Los últimos `segundos` de audio, sin copiar el dictado entero. Para las
    /// vistas previas en vivo, que no necesitan lo que ya se transcribió.
    func pcmReciente(segundos: Double) -> Data {
        candado.lock(); defer { candado.unlock() }
        let tope = Int(segundos * Recorder.frecuenciaInterna) * 2
        guard samples.count > tope else { return samples }
        return Data(samples.suffix(tope))
    }

    private func wavFile(from pcm: Data) -> Data {
        var wav = Data()
        let sampleRate: UInt32 = 16000
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count).littleEndian)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian)
        append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian)
        append(UInt32(sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian)
        append(UInt16(16).littleEndian)
        wav.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count).littleEndian)
        wav.append(pcm)
        return wav
    }
}
