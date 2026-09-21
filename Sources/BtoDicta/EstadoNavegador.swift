import Foundation

/// Lo que un navegador cuenta de sí mismo (spec 006, T03).
///
/// Esto existe porque hay cosas del navegador que el sistema operativo **no deja
/// ver desde fuera**. Comprobado el 2026-09-20: `audible of active tab` responde
/// error -1700 y las únicas propiedades que un navegador expone por AppleScript
/// son URL, name, loading, class e id. Saber qué pestaña está SONANDO solo es
/// posible desde dentro del propio navegador.
///
/// Sin ese dato, la bitácora tiene que adivinar por el foco, y adivinar falla
/// justo en los casos normales: música en un monitor mientras se trabaja en
/// otro, un juego minimizado que sigue sonando, un vídeo en una ventana de atrás.
struct EstadoNavegador {

    struct Pestaña {
        let url: String
        let titulo: String
        let audible: Bool
        let activa: Bool
    }

    /// Qué navegador habla: «Google Chrome», «Firefox»…
    let navegador: String
    /// Versión de la extensión que informa, para saber si se quedó atrás.
    let version: String
    let pestañas: [Pestaña]
    /// Cuándo lo dijo. No se usa la hora de llegada: entre que el navegador mira
    /// y la petición llega puede pasar tiempo, y un dato viejo presentado como
    /// actual es peor que no tenerlo.
    let instante: Date

    var activa: Pestaña? { pestañas.first { $0.activa } }
    var audibles: [Pestaña] { pestañas.filter { $0.audible } }

    /// Construye el estado desde el JSON que manda la extensión.
    ///
    /// Devuelve `nil` en vez de un estado a medias: un informe incompleto del
    /// navegador no debe poder inclinar una decisión sobre qué se graba.
    init?(json: [String: Any]) {
        guard let navegador = json["navegador"] as? String, !navegador.isEmpty,
              let crudas = json["pestanas"] as? [[String: Any]] else { return nil }
        self.navegador = navegador
        self.version = (json["version"] as? String) ?? ""
        self.pestañas = crudas.compactMap { p in
            guard let url = p["url"] as? String else { return nil }
            return Pestaña(url: url,
                           titulo: (p["titulo"] as? String) ?? "",
                           audible: (p["audible"] as? Bool) ?? false,
                           activa: (p["activa"] as? Bool) ?? false)
        }
        // El instante lo pone el navegador si lo manda; si no, vale el de
        // llegada, que para un informe recién enviado es equivalente.
        if let ts = json["instante"] as? Double {
            self.instante = Date(timeIntervalSince1970: ts)
        } else {
            self.instante = Date()
        }
    }

    /// Para las pruebas y para el uso interno.
    init(navegador: String, pestañas: [Pestaña], instante: Date = Date(), version: String = "") {
        self.navegador = navegador
        self.version = version
        self.pestañas = pestañas
        self.instante = instante
    }

    /// Cuánto hace que se recibió. Un estado viejo no sirve para decidir: si el
    /// navegador dejó de informar, es mejor volver a adivinar por el foco que
    /// creerle a un dato de hace media hora.
    var antiguedad: TimeInterval { Date().timeIntervalSince(instante) }
}

/// El último estado que reportó cada navegador.
///
/// Es memoria viva a propósito, no disco: si la aplicación se reinicia, lo que
/// valía es lo que el navegador diga a continuación, no lo que dijo antes de
/// apagarse. Guardar esto entre arranques daría una foto vieja con aire de
/// actual — justo el patrón que costó caro en otras partes de esta aplicación,
/// pero al revés.
enum EstadoNavegadores {
    private static let candado = NSLock()
    private static var porNavegador: [String: EstadoNavegador] = [:]

    /// Pasado este tiempo sin noticias, el informe se considera caducado y la
    /// bitácora vuelve a decidir con lo que ve el sistema.
    static func segundosDeVigencia() -> TimeInterval {
        max(5, (Config.json0("navegador_vigencia_segundos") as? Double) ?? 90)
    }

    static func anotar(_ estado: EstadoNavegador) {
        candado.lock(); defer { candado.unlock() }
        porNavegador[estado.navegador] = estado
    }

    /// Los informes que siguen siendo válidos.
    static func vigentes() -> [EstadoNavegador] {
        candado.lock(); defer { candado.unlock() }
        let tope = segundosDeVigencia()
        return porNavegador.values.filter { $0.antiguedad <= tope }
    }

    /// La versión de extensión que trae esta copia de BtoDicta.
    ///
    /// Se lee del manifiesto que viaja dentro de la aplicación, no de una
    /// constante escrita a mano: una constante y un manifiesto se desincronizan
    /// el día que alguien toca uno y olvida el otro.
    static func versionQueTraeLaApp() -> String {
        guard let url = Bundle.main.url(forResource: "manifest.chromium", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let v = j["version"] as? String else { return "" }
        return v
    }

    /// ¿Hay alguna extensión informando con una versión distinta de la que
    /// trae la aplicación? Devuelve los navegadores afectados.
    ///
    /// Una extensión cargada a mano NO se actualiza sola —eso solo lo hace una
    /// tienda—, así que lo único que evita seguir con una vieja sin enterarse es
    /// que alguien lo diga.
    static func desactualizadas() -> [(navegador: String, tiene: String, deberia: String)] {
        let esperada = versionQueTraeLaApp()
        guard !esperada.isEmpty else { return [] }
        return vigentes().compactMap { i in
            guard !i.version.isEmpty, i.version != esperada else { return nil }
            return (i.navegador, i.version, esperada)
        }
    }

    static func olvidarTodo() {
        candado.lock(); porNavegador.removeAll(); candado.unlock()
    }
}
