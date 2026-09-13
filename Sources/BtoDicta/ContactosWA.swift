import Foundation
import Contacts

// MARK: - Contactos para el modo WhatsApp (Fase 5.5)
//
// Resuelve un NOMBRE a un NÚMERO para mandar directo al chat. Cascada:
//   1) lista IMPORTADA por el usuario (CSV/JSON: nombre,numero)
//   2) Contactos de macOS (permiso)
// 0 coincidencias → avisa · 1 exacta → directo · aproximada o 2+ → modal.

struct ContactoWA: Identifiable {
    let id = UUID()
    let nombre: String
    let numero: String   // solo dígitos y '+'
}

enum ContactosWA {
    private static var archivo: URL { Config.dir.appendingPathComponent("contactos_wa.json") }
    private static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespaces)
    }
    private static func soloNumero(_ s: String) -> String {
        String(s.filter { $0.isNumber || $0 == "+" })
    }

    // ---- Lista importada ----
    static func importados() -> [ContactoWA] {
        guard let d = try? Data(contentsOf: archivo),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return [] }
        Config.protegerSecreto(archivo) // migra instalaciones antiguas a 0600
        return arr.compactMap {
            let n = $0["nombre"] ?? ""; let num = soloNumero($0["numero"] ?? "")
            return n.isEmpty ? nil : ContactoWA(nombre: n, numero: num)
        }
    }
    private static func guardar(_ cs: [ContactoWA]) {
        Config.asegurarDirSeguro()
        let arr = cs.map { ["nombre": $0.nombre, "numero": $0.numero] }
        if let d = try? JSONSerialization.data(withJSONObject: arr) {
            try? d.write(to: archivo, options: .atomic)
            Config.protegerSecreto(archivo)
        }
    }
    static func vaciar() { try? FileManager.default.removeItem(at: archivo) }

    struct ImportResult { let validos: Int; let invalidos: Int; let total: Int; let detalle: String }

    /// Parser CSV REAL (comillas, comas dentro de campos, "" escapadas). Soporta ',' y ';'.
    static func parseCSV(_ text: String) -> [[String]] {
        let sep: Character = {
            let primera = text.prefix(while: { $0 != "\n" && $0 != "\r" })
            return (primera.contains(";") && !primera.contains(",")) ? ";" : ","
        }()
        // Swift agrupa "\r\n" como UN solo Character (grapheme) → normalizamos a "\n".
        let norm = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []; var row: [String] = []; var field = ""; var q = false
        var it = norm.makeIterator(); var pend: Character? = nil
        func next() -> Character? { if let p = pend { pend = nil; return p }; return it.next() }
        while let c = next() {
            if q {
                if c == "\"" {
                    if let n = next() { if n == "\"" { field.append("\"") } else { q = false; pend = n } }
                    else { q = false }
                } else { field.append(c) }
            } else if c == "\"" {
                q = true
            } else if c == sep {
                row.append(field); field = ""
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""
            } else if c == "\r" {
                // fin de línea Windows: se ignora (el \n cierra la fila)
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }
    /// Primer número de un campo (Google separa varios con ":::").
    private static func primerNumero(_ v: String) -> String {
        soloNumero(v.components(separatedBy: ":::").first ?? v)
    }
    /// Analiza el texto CSV → contactos (PURA, sin guardar; testeable). Detecta la
    /// cabecera (Google/Gmail: Name/First Name/Last Name + "Phone N - Value").
    static func analizarCSV(_ txt: String) -> (nuevos: [ContactoWA], validos: Int, invalidos: Int, detalle: String) {
        let rows = parseCSV(txt)
        guard rows.count > 1 else { return ([], 0, 0, "CSV vacío o sin filas") }
        let hn = rows[0].map { norm($0) }
        // Nombre COMPLETO solo si el encabezado lo es de verdad (no "First Name").
        let iName = hn.firstIndex { $0 == "name" || $0.contains("display name") || $0.contains("full name") || $0.contains("nombre completo") }
        let iFirst = hn.firstIndex { $0.contains("first name") || $0.contains("given name") || $0 == "nombre" || $0 == "primer nombre" || $0 == "nombres" }
        let iLast = hn.firstIndex { $0.contains("last name") || $0.contains("family name") || $0 == "apellido" || $0 == "apellidos" || $0 == "surname" }
        var phoneCols = hn.indices.filter { hn[$0].contains("phone") && hn[$0].contains("value") }   // Google "Phone 1 - Value"
        if phoneCols.isEmpty {
            let claves = ["numero", "number", "phone", "tel", "movil", "mobile", "celular", "whatsapp"]
            phoneCols = hn.indices.filter { h in claves.contains { hn[h].contains($0) } }
        }
        var nuevos: [ContactoWA] = []; var validos = 0, invalidos = 0
        if iName != nil || iFirst != nil, !phoneCols.isEmpty {
            for r in rows.dropFirst() where r.contains(where: { !$0.isEmpty }) {
                let nombre: String = {
                    if let iName, iName < r.count, !r[iName].isEmpty { return r[iName] }
                    let f = (iFirst.flatMap { $0 < r.count ? r[$0] : nil }) ?? ""
                    let l = (iLast.flatMap { $0 < r.count ? r[$0] : nil }) ?? ""
                    return [f, l].filter { !$0.isEmpty }.joined(separator: " ")
                }()
                let num = phoneCols.compactMap { $0 < r.count ? primerNumero(r[$0]) : nil }.first { !$0.isEmpty } ?? ""
                if !nombre.isEmpty, !num.isEmpty { nuevos.append(ContactoWA(nombre: nombre, numero: num)); validos += 1 } else { invalidos += 1 }
            }
            return (nuevos, validos, invalidos, "CSV cabecera (nombre col \(iName ?? iFirst ?? -1), tel cols \(phoneCols))")
        }
        for r in rows where r.count >= 2 {   // sin cabecera: nombre,numero
            let num = primerNumero(r[1])
            if !r[0].isEmpty, !num.isEmpty { nuevos.append(ContactoWA(nombre: r[0], numero: num)); validos += 1 } else { invalidos += 1 }
        }
        return (nuevos, validos, invalidos, "CSV sin cabecera (2 columnas)")
    }

    /// Analiza vCard (.vcf, el formato de iPhone/Android/iCloud/Outlook). PURA.
    static func analizarVCard(_ txt: String) -> (nuevos: [ContactoWA], validos: Int, invalidos: Int, detalle: String) {
        var out: [ContactoWA] = []; var v = 0, inv = 0
        var fn = "", nParts = "", tel = ""
        func valor(_ l: String) -> String { l.firstIndex(of: ":").map { String(l[l.index(after: $0)...]) } ?? "" }
        func nombreDeN(_ s: String) -> String {
            let c = s.components(separatedBy: ";")
            let given = c.count > 1 ? c[1] : "", family = c.first ?? ""
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
        func flush() {
            let nombre = (fn.isEmpty ? nombreDeN(nParts) : fn).trimmingCharacters(in: .whitespaces)
            if !nombre.isEmpty, !tel.isEmpty { out.append(ContactoWA(nombre: nombre, numero: tel)); v += 1 }
            else if !nombre.isEmpty || !tel.isEmpty { inv += 1 }
            fn = ""; nParts = ""; tel = ""
        }
        for raw in txt.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n") {
            let l = String(raw), up = l.uppercased()
            let prop = (l.firstIndex(of: ":").map { String(l[..<$0]) } ?? l).uppercased()
            if up.hasPrefix("BEGIN:VCARD") { fn = ""; nParts = ""; tel = "" }
            else if up.hasPrefix("END:VCARD") { flush() }
            else if prop == "FN" || prop.hasPrefix("FN;") { fn = valor(l) }
            else if prop == "N" || prop.hasPrefix("N;") { if fn.isEmpty { nParts = valor(l) } }
            else if prop.contains("TEL"), tel.isEmpty { tel = primerNumero(valor(l)) }
        }
        return (out, v, inv, "vCard (teléfono/iCloud/Outlook)")
    }

    /// Importa CSV (Google/Gmail/Outlook/Edge), JSON o vCard (.vcf, teléfonos). Auto-detecta.
    @discardableResult static func importar(_ url: URL) -> ImportResult {
        guard let txt = try? String(contentsOf: url, encoding: .utf8) else {
            Log.write("import contactos: no pude leer \(url.lastPathComponent)")
            return ImportResult(validos: 0, invalidos: 0, total: importados().count, detalle: "no se pudo leer el archivo")
        }
        var cs = importados()
        var validos = 0, invalidos = 0, detalle = ""
        let ext = url.pathExtension.lowercased()
        let esVCard = ext == "vcf" || txt.uppercased().contains("BEGIN:VCARD")
        if esVCard {
            let a = analizarVCard(txt)
            cs.append(contentsOf: a.nuevos); validos = a.validos; invalidos = a.invalidos; detalle = a.detalle
        } else if ext == "json" || txt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["),
           let arr = try? JSONSerialization.jsonObject(with: Data(txt.utf8)) as? [[String: Any]] {
            for o in arr {
                let n = (o["nombre"] as? String) ?? (o["name"] as? String) ?? ""
                let num = primerNumero(String(describing: o["numero"] ?? o["number"] ?? o["telefono"] ?? o["phone"] ?? ""))
                if !n.isEmpty, !num.isEmpty { cs.append(ContactoWA(nombre: n, numero: num)); validos += 1 } else { invalidos += 1 }
            }
            detalle = "JSON"
        } else {
            let a = analizarCSV(txt)
            cs.append(contentsOf: a.nuevos); validos = a.validos; invalidos = a.invalidos; detalle = a.detalle
        }
        var vistos = Set<String>()
        let dedup = cs.filter { !$0.numero.isEmpty && vistos.insert("\(norm($0.nombre))|\($0.numero)").inserted }
        guardar(dedup)
        Log.write("import contactos: \(detalle) → válidos=\(validos) inválidos=\(invalidos) total-guardados=\(dedup.count)")
        return ImportResult(validos: validos, invalidos: invalidos, total: dedup.count, detalle: detalle)
    }
    static func plantillaCSV() -> String {
        "nombre,numero\nAna Pérez,593999999999\nMaría López,593988888888\n"
    }
    /// Exporta los contactos actuales; si está vacío, un EJEMPLO para ver el formato.
    static func exportarCSV() -> String {
        let cs = importados()
        if cs.isEmpty { return plantillaCSV() }
        return "nombre,numero\n" + cs.map { "\($0.nombre),\($0.numero)" }.joined(separator: "\n") + "\n"
    }
    static func exportarJSON() -> String {
        let cs = importados()
        let arr: [[String: String]] = cs.isEmpty
            ? [["nombre": "Ana Pérez", "numero": "593999999999"], ["nombre": "María López", "numero": "593988888888"]]
            : cs.map { ["nombre": $0.nombre, "numero": $0.numero] }
        let d = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])
        return d.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // ---- Contactos de macOS ----
    static func usarMac() -> Bool { Config.waUsarContactosMac() }
    private static func deMac(_ done: @escaping ([ContactoWA]) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { ok, _ in
            guard ok else { done([]); return }
            var out: [ContactoWA] = []
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let req = CNContactFetchRequest(keysToFetch: keys)
            try? store.enumerateContacts(with: req) { c, _ in
                let nombre = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                for p in c.phoneNumbers {
                    let num = soloNumero(p.value.stringValue)
                    if !nombre.isEmpty, !num.isEmpty { out.append(ContactoWA(nombre: nombre, numero: num)) }
                }
            }
            done(out)
        }
    }

    /// Coincidencia local y determinista. Exacto primero; solo si no existe usa
    /// distancia por PALABRA ("Andresito"→"Andrés"). El llamador recibe el flag
    /// aproximado para obligar a confirmar incluso cuando solo haya un resultado.
    static func coincidencias(_ nombre: String, en contactos: [ContactoWA])
        -> (contactos: [ContactoWA], aproximada: Bool) {
        let n = norm(nombre).trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?¿¡"))
        guard !n.isEmpty else { return ([], false) }
        var vistos = Set<String>()
        let unicos = contactos.filter { !$0.numero.isEmpty && vistos.insert($0.numero).inserted }
        var exactos = unicos.filter { norm($0.nombre).contains(n) }
        if !exactos.isEmpty {
            exactos.sort { a, b in
                let pa = norm(a.nombre).hasPrefix(n), pb = norm(b.nombre).hasPrefix(n)
                return pa != pb ? pa : a.nombre.count < b.nombre.count
            }
            return (exactos, false)
        }

        let q = n.split(separator: " ").map(String.init).filter { $0.count >= 4 }
        guard !q.isEmpty else { return ([], false) }
        var puntuados: [(ContactoWA, Double)] = []
        for c in unicos {
            let partes = norm(c.nombre).split(separator: " ").map(String.init).filter { $0.count >= 4 }
            guard !partes.isEmpty else { continue }
            var suma = 0.0, valido = true
            for buscado in q {
                let candidatos = partes.filter { $0.first == buscado.first }
                let mejor = candidatos.map { ModoFuzzy.similitud(buscado, $0) }.max() ?? 0
                if mejor < 0.72 { valido = false; break }
                suma += mejor
            }
            if valido { puntuados.append((c, suma / Double(q.count))) }
        }
        puntuados.sort { $0.1 == $1.1 ? $0.0.nombre.count < $1.0.nombre.count : $0.1 > $1.1 }
        return (puntuados.map(\.0), !puntuados.isEmpty)
    }

    /// Resuelve un nombre (importados → Contactos de Mac), callback en MAIN.
    static func resolverDetallado(_ nombre: String,
                                  _ done: @escaping ([ContactoWA], Bool) -> Void) {
        func terminar(_ extra: [ContactoWA]) {
            let r = coincidencias(nombre, en: importados() + extra)
            DispatchQueue.main.async { done(r.contactos, r.aproximada) }
        }
        if usarMac() { deMac { terminar($0) } }
        else { terminar([]) }
    }

    /// Compatibilidad para llamadores que no necesitan distinguir el fuzzy.
    static func resolver(_ nombre: String, _ done: @escaping ([ContactoWA]) -> Void) {
        resolverDetallado(nombre) { contactos, _ in done(contactos) }
    }

    /// Extrae el DESTINATARIO del texto: "a X", "para X", "enviar a X" al inicio.
    /// Devuelve (nombre?, mensaje). Con coma, el nombre es todo hasta la coma
    /// (nombres de 2 palabras); sin coma, el nombre es la 1ª palabra.
    static func objetivo(_ texto: String) -> (nombre: String?, mensaje: String) {
        let t = texto.trimmingCharacters(in: .whitespaces)
        let low = norm(t)
        let prefs = ["enviar a ", "envia a ", "mandar a ", "manda a ", "mandale a ", "mándale a ",
                     "escribe a ", "escribele a ", "escríbele a ", "para ", "a "]
        // El NOMBRE va hasta la primera puntuación (coma/punto/…) que el STT pone
        // antes del mensaje; el resto es el mensaje. Sin puntuación, la 1ª palabra.
        let corte: Set<Character> = [",", ".", ";", ":", "!", "?", "¿", "¡", "\n"]
        for pref in prefs where low.hasPrefix(pref) {
            let resto = String(t.dropFirst(pref.count)).trimmingCharacters(in: .whitespaces)
            if let idx = resto.firstIndex(where: { corte.contains($0) }) {
                let nombre = String(resto[..<idx]).trimmingCharacters(in: .whitespaces)
                let msg = String(resto[resto.index(after: idx)...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?¿¡\n"))
                return (nombre.isEmpty ? nil : nombre, msg)
            }
            let parts = resto.split(separator: " ", maxSplits: 1).map(String.init)
            let nombre = parts.first ?? ""
            return (nombre.isEmpty ? nil : nombre, parts.count > 1 ? parts[1] : "")
        }
        return (nil, t)
    }

    /// URL de WhatsApp a un número (o sin número para elegir), con failover app→wa.me.
    static func urlEnvio(numero: String?, texto: String, tieneApp: Bool) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        let enc = texto.addingPercentEncoding(withAllowedCharacters: cs) ?? texto
        let num = soloNumero(numero ?? "")
        if tieneApp {
            return num.isEmpty ? "whatsapp://send?text=\(enc)" : "whatsapp://send?phone=\(num)&text=\(enc)"
        }
        return num.isEmpty ? "https://wa.me/?text=\(enc)" : "https://wa.me/\(num)?text=\(enc)"
    }
}
