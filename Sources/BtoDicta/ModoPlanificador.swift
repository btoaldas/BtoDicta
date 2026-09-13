import Foundation

// MARK: - Planificador de intenciones naturales
//
// Esta capa NO reemplaza los comandos explícitos "modo X": los complementa.
// Convierte pedidos naturales en un plan de 1..N etapas, pero siempre lo entrega
// como propuesta para confirmar. La seguridad lingüística se basa en RELACIONES:
// "enviar POR correo" es acción; "el correo llegó" es contenido.

enum ModoPlanificador {
    private struct Token {
        let original: String
        let normal: String
        let rango: NSRange
    }

    private struct Parcial {
        var transforms: [Modo] = []
        var acciones: [ModoAccionPlan] = []
        var primerComando: Int?
        var ultimoComando: Int?
        var confianza = 0.0

        var tieneEtapas: Bool { !transforms.isEmpty || !acciones.isEmpty }
    }

    private static let regexPalabra = try! NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{N}'’_-]*|\p{N}+"#)

    private static let prefijoSolicitud: Set<String> = [
        "por", "favor", "porfavor", "porfa", "oye", "hey", "btodicta", "beto",
        "quiero", "quisiera", "necesito", "puedes", "puede", "podrias", "podria",
        "podemos", "podrian", "gustaria", "encantaria", "importaria", "ayudas",
        "ayudame", "ayudar", "me", "te", "le", "les", "lo", "se", "pido", "que",
        "a", "al", "haz", "hazme", "vamos", "dale", "deseo", "favorcito"
    ]
    private static let conectoresEtapa: Set<String> = [
        "y", "e", "que", "luego", "despues", "posteriormente", "ademas", "tambien",
        "seguidamente", "continuacion", "para"
    ]
    private static let marcadoresContenido: [[String]] = [
        ["lo", "siguiente"], ["el", "siguiente", "texto"], ["este", "texto"],
        ["esta", "frase"], ["esto"], ["texto"], ["que", "dice"], ["diciendo"],
        ["que", "diga"], ["con", "el", "texto"],
        ["y", "escribe"], ["y", "pega"], ["y", "pon"], ["y", "coloca"],
        ["escribe"], ["pega"], ["pon"], ["coloca"]
    ]
    private static let verbosEnvio: Set<String> = [
        "envia", "enviar", "enviame", "envialo", "enviaselo", "enviale", "enviarle",
        "envie", "envies", "envien", "enviarselo", "manda", "mandar", "mandame",
        "mandalo", "mandaselo", "mandarselo", "mandale", "mandarle", "mande", "mandes",
        "manden", "comparte", "compartir", "compartelo", "compartas", "pasale", "pasarlo"
    ]
    private static let verbosAbrir: Set<String> = [
        "abre", "abrir", "abreme", "abras", "abra", "abran", "lanza", "lanzar",
        "lances", "inicia", "iniciar", "inicies"
    ]
    private static let mediosEnvio: [String: String] = [
        "correo": "correo", "email": "correo", "mail": "correo",
        "outlook": "outlook",
        "whatsapp": "whatsapp", "wasap": "whatsapp", "guasap": "whatsapp", "wasa": "whatsapp",
        "mensaje": "mensajes", "mensajes": "mensajes", "imessage": "mensajes"
    ]
    private static let verbosTraducir: Set<String> = [
        "traduce", "traduceme", "traducelo", "traducela", "traducir", "traducirme",
        "traducirlo", "traducirla", "traduzca", "traduzcame", "traduzcas", "traduzcamos",
        "traduzcan"
    ]
    private static let verbosResumir: Set<String> = [
        "resume", "resumeme", "resumelo", "resumir", "resumirme", "resumirlo",
        "resuma", "resumame", "resumas", "resumamos", "resuman", "sintetiza", "sintetizar",
        "sintetices", "condensa", "condensar", "condenses"
    ]
    private static let verbosFormalizar: Set<String> = [
        "formaliza", "formalizame", "formalizalo", "formalizar", "formalizarlo",
        "formalices", "formalice", "profesionaliza", "profesionalizar", "profesionalices"
    ]
    private static let verbosBuscar: Set<String> = [
        "busca", "buscame", "buscar", "buscalo", "busquela", "googlea", "googlear",
        "busques", "busque", "busquen", "investiga", "investigar", "investigues"
    ]
    private static let verbosMusica: Set<String> = [
        "pon", "ponme", "poner", "reproduce", "reproduceme", "reproducir", "toca",
        "tocame", "escucha", "escuchame", "escuchar"
    ]
    private static let verbosBuscarMusica: Set<String> = [
        "busca", "buscame", "buscar", "buscalo", "busquela", "encuentra", "encuentrame",
        "encontrar", "muestra", "muestrame", "mostrar"
    ]
    private static let objetosMusica: Set<String> = [
        "musica", "cancion", "canciones", "tema", "playlist", "radio", "album"
    ]
    private static let objetosVideo: Set<String> = ["video", "videos", "tutorial", "tutoriales"]
    private static let verbosRecordar: Set<String> = [
        "recuerdame", "recordarme", "avisame", "avisar", "recuerdalo"
    ]
    private static let verbosAgendar: Set<String> = [
        "agenda", "agendame", "agendar", "programa", "programame", "programar"
    ]
    private static let objetosAgenda: Set<String> = ["evento", "reunion", "cita", "calendario", "agenda", "horario"]
    private static let verbosMostrarArchivo: Set<String> = [
        "muestra", "muestrame", "muestralo", "mostrar", "ver",
        "ensena", "ensename", "ensenalo", "revela", "revelame", "revelalo"
    ]
    private static let verbosArchivo: Set<String> = [
        "busca", "buscame", "buscar", "encuentra", "encuentrame", "encontrar",
        "abre", "abrir", "abreme", "muestra", "muestrame", "muestralo", "mostrar",
        "ver", "ensena", "ensename", "ensenalo", "revela", "revelame", "revelalo"
    ]
    private static let verbosRedactar: Set<String> = [
        "redacta", "redactame", "redactar", "escribe", "escribeme", "escribir",
        "redactes", "redacte", "escribas", "escriba", "prepara", "preparame", "preparar",
        "prepares", "prepare", "crea", "creame", "crear", "crees", "cree"
    ]
    /// Redacción libre que no cae en los formatos cerrados correo/oficio/nota.
    /// La lista evita verbos ambiguos en primera persona (p. ej. «creé») y exige
    /// además un objeto creativo cercano antes de proponer la etapa.
    private static let verbosGenerar: Set<String> = [
        "haz", "hazme", "crea", "creame", "crear", "genera", "generame", "generar",
        "redacta", "redactame", "redactar", "escribe", "escribeme", "escribir",
        "prepara", "preparame", "preparar", "inventa", "inventame", "inventar",
        "compone", "componme", "componer"
    ]
    private static let objetosGeneracion: Set<String> = [
        "redaccion", "verso", "poema", "texto", "mensaje", "saludo", "respuesta",
        "carta", "cuento", "historia", "publicacion", "guion", "frase", "parrafo",
        "contenido", "ejemplo"
    ]
    private static let verbosGuardar: Set<String> = [
        "anota", "anotame", "anotar", "apunta", "apuntame", "apuntar", "guarda",
        "guardame", "guardar", "guardes", "agrega", "agregame", "agregar", "agregues",
        "anade", "anademe", "anadir", "anadas"
    ]
    private static let verbosAgente: Set<String> = [
        "pregunta", "preguntale", "preguntar", "preguntes", "consulte", "consulta",
        "consultale", "consultar", "consultes", "pidele", "pedirle"
    ]

