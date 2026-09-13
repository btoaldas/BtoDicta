import Foundation

// MARK: - Bitácora continua: biblioteca de prompts
//
// Un mismo día da para muchas cosas distintas: resumirlo, limpiarlo sin
// resumir, sacar las ideas principales, generar una lluvia de ideas… Cada una
// es un prompt guardado, editable, y siempre recuperable a su texto original.
//
// Se guardan en `~/.btodicta/continuo-prompts.json`. Solo se escriben ahí los
// que el usuario TOCÓ: los de fábrica viven en el código, así que al actualizar
// la app llegan mejoras sin pisar lo que cada quien haya personalizado.

struct PromptContinuo: Identifiable, Codable, Equatable {
    var id: String
    var nombre: String
    var descripcion: String
    var texto: String

    /// `true` si difiere del de fábrica (y por tanto se puede restaurar).
    var modificado: Bool {
        guard let base = ContinuoPrompts.deFabrica.first(where: { $0.id == id }) else { return true }
        return base.texto != texto || base.nombre != nombre
    }
}

enum ContinuoPrompts {

    private static var archivo: URL {
        Config.dir.appendingPathComponent("continuo-prompts.json")
    }

    // MARK: Catálogo de fábrica

    static let deFabrica: [PromptContinuo] = [
        PromptContinuo(
            id: "resumen_diario",
            nombre: "Resumen del día",
            descripcion: "Relato de la jornada: en qué se trabajó, qué se decidió, qué quedó pendiente.",
            texto: """
            Eres el cronista de la jornada de trabajo. Con el material de abajo,
            redacta en español y en Markdown:

            ## Resumen
            Dos o tres frases sobre en qué se fue el día.

            ## En qué se trabajó
            Los temas o proyectos reales, con lo avanzado en cada uno.

            ## Decisiones
            Qué se decidió y por qué, si se decidió algo.

            ## Pendientes
            Lo que quedó a medias o se nombró como siguiente paso.

            No inventes nada que no esté en el material. Si algo no se puede
            determinar, omítelo en vez de rellenar.
            """),

        PromptContinuo(
            id: "transcripcion_limpia",
            nombre: "Transcribir y normalizar (sin resumir)",
            descripcion: "Deja el texto legible y ordenado, conservando TODO. No resume.",
            texto: """
            Limpia y normaliza la transcripción de abajo SIN RESUMIR y SIN
            OMITIR nada de lo dicho.

            - Conserva las marcas de tiempo tal como vienen.
            - Corrige puntuación, mayúsculas y errores evidentes de
              reconocimiento de voz.
            - Quita muletillas y repeticiones de tartamudeo, pero no ideas.
            - Respeta las anotaciones entre paréntesis sobre lo que se veía en
              pantalla; déjalas donde están.
            - Si una palabra es claramente un error de transcripción y el
              contexto permite deducirla, corrígela y marca la duda con [?].

            Devuelve solo el texto limpio, en Markdown.
            """),

        PromptContinuo(
            id: "ideas_principales",
            nombre: "Ideas principales",
            descripcion: "Extrae las ideas de fondo, sin el ruido de la conversación.",
            texto: """
            Extrae del material de abajo las ideas principales, en español y en
            Markdown. Una lista de puntos, cada uno con una idea completa y
            autónoma: quien lo lea sin haber estado ahí debe entenderla.

            Ordena de más a menos importante. Descarta lo accesorio, el ruido y
            lo que sea solo mecánica de trabajo. No inventes.
            """),

        PromptContinuo(
            id: "lluvia_ideas",
            nombre: "Lluvia de ideas",
            descripcion: "Toma lo hablado como semilla y propone caminos nuevos.",
            texto: """
            A partir de lo hablado abajo, genera una lluvia de ideas en español
            y en Markdown.

            Primero, en dos líneas: qué se estaba intentando resolver.
            Después, entre diez y quince propuestas, cada una con una frase de
            por qué podría funcionar.

            Mezcla lo conservador y lo arriesgado. Marca con ⚡ las tres que te
            parezcan más prometedoras y di en una línea por qué.
            """),

        PromptContinuo(
            id: "tareas",
            nombre: "Tareas y compromisos",
            descripcion: "Solo lo accionable: qué hay que hacer, quién y para cuándo.",
            texto: """
            Saca del material de abajo únicamente lo ACCIONABLE, en español y en
            Markdown, como lista de casillas:

            - [ ] Tarea, con responsable si se nombra y fecha si se menciona.

            Incluye compromisos adquiridos aunque no se hayan llamado tareas.
            Separa en «Mías» y «De otros» si se distingue. Si no hay nada
            accionable, dilo en una línea y no rellenes.
            """),

        PromptContinuo(
            id: "decisiones",
            nombre: "Decisiones y su porqué",
            descripcion: "Qué se decidió, qué se descartó y con qué razón.",
            texto: """
            Registra las decisiones tomadas en el material de abajo, en español
            y en Markdown. Por cada una:

            **Decisión** — qué se decidió.
            **Porqué** — la razón que se dio.
            **Alternativa descartada** — qué se consideró y no se eligió, si consta.

            Si una decisión quedó abierta, ponla aparte bajo «Sin cerrar». No
            inventes razones que no se dijeron.
            """),

        PromptContinuo(
            id: "informe",
            nombre: "Informe formal",
            descripcion: "Redacción para enviar a un tercero, en tono neutro.",
            texto: """
            Redacta un informe en español a partir del material de abajo, en
            tono profesional y neutro, apto para enviar a un tercero que no
            estuvo presente.

            Estructura: antecedente, desarrollo, resultado y siguientes pasos.
            Sin coloquialismos, sin marcas de tiempo, sin nombres de personas
            salvo que sean imprescindibles. No inventes datos.
            """),

        PromptContinuo(
            id: "preguntas",
            nombre: "Preguntas abiertas",
            descripcion: "Qué quedó sin responder y convendría aclarar.",
            texto: """
            Del material de abajo, extrae las preguntas que quedaron sin
            responder, los supuestos sin verificar y los puntos donde hubo duda
            o desacuerdo. En español y en Markdown, como lista.

            Por cada punto, una línea de por qué conviene resolverlo. Ordena por
            urgencia aparente. Si todo quedó cerrado, dilo y ya.
            """),

        PromptContinuo(
            id: "aprendizajes",
            nombre: "Aprendizajes",
            descripcion: "Qué se aprendió y qué conviene no repetir.",
            texto: """
            Del material de abajo, saca los aprendizajes: qué se descubrió, qué
            salió mal y por qué, y qué conviene hacer distinto la próxima vez.
            En español y en Markdown.

            Separa en «Qué funcionó», «Qué falló» y «Qué haría distinto». Sé
            concreto: nombra la causa, no el síntoma. No moralices.
            """),

        PromptContinuo(
            id: "cronologia",
            nombre: "Cronología",
            descripcion: "Qué pasó y en qué orden, con horas.",
            texto: """
            Reconstruye la cronología del material de abajo, en español y en
            Markdown, como lista con la hora al principio de cada línea.

            Agrupa en bloques cuando varias entradas seguidas sean del mismo
            asunto, e indica el rango horario del bloque. Sé escueto: una línea
            por hecho. No interpretes ni valores.
            """),
    ]

