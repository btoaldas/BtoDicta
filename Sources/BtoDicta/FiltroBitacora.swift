import Foundation

/// Decide si lo que está pasando en pantalla —o sonando por los altavoces—
/// merece entrar en la bitácora.
///
/// El problema que resuelve
/// ------------------------
/// La bitácora graba la jornada entera, y en una jornada entera caben cosas que
/// no son trabajo: una partida, un vídeo, una serie de fondo. Medido el
/// 2026-09-19 sobre esta máquina, el audio del sistema recogió 292 minutos, y
/// entre ellos el anunciador de un juego («Double kill!») y el diálogo de una
/// película. Todo eso llegaba al resumen del día como si fuera actividad
/// laboral.
///
/// La señal necesaria ya estaba grabada: la pista de pantalla anota qué
/// aplicación está al frente en cada momento. A las 22:38, mientras el audio
/// capturaba el juego, al frente estaba «Dota 2». No hace falta comparar formas
/// de onda ni adivinar: basta preguntar quién tiene el foco.
///
/// Las reglas
/// ----------
/// - **Nada se filtra de fábrica.** Con las listas vacías, todo entra igual que
///   siempre. Empezar decidiendo por el usuario qué de su día no importa sería
///   pasarse: estas listas las escribe él.
/// - **La lista blanca gana a la negra.** Permite bloquear un navegador entero y
///   rescatar una pestaña concreta, que es el caso real: el mismo Edge muestra
///   YouTube y una reunión.
/// - Se mira **la aplicación y el título de la ventana**, porque solo con la
///   aplicación no se distingue un vídeo de una videollamada cuando ambos viven
///   dentro del navegador. Medido: el 89 % del audio del sistema salía del
///   navegador.
/// - La comparación es por **fragmento, sin distinguir mayúsculas ni tildes**:
///   quien escribe «youtube» espera que valga para «YouTube — Mozilla Firefox».
enum FiltroBitacora {

    enum Veredicto: Equatable {
        case entra
        case fuera(String)      // el motivo, para poder explicarlo en el registro
    }

    // MARK: Listas

    static func appsExcluidas() -> [String] { lista("bitacora_excluir_apps") }
    static func titulosExcluidos() -> [String] { lista("bitacora_excluir_titulos") }
    static func appsIncluidas() -> [String] { lista("bitacora_incluir_apps") }
    static func titulosIncluidos() -> [String] { lista("bitacora_incluir_titulos") }

