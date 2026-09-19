import AppKit
import AVFoundation

// MARK: - Bitácora continua: audio
//
// Graba el micrófono en segundo plano, en trozos cerrados periódicamente.
//
// REGLA INNEGOCIABLE: el dictado por doble Fn manda. Cuando arranca, esta
// bitácora suelta el micrófono y espera; cuando termina, vuelve sola. Eso NO es
// configurable a propósito — un interruptor ahí acabaría rompiendo el dictado.
//
// Y ceder no deja hueco: mientras dictas, el propio dictado ya escribe su audio
// en `historial/`, y `adoptar(...)` lo incorpora a la línea de tiempo. La
// cobertura es continua sin tocar `Recorder` ni `ActivacionVoz`.
//
// El audio se escribe PCM crudo al instante (sobrevive a cualquier cierre
// abrupto) y se comprime cuando el trozo ya está cerrado. Al revés —escribir
// m4a en vivo— un corte dejaría el contenedor sin cerrar y el trozo entero
// ilegible: `AVAudioFile` no expone `close()`, se finaliza al liberarse.

final class ContinuoAudio {

    static let shared = ContinuoAudio()

    private let cola = DispatchQueue(label: "btodicta.continuo.audio")
    private let comprimir = DispatchQueue(label: "btodicta.continuo.audio.comprimir", qos: .utility)

