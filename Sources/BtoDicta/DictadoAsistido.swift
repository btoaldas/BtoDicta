import Foundation

/// Orden explícita de escritura dentro de un turno del Asistente. Se mantiene
/// separada del planificador general porque su destino no es una app ni una IA:
/// es el campo que ya estaba activo cuando comenzó el dictado.
struct SolicitudDictadoAsistido: Equatable {
    enum Operacion: String {
        case dictar
        case transcribir
        case escribir
        case corregir
        case actualizar
        case mejorar
    }

    let operacion: Operacion
    let frase: String
    let contenido: String
}

/// Intérprete local y conservador. Solo lo llama AppDelegate después de haber
/// confirmado que el turno pertenece al Asistente; aun así, exige una orden al
/// INICIO para no confundir una narración normal con una acción.
enum DictadoAsistido {
    private struct Patron {
        let operacion: SolicitudDictadoAsistido.Operacion
        let expresion: NSRegularExpression
    }

    private static let cortesia = #"^\s*(?:(?:por\s+favor|porfa)\s*[,;:\-—–]?\s*)?"#
    private static let marcador = #"(?:esto|lo\s+siguiente|el\s+siguiente\s+texto|este\s+texto)"#

    private static func rx(_ cuerpo: String) -> NSRegularExpression {
        // Son expresiones constantes y cubiertas por QA; fallar al desarrollar
        // es preferible a aceptar silenciosamente una ruta insegura.
        try! NSRegularExpression(pattern: cortesia + cuerpo,
                                 options: [.caseInsensitive])
    }

    private static let patrones: [Patron] = [
        Patron(operacion: .dictar, expresion: rx(
            #"(?:crea|haz|prepara)(?:me)?\s+(?:un\s+)?dictado(?:\s+(?:de\s+)?"#
            + marcador + #")?(?=\s|[,.:;—–\-]|$)"#)),
        Patron(operacion: .dictar, expresion: rx(
            #"(?:dicta|d[ií]ctame)(?=\s|[,.:;—–\-]|$)(?:\s+"#
            + marcador + #")?"#)),
        Patron(operacion: .transcribir, expresion: rx(
            #"(?:transcribe|transcr[ií]beme)(?=\s|[,.:;—–\-]|$)(?:\s+"#
            + marcador + #")?"#)),
        // Estos verbos también pueden ordenar herramientas ("escribe un
        // correo", "actualiza el sistema"). Por eso solo entran aquí con el
        // marcador inequívoco "esto / lo siguiente / este texto".
        Patron(operacion: .escribir, expresion: rx(
            #"(?:escribe|escr[ií]beme)\s+"# + marcador
            + #"(?=\s|[,.:;—–\-]|$)"#)),
        Patron(operacion: .corregir, expresion: rx(
            #"(?:corrige|corr[ií]geme)\s+"# + marcador
            + #"(?=\s|[,.:;—–\-]|$)"#)),
        Patron(operacion: .actualizar, expresion: rx(
            #"(?:actualiza|actual[ií]zame)\s+"# + marcador
            + #"(?=\s|[,.:;—–\-]|$)"#)),
        Patron(operacion: .mejorar, expresion: rx(
            #"(?:mejora|mej[oó]rame)\s+"# + marcador
            + #"(?=\s|[,.:;—–\-]|$)"#)),
        // "Dictado" solo abre un segundo turno manos libres. Con contenido se
        // exige un separador: "dictado: mañana llego...".
        Patron(operacion: .dictar, expresion: rx(
            #"dictado(?=\s*[,.:;—–\-]|\s*$)"#)),
    ]

    static func detectar(_ texto: String) -> SolicitudDictadoAsistido? {
        let ns = texto as NSString
        let total = NSRange(location: 0, length: ns.length)
        for patron in patrones {
            guard let match = patron.expresion.firstMatch(in: texto, range: total),
                  match.range.location != NSNotFound else { continue }
            let fin = NSMaxRange(match.range)
            let frase = ns.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let separadores = CharacterSet(charactersIn: " \t\r\n,.:;—–-")
            let resto = ns.substring(from: fin)
            // Solo limpia ENTRE la orden y el contenido. `trimmingCharacters`
            // también quitaba el punto final de "nos vemos mañana.", alterando
            // justo el texto que prometemos conservar.
            let contenido = String(resto.drop(while: { caracter in
                caracter.unicodeScalars.allSatisfy { separadores.contains($0) }
            }))
            return SolicitudDictadoAsistido(operacion: patron.operacion,
                                            frase: frase,
                                            contenido: contenido)
        }
        return nil
    }

    static func esCancelacion(_ texto: String) -> Bool {
        let n = PerfilAgente.normalizar(texto)
        return ["cancela", "cancelar", "olvidalo", "dejalo"].contains(n)
    }
}
