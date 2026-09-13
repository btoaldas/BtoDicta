import Foundation

/// Lista editable de frases habladas. Acepta una frase por línea y conserva la
/// compatibilidad histórica con comas. Las comas DENTRO de una frase se pueden
/// proteger con comillas: `"Oye, Bto"`.
enum FrasesConfigurables {
    /// Un activador de una sola palabra convierte expresiones normales como
    /// "Oye, qué tontera" en una invocación accidental del agente. Exigir dos
    /// palabras conserva nombres libres ("Oye mamá", "Hola Jarvis", etc.) y
    /// mantiene la activación deliberada.
    static func activadorSeguro(_ frase: String) -> Bool {
        PerfilAgente.normalizar(frase).split(separator: " ").count >= 2
    }

    static func activadoresSeguros(_ frases: [String]) -> [String] {
        frases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && activadorSeguro($0) }
    }

    static func parsear(_ texto: String) -> [String] {
        var salida: [String] = []
        var actual = ""
        var cierreComilla: Character?
        var i = texto.startIndex

        func agregar() {
            let t = actual.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !salida.contains(where: {
                PerfilAgente.normalizar($0) == PerfilAgente.normalizar(t)
            }) { salida.append(t) }
            actual = ""
        }

        while i < texto.endIndex {
            let c = texto[i]
            if let cierre = cierreComilla, c == cierre {
                let siguiente = texto.index(after: i)
                if cierre == "\"", siguiente < texto.endIndex, texto[siguiente] == "\"" {
                    actual.append("\""); i = siguiente
                } else {
                    cierreComilla = nil
                }
            } else if cierreComilla == nil, ["\"", "“", "«"].contains(c) {
                cierreComilla = c == "“" ? "”" : (c == "«" ? "»" : "\"")
            } else if cierreComilla == nil, c == "," || c == "\n" || c == "\r" {
                agregar()
            } else {
                actual.append(c)
            }
            i = texto.index(after: i)
        }
        agregar()
        return salida
    }

    static func formatear(_ frases: [String], multilinea: Bool = true) -> String {
        let separador = multilinea ? "\n" : ", "
        return frases.map { frase in
            let t = frase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.contains(",") || t.contains("\"") || t.contains("\n") else { return t }
            return "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.filter { !$0.isEmpty }.joined(separator: separador)
    }
}
