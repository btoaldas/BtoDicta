import AppKit

// MARK: - Modo EN VIVO + colores por modo + detección difusa (sin dependencias)
//
// Tres piezas que trabajan juntas:
//   • ColorModo: cada modo tiene SU color en el notch (el usuario puede fijarlo en hex;
//     si no, los modos base tienen paleta fija y los propios un color determinista por
//     id — siempre el mismo). El fondo del notch se TIÑE suave con ese color.
//   • detectarFuzzy: capa de detección SIN dependencias (viaja en el Git): tolera
//     mal-escuchas por distancia de edición ("molde traductor", "moto agente") aunque
//     no haya Ollama/embeddings. Complementa la capa exacta y la semántica.
//   • ModoVivo: mientras HABLAS, evalúa los parciales (preview/streaming); si dices
//     "modo X" al inicio, el notch cambia YA de nombre+color ("te caché") y tú sigues
//     hablando. El texto final tiene prioridad; si no entiende el comando, el match
//     vivo de ESA sesión actúa como respaldo seguro.

enum ColorModo {
    /// Paleta fija de los modos base (distinguibles entre sí y sobre negro).
    private static let base: [String: NSColor] = [
        "dictado":   NSColor(calibratedWhite: 0.55, alpha: 1),
        "correo":    NSColor(calibratedRed: 0.36, green: 0.62, blue: 1.00, alpha: 1),  // azul
        "oficio":    NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.77, alpha: 1),  // teal
        "tarea":     NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.26, alpha: 1),  // naranja
        "nota":      NSColor(calibratedRed: 0.98, green: 0.83, blue: 0.30, alpha: 1),  // amarillo
        "traducir":  NSColor(calibratedRed: 0.42, green: 0.78, blue: 1.00, alpha: 1),  // celeste
        "resumir":   NSColor(calibratedRed: 0.78, green: 0.62, blue: 1.00, alpha: 1),  // lila
        "asistente": NSColor(calibratedRed: 0.62, green: 0.55, blue: 0.95, alpha: 1),  // violeta
        "buscar":    NSColor(calibratedRed: 0.42, green: 0.85, blue: 0.45, alpha: 1),  // verde
        "musica":    NSColor(calibratedRed: 1.00, green: 0.35, blue: 0.58, alpha: 1),  // rosa
        "aplicacion": NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.75, alpha: 1), // menta
        "agente":    NSColor(calibratedRed: 0.93, green: 0.45, blue: 0.85, alpha: 1),  // magenta
    ]
    /// Paleta para modos PROPIOS: color determinista por id (siempre el mismo).
    private static let propios: [NSColor] = [
        NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.80, green: 0.72, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.70, green: 0.90, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.45, alpha: 1),
        NSColor(calibratedRed: 0.60, green: 0.70, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.75, alpha: 1),
        NSColor(calibratedRed: 0.50, green: 0.90, blue: 0.75, alpha: 1),
        NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.55, alpha: 1),
    ]

    /// El color del modo: hex del usuario > paleta base > determinista por id.
    static func de(_ modo: Modo) -> NSColor {
        if let c = hex(modo.color) { return c }
        if let c = base[modo.id] { return c }
        // Hash determinista (djb2) del id → mismo color siempre, incluso tras reiniciar.
        var h: UInt64 = 5381
        for b in modo.id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return propios[Int(h % UInt64(propios.count))]
    }

    /// Tinte de FONDO del notch para el modo: el color al `alpha` sobre negro.
    /// Dictado = negro puro (sin tinte). "Distintas intensidades" según el modo.
    static func fondo(_ modo: Modo) -> NSColor {
        guard modo.id != "dictado" else { return .black }
        let c = de(modo).usingColorSpace(.deviceRGB) ?? de(modo)
        let t: CGFloat = 0.16
        return NSColor(calibratedRed: c.redComponent * t, green: c.greenComponent * t,
                       blue: c.blueComponent * t, alpha: 1)
    }

    static func hex(_ s: String) -> NSColor? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    static func aHex(_ c: NSColor) -> String {
        let d = c.usingColorSpace(.deviceRGB) ?? c
        return String(format: "#%02X%02X%02X", Int(d.redComponent * 255),
                      Int(d.greenComponent * 255), Int(d.blueComponent * 255))
    }
}

