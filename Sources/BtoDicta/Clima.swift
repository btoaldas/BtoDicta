import AppKit
import CoreLocation
import Foundation

// MARK: - Solicitud meteorológica

struct SolicitudClima: Equatable {
    let lugar: String?
    let diasDesdeHoy: Int

    var usaUbicacionActual: Bool { lugar == nil }

    /// Gramática deliberadamente conservadora. Una pregunta o una orden breve
    /// sí entra; una narración como «ayer hablamos del clima» sigue como dictado.
    static func interpretar(_ texto: String) -> SolicitudClima? {
        let normal = PerfilAgente.normalizar(texto)
        guard !normal.isEmpty else { return nil }
        // Palabras meteorológicas usadas con otro sentido. Estas frases deben
        // seguir como dictado/consulta normal y nunca activar el clima.
        let otroContexto = [
            "tiempo hace falta", "tiempo hace que", "cuanto tiempo",
            "clima laboral", "clima organizacional", "clima de trabajo",
            "clima politico", "clima social", "pronostico de ventas",
            "pronostico financiero", "pronostico electoral",
            "temperatura del procesador", "temperatura de la cpu",
            "temperatura del horno", "temperatura del motor",
        ].contains(where: { normal.contains($0) })
        guard !otroContexto else { return nil }
        let meteorologico = normal.contains("clima") || normal.contains("pronostico")
            || normal.contains("temperatura") || normal.contains("tiempo hace")
            || normal.contains("tiempo hara") || normal.contains("tiempo habra")
            || normal.contains("como esta el tiempo") || normal.contains("como estara el tiempo")
            || normal.contains("va a llover") || normal.contains("llovera")
            || normal.contains("llueve hoy") || normal.contains("llueve manana")
        guard meteorologico else { return nil }

        let pedido = texto.contains("?") || texto.contains("¿")
            || normal.hasPrefix("clima") || normal.hasPrefix("pronostico")
            || normal.hasPrefix("temperatura") || normal.hasPrefix("va a llover")
            || normal.hasPrefix("llovera")
            || ["dime", "dimelo", "consulta", "consultame", "revisa", "revisame",
                "busca", "buscame", "quiero", "quisiera", "necesito", "puedes",
                "podrias", "me puedes", "me podrias", "como esta", "como estara",
                "que clima", "que tiempo", "cual es"]
                .contains(where: { normal.hasPrefix($0) })
        guard pedido else { return nil }

        let dias = normal.contains("pasado manana") ? 2
            : (normal.contains("manana") ? 1 : 0)
        return SolicitudClima(lugar: extraerLugar(texto), diasDesdeHoy: dias)
    }

    private static func extraerLugar(_ texto: String) -> String? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "¿?¡!.;"))
        let patrones = [
            #"\ben\s+([^?!.]+)$"#,
            #"\b(?:clima|pron[oó]stico|temperatura)\s+(?:actual\s+)?(?:del|de|en|para)\s+([^?!.]+)$"#,
            #"\b(?:clima|pron[oó]stico|temperatura)\s+([^?!.]+)$"#,
        ]
        for patron in patrones {
            guard let re = try? NSRegularExpression(pattern: patron,
                                                     options: [.caseInsensitive]) else { continue }
            let ns = t as NSString
            guard let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { continue }
            var lugar = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-\n\t"))
            lugar = lugar.replacingOccurrences(
                of: #"(?:^|\s+)(?:para\s+)?(?:el\s+)?(?:día\s+de\s+hoy|dia\s+de\s+hoy|pasado\s+mañana|pasado\s+manana|mañana|manana|hoy)$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
            let n = PerfilAgente.normalizar(lugar)
            let genericos: Set<String> = [
                "", "actual", "hoy", "manana", "pasado manana", "dia", "el dia",
                "dia de hoy", "el dia de hoy",
                "mi ubicacion", "mi ubicacion actual", "aqui", "donde estoy",
                "el lugar donde estoy", "la ciudad donde estoy",
            ]
            // Ya hubo una coincidencia gramatical, pero lo capturado era solo
            // la fecha/ubicación genérica. No probar el patrón más amplio:
            // convertiría «clima del día de hoy» en la ciudad «del día».
            if genericos.contains(n) || n.hasPrefix("dia de hoy") { return nil }
            if !genericos.contains(n), !n.hasPrefix("dia de hoy"), lugar.count <= 140 {
                return lugar
            }
        }
        return nil
    }
}

