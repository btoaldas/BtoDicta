import Foundation
import AVFoundation
import Accelerate

// MARK: - Coincidencia por AUDIO (experimental, opt-in)
//
// Idea: grabar tu voz diciendo un término ("Zentrix") y, al dictar,
// reconocer ese sonido aunque el motor escriba otra cosa. Es "reconocer
// tarareando": nunca hay match perfecto, se mide QUÉ TAN PARECIDO (distancia)
// y se compara contra un umbral.
//
// Motor: espectrograma mel (cómo se reparte la energía del sonido en el tiempo)
// + DTW (alinea dos audios aunque uno vaya más rápido). Todo local, sin modelos
// que descargar. Dependiente de UN hablante (tu voz) — el caso más fácil.
//
// NADA de esto corre si el flag "match_por_audio" está apagado (por defecto).

enum AudioMatch {
    static var dir: URL { Config.dir.appendingPathComponent("voces") }
    static let sr: Double = 16000
    static let frameLen = 400      // 25 ms @16k
    static let hop = 160           // 10 ms
    static let fftLen = 512
    static let nMel = 40
    /// Umbral por defecto (distancia DTW normalizada). Debajo = "es la palabra".
    /// Calibrado midiendo: misma palabra ≈2.6 (voz distinta), palabras
    /// diferentes ≈5.5+. 4.0 cae en medio, sesgado a evitar falsos positivos.
    /// Ajustable por el usuario tras medir con su propia voz.
    static let umbralDefecto: Float = 4.0