    private static func lista(_ clave: String) -> [String] {
        ((Config.json0(clave) as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// ¿Hay alguna regla escrita? Si no, ni se consulta: el caso normal es que
    /// el usuario no haya configurado nada y todo entre.
    static var hayReglas: Bool {
        !appsExcluidas().isEmpty || !titulosExcluidos().isEmpty
    }

    // MARK: El veredicto

    /// Lo que mira el filtro cuando al frente hay un navegador: la URL de la
    /// PESTAÑA ACTIVA, no solo el título de la ventana.
    ///
    /// Un navegador no trabaja por ventanas sino por pestañas: en la misma
    /// ventana conviven un vídeo y el correo. El título ayuda —refleja la
    /// pestaña activa— pero puede engañar: un artículo llamado «Por qué dejé
    /// YouTube» quedaría excluido sin ser un vídeo. La URL no se presta a eso.
    ///
    /// **Lo que NO se puede saber, y conviene decirlo:** qué pestaña está
    /// sonando. Los navegadores lo saben y lo muestran con el altavoz en la
    /// pestaña, pero no lo exponen a otras aplicaciones — comprobado el
    /// 2026-09-20: `audible of active tab` da error -1700, y las únicas
    /// propiedades que ofrecen son URL, name, loading, class e id. Solo una
    /// extensión instalada dentro del navegador podría leerlo.
    ///
    /// No hace falta: el criterio es **qué pestaña estás mirando**. Con un vídeo
    /// sonando detrás mientras escribes un correo, la pestaña activa es el
    /// correo y el trozo se guarda, que es lo correcto.
    ///
    /// Firefox queda fuera de esto: no expone sus pestañas por AppleScript. Ahí
    /// se sigue mirando el título de la ventana, que también refleja la pestaña
    /// activa aunque sea menos preciso.
    /// Lo que dice el navegador de sí mismo, si es que lo dijo hace poco.
    ///
    /// Tiene PRIORIDAD sobre lo que se adivina por el foco, y no por capricho:
    /// mirar el foco es un sustituto pobre de saber qué suena, y falla en los
    /// casos normales —música en un monitor mientras se trabaja en otro, un
    /// vídeo en una ventana de atrás—. El navegador sí lo sabe.
    ///
    /// Si el informe caducó o no hay extensión, se vuelve a adivinar. Degradar
    /// es correcto: la bitácora funcionaba antes de existir la extensión y debe
    /// seguir funcionando si alguien la desinstala.
    static func decidirConNavegador(app: String?, pista: String?) -> Veredicto {
        guard hayReglas else { return .entra }

        // ¿Hay un navegador al frente que esté informando?
        let informes = EstadoNavegadores.vigentes()
        if let informe = informes.first(where: { coincide(app: app, con: $0.navegador) }),
           let activa = informe.activa {
            // Lo que se mira es LA PESTAÑA QUE SE ESTÁ MIRANDO, no la que suena.
            // Con un vídeo sonando detrás mientras se escribe un correo, lo que
            // se está haciendo es escribir el correo.
            let pistaReal = activa.url.isEmpty ? activa.titulo : activa.url
            return decidir(app: app, ventana: pistaReal.isEmpty ? pista : pistaReal)
        }
        return decidir(app: app, ventana: pista)
    }

    /// ¿El nombre de la aplicación al frente corresponde a este navegador?
    private static func coincide(app: String?, con navegador: String) -> Bool {
        guard let a = app, !a.isEmpty else { return false }
        let x = normalizar(a), y = normalizar(navegador)
        return x.contains(y) || y.contains(x)
    }

    static func contextoDelFrente() -> (app: String?, pista: String?) {
        let frente = ContextoApp.alFrente()
        let app = frente.nombre.isEmpty ? nil : frente.nombre
        if let url = ContextoApp.urlNavegador(frente.bundleId), !url.isEmpty {
            return (app, url)
        }
        return (app, ContinuoPantalla.tituloVentanaAlFrente())
    }

    static func decidir(app: String?, ventana: String?) -> Veredicto {
        decidir(app: app, ventana: ventana,
                excluirApps: appsExcluidas(), excluirTitulos: titulosExcluidos(),
                incluirApps: appsIncluidas(), incluirTitulos: titulosIncluidos())
    }

    /// La decisión, sin leer nada de disco.
    ///
    /// Está separada de la anterior para poder probarla. `decidir(app:ventana:)`
    /// saca las listas de `Config`, que apunta al `config.json` de quien esté
    /// usando el equipo: una prueba escrita contra ella mediría la configuración
    /// real del usuario en vez de la regla, y cambiaría de resultado según el día.
    static func decidir(app: String?, ventana: String?,
                        excluirApps: [String], excluirTitulos: [String],
                        incluirApps: [String], incluirTitulos: [String]) -> Veredicto {
        // Sin una sola regla escrita no se mira nada: el caso normal es que el
        // usuario no haya configurado nada y todo entre.
        guard !excluirApps.isEmpty || !excluirTitulos.isEmpty else { return .entra }
        let a = normalizar(app ?? "")
        let v = normalizar(ventana ?? "")

        // La lista blanca manda. Va PRIMERO a propósito: sirve para rescatar
        // excepciones de una regla ancha («no grabes el navegador, salvo las
        // reuniones»), y eso solo funciona si se mira antes de excluir.
        for permitida in incluirApps where !a.isEmpty && a.contains(normalizar(permitida)) {
            return .entra
        }
        for permitido in incluirTitulos where !v.isEmpty && v.contains(normalizar(permitido)) {
            return .entra
        }

        for excluida in excluirApps where !a.isEmpty && a.contains(normalizar(excluida)) {
            return .fuera("la aplicación «\(app ?? "")» está en tu lista de excluidas")
        }
        for excluido in excluirTitulos where !v.isEmpty && v.contains(normalizar(excluido)) {
            return .fuera("el título contiene «\(excluido)», que excluiste")
        }
        return .entra
    }

    /// Minúsculas y sin tildes, para que «Música» case con «musica» y «YouTube»
    /// con «youtube». Quien escribe una regla no debería tener que acertar la
    /// acentuación exacta que use cada aplicación en su título.
    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