// MARK: - Una ubicación puntual, nunca rastreo continuo

extension Notification.Name {
    static let betoUbicacionClimaCambio = Notification.Name("BtoDictaUbicacionClimaCambio")
}

final class UbicacionClima: NSObject, CLLocationManagerDelegate {
    static let shared = UbicacionClima()

    enum Fallo: LocalizedError {
        case sinPermiso, restringida, noDisponible, timeout, sistema(Error)
        var errorDescription: String? {
            switch self {
            case .sinPermiso:
                return "BtoDicta no tiene permiso de ubicación. Autorízalo en Ajustes o configura una ciudad de respaldo."
            case .restringida:
                return "La ubicación está restringida en esta Mac. Dime una ciudad o configura una ubicación de respaldo."
            case .noDisponible:
                return "No pude obtener la ubicación actual. Dime una ciudad o configura una ubicación de respaldo."
            case .timeout:
                return "La ubicación tardó demasiado. Dime una ciudad o vuelve a intentarlo."
            case .sistema(let error): return error.localizedDescription
            }
        }
    }

    private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        // Para clima basta una zona aproximada; no pedimos precisión de calle.
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        return m
    }()
    private var pendientes: [(Result<CLLocation, Error>) -> Void] = []
    private var timeout: DispatchWorkItem?
    private var leyendo = false
    private var cache: (ubicacion: CLLocation, fecha: Date)?

    static func estado() -> CLAuthorizationStatus {
        shared.manager.authorizationStatus
    }

    static func nombreEstado(_ estado: CLAuthorizationStatus = estado()) -> String {
        switch estado {
        case .authorizedAlways, .authorizedWhenInUse: return "Permitida"
        case .denied: return "Denegada"
        case .restricted: return "Restringida"
        case .notDetermined: return "Se pedirá al consultar"
        @unknown default: return "Desconocida"
        }
    }

    func solicitarPermiso() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.solicitarPermiso() }
            return
        }
        let m = manager
        guard m.authorizationStatus == .notDetermined else {
            Self.abrirPrivacidad(); return
        }
        NSApp.activate(ignoringOtherApps: true)
        m.requestWhenInUseAuthorization()
    }

    static func abrirPrivacidad() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    func obtener(_ completion: @escaping (Result<CLLocation, Error>) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.obtener(completion) }
            return
        }
        if let cache, Date().timeIntervalSince(cache.fecha) < 15 * 60 {
            completion(.success(cache.ubicacion)); return
        }
        pendientes.append(completion)
        let m = manager
        switch m.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: comenzarLectura()
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            m.requestWhenInUseAuthorization()
        case .denied: terminar(.failure(Fallo.sinPermiso))
        case .restricted: terminar(.failure(Fallo.restringida))
        @unknown default: terminar(.failure(Fallo.noDisponible))
        }
    }

    private func comenzarLectura() {
        guard !leyendo, !pendientes.isEmpty else { return }
        leyendo = true
        manager.requestLocation()
        let trabajo = DispatchWorkItem { [weak self] in
            self?.terminar(.failure(Fallo.timeout))
        }
        timeout?.cancel(); timeout = trabajo
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: trabajo)
    }

    private func terminar(_ resultado: Result<CLLocation, Error>) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.terminar(resultado) }
            return
        }
        timeout?.cancel(); timeout = nil; leyendo = false
        let callbacks = pendientes; pendientes.removeAll()
        callbacks.forEach { $0(resultado) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        NotificationCenter.default.post(name: .betoUbicacionClimaCambio, object: nil)
        guard !pendientes.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: comenzarLectura()
        case .denied: terminar(.failure(Fallo.sinPermiso))
        case .restricted: terminar(.failure(Fallo.restringida))
        case .notDetermined: break
        @unknown default: terminar(.failure(Fallo.noDisponible))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let mejor = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
            terminar(.failure(Fallo.noDisponible)); return
        }
        cache = (mejor, Date())
        terminar(.success(mejor))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let e = error as? CLError, e.code == .denied {
            terminar(.failure(Fallo.sinPermiso))
        } else { terminar(.failure(Fallo.sistema(error))) }
    }
}