    // ---- Carpeta de muestras por término ----
    static func slug(_ s: String) -> String {
        let base = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let limpio = base.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(limpio).replacingOccurrences(of: "__", with: "_")
    }
    static func carpeta(_ termino: String) -> URL { dir.appendingPathComponent(slug(termino)) }
    static func muestras(_ termino: String) -> [URL] {
        let c = carpeta(termino)
        let files = (try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func nuevaMuestraURL(_ termino: String) -> URL {
        let c = carpeta(termino)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        // nombre por conteo (sin depender de la fecha, que no está disponible en scripts)
        let n = muestras(termino).count + 1
        return c.appendingPathComponent(String(format: "muestra-%02d.wav", n))
    }
    static func borrar(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    static func tieneMuestras(_ termino: String) -> Bool { !muestras(termino).isEmpty }

    // ---- Lectura de audio a mono 16k float ----
    static func leerSamples(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFmt = file.processingFormat
        guard let salida = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr,
                                         channels: 1, interleaved: false) else { return nil }
        guard let conv = AVAudioConverter(from: inFmt, to: salida) else { return nil }
        let cap = AVAudioFrameCount(file.length)
        guard cap > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: cap) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        let ratio = sr / inFmt.sampleRate
        let outCap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 1024)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: salida, frameCapacity: outCap) else { return nil }
        var entregado = false
        var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in
            if entregado { status.pointee = .noDataNow; return nil }
            entregado = true; status.pointee = .haveData; return inBuf
        }
        if err != nil { return nil }
        guard let ptr = outBuf.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuf.frameLength)))
    }

    // ---- Banco de filtros mel (precalculado una vez) ----
    static let melBanco: [[Float]] = construirMel()
    private static func hzAMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
    private static func melAHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
    private static func construirMel() -> [[Float]] {
        let bins = fftLen / 2 + 1          // 257
        let lo = hzAMel(0), hi = hzAMel(sr / 2)
        let puntos = (0...(nMel + 1)).map { melAHz(lo + (hi - lo) * Double($0) / Double(nMel + 1)) }
        let binHz = puntos.map { Int(floor(Double(fftLen + 1) * $0 / sr)) }
        var banco = Array(repeating: [Float](repeating: 0, count: bins), count: nMel)
        for m in 1...nMel {
            let izq = binHz[m - 1], cen = binHz[m], der = binHz[m + 1]
            if cen > izq { for k in izq..<cen where k < bins { banco[m-1][k] = Float(k - izq) / Float(cen - izq) } }
            if der > cen { for k in cen..<der where k < bins { banco[m-1][k] = Float(der - k) / Float(der - cen) } }
        }
        return banco
    }

    // ---- Rasgos: secuencia de vectores log-mel, con recorte de silencio y CMN ----
    // cmn=false para el audio del dictado: ahí el CMN se aplica por VENTANA
    // local en el spotting (si no, normalizar sobre toda la frase desalinea).
    static func rasgos(_ url: URL, cmn: Bool = true) -> [[Float]]? {
        guard let s = leerSamples(url), s.count >= frameLen else { return nil }
        let sam = recortarSilencio(s)
        guard sam.count >= frameLen else { return nil }

        var ventana = [Float](repeating: 0, count: frameLen)
        vDSP_hamm_window(&ventana, vDSP_Length(frameLen), 0)
        let log2n = vDSP_Length(9)      // 512
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }
        let bins = fftLen / 2 + 1

        var seq: [[Float]] = []
        var i = 0
        while i + frameLen <= sam.count {
            // ventana + pad a 512
            var frame = [Float](repeating: 0, count: fftLen)
            vDSP_vmul(Array(sam[i..<i+frameLen]), 1, ventana, 1, &frame, 1, vDSP_Length(frameLen))
            // FFT real
            var realp = [Float](repeating: 0, count: fftLen/2)
            var imagp = [Float](repeating: 0, count: fftLen/2)
            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftLen/2) { cp in
                            vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(fftLen/2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            // potencia por bin (257): |X|^2, con manejo del bin de Nyquist en imagp[0]
            var pot = [Float](repeating: 0, count: bins)
            pot[0] = realp[0] * realp[0]
            pot[bins - 1] = imagp[0] * imagp[0]
            for k in 1..<(fftLen/2) { pot[k] = realp[k]*realp[k] + imagp[k]*imagp[k] }
            // mel + log
            var mel = [Float](repeating: 0, count: nMel)
            for m in 0..<nMel {
                var acc: Float = 0
                vDSP_dotpr(melBanco[m], 1, pot, 1, &acc, vDSP_Length(bins))
                mel[m] = log(acc + 1e-6)
            }
            seq.append(mel)
            i += hop
        }
        guard !seq.isEmpty else { return nil }
        return cmn ? normalizarCMN(seq) : seq
    }

    /// Cepstral mean normalization: resta la media de cada coeficiente. Ayuda a
    /// que el mismo sonido con distinto micro/volumen quede parecido.
    private static func normalizarCMN(_ seq: [[Float]]) -> [[Float]] {
        let n = seq.count, d = seq[0].count
        var media = [Float](repeating: 0, count: d)
        for v in seq { for j in 0..<d { media[j] += v[j] } }
        for j in 0..<d { media[j] /= Float(n) }
        return seq.map { v in (0..<d).map { v[$0] - media[$0] } }
    }

    /// Recorta silencio al inicio/fin por energía (deja la palabra, no el aire).
    private static func recortarSilencio(_ s: [Float]) -> [Float] {
        let win = 160
        var energias: [Float] = []
        var i = 0
        while i + win <= s.count {
            var e: Float = 0; vDSP_measqv(Array(s[i..<i+win]), 1, &e, vDSP_Length(win))
            energias.append(e); i += win
        }
        guard let maxE = energias.max(), maxE > 0 else { return s }
        let umbral = maxE * 0.02
        let ini = energias.firstIndex { $0 > umbral } ?? 0
        let fin = energias.lastIndex { $0 > umbral } ?? (energias.count - 1)
        let a = max(0, ini * win), b = min(s.count, (fin + 1) * win)
        return a < b ? Array(s[a..<b]) : s
    }

    // ---- DTW normalizado entre dos secuencias de rasgos ----
    static func dtw(_ a: [[Float]], _ b: [[Float]]) -> Float {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return .greatestFiniteMagnitude }
        let inf = Float.greatestFiniteMagnitude
        var prev = [Float](repeating: inf, count: m + 1)   // fila i-1
        var curr = [Float](repeating: inf, count: m + 1)   // fila i
        prev[0] = 0                                         // D[0][0] = 0
        for i in 1...n {
            curr[0] = inf                                  // D[i][0] = inf
            for j in 1...m {
                let d = distEuclid(a[i-1], b[j-1])
                let mejor = min(prev[j], curr[j-1], prev[j-1])
                curr[j] = d + mejor
            }
            swap(&prev, &curr)                             // curr pasa a ser i-1
        }
        return prev[m] / Float(n + m)     // normaliza por largo del camino
    }
    private static func distEuclid(_ a: [Float], _ b: [Float]) -> Float {
        var dif = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &dif, 1, vDSP_Length(a.count))
        var s: Float = 0; vDSP_svesq(dif, 1, &s, vDSP_Length(a.count))
        return sqrt(s)
    }

    // ---- Evaluación: ¿el audio de prueba coincide con las muestras del término? ----
    /// Menor distancia entre el audio de prueba y CUALQUIER muestra del término.
    static func distancia(pruebaURL: URL, termino: String) -> Float? {
        guard let test = rasgos(pruebaURL) else { return nil }
        return distanciaRasgos(test, termino: termino)
    }
    static func distanciaRasgos(_ test: [[Float]], termino: String) -> Float? {
        let refs = muestras(termino).compactMap { rasgos($0) }
        guard !refs.isEmpty else { return nil }
        return refs.map { dtw(test, $0) }.min()
    }

    /// Umbral efectivo de "probar por voz" (palabra aislada).
    static func umbral() -> Float { Float(Config.umbralAudio() ?? Double(umbralDefecto)) }
    /// Raya del DICTADO real (subsequence DTW). Escala PROPIA (~8–13, más alta
    /// que "probar por voz") — calibrada con audio real del dueño del proyecto: dichas
    /// ≤10.46, no-dichas ≥10.49. Default conservador; ajustable.
    static let umbralDictadoDefecto: Float = 10.4
    static func umbralDictado() -> Float { Float(Config.umbralAudioDictado() ?? Double(umbralDictadoDefecto)) }

    // ---- Bitácora del DICTADO real (para calibrar la raya del dictado) ----
    static var dictadoURL: URL { dir.appendingPathComponent("dictado.jsonl") }
    static func registrarDictado(termino: String, dist: Float, corrigio: Bool, texto: String) {
        let iso = ISO8601DateFormatter().string(from: Date())
        let obj: [String: Any] = ["ts": iso, "termino": termino, "dist": Double(dist),
                                  "corrigio": corrigio, "raya": Double(umbralDictado()),
                                  "texto": String(texto.prefix(120))]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: dictadoURL.path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else { try? line.write(to: dictadoURL, atomically: true, encoding: .utf8) }
    }

    // ---- Bitácora de pruebas (para afinar el umbral con datos reales) ----
    // tipo: "correcta" = dijiste la palabra buena · "falsa" = dijiste algo
    // parecido/mal a propósito. Con eso se calcula el umbral SUGERIDO.
    static var pruebasURL: URL { dir.appendingPathComponent("pruebas.jsonl") }
    static func registrarPrueba(termino: String, dist: Float, umbral u: Float, caza: Bool, tipo: String) {
        let iso = ISO8601DateFormatter().string(from: Date())
        let obj: [String: Any] = ["ts": iso, "termino": termino, "dist": Double(dist),
                                  "umbral": Double(u), "caza": caza, "tipo": tipo]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = FileHandle(forWritingAtPath: pruebasURL.path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: pruebasURL, atomically: true, encoding: .utf8)
        }
        Log.log(.config, "prueba voz [\(tipo)]: \(termino) dist=\(String(format: "%.2f", dist)) raya=\(String(format: "%.2f", u)) → \(caza ? "caza ✅" : "no ❌")")
    }

    struct Fila { let termino: String; let dist: Float; let tipo: String }
    static func todasLasPruebas() -> [Fila] {
        guard let text = try? String(contentsOf: pruebasURL, encoding: .utf8) else { return [] }
        var out: [Fila] = []
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = j["termino"] as? String, let dist = j["dist"] as? Double else { continue }
            out.append(Fila(termino: t, dist: Float(dist), tipo: (j["tipo"] as? String) ?? ""))
        }
        return out
    }
    /// Distancias recientes de un término, separadas por tipo (para el resumen).
    static func recientesPorTipo(_ termino: String, tipo: String, n: Int = 15) -> [Float] {
        Array(todasLasPruebas().filter { $0.termino == termino && $0.tipo == tipo }.map { $0.dist }.suffix(n))
    }

    private static func percentil(_ xs: [Float], _ p: Double) -> Float {
        let s = xs.sorted(); if s.isEmpty { return 0 }
        let idx = max(0, min(s.count - 1, Int((Double(s.count - 1) * p).rounded())))
        return s[idx]
    }

    /// Umbral SUGERIDO a partir de TODAS las pruebas etiquetadas (todas las
    /// filas). La raya ideal cae entre lo alto de las "correctas" y lo bajo de
    /// las "falsas". Es distinto para cada persona: sale de TU voz.
    struct Sugerencia { let valor: Float; let corrHi: Float; let falsLo: Float
                        let nCorr: Int; let nFals: Int; let traslape: Bool }
    static func umbralSugerido() -> Sugerencia? {
        let filas = todasLasPruebas()
        let corr = filas.filter { $0.tipo == "correcta" }.map { $0.dist }
        let fals = filas.filter { $0.tipo == "falsa" }.map { $0.dist }
        guard corr.count >= 2, fals.count >= 2 else { return nil }
        let corrHi = percentil(corr, 0.85)   // casi todas las correctas por debajo
        let falsLo = percentil(fals, 0.15)   // casi todas las falsas por encima
        let traslape = corrHi >= falsLo
        // en medio del hueco; si se traslapan, sesgar a estricto (menos falsos +)
        let valor = traslape ? (corrHi + falsLo) / 2 : (corrHi + falsLo) / 2
        return Sugerencia(valor: valor, corrHi: corrHi, falsLo: falsLo,
                          nCorr: corr.count, nFals: fals.count, traslape: traslape)
    }

    /// Sugerido de la raya del DICTADO desde dictado.jsonl. "con" = el término
    /// aparece en el texto (lo dijiste y el motor acertó); "sin" = no aparece.
    static func umbralDictadoSugerido() -> Sugerencia? {
        guard let text = try? String(contentsOf: dictadoURL, encoding: .utf8) else { return nil }
        var con: [Float] = [], sin: [Float] = []
        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = j["termino"] as? String, let dist = j["dist"] as? Double,
                  let txt = j["texto"] as? String else { continue }
            if txt.range(of: t, options: .caseInsensitive) != nil { con.append(Float(dist)) }
            else { sin.append(Float(dist)) }
        }
        guard con.count >= 2, sin.count >= 2 else { return nil }
        let corrHi = percentil(con, 0.85), falsLo = percentil(sin, 0.15)
        let traslape = corrHi >= falsLo
        return Sugerencia(valor: (corrHi + falsLo) / 2, corrHi: corrHi, falsLo: falsLo,
                          nCorr: con.count, nFals: sin.count, traslape: traslape)
    }

    // ---- Spotting: ¿aparece el término DENTRO del audio del dictado? ----
    // Sin timestamps del motor: deslizo la muestra (ventana móvil) sobre el
    // audio completo y me quedo con el mejor calce (misma escala que probar
    // por voz, así la raya calibrada sirve). Devuelve la menor distancia.
    /// Rasgos del audio del dictado SIN CMN global (se normaliza por ventana).
    static func rasgosDeWav(_ wav: Data) -> [[Float]]? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("beto-dictado.wav")
        try? wav.write(to: tmp)
        return rasgos(tmp, cmn: false)
    }

    private static func spotMin(refs: [[[Float]]], dictado: [[Float]]) -> Float? {
        guard !refs.isEmpty, !dictado.isEmpty else { return nil }
        var mejor = Float.greatestFiniteMagnitude
        for ref in refs {
            let m = ref.count
            guard m >= 4, dictado.count >= max(4, m / 2) else { continue }
            let win = Int(Float(m) * 1.4)
            let hop = max(3, m / 4)
            var i = 0
            while i < dictado.count {
                let fin = min(dictado.count, i + win)
                if fin - i >= max(4, m / 2) {
                    // CMN LOCAL de la ventana → escala comparable a la referencia
                    mejor = min(mejor, dtw(ref, normalizarCMN(Array(dictado[i..<fin]))))
                }
                if fin >= dictado.count { break }
                i += hop
            }
        }
        return mejor == .greatestFiniteMagnitude ? nil : mejor
    }

    /// ¿El término (por sus muestras) suena DENTRO del audio del dictado?
    /// rasgosDictado debe venir SIN CMN (rasgosDeWav lo hace así).
    static func detectadoEnDictado(termino: String, rasgosDictado: [[Float]]) -> Float? {
        // refs crudos (sin CMN) para igualar al dictado (también crudo).
        let refs = muestras(termino).compactMap { rasgos($0, cmn: false) }
        guard !refs.isEmpty else { return nil }
        return spotSubseqMin(refs: refs, dictado: rasgosDictado)?.dist
    }

    /// Subsequence DTW: alinea la referencia a la MEJOR subventana del dictado
    /// (arranque y fin libres) — localiza la palabra sin ventana fija. Es la
    /// idea de "encontrar dónde encaja mejor". Normaliza por largo de referencia.
    /// Devuelve (distancia normalizada, columna final del mejor calce) para
    /// saber DÓNDE en el audio encaja mejor la referencia (→ colocar la palabra).
    private static func subseqDTW(ref: [[Float]], dictado: [[Float]]) -> (dist: Float, fin: Int) {
        let m = ref.count, n = dictado.count
        if m == 0 || n == 0 { return (.greatestFiniteMagnitude, 0) }
        let inf = Float.greatestFiniteMagnitude
        var prev = [Float](repeating: 0, count: n + 1)   // fila 0 = 0 en todo j (arranque libre)
        var curr = [Float](repeating: inf, count: n + 1)
        for i in 1...m {
            curr[0] = inf
            for j in 1...n {
                let d = distEuclid(ref[i-1], dictado[j-1])
                curr[j] = d + min(prev[j-1], prev[j], curr[j-1])
            }
            swap(&prev, &curr)
        }
        var best = inf, bestJ = 0
        for j in 1...n where prev[j] < best { best = prev[j]; bestJ = j }   // fin libre
        return (best / Float(m), bestJ)
    }
    /// (distancia, posición 0..1 dentro del audio) del mejor calce entre muestras.
    private static func spotSubseqMin(refs: [[[Float]]], dictado: [[Float]]) -> (dist: Float, pos: Float)? {
        guard !refs.isEmpty, !dictado.isEmpty else { return nil }
        var mejorD = Float.greatestFiniteMagnitude, mejorPos: Float = 0
        for ref in refs where ref.count >= 4 && dictado.count >= ref.count {
            let (d, fin) = subseqDTW(ref: ref, dictado: dictado)
            if d < mejorD { mejorD = d; mejorPos = Float(fin) / Float(dictado.count) }
        }
        return mejorD == .greatestFiniteMagnitude ? nil : (mejorD, mejorPos)
    }
    /// Método viejo (ventana fija) — para comparar en pruebas.
    static func detectadoViejo(termino: String, rasgosDictado: [[Float]]) -> Float? {
        let refs = muestras(termino).compactMap { rasgos($0) }
        guard !refs.isEmpty else { return nil }
        return spotMin(refs: refs, dictado: rasgosDictado)
    }

    /// Corrección combinada AUDIO + texto (opt-in, ≤ tope de segundos):
    /// para cada término con muestras, si su sonido aparece en el audio y NO
    /// está ya escrito, reemplaza la palabra del texto fonéticamente más cercana
    /// (la que el motor botó). Audio confirma, texto coloca. Devuelve el texto
    /// corregido y un registro de lo que hizo.
    static func corregirConAudio(texto: String, wav: Data, terminos: [String],
                                 siglas: Set<String> = []) -> (texto: String, cambios: [String]) {
        guard let dict = rasgosDeWav(wav) else { return (texto, []) }
        let u = umbralDictado()
        var resultado = texto
        var cambios: [String] = []
        for termino in terminos where tieneMuestras(termino) {
            guard let (d, pos) = spotSubseqMin(refs: muestras(termino).compactMap { rasgos($0, cmn: false) }, dictado: dict) else { continue }
            let ds = String(format: "%.2f", d)
            let yaEscrito = resultado.range(of: termino, options: .caseInsensitive) != nil
            var corrigio = false
            if !yaEscrito {
                // Coloca por POSICIÓN del audio (dónde encajó) + parecido. Para
                // siglas, por posición (no suenan parecido a las letras).
                if d <= u, let mala = palabraAReemplazar(en: resultado, termino: termino,
                                                         sigla: siglas.contains(termino), pos: pos) {
                    resultado = reemplazarPalabra(mala, por: termino, en: resultado)
                    corrigio = true
                    cambios.append("🔊 \(termino) (audio \(ds)\(siglas.contains(termino) ? " sigla" : "")): '\(mala)' → '\(termino)'")
                } else if d <= u {
                    cambios.append("🔊 \(termino) sonó a \(ds) pero no hallé palabra que reemplazar")
                } else if d <= u * 1.12 {
                    cambios.append("· \(termino) sonó a \(ds) (raya \(String(format: "%.2f", u)) → no corrige)")
                }
            }
            registrarDictado(termino: termino, dist: d, corrigio: corrigio, texto: texto)
        }
        return (resultado, cambios)
    }

    /// Elige la palabra del texto a reemplazar por el término, usando la
    /// POSICIÓN donde el audio encajó (pos 0..1). Palabra normal: la más
    /// parecida fonéticamente cerca de esa posición (o global). Sigla: la
    /// palabra rara más cercana a esa posición (las siglas no suenan a sus letras).
    private static func palabraAReemplazar(en texto: String, termino: String, sigla: Bool, pos: Float) -> String? {
        let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{N}]*")
        let ns = texto as NSString
        let ms = regex?.matches(in: texto, range: NSRange(location: 0, length: ns.length)) ?? []
        let palabras = ms.map { ns.substring(with: $0.range) }
        guard !palabras.isEmpty else { return nil }
        let n = palabras.count
        let objetivo = min(n - 1, max(0, Int((pos * Float(n)).rounded())))

        // Candidatas: no comunes, ≥2 letras, no el término mismo.
        func califica(_ w: String) -> Bool {
            w.count >= 2 && !Aprendizaje.esComun(w) && w.caseInsensitiveCompare(termino) != .orderedSame
        }
        if sigla {
            // Guarda anti-falsos: solo reemplaza una palabra cuya INICIAL
            // coincida con la de la sigla (deótico→D sí, aprobó→a no), y
            // cercana a donde sonó. Así no pisa palabras correctas.
            func inicial(_ s: String) -> Character? {
                s.folding(options: .diacriticInsensitive, locale: .current).lowercased().first
            }
            let ini = inicial(termino)
            var mejor: (String, Int)?     // (palabra, distancia a la posición)
            for (i, w) in palabras.enumerated()
            where califica(w) && abs(i - objetivo) <= 3 && inicial(w) == ini {
                let dist = abs(i - objetivo)
                if mejor == nil || dist < mejor!.1 { mejor = (w, dist) }
            }
            return mejor?.0     // nil si ninguna coincide en inicial → no toca
        }
        // palabra normal: fonética cerca de la posición; si no, global (viejo).
        let ct = Fonetica.codigo(termino)
        var cerca: (String, Int)?
        for (i, w) in palabras.enumerated() where abs(i - objetivo) <= 3 && califica(w) && w.count >= 3 {
            let fd = Fonetica.distancia(Fonetica.codigo(w), ct)
            if fd <= max(2, ct.count / 2), cerca == nil || fd < cerca!.1 { cerca = (w, fd) }
        }
        if let c = cerca { return c.0 }
        return palabraMasParecida(en: texto, a: termino)   // respaldo global
    }

    /// Palabra del texto con el sonido (Metaphone) más cercano al término.
    private static func palabraMasParecida(en texto: String, a termino: String) -> String? {
        let ct = Fonetica.codigo(termino)
        var mejor: (palabra: String, d: Int)?
        let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{N}]*")
        let ns = texto as NSString
        for m in regex?.matches(in: texto, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let w = ns.substring(with: m.range)
            guard w.count >= 3, !Aprendizaje.esComun(w),
                  w.caseInsensitiveCompare(termino) != .orderedSame else { continue }
            let d = Fonetica.distancia(Fonetica.codigo(w), ct)
            if mejor == nil || d < mejor!.d { mejor = (w, d) }
        }
        guard let mj = mejor, mj.d <= max(2, ct.count / 2) else { return nil }
        return mj.palabra
    }
    private static func reemplazarPalabra(_ vieja: String, por nueva: String, en texto: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: vieja)
        let patron = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return texto }
        let ns = NSRange(texto.startIndex..., in: texto)
        // solo la PRIMERA ocurrencia
        guard let m = regex.firstMatch(in: texto, range: ns), let r = Range(m.range, in: texto) else { return texto }
        return texto.replacingCharacters(in: r, with: nueva)
    }

    /// El término más cercano entre los que tienen muestras (para el flujo de
    /// dictado y el "probar por voz"). nil si nada supera el umbral.
    static func mejorCoincidencia(pruebaURL: URL, terminos: [String]) -> (termino: String, dist: Float)? {
        guard let test = rasgos(pruebaURL) else { return nil }
        var mejor: (String, Float)?
        for t in terminos where tieneMuestras(t) {
            if let d = distanciaRasgos(test, termino: t), mejor == nil || d < mejor!.1 { mejor = (t, d) }
        }
        guard let (t, d) = mejor, d <= umbral() else { return nil }
        return (t, d)
    }
}

// MARK: - Grabador de voz (para enrolar muestras y para "probar por voz")

final class GrabadorVoz: NSObject, ObservableObject {
    @Published var grabando = false
    private var rec: AVAudioRecorder?
    private(set) var ultimaURL: URL?

    private let ajustes: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    func iniciar(a url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        guard let r = try? AVAudioRecorder(url: url, settings: ajustes) else { return }
        rec = r; ultimaURL = url
        r.record()
        grabando = true
    }
    func detener() {
        rec?.stop(); rec = nil; grabando = false
    }
}
