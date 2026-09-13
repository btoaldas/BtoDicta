import Foundation

// MARK: - Resolución ÚNICA de modos
//
// Una decisión de modo deja de ser un par de globals sueltos. Cada coincidencia
// conserva qué frase ganó, cuántas palabras consumió, sus argumentos dinámicos
// (idioma/buscador), la confianza y la sesión de dictado a la que pertenece.

enum FuenteModo: String {
    case exacto = "voz"
    case difuso = "fuzzy"
    case gramatical
    case natural
    case planSemantico = "plan_semantico"
    case ia = "ia"
    case contexto
    case semantico
    case vivoExacto = "vivo_exacto"
    case vivoDifuso = "vivo_fuzzy"
    case manual
}

struct ModoMatch {
    var modo: Modo
    var fuente: FuenteModo
    let frase: String
    let tokensComando: [String]
    let palabrasConsumidas: Int
    let confianza: Double
    var confirmadoPorPausa: Bool
    let textoLimpio: String

    var firmaEfectiva: String {
        "\(modo.id)|\(modo.idiomaDestino)|\(modo.buscador)|\(palabrasConsumidas)"
    }
}

struct ModoContexto {
    let bundleId: String
    let nombre: String
    var url: String?
}

struct ModoAccionPlan {
    var modo: Modo
    var destinatario: String?
    /// Asunto explícito de un borrador de correo. Si queda vacío, el redactor
    /// puede devolver una línea `ASUNTO:` y el ejecutor la extrae localmente.
    var asunto: String?
    /// Nombre sugerido para una creación local; la ubicación siempre la elige
    /// el usuario mediante NSSavePanel.
    var nombreArchivo: String?

    init(modo: Modo, destinatario: String?, asunto: String? = nil,
         nombreArchivo: String? = nil) {
        self.modo = modo
        self.destinatario = destinatario
        self.asunto = asunto
        self.nombreArchivo = nombreArchivo
    }
}

/// Un plan puede tener N transformaciones y N acciones. `accion` se conserva como
/// compatibilidad de lectura para el código/herramientas antiguas que solo conocían
/// una acción final.
struct ModoCadena {
    let transforms: [Modo]
    let acciones: [ModoAccionPlan]
    let contenido: String

    var accion: Modo? { acciones.first?.modo }

    init(transforms: [Modo], accion: Modo?, contenido: String) {
        self.transforms = transforms
        self.acciones = accion.map { [ModoAccionPlan(modo: $0, destinatario: nil)] } ?? []
        self.contenido = contenido
    }

    init(transforms: [Modo], acciones: [ModoAccionPlan], contenido: String) {
        self.transforms = transforms
        self.acciones = acciones
        self.contenido = contenido
    }

    var etapas: [Modo] { transforms + acciones.map(\.modo) }
}

struct ModoPreguntaPlan {
    let cadena: ModoCadena
    let descripcion: String
    let detalles: [String]
    let alternativas: [String]
    let fuente: FuenteModo
    let confianza: Double
}

struct ModoResolucion {
    let modo: Modo
    let texto: String
    let fuente: FuenteModo
    let match: ModoMatch?
}

enum ResultadoModo {
    case cadena(ModoCadena)
    case modo(ModoResolucion)
    /// La capa gramatical entendió la intención pero es AMBIGUA ("quiero traducir…"):
    /// la app muestra el mini-modal "¿Cambiar a modo X?" (fn = sí) antes de despachar.
    case preguntar(ModoMatch)
    /// Cadena COLOQUIAL detectada ("envía un correo que traduzca lo siguiente…"):
    /// SIEMPRE se confirma con el modal ("¿TRADUCIR y enviar por CORREO? fn = sí").
    case preguntarCadena(ModoCadena, descripcion: String)
    /// Pedido natural o semántico convertido en un plan de 1..N etapas. Nunca
    /// ejecuta acciones externas sin que el usuario confirme la propuesta.
    case preguntarPlan(ModoPreguntaPlan)
}

struct ModoCatalogo {
    struct Disparador {
        let modo: Modo
        let frase: String
        let tokens: [String]
    }

    let modos: [Modo]
    let exactos: [Disparador]
    let difusos: [Disparador]

