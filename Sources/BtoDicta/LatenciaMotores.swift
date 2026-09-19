import Foundation

// MARK: - Cuánto tarda cada motor, medido
//
// La cascada decide el orden de los motores, y ese orden estaba puesto a mano.
// Para cambiarlo con criterio hace falta saber cuánto tarda cada uno de verdad,
// y hasta ahora solo uno medía su tiempo —y en modo depuración—.
//
// Esto lo mide para todos, guarda las últimas veces de cada uno y calcula la
// MEDIANA. La mediana y no la media: un cuelgue de veinte segundos arrastra la
// media de cien llamadas buenas, y lo que interesa saber es lo que tarda
// normalmente, no lo que tardó el peor día.

enum LatenciaMotores {

    /// Cuántas medidas se guardan por motor. Suficiente para que la mediana sea
    /// estable, poco para que refleje cómo va el motor ESTA semana y no hace
    /// tres meses.
    private static let recordar = 50

    private static let candado = NSLock()
    private static var tiempos: [String: [Int]] = [:]

    private static var archivo: URL { Config.dir.appendingPathComponent("latencias.json") }

    /// Anota lo que tardó una llamada, en milisegundos.
    static func anotar(_ motor: String, ms: Int) {
        guard ms > 0, ms < 600_000 else { return }
        candado.lock()
        var l = tiempos[motor] ?? []
        l.append(ms)
        if l.count > recordar { l.removeFirst(l.count - recordar) }
        tiempos[motor] = l
        let copia = tiempos
        candado.unlock()
        guardar(copia)
    }

    /// Lo que tarda normalmente cada motor: (motor, mediana en ms, medidas).
    static func resumen() -> [(motor: String, ms: Int, medidas: Int)] {
        cargarSiHaceFalta()
        candado.lock(); defer { candado.unlock() }
        return tiempos.compactMap { motor, l in
            guard !l.isEmpty else { return nil }
            let ordenados = l.sorted()
            let mediana = ordenados[ordenados.count / 2]
            return (motor, mediana, l.count)
        }.sorted { $0.1 < $1.1 }
    }

    // MARK: Persistencia

    private static var cargado = false

    private static func cargarSiHaceFalta() {
        candado.lock()
        let hayQue = !cargado
        candado.unlock()
        guard hayQue else { return }
        let d = (try? Data(contentsOf: archivo)) ?? Data()
        let t = ((try? JSONSerialization.jsonObject(with: d)) as? [String: [Int]]) ?? [:]
        candado.lock(); if tiempos.isEmpty { tiempos = t }; cargado = true; candado.unlock()
    }

    private static var ultimoGuardado = Date.distantPast

    private static func guardar(_ t: [String: [Int]]) {
        // No se escribe en cada llamada: una tanda de la bitácora puede hacer
        // cien seguidas y esto no vale cien escrituras a disco.
        guard Date().timeIntervalSince(ultimoGuardado) > 30 else { return }
        ultimoGuardado = Date()
        Config.asegurarDirSeguro()
        guard let d = try? JSONSerialization.data(withJSONObject: t) else { return }
        try? d.write(to: archivo, options: .atomic)
    }

    /// Solo para las pruebas.
    static func olvidarQA() {
        candado.lock(); tiempos = [:]; cargado = true; candado.unlock()
    }
}