    private var engine: AVAudioEngine?
    private var conversor: AVAudioConverter?
    /// Con qué formato se armó el conversor, para rearmarlo si el micrófono
    /// cambia de frecuencia o de número de canales a mitad de la grabación.
    private var convertidorDesde: AVAudioFormat?
    private let formatoSalida = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16000, channels: 1, interleaved: true)!

    private var mano: FileHandle?
    private var rutaTrozo: URL?
    private var inicioTrozo = Date()
    private var bytesTrozo = 0

    /// Cedido al dictado. Distinto de "apagado": aquí volvemos solos.
    /// Protegido por candado propio porque se levanta desde el hilo del dictado
    /// y se lee desde la cola de audio.
    private var cedido = false
    private let candadoCesion = NSLock()
    /// Sube en cada cesión: un reintento de una generación vieja se descarta.
    private var generacion: UInt64 = 0
    /// Evita que dos arranques concurrentes se pisen el trozo abierto.
    private var montando = false
    /// Intentos de arranque encadenados (micrófono ocupado).
    private var intentos = 0
    /// Arranques que montaron el motor pero no entregaron un solo buffer. Se
    /// cuentan APARTE de los intentos de montaje: el motor «arranca» siempre,
    /// así que reiniciar el contador al montar dejaba un bucle infinito de
    /// reinicios cada 8 s (visto el 2026-09-13, 15 vueltas seguidas).
    private var arranquesMudos = 0
    /// Solo para diagnóstico: cuántos buffers ha entregado el tap.
    private var buffersVistos = 0
    private(set) var activo = false

    /// Modo `voz`: colchón previo para no cortar la primera sílaba.
    private var colchon = Data()
    private var hablando = false
    private var ultimaVoz = Date.distantPast

    private init() {}

    // MARK: Ciclo de vida

    /// Enciende la bitácora si el ajuste lo permite. Idempotente.
    func arrancar() {
        guard Config.continuoActivo(), Config.continuoAudioModo() != "manual" else { return }
        cola.async { [weak self] in self?.arrancarEnCola() }
    }

    func detener() {
        cola.async { [weak self] in self?.detenerEnCola(cerrandoTrozo: true) }
    }

    /// El dictado pide el micrófono. Suelta TODO y avisa cuando esté libre —
    /// misma semántica que `ActivacionVoz.suspender`, para que `AppDelegate`
    /// encadene las dos igual.
    ///
    /// La bandera se levanta AQUÍ MISMO, de forma síncrona, antes de encolar
    /// nada. Marcarla dentro de la cola era una carrera real: si la cola venía
    /// ocupada con reintentos de arranque, uno de ellos tomaba el micrófono
    /// DESPUÉS de que al dictado ya se le hubiera dicho que podía seguir, y el
    /// dictado grababa silencio.
    func suspender(completion: @escaping () -> Void) {
        candadoCesion.lock()
        cedido = true
        generacion &+= 1          // invalida cualquier reintento en vuelo
        candadoCesion.unlock()

        cola.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion() }; return }
            self.detenerEnCola(cerrandoTrozo: true)
            DispatchQueue.main.async { completion() }
        }
    }

    /// El dictado terminó: recuperamos el micrófono si seguimos encendidos.
    func reanudar() {
        candadoCesion.lock()
        cedido = false
        candadoCesion.unlock()
        cola.async { [weak self] in
            guard let self else { return }
            guard Config.continuoActivo(), Config.continuoAudioModo() != "manual" else { return }
            self.arrancarEnCola()
        }
    }

    /// Lectura segura desde cualquier hilo.
    private var estaCedido: Bool {
        candadoCesion.lock(); defer { candadoCesion.unlock() }
        return cedido
    }

    // MARK: Arranque real

    private func arrancarEnCola() {
        // `montando` cierra una reentrada real: `reconciliarActivacionVoz` llama
        // a `reanudar()` cada vez que cambia el estado del micrófono, y mientras
        // el montaje espera en `main.sync` la bandera `activo` todavía es falsa.
        // Sin esto, el segundo arranque abría otro trozo y dejaba al tap del
        // primero escribiendo en un descriptor ya cerrado: 0 bytes en disco.
        guard !activo, !estaCedido, !montando else { return }
        montando = true
        defer { montando = false }
        if Config.continuoSoloConCorriente(), !EnergiaMac.conCorriente() {
            Log.log(.sistema, "bitácora: con batería y el ajuste pide corriente — no arranco el audio")
            return
        }

        // TODO el montaje del motor va en el hilo principal, no solo el
        // constructor: `inputNode`, `installTap` y `start()` incluidos. Montarlo
        // desde una cola de fondo deja un nodo que arranca sin quejarse pero
        // nunca entrega un solo buffer — el tap no se dispara y el archivo queda
        // en 0 bytes. Es el mismo requisito que respeta `ActivacionVoz`.
        // El archivo NO se abre aquí. Se abre solo cuando llega el primer trozo
        // de audio de verdad (`escribir`), porque el motor puede no arrancar:
        // abrirlo antes dejaba un .pcm de 0 bytes por cada intento fallido.
        var arrancado = false
        DispatchQueue.main.sync { arrancado = self.montarEnMain() }
        guard arrancado else { reintentar(); return }
        // `intentos` NO se reinicia aquí: solo cuando llegue audio de verdad.
        activo = true
        let marcaBuffers = buffersVistos
        candadoCesion.lock(); let genVigia = generacion; candadoCesion.unlock()
        Log.log(.sistema, "bitácora: audio en marcha (modo \(Config.continuoAudioModo()), eco \(Config.continuoAudioCancelacionEco() ? "sí" : "no"))")
        // Vigía del arranque mudo: un engine puede arrancar sin error y no
        // entregar jamás un buffer (pasó con el montaje en cola de fondo y
        // puede pasar si el dispositivo quedó en mal estado). Si en 8 s no
        // llegó nada, se desmonta y se reintenta desde cero.
        cola.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.activo, self.buffersVistos == marcaBuffers else { return }
            // Un vigía de una generación anterior no puede matar un motor
            // recién re-arrancado tras una cesión.
            self.candadoCesion.lock(); let vigente = self.generacion; self.candadoCesion.unlock()
            guard vigente == genVigia else { return }
            self.arranquesMudos += 1
            self.detenerEnCola(cerrandoTrozo: true)
            // Tras varias vueltas mudas el micrófono no es nuestro (lo tiene
            // otra app, cambió el dispositivo o quedó en mal estado tras un
            // cierre brusco). La bitácora NO se apaga —es su razón de ser
            // estar siempre grabando—: baja el ritmo a un intento por minuto,
            // deja de llenar el registro y vuelve sola en cuanto el micrófono
            // responda. Lo que se corrige es el bucle cada 8 s, no la vigilancia.
            if self.arranquesMudos >= 4 {
                if self.arranquesMudos == 4 {
                    Log.log(.sistema, "bitácora: el micrófono no entrega audio tras \(self.arranquesMudos) intentos — sigo intentando cada minuto (revisa si otra app lo está usando)")
                }
                self.intentos = 0
                self.cola.asyncAfter(deadline: .now() + 60) { [weak self] in
                    guard let self, Config.continuoActivo() else { return }
                    Log.debug("bitácora: reintento lento del micrófono (\(self.arranquesMudos) arranques mudos)")
                    self.arrancarEnCola()
                }
                return
            }
            Log.log(.sistema, "bitácora: el motor arrancó pero no entrega audio — reinicio \(self.arranquesMudos)/3")
            self.reintentar()
        }
    }

    /// El dispositivo de entrada puede estar ocupado al arrancar la app: la
    /// propia BtoDicta monta su audio en esos primeros segundos y CoreAudio
    /// devuelve -10875. No es un fallo definitivo, es "todavía no". Se reintenta
    /// con espera creciente y se abandona tras varios intentos para no dejar un
    /// bucle eterno pidiendo un micrófono que otro tiene.
    private func reintentar() {
        intentos += 1
        guard intentos <= 6 else {
            Log.log(.sistema, "bitácora: el micrófono sigue ocupado tras \(intentos) intentos — lo dejo hasta el próximo cambio de estado")
            intentos = 0
            return
        }
        // Espera creciente de verdad: 2,5 s, 5 s, 10 s, 20 s… Con incrementos
        // lineales una app que retiene el micrófono nos tenía preguntando cada
        // dos segundos y medio durante minutos.
        let espera = min(60.0, 2.5 * pow(2.0, Double(intentos - 1)))
        candadoCesion.lock(); let gen = generacion; candadoCesion.unlock()
        Log.log(.sistema, "bitácora: micrófono ocupado, reintento \(intentos) en \(espera) s")
        cola.asyncAfter(deadline: .now() + espera) { [weak self] in
            guard let self else { return }
            // Si entre medias el dictado pidió el micrófono, este reintento es
            // de una generación anterior y no debe tomarlo.
            self.candadoCesion.lock(); let vigente = self.generacion; self.candadoCesion.unlock()
            guard vigente == gen else { return }
            self.arrancarEnCola()
        }
    }

    /// Monta el motor de captura. SOLO desde el hilo principal.
    private func montarEnMain() -> Bool {
        let motor = AVAudioEngine()
        let entrada = motor.inputNode
        entrada.removeTap(onBus: 0)

        // ORDEN CRÍTICO. `setVoiceProcessingEnabled` sustituye la AudioUnit que
        // hay debajo del nodo (pasa de HAL a VoiceProcessingIO), así que cualquier
        // propiedad fijada antes se descarta. Si fijamos el micrófono primero,
        // se pierde y macOS nos enchufa el de por defecto. Por eso: eco primero,
        // luego volver a pedir la unidad, luego el dispositivo, y solo entonces
        // leer el formato.
        if Config.continuoAudioCancelacionEco() {
            do {
                try entrada.setVoiceProcessingEnabled(true)
            } catch {
                Log.log(.sistema, "bitácora: no pude activar la cancelación de eco (\(error.localizedDescription)) — sigo sin ella")
            }
        }
        Microfono.aplicar(a: entrada.audioUnit)

        let formatoEntrada = entrada.outputFormat(forBus: 0)
        guard formatoEntrada.sampleRate > 0 else {
            Log.log(.sistema, "bitácora: el micrófono no entregó formato válido — no arranco")
            return false
        }
        // El formato NO se le pasa a `installTap`. `Microfono.aplicar` de arriba
        // puede CAMBIAR el dispositivo de entrada, y CoreAudio todavía no ha
        // terminado de conmutar cuando se lee `outputFormat`: devuelve el del
        // aparato ANTERIOR. Es un formato válido, así que pasa el guard, pero no
        // es el que el motor tiene delante y `installTap` lo rechaza con «format
        // mismatch» — el mismo fallo que el grabador arrastró hasta 0.63.2. Aquí
        // dolía más: si la escucha no entra, la bitácora deja de grabar en
        // silencio. El conversor se arma con el formato del primer audio REAL.
        conversor = nil
        convertidorDesde = nil
        // A cero en CADA montaje: si no, «el micrófono entrega audio» solo sale
        // la primera vez de la sesión y las recuperaciones tras ceder el
        // micrófono al dictado quedan mudas en el registro. Es justo la línea
        // que se mira para saber si la bitácora está escuchando.
        buffersVistos = 0

        entrada.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let formatoEntrada = buffer.format
            if self.convertidorDesde?.sampleRate != formatoEntrada.sampleRate
                || self.convertidorDesde?.channelCount != formatoEntrada.channelCount {
                let conv = AVAudioConverter(from: formatoEntrada, to: self.formatoSalida)
                // El nodo de entrada puede exponer VARIOS canales (aquí llega con 9
                // tras activar la cancelación de eco). Sin mapa de canales, la
                // conversión a mono devuelve 0 marcos y el audio se pierde sin decir
                // nada. `[0]` toma el primer canal, que es el del micrófono.
                if formatoEntrada.channelCount > 1 {
                    conv?.channelMap = [0]
                    Log.log(.sistema, "bitácora: entrada de \(formatoEntrada.channelCount) canales — tomo el canal 0")
                }
                self.conversor = conv
                self.convertidorDesde = formatoEntrada
                Log.log(.sistema, "bitácora: formato de entrada \(Int(formatoEntrada.sampleRate)) Hz, \(formatoEntrada.channelCount) can")
            }
            self.buffersVistos += 1
            if self.buffersVistos == 1 {
                // Audio real: aquí sí se limpian los contadores de reintento.
                self.cola.async { self.intentos = 0; self.arranquesMudos = 0 }
                Log.log(.sistema, "bitácora: el micrófono entrega audio (\(buffer.frameLength) marcos por buffer)")
            } else if self.buffersVistos % 600 == 0 {
                Log.debug("bitácora: tap #\(self.buffersVistos)")
            }
            guard let conv = self.conversor else { return }
            let razon = self.formatoSalida.sampleRate / formatoEntrada.sampleRate
            let capacidad = AVAudioFrameCount(Double(buffer.frameLength) * razon) + 64
            guard let salida = AVAudioPCMBuffer(pcmFormat: self.formatoSalida, frameCapacity: capacidad) else { return }
            var servido = false
            var fallo: NSError?
            conv.convert(to: salida, error: &fallo) { _, estado in
                if servido { estado.pointee = .noDataNow; return nil }
                servido = true
                estado.pointee = .haveData
                return buffer
            }
            if let fallo, self.buffersVistos <= 3 {
                Log.log(.sistema, "bitácora: la conversión falló — \(fallo.localizedDescription)")
            }
            guard salida.frameLength > 0, let ch = salida.int16ChannelData else { return }
            let trozo = Data(bytes: ch[0], count: Int(salida.frameLength) * 2)

            var suma: Double = 0
            let n = Int(salida.frameLength)
            for i in 0..<n {
                let v = Double(ch[0][i]) / 32768.0
                suma += v * v
            }
            let rms = (suma / Double(max(n, 1))).squareRoot()

            self.cola.async { self.recibir(trozo, rms: rms) }
        }

        motor.prepare()
        do {
            try motor.start()
        } catch {
            entrada.removeTap(onBus: 0)
            try? entrada.setVoiceProcessingEnabled(false)
            Log.log(.sistema, "bitácora: el motor de audio no arrancó (\(error.localizedDescription))")

            return false
        }
        engine = motor
        return true
    }

    private func detenerEnCola(cerrandoTrozo: Bool) {
        guard activo || engine != nil else {
            if cerrandoTrozo { cerrarTrozo() }
            return
        }
        let motor = engine
        engine = nil
        conversor = nil
        activo = false
        colchon.removeAll()
        hablando = false
        if let motor {
            // Desmontar en MAIN, simétrico al montaje: el nodo de entrada no se
            // toca desde colas de fondo. Y APAGAR el procesamiento de voz al
            // soltar — la AUVoiceIO aplica cancelación de eco a nivel de
            // dispositivo, y dejarla puesta puede seguir tratando como "eco"
            // (silenciando) lo que capture el siguiente motor que lo abra.
            DispatchQueue.main.sync {
                let entrada = motor.inputNode
                entrada.removeTap(onBus: 0)
                motor.stop()
                try? entrada.setVoiceProcessingEnabled(false)
            }
            Log.log(.sistema, "bitácora: micrófono liberado")
        }
        if cerrandoTrozo { cerrarTrozo() }
    }

    // MARK: Escritura

    private func recibir(_ trozo: Data, rms: Double) {
        guard activo, !estaCedido else { return }

        if Config.continuoAudioModo() == "voz" {
            // Puerta por energía (no es un detector neuronal: es un umbral sobre
            // la señal ya tratada por la cancelación de eco). Con colchón previo
            // para no comerse el arranque de la frase, y cola de 1,5 s para no
            // cortar en cada pausa.
            var umbral = Config.continuoAudioUmbralVoz()
            // Puerta anti-eco: si por los parlantes está sonando algo (lo sabe
            // la pista del sistema), lo que capte el micrófono es en parte ese
            // sonido. Exigir más nivel evita registrar como «dicho» lo que en
            // realidad se estaba reproduciendo.
            if ContinuoAudioSistema.nivelActual > Config.continuoSistemaUmbral() {
                umbral *= Config.continuoAudioFactorAntiEco()
            }
            if rms >= umbral {
                if !hablando {
                    hablando = true
                    escribir(colchon)
                    colchon.removeAll()
                }
                ultimaVoz = Date()
            } else if hablando, Date().timeIntervalSince(ultimaVoz) > 1.5 {
                hablando = false
            }
            guard hablando else {
                colchon.append(trozo)
                // Colchón de ~1 s a 16 kHz mono 16 bits.
                if colchon.count > 32_000 { colchon.removeFirst(colchon.count - 32_000) }
                return
            }
        }

        escribir(trozo)
    }

    private func escribir(_ datos: Data) {
        guard !datos.isEmpty else { return }
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
        // Si ya hay un trozo abierto, ciérralo antes: abrir dos veces seguidas
        // dejaba el archivo anterior huérfano y en 0 bytes, porque `rutaTrozo`
        // se sobrescribía sin pasar por `cerrarTrozo`.
        if mano != nil { cerrarTrozo() }
        let ahora = Date()
        let carpeta = Self.carpetaDelDia(ahora, sub: "audio")
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appendingPathComponent(Self.sello(ahora) + ".pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        mano = try? FileHandle(forWritingTo: url)
        rutaTrozo = url
        inicioTrozo = ahora
        bytesTrozo = 0
    }

    private func cerrarTrozo() {
        try? mano?.close()
        mano = nil
        guard let url = rutaTrozo else { return }
        rutaTrozo = nil
        let inicio = inicioTrozo
        let bytes = bytesTrozo

        // Un trozo de menos de medio segundo no aporta nada.
        guard bytes > 16_000 else { try? FileManager.default.removeItem(at: url); return }

        let duracion = Double(bytes) / 32_000.0
        // Se registra el PCM crudo tal cual. La compresión NO se hace aquí a
        // propósito: la tanda diferida ya va a leer este audio para transcribirlo
        // y ese es el momento barato de comprimirlo, en una sola pasada y con el
        // equipo enchufado. Comprimir en caliente solo añadía un camino que podía
        // dejar contenedores a medias.
        comprimir.async {
            ContinuoIndice.shared.registrarAudio(ruta: url, instante: inicio,
                                                 duracion: duracion, origen: "continuo")
        }
    }

    // MARK: Adopción del audio del dictado

    /// Incorpora a la bitácora el `.wav` que el dictado acaba de guardar. Así,
    /// ceder el micrófono no abre un hueco en la línea de tiempo.
    static func adoptar(wav url: URL, instante: Date) {
        guard Config.continuoActivo(), Config.continuoAudioAdoptarDictado() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0
        let duracion = Double(bytes) / 32_000.0
        guard let id = ContinuoIndice.shared.registrarAudio(ruta: url, instante: instante,
                                                            duracion: duracion, origen: "dictado") else { return }
        // El dictado YA tiene su transcripción (el .txt que escribió el propio
        // flujo, con pulido incluido). Se adopta ese texto y la fila queda
        // procesada: la tanda no debe retranscribir un dictado ni, mucho menos,
        // pisar el .txt del historial con texto crudo.
        let txt = url.deletingPathExtension().appendingPathExtension("txt")
        let texto = (try? String(contentsOf: txt, encoding: .utf8)) ?? ""
        ContinuoIndice.shared.anotarTexto(texto, material: .audio, id: id)
    }

    // MARK: Utilidades

    static func carpetaDelDia(_ fecha: Date, sub: String) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return Config.continuoCarpeta()
            .appendingPathComponent(f.string(from: fecha))
            .appendingPathComponent(sub)
    }

    static func sello(_ fecha: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH-mm-ss"
        return f.string(from: fecha)
    }

}

// MARK: - Energía

enum EnergiaMac {
    /// `true` si el equipo está enchufado. Con batería, la bitácora puede
    /// pausarse si el usuario lo pidió.
    static func conCorriente() -> Bool {
        let salida = Process()
        salida.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        salida.arguments = ["-g", "batt"]
        let tuberia = Pipe()
        salida.standardOutput = tuberia
        salida.standardError = FileHandle.nullDevice
        do { try salida.run() } catch { return true }
        let datos = tuberia.fileHandleForReading.readDataToEndOfFile()
        salida.waitUntilExit()
        let texto = String(data: datos, encoding: .utf8) ?? ""
        // Un portátil sin batería (o un sobremesa) no imprime 'Battery Power'.
        return !texto.contains("'Battery Power'")
    }
}