    init(modos: [Modo]) {
        self.modos = modos
        var ex: [Disparador] = []
        var di: [Disparador] = []
        for modo in modos where modo.id != "dictado"
            && (modo.base != "aplicacion" || Config.modoAplicaciones()) {
            let frases = ModosStore.frasesVoz(modo)
            var vistos = Set<String>()
            for frase in frases {
                let toks = ModoResolver.tokensNormalizados(frase)
                guard !toks.isEmpty else { continue }
                let firma = toks.joined(separator: " ")
                guard vistos.insert(firma).inserted else { continue }
                let d = Disparador(modo: modo, frase: frase, tokens: toks)
                ex.append(d); di.append(d)
            }
            // Vaciar "Frases de voz" significa SIN voz. El nombre automático solo
            // complementa al fuzzy cuando el modo sí tiene activación por voz.
            if !frases.isEmpty {
                let frase = "modo \(modo.nombre)"
                let toks = ModoResolver.tokensNormalizados(frase)
                let firma = toks.joined(separator: " ")
                if vistos.insert(firma).inserted {
                    di.append(Disparador(modo: modo, frase: frase, tokens: toks))
                }
            }
        }
        // Compatibilidad: versiones anteriores podían crear un modo Acción
        // “Música” con la misma frase exacta “modo música”. A igualdad de largo,
        // el modo dedicado nuevo gana; los alias exclusivos del modo viejo siguen
        // funcionando. Sin este desempate el resultado dependía del orden del JSON.
        func antes(_ a: Disparador, _ b: Disparador) -> Bool {
            if a.tokens.count != b.tokens.count { return a.tokens.count > b.tokens.count }
            let aMusica = a.modo.id == "musica", bMusica = b.modo.id == "musica"
            if aMusica != bMusica { return aMusica }
            return false
        }
        exactos = ex.sorted(by: antes)
        difusos = di.sorted(by: antes)
    }
}

/// El catálogo compilado se reutiliza. Se invalida al guardar Modos, de modo que
/// editar una frase/color/modo se refleja en el próximo parcial sin releer JSON.
enum ModoCatalogoCache {
    private static let lock = NSLock()
    private static var cache: ModoCatalogo?
    private static var generacion = 0   // sube en cada invalidar(): una invalidación que
                                        // llegue MIENTRAS otro hilo construye no se pierde

    static func actual() -> ModoCatalogo {
        lock.lock()
        if let cache { lock.unlock(); return cache }
        let gen = generacion
        lock.unlock()
        let nuevo = ModoCatalogo(modos: ModosStore.todos())
        lock.lock()
        if cache == nil, generacion == gen { cache = nuevo }
        let salida = cache ?? nuevo
        lock.unlock()
        return salida
    }

    static func invalidar() {
        lock.lock(); cache = nil; generacion += 1; lock.unlock()
    }
}

enum ModoResolver {
    /// Solo variantes observadas/decididas. Una palabra común parecida ("todo",
    /// "moda") NO abre la puerta al fuzzy. Los alias exactos del usuario sí valen.
    static let palabrasModoSeguras: Set<String> =
        ["modo", "mudo", "molde", "moto", "modho", "moldo", "mode", "modos", "mod", "moro"]

