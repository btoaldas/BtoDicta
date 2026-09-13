import Foundation

struct EstadoCuotaYouTube: Codable, Equatable {
    var diaPacifico: String
    var usadas: Int
    var agotadaPorServidor: Bool
}

/// Contador preventivo de search.list. La cuota real vive en Google y puede
/// compartirse con otros equipos; por eso un 403 del servidor siempre prevalece.
enum YouTubeCuotaBusqueda {
    private static let lock = NSLock()
    private static var cache: EstadoCuotaYouTube?
    private static var url: URL { Config.dir.appendingPathComponent("youtube-cuota.json") }

    static func estado(ahora: Date = Date()) -> EstadoCuotaYouTube {
        lock.lock(); defer { lock.unlock() }
        return cargarNormalizado(ahora: ahora)
    }

    static func restantes(ahora: Date = Date()) -> Int {
        let e = estado(ahora: ahora)
        return e.agotadaPorServidor ? 0 : max(0, Config.youtubeBusquedasDiarias() - e.usadas)
    }

    static func resumen(ahora: Date = Date()) -> String {
        let e = estado(ahora: ahora)
        let maximo = Config.youtubeBusquedasDiarias()
        let quedan = e.agotadaPorServidor ? 0 : max(0, maximo - e.usadas)
        let sufijo = e.agotadaPorServidor ? " · Google indicó cuota agotada" : " · quedan ~\(quedan)"
        return "Búsquedas remotas hoy: \(min(e.usadas, maximo))/\(maximo)\(sufijo) · reinicia 00:00 PT"
    }

    /// Reserva una llamada antes de enviarla: también las solicitudes inválidas
    /// consumen cuota según YouTube.
    static func consumirSiDisponible(ahora: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var e = cargarNormalizado(ahora: ahora)
        guard !e.agotadaPorServidor, e.usadas < Config.youtubeBusquedasDiarias() else { return false }
        e.usadas += 1; guardar(e); return true
    }

    static func marcarAgotadaPorServidor(ahora: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var e = cargarNormalizado(ahora: ahora)
        e.agotadaPorServidor = true
        e.usadas = max(e.usadas, Config.youtubeBusquedasDiarias())
        guardar(e)
    }

    /// Útil solo al cambiar de proyecto/credenciales; no amplía la cuota real.
    static func reiniciarEstimacion(ahora: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guardar(.init(diaPacifico: dia(ahora), usadas: 0, agotadaPorServidor: false))
    }

    private static func cargarNormalizado(ahora: Date) -> EstadoCuotaYouTube {
        let hoy = dia(ahora)
        if let cache, cache.diaPacifico == hoy { return cache }
        if let data = try? Data(contentsOf: url),
           let e = try? JSONDecoder().decode(EstadoCuotaYouTube.self, from: data),
           e.diaPacifico == hoy {
            cache = e; return e
        }
        let nuevo = EstadoCuotaYouTube(diaPacifico: hoy, usadas: 0,
                                       agotadaPorServidor: false)
        guardar(nuevo); return nuevo
    }

    private static func guardar(_ estado: EstadoCuotaYouTube) {
        cache = estado
        guard let data = try? JSONEncoder().encode(estado) else { return }
        try? data.write(to: url, options: .atomic); Config.protegerSecreto(url)
    }

    private static func dia(_ fecha: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

struct EntradaHistorialYouTube: Codable, Hashable, Identifiable {
    var id: String { video.id }
    let video: VideoYouTubeInterno
    var ultimaReproduccion: Date
    var reproducciones: Int
}

/// Historial privado de reproducciones confirmadas por el IFrame Player.
/// No se envía a Google ni se confunde con el historial de la cuenta YouTube.
enum YouTubeHistorial {
    private static let lock = NSLock()
    private static var cache: [EntradaHistorialYouTube]?
    private static var url: URL { Config.dir.appendingPathComponent("youtube-historial.json") }

    static func todos() -> [EntradaHistorialYouTube] {
        lock.lock(); defer { lock.unlock() }
        return cargar()
    }

    static func videos() -> [VideoYouTubeInterno] { todos().map(\.video) }

    static func idsRecientes(limite: Int = 12) -> Set<String> {
        Set(todos().prefix(max(0, limite)).map(\.id))
    }

    static func registrar(_ video: VideoYouTubeInterno, ahora: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var items = cargar()
        let veces: Int
        if let i = items.firstIndex(where: { $0.id == video.id }) {
            veces = items[i].reproducciones + 1
            items.remove(at: i)
        } else {
            veces = 1
        }
        items.insert(.init(video: video, ultimaReproduccion: ahora,
                           reproducciones: veces), at: 0)
        guardar(Array(items.prefix(500)))
    }

    static func vaciar() {
        lock.lock(); defer { lock.unlock() }
        guardar([])
    }

    private static func cargar() -> [EntradaHistorialYouTube] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([EntradaHistorialYouTube].self,
                                                     from: data) else {
            cache = []; return []
        }
        cache = items.sorted { $0.ultimaReproduccion > $1.ultimaReproduccion }
        return cache ?? []
    }

    private static func guardar(_ items: [EntradaHistorialYouTube]) {
        cache = items
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
        Config.protegerSecreto(url)
    }
}

/// Cola local y portable entre aperturas. Seleccionar un conjunto de resultados
/// la reemplaza; “Añadir a cola” agrega sin duplicar y conserva el orden elegido.
enum YouTubeCola {
    private static let lock = NSLock()
    private static var cache: [VideoYouTubeInterno]?
    private static var url: URL { Config.dir.appendingPathComponent("youtube-cola.json") }

