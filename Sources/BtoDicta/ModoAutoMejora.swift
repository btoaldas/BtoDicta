import Foundation

/// Aprende de las respuestas explícitas del modal. No entrena un modelo ni manda
/// datos fuera: conserva contadores locales y, para la capa semántica, mueve el
/// umbral en pasos pequeños y acotados. Las acciones externas siguen confirmándose.
enum ModoAutoMejora {
    private struct Fuente: Codable {
        var si = 0
        var no = 0
        var scoresSi: [Double] = []
        var scoresNo: [Double] = []
    }
    private static let lock = NSLock()
    private static var url: URL { Config.dir.appendingPathComponent("modo-feedback.json") }

    private static func cargar() -> [String: Fuente] {
        guard let d = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode([String: Fuente].self, from: d) else { return [:] }
        return v
    }

    static func registrar(fuente: String, confianza: Double, aceptado: Bool) {
        guard Config.modoAutoMejora() else { return }
        lock.lock()
        var todo = cargar()
        var f = todo[fuente] ?? Fuente()
        if aceptado {
            f.si += 1; f.scoresSi.append(confianza)
            if f.scoresSi.count > 40 { f.scoresSi.removeFirst(f.scoresSi.count - 40) }
        } else {
            f.no += 1; f.scoresNo.append(confianza)
            if f.scoresNo.count > 40 { f.scoresNo.removeFirst(f.scoresNo.count - 40) }
        }
        todo[fuente] = f
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(todo) {
            try? d.write(to: url, options: .atomic); Config.protegerSecreto(url)
        }
        lock.unlock()

        guard [FuenteModo.semantico.rawValue, FuenteModo.planSemantico.rawValue].contains(fuente),
              f.si + f.no >= 4 else { return }
        let actual = Config.modoSemanticoUmbral()
        let promSi = f.scoresSi.isEmpty ? nil : f.scoresSi.reduce(0, +) / Double(f.scoresSi.count)
        let promNo = f.scoresNo.isEmpty ? nil : f.scoresNo.reduce(0, +) / Double(f.scoresNo.count)
        var objetivo = actual
        if let s = promSi, let n = promNo, n < s {
            objetivo = (s + n) / 2
        } else if let s = promSi, f.si >= 3, f.no == 0 {
            objetivo = min(actual, s - 0.015)
        } else if let n = promNo, f.no >= 3 {
            objetivo = max(actual, n + 0.015)
        }
        objetivo = min(0.78, max(0.45, objetivo))
        let limitado = min(actual + 0.02, max(actual - 0.02, objetivo))
        if abs(limitado - actual) >= 0.005 {
            Config.set("modo_sem_umbral", to: limitado)
            ModosLog.registrar("auto_umbral", ["fuente": fuente, "antes": actual,
                                                "despues": limitado, "si": f.si, "no": f.no])
        }
    }

    static func reiniciar() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
        Config.set("modo_sem_umbral", to: 0.5)
    }
}