    static func tokenNormalizado(_ s: String) -> String {
        let bordes = CharacterSet.punctuationCharacters
            .union(.symbols)
            .union(.whitespacesAndNewlines)
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "es"))
            .trimmingCharacters(in: bordes)
    }

    static func tokensNormalizados(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace })
            .map { tokenNormalizado(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func tokensOriginales(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func limpiar(_ originales: [String], desde indice: Int) -> String {
        guard indice < originales.count else { return "" }
        return originales.dropFirst(indice).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;\n").union(.whitespacesAndNewlines))
    }

    private static func conArgumento(_ base: Modo, normalizados: [String],
                                     desde inicio: Int) -> (Modo, Int) {
        var modo = base
        guard inicio < normalizados.count else { return (modo, inicio) }
        var candidato = inicio
        let fillers: Set<String>
        let reconocer: (String) -> String?
        if modo.base == "traducir" {
            fillers = ["a", "al"]
            reconocer = Idiomas.reconocer
        } else if modo.base == "buscar" {
            fillers = ["en"]
            reconocer = Buscadores.reconocer
        } else if modo.base == "musica" {
            fillers = ["en", "con"]
            reconocer = { Musica.reconocerProveedor(en: $0) }
        } else if modo.base == "aplicacion" {
            guard Config.modoAplicaciones() else { return (modo, inicio) }
            switch AplicacionesMac.resolverPrefijo(Array(normalizados.dropFirst(inicio))) {
            case .encontrada(let match):
                return (AplicacionesMac.aplicar(match, a: modo), inicio + match.palabrasConsumidas)
            case .ambiguas, .ninguna:
                // El ejecutor conserva el texto y puede mostrar las alternativas;
                // aquí nunca consume a ciegas una palabra que podría ser contenido.
                return (modo, inicio)
            }
        } else { return (modo, inicio) }

        if fillers.contains(normalizados[candidato]), candidato + 1 < normalizados.count {
            candidato += 1
        }
        var consumidas = candidato + 1
        var valor = reconocer(normalizados[candidato])
        if modo.base == "musica", candidato + 1 < normalizados.count {
            let dos = normalizados[candidato] + " " + normalizados[candidato + 1]
            if let p = Musica.reconocerProveedorCompuesto(dos) {
                valor = p; consumidas = candidato + 2
            }
        }
        guard let valor else { return (modo, inicio) }
        if modo.base == "traducir" { modo.idiomaDestino = valor }
        else if modo.base == "musica" { modo.musicaProveedor = valor }
        else { modo.buscador = valor }
        return (modo, consumidas)
    }

    private static func construir(_ disparador: ModoCatalogo.Disparador,
                                  texto: String, confianza: Double,
                                  fuente: FuenteModo) -> ModoMatch {
        // OJO: la detección matchea sobre tokens FILTRADOS (sin tokens de pura
        // puntuación, p.ej. el "- " que emite Whisper), pero el recorte va sobre los
        // ORIGINALES. Mapeamos índices filtrado→original para no cortar corrido.
        let originales = tokensOriginales(texto)
        let normPorOriginal = originales.map(tokenNormalizado)
        let idxValidos = normPorOriginal.indices.filter { !normPorOriginal[$0].isEmpty }
        let filtrados = idxValidos.map { normPorOriginal[$0] }
        let base = min(disparador.tokens.count, filtrados.count)
        let (modo, consumidasFiltrado) = conArgumento(disparador.modo,
                                                      normalizados: filtrados, desde: base)
        let corteOriginal = consumidasFiltrado == 0 ? 0
            : (consumidasFiltrado <= idxValidos.count ? idxValidos[consumidasFiltrado - 1] + 1
                                                      : originales.count)
        return ModoMatch(modo: modo, fuente: fuente, frase: disparador.frase,
                         tokensComando: Array(filtrados.prefix(consumidasFiltrado)),
                         palabrasConsumidas: corteOriginal, confianza: confianza,
                         confirmadoPorPausa: false,
                         textoLimpio: limpiar(originales, desde: corteOriginal))
    }

    static func detectarExacto(_ texto: String, catalogo: ModoCatalogo = ModoCatalogoCache.actual()) -> ModoMatch? {
        let entrada = tokensNormalizados(texto)
        guard !entrada.isEmpty else { return nil }
        for d in catalogo.exactos where d.tokens.count <= entrada.count {
            if Array(entrada.prefix(d.tokens.count)) == d.tokens {
                return construir(d, texto: texto, confianza: 1, fuente: .exacto)
            }
        }
        return nil
    }

    static func detectarDifuso(_ texto: String, catalogo: ModoCatalogo = ModoCatalogoCache.actual()) -> ModoMatch? {
        let entrada = tokensNormalizados(texto)
        guard let primera = entrada.first, palabrasModoSeguras.contains(primera) else { return nil }

        struct Candidato { let d: ModoCatalogo.Disparador; let score: Double }
        var porModo: [String: Candidato] = [:]
        for d in catalogo.difusos where d.tokens.count <= entrada.count {
            guard let f = d.tokens.first, palabrasModoSeguras.contains(f) else { continue }
            var total = 0.0
            var valido = true
            for (i, palabra) in d.tokens.enumerated() {
                let s = i == 0 ? 1.0 : ModoFuzzy.similitud(palabra, entrada[i])
                if s < 0.72 { valido = false; break }
                total += s
            }
            guard valido else { continue }
            let score = total / Double(d.tokens.count)
            if score > 0.84, score > (porModo[d.modo.id]?.score ?? 0) {
                porModo[d.modo.id] = Candidato(d: d, score: score)
            }
        }
        let orden = porModo.values.sorted { $0.score > $1.score }
        guard let mejor = orden.first else { return nil }
        // Si dos modos distintos están casi empatados, no adivinar. Un match
        // prácticamente perfecto sí es suficientemente inequívoco.
        if let segundo = orden.dropFirst().first,
           mejor.score < 0.98, mejor.score - segundo.score < 0.04 { return nil }
        return construir(mejor.d, texto: texto, confianza: mejor.score, fuente: .difuso)
    }

    /// Alinea la frase captada EN VIVO contra el texto final usando una ventana
    /// variable. Tolera que el STT una/quite una palabra, sin asumir "siempre 2".
    static func aplicarVivo(_ vivo: ModoMatch, al texto: String) -> ModoMatch {
        let originales = tokensOriginales(texto)
        let entrada = originales.map(tokenNormalizado)
        let esperado = vivo.tokensComando
        guard !entrada.isEmpty, !esperado.isEmpty else {
            var r = vivo; r.fuente = vivo.fuente == .exacto ? .vivoExacto : .vivoDifuso
            return ModoMatch(modo: r.modo, fuente: r.fuente, frase: r.frase,
                             tokensComando: r.tokensComando, palabrasConsumidas: 0,
                             confianza: r.confianza, confirmadoPorPausa: r.confirmadoPorPausa,
                             textoLimpio: texto)
        }

        // El STT final puede COMERSE la palabra "modo", deformarla, o unir/quitar una
        // palabra. Probamos variantes del comando esperado (con y sin la palabra-modo)
        // contra ventanas del inicio de la entrada, y nos quedamos con la mejor
        // alineación. Umbral moderado: la alineación protege y el fallback conserva todo.
        var variantes: [[String]] = [esperado]
        if palabrasModoSeguras.contains(esperado[0]), esperado.count > 1 {
            variantes.append(Array(esperado.dropFirst()))   // final sin "modo"
        }
        var mejor: (n: Int, score: Double)?
        for variante in variantes {
            let minimo = max(1, variante.count - 2)
            let maximo = min(entrada.count, variante.count + 2)
            guard minimo <= maximo else { continue }
            for n in minimo...maximo {
                let score = similitudSecuencia(variante, Array(entrada.prefix(n)))
                if score > (mejor?.score ?? 0) { mejor = (n, score) }
            }
        }
        guard let alineado = mejor, alineado.score >= 0.66 else {
            return ModoMatch(modo: vivo.modo,
                             fuente: vivo.fuente == .exacto ? .vivoExacto : .vivoDifuso,
                             frase: vivo.frase, tokensComando: vivo.tokensComando,
                             palabrasConsumidas: 0, confianza: vivo.confianza,
                             confirmadoPorPausa: vivo.confirmadoPorPausa, textoLimpio: texto)
        }
        // Si el parcial vivo terminó antes de oír el argumento, el final todavía
        // puede aportar "quichua"/"wikipedia" justo después de la frase.
        let resuelto: (Modo, Int)
        if vivo.modo.base == "aplicacion", !vivo.modo.appBundleId.isEmpty {
            // El argumento (Word/Excel/…) ya formaba parte de tokensComando y de
            // la alineación. No interpretes la primera palabra del CONTENIDO como
            // una segunda aplicación.
            resuelto = (vivo.modo, alineado.n)
        } else {
            resuelto = conArgumento(vivo.modo, normalizados: entrada, desde: alineado.n)
        }
        let (modo, consumidas) = resuelto
        return ModoMatch(modo: modo,
                         fuente: vivo.fuente == .exacto ? .vivoExacto : .vivoDifuso,
                         frase: vivo.frase,
                         tokensComando: Array(entrada.prefix(consumidas)),
                         palabrasConsumidas: consumidas,
                         confianza: min(vivo.confianza, alineado.score),
                         confirmadoPorPausa: vivo.confirmadoPorPausa,
                         textoLimpio: limpiar(originales, desde: consumidas))
    }

    private static func similitudSecuencia(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = (0...b.count).map(Double.init)
        var cur = [Double](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = Double(i)
            for j in 1...b.count {
                let sustitucion = 1.0 - ModoFuzzy.similitud(a[i - 1], b[j - 1])
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + sustitucion)
            }
            swap(&prev, &cur)
        }
        return max(0, 1 - prev[b.count] / Double(max(a.count, b.count)))
    }

    // MARK: Capa GRAMATICAL (morfología del verbo del modo, sin dependencias)
    //
    // Reconoce el VERBO del modo en cualquier conjugación al inicio: "tradúceme esto",
    // "traduce al inglés", "quiero traducir…", "búscame en google…", "apúntame como
    // tarea…". Dos niveles de certeza:
    //   • .directo   — imperativo del verbo AL INICIO ("tradúceme esto…"): cambia ya.
    //   • .preguntar — intención indirecta ("quiero traducir algo…"): la app muestra
    //     el mini-modal "¿Cambiar a modo X?" (fn = sí) antes de despachar.

    enum CertezaGramatical { case directo, preguntar }

    /// Raíz verbal + sinónimos de intención por modo BASE (los propios heredan por base).
    private static func stemsDe(_ modo: Modo) -> [String] {
        switch modo.id {
        case "traducir": return ["traduc", "traduzc"]
        case "buscar": return ["busc", "busq", "googl"]
        case "musica": return ["music", "cancion", "reproduc", "pon"]
        case "tarea": return ["tarea"]
        case "nota": return ["nota", "apunt", "anot"]
        case "correo": return ["correo", "mail"]
        case "agente": return ["agente", "pregunt", "consult"]
        case "asistente": return ["asistent", "respond"]
        case "oficio": return ["oficio"]
        default:
            // Modo propio: la raíz de su nombre (≥4 letras) — "Resumir" → "resum".
            let n = tokenNormalizado(modo.nombre)
            return n.count >= 4 ? [String(n.prefix(max(4, n.count - 2)))] : []
        }
    }

    private static let prefijosIntencion: Set<String> =
        ["quiero", "quisiera", "necesito", "puedes", "podrias", "hazme", "ayudame", "dale", "porfa", "vamos"]
    private static let fillersPostVerbo: Set<String> =
        ["me", "esto", "eso", "lo", "la", "siguiente", "como", "una", "un", "de", "por", "favor"]

    static func detectarGramatical(_ texto: String,
                                   catalogo: ModoCatalogo = ModoCatalogoCache.actual())
        -> (match: ModoMatch, certeza: CertezaGramatical)? {
        let originales = tokensOriginales(texto)
        let normPorOriginal = originales.map(tokenNormalizado)
        let idxValidos = normPorOriginal.indices.filter { !normPorOriginal[$0].isEmpty }
        let filtrados = idxValidos.map { normPorOriginal[$0] }
        guard filtrados.count >= 2 else { return nil }   // comando + algo de contenido

        // Zona de arranque: token 0, o token 1 si el 0 es un prefijo de intención.
        var pos = 0
        var certeza = CertezaGramatical.directo
        if prefijosIntencion.contains(filtrados[0]) { pos = 1; certeza = .preguntar }
        guard pos < filtrados.count else { return nil }
        let token = filtrados[pos]
        guard token.count >= 4 else { return nil }

        for modo in catalogo.modos where modo.id != "dictado" {
            for stem in stemsDe(modo) where token.hasPrefix(stem) && token != stem + "cion" {
                // El TOKEN debe ser forma del verbo/nombre, no otra palabra que empiece
                // igual por azar: exige que tras el stem solo queden ≤5 letras.
                guard token.count - stem.count <= 5 else { continue }
                var modoElegido = modo
                var cert = certeza
                // El sustantivo de modo PURO al inicio ("tarea comprar pan") es ambiguo;
                // una forma VERBAL ("apúntame…") es intención clara.
                let nombreLiteral = tokenNormalizado(modo.nombre)
                if pos == 0, token == nombreLiteral { cert = .preguntar }
                // Consumir: comando + fillers + argumento (idioma/buscador).
                var fin = pos + 1
                while fin < filtrados.count, fillersPostVerbo.contains(filtrados[fin]) { fin += 1 }
                // "apúntame como TAREA…", "guárdame como NOTA…": el sustantivo de modo
                // EXPLÍCITO tras el verbo manda sobre el stem del verbo.
                if fin < filtrados.count {
                    let destino = filtrados[fin]
                    if let otro = catalogo.modos.first(where: {
                        $0.id != "dictado" && tokenNormalizado($0.nombre) == destino
                    }) { modoElegido = otro; fin += 1 }
                }
                let (conArg, consumidas) = conArgumento(modoElegido, normalizados: filtrados, desde: fin)
                let corteOriginal = consumidas == 0 ? 0
                    : (consumidas <= idxValidos.count ? idxValidos[consumidas - 1] + 1 : originales.count)
                let limpio = limpiar(originales, desde: corteOriginal)
                guard !limpio.isEmpty else { continue }   // sin contenido no vale la pena
                let m = ModoMatch(modo: conArg, fuente: .gramatical, frase: "gram:\(stem)",
                                  tokensComando: Array(filtrados.prefix(consumidas)),
                                  palabrasConsumidas: corteOriginal,
                                  confianza: cert == .directo ? 0.9 : 0.6,
                                  confirmadoPorPausa: false, textoLimpio: limpio)
                return (m, cert)
            }
        }
        return nil
    }

    // MARK: Cadena COLOQUIAL (múltiples intenciones sin decir "modo")
    //
    // "Por favor, envía un correo que traduzca lo siguiente: …", "tradúceme esto al
    // inglés y mándalo por whatsapp…". Reglas de seguridad: (1) el PRIMER verbo de
    // intención debe estar al arranque real de la orden (tras cortesías), (2) hacen
    // falta ≥2 intenciones distintas, (3) NUNCA ejecuta directo — SIEMPRE pregunta
    // con el modal. El orden de ejecución es fijo: transforms → acción (da igual el
    // orden en que lo digas: "correo que traduzca" = traducir y luego correo).

    private static let cortesias: Set<String> = ["por", "favor", "porfa", "porfavor", "oye", "hey", "btodicta"]
    private static let verbosEnvio: Set<String> = ["envia", "enviar", "enviame", "envialo", "enviaselo",
        "manda", "mandar", "mandame", "mandalo", "mandaselo", "mandale", "escribe", "escribele", "redacta"]
    private static let mediosAccion: [String: String] = [
        "correo": "correo", "mail": "correo", "email": "correo",
        "whatsapp": "whatsapp", "wasap": "whatsapp", "guasap": "whatsapp",
        "outlook": "outlook", "mensaje": "mensajes", "mensajes": "mensajes",
    ]
    private static let delimitadores: Set<String> = ["siguiente", "esto", "texto", "dice", "diga"]

    static func detectarCadenaColoquial(_ texto: String,
                                        catalogo: ModoCatalogo = ModoCatalogoCache.actual())
        -> (cadena: ModoCadena, descripcion: String)? {
        let originales = tokensOriginales(texto)
        let normPorOriginal = originales.map(tokenNormalizado)
        let idxValidos = normPorOriginal.indices.filter { !normPorOriginal[$0].isEmpty }
        let filtrados = idxValidos.map { normPorOriginal[$0] }
        guard filtrados.count >= 4 else { return nil }
        // La palabra "modo" al inicio pertenece a la cadena CLÁSICA (detectarCadena).
        if palabrasModoSeguras.contains(filtrados[0]) { return nil }

        let zona = min(filtrados.count, 14)
        var transforms: [Modo] = []
        var accion: Modo?
        var idioma: String?
        var ultimoComando = -1     // índice (filtrado) del último token de la orden
        var primeraIntencion = -1

        var i = 0
        while i < zona {
            let t = filtrados[i]
            if let idi = Idiomas.reconocer(t) { idioma = idi; ultimoComando = max(ultimoComando, i); i += 1; continue }
            // Transform: traducir (u otro modo transform por stem de nombre).
            if t.count >= 5, (t.hasPrefix("traduc") || t.hasPrefix("traduzc")) {
                if !transforms.contains(where: { $0.id == "traducir" }) {
                    transforms.append(ModosStore.modo("traducir"))
                }
                if primeraIntencion < 0 { primeraIntencion = i }
                ultimoComando = max(ultimoComando, i); i += 1; continue
            }
            // Acción: verbo de envío ("envía", "mándalo") o medio directo ("correo", "whatsapp").
            if verbosEnvio.contains(t) {
                if primeraIntencion < 0 { primeraIntencion = i }
                ultimoComando = max(ultimoComando, i); i += 1; continue
            }
            if let medio = mediosAccion[t] {
                accion = Modo(id: "cadena-\(medio)", nombre: Acciones.nombre(medio),
                              icono: "bolt.fill", base: "accion", accion: medio)
                if primeraIntencion < 0 { primeraIntencion = i }
                ultimoComando = max(ultimoComando, i); i += 1; continue
            }
            i += 1
        }

        // Seguridad: ≥2 intenciones (transform + acción) y la PRIMERA al arranque real
        // (tras cortesías). "la tarea del agente es enviar un correo" no arranca así.
        guard !transforms.isEmpty, accion != nil else { return nil }
        var arranque = 0
        while arranque < filtrados.count, cortesias.contains(filtrados[arranque]) { arranque += 1 }
        guard primeraIntencion >= 0, primeraIntencion <= arranque + 1 else { return nil }
        guard ultimoComando >= 0 else { return nil }

        if let idioma { for j in transforms.indices where transforms[j].base == "traducir" { transforms[j].idiomaDestino = idioma } }

        // Contenido: tras el último token de la orden, saltando fillers/delimitadores
        // ("lo siguiente", "que dice", "esto:").
        var corte = ultimoComando + 1
        while corte < filtrados.count,
              fillersPostVerbo.contains(filtrados[corte]) || delimitadores.contains(filtrados[corte])
              || cortesias.contains(filtrados[corte]) || filtrados[corte] == "que" || filtrados[corte] == "y" {
            corte += 1
        }
        let corteOriginal = corte == 0 ? 0
            : (corte <= idxValidos.count ? idxValidos[corte - 1] + 1 : originales.count)
        let contenido = limpiar(originales, desde: corteOriginal)
        guard !contenido.isEmpty else { return nil }   // orden sin contenido no vale la pena

        let partes = transforms.map { $0.base == "traducir" ? "TRADUCIR\($0.idiomaDestino.isEmpty ? "" : " al \($0.idiomaDestino)")" : $0.nombre.uppercased() }
        let desc = partes.joined(separator: ", ") + " y " + (accion!.nombre.lowercased())
        return (ModoCadena(transforms: transforms, accion: accion, contenido: contenido), desc)
    }

    static func matchSemantico(texto: String, modo: Modo, limpio: String,
                               confianza: Double = 0) -> ModoMatch {
        let todos = tokensNormalizados(texto)
        let contenido = tokensNormalizados(limpio)
        let consumidas = max(1, todos.count - contenido.count)
        return ModoMatch(modo: modo, fuente: .semantico, frase: "semántico",
                         tokensComando: Array(todos.prefix(consumidas)),
                         palabrasConsumidas: consumidas, confianza: confianza,
                         confirmadoPorPausa: false, textoLimpio: limpio)
    }

    private static func planSemantico(_ r: ModosStore.DeteccionSemantica,
                                      catalogo: ModoCatalogo) -> ModoPreguntaPlan? {
        guard let modo = r.modo,
              r.textoLimpio.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        let cadena: ModoCadena
        if modo.base == "accion" || modo.base == "buscar" || modo.base == "aplicacion" || modo.base == "musica" {
            cadena = ModoCadena(transforms: [],
                                acciones: [ModoAccionPlan(modo: modo, destinatario: nil)],
                                contenido: r.textoLimpio)
        } else {
            cadena = ModoCadena(transforms: [modo], acciones: [], contenido: r.textoLimpio)
        }
        var alternativas: [String] = []
        if let segundo = r.segundoId,
           let m2 = catalogo.modos.first(where: { $0.id == segundo }) {
            alternativas.append(ModoPlanificador.descripcionEtapa(m2))
        }
        return ModoPlanificador.pregunta(para: cadena, fuente: .planSemantico,
                                          confianza: r.score, alternativas: alternativas)
    }

    /// Orden declarado y testeable:
    /// cadena explícita > exacto > difuso > pedido natural > vivo confirmado por
    /// pausa > semántica/IA > contexto > respaldo vivo > modo manual congelado.
    static func resolver(texto: String, modoBase: Modo, contexto: ModoContexto?,
                         vivo: ModoMatch?, completion: @escaping (ResultadoModo) -> Void) {
        if Config.modoPorVoz(), let c = ModosStore.detectarCadena(texto) {
            completion(.cadena(c))
            return
        }
        let catalogo = ModoCatalogoCache.actual()
        if Config.modoPorVoz(), let m = detectarExacto(texto, catalogo: catalogo) {
            completion(.modo(ModoResolucion(modo: m.modo, texto: m.textoLimpio,
                                            fuente: .exacto, match: m)))
            return
        }
        if Config.modoPorVoz(), let m = detectarDifuso(texto, catalogo: catalogo) {
            completion(.modo(ModoResolucion(modo: m.modo, texto: m.textoLimpio,
                                            fuente: .difuso, match: m)))
            return
        }
        // CAPTURA/GRABACIÓN NATIVA: tiene gramática cerrada, herramienta propia
        // y confirmación obligatoria. Si su interruptor está encendido, una orden
        // inequívoca como “Graba la pantalla…” no debe depender del árbitro de IA
        // ni del interruptor general de gramática natural. “Modo por voz” sigue
        // siendo el corte maestro para quien quiera dictado puro.
        if Config.modoPorVoz(), Config.agenteHerramientaCapturas(),
           let plan = AgenteNucleo.planificarCaptura(texto) {
            completion(.preguntarPlan(plan))
            return
        }
        // PEDIDO NATURAL: construye un plan de 1..N etapas por relaciones verbales.
        // Nunca ejecuta directo: el usuario ve exactamente qué entendimos y confirma.
        // Esta capa reemplaza en producción las antiguas raíces gramaticales amplias,
        // que confundían títulos como "Notas de la reunión" con órdenes.
        if Config.modoPorVoz(), Config.modoGramatical(),
           let plan = detectarPedidoNatural(texto, catalogo: catalogo,
                                             permitirCapturas: false) {
            completion(.preguntarPlan(plan))
            return
        }

        // Una frase EXACTA captada por los oídos en vivo (o cualquier match confirmado
        // por pausa) es intención explícita, no un fallback: gana al contexto implícito
        // de la app. Sin esto, hablar de corrido (sin pausa) degradaba la orden de voz
        // frente al modo por app — regresión respecto del comportamiento anterior.
        if Config.modoPorVoz(), let vivo, vivo.confirmadoPorPausa || vivo.fuente == .exacto {
            let m = aplicarVivo(vivo, al: texto)
            completion(.modo(ModoResolucion(modo: m.modo, texto: m.textoLimpio,
                                            fuente: m.fuente, match: m)))
            return
        }

        func respaldo() {
            if Config.modoPorVoz(), let vivo {
                let m = aplicarVivo(vivo, al: texto)
                completion(.modo(ModoResolucion(modo: m.modo, texto: m.textoLimpio,
                                                fuente: m.fuente, match: m)))
            } else {
                completion(.modo(ModoResolucion(modo: modoBase, texto: texto,
                                                fuente: .manual, match: nil)))
            }
        }

        func contextoORespaldo() {
            if Config.modoPorContexto(), let contexto,
               let m = ModosStore.detectarPorContexto(bundleId: contexto.bundleId,
                                                       nombre: contexto.nombre, url: contexto.url) {
                completion(.modo(ModoResolucion(modo: m, texto: texto,
                                                fuente: .contexto, match: nil)))
            } else { respaldo() }
        }

        // El interruptor maestro manda también sobre embeddings e IA. Apagar
        // "modo por voz" nunca debe dejar una capa inteligente activa por detrás.
        guard Config.modoPorVoz() else { contextoORespaldo(); return }

        // AUTORIDAD DEL ROUTER EN CONTEXTO DE AGENTE.
        // Cuando el pedido llegó por "Oye <agente> …" (modoBase = agente), la
        // decisión de A QUÉ CAPACIDAD cae la toma el router global
        // (RouterGlobalIA, vía responderAgente): tiene el catálogo cerrado
        // completo y la regla anti-invención. El árbitro de modos y el desempate
        // semántico de aquí son la ruta de dictado LEGACY y COMPETÍAN con él —
        // p. ej. "hazme una tarea…" acababa en la conexión UEA en vez de crear la
        // tarea. Los cortes deterministas de arriba (cadena/exacto/difuso/natural/
        // captura/vivo confirmado) ya se aplicaron; lo que quede se resuelve al
        // modo agente y el router elige. Las conexiones NOMBRADAS ya se atendieron
        // antes en AppDelegate (ConexionesDeteccion), así que no se pierden.
        if modoBase.base == "agente" {
            completion(.modo(ModoResolucion(modo: modoBase, texto: texto,
                                            fuente: .manual, match: nil)))
            return
        }

        let explicito = ModosStore.pareceComando(texto)
        let solicitud = ModoPlanificador.parecePedidoParaArbitraje(texto)

        /// Última instancia: una IA activa solo clasifica la ZONA de intención.
        /// Si tarda/falla/no ve intención, no bloquea ni cambia el texto.
        func arbitrarIA(siFalla propuestaLocal: ModoPreguntaPlan? = nil) {
            guard solicitud else {
                if let propuestaLocal { completion(.preguntarPlan(propuestaLocal)) }
                else { contextoORespaldo() }
                return
            }
            ModoIAEnrutador.resolver(texto, catalogo: catalogo) { plan in
                if let plan { completion(.preguntarPlan(plan)) }
                else if let propuestaLocal { completion(.preguntarPlan(propuestaLocal)) }
                else { contextoORespaldo() }
            }
        }

        // Embeddings: comandos explícitos inequívocos continúan automáticos; una
        // petición natural o un empate se confirma. En empate la IA intenta
        // desempatar ANTES de presentar la pregunta.
        if Config.modoSemantico(), (explicito || solicitud) {
            ModosStore.detectarSemanticoDetallado(texto) { r in
                guard let modo = r.modo, r.superaUmbral else {
                    arbitrarIA(); return
                }
                if explicito, r.inequívoco {
                    let m = matchSemantico(texto: texto, modo: modo,
                                           limpio: r.textoLimpio, confianza: r.score)
                    completion(.modo(ModoResolucion(modo: modo, texto: r.textoLimpio,
                                                    fuente: .semantico, match: m)))
                    return
                }
                guard let propuesta = planSemantico(r, catalogo: catalogo) else {
                    arbitrarIA(); return
                }
                if r.inequívoco { completion(.preguntarPlan(propuesta)) }
                else { arbitrarIA(siFalla: propuesta) }
            }
        } else if solicitud { arbitrarIA() }
        else { contextoORespaldo() }
    }

    /// Une las órdenes generales de Modos con herramientas locales que tienen
    /// una gramática especializada. Así "haz una captura…" funciona también
    /// como orden natural (con confirmación) sin exigir "Oye Bto" ni "modo".
    /// El parámetro explícito mantiene el QA independiente de la configuración.
    static func detectarPedidoNatural(_ texto: String, catalogo: ModoCatalogo,
                                      permitirCapturas: Bool = Config.agenteHerramientaCapturas())
        -> ModoPreguntaPlan? {
        if Config.agenteNucleoActivo(),
           let r = RutinasAgenteStore.detectarSeleccionBreve(texto)
                ?? RutinasAgenteStore.detectar(texto) {
            let m = Modo(id: "plan-rutina", nombre: "Rutina · \(r.rutina.nombre)",
                         icono: "list.bullet.rectangle", base: "accion",
                         prompt: r.rutina.id, accion: "rutina")
            return ModoPlanificador.pregunta(para: ModoCadena(transforms: [],
                acciones: [ModoAccionPlan(modo: m, destinatario: nil)],
                contenido: r.contenido), fuente: .natural, confianza: 0.99)
        }
        if Config.agenteNucleoActivo(), let clima = AgenteNucleo.planificarClima(texto) {
            return clima
        }
        if let plan = ModoPlanificador.detectarNatural(texto, catalogo: catalogo) { return plan }
        if permitirCapturas, let plan = AgenteNucleo.planificarCaptura(texto) { return plan }
        return nil
    }
}