    private static func tokens(_ texto: String, rango: NSRange? = nil) -> [Token] {
        let ns = texto as NSString
        let r = rango ?? NSRange(location: 0, length: ns.length)
        return regexPalabra.matches(in: texto, range: r).map { m in
            let original = ns.substring(with: m.range)
            return Token(original: original, normal: ModoResolver.tokenNormalizado(original), rango: m.range)
        }
    }

    private static func fin(_ r: NSRange) -> Int { r.location + r.length }

    private static func modo(_ id: String, catalogo: ModoCatalogo) -> Modo? {
        catalogo.modos.first { $0.id == id }
    }

    private static func accion(_ id: String) -> Modo {
        Modo(id: "plan-\(id)", nombre: Acciones.nombre(id), icono: "bolt.fill",
             base: id == "buscar" ? "buscar" : "accion", accion: id)
    }

    private static func agregarTransform(_ modo: Modo, a parcial: inout Parcial) {
        guard !parcial.transforms.contains(where: { $0.id == modo.id }) else { return }
        parcial.transforms.append(modo)
    }

    private static func agregarAccion(_ etapa: ModoAccionPlan, a parcial: inout Parcial) {
        let destino = etapa.modo.base == "aplicacion"
            ? "app:\(etapa.modo.appBundleId)|\(etapa.modo.appRuta)"
            : (etapa.modo.base == "musica" ? "musica:\(etapa.modo.musicaProveedor)" : etapa.modo.accion)
        let firma = "\(destino)|\(etapa.destinatario ?? "")"
        guard !parcial.acciones.contains(where: {
            let otro = $0.modo.base == "aplicacion"
                ? "app:\($0.modo.appBundleId)|\($0.modo.appRuta)"
                : ($0.modo.base == "musica" ? "musica:\($0.modo.musicaProveedor)" : $0.modo.accion)
            return "\(otro)|\($0.destinatario ?? "")" == firma
        }) else { return }
        parcial.acciones.append(etapa)
    }

    private static func aplicacionCercana(desde i: Int, en ts: [Token],
                                          catalogo: ModoCatalogo) -> (Modo, Int)? {
        guard Config.modoAplicaciones(), i + 1 < ts.count,
              let base = modo("aplicacion", catalogo: catalogo) else { return nil }
        var j = i + 1
        let relleno: Set<String> = ["la", "el", "una", "un", "aplicacion", "app", "programa", "de"]
        while j < ts.count, relleno.contains(ts[j].normal) { j += 1 }
        guard j < ts.count else { return nil }
        let resto = ts[j...].map(\.normal)
        guard case .encontrada(let match) = AplicacionesMac.resolverPrefijo(resto) else { return nil }
        return (AplicacionesMac.aplicar(match, a: base), j + match.palabrasConsumidas - 1)
    }

    /// Entre dos etapas debe existir una relación explícita (y/luego/que/coma).
    /// Así un verbo que aparece dentro del contenido no se convierte en otra etapa.
    private static func puenteValido(_ texto: String, desde: Int, hasta: Int) -> Bool {
        guard hasta >= desde else { return false }
        let ns = texto as NSString
        let puente = ns.substring(with: NSRange(location: desde, length: hasta - desde))
        if puente.contains(",") || puente.contains(";") { return true }
        let p = ModoResolver.tokensNormalizados(puente)
        return p.contains(where: conectoresEtapa.contains)
    }

    private static func prefijoValido(_ ts: [Token], primer: Int) -> Bool {
        guard primer >= 0 else { return false }
        if primer == 0 { return true }
        // No basta con que el verbo aparezca "pronto": TODO lo anterior debe sonar
        // a petición. "La idea es traducir" no es una orden; "por favor ayúdame a
        // traducir" sí.
        return primer <= 8 && ts[..<primer].allSatisfy { prefijoSolicitud.contains($0.normal) }
    }

    private static func pideResultadosEnFinder(desde inicio: Int, en ts: [Token]) -> Bool {
        let fin = min(ts.count, inicio + 18)
        guard inicio < fin else { return false }
        let zona = Array(ts[inicio..<fin].map(\.normal))
        guard let f = zona.firstIndex(of: "finder") else { return false }
        if zona.contains(where: verbosMostrarArchivo.contains) { return true }
        if f > 0, zona[f - 1] == "en" { return true }
        return f > 1 && zona[f - 2] == "en" && zona[f - 1] == "el"
    }

    private static func idiomaDespues(de i: Int, en ts: [Token]) -> (String, Int)? {
        var j = i + 1
        while j < ts.count, ["a", "al", "en", "idioma"].contains(ts[j].normal) { j += 1 }
        guard j < ts.count, let idi = Idiomas.reconocer(ts[j].normal) else { return nil }
        return (idi, j)
    }

    private static func buscadorCercano(desde i: Int, en ts: [Token]) -> (String, Int)? {
        let limite = min(ts.count, i + 6)
        guard i + 1 < limite else { return nil }
        for j in (i + 1)..<limite {
            if let b = Buscadores.reconocer(ts[j].normal) { return (b, j) }
            if !["en", "por", "con", "el", "la", "un", "una", "buscador"].contains(ts[j].normal) { break }
        }
        return nil
    }

    private static func proveedorMusicaCercano(desde i: Int, en ts: [Token]) -> (String, Int)? {
        let limite = min(ts.count, i + 7)
        guard i + 1 < limite else { return nil }
        for j in (i + 1)..<limite {
            if j + 1 < limite {
                let dos = ts[j].normal + " " + ts[j + 1].normal
                if let p = Musica.reconocerProveedorCompuesto(dos) { return (p, j + 1) }
            }
            if let p = Musica.reconocerProveedor(en: ts[j].normal) { return (p, j) }
            if !["en", "por", "con", "el", "la", "un", "una", "musica", "music"].contains(ts[j].normal) { break }
        }
        return nil
    }

    private static func destinoRedaccion(desde i: Int, en ts: [Token]) -> (String, Int)? {
        let limite = min(ts.count, i + 6)
        guard i + 1 < limite else { return nil }
        for j in (i + 1)..<limite {
            switch ts[j].normal {
            case "correo", "email", "mail": return ("correo", j)
            case "oficio", "memorando", "documento": return ("oficio", j)
            case "nota", "notas": return ("nota", j)
            case "tarea", "pendiente", "recordatorio": return ("tarea", j)
            default: continue
            }
        }
        return nil
    }