    // MARK: Acceso

    /// Todos los prompts: los de fábrica, con las ediciones aplicadas encima.
    static func todos() -> [PromptContinuo] {
        let editados = cargarEditados()
        var salida = deFabrica.map { base in
            editados.first(where: { $0.id == base.id }) ?? base
        }
        // Los que el usuario creó de cero y no existen de fábrica.
        for e in editados where !deFabrica.contains(where: { $0.id == e.id }) {
            salida.append(e)
        }
        return salida
    }

    static func porId(_ id: String) -> PromptContinuo? {
        todos().first { $0.id == id }
    }

    /// El elegido para ejecutar; si el guardado ya no existe, el primero.
    static func activo() -> PromptContinuo {
        porId(Config.continuoPromptActivo()) ?? todos()[0]
    }

    // MARK: Edición

    static func guardar(_ p: PromptContinuo) {
        var editados = cargarEditados().filter { $0.id != p.id }
        // Si vuelve a coincidir con el de fábrica, se deja de guardar: así
        // hereda futuras mejoras del catálogo.
        if let base = deFabrica.first(where: { $0.id == p.id }),
           base.texto == p.texto, base.nombre == p.nombre {
            escribir(editados)
            return
        }
        editados.append(p)
        escribir(editados)
    }

    /// Devuelve un prompt a su texto original. Devuelve nil si era propio del
    /// usuario y no tiene original al que volver.
    @discardableResult
    static func restaurar(id: String) -> PromptContinuo? {
        guard let base = deFabrica.first(where: { $0.id == id }) else { return nil }
        escribir(cargarEditados().filter { $0.id != id })
        return base
    }

    static func restaurarTodos() {
        escribir([])
    }

    static func borrar(id: String) {
        guard !deFabrica.contains(where: { $0.id == id }) else { return }
        escribir(cargarEditados().filter { $0.id != id })
    }

    // MARK: Persistencia

    private static func cargarEditados() -> [PromptContinuo] {
        guard let data = try? Data(contentsOf: archivo),
              let lista = try? JSONDecoder().decode([PromptContinuo].self, from: data) else { return [] }
        return lista
    }

    private static func escribir(_ lista: [PromptContinuo]) {
        let cod = JSONEncoder()
        cod.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? cod.encode(lista) else { return }
        try? data.write(to: archivo, options: .atomic)
    }
}
