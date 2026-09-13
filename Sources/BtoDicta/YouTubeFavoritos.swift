import Foundation

/// Favoritos privados de BtoDicta. No escribe ni modifica la cuenta Google y
/// por tanto no necesita ampliar el permiso OAuth de solo lectura.
enum YouTubeFavoritos {
    private static let lock = NSLock()
    private static var cache: [VideoYouTubeInterno]?
    private static var url: URL { Config.dir.appendingPathComponent("youtube-favoritos.json") }

    static func todos() -> [VideoYouTubeInterno] {
        lock.lock(); defer { lock.unlock() }
        return cargar()
    }

    static func contiene(_ id: String) -> Bool { todos().contains { $0.id == id } }

    @discardableResult
    static func alternar(_ video: VideoYouTubeInterno) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var lista = cargar()
        if let i = lista.firstIndex(where: { $0.id == video.id }) {
            lista.remove(at: i); guardar(lista); return false
        }
        lista.insert(video, at: 0); guardar(Array(lista.prefix(500))); return true
    }

    private static func cargar() -> [VideoYouTubeInterno] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let lista = try? JSONDecoder().decode([VideoYouTubeInterno].self, from: data) else {
            cache = []
            return []
        }
        cache = lista
        return lista
    }

    private static func guardar(_ lista: [VideoYouTubeInterno]) {
        cache = lista
        guard let data = try? JSONEncoder().encode(lista) else { return }
        try? data.write(to: url, options: .atomic)
        Config.protegerSecreto(url)
    }
}
