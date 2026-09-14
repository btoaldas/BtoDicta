import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Historial (caja negra: voz + texto a disco EN VIVO)

final class HistoryWriter {
    private let base: URL
    private var pcmHandle: FileHandle?
    private var lastTextWrite = Date.distantPast

    var wavURL: URL { base.appendingPathExtension("wav") }
    var txtURL: URL { base.appendingPathExtension("txt") }
    /// Interno salvo para la prueba propia de cancelación (spec 002).
    private(set) lazy var pcmURL: URL = base.appendingPathExtension("pcm")

    static var historyDir: URL { Config.dir.appendingPathComponent("historial") }

    /// Un rescate aditivo vive junto al texto original como
    /// `HH-mm-ss.recuperado.txt`. No es otra entrada del historial: es la copia
    /// verificada que los lectores deben preferir sin pisar la evidencia previa.
    static func esTextoPrincipal(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "txt"
            && !url.lastPathComponent.lowercased().hasSuffix(".recuperado.txt")
    }

    static func textoRecuperadoURL(para principal: URL) -> URL {
        principal.deletingPathExtension()
            .appendingPathExtension("recuperado")
            .appendingPathExtension("txt")
    }

    static func textoPreferidoURL(para principal: URL) -> URL {
        let recuperado = textoRecuperadoURL(para: principal)
        return FileManager.default.fileExists(atPath: recuperado.path) ? recuperado : principal
    }

    init() {
        let dir = Self.historyDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        func part(_ format: String) -> String {
            let f = DateFormatter()
            f.dateFormat = format
            return f.string(from: now)
        }
        // Estructura anidada: historial/2026/07/09/HH-mm-ss.*
        let dayDir = dir
            .appendingPathComponent(part("yyyy"))
            .appendingPathComponent(part("MM"))
            .appendingPathComponent(part("dd"))
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        base = dayDir.appendingPathComponent(part("HH-mm-ss"))
        FileManager.default.createFile(atPath: pcmURL.path, contents: nil)
        pcmHandle = try? FileHandle(forWritingTo: pcmURL)
    }

    /// Cuántos bytes de PCM llevan escritos. Es la MEDIDA del dictado: la
    /// aplicación ya no necesita guardar una copia del audio para saber por
    /// dónde va.
    private(set) var bytesEscritos = 0

    /// Audio crudo a disco al instante — sobrevive a cualquier crash.
    func append(chunk: Data) {
        pcmHandle?.write(chunk)
        bytesEscritos += chunk.count
    }

    /// Lee un tramo del audio ya grabado, directamente del archivo.
    ///
    /// Es lo que permite dejar de conservar el dictado entero en memoria: el
    /// archivo que se está escribiendo YA es el audio completo, así que quien
    /// necesite un trozo lo pide aquí en vez de quedarse con una copia. Medido
    /// en el equipo de referencia, leer 25 MB tarda 1 ms, frente a los ~23 s
    /// que tarda la llamada de transcripción que viene después.
    func leerPCM(desde: Int, hasta: Int? = nil) -> Data {
        let fin = min(hasta ?? bytesEscritos, bytesEscritos)
        let ini = max(0, min(desde, fin))
        guard fin > ini else { return Data() }
        // Se vacía lo pendiente para que el tramo recién hablado también esté.
        try? pcmHandle?.synchronize()
        guard let lector = try? FileHandle(forReadingFrom: pcmURL) else { return Data() }
        defer { try? lector.close() }
        try? lector.seek(toOffset: UInt64(ini))
        return (try? lector.read(upToCount: fin - ini)) ?? Data()
    }

    /// Texto parcial a disco (máx. 2 escrituras/seg para no castigar el SSD).
    func savePartial(_ text: String, force: Bool = false) {
        guard force || Date().timeIntervalSince(lastTextWrite) > 0.5 else { return }
        lastTextWrite = Date()
        try? text.write(to: txtURL, atomically: true, encoding: .utf8)
    }

    /// Cierre normal: WAV con cabecera + texto final; borra el crudo temporal
    /// SOLO si el .wav quedó bien escrito (disco lleno no debe perder el audio).
    func finish(wav: Data, finalText: String) {
        try? pcmHandle?.close()
        pcmHandle = nil
        if !finalText.isEmpty {
            try? finalText.write(to: txtURL, atomically: true, encoding: .utf8)
        }
        do {
            try wav.write(to: wavURL)
            try? FileManager.default.removeItem(at: pcmURL)
            // La bitácora continua cede el micrófono mientras dictas. Adoptar
            // aquí el .wav recién cerrado es lo que evita que esa cesión deje un
            // hueco en la línea de tiempo. Un único punto para los ocho sitios
            // que cierran un dictado.
            ContinuoAudio.adoptar(wav: wavURL, instante: Date())
        } catch {
            Log.log(.sistema, "historial: no pude escribir el .wav (\(error.localizedDescription)) — conservo el .pcm crudo")
        }
    }

    /// Cierre sin dictado útil: borra los restos vacíos.
    func discard() {
        try? pcmHandle?.close()
        pcmHandle = nil
        try? FileManager.default.removeItem(at: pcmURL)
        try? FileManager.default.removeItem(at: txtURL)
    }

    /// Rescata dictados de sesiones que murieron a medias: cada .pcm huérfano
    /// se convierte en .wav reproducible. Se llama al arrancar la app.
    static func rescatarHuerfanos() {
        guard let files = FileManager.default.enumerator(at: historyDir, includingPropertiesForKeys: nil) else { return }
        var rescatados = 0
        for case let url as URL in files where url.pathExtension == "pcm" {
            guard let pcm = try? Data(contentsOf: url) else { continue }
            let wavURL = url.deletingPathExtension().appendingPathExtension("wav")
            // Menos de medio segundo de audio o ya rescatado: solo limpiar.
            if pcm.count > 16000 && !FileManager.default.fileExists(atPath: wavURL.path) {
                // Si el .wav no se puede escribir (disco lleno), conservar el
                // .pcm para intentarlo en el próximo arranque.
                guard (try? wavData(pcm: pcm).write(to: wavURL)) != nil else { continue }
                rescatados += 1
            }
            try? FileManager.default.removeItem(at: url)
        }
        if rescatados > 0 {
            Log.log(.sistema, "historial: \(rescatados) dictado(s) rescatado(s) de cierres a medias")
        }
    }

    /// PCM16 16 kHz mono → WAV con cabecera.
    static func wavData(pcm: Data) -> Data {
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
