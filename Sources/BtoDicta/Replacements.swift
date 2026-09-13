import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Reemplazos (palabra completa, sin distinguir mayúsculas)

func applyReplacements(_ text: String) -> String {
    var result = text
    let rules = Config.replacements().sorted { $0.original.count > $1.original.count }
    for rule in rules {
        if rule.isRegex == true {
            if let regex = try? NSRegularExpression(pattern: rule.original, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range,
                                                        withTemplate: rule.replacement)
            }
            continue
        }
        let variants = rule.original.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
        for variant in variants {
            let escaped = NSRegularExpression.escapedPattern(for: variant)
            let pattern = "(?<![\\p{L}\\p{N}])" + escaped + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, options: [], range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: rule.replacement))
        }
    }
    // Corrección por SONIDO (opt-in global + por término): corrige palabras
    // que suenan como un término marcado, con triple candado anti-abuso.
    if Config.correccionPorSonido() {
        let terminos = rules.filter { $0.porSonido == true && $0.isRegex != true }.map { $0.replacement }
        if !terminos.isEmpty { result = corregirPorSonido(result, terminos: terminos) }
    }
    return result
}

/// Reemplaza palabras que SUENAN como uno de los términos (y se escriben
/// parecido, y no son palabras comunes). Cada corrección queda en el log.
private func corregirPorSonido(_ texto: String, terminos: [String]) -> String {
    guard let regex = try? NSRegularExpression(pattern: "\\p{L}[\\p{L}\\p{N}]*") else { return texto }
    let ns = texto as NSString
    var resultado = texto
    var offset = 0
    for m in regex.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
        let palabra = ns.substring(with: m.range)
        // No tocar palabras comunes ni las que ya son un término correcto.
        guard palabra.count >= 3, !Aprendizaje.esComun(palabra),
              !terminos.contains(where: { $0.caseInsensitiveCompare(palabra) == .orderedSame }) else { continue }
        guard let termino = terminos.first(where: { Fonetica.coincide(palabra: palabra, termino: $0) }) else { continue }
        // Aplicar sobre el resultado (ajustando el desplazamiento acumulado).
        if let r = Range(NSRange(location: m.range.location + offset, length: m.range.length), in: resultado) {
            resultado.replaceSubrange(r, with: termino)
            offset += termino.utf16.count - m.range.length
            Log.log(.config, "corrección por sonido: \(palabra) → \(termino)")
            Aprendizaje.registrarSonido(de: palabra, a: termino)
        }
    }
    return resultado
}

