import Foundation

// MARK: - Fonética española (Metaphone adaptado) para corrección por sonido
//
// Convierte una palabra en un código de cómo SUENA en español, normalizando
// las consonantes que comparten sonido (k/qu/c, b/v, s/z/c-suave, j/g-suave,
// y/ll, x/ks). Así "Zentrix", "Sentrix", "Gentrix" caen en códigos muy cercanos.
//
// NO se usa solo: siempre con un doble candado (sonido + escritura parecidos)
// para no sobre-corregir palabras que apenas suenan parecido.

enum Fonetica {
    /// Código fonético español de una palabra (mayúsculas, sin acentos,
    /// consonantes normalizadas por sonido, vocales conservadas).
    static func codigo(_ palabra: String) -> String {
        let acentos: [Character: Character] = [
            "Á": "A", "À": "A", "É": "E", "È": "E", "Í": "I", "Ì": "I",
            "Ó": "O", "Ò": "O", "Ú": "U", "Ù": "U", "Ü": "U",
        ]
        let s = String(palabra.uppercased().compactMap { c -> Character? in
            let a = acentos[c] ?? c
            return a.isLetter ? a : nil
        })
        let ch = Array(s)
        let n = ch.count
        func at(_ i: Int) -> Character { (i >= 0 && i < n) ? ch[i] : " " }
        let vocales: Set<Character> = ["A", "E", "I", "O", "U"]

        var out = ""
        var i = 0
        while i < n {
            let c = ch[i], sig = at(i + 1)
            // Saltar letra repetida (LL y RR se tratan aparte).
            if c == at(i + 1), c != "L", c != "R" { i += 1; continue }
            switch c {
            case "A", "E", "I", "O", "U":
                out.append(c)
            case "B", "V":            // suenan igual
                out.append("B")
            case "C":
                if sig == "H" { out.append("X"); i += 1 }          // CH → X
                else if sig == "E" || sig == "I" { out.append("S") } // CE/CI → S
                else { out.append("K") }                            // CA/CO/CU/C → K
            case "Z":  out.append("S")                              // Z → S
            case "Q":
                if sig == "U" { out.append("K"); i += 1 }           // QU → K (u muda)
                else { out.append("K") }
            case "K":  out.append("K")
            case "G":
                if sig == "E" || sig == "I" { out.append("J") }     // GE/GI → J
                else if sig == "U" && (at(i + 2) == "E" || at(i + 2) == "I") {
                    out.append("G"); i += 1                          // GUE/GUI → G (u muda)
                } else { out.append("G") }
            case "J":  out.append("J")
            case "H":
                break                                                // H muda
            case "L":
                if sig == "L" { out.append("Y"); i += 1 }           // LL → Y
                else { out.append("L") }
            case "Y":
                out.append(vocales.contains(sig) || out.isEmpty ? "Y" : "I")
            case "Ñ":  out.append("N")
            case "R":
                if sig == "R" { out.append("R"); i += 1 } else { out.append("R") }
            case "W":  out.append("B")
            case "X":  out.append("KS")                             // X → KS
            case "P", "T", "D", "F", "M", "N", "S":
                out.append(c)
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// Distancia de edición (Levenshtein).
    static func distancia(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }; if t.isEmpty { return s.count }
        var fila = Array(0...t.count)
        for i in 1...s.count {
            var prev = fila[0]; fila[0] = i
            for j in 1...t.count {
                let tmp = fila[j]
                fila[j] = s[i - 1] == t[j - 1] ? prev : min(prev, fila[j], fila[j - 1]) + 1
                prev = tmp
            }
        }
        return fila[t.count]
    }

    /// ¿"palabra" suena Y se escribe suficientemente parecido a "termino"
    /// como para corregirla? DOBLE candado, conservador a propósito.
    static func coincide(palabra: String, termino: String) -> Bool {
        let p = palabra.lowercased(), t = termino.lowercased()
        guard p != t, p.count >= 3 else { return false }
        // 1) el sonido: los códigos fonéticos casi idénticos.
        let fp = codigo(palabra), ft = codigo(termino)
        guard distancia(fp, ft) <= 1 else { return false }
        // 2) la escritura: no demasiado lejos (evita falsos por puro sonido).
        let umbral = max(2, Int(Double(max(p.count, t.count)) * 0.4))
        return distancia(p, t) <= umbral
    }
}
