import AppKit
import CryptoKit
import Foundation
import Network
import Security

// MARK: - Catálogo oficial de YouTube para el reproductor interno

struct VideoYouTubeInterno: Identifiable, Hashable, Codable {
    let id: String
    let titulo: String
    let canal: String
    let miniatura: URL?
}

struct ListaYouTubeInterna: Identifiable, Hashable, Codable {
    let id: String
    let titulo: String
    let cantidad: Int
    let miniatura: URL?
}

enum TipoBusquedaYouTube: String, CaseIterable, Identifiable {
    case musica, videos
    var id: String { rawValue }
    var nombre: String { self == .musica ? "Música" : "Videos y tutoriales" }
    static func inferir(_ texto: String) -> Self {
        let normal = PerfilAgente.normalizar(texto)
        return normal.contains("tutorial") || normal.contains("video") ? .videos : .musica
    }
}

enum AutorizacionYouTube {
    case oauth(String)
    case apiKey(String)
}

enum ErrorYouTubeInterno: LocalizedError {
    case sinCredenciales
    case credencialesInvalidas(String)
    case red(String)
    case respuesta(String)
    case cuotaAgotada(String)
    case cancelado

    var errorDescription: String? {
        switch self {
        case .sinCredenciales:
            return "Conecta tu cuenta Google o guarda una clave de YouTube Data API en Ajustes → Asistente → Modo Música."
        case .credencialesInvalidas(let detalle), .red(let detalle), .respuesta(let detalle),
             .cuotaAgotada(let detalle):
            return detalle
        case .cancelado:
            return "La autorización de Google se canceló o venció."
        }
    }

    var esCuotaAgotada: Bool {
        if case .cuotaAgotada = self { return true }
        return false
    }
}