    static func todos() -> [VideoYouTubeInterno] {
        lock.lock(); defer { lock.unlock() }
        return cargar()
    }

    static func reemplazar(_ videos: [VideoYouTubeInterno]) {
        lock.lock(); defer { lock.unlock() }
        guardar(unicos(videos))
    }

    @discardableResult
    static func agregar(_ video: VideoYouTubeInterno) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var items = cargar()
        guard !items.contains(where: { $0.id == video.id }) else { return false }
        items.append(video); guardar(Array(items.prefix(500))); return true
    }

    static func quitar(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        var items = cargar(); items.removeAll { $0.id == id }; guardar(items)
    }

    static func vaciar() {
        lock.lock(); defer { lock.unlock() }
        guardar([])
    }

    private static func unicos(_ videos: [VideoYouTubeInterno]) -> [VideoYouTubeInterno] {
        var vistos = Set<String>()
        return videos.filter { vistos.insert($0.id).inserted }.prefix(500).map { $0 }
    }

    private static func cargar() -> [VideoYouTubeInterno] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([VideoYouTubeInterno].self,
                                                     from: data) else {
            cache = []; return []
        }
        cache = unicos(items); return cache ?? []
    }

    private static func guardar(_ items: [VideoYouTubeInterno]) {
        cache = items
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
        Config.protegerSecreto(url)
    }
}

/// Catálogo local de todo resultado ya visto (búsquedas y listas abiertas).
/// Permite seguir encontrando música sin gastar cuota ni depender de la red.
enum YouTubeBibliotecaCache {
    private static let lock = NSLock()
    private static var cache: [VideoYouTubeInterno]?
    private static var url: URL { Config.dir.appendingPathComponent("youtube-biblioteca.json") }

    static func todos() -> [VideoYouTubeInterno] {
        lock.lock(); defer { lock.unlock() }
        return cargar()
    }

    static func registrar(_ videos: [VideoYouTubeInterno]) {
        guard !videos.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        guardar(combinar([videos, cargar()]))
    }

    static func combinar(_ fuentes: [[VideoYouTubeInterno]]) -> [VideoYouTubeInterno] {
        var vistos = Set<String>()
        return fuentes.flatMap { $0 }.filter { vistos.insert($0.id).inserted }
    }

    /// Búsqueda por tokens, sin IA ni red. Las palabras operativas se ignoran
    /// para que “pon música de Julio Jaramillo” encuentre artista y canciones.
    static func buscar(_ consulta: String, en videos: [VideoYouTubeInterno],
                       permitirTodos: Bool = false) -> [VideoYouTubeInterno] {
        let q = PerfilAgente.normalizar(consulta)
        let vacias: Set<String> = ["por", "favor", "pon", "poner", "reproduce", "reproducir",
                                   "busca", "buscar", "musica", "cancion", "video", "tutorial",
                                   "de", "del", "la", "el", "los", "las", "un", "una", "para", "en"]
        let tokens = q.split(separator: " ").map(String.init)
            .filter { $0.count > 1 && !vacias.contains($0) }
        if tokens.isEmpty { return permitirTodos ? videos : [] }
        return videos.compactMap { video -> (VideoYouTubeInterno, Int)? in
            let texto = PerfilAgente.normalizar("\(video.titulo) \(video.canal)")
            let coincidencias = tokens.filter { texto.contains($0) }.count
            guard coincidencias > 0 else { return nil }
            let completo = texto.contains(q) ? 1_000 : 0
            return (video, completo + coincidencias * 10)
        }.sorted { a, b in
            a.1 == b.1 ? a.0.titulo.localizedCaseInsensitiveCompare(b.0.titulo) == .orderedAscending
                : a.1 > b.1
        }.map(\.0)
    }

    private static func cargar() -> [VideoYouTubeInterno] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([VideoYouTubeInterno].self, from: data) else {
            cache = []; return []
        }
        cache = Array(combinar([items]).prefix(2_000)); return cache ?? []
    }

    private static func guardar(_ items: [VideoYouTubeInterno]) {
        cache = Array(items.prefix(2_000))
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic); Config.protegerSecreto(url)
    }
}