// MARK: Detección DIFUSA (sin embeddings, sin red — viaja en el Git)

enum ModoFuzzy {
    /// Tolerancia por distancia de edición: "molde traductor"→traducir, "moto agente"→
    /// agente, "modo tradutor"→traducir. Solo al INICIO del texto. Devuelve el modo y
    /// el texto sin la frase disparadora. Más conservador que la capa exacta (que corre
    /// antes): exige parecido fuerte por palabra.
    static func detectar(_ texto: String) -> (Modo, String)? {
        guard let match = ModoResolver.detectarDifuso(texto) else { return nil }
        return (match.modo, match.textoLimpio)
    }

    /// Mal-escuchas conocidas de la palabra "modo" (el STT las confunde seguido).
    private static let variantesModo = ModoResolver.palabrasModoSeguras

    /// Similitud 0-1 por distancia de Levenshtein relativa.
    static func similitud(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        // "modo" y sus mal-escuchas cuentan como iguales entre sí.
        if variantesModo.contains(a), variantesModo.contains(b) { return 1 }
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return 0 }
        let aa = Array(a.utf8), bb = Array(b.utf8)
        var prev = Array(0...bb.count)
        var cur = [Int](repeating: 0, count: bb.count + 1)
        for i in 1...aa.count {
            cur[0] = i
            for j in 1...bb.count {
                let cost = aa[i-1] == bb[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            swap(&prev, &cur)
        }
        let d = Double(prev[bb.count])
        return 1.0 - d / Double(max(n, m))
    }
}

// MARK: Modo EN VIVO (mientras hablas)

enum ModoVivo {
    private struct Estado {
        let sesion: UUID
        let catalogo: ModoCatalogo
        let aviso: (ModoMatch) -> Void
        var detectado: ModoMatch?
        var ultimoParcial = ""
        var candidatoFuzzy: ModoMatch?
        var repeticionesFuzzy = 0
        var pausaConfirmada = false
    }

    private static let lock = NSLock()
    private static var estado: Estado?

    /// Cada grabación posee su UUID. Un parcial o una respuesta semántica tardía
    /// de la grabación anterior queda descartado por identidad, no por timing.
    static func empezar(sesion: UUID, onCambio: @escaping (ModoMatch) -> Void) {
        lock.lock()
        estado = Estado(sesion: sesion, catalogo: ModoCatalogoCache.actual(), aviso: onCambio)
        lock.unlock()
    }

    /// Devuelve una COPIA del match de esta sesión y borra todo el estado. Así
    /// `deliver()` nunca puede recoger un modo viejo de archivo/cancelación/otro dictado.
    static func terminar(sesion: UUID) -> ModoMatch? {
        lock.lock(); defer { lock.unlock() }
        guard estado?.sesion == sesion else { return nil }
        let r = estado?.detectado
        estado = nil
        return r
    }

    static func cancelar(sesion: UUID) {
        lock.lock()
        if estado?.sesion == sesion { estado = nil }
        lock.unlock()
    }