    /// “Crea una nota” conserva el modo Nota local de BtoDicta. Solo se vuelve
    /// una acción externa si el usuario nombra de forma inequívoca Apple/Mac o la
    /// aplicación Notes; así no reintroducimos la antigua colisión de nombres.
    private static func notaAppleCercana(desde i: Int, en ts: [Token]) -> Int? {
        let limite = min(ts.count, i + 10)
        guard i + 1 < limite else { return nil }
        var vioNota = false
        var vioNombreNotes = false
        var vioDestinoApple = false
        var vioAplicacion = false
        var ultimo = i
        var completo = false
        let relleno: Set<String> = [
            "en", "de", "del", "la", "el", "una", "un", "aplicacion", "app",
            "nota", "notas", "notes", "apple", "mac", "macos"
        ]
        for j in (i + 1)..<limite {
            let t = ts[j].normal
            if ["nota", "notas", "notes"].contains(t) { vioNota = true; ultimo = j }
            if ["notas", "notes"].contains(t) { vioNombreNotes = true; ultimo = j }
            if ["apple", "mac", "macos"].contains(t) { vioDestinoApple = true; ultimo = j }
            if ["aplicacion", "app"].contains(t) { vioAplicacion = true; ultimo = j }
            completo = vioNota && (vioDestinoApple || (vioAplicacion && vioNombreNotes))
            if completo, !relleno.contains(t) { break }
            if j > i + 1, ["que", "diga", "diciendo", "texto"].contains(t) { break }
        }
        return completo ? ultimo : nil
    }

    private static func objetoGeneracion(desde i: Int, en ts: [Token]) -> Int? {
        let limite = min(ts.count, i + 9)
        guard i + 1 < limite else { return nil }
        return ((i + 1)..<limite).first { objetosGeneracion.contains(ts[$0].normal) }
    }

    /// Etapa interna para «crea un verso … y después mándaselo…». Conserva la
    /// IA/modelo configurados en Asistente, pero usa un prompt acotado para que
    /// la IA devuelva el contenido y no prometa falsamente ejecutar WhatsApp.
    private static func modoGeneracion(catalogo: ModoCatalogo) -> Modo? {
        guard var m = modo("asistente", catalogo: catalogo) else { return nil }
        m.id = "generar"
        m.nombre = "Redactar"
        m.icono = "pencil.and.outline"
        m.prompt = "Redacta el contenido descrito por el pedido. Devuelve únicamente el texto final solicitado, sin explicar el proceso, sin saludar y sin afirmar que enviarás, abrirás o ejecutarás acciones posteriores."
        return m
    }

    private static func destinoAgente(desde i: Int, en ts: [Token]) -> (String, Int)? {
        let limite = min(ts.count, i + 6)
        guard i + 1 < limite else { return nil }
        for j in (i + 1)..<limite {
            if ts[j].normal == "agente" { return ("agente", j) }
            if ts[j].normal == "gente" { return ("agente", j) } // STT frecuente: "al agente"→"a la gente"
            if ts[j].normal == "asistente" { return ("asistente", j) }
            if !["a", "al", "el", "la", "un", "una", "mi"].contains(ts[j].normal) { break }
        }
        return nil
    }

    private static func destinatario(desde verbo: Int, medio: Int, en ts: [Token], texto: String)
        -> (String?, Int) {
        let paradas: Set<String> = [
            "por", "mediante", "en", "via", "y", "e", "luego", "despues", "que",
            "diciendo", "mensaje", "texto", "con"
        ]
        // "mándaselo A Andrés POR WhatsApp"
        if verbo + 1 < medio,
           let a = ((verbo + 1)..<medio).first(where: { ["a", "al", "para"].contains(ts[$0].normal) }) {
            var nombres: [String] = []
            var ultimo = a
            var j = a + 1
            while j < medio, nombres.count < 4, !paradas.contains(ts[j].normal) {
                nombres.append(ts[j].original); ultimo = j; j += 1
            }
            if !nombres.isEmpty { return (nombres.joined(separator: " "), max(medio, ultimo)) }
        }
        // "por WhatsApp A Andrés, ...". Sin coma tomamos una palabra: no nos
        // comemos el mensaje entero intentando adivinar un apellido.
        var j = medio + 1
        if j < ts.count, ["a", "al", "para"].contains(ts[j].normal) {
            j += 1
            guard j < ts.count else { return (nil, medio) }
            var nombres = [ts[j].original]
            var ultimo = j
            if j + 1 < ts.count {
                let ns = texto as NSString
                let puente = ns.substring(with: NSRange(location: fin(ts[j].rango),
                                                         length: max(0, ts[j + 1].rango.location - fin(ts[j].rango))))
                if !puente.contains(",") && !puente.contains(":") && !puente.contains(".")
                    && !paradas.contains(ts[j + 1].normal)
                    && ts[j + 1].original.first?.isUppercase == true {
                    nombres.append(ts[j + 1].original); ultimo = j + 1
                }
            }
            return (nombres.joined(separator: " "), ultimo)
        }
        // El STT puede omitir la preposición: "manda por WhatsApp Andrés,
        // llego a las ocho". La coma vuelve seguro el límite; sin puntuación no
        // adivinamos, porque podría ser ya el comienzo del mensaje.
        j = medio + 1
        let noNombres: Set<String> = [
            "el", "la", "los", "las", "un", "una", "este", "esta", "esto",
            "mensaje", "texto", "lo", "siguiente", "diciendo", "que"
        ]
        if j < ts.count, !noNombres.contains(ts[j].normal) {
            var nombres: [String] = []
            var ultimo = j
            while j < ts.count, nombres.count < 4, !paradas.contains(ts[j].normal) {
                nombres.append(ts[j].original); ultimo = j
                let ns = texto as NSString
                let siguiente = fin(ts[j].rango)
                let hasta = j + 1 < ts.count ? ts[j + 1].rango.location : ns.length
                let puente = ns.substring(with: NSRange(location: siguiente,
                                                         length: max(0, hasta - siguiente)))
                if puente.contains(",") || puente.contains(":") {
                    return (nombres.joined(separator: " "), ultimo)
                }
                if puente.contains(".") || puente.contains(";") { break }
                j += 1
            }
        }
        return (nil, medio)
    }

