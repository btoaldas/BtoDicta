import Foundation

/// El catálogo de exclusiones propuestas (spec 007, T05, RF-01 y RF-04).
///
/// Por qué existe
/// --------------
/// La lista de lo que la bitácora no debe mirar nace vacía, y llenarla a mano son
/// decenas de decisiones sueltas. Por eso no se hace. Un valor de fábrica vacío no
/// protege a nadie.
///
/// Esto NO aplica nada por su cuenta. Propone categorías completas; quien decide
/// es el usuario, y hasta que acepte, su configuración no se toca (RNF-02).
enum SemillasExclusion {

    /// A qué lista va una entrada.
    ///
    /// Esto no es un detalle de organización: es el RF-04 hecho dato. Una regla
    /// escrita en la lista equivocada **nunca puede coincidir**, y falla en
    /// silencio — pareció configurada durante días. `titulos` se compara contra
    /// el título de la ventana; `apps`, contra el nombre de la aplicación.
    enum Destino: String, Codable {
        case titulos
        case apps
    }

    struct Categoria: Codable, Identifiable {
        let id: String
        let nombre: String
        let destino: Destino
        let descripcion: String
        let entradas: [String]
    }

    struct Catalogo: Codable {
        let version: Int
        let categorias: [Categoria]
    }

    // MARK: Leer el catálogo

    /// Lo que trae esta copia de la aplicación.
    ///
    /// Si no se puede leer se devuelve un catálogo vacío en vez de reventar: sin
    /// semillas la pantalla queda sosa, pero la bitácora sigue funcionando. Un
    /// catálogo que no carga no puede ser motivo de que la app no arranque.
    static func catalogo() -> Catalogo {
        guard let ruta = Bundle.main.url(forResource: "semillas-exclusion", withExtension: "json"),
              let datos = try? Data(contentsOf: ruta),
              let leido = try? JSONDecoder().decode(Catalogo.self, from: datos) else {
            return Catalogo(version: 0, categorias: [])
        }
        return leido
    }

    // MARK: Validación del propio catálogo

    /// Qué le pasa a una entrada para no ser aceptable.
    ///
    /// Se comprueba el catálogo y no solo lo que escriba el usuario, porque el
    /// catálogo viaja dentro de la aplicación: un error aquí lo heredan todos, y
    /// nadie lo revisa después.
    static func problemas(_ c: Catalogo) -> [String] {
        var males: [String] = []
        var vistos = Set<String>()

        for cat in c.categorias {
            if !vistos.insert(cat.id).inserted {
                males.append("la categoría «\(cat.id)» está repetida")
            }
            if cat.entradas.isEmpty {
                males.append("la categoría «\(cat.id)» no tiene ni una entrada")
            }
            for e in cat.entradas {
                let limpio = e.trimmingCharacters(in: .whitespaces)
                if limpio != e {
                    males.append("«\(e)» (\(cat.id)) tiene espacios de sobra")
                }
                if limpio.lowercased() != limpio {
                    males.append("«\(e)» (\(cat.id)) tiene mayúsculas: la comparación ya ignora la caja, y así se ve igual en el archivo que en la lista")
                }
                // La trampa que justifica esto: la coincidencia es por SUBCADENA.
                // Pero el riesgo NO es el mismo en las dos listas, y la primera
                // versión de esta comprobación lo trataba igual — con el
                // resultado de rechazar «vlc», que estaba en el propio catálogo.
                //
                // - Un título de ventana es texto largo y ajeno: ahí una cadena
                //   corta casa con cualquier cosa. «sex» casaría con «Essex» y
                //   «sexta»; «porn» con una URL de trabajo que lo llevara dentro.
                //   Se exige además un punto, porque un dominio sin punto no es
                //   un dominio: es un fragmento.
                // - Un nombre de aplicación es corto y controlado por el sistema.
                //   «vlc» es el nombre entero, no un trozo de otra cosa.
                let minimo = cat.destino == .titulos ? 4 : 3
                if limpio.count < minimo {
                    males.append("«\(e)» (\(cat.id)) es demasiado corta para comparar por subcadena")
                }
                if cat.destino == .titulos && !limpio.contains(".") {
                    males.append("«\(e)» (\(cat.id)) va a la lista de títulos pero no parece un dominio")
                }
            }
        }
        return males
    }

    // MARK: Repartir por destino

    /// Reparte las entradas elegidas en las dos listas a las que pertenecen.
    ///
    /// Devuelve lo que hay que AÑADIR, no la lista final: quien escribe decide si
    /// unir o reemplazar, y aquí no se toca nada del usuario.
    static func repartir(_ elegidas: [Categoria]) -> (apps: [String], titulos: [String]) {
        var apps: [String] = []
        var titulos: [String] = []
        for c in elegidas {
            switch c.destino {
            case .apps: apps.append(contentsOf: c.entradas)
            case .titulos: titulos.append(contentsOf: c.entradas)
            }
        }
        return (apps, titulos)
    }

