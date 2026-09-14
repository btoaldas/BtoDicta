import Foundation
import AVFoundation

// MARK: - Dictados de mentira para probar de verdad
//
// Un fallo que solo aparece con audio largo no se caza dictando a mano: hay que
// hablar tres minutos, esperar, y repetir hasta que vuelva a pasar. Esto genera
// ese audio con la voz que macOS ya trae —gratis, sin red y sin API— en el
// MISMO formato que la aplicación manda a transcribir: 16 kHz, mono, 16 bits.
//
// No sustituye a probar dictando: sustituye a probar dictando VEINTE VECES.
enum VozSintetica {

    /// Frases con contenido y puntuación variada: un motor de transcripción se
    /// comporta distinto ante un tono plano que ante habla real.
    private static let frases = [
        "Esta es una prueba de duración para medir cuánto tarda la transcripción.",
        "El informe del mes pasado quedó pendiente de revisión por la dirección.",
        "¿Cuántos minutos de audio caben en una sola llamada a la interfaz?",
        "Anota la fecha, el número de oficio y el nombre completo del solicitante.",
        "Hay que comprobar la conexión antes de dar por caído un proveedor.",
        "La bitácora guarda el audio en crudo y lo comprime cuando termina.",
    ]

    /// Devuelve un WAV de aproximadamente `segundos`, listo para mandar a
    /// cualquier motor. SÍNCRONA a propósito, para poder encadenar pruebas sin
    /// anidar cierres: llámala desde una cola de fondo, nunca desde la
    /// principal, porque espera a que el sintetizador termine.
    static func wav(segundos: Double) -> Data? {
        guard segundos > 0 else { return nil }
        // Español de la máquina; si no hubiera, la que el sistema tenga por
        // defecto. Se habla algo rápido para no necesitar textos enormes.
        let voz = AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
            ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
        // ~2,5 palabras por segundo a ritmo normal; se pide de sobra y luego se
        // recorta al tamaño exacto, que es más fiable que acertar el texto.
        let palabrasNecesarias = Int(segundos * 3) + 20
        var texto = ""
        var i = 0
        while texto.split(separator: " ").count < palabrasNecesarias {
            texto += frases[i % frases.count] + " "
            i += 1
        }
        let u = AVSpeechUtterance(string: texto)
        u.voice = voz
        u.rate = AVSpeechUtteranceDefaultSpeechRate

        let destino = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                    sampleRate: Recorder.frecuenciaInterna,
                                    channels: 1, interleaved: true)
        guard let destino else { return nil }

        var pcm = Data()
        var conversor: AVAudioConverter?
        let objetivo = Int(segundos * Double(RedSeguridadDictado.bytesPorSegundo))
        let espera = DispatchSemaphore(value: 0)
        let sint = AVSpeechSynthesizer()
        sint.write(u) { buffer in
            guard let b = buffer as? AVAudioPCMBuffer else { espera.signal(); return }
            // Un buffer vacío es la señal de fin del sintetizador.
            guard b.frameLength > 0 else { espera.signal(); return }
            if conversor == nil { conversor = AVAudioConverter(from: b.format, to: destino) }
            guard let conv = conversor,
                  let salida = AVAudioPCMBuffer(pcmFormat: destino,
                                                frameCapacity: AVAudioFrameCount(
                                                    Double(b.frameLength) * destino.sampleRate / b.format.sampleRate) + 1024)
            else { return }
            var entregado = false
            var err: NSError?
            conv.convert(to: salida, error: &err) { _, estado in
                if entregado { estado.pointee = .noDataNow; return nil }
                entregado = true; estado.pointee = .haveData; return b
            }
            guard err == nil, let canal = salida.int16ChannelData else { return }
            pcm.append(Data(bytes: canal[0], count: Int(salida.frameLength) * 2))
        }
        // Tope de cordura: sintetizar tres minutos tarda segundos, no minutos.
        _ = espera.wait(timeout: .now() + max(30, segundos))
        guard pcm.count > 1_000 else { return nil }
        // Ajuste al tamaño pedido: se recorta lo que sobre y se repite lo que
        // haya si faltara, siempre en frontera de muestra (16 bits = 2 bytes).
        if pcm.count > objetivo {
            pcm = pcm.prefix(RedSeguridadDictado.par(objetivo))
        } else {
            let base = pcm
            while pcm.count < objetivo { pcm.append(base) }
            pcm = pcm.prefix(RedSeguridadDictado.par(objetivo))
        }
        return HistoryWriter.wavData(pcm: pcm)
    }
}