// MARK: - Open-Meteo (HTTPS, sin clave)

enum ClimaServicio {
    private struct Geocodificacion: Decodable { let results: [Lugar]? }
    private struct Lugar: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let countryCode: String?
        let admin1: String?
        let admin2: String?
        let population: Int?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, country, admin1, admin2, population
            case countryCode = "country_code"
        }

        var etiqueta: String {
            var partes: [String] = []
            for p in [name, admin1, country].compactMap({ $0 }) where
                !partes.contains(where: { PerfilAgente.normalizar($0) == PerfilAgente.normalizar(p) }) {
                partes.append(p)
            }
            return partes.joined(separator: ", ")
        }
    }
    private struct Respuesta: Decodable {
        let current: Actual?
        let daily: Diario?
    }
    private struct Actual: Decodable {
        let temperature: Double?
        let apparent: Double?
        let humidity: Double?
        let precipitation: Double?
        let weatherCode: Int?
        let wind: Double?
        enum CodingKeys: String, CodingKey {
            case precipitation
            case temperature = "temperature_2m"
            case apparent = "apparent_temperature"
            case humidity = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case wind = "wind_speed_10m"
        }
    }
    private struct Diario: Decodable {
        let time: [String]?
        let maxima: [Double]?
        let minima: [Double]?
        let probabilidad: [Double]?
        let codigos: [Int]?
        enum CodingKeys: String, CodingKey {
            case time
            case maxima = "temperature_2m_max"
            case minima = "temperature_2m_min"
            case probabilidad = "precipitation_probability_max"
            case codigos = "weather_code"
        }
    }

    private static let sesion: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 14
        c.waitsForConnectivity = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    static func consultar(_ texto: String,
                          completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard let solicitud = SolicitudClima.interpretar(texto) else {
            completar(.init(ok: false,
                mensaje: "No entendí qué clima quieres consultar. Prueba: clima de Quito, o clima de hoy."),
                completion)
            return
        }
        consultar(solicitud, completion: completion)
    }

    static func consultar(_ solicitud: SolicitudClima,
                          completion: @escaping (ResultadoHerramientaApple) -> Void) {
        if let lugar = solicitud.lugar {
            geocodificar(lugar) { resultado in
                switch resultado {
                case .success(let l): pronostico(lat: l.latitude, lon: l.longitude,
                                                  etiqueta: l.etiqueta, fuente: "ciudad",
                                                  solicitud: solicitud, completion: completion)
                case .failure(let error): completar(.init(ok: false,
                    mensaje: error.localizedDescription,
                    evidencia: ["proveedor": "Open-Meteo", "fuente": "ciudad"]), completion)
                }
            }
            return
        }
        let respaldo = Config.climaUbicacionPredeterminada()
        guard Config.climaUsarUbicacionActual() else {
            if !respaldo.isEmpty {
                consultar(SolicitudClima(lugar: respaldo, diasDesdeHoy: solicitud.diasDesdeHoy),
                          completion: completion)
            } else {
                completar(.init(ok: false,
                    mensaje: "La ubicación actual está desactivada. Dime una ciudad o configura una ubicación de respaldo."),
                    completion)
            }
            return
        }
        UbicacionClima.shared.obtener { resultado in
            switch resultado {
            case .success(let l):
                pronostico(lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                            etiqueta: "tu ubicación actual", fuente: "ubicacion_actual",
                            solicitud: solicitud, completion: completion)
            case .failure(let error):
                if !respaldo.isEmpty {
                    consultar(SolicitudClima(lugar: respaldo,
                                             diasDesdeHoy: solicitud.diasDesdeHoy), completion: completion)
                } else {
                    completar(.init(ok: false, mensaje: error.localizedDescription,
                                    evidencia: ["fuente": "ubicacion_actual"]), completion)
                }
            }
        }
    }

    private static func geocodificar(_ consulta: String,
                                     completion: @escaping (Result<Lugar, Error>) -> Void) {
        let limpia = String(consulta.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        let terminos = consultasGeocodificacion(limpia)
        geocodificar(terminos: terminos, indice: 0, consultaCompleta: limpia,
                     completion: completion)
    }

    /// Open-Meteo busca nombres de localidades, no direcciones completas. Si
    /// el STT quitó las comas de «Quito, Pichincha, Ecuador», probamos prefijos
    /// decrecientes y acotados hasta encontrar la ciudad. Con comas usamos
    /// directamente el primer componente, que conserva ciudades compuestas.
    static func consultasGeocodificacion(_ consulta: String) -> [String] {
        let limpia = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpia.contains(",") {
            let primero = limpia.split(separator: ",", maxSplits: 1).first.map(String.init) ?? limpia
            return [primero.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        let palabras = limpia.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard palabras.count > 1 else { return [limpia] }
        var salida = [limpia]
        let mayor = min(palabras.count - 1, 5)
        for cantidad in stride(from: mayor, through: 1, by: -1) {
            let candidato = palabras.prefix(cantidad).joined(separator: " ")
            if !salida.contains(where: {
                PerfilAgente.normalizar($0) == PerfilAgente.normalizar(candidato)
            }) { salida.append(candidato) }
        }
        return salida
    }

    private static func geocodificar(terminos: [String], indice: Int,
                                     consultaCompleta: String,
                                     completion: @escaping (Result<Lugar, Error>) -> Void) {
        guard terminos.indices.contains(indice) else {
            completarResultado(.failure(FalloServicio.lugarNoEncontrado(consultaCompleta)), completion)
            return
        }
        let termino = terminos[indice]
        var c = URLComponents()
        c.scheme = "https"; c.host = "geocoding-api.open-meteo.com"; c.path = "/v1/search"
        c.queryItems = [URLQueryItem(name: "name", value: termino),
                        URLQueryItem(name: "count", value: "10"),
                        URLQueryItem(name: "language", value: "es"),
                        URLQueryItem(name: "format", value: "json")]
        guard let url = c.url else {
            completarResultado(.failure(FalloServicio.respuestaInvalida), completion); return
        }
        pedir(url) { resultado in
            switch resultado {
            case .failure(let error): completarResultado(.failure(error), completion)
            case .success(let data):
                guard let lista = try? JSONDecoder().decode(Geocodificacion.self, from: data).results,
                      !lista.isEmpty else {
                    geocodificar(terminos: terminos, indice: indice + 1,
                                 consultaCompleta: consultaCompleta, completion: completion)
                    return
                }
                let q = PerfilAgente.normalizar(consultaCompleta)
                let primera = PerfilAgente.normalizar(termino)
                let elegida = lista.max { a, b in puntaje(a, consulta: q, primera: primera)
                    < puntaje(b, consulta: q, primera: primera) }!
                completarResultado(.success(elegida), completion)
            }
        }
    }

    private static func puntaje(_ l: Lugar, consulta: String, primera: String) -> Int {
        let h = PerfilAgente.normalizar([l.name, l.admin1, l.admin2, l.country, l.countryCode]
            .compactMap { $0 }.joined(separator: " "))
        var s = PerfilAgente.normalizar(l.name) == primera ? 100 : 0
        for token in Set(consulta.split(separator: " ").map(String.init)) where token.count >= 3 {
            if h.split(separator: " ").contains(Substring(token)) { s += 10 }
        }
        s += min(9, Int(log10(Double(max(1, l.population ?? 1)))))
        return s
    }

    private static func pronostico(lat: Double, lon: Double, etiqueta: String,
                                   fuente: String, solicitud: SolicitudClima,
                                   completion: @escaping (ResultadoHerramientaApple) -> Void) {
        var c = URLComponents()
        c.scheme = "https"; c.host = "api.open-meteo.com"; c.path = "/v1/forecast"
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", lon)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(max(2, solicitud.diasDesdeHoy + 1))),
        ]
        guard let url = c.url else {
            completar(.init(ok: false, mensaje: FalloServicio.respuestaInvalida.localizedDescription), completion)
            return
        }
        pedir(url) { resultado in
            switch resultado {
            case .failure(let error): completar(.init(ok: false,
                mensaje: "No pude consultar el clima ahora: \(error.localizedDescription)",
                evidencia: ["proveedor": "Open-Meteo", "fuente": fuente]), completion)
            case .success(let data):
                guard let r = try? JSONDecoder().decode(Respuesta.self, from: data),
                      let mensaje = mensaje(r, lugar: etiqueta, dia: solicitud.diasDesdeHoy) else {
                    completar(.init(ok: false,
                        mensaje: "Open-Meteo no devolvió un pronóstico utilizable para \(etiqueta).",
                        evidencia: ["proveedor": "Open-Meteo", "fuente": fuente]), completion)
                    return
                }
                completar(.init(ok: true, mensaje: mensaje,
                    evidencia: ["proveedor": "Open-Meteo", "fuente": fuente,
                                "lugar": String(etiqueta.prefix(140)),
                                "dia": String(solicitud.diasDesdeHoy)]), completion)
            }
        }
    }

    private static func pedir(_ url: URL,
                              completion: @escaping (Result<Data, Error>) -> Void) {
        guard url.scheme == "https",
              ["api.open-meteo.com", "geocoding-api.open-meteo.com"].contains(url.host ?? "") else {
            completion(.failure(FalloServicio.urlNoSegura)); return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("close", forHTTPHeaderField: "Connection")
        sesion.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let h = response as? HTTPURLResponse, (200..<300).contains(h.statusCode),
                  let data, data.count <= 1_500_000 else {
                completion(.failure(FalloServicio.respuestaInvalida)); return
            }
            completion(.success(data))
        }.resume()
    }

    private static func mensaje(_ r: Respuesta, lugar: String, dia: Int) -> String? {
        let i = max(0, dia)
        guard let d = r.daily,
              let maxs = d.maxima, let mins = d.minima,
              maxs.indices.contains(i), mins.indices.contains(i) else { return nil }
        let codigo = d.codigos?.indices.contains(i) == true ? d.codigos?[i] : r.current?.weatherCode
        let estado = descripcion(codigo ?? -1)
        let lluvia = d.probabilidad?.indices.contains(i) == true ? d.probabilidad?[i] : nil
        let rango = "entre \(entero(mins[i])) y \(entero(maxs[i])) grados"
        let prob = lluvia.map { ", con \(entero($0)) por ciento de probabilidad de lluvia" } ?? ""
        if i == 0, let actual = r.current, let temp = actual.temperature {
            var partes = ["En \(lugar) ahora hay \(estado) y \(entero(temp)) grados"]
            if let sensacion = actual.apparent, abs(sensacion - temp) >= 1 {
                partes.append("sensación de \(entero(sensacion)) grados")
            }
            partes.append("hoy estará \(rango)\(prob)")
            if let humedad = actual.humidity { partes.append("humedad de \(entero(humedad)) por ciento") }
            if let viento = actual.wind { partes.append("viento de \(entero(viento)) kilómetros por hora") }
            return partes.joined(separator: "; ") + "."
        }
        let diaTexto = i == 1 ? "Mañana" : (i == 2 ? "Pasado mañana" : "Hoy")
        return "\(diaTexto), en \(lugar) se espera \(estado), \(rango)\(prob)."
    }

    private static func entero(_ n: Double) -> Int { Int(n.rounded()) }

    static func descripcion(_ codigo: Int) -> String {
        switch codigo {
        case 0: return "cielo despejado"
        case 1: return "cielo mayormente despejado"
        case 2: return "cielo parcialmente nublado"
        case 3: return "cielo nublado"
        case 45, 48: return "niebla"
        case 51, 53, 55: return "llovizna"
        case 56, 57: return "llovizna helada"
        case 61: return "lluvia ligera"
        case 63: return "lluvia moderada"
        case 65: return "lluvia fuerte"
        case 66, 67: return "lluvia helada"
        case 71, 73, 75, 77: return "nieve"
        case 80: return "chubascos ligeros"
        case 81: return "chubascos moderados"
        case 82: return "chubascos fuertes"
        case 85, 86: return "chubascos de nieve"
        case 95: return "tormenta"
        case 96, 99: return "tormenta con granizo"
        default: return "condiciones variables"
        }
    }

    private enum FalloServicio: LocalizedError {
        case urlNoSegura, respuestaInvalida, lugarNoEncontrado(String)
        var errorDescription: String? {
            switch self {
            case .urlNoSegura: return "La URL meteorológica no es HTTPS."
            case .respuestaInvalida: return "El servicio meteorológico devolvió una respuesta inválida."
            case .lugarNoEncontrado(let lugar):
                return "No encontré «\(lugar)». Prueba con ciudad, provincia y país."
            }
        }
    }

    private static func completar(_ resultado: ResultadoHerramientaApple,
                                  _ completion: @escaping (ResultadoHerramientaApple) -> Void) {
        DispatchQueue.main.async { completion(resultado) }
    }

    private static func completarResultado<T>(_ resultado: Result<T, Error>,
                                               _ completion: @escaping (Result<T, Error>) -> Void) {
        DispatchQueue.main.async { completion(resultado) }
    }
}

// MARK: - QA puro y reproducible

enum ClimaQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_CLIMATEST"] == "1" else { return }
        let casos: [(String, String?, Int)] = [
            ("¿Puedes decirme el clima del día de hoy?", nil, 0),
            ("¿Me puedes decir el clima de Quito, Pichincha, Ecuador?", "Quito, Pichincha, Ecuador", 0),
            ("Qué tiempo hará mañana en Quito", "Quito", 1),
            ("¿Va a llover hoy en Tena?", "Tena", 0),
            ("Pronóstico para pasado mañana en Cuenca", "Cuenca", 2),
            ("Clima Quito", "Quito", 0),
            ("Clima actual", nil, 0),
            ("¿Qué temperatura hay en Loja?", "Loja", 0),
        ]
        var fallos = 0
        for (texto, lugar, dia) in casos {
            let r = SolicitudClima.interpretar(texto)
            let ok = r?.lugar == lugar && r?.diasDesdeHoy == dia
            if !ok { fallos += 1 }
            print("CLIMATEST \(ok ? "OK" : "FALLA") \(texto) → \(r?.lugar ?? "ubicación actual") día=\(r?.diasDesdeHoy ?? -1)")
        }
        let negativos = [
            "El clima de Quito estuvo agradable ayer.",
            "Necesito tiempo para terminar el informe.",
            "El documento habla del pronóstico meteorológico.",
            "Ayer pregunté si iba a llover.",
            "¿Qué tiempo hace falta para terminar el informe?",
            "¿Cómo está el clima laboral de la oficina?",
            "Temperatura del procesador de esta Mac.",
            "Pronóstico de ventas para mañana.",
        ]
        for texto in negativos {
            let ok = SolicitudClima.interpretar(texto) == nil
            if !ok { fallos += 1 }
            print("CLIMATEST NEG \(ok ? "OK" : "FALLA") \(texto)")
        }
        let codigos = ClimaServicio.descripcion(0) == "cielo despejado"
            && ClimaServicio.descripcion(63) == "lluvia moderada"
            && ClimaServicio.descripcion(95) == "tormenta"
        if !codigos { fallos += 1 }
        print("CLIMATEST códigos=\(codigos ? "OK" : "FALLA")")
        let terminos = ClimaServicio.consultasGeocodificacion("Quito Pichincha Ecuador")
        let sinComas = terminos == ["Quito Pichincha Ecuador", "Quito Pichincha", "Quito"]
        if !sinComas { fallos += 1 }
        print("CLIMATEST ciudad-sin-comas=\(sinComas ? "OK" : "FALLA") \(terminos)")
        print("CLIMATEST \(fallos == 0 ? "TODO OK" : "FALLOS=\(fallos)")")
        exit(fallos == 0 ? 0 : 11)
    }
}