    private static func parsearRegion(_ texto: String, rango: NSRange,
                                      catalogo: ModoCatalogo,
                                      exigirPrefijo: Bool) -> Parcial? {
        let ts = tokens(texto, rango: rango)
        guard !ts.isEmpty else { return nil }
        var p = Parcial()
        var i = 0
        var finEtapaAnterior: Int?

        func puedeAgregar(en indice: Int) -> Bool {
            if p.primerComando == nil { return !exigirPrefijo || prefijoValido(ts, primer: indice) }
            guard let anterior = finEtapaAnterior else { return false }
            return puenteValido(texto, desde: anterior, hasta: ts[indice].rango.location)
        }
        func marcar(_ inicio: Int, _ finIndice: Int,
                    contenidoDespuesDe: Int? = nil, confianza: Double) {
            if p.primerComando == nil { p.primerComando = inicio }
            // Algunas palabras confirman el destino sin dejar de ser contenido.
            // En «agenda un horario/reunión mañana…», horario/reunión será el
            // título del evento; solo el verbo «agenda» debe recortarse.
            p.ultimoComando = max(p.ultimoComando ?? 0, contenidoDespuesDe ?? finIndice)
            finEtapaAnterior = fin(ts[finIndice].rango)
            p.confianza = max(p.confianza, confianza)
        }

        while i < ts.count {
            let t = ts[i].normal

            if verbosTraducir.contains(t), puedeAgregar(en: i), var m = modo("traducir", catalogo: catalogo) {
                var ultimo = i
                if let (idi, j) = idiomaDespues(de: i, en: ts) { m.idiomaDestino = idi; ultimo = j }
                agregarTransform(m, a: &p); marcar(i, ultimo, confianza: 0.94); i = ultimo + 1; continue
            }
            if verbosResumir.contains(t), puedeAgregar(en: i), let m = modo("resumir", catalogo: catalogo) {
                agregarTransform(m, a: &p); marcar(i, i, confianza: 0.93); i += 1; continue
            }
            if verbosFormalizar.contains(t), puedeAgregar(en: i), var m = modo("oficio", catalogo: catalogo) {
                m.nombre = "Formalizar"
                agregarTransform(m, a: &p); marcar(i, i, confianza: 0.92); i += 1; continue
            }
            if (verbosRedactar.contains(t) || verbosGuardar.contains(t)), puedeAgregar(en: i),
               let j = notaAppleCercana(desde: i, en: ts) {
                agregarAccion(ModoAccionPlan(modo: accion("notas"), destinatario: nil), a: &p)
                marcar(i, j, confianza: 0.98); i = j + 1; continue
            }
            if verbosRedactar.contains(t), puedeAgregar(en: i),
               let (id, j) = destinoRedaccion(desde: i, en: ts), let m = modo(id, catalogo: catalogo) {
                agregarTransform(m, a: &p); marcar(i, j, confianza: 0.92); i = j + 1; continue
            }
            if verbosGenerar.contains(t), puedeAgregar(en: i),
               let j = objetoGeneracion(desde: i, en: ts),
               let m = modoGeneracion(catalogo: catalogo) {
                // El objeto («un verso», «una redacción»…) forma parte del pedido
                // que verá la IA. Solo se recorta el verbo; `finEtapaAnterior`
                // queda después del objeto para exigir un puente antes de otra etapa.
                agregarTransform(m, a: &p)
                marcar(i, j, contenidoDespuesDe: i, confianza: 0.96)
                i = j + 1; continue
            }
            if verbosGuardar.contains(t), puedeAgregar(en: i),
               let (id, j) = destinoRedaccion(desde: i, en: ts), ["nota", "tarea"].contains(id),
               let m = modo(id, catalogo: catalogo) {
                agregarTransform(m, a: &p); marcar(i, j, confianza: 0.91); i = j + 1; continue
            }
            if verbosAgente.contains(t), puedeAgregar(en: i),
               let (id, j) = destinoAgente(desde: i, en: ts), let m = modo(id, catalogo: catalogo) {
                agregarTransform(m, a: &p); marcar(i, j, confianza: 0.91); i = j + 1; continue
            }
            // Controles del reproductor: “pausa la música”, “siguiente canción”,
            // “cierra el reproductor”… Se resuelven localmente, sin IA.
            if puedeAgregar(en: i), let mBase = modo("musica", catalogo: catalogo) {
                let control = Musica.comando(texto)
                if control.intencion == nil {
                    var m = mBase; m.musicaAccion = control.rawValue
                    agregarAccion(ModoAccionPlan(modo: m, destinatario: nil), a: &p)
                    marcar(i, max(i, ts.count - 1), confianza: 0.99)
                    i = ts.count; continue
                }
            }
            // “busca música de Julio” conserva una intención distinta de
            // “pon música de Julio”: la primera solo muestra resultados.
            if verbosBuscarMusica.contains(t), puedeAgregar(en: i),
               let mBase = modo("musica", catalogo: catalogo) {
                let limite = min(ts.count, i + 7)
                let cerca = i + 1 < limite ? Array(ts[(i + 1)..<limite].map(\.normal)) : []
                let mencionaMusica = cerca.contains(where: objetosMusica.contains)
                let mencionaVideo = cerca.contains(where: objetosVideo.contains)
                let prov = proveedorMusicaCercano(desde: i, en: ts)
                if mencionaMusica || mencionaVideo || prov != nil {
                    var m = mBase; m.musicaAccion = "buscar"; var ultimo = i
                    if mencionaVideo { m.musicaProveedor = "btodicta_youtube" }
                    if let (id, j) = prov { m.musicaProveedor = id; ultimo = max(ultimo, j) }
                    if let j = ((i + 1)..<limite).first(where: {
                        objetosMusica.contains(ts[$0].normal) || objetosVideo.contains(ts[$0].normal)
                    }) {
                        ultimo = max(ultimo, j)
                    }
                    agregarAccion(ModoAccionPlan(modo: m, destinatario: nil), a: &p)
                    // “tutoriales/videos” también define el tipo de búsqueda;
                    // se conserva en la consulta para que la API no aplique el
                    // filtro musical cuando el usuario no repite “video”.
                    marcar(i, ultimo, contenidoDespuesDe: mencionaVideo ? i : nil,
                           confianza: 0.97)
                    i = ultimo + 1; continue
                }
            }
            // "pon música de Jessy Uribe" / "reproduce en Spotify…". Exige un
            // objeto musical o proveedor cercano; "pon el informe" no activa nada.
            if verbosMusica.contains(t), puedeAgregar(en: i),
               let mBase = modo("musica", catalogo: catalogo) {
                let limite = min(ts.count, i + 7)
                let cerca = i + 1 < limite ? Array(ts[(i + 1)..<limite].map(\.normal)) : []
                let mencionaMusica = cerca.contains(where: objetosMusica.contains)
                let mencionaVideo = cerca.contains(where: objetosVideo.contains)
                let prov = proveedorMusicaCercano(desde: i, en: ts)
                if mencionaMusica || mencionaVideo || prov != nil {
                    var m = mBase; m.musicaAccion = "reproducir"; var ultimo = i
                    if mencionaVideo { m.musicaProveedor = "btodicta_youtube" }
                    if let (id, j) = prov { m.musicaProveedor = id; ultimo = max(ultimo, j) }
                    if let j = ((i + 1)..<limite).first(where: {
                        objetosMusica.contains(ts[$0].normal) || objetosVideo.contains(ts[$0].normal)
                    }) {
                        ultimo = max(ultimo, j)
                    }
                    agregarAccion(ModoAccionPlan(modo: m, destinatario: nil), a: &p)
                    marcar(i, ultimo, contenidoDespuesDe: mencionaVideo ? i : nil,
                           confianza: 0.96)
                    i = ultimo + 1; continue
                }
            }
            if verbosRecordar.contains(t), puedeAgregar(en: i) {
                agregarAccion(ModoAccionPlan(modo: accion("recordatorios"), destinatario: nil), a: &p)
                marcar(i, i, confianza: 0.97); i += 1; continue
            }
            if verbosAgendar.contains(t), puedeAgregar(en: i) {
                let limite = min(ts.count, i + 6)
                if let j = ((i + 1)..<limite).first(where: { objetosAgenda.contains(ts[$0].normal) }) {
                    agregarAccion(ModoAccionPlan(modo: accion("calendario"), destinatario: nil), a: &p)
                    marcar(i, j, contenidoDespuesDe: i, confianza: 0.95); i = j + 1; continue
                }
            }
            if verbosArchivo.contains(t), puedeAgregar(en: i) {
                let limite = min(ts.count, i + 5)
                if let j = ((i + 1)..<limite).first(where: { ["archivo", "documento", "carpeta"].contains(ts[$0].normal) }) {
                    var m = accion("archivo")
                    if pideResultadosEnFinder(desde: i, en: ts) { m.prompt = "finder" }
                    agregarAccion(ModoAccionPlan(modo: m, destinatario: nil), a: &p)
                    marcar(i, j, confianza: 0.95); i = j + 1; continue
                }
            }
            if verbosBuscar.contains(t), puedeAgregar(en: i) {
                var m = modo("buscar", catalogo: catalogo) ?? accion("buscar")
                var ultimo = i
                if let (b, j) = buscadorCercano(desde: i, en: ts) { m.buscador = b; ultimo = j }
                agregarAccion(ModoAccionPlan(modo: m, destinatario: nil), a: &p)
                marcar(i, ultimo, confianza: 0.92); i = ultimo + 1; continue
            }
            if verbosEnvio.contains(t), puedeAgregar(en: i) {
                let limite = min(ts.count, i + 11)
                var halladas: [(String, Int)] = []
                if i + 1 < limite {
                    for j in (i + 1)..<limite {
                        if let id = mediosEnvio[ts[j].normal] { halladas.append((id, j)) }
                        let ns = texto as NSString
                        let entre = ns.substring(with: NSRange(location: fin(ts[j - 1].rango),
                                                               length: max(0, ts[j].rango.location - fin(ts[j - 1].rango))))
                        if entre.contains(":") || entre.contains(".") || entre.contains(";") { break }
                    }
                }
                if !halladas.isEmpty {
                    var ultimo = i
                    for (id, j) in halladas {
                        let permiteDestinatario = id == "whatsapp" || id == "mensajes"
                        let (dest, finDest) = permiteDestinatario
                            ? destinatario(desde: i, medio: j, en: ts, texto: texto)
                            : (nil, j)
                        agregarAccion(ModoAccionPlan(modo: accion(id), destinatario: dest), a: &p)
                        ultimo = max(ultimo, max(j, finDest))
                    }
                    marcar(i, ultimo, confianza: 0.95); i = ultimo + 1; continue
                }
            }
            if verbosAbrir.contains(t), puedeAgregar(en: i) {
                let limite = min(ts.count, i + 6)
                var encontrado: (String, Int)?
                if i + 1 < limite {
                    for j in (i + 1)..<limite {
                        if let v = ModosStore.resolverVerbo(ts[j].normal), v.tipo == "accion",
                           v.id != "buscar", v.id != "aplicacion" {
                            encontrado = (v.id, j); break
                        }
                    }
                }
                if let (id, j) = encontrado {
                    agregarAccion(ModoAccionPlan(modo: accion(id), destinatario: nil), a: &p)
                    marcar(i, j, confianza: 0.9); i = j + 1; continue
                }
                if let (app, j) = aplicacionCercana(desde: i, en: ts, catalogo: catalogo) {
                    agregarAccion(ModoAccionPlan(modo: app, destinatario: nil), a: &p)
                    marcar(i, j, confianza: 0.94); i = j + 1; continue
                }
            }
            i += 1
        }

        guard p.tieneEtapas, let primero = p.primerComando,
              (!exigirPrefijo || prefijoValido(ts, primer: primero)) else { return nil }
        return p
    }

