import Foundation

/// Intérprete local de órdenes largas como:
/// “abre Gmail y escribe un correo para a@b.com: …” o
/// “abre Word y crea un oficio completo: …”.
///
/// Solo estructura intención y campos; no abre ni envía nada. El plan resultante
/// atraviesa la política normal de autonomía/confirmación de BtoDicta.
enum OrdenEstructurada {
    private struct Token {
        let original: String
        let normal: String
        let rango: NSRange
    }

    private enum Formato {
        case correo, oficio, documento
    }

    private static let palabras = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’_.@+-]*"#)
    private static let correos = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive])
    private static let correoHablado = try! NSRegularExpression(
        pattern: #"\b(?:para|a)\s+((?:[a-z0-9]+\s+){0,5}[a-z0-9]+)\s+arroba\s+((?:[a-z0-9]+\s*){1,2})\s+punto\s+([a-z]{2,})(?:\s+punto\s+([a-z]{2,}))?\b"#,
        options: [.caseInsensitive])
    private static let cuerpoSeccion = try! NSRegularExpression(
        pattern: #"\b(?:cuerpo|mensaje|contenido)\s*:\s*([\s\S]+)$"#,
        options: [.caseInsensitive])
    private static let asuntoSeccion = try! NSRegularExpression(
        pattern: #"\basunto\s*:\s*([\s\S]+?)(?=\b(?:cuerpo|mensaje|contenido)\s*:)"#,
        options: [.caseInsensitive])
    private static let marcadorContenido = try! NSRegularExpression(
        pattern: #"\b(?:(?:que\s+)?(?:diga|diciendo)(?:\s+(?:lo\s+siguiente|el\s+siguiente\s+texto|el\s+texto|este\s+texto|este\s+mensaje))?|con\s+(?:lo\s+siguiente|el\s+siguiente\s+texto|el\s+texto|este\s+texto|este\s+mensaje))\b"#,
        options: [.caseInsensitive])
    private static let nombreArchivo = try! NSRegularExpression(
        pattern: #"\b(?:llamado|llamada|con\s+(?:el\s+)?nombre)\s+[\"“]?([^\"”:,;]+?)[\"”]?(?=\s+(?:que|con|y)\b|[:;,]|$)"#,
        options: [.caseInsensitive])

    private static let verbosAbrir: Set<String> = [
        "abre", "abrir", "abreme", "abra", "abras", "lanza", "lanzar", "inicia", "iniciar"
    ]
    private static let verbosRedactar: Set<String> = [
        "escribe", "escribeme", "escribir", "redacta", "redactame", "redactar",
        "crea", "creame", "crear", "prepara", "preparame", "preparar",
        "elabora", "elaborame", "elaborar", "genera", "generame", "generar", "haz", "hazme"
    ]
    private static let cortesias: Set<String> = [
        "por", "favor", "porfavor", "porfa", "oye", "hey", "beto", "btodicta",
        "jarvis", "quiero", "quisiera", "necesito", "puedes", "podrias", "podria",
        "me", "ayuda", "ayudame", "a", "que", "te", "pido", "deseo"
    ]

    private static func tokenizar(_ texto: String) -> [Token] {
        let ns = texto as NSString
        return palabras.matches(in: texto, range: NSRange(location: 0, length: ns.length)).map {
            let o = ns.substring(with: $0.range)
            return Token(original: o, normal: PerfilAgente.normalizar(o), rango: $0.range)
        }
    }

    private static func fin(_ r: NSRange) -> Int { r.location + r.length }

    private static func modoAccion(_ id: String) -> Modo {
        Modo(id: "orden-\(id)", nombre: Acciones.nombre(id), icono: "doc.badge.plus",
             base: "accion", accion: id)
    }

    private static func formato(en ts: [Token], destino: Modo?) -> (Formato, Int)? {
        for (i, t) in ts.prefix(26).enumerated() {
            if ["correo", "email", "mail"].contains(t.normal) { return (.correo, i) }
            if ["oficio", "memorando", "memorandum"].contains(t.normal) { return (.oficio, i) }
            if ["documento", "carta", "informe", "solicitud"].contains(t.normal) { return (.documento, i) }
        }
        if let id = destino?.accion, ["gmail", "correo", "outlook"].contains(id) {
            return (.correo, 0)
        }
        return nil
    }

    private static func accionPersonalizada(desde inicio: Int, ts: [Token],
                                             catalogo: ModoCatalogo) -> (Modo, Int)? {
        guard inicio < ts.count else { return nil }
        for m in catalogo.modos where m.base == "accion" && m.accion == "url"
            && Acciones.plantillaURLSegura(m.prompt) {
            let nombre = ModoResolver.tokensNormalizados(m.nombre)
            guard !nombre.isEmpty, inicio + nombre.count <= ts.count,
                  Array(ts[inicio..<(inicio + nombre.count)].map(\.normal)) == nombre else { continue }
            return (m, inicio + nombre.count - 1)
        }
        return nil
    }

    private static func destino(en ts: [Token], catalogo: ModoCatalogo,
                                aplicaciones: [AplicacionMac]?) -> (Modo, Int)? {
        let zona = Array(ts.prefix(26))
        guard let abrir = zona.firstIndex(where: { verbosAbrir.contains($0.normal) }) else {
            // Variante sin “abre”: “escribe EN Gmail un correo…”. El proveedor
            // debe estar unido al verbo por una preposición; una mención a Gmail
            // dentro del contenido nunca gana como destino.
            guard let redactar = zona.firstIndex(where: { verbosRedactar.contains($0.normal) }) else { return nil }
            let limite = min(zona.count, redactar + 9)
            if redactar + 1 < limite {
                for i in (redactar + 1)..<limite where ["gmail", "outlook", "hotmail"].contains(zona[i].normal) {
                    let previos = zona[redactar..<i].map(\.normal)
                    guard previos.contains(where: { ["en", "con", "usando", "mediante"].contains($0) }) else { continue }
                    return (modoAccion(zona[i].normal == "gmail" ? "gmail" : "outlook"), i)
                }
            }
            return nil
        }
        var j = abrir + 1
        let relleno: Set<String> = ["la", "el", "una", "un", "aplicacion", "app", "programa", "pagina", "web", "de"]
        while j < ts.count, relleno.contains(ts[j].normal) { j += 1 }
        guard j < ts.count else { return nil }
        if ts[j].normal == "gmail" { return (modoAccion("gmail"), j) }
        if ["outlook", "hotmail"].contains(ts[j].normal) { return (modoAccion("outlook"), j) }
        if ["correo", "mail"].contains(ts[j].normal) { return (modoAccion("correo"), j) }
        if let personalizado = accionPersonalizada(desde: j, ts: ts, catalogo: catalogo) {
            return personalizado
        }
        let resto = Array(ts[j...].map(\.normal))
        switch AplicacionesMac.resolverPrefijo(resto, en: aplicaciones) {
        case .encontrada(let match):
            let base = catalogo.modos.first(where: { $0.id == "aplicacion" })
                ?? Modo(id: "aplicacion", nombre: "Aplicación", icono: "square.grid.2x2.fill", base: "aplicacion")
            return (AplicacionesMac.aplicar(match, a: base), j + match.palabrasConsumidas - 1)
        case .ambiguas, .ninguna: return nil
        }
    }

    private static func extraerCorreos(_ texto: String) -> String? {
        let ns = texto as NSString
        var vistos = Set<String>()
        let lista = correos.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
            .filter { vistos.insert($0.lowercased()).inserted }
        if !lista.isEmpty { return lista.joined(separator: ",") }

        // Un motor puede escribir lo que oyó (“ana perez arroba example punto
        // com”) en lugar de reconstruir la dirección. Se normaliza solo dentro
        // de una cláusula `para/a … arroba … punto …`; nunca se adivina desde
        // palabras sueltas del cuerpo.
        let hablado = PerfilAgente.normalizar(texto)
            .replacingOccurrences(of: "guion bajo", with: "guionbajo")
        let hns = hablado as NSString
        guard let m = correoHablado.firstMatch(in: hablado,
            range: NSRange(location: 0, length: hns.length)), m.numberOfRanges >= 4 else { return nil }
        func parte(_ i: Int) -> String {
            guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound else { return "" }
            return hns.substring(with: m.range(at: i)).replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "guionbajo", with: "_")
        }
        let candidato = parte(1) + "@" + parte(2) + "." + parte(3)
            + (parte(4).isEmpty ? "" : "." + parte(4))
        let cns = candidato as NSString
        guard let v = correos.firstMatch(in: candidato,
            range: NSRange(location: 0, length: cns.length)), v.range.length == cns.length else { return nil }
        return candidato
    }

    private static func grupo(_ re: NSRegularExpression, en texto: String) -> (String, NSRange)? {
        let ns = texto as NSString
        guard let m = re.firstMatch(in: texto, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return (ns.substring(with: m.range(at: 1)), m.range(at: 1))
    }

    private static func nombreSugeridoArchivo(_ texto: String) -> String? {
        guard let s = grupo(nombreArchivo, en: texto)?.0
            .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func limpiarContenido(_ texto: String) -> String {
        var t = texto.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,:;—-\"“”«»"))
        t = t.replacingOccurrences(of: #"^(?:y\s+)?(?:que\s+)?(?:diga|dice)\s*"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dos puntos que separan la orden del contenido. Omite horas (`10:30`) y
    /// esquemas (`https://`) para no cortar dentro del texto real.
    private static func separadorCabecera(_ texto: String, desde: Int) -> Int? {
        let ns = texto as NSString
        guard desde >= 0, desde < ns.length else { return nil }
        for i in desde..<ns.length where ns.character(at: i) == 58 { // :
            let anterior = i > 0 ? UnicodeScalar(ns.character(at: i - 1)) : nil
            let siguiente = i + 1 < ns.length ? UnicodeScalar(ns.character(at: i + 1)) : nil
            if let a = anterior, let s = siguiente,
               CharacterSet.decimalDigits.contains(a), CharacterSet.decimalDigits.contains(s) { continue }
            if siguiente?.value == 47 { continue }
            return i
        }
        return nil
    }

    private static func finDestinatarioCorreo(_ ts: [Token]) -> Int? {
        if let t = ts.first(where: { $0.original.contains("@") }) {
            let direccion = t.original.trimmingCharacters(
                in: CharacterSet(charactersIn: ",.;:!?¡¿"))
            return t.rango.location + (direccion as NSString).length
        }
        guard let arroba = ts.firstIndex(where: { $0.normal == "arroba" }), arroba + 2 < ts.count,
              let punto = ts[(arroba + 1)...].firstIndex(where: { $0.normal == "punto" }),
              punto + 1 < ts.count else { return nil }
        var ultimo = punto + 1
        if punto + 2 < ts.count, ts[punto + 2].normal == "punto", punto + 3 < ts.count {
            ultimo = punto + 3
        }
        return fin(ts[ultimo].rango)
    }

    private static func separadorOracion(_ texto: String, desde: Int) -> Int? {
        let ns = texto as NSString
        guard desde >= 0, desde < ns.length else { return nil }
        for i in desde..<ns.length where [33, 46, 63].contains(Int(ns.character(at: i))) {
            guard i + 1 >= ns.length
                    || UnicodeScalar(ns.character(at: i + 1)).map(CharacterSet.whitespacesAndNewlines.contains) == true else { continue }
            return i
        }
        return nil
    }

    private static func campos(_ texto: String, ts: [Token], indiceFormato: Int,
                               ultimoDestino: Int, ultimoVerbo: Int) -> (contenido: String, asunto: String?) {
        if let cuerpo = grupo(cuerpoSeccion, en: texto) {
            let asunto = grupo(asuntoSeccion, en: texto)?.0
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n,.;:\"“”«»"))
            return (limpiarContenido(cuerpo.0), asunto?.isEmpty == false ? asunto : nil)
        }
        let ns = texto as NSString
        let desde = [indiceFormato, ultimoDestino, ultimoVerbo].filter { $0 >= 0 && $0 < ts.count }
            .map { fin(ts[$0].rango) }.max() ?? 0
        if let dos = separadorCabecera(texto, desde: desde) {
            return (limpiarContenido(ns.substring(from: dos + 1)), nil)
        }
        if desde < ns.length,
           let marcador = marcadorContenido.firstMatch(in: texto,
                range: NSRange(location: desde, length: ns.length - desde)) {
            let inicio = NSMaxRange(marcador.range)
            return (limpiarContenido(ns.substring(from: inicio)), nil)
        }
        // Apple Speech suele sustituir “:” por punto. Si antes del punto hay una
        // dirección (literal o “arroba/punto”), todo lo posterior es el cuerpo;
        // así la dirección no termina dentro del texto redactado.
        if let finCorreo = finDestinatarioCorreo(ts),
           let punto = separadorOracion(texto, desde: finCorreo), punto + 1 < ns.length {
            return (limpiarContenido(ns.substring(from: punto + 1)), nil)
        }
        guard indiceFormato >= 0, indiceFormato < ts.count else { return ("", nil) }
        return (limpiarContenido(ns.substring(from: fin(ts[indiceFormato].rango))), nil)
    }

    private static func transformar(_ formato: Formato, catalogo: ModoCatalogo,
                                    asunto: String?) -> Modo {
        switch formato {
        case .correo:
            var m = catalogo.modos.first(where: { $0.id == "correo" })
                ?? Modo(id: "correo", nombre: "Correo", icono: "envelope.fill", base: "pulir")
            m.nombre = "Correo estructurado"
            let reglaAsunto = asunto.map { "La primera línea debe ser exactamente ASUNTO: \($0)." }
                ?? "La primera línea debe ser ASUNTO: seguido de un asunto breve y útil que resuma el pedido."
            m.prompt += "\n\(reglaAsunto) Luego deja una línea en blanco y escribe saludo, cuerpo y despedida. No inventes destinatarios ni hechos. Devuelve únicamente ese borrador."
            return m
        case .oficio:
            var m = catalogo.modos.first(where: { $0.id == "oficio" })
                ?? Modo(id: "oficio", nombre: "Oficio", icono: "doc.text.fill", base: "pulir")
            m.prompt += "\nConstruye el documento completo solicitado. Incluye encabezado, fecha, destinatario, asunto, cuerpo y cierre cuando los datos existan; usa campos claramente marcados cuando falten y no inventes nombres, cargos ni números."
            return m
        case .documento:
            return Modo(id: "documento-estructurado", nombre: "Documento estructurado",
                        icono: "doc.richtext", base: "pulir",
                        prompt: "Redacta el documento solicitado con estructura profesional y clara. Sigue las condiciones del usuario, conserva sus datos y no inventes nombres, fechas ni hechos. Si falta un dato indispensable, usa un campo entre corchetes. Devuelve solo el documento final.")
        }
    }

    static func detectar(_ texto: String,
                         catalogo: ModoCatalogo = ModoCatalogoCache.actual(),
                         aplicaciones: [AplicacionMac]? = nil) -> ModoPreguntaPlan? {
        let ts = tokenizar(texto)
        guard !ts.isEmpty else { return nil }
        let zona = Array(ts.prefix(26))
        let indicesComando = zona.indices.filter {
            verbosAbrir.contains(zona[$0].normal) || verbosRedactar.contains(zona[$0].normal)
        }
        guard let primero = indicesComando.first, primero <= 8,
              primero == 0 || zona[..<primero].allSatisfy({ cortesias.contains($0.normal) }),
              let redaccion = indicesComando.first(where: { verbosRedactar.contains(zona[$0].normal) }) else {
            return nil
        }

        var d = destino(en: ts, catalogo: catalogo, aplicaciones: aplicaciones)
        var f = formato(en: ts, destino: d?.0)
        if d == nil, let archivo = zona.firstIndex(where: { $0.normal == "archivo" }) {
            d = (modoAccion("archivo_nuevo"), archivo)
            f = (.documento, archivo)
        }
        guard let (tipo, indiceFormato) = f else { return nil }
        guard let (accion, finDestino) = d else { return nil }

        let datos = campos(texto, ts: ts, indiceFormato: indiceFormato,
                           ultimoDestino: finDestino, ultimoVerbo: redaccion)
        guard datos.contenido.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        let transforms = accion.accion == "archivo_nuevo" ? []
            : [transformar(tipo, catalogo: catalogo, asunto: datos.asunto)]
        let destinatario = ["gmail", "correo", "outlook"].contains(accion.accion)
            ? extraerCorreos(texto) : nil
        let etapa = ModoAccionPlan(modo: accion, destinatario: destinatario,
                                   asunto: datos.asunto,
                                   nombreArchivo: accion.accion == "archivo_nuevo"
                                    ? nombreSugeridoArchivo(texto) : nil)
        return ModoPlanificador.pregunta(
            para: ModoCadena(transforms: transforms, acciones: [etapa],
                              contenido: datos.contenido),
            fuente: .natural, confianza: 0.98)
    }
}
