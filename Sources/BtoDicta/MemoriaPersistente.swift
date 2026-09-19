import Foundation

// MARK: - «Esto ya lo hice» — recuerdos que sobreviven a cerrar la aplicación
//
// El mismo fallo apareció CUATRO veces en sitios distintos: el resumen por
// correo, el aviso de saldo bajo, las rutinas de la bitácora y el planificador
// de tandas. Todos guardaban en una variable en memoria la nota de qué habían
// hecho ya y cuándo. Al cerrar la aplicación esa nota desaparecía, y al volver a
// abrirla creían que no habían hecho nada.
//
// Lo que se veía por fuera era distinto en cada caso —diecisiete correos
// repetidos, sesenta y ocho avisos en un día, tres resúmenes del mismo día— pero
// la causa era la misma. Y cada uno se arregló por separado, lo que garantiza
// que habrá un quinto.
//
// Esto es el sitio donde apuntarlo. No es una base de datos: es una libreta de
// notas cortas, agrupadas por tema, que se guarda en disco.

enum MemoriaPersistente {

    private static let candado = NSLock()
    private static var cache: [String: [String: String]] = [:]
    private static var cargado = false

    private static var archivo: URL {
        Config.dir.appendingPathComponent("memoria-tareas.json")
    }

    // MARK: Leer y escribir

    /// El valor apuntado para esta clave dentro de un tema, si lo hay.
    static func valor(tema: String, clave: String) -> String? {
        cargar()
        candado.lock(); defer { candado.unlock() }
        return cache[tema]?[clave]
    }

    /// Apunta un valor. `nil` lo borra.
    static func poner(tema: String, clave: String, valor: String?) {
        cargar()
        candado.lock()
        var t = cache[tema] ?? [:]
        if let valor { t[clave] = valor } else { t[clave] = nil }
        cache[tema] = t
        let copia = cache
        candado.unlock()
        guardar(copia)
    }

    // MARK: Lo que se pregunta de verdad

    /// ¿Se hizo ya esto HOY? Si no, lo apunta y devuelve `false`.
    ///
    /// La pregunta y la marca van juntas a propósito: separarlas es lo que
    /// permite que dos comprobaciones seguidas pasen las dos.
    static func yaHechoHoy(tema: String, clave: String, ahora: Date = Date()) -> Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let hoy = f.string(from: ahora)
        cargar()
        candado.lock()
        let previo = cache[tema]?[clave]
        if previo == hoy { candado.unlock(); return true }
        var t = cache[tema] ?? [:]
        t[clave] = hoy
        cache[tema] = t
        let copia = cache
        candado.unlock()
        guardar(copia)
        return false
    }

    /// Cuándo se hizo esto por última vez, o `nil` si nunca.
    static func ultimaVez(tema: String, clave: String) -> Date? {
        guard let s = valor(tema: tema, clave: clave) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    /// Apunta que esto se acaba de hacer.
    static func anotarAhora(tema: String, clave: String, ahora: Date = Date()) {
        poner(tema: tema, clave: clave, valor: ISO8601DateFormatter().string(from: ahora))
    }

    // MARK: Disco

    private static func cargar() {
        candado.lock()
        let falta = !cargado
        candado.unlock()
        guard falta else { return }
        let d = (try? Data(contentsOf: archivo)) ?? Data()
        let t = ((try? JSONSerialization.jsonObject(with: d)) as? [String: [String: String]]) ?? [:]
        candado.lock()
        if cache.isEmpty { cache = t }
        cargado = true
        candado.unlock()
    }

    private static func guardar(_ t: [String: [String: String]]) {
        Config.asegurarDirSeguro()
        guard let d = try? JSONSerialization.data(withJSONObject: t, options: [.prettyPrinted]) else { return }
        try? d.write(to: archivo, options: .atomic)
    }

    /// Simula cerrar y volver a abrir la aplicación: se olvida lo que hay en
    /// memoria, NO lo del disco. Solo para las pruebas.
    static func simularReinicioQA() {
        candado.lock(); cache = [:]; cargado = false; candado.unlock()
    }

    /// Borra un tema entero. Solo para las pruebas.
    static func olvidarTemaQA(_ tema: String) {
        cargar()
        candado.lock(); cache[tema] = nil; let copia = cache; candado.unlock()
        guardar(copia)
    }
}