    private static func primerSeparador(_ texto: String, antesDe limite: Int,
                                        caracteres: CharacterSet) -> Int? {
        let ns = texto as NSString
        guard limite > 0 else { return nil }
        for i in 0..<min(limite, ns.length) {
            let u = UnicodeScalar(ns.character(at: i))
            guard let u, caracteres.contains(u) else { continue }
            // En "recuérdame mañana a las 8:00 p.m." los dos puntos son parte
            // de la hora, no el límite entre la orden y su contenido. Tratarlo
            // como separador recortaba la orden a "00 p.m." y EventKit terminaba
            // creando el recordatorio a medianoche.
            if u == ":", i > 0, i + 1 < ns.length {
                let anterior = UnicodeScalar(ns.character(at: i - 1))
                let siguiente = UnicodeScalar(ns.character(at: i + 1))
                if let anterior, let siguiente,
                   CharacterSet.decimalDigits.contains(anterior),
                   CharacterSet.decimalDigits.contains(siguiente) {
                    continue
                }
            }
            return i
        }
        return nil
    }

    private static func rangoSufijoSecuencial(_ texto: String) -> NSRange? {
        let patron = #"[.!?]\s+(?:y\s+)?(?:despu[eé]s|luego|a\s+continuaci[oó]n|posteriormente)\b"#
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return nil }
        let ns = texto as NSString
        return re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length))?.range
    }

    /// Variante para cuando el STT reemplaza ": ... . Y después" por una sola
    /// oración: "esto, ... y después ...". Solo se busca DESPUÉS de que una
    /// cabecera inequívoca ya delimitó el comienzo del contenido; por eso no
    /// confunde "resume y luego traduce" con texto dictado.
    private static func rangoSufijoDentroDelContenido(_ texto: String, desde inicio: Int) -> NSRange? {
        let patron = #"\b(?:y\s+)?(?:despu[eé]s|luego|a\s+continuaci[oó]n|posteriormente)\b"#
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return nil }
        let ns = texto as NSString
        guard inicio >= 0, inicio < ns.length else { return nil }
        return re.firstMatch(in: texto,
                             range: NSRange(location: inicio, length: ns.length - inicio))?.range
    }

    /// Apple Speech suele convertir dos puntos en coma. Elegimos únicamente
    /// una coma/semicolon cuyo encabezado ya diga "esto", "lo siguiente" o
    /// "texto"; una coma de cortesía ("Por favor, ...") no cuenta.
    private static func separadorContenidoMarcado(_ texto: String, antesDe limite: Int) -> Int? {
        let ns = texto as NSString
        guard limite > 0 else { return nil }
        for i in 0..<min(limite, ns.length) {
            let c = ns.character(at: i)
            guard c == 44 || c == 59 else { continue } // , ;
            let cabecera = ns.substring(with: NSRange(location: 0, length: i))
            let n = ModoResolver.tokensNormalizados(cabecera)
            if n.contains("esto") || n.contains("siguiente") || n.contains("texto") { return i }
        }
        return nil
    }

    private static func saltarMarcador(_ texto: String, desde: Int, hasta: Int) -> Int {
        let r = NSRange(location: max(0, desde), length: max(0, hasta - max(0, desde)))
        let ts = tokens(texto, rango: r)
        guard !ts.isEmpty else { return desde }
        for patron in marcadoresContenido where ts.count >= patron.count {
            if Array(ts.prefix(patron.count).map(\.normal)) == patron {
                return fin(ts[patron.count - 1].rango)
            }
        }
        return desde
    }

    private static func limpiarContenido(_ s: String) -> String {
        var t = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,:;"))
        while let f = t.first, ".!?…".contains(f) {
            t.removeFirst(); t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let pares: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»"), ("'", "'")]
        if let f = t.first, let cierre = pares.first(where: { $0.0 == f })?.1,
           let idx = t.lastIndex(of: cierre), idx != t.startIndex {
            let despues = t[t.index(after: idx)...]
            let soloPuntuacion = despues.allSatisfy { $0.isWhitespace || ".!?…".contains($0) }
            if soloPuntuacion {
                t.remove(at: idx); t.removeFirst()
                t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return t
    }

    static func descripcionEtapa(_ modo: Modo, destinatario: String? = nil) -> String {
        if modo.base == "traducir" {
            return "Traducir" + (modo.idiomaDestino.isEmpty ? "" : " al \(modo.idiomaDestino)")
        }
        if modo.id == "resumir" { return "Resumir" }
        if modo.id == "agente" { return "Preguntar al agente" }
        if modo.base == "musica" {
            let nombres: [String: String] = [
                "buscar": "Buscar música o video", "reproducir": "Reproducir música",
                "pausar": "Pausar música", "reanudar": "Reanudar música",
                "detener": "Detener música", "siguiente": "Siguiente canción",
                "anterior": "Canción anterior", "aleatorio": "Mezclar la cola", "cerrar": "Cerrar reproductor",
                "pantalla_completa": "Cambiar pantalla completa", "compacto": "Cambiar vista compacta",
            ]
            let verbo = nombres[modo.musicaAccion] ?? "Reproducir música"
            return ["", "auto"].contains(modo.musicaProveedor)
                ? verbo
                : "\(verbo) en \(Musica.nombre(modo.musicaProveedor))"
        }
        if modo.nombre == "Formalizar" { return "Formalizar" }
        if modo.base == "buscar" { return "Buscar en \(Buscadores.nombre(modo.buscador))" }
        if modo.base == "aplicacion" {
            return "Abrir \(modo.appNombre.isEmpty ? "una aplicación" : modo.appNombre) y colocar el texto"
        }
        if modo.base == "accion" {
            switch modo.accion {
            case "gmail":
                return "Preparar un borrador en Gmail" + ((destinatario?.isEmpty == false) ? " para \(destinatario!)" : "")
            case "correo":
                return "Preparar un borrador en Mail" + ((destinatario?.isEmpty == false) ? " para \(destinatario!)" : "")
            case "outlook":
                return "Preparar un borrador en Outlook" + ((destinatario?.isEmpty == false) ? " para \(destinatario!)" : "")
            case "recordatorios": return "Crear un recordatorio"
            case "calendario": return "Crear un evento en Calendario"
            case "notas": return "Crear una nota en Notas de Apple"
            case "archivo": return modo.prompt == "finder"
                ? "Mostrar resultados de archivos en Finder"
                : "Buscar un archivo en la Mac"
            case "archivo_nuevo": return "Crear un archivo local y elegir dónde guardarlo"
            case "clima": return "Consultar el clima"
            case "volumen":
                return SolicitudVolumenMac(codigo: modo.prompt)?.descripcion
                    ?? "Controlar el volumen del Mac"
            case "nota_local": return "Guardar una nota local"
            case "tarea_local": return "Guardar una tarea local"
            case "atajo_apple": return "Ejecutar el Atajo Apple configurado"
            case "rutina": return "Ejecutar la rutina configurada"
            case "conexion": return "Usar la conexión \(modo.nombre)"
            default: break
            }
            var d = modo.accion == "whatsapp" || modo.accion == "mensajes"
                    ? "Abrir borrador en \(Acciones.nombre(modo.accion))"
                    : "Abrir \(Acciones.nombre(modo.accion))"
            if let destinatario, !destinatario.isEmpty { d += " a \(destinatario)" }
            return d
        }
        switch modo.id {
        case "correo": return "Dar formato de correo"
        case "oficio": return "Convertir en oficio"
        case "tarea": return "Crear una tarea"
        case "nota": return "Crear una nota"
        default: return modo.nombre
        }
    }

    static func pregunta(para cadena: ModoCadena, fuente: FuenteModo = .natural,
                         confianza: Double = 0.9, alternativas: [String] = []) -> ModoPreguntaPlan {
        let detalles = cadena.transforms.map { descripcionEtapa($0) }
            + cadena.acciones.map { descripcionEtapa($0.modo, destinatario: $0.destinatario) }
        let descripcion: String
        if detalles.count == 1 { descripcion = detalles[0] }
        else if detalles.count == 2 { descripcion = detalles.joined(separator: " y luego ") }
        else { descripcion = detalles.dropLast().joined(separator: ", ") + " y finalmente " + (detalles.last ?? "") }
        return ModoPreguntaPlan(cadena: cadena, descripcion: descripcion,
                                detalles: detalles, alternativas: alternativas,
                                fuente: fuente, confianza: confianza)
    }

    /// Pedido natural → plan. Devuelve nil ante texto narrativo o si no queda
    /// contenido. Los pedidos naturales SIEMPRE se confirman aguas arriba.
    static func detectarNatural(_ texto: String,
                                catalogo: ModoCatalogo = ModoCatalogoCache.actual()) -> ModoPreguntaPlan? {
        // Las órdenes largas con documento + destino llevan campos adicionales
        // (destinatario/asunto). Se estructuran antes del parser general, pero
        // terminan en el MISMO ModoCadena y la misma confirmación.
        if let p = OrdenEstructurada.detectar(texto, catalogo: catalogo) { return p }
        // “Pon música” puede repetirse por énfasis o porque el STT duplicó el
        // parcial. Es una orden completa sin consulta: se colapsa a UNA acción y
        // usa la consulta predeterminada/aleatoria, nunca se manda a una IA.
        let palabrasMusica = ModoResolver.tokensNormalizados(texto).filter {
            !["por", "favor", "porfavor", "oye", "beto", "btodicta"].contains($0)
        }
        if !palabrasMusica.isEmpty, palabrasMusica.count.isMultiple(of: 2) {
            let paresValidos = stride(from: 0, to: palabrasMusica.count, by: 2).allSatisfy { i in
                ["pon", "ponme", "reproduce", "toca"].contains(palabrasMusica[i])
                    && palabrasMusica[i + 1] == "musica"
            }
            if paresValidos, var m = modo("musica", catalogo: catalogo) {
                m.musicaAccion = "reproducir"
                return pregunta(para: ModoCadena(transforms: [],
                    acciones: [ModoAccionPlan(modo: m, destinatario: nil)], contenido: ""),
                    fuente: .natural, confianza: 0.99)
            }
        }
        let ns = texto as NSString
        guard ns.length > 0 else { return nil }
        var sufijo = rangoSufijoSecuencial(texto)
        var finPrincipal = sufijo?.location ?? ns.length
        let dosPuntos = primerSeparador(texto, antesDe: finPrincipal,
                                        caracteres: CharacterSet(charactersIn: ":"))

        var limitePrefijo = finPrincipal
        var inicioContenido: Int?
        if let dosPuntos {
            limitePrefijo = dosPuntos
            inicioContenido = dosPuntos + 1
        } else if let punto = primerSeparador(texto, antesDe: finPrincipal,
                                              caracteres: CharacterSet(charactersIn: ".!?")) {
            let cabecera = ns.substring(with: NSRange(location: 0, length: punto))
            let cola = punto + 1 < finPrincipal
                ? ns.substring(with: NSRange(location: punto + 1, length: finPrincipal - punto - 1))
                : ""
            let n = ModoResolver.tokensNormalizados(cabecera)
            let hayCola = cola.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
            if hayCola && (n.contains("siguiente") || n.contains("esto") || n.contains("texto")) {
                limitePrefijo = punto
                inicioContenido = punto + 1
            }
        }
        // Un punto final puede existir aunque no sea separador de cabecera. En
        // ese caso todavía debemos probar la coma que Apple puso por los dos
        // puntos (no puede ser un `else` del bloque anterior).
        if inicioContenido == nil,
           let marcado = separadorContenidoMarcado(texto, antesDe: finPrincipal) {
            limitePrefijo = marcado
            inicioContenido = marcado + 1
        }

        // También tolera una frase corrida sin puntuación: "traduce la vida es
        // bella y luego envíalo por correo". Solo se separa si ENTRE la primera
        // orden y "y luego" hay contenido real; "resume y luego traduce" sigue
        // siendo simplemente una cabecera con dos transformaciones.
        if inicioContenido == nil, sufijo == nil,
           let flexible = rangoSufijoDentroDelContenido(texto, desde: 0) {
            let rAntes = NSRange(location: 0, length: flexible.location)
            if let antes = parsearRegion(texto, rango: rAntes,
                                         catalogo: catalogo, exigirPrefijo: true),
               let ultimo = antes.ultimoComando {
                let previos = tokens(texto, rango: rAntes)
                if ultimo < previos.count {
                    let inicioPosible = fin(previos[ultimo].rango)
                    let entre = ns.substring(with: NSRange(location: inicioPosible,
                                                            length: max(0, flexible.location - inicioPosible)))
                    let palabras = tokens(entre).map(\.normal)
                    let soloMarcador: Set<String> = [
                        "esto", "lo", "siguiente", "el", "texto", "este", "esta", "frase"
                    ]
                    if !palabras.isEmpty, !palabras.allSatisfy({ soloMarcador.contains($0) }) {
                        sufijo = flexible
                        finPrincipal = flexible.location
                        limitePrefijo = flexible.location
                        inicioContenido = inicioPosible
                    }
                }
            }
        }

        // Sin separador duro solo examinamos el inicio. El contenido no puede
        // reactivar etapas mucho después dentro de una narración.
        if inicioContenido == nil {
            let todos = tokens(texto, rango: NSRange(location: 0, length: finPrincipal))
            if todos.count > 18 { limitePrefijo = fin(todos[17].rango) }
        }

        guard var principal = parsearRegion(texto,
                                            rango: NSRange(location: 0, length: max(0, limitePrefijo)),
                                            catalogo: catalogo, exigirPrefijo: true) else { return nil }

        var finContenido = finPrincipal
        // Si ya identificamos una cabecera y contenido, toleramos el formato
        // continuo que suele producir Apple: "..., contenido y después envía".
        // Aceptamos ese corte solo si la cola contiene una etapa real.
        var sufijoEfectivo = sufijo
        if sufijoEfectivo == nil, let inicioContenido,
           let candidato = rangoSufijoDentroDelContenido(texto, desde: inicioContenido) {
            let inicioCandidato = min(ns.length, fin(candidato))
            let cola = NSRange(location: inicioCandidato, length: ns.length - inicioCandidato)
            if parsearRegion(texto, rango: cola, catalogo: catalogo, exigirPrefijo: false) != nil {
                sufijoEfectivo = candidato
            }
        }
        if let sufijo = sufijoEfectivo {
            let inicioSufijo = min(ns.length, fin(sufijo))
            let r = NSRange(location: inicioSufijo, length: ns.length - inicioSufijo)
            if let extra = parsearRegion(texto, rango: r, catalogo: catalogo, exigirPrefijo: false) {
                for m in extra.transforms { agregarTransform(m, a: &principal) }
                for a in extra.acciones { agregarAccion(a, a: &principal) }
                principal.confianza = max(principal.confianza, extra.confianza)
                finContenido = sufijo.location   // no incluye el punto que introduce "Luego…"
            }
        }

        if inicioContenido == nil, let ultimo = principal.ultimoComando {
            let ts = tokens(texto, rango: NSRange(location: 0, length: limitePrefijo))
            if ultimo < ts.count { inicioContenido = fin(ts[ultimo].rango) }
        }
        guard var inicio = inicioContenido, inicio <= finContenido else { return nil }
        inicio = saltarMarcador(texto, desde: inicio, hasta: finContenido)
        let bruto = ns.substring(with: NSRange(location: inicio, length: max(0, finContenido - inicio)))
        let contenido = limpiarContenido(bruto)
        let soloControlMusical = principal.transforms.isEmpty && !principal.acciones.isEmpty
            && principal.acciones.allSatisfy {
                $0.modo.base == "musica"
                    && ComandoMusica(rawValue: $0.modo.musicaAccion)?.intencion == nil
            }
        guard soloControlMusical
                || contenido.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }

        let cadena = ModoCadena(transforms: principal.transforms,
                                acciones: principal.acciones,
                                contenido: contenido)
        // El agente tiene un ciclo propio (herramientas, TTS, cancelación). Hasta
        // que exponga una salida encadenable, no fingimos que puede ser una etapa
        // intermedia: pedido ambiguo → cae al flujo normal/árbitro.
        if cadena.transforms.contains(where: { $0.base == "agente" }), cadena.etapas.count > 1 {
            return nil
        }
        var alternativas: [String] = []
        let pasos = principal.transforms.map { descripcionEtapa($0) }
            + principal.acciones.map { descripcionEtapa($0.modo, destinatario: $0.destinatario) }
        // Para un plan largo, las otras lecturas útiles son prefijos ejecutables:
        // 1) solo traducir; 2) traducir + correo; el plan principal añade WhatsApp.
        if pasos.count > 1 {
            for n in 1..<min(pasos.count, 4) {
                alternativas.append(pasos.prefix(n).joined(separator: " → "))
            }
        }
        return pregunta(para: cadena, fuente: .natural,
                        confianza: principal.confianza, alternativas: alternativas)
    }

    /// Señal conservadora para activar el fallback semántico natural. No basta con
    /// mencionar un sustantivo de modo; debe haber una forma de petición al inicio.
    static func pareceSolicitudNatural(_ texto: String) -> Bool {
        let ts = tokens(texto)
        guard !ts.isEmpty else { return false }
        let zona = ts.prefix(min(8, ts.count)).map(\.normal)
        let pide = zona.contains(where: prefijoSolicitud.contains)
        let verbo = zona.contains { verbosTraducir.contains($0) || verbosResumir.contains($0)
            || verbosFormalizar.contains($0) || verbosBuscar.contains($0)
            || verbosEnvio.contains($0) || verbosRedactar.contains($0)
            || verbosGenerar.contains($0)
            || verbosGuardar.contains($0) || verbosAbrir.contains($0) || verbosAgente.contains($0)
            || verbosMusica.contains($0) || verbosRecordar.contains($0)
            || verbosAgendar.contains($0) || verbosArchivo.contains($0) }
        return pide && verbo
    }

    /// Puerta conservadora para el último árbitro. Una simple mención a "correo"
    /// o "traducir" dentro de una narración no basta: debe haber al inicio una
    /// forma de petición/comando y una pista de un modo existente.
    static func parecePedidoParaArbitraje(_ texto: String) -> Bool {
        let ts = tokens(texto)
        guard !ts.isEmpty else { return false }
        if let primero = ts.first?.normal,
           ModoResolver.palabrasModoSeguras.contains(primero) { return true }
        let zona = Array(ts.prefix(min(12, ts.count)).map(\.normal))
        for i in zona.indices {
            let t = zona[i]
            let esVerbo = verbosTraducir.contains(t) || verbosResumir.contains(t)
                || verbosFormalizar.contains(t) || verbosBuscar.contains(t)
                || verbosEnvio.contains(t) || verbosRedactar.contains(t)
                || verbosGenerar.contains(t)
                || verbosGuardar.contains(t) || verbosAbrir.contains(t) || verbosAgente.contains(t)
                || verbosMusica.contains(t) || verbosRecordar.contains(t)
                || verbosAgendar.contains(t) || verbosArchivo.contains(t)
            guard esVerbo, i <= 8,
                  i == 0 || zona[..<i].allSatisfy({ prefijoSolicitud.contains($0) }) else { continue }

            // Verbos genéricos necesitan un objeto que los convierta en modo.
            let cerca = zona.dropFirst(i + 1).prefix(7)
            if verbosEnvio.contains(t) {
                if cerca.contains(where: { mediosEnvio[$0] != nil }) { return true }
                continue
            }
            if verbosRedactar.contains(t) || verbosGenerar.contains(t) || verbosGuardar.contains(t) {
                if cerca.contains(where: { ["correo", "email", "mail", "oficio", "memorando",
                                            "nota", "notas", "tarea", "pendiente", "recordatorio"].contains($0)
                                            || objetosGeneracion.contains($0) }) {
                    return true
                }
                continue
            }
            if verbosAbrir.contains(t) {
                if cerca.contains(where: { ModosStore.resolverVerbo($0)?.tipo == "accion" }) { return true }
                var candidatos = Array(cerca)
                let relleno: Set<String> = ["la", "el", "una", "un", "aplicacion", "app", "programa", "de"]
                while let primero = candidatos.first, relleno.contains(primero) { candidatos.removeFirst() }
                if Config.modoAplicaciones(),
                   case .encontrada = AplicacionesMac.resolverPrefijo(candidatos) { return true }
                continue
            }
            if verbosAgente.contains(t) {
                if cerca.contains(where: { ["agente", "gente", "asistente"].contains($0) }) { return true }
                continue
            }
            return true
        }
        return false
    }

    static func zonaSemantica(_ texto: String) -> String {
        let ns = texto as NSString
        var partes: [String] = []
        if let dos = primerSeparador(texto, antesDe: ns.length,
                                     caracteres: CharacterSet(charactersIn: ":")) {
            partes.append(ns.substring(with: NSRange(location: 0, length: dos)))
        } else {
            partes.append(tokens(texto).prefix(Config.modoIAPalabras()).map(\.original).joined(separator: " "))
        }
        if let sufijo = rangoSufijoSecuencial(texto) {
            let inicio = fin(sufijo)
            let cola = tokens(texto, rango: NSRange(location: inicio, length: ns.length - inicio))
                .prefix(min(14, Config.modoIAPalabras())).map(\.original).joined(separator: " ")
            if !cola.isEmpty { partes.append("DESPUÉS: " + cola) }
        }
        return partes.joined(separator: " … ")
    }

    /// Conserva el texto original y corta únicamente las zonas de orden. Los
    /// conteos de la IA se validan y solo se usan cuando no hay separadores más
    /// seguros (dos puntos / "y después").
    static func conteosArbitrajeValidos(_ texto: String, prefijoPalabras: Int,
                                        sufijoPalabras: Int) -> Bool {
        guard prefijoPalabras >= 0, sufijoPalabras >= 0 else { return false }
        let ts = tokens(texto)
        guard !ts.isEmpty else { return false }
        let ns = texto as NSString
        let sufijoSeguro = rangoSufijoSecuencial(texto)
        let finContenido = sufijoSeguro?.location ?? ns.length
        let tieneDosPuntos = primerSeparador(texto, antesDe: finContenido,
                                             caracteres: CharacterSet(charactersIn: ":")) != nil
        let maxPrefijo = min(Config.modoIAPalabras(), max(0, ts.count - 1))
        guard prefijoPalabras <= maxPrefijo, sufijoPalabras <= min(14, ts.count) else { return false }
        if tieneDosPuntos { return true } // el corte real lo decide la puntuación, no la IA
        guard prefijoPalabras >= 1 else { return false }
        if sufijoPalabras > 0, sufijoSeguro == nil { return false }
        return prefijoPalabras + sufijoPalabras < ts.count
    }

    static func contenidoParaArbitraje(_ texto: String, prefijoPalabras: Int,
                                       sufijoPalabras: Int) -> String {
        let ns = texto as NSString
        let sufijo = rangoSufijoSecuencial(texto)
        let finContenido = sufijo?.location ?? ns.length
        if let dos = primerSeparador(texto, antesDe: finContenido,
                                     caracteres: CharacterSet(charactersIn: ":")) {
            return limpiarContenido(ns.substring(with: NSRange(location: dos + 1,
                                                                 length: max(0, finContenido - dos - 1))))
        }
        let ts = tokens(texto)
        guard !ts.isEmpty else { return texto }
        let pre = min(max(0, prefijoPalabras), ts.count)
        let suf = min(max(0, sufijoPalabras), max(0, ts.count - pre))
        let inicio = pre < ts.count ? ts[pre].rango.location : ns.length
        let finRango = suf > 0 ? ts[ts.count - suf].rango.location : finContenido
        guard inicio < min(finRango, finContenido) else { return "" }
        return limpiarContenido(ns.substring(with: NSRange(location: inicio,
                                                             length: min(finRango, finContenido) - inicio)))
    }
}
