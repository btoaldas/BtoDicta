import Foundation

// MARK: - La conexión con la que se transcribe
//
// Todos los motores de nube compartían `URLSession.shared` y mandaban
// `Connection: close`. Esa combinación tiene un fallo que aparece justo como
// aparece el dictado real: a ratos.
//
// El servidor cierra la conexión al responder —se lo pide esa cabecera— pero el
// banco del cliente se la queda de todas formas. Al dictado siguiente, si pasó
// un rato, se escribe contra un socket que ya no existe y la petición se cuelga
// hasta agotar el plazo. Medido con ocho dictados de 40 s separados por 45 s:
// SEIS tardaron ~18,7 s, y el reintento —con conexión nueva— resolvía el mismo
// audio en 1,7 s. Diez veces más rápido por estrenar conexión.
//
// La solución no es abrir conexión cada vez (eso paga un saludo TLS en cada
// dictado) ni reutilizarla siempre (eso es el fallo): es reutilizarla mientras
// está CALIENTE y tirarla en cuanto lleva parada más de lo que suele durar un
// keep-alive ocioso.
enum RedDictado {

    /// Tiempo de reposo tras el cual la conexión se considera sospechosa. Por
    /// debajo de esto, dos dictados seguidos reaprovechan la conexión y no
    /// pagan handshake; por encima, se estrena.
    private static let refrescoSegundos: TimeInterval = 20

    private static var _sesion: URLSession?
    private static var ultimoUso = Date.distantPast
    private static let candado = NSLock()

    /// La sesión con la que hablar con cualquier motor de transcripción.
    static func sesion() -> URLSession {
        candado.lock(); defer { candado.unlock() }
        if let s = _sesion, Date().timeIntervalSince(ultimoUso) < refrescoSegundos {
            ultimoUso = Date()
            return s
        }
        _sesion?.finishTasksAndInvalidate()
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 4
        c.timeoutIntervalForResource = 300
        c.waitsForConnectivity = false     // sin red, fallar ya y pasar al motor local
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let s = URLSession(configuration: c)
        _sesion = s
        ultimoUso = Date()
        return s
    }

    /// Sesión de un solo uso, para el reintento que sigue a un cuelgue: si la
    /// anterior se quedó a medias, lo último que conviene es heredarla.
    static func sesionNueva() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.httpMaximumConnectionsPerHost = 1
        c.httpShouldUsePipelining = false
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: c)
    }

    /// ¿La sesión es la compartida? Sirve para no invalidar por error la que
    /// usa toda la aplicación al terminar una petición.
    static func esCompartida(_ s: URLSession) -> Bool {
        candado.lock(); defer { candado.unlock() }
        return s === _sesion
    }
}