enum YouTubeDataAPI {
    private struct Respuesta: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            struct Snippet: Decodable {
                struct Thumbnails: Decodable {
                    struct Imagen: Decodable { let url: String }
                    let medium: Imagen?
                    let `default`: Imagen?
                }
                let title: String
                let channelTitle: String
                let thumbnails: Thumbnails?
            }
            let id: ID
            let snippet: Snippet
        }
        struct Fallo: Decodable {
            struct Detalle: Decodable {
                let message: String
                let reason: String?
            }
            let message: String?
            let errors: [Detalle]?
        }
        let items: [Item]?
        let error: Fallo?
    }

    static func idDirecto(_ texto: String) -> String? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return limpio
        }
        guard let u = URL(string: limpio), let host = u.host?.lowercased() else { return nil }
        let candidato: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            candidato = u.pathComponents.dropFirst().first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if u.path.hasPrefix("/shorts/") || u.path.hasPrefix("/embed/") {
                candidato = u.pathComponents.count > 2 ? u.pathComponents[2] : nil
            } else {
                candidato = URLComponents(url: u, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            }
        } else { return nil }
        guard let candidato,
              candidato.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return candidato
    }

    static func buscar(_ consulta: String, tipo: TipoBusquedaYouTube = .musica,
                       completion: @escaping (Result<[VideoYouTubeInterno], Error>) -> Void) {
        if let id = idDirecto(consulta) {
            completion(.success([.init(id: id, titulo: "Video de YouTube", canal: "YouTube", miniatura: nil)]))
            return
        }
        if ProcessInfo.processInfo.environment["BTODICTA_YT_FORCE_LOCAL"] == "1" {
            completion(.failure(ErrorYouTubeInterno.cuotaAgotada("QA: cuota agotada.")))
            return
        }
        YouTubeOAuth.autorizacion { auth in
            switch auth {
            case .failure(let error): completion(.failure(error))
            case .success(let autorizacion):
                buscar(consulta, tipo: tipo, autorizacion: autorizacion, completion: completion)
            }
        }
    }

    private static func buscar(_ consulta: String, tipo: TipoBusquedaYouTube,
                               autorizacion: AutorizacionYouTube,
                               completion: @escaping (Result<[VideoYouTubeInterno], Error>) -> Void) {
        guard YouTubeCuotaBusqueda.consumirSiDisponible() else {
            completion(.failure(ErrorYouTubeInterno.cuotaAgotada(
                "Se alcanzó el límite preventivo de búsquedas de YouTube de hoy.")))
            return
        }
        var c = componentesBusqueda(consulta, tipo: tipo)
        if case .apiKey(let key) = autorizacion { c.queryItems?.append(.init(name: "key", value: key)) }
        guard let url = c.url else {
            completion(.failure(ErrorYouTubeInterno.respuesta("No pude construir la búsqueda de YouTube."))); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        // (sin `Connection: close`: ver nota abajo)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .oauth(let token) = autorizacion {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            let terminar: (Result<[VideoYouTubeInterno], Error>) -> Void = { resultado in
                DispatchQueue.main.async { completion(resultado) }
            }
            if let error { terminar(.failure(ErrorYouTubeInterno.red("YouTube no respondió: \(error.localizedDescription)"))); return }
            guard let http = response as? HTTPURLResponse, let data else {
                terminar(.failure(ErrorYouTubeInterno.respuesta("YouTube devolvió una respuesta vacía."))); return
            }
            guard let dec = try? JSONDecoder().decode(Respuesta.self, from: data) else {
                terminar(.failure(ErrorYouTubeInterno.respuesta("No pude leer la respuesta oficial de YouTube."))); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detalle = dec.error?.message ?? dec.error?.errors?.first?.message
                    ?? "HTTP \(http.statusCode)"
                let razones = dec.error?.errors?.compactMap(\.reason) ?? []
                let cuota = (razones + [detalle]).contains {
                    let s = $0.lowercased()
                    return s.contains("quota") || s.contains("dailylimit")
                }
                if cuota {
                    YouTubeCuotaBusqueda.marcarAgotadaPorServidor()
                    terminar(.failure(ErrorYouTubeInterno.cuotaAgotada(
                        "YouTube informó que la cuota de búsquedas se agotó por hoy.")))
                    return
                }
                terminar(.failure(ErrorYouTubeInterno.respuesta("YouTube rechazó la búsqueda: \(detalle)"))); return
            }
            let videos = (dec.items ?? []).compactMap { item -> VideoYouTubeInterno? in
                guard let id = item.id.videoId,
                      id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
                let mini = item.snippet.thumbnails?.medium?.url ?? item.snippet.thumbnails?.default?.url
                return .init(id: id, titulo: desescapar(item.snippet.title),
                             canal: desescapar(item.snippet.channelTitle),
                             miniatura: mini.flatMap(URL.init(string:)))
            }
            YouTubeBibliotecaCache.registrar(videos)
            terminar(.success(videos))
        }.resume()
    }

    /// Constructor puro para QA: música aplica categoría 10; tutoriales y video
    /// general no quedan atrapados en ese filtro.
    static func componentesBusqueda(_ consulta: String,
                                     tipo: TipoBusquedaYouTube) -> URLComponents {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        c.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "maxResults", value: "12"),
            .init(name: "order", value: "relevance"),
            .init(name: "safeSearch", value: "moderate"),
            .init(name: "videoEmbeddable", value: "true"),
            .init(name: "videoSyndicated", value: "true"),
            .init(name: "relevanceLanguage", value: Locale.preferredLanguages.first?.prefix(2).description ?? "es"),
            .init(name: "q", value: consulta),
        ]
        if tipo == .musica { c.queryItems?.append(.init(name: "videoCategoryId", value: "10")) }
        return c
    }

    private struct RespuestaListas: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct Thumbnails: Decodable {
                    struct Imagen: Decodable { let url: String }
                    let medium: Imagen?
                    let `default`: Imagen?
                }
                let title: String
                let thumbnails: Thumbnails?
            }
            struct Detalles: Decodable { let itemCount: Int? }
            let id: String
            let snippet: Snippet
            let contentDetails: Detalles?
        }
        let items: [Item]?
    }

    private struct RespuestaElementosLista: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable {
                struct Recurso: Decodable { let videoId: String? }
                struct Thumbnails: Decodable {
                    struct Imagen: Decodable { let url: String }
                    let medium: Imagen?
                    let `default`: Imagen?
                }
                let title: String
                let videoOwnerChannelTitle: String?
                let resourceId: Recurso
                let thumbnails: Thumbnails?
            }
            let snippet: Snippet
        }
        let items: [Item]?
    }

    /// Listas propias visibles para la cuenta Google conectada. La API key sola
    /// no identifica al usuario y por eso no se usa como sustituto silencioso.
    static func misListas(completion: @escaping (Result<[ListaYouTubeInterna], Error>) -> Void) {
        YouTubeOAuth.autorizacionSoloCuenta { auth in
            switch auth {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlists")!
                c.queryItems = [
                    .init(name: "part", value: "snippet,contentDetails"),
                    .init(name: "mine", value: "true"),
                    .init(name: "maxResults", value: "50"),
                ]
                pedir(c, token: token, como: RespuestaListas.self) { resultado in
                    completion(resultado.map { respuesta in
                        (respuesta.items ?? []).map { item in
                            let mini = item.snippet.thumbnails?.medium?.url
                                ?? item.snippet.thumbnails?.default?.url
                            return .init(id: item.id, titulo: desescapar(item.snippet.title),
                                         cantidad: item.contentDetails?.itemCount ?? 0,
                                         miniatura: mini.flatMap(URL.init(string:)))
                        }
                    })
                }
            }
        }
    }

    static func videos(de lista: ListaYouTubeInterna,
                       completion: @escaping (Result<[VideoYouTubeInterno], Error>) -> Void) {
        YouTubeOAuth.autorizacionSoloCuenta { auth in
            switch auth {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
                c.queryItems = [
                    .init(name: "part", value: "snippet"),
                    .init(name: "playlistId", value: lista.id),
                    .init(name: "maxResults", value: "50"),
                ]
                pedir(c, token: token, como: RespuestaElementosLista.self) { resultado in
                    completion(resultado.map { respuesta in
                        let videos: [VideoYouTubeInterno] = (respuesta.items ?? []).compactMap { item in
                            guard let id = item.snippet.resourceId.videoId,
                                  id.range(of: #"^[A-Za-z0-9_-]{11}$"#,
                                           options: .regularExpression) != nil else { return nil }
                            let mini = item.snippet.thumbnails?.medium?.url
                                ?? item.snippet.thumbnails?.default?.url
                            return .init(id: id, titulo: desescapar(item.snippet.title),
                                         canal: desescapar(item.snippet.videoOwnerChannelTitle ?? "YouTube"),
                                         miniatura: mini.flatMap(URL.init(string:)))
                        }
                        YouTubeBibliotecaCache.registrar(videos)
                        return videos
                    })
                }
            }
        }
    }

    private static func pedir<T: Decodable>(_ componentes: URLComponents, token: String,
                                             como: T.Type,
                                             completion: @escaping (Result<T, Error>) -> Void) {
        guard let url = componentes.url else {
            completion(.failure(ErrorYouTubeInterno.respuesta("No pude construir la consulta de YouTube.")))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // (sin `Connection: close`: ver nota abajo)
        URLSession.shared.dataTask(with: req) { data, response, error in
            let terminar: (Result<T, Error>) -> Void = { resultado in
                DispatchQueue.main.async { completion(resultado) }
            }
            if let error {
                terminar(.failure(ErrorYouTubeInterno.red("YouTube no respondió: \(error.localizedDescription)")))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                terminar(.failure(ErrorYouTubeInterno.respuesta("YouTube devolvió una respuesta vacía.")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detalle = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                terminar(.failure(ErrorYouTubeInterno.respuesta(
                    "YouTube rechazó la consulta: \(detalle ?? "HTTP \(http.statusCode)")")))
                return
            }
            do { terminar(.success(try JSONDecoder().decode(T.self, from: data))) }
            catch { terminar(.failure(ErrorYouTubeInterno.respuesta("No pude leer la biblioteca de YouTube."))) }
        }.resume()
    }

    private static func desescapar(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - OAuth de Google para una app de escritorio

enum YouTubeOAuth {
    private struct ArchivoCredenciales: Decodable {
        struct Cliente: Decodable {
            let client_id: String
            let client_secret: String?
        }
        let installed: Cliente?
    }

    private struct TokenRespuesta: Decodable {
        let access_token: String?
        let expires_in: Double?
        let refresh_token: String?
        let error_description: String?
        let error: String?
    }

    private static let lock = NSLock()
    private static var tokenMemoria = ""
    private static var tokenVence = Date.distantPast
    private static var flujo: GoogleOAuthLoopback?

    static var tieneCliente: Bool { !ApiKeys.get("YOUTUBE_OAUTH_CLIENT_ID").isEmpty }
    static var conectada: Bool {
        tieneCliente && !ApiKeys.get("YOUTUBE_OAUTH_REFRESH_TOKEN").isEmpty
    }
    static var tieneAPIKey: Bool { !ApiKeys.get("YOUTUBE_DATA_API_KEY").isEmpty }

    /// Validador puro para QA/importación: no escribe configuración ni revela
    /// los campos. Solo acepta el formato de aplicación de escritorio.
    static func clienteEsValido(_ data: Data) -> Bool { (try? decodificarCliente(data)) != nil }

    static func importarCliente(desde url: URL) -> Result<Void, Error> {
        do {
            let data = try Data(contentsOf: url)
            let c = try decodificarCliente(data)
            ApiKeys.set("YOUTUBE_OAUTH_CLIENT_ID", c.client_id)
            ApiKeys.set("YOUTUBE_OAUTH_CLIENT_SECRET", c.client_secret ?? "")
            return .success(())
        } catch {
            return .failure(ErrorYouTubeInterno.credencialesInvalidas(
                "No pude leer las credenciales OAuth: \(error.localizedDescription)"))
        }
    }

    private static func decodificarCliente(_ data: Data) throws -> ArchivoCredenciales.Cliente {
        guard data.count <= 128_000 else {
            throw ErrorYouTubeInterno.credencialesInvalidas("El archivo OAuth es demasiado grande.")
        }
        let root = try JSONDecoder().decode(ArchivoCredenciales.self, from: data)
        guard let c = root.installed,
              c.client_id.hasSuffix(".apps.googleusercontent.com"),
              !c.client_id.contains(where: { $0.isNewline }),
              !(c.client_secret ?? "").contains(where: { $0.isNewline }) else {
            throw ErrorYouTubeInterno.credencialesInvalidas(
                "Elige un JSON de OAuth tipo «Aplicación de escritorio», no uno de aplicación web.")
        }
        return c
    }

    private static func borrarSesionLocal() {
        ApiKeys.set("YOUTUBE_OAUTH_REFRESH_TOKEN", "")
        lock.lock(); tokenMemoria = ""; tokenVence = .distantPast; lock.unlock()
    }

    /// Revoca el refresh token en Google y borra la copia local aun si la red
    /// falla. De ese modo “Desconectar” no es solo un cambio visual.
    static func desconectar(completion: @escaping (String) -> Void) {
        let refresh = ApiKeys.get("YOUTUBE_OAUTH_REFRESH_TOKEN")
        borrarSesionLocal()
        guard !refresh.isEmpty else { completion("Cuenta Google desconectada de esta Mac."); return }
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // (sin `Connection: close`: ver nota abajo)
        req.httpBody = formulario(["token": refresh]).data(using: .utf8)
        URLSession.shared.dataTask(with: req) { _, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode).map { (200..<300).contains($0) } ?? false
            DispatchQueue.main.async {
                completion(ok
                    ? "Cuenta Google revocada y desconectada."
                    : "La copia local se borró. Sin red, revisa también los accesos de tu cuenta Google.")
            }
        }.resume()
    }

    static func autorizacion(completion: @escaping (Result<AutorizacionYouTube, Error>) -> Void) {
        if conectada {
            token { resultado in
                switch resultado {
                case .success(let token): completion(.success(.oauth(token)))
                case .failure(let error):
                    let key = ApiKeys.get("YOUTUBE_DATA_API_KEY")
                    completion(key.isEmpty ? .failure(error) : .success(.apiKey(key)))
                }
            }
            return
        }
        let key = ApiKeys.get("YOUTUBE_DATA_API_KEY")
        completion(key.isEmpty ? .failure(ErrorYouTubeInterno.sinCredenciales) : .success(.apiKey(key)))
    }

    static func autorizacionSoloCuenta(completion: @escaping (Result<String, Error>) -> Void) {
        guard conectada else {
            completion(.failure(ErrorYouTubeInterno.credencialesInvalidas(
                "Conecta tu cuenta Google para ver tus listas. Una clave API solo permite búsquedas públicas.")))
            return
        }
        token(completion: completion)
    }

    static func conectar(completion: @escaping (Bool, String) -> Void) {
        let clientID = ApiKeys.get("YOUTUBE_OAUTH_CLIENT_ID")
        guard !clientID.isEmpty else {
            completion(false, "Primero importa el JSON OAuth de una aplicación de escritorio de Google."); return
        }
        DispatchQueue.main.async {
            flujo?.cancelar()
            let nuevo = GoogleOAuthLoopback(clientID: clientID) { resultado in
                DispatchQueue.main.async {
                    flujo = nil
                    switch resultado {
                    case .failure(let e): completion(false, e.localizedDescription)
                    case .success(let datos):
                        intercambiar(codigo: datos.codigo, verificador: datos.verificador,
                                    redirect: datos.redirect) { tokenResultado in
                            switch tokenResultado {
                            case .failure(let e): completion(false, e.localizedDescription)
                            case .success: completion(true, "Cuenta Google conectada. BtoDicta nunca recibió tu contraseña.")
                            }
                        }
                    }
                }
            }
            flujo = nuevo
            nuevo.iniciar()
        }
    }

    private static func token(completion: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        let guardado = tokenMemoria
        let vigente = tokenVence.timeIntervalSinceNow > 60
        lock.unlock()
        if vigente, !guardado.isEmpty { completion(.success(guardado)); return }
        let refresh = ApiKeys.get("YOUTUBE_OAUTH_REFRESH_TOKEN")
        let client = ApiKeys.get("YOUTUBE_OAUTH_CLIENT_ID")
        guard !refresh.isEmpty, !client.isEmpty else {
            completion(.failure(ErrorYouTubeInterno.sinCredenciales)); return
        }
        var campos = [
            "client_id": client,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ]
        let secret = ApiKeys.get("YOUTUBE_OAUTH_CLIENT_SECRET")
        if !secret.isEmpty { campos["client_secret"] = secret }
        pedirToken(campos, completion: completion)
    }

    private static func intercambiar(codigo: String, verificador: String, redirect: String,
                                     completion: @escaping (Result<String, Error>) -> Void) {
        var campos = [
            "client_id": ApiKeys.get("YOUTUBE_OAUTH_CLIENT_ID"),
            "code": codigo,
            "code_verifier": verificador,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
        ]
        let secret = ApiKeys.get("YOUTUBE_OAUTH_CLIENT_SECRET")
        if !secret.isEmpty { campos["client_secret"] = secret }
        pedirToken(campos, completion: completion)
    }

    private static func pedirToken(_ campos: [String: String],
                                   completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // (sin `Connection: close`: ver nota abajo)
        req.httpBody = formulario(campos).data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, response, error in
            let terminar: (Result<String, Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if let error { terminar(.failure(ErrorYouTubeInterno.red("Google no respondió: \(error.localizedDescription)"))); return }
            guard let data, let http = response as? HTTPURLResponse,
                  let r = try? JSONDecoder().decode(TokenRespuesta.self, from: data),
                  (200..<300).contains(http.statusCode), let access = r.access_token else {
                let detalle = data.flatMap { try? JSONDecoder().decode(TokenRespuesta.self, from: $0) }
                terminar(.failure(ErrorYouTubeInterno.respuesta(
                    "Google rechazó la autorización: \(detalle?.error_description ?? detalle?.error ?? "respuesta inválida")")))
                return
            }
            if let refresh = r.refresh_token, !refresh.isEmpty {
                ApiKeys.set("YOUTUBE_OAUTH_REFRESH_TOKEN", refresh)
            }
            lock.lock(); tokenMemoria = access
            tokenVence = Date().addingTimeInterval(r.expires_in ?? 3_600); lock.unlock()
            terminar(.success(access))
        }.resume()
    }

    private static func formulario(_ valores: [String: String]) -> String {
        var permitidos = CharacterSet.urlQueryAllowed
        permitidos.remove(charactersIn: "+&=?#")
        return valores.sorted { $0.key < $1.key }.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: permitidos) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: permitidos) ?? v)"
        }.joined(separator: "&")
    }
}