    /// Une sin duplicar, conservando el orden de lo que ya había.
    ///
    /// Unión y no concatenación: aceptar dos veces la misma categoría no puede
    /// hacer crecer la lista. La comparación de duplicados ignora caja y espacios,
    /// que es como los compara el filtro.
    static func unir(_ actual: [String], con nuevas: [String]) -> [String] {
        let clave: (String) -> String = { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var vistos = Set(actual.map(clave))
        var salida = actual
        for n in nuevas {
            let limpia = n.trimmingCharacters(in: .whitespaces)
            guard !limpia.isEmpty, vistos.insert(clave(limpia)).inserted else { continue }
            salida.append(limpia)
        }
        return salida
    }

    // MARK: Calcular y escribir (spec 007, T06, RF-01)

    /// Qué quedaría en cada lista al aceptar. **No escribe nada.**
    ///
    /// Está separada de `aplicar` por un motivo concreto: `Config.set` escribe en
    /// el `config.json` de quien esté usando el equipo. Una prueba de la función
    /// que escribe modificaría la configuración real del usuario — el sitio donde
    /// se prueba una escritura nunca es el dato bueno. Así se prueba la decisión,
    /// que es lo que puede equivocarse, sin tocar nada de nadie.
    static func nuevasListas(apps actualApps: [String], titulos actualTitulos: [String],
                             elegidas: [Categoria]) -> (apps: [String], titulos: [String]) {
        let (nuevasApps, nuevosTitulos) = repartir(elegidas)
        return (unir(actualApps, con: nuevasApps), unir(actualTitulos, con: nuevosTitulos))
    }

    /// Escribe lo elegido. **El único sitio de todo el programa que toca estas
    /// listas desde el asistente**, y solo se llama desde el botón de aceptar.
    ///
    /// Que sea el único importa: es lo que sostiene el RNF-02 —abrir y cerrar la
    /// pantalla sin aceptar no cambia un byte— y hay una prueba que lo comprueba
    /// contando los sitios que escriben, no leyendo el código a ojo.
    ///
    /// Se escribe por `Config.set` y nunca tocando el archivo: `Config` mantiene
    /// la configuración en caché y la reescribe entera, así que una edición por
    /// fuera se perdería en el siguiente guardado.
    @discardableResult
    static func aplicar(_ elegidas: [Categoria]) -> (apps: Int, titulos: Int) {
        let nuevas = nuevasListas(apps: FiltroBitacora.appsExcluidas(),
                                  titulos: FiltroBitacora.titulosExcluidos(),
                                  elegidas: elegidas)
        Config.set("bitacora_excluir_apps", to: nuevas.apps)
        Config.set("bitacora_excluir_titulos", to: nuevas.titulos)
        return (nuevas.apps.count, nuevas.titulos.count)
    }

    // MARK: Lo que el usuario rechazó (spec 007, T08, RF-07)

    /// Identificadores de categoría que el usuario desmarcó en su día.
    ///
    /// Hace falta guardar el rechazo, y no solo lo aceptado: sin esto no se
    /// distingue «nunca se lo propusimos» de «dijo que no», y cada versión nueva
    /// se lo volvería a proponer marcado. Una propuesta que reaparece sola
    /// después de haberla rechazado es una forma de decidir por el usuario.
    static func rechazadas() -> Set<String> {
        Set((Config.json0("bitacora_semillas_rechazadas") as? [String]) ?? [])
    }

    static func guardarRechazadas(_ ids: Set<String>) {
        Config.set("bitacora_semillas_rechazadas", to: Array(ids).sorted())
    }

    /// Versión del catálogo que el usuario ya revisó.
    static func versionVista() -> Int { (Config.json0("bitacora_asistente_visto") as? Int) ?? 0 }

    static func guardarVersionVista(_ v: Int) { Config.set("bitacora_asistente_visto", to: v) }

    /// Qué proponer, y cuáles vienen marcadas.
    ///
    /// Se proponen todas las categorías —para que el usuario pueda cambiar de
    /// opinión sobre una que rechazó— pero **solo vienen marcadas las que no ha
    /// rechazado**. Ocultar las rechazadas sería peor: dejaría al usuario sin
    /// forma de volver atrás desde la misma pantalla.
    static func propuesta(_ c: Catalogo, rechazadas rech: Set<String>)
        -> [(categoria: Categoria, marcada: Bool)] {
        c.categorias.map { ($0, !rech.contains($0.id)) }
    }

    /// ¿Hay algo nuevo que enseñar sin que el usuario lo pida?
    ///
    /// Solo si el catálogo trae una versión posterior a la que ya revisó. Con la
    /// misma versión no se molesta a nadie, aunque haya categorías rechazadas:
    /// rechazar es una respuesta, no un pendiente.
    static func hayNovedades(_ c: Catalogo, vista: Int) -> Bool { c.version > vista }
}
