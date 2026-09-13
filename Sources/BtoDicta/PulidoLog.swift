import Foundation

// MARK: - Odómetro de GASTO de pulido/traducción con IA (tokens → costo)
//
// Cada pulido/traducción exitoso registra tokens y costo estimado (según el
// precio manual/curado/publicado del modelo). Estadísticas lo muestra por
// hoy/semana/mes, igual que el uso de voz.

enum PulidoLog {
    static var fileURL: URL { Config.dir.appendingPathComponent("pulido.jsonl") }
    private static let lock = NSLock()

    static func record(provider: String, modelo: String, tin: Int, tout: Int) {
        guard tin > 0 || tout > 0 else { return }
        let precio = ChatIA.precioNum(provider, modelo)
        let costo = precio.map { Double(tin) / 1_000_000 * $0.0 + Double(tout) / 1_000_000 * $0.1 } ?? 0
        let obj: [String: Any] = ["ts": Date().timeIntervalSince1970, "prov": provider,
                                  "modelo": modelo, "tin": tin, "tout": tout, "costo": costo]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        lock.lock(); defer { lock.unlock() }
        Config.asegurarDirSeguro()
        if let h = try? FileHandle(forWritingTo: fileURL) {
            h.seekToEndOfFile(); h.write(data); h.write("\n".data(using: .utf8)!); try? h.close()
        } else {
            try? (String(data: data, encoding: .utf8)! + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    struct Totales {
        var hoyCosto = 0.0, semanaCosto = 0.0, mesCosto = 0.0, añoCosto = 0.0
        var tokensHoy = 0, pulidosHoy = 0, pulidosMes = 0
        var costoPorDia = Array(repeating: 0.0, count: 7)  // últimos 7 días (hoy = índice 6)
    }

    static func totales() -> Totales {
        var t = Totales()
        guard let txt = try? String(contentsOf: fileURL, encoding: .utf8) else { return t }
        let cal = Calendar.current; let ahora = Date()
        let inicioDia = cal.startOfDay(for: ahora)
        for linea in txt.split(separator: "\n") {
            guard let d = linea.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let ts = j["ts"] as? Double else { continue }
            let fecha = Date(timeIntervalSince1970: ts)
            let costo = (j["costo"] as? Double) ?? 0
            let tin = (j["tin"] as? Int) ?? 0, tout = (j["tout"] as? Int) ?? 0
            let dias = cal.dateComponents([.day], from: cal.startOfDay(for: fecha), to: inicioDia).day ?? 999
            if cal.isDate(fecha, inSameDayAs: ahora) { t.hoyCosto += costo; t.tokensHoy += tin + tout; t.pulidosHoy += 1 }
            if dias >= 0 && dias < 7 { t.semanaCosto += costo; t.costoPorDia[6 - dias] += costo }
            if cal.isDate(fecha, equalTo: ahora, toGranularity: .month) { t.mesCosto += costo; t.pulidosMes += 1 }
            if cal.isDate(fecha, equalTo: ahora, toGranularity: .year) { t.añoCosto += costo }
        }
        return t
    }
}