private final class GoogleOAuthLoopback {
    struct Datos { let codigo: String; let verificador: String; let redirect: String }

    private let clientID: String
    private let completion: (Result<Datos, Error>) -> Void
    private let cola = DispatchQueue(label: "ec.eztic.BtoDicta.youtube-oauth")
    private let cierreLock = NSLock()
    private var listener: NWListener?
    private var termino = false
    private let estado = GoogleOAuthLoopback.aleatorio(24)
    private let verificador = GoogleOAuthLoopback.aleatorio(48)

    init(clientID: String, completion: @escaping (Result<Datos, Error>) -> Void) {
        self.clientID = clientID; self.completion = completion
    }

    func iniciar() {
        do {
            let parametros = NWParameters.tcp
            parametros.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let l = try NWListener(using: parametros)
            listener = l
            l.stateUpdateHandler = { [weak self] estado in
                guard let self else { return }
                switch estado {
                case .ready: self.abrirNavegador()
                case .failed(let error): self.finalizar(.failure(ErrorYouTubeInterno.red(
                    "No pude abrir el retorno local de Google: \(error.localizedDescription)")))
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] in self?.recibir($0) }
            l.start(queue: cola)
            cola.asyncAfter(deadline: .now() + 180) { [weak self] in
                self?.finalizar(.failure(ErrorYouTubeInterno.cancelado))
            }
        } catch {
            finalizar(.failure(ErrorYouTubeInterno.red(
                "No pude iniciar la autorización local: \(error.localizedDescription)")))
        }
    }