    /// Evalúa solo la zona inicial configurable. Exacto cambia inmediatamente;
    /// fuzzy exige dos parciales estables para evitar parpadeos/falsos positivos.
    static func evaluar(_ parcial: String, sesion: UUID) {
        guard Config.modoVivo() else { return }
        lock.lock()
        guard var e = estado, e.sesion == sesion else { lock.unlock(); return }
        e.ultimoParcial = parcial
        let inicio = prefijo(parcial)
        var avisar: ModoMatch?
        if var m = ModoResolver.detectarExacto(inicio, catalogo: e.catalogo) {
            // No PISAR la confirmación por pausa: si el mismo comando sigue al frente,
            // el match re-construido hereda el flag (los parciales posteriores a la
            // pausa no deben degradar la prioridad ya ganada).
            if e.detectado?.firmaEfectiva == m.firmaEfectiva {
                m.confirmadoPorPausa = e.detectado?.confirmadoPorPausa ?? false
            } else if e.pausaConfirmada {
                m.confirmadoPorPausa = true   // la pausa confirmó ESTA sesión de comando
            }
            if e.detectado?.firmaEfectiva != m.firmaEfectiva { avisar = m }
            e.detectado = m
            e.candidatoFuzzy = nil; e.repeticionesFuzzy = 0
        } else if let m = ModoResolver.detectarDifuso(inicio, catalogo: e.catalogo) {
            if e.candidatoFuzzy?.firmaEfectiva == m.firmaEfectiva { e.repeticionesFuzzy += 1 }
            else { e.candidatoFuzzy = m; e.repeticionesFuzzy = 1 }
            if e.repeticionesFuzzy >= 2, e.detectado == nil {
                e.detectado = m; avisar = m
            }
        } else {
            e.candidatoFuzzy = nil; e.repeticionesFuzzy = 0
        }
        let callback = e.aviso
        estado = e
        lock.unlock()
        if let avisar { DispatchQueue.main.async { callback(avisar) } }
    }

    /// Tras una pausa real del audio confirma el límite del comando sin detener
    /// la grabación. Acepta un fuzzy aún no repetido y, como último nivel, hace
    /// UNA sola consulta semántica sobre el inicio (si el usuario la activó).
    @discardableResult
    static func confirmarPausa(sesion: UUID) -> Bool {
        guard Config.modoVivo(), Config.modoVivoPausa() else { return false }
        lock.lock()
        guard var e = estado, e.sesion == sesion else { lock.unlock(); return false }
        if e.pausaConfirmada { lock.unlock(); return true }
        guard !e.ultimoParcial.isEmpty else {
            lock.unlock(); return false
        }
        let inicio = prefijo(e.ultimoParcial)
        var match = e.detectado ?? e.candidatoFuzzy
        if match == nil { match = ModoResolver.detectarExacto(inicio, catalogo: e.catalogo) }
        if match == nil { match = ModoResolver.detectarDifuso(inicio, catalogo: e.catalogo) }
        if var match {
            e.pausaConfirmada = true
            match.confirmadoPorPausa = true
            e.detectado = match
            let callback = e.aviso
            estado = e
            lock.unlock()
            DispatchQueue.main.async { callback(match) }
            return true
        }
        let debeSemantico = Config.modoSemantico() && ModosStore.pareceComando(inicio)
        if debeSemantico { e.pausaConfirmada = true }
        estado = e
        lock.unlock()
        guard debeSemantico else { return false }
        ModosStore.detectarSemantico(inicio) { modo, limpio in
            guard let modo else { return }
            var m = ModoResolver.matchSemantico(texto: inicio, modo: modo, limpio: limpio)
            m.confirmadoPorPausa = true
            lock.lock()
            guard var actual = estado, actual.sesion == sesion else { lock.unlock(); return }
            actual.detectado = m
            let callback = actual.aviso
            estado = actual
            lock.unlock()
            DispatchQueue.main.async { callback(m) }
        }
        return true
    }

    private static func prefijo(_ texto: String) -> String {
        texto.split(whereSeparator: { $0.isWhitespace })
            .prefix(max(2, Config.modoVivoPalabras()))
            .joined(separator: " ")
    }
}

/// Regla pura del VAD de pausa. El audio/RMS vive en AppDelegate, pero la
/// decisión temporal se prueba sin micrófono ni esperas reales.
enum ModoPausaGate {
    static func debeConfirmar(ahora: Date, ultimaVoz: Date, huboVoz: Bool,
                              yaDisparada: Bool, segundos: Double) -> Bool {
        huboVoz && !yaDisparada && ahora.timeIntervalSince(ultimaVoz) >= segundos
    }
}