    func cancelar() { cola.async { [weak self] in self?.finalizar(.failure(ErrorYouTubeInterno.cancelado)) } }

    private func abrirNavegador() {
        guard let puerto = listener?.port else {
            finalizar(.failure(ErrorYouTubeInterno.red("Google OAuth no obtuvo un puerto local."))); return
        }
        let redirect = "http://127.0.0.1:\(puerto.rawValue)/oauth2callback"
        let reto = Data(SHA256.hash(data: Data(verificador.utf8)))
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/youtube.readonly"),
            .init(name: "access_type", value: "offline"), .init(name: "prompt", value: "consent"),
            .init(name: "state", value: estado), .init(name: "code_challenge", value: reto),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = c.url else {
            finalizar(.failure(ErrorYouTubeInterno.respuesta("No pude construir la autorización de Google."))); return
        }
        DispatchQueue.main.async { [weak self] in
            guard NSWorkspace.shared.open(url) else {
                self?.finalizar(.failure(ErrorYouTubeInterno.red("No pude abrir el navegador para Google."))); return
            }
        }
    }

    private func recibir(_ conexion: NWConnection) {
        conexion.start(queue: cola)
        conexion.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let pedido = String(data: data, encoding: .utf8),
                  let primera = pedido.components(separatedBy: "\r\n").first,
                  primera.hasPrefix("GET "),
                  let ruta = primera.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://127.0.0.1\(ruta)"),
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
                self?.responder(conexion, ok: false); return
            }
            // Una URL hostil puede repetir parámetros; tomamos el primero sin
            // usar `Dictionary(uniqueKeysWithValues:)`, que abortaría el proceso.
            var dic: [String: String] = [:]
            for item in items where dic[item.name] == nil { dic[item.name] = item.value ?? "" }
            guard dic["state"] == self.estado, let codigo = dic["code"], !codigo.isEmpty,
                  let puerto = self.listener?.port else {
                self.responder(conexion, ok: false)
                self.finalizar(.failure(ErrorYouTubeInterno.respuesta(
                    dic["error_description"] ?? "Google devolvió una autorización inválida."))); return
            }
            self.responder(conexion, ok: true)
            let redirect = "http://127.0.0.1:\(puerto.rawValue)/oauth2callback"
            self.finalizar(.success(.init(codigo: codigo, verificador: self.verificador,
                                          redirect: redirect)))
        }
    }

    private func responder(_ conexion: NWConnection, ok: Bool) {
        let cuerpo = """
        <!doctype html><meta charset="utf-8"><title>BtoDicta</title>
        <body style="font:18px -apple-system;padding:40px;background:#16131d;color:white">
        <h2>\(ok ? "Cuenta autorizada" : "No se pudo autorizar")</h2>
        <p>\(ok ? "Ya puedes volver a BtoDicta y cerrar esta pestaña." : "Vuelve a BtoDicta para revisar el detalle.")</p></body>
        """
        let bytes = Data(cuerpo.utf8)
        let cabecera = "HTTP/1.1 \(ok ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        conexion.send(content: Data(cabecera.utf8) + bytes, completion: .contentProcessed { _ in conexion.cancel() })
    }

    private func finalizar(_ resultado: Result<Datos, Error>) {
        cierreLock.lock()
        guard !termino else { cierreLock.unlock(); return }
        termino = true; cierreLock.unlock()
        listener?.cancel(); listener = nil
        DispatchQueue.main.async { self.completion(resultado) }
    }

    private static func aleatorio(_ bytes: Int) -> String {
        var d = Data(count: bytes)
        let ok = d.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, bytes, ptr.baseAddress!) == errSecSuccess
        }
        if !ok { return UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        return d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
