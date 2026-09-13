import Foundation

// MARK: - Modo Tarea multi-sección: una sola pestaña, varias "llamadas"
//
// El modo Tarea deja de ser solo "escribir": según lo dictado, decide qué hacer
// —como los endpoints de una Conexión API, pero local y determinista—:
//   crear · completar (tachar) · modificar · resumen (hoy / semana / pendientes)
// El texto que llega aquí ya viene SIN la frase "modo tarea" (la quitó el
// resolvedor de modos). Parser puro y testeable; sin IA para clasificar.

enum AlcanceResumen: String { case hoy, semana, pendientes }

enum ComandoTarea: Equatable {
    case crear                       // texto tal cual = nueva tarea (comportamiento actual)
    case completar(String)           // tachar la tarea que más se parezca
    case modificar(String, String)   // (busca, nuevoTexto)
    case resumen(AlcanceResumen)
}

enum TareasComando {
    private static func norm(_ s: String) -> String { PerfilAgente.normalizar(s) }

    // Verbos de cada intención (raíz al inicio del dictado).
    private static let verbosCompletar = [
        "quita", "quitar", "quítame", "completa", "completar", "complete", "completé",
        "termina", "terminar", "termine", "terminé", "marca", "marcar", "marca como hecha",
        "ya hice", "ya termine", "ya terminé", "hecho", "hice", "lista", "tacha", "tachar",
        "borra", "borrar", "elimina", "eliminar", "saca", "sacar",
    ]
    private static let verbosModificar = [
        "cambia", "cambiar", "modifica", "modificar", "edita", "editar",
        "actualiza", "actualizar", "corrige", "corregir",
    ]
    private static let verbosResumen = [
        "resumen", "resumeme", "resúmeme", "resume", "dame", "muestrame", "muéstrame",
        "que tengo", "qué tengo", "que tareas", "qué tareas", "cuales", "cuáles",
        "lista de", "listame", "lístame", "dime mis", "mis tareas", "mis pendientes",
    ]

    /// Quita el "la/una/mi tarea (de/que)" que suele venir tras el verbo, para
    /// quedarse con la descripción real de la tarea a buscar.
    private static func limpiarObjetivo(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        let prefijos = ["la tarea de ", "la tarea que ", "la tarea ", "una tarea de ",
                        "mi tarea de ", "tarea de ", "tarea ", "la de ", "el de ",
                        "de ", "que "]
        let bajo = norm(t)
        for p in prefijos where bajo.hasPrefix(p) {
            t = String(t.dropFirst(p.count)); break
        }
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
    }

    static func interpretar(_ texto: String) -> ComandoTarea {
        let bajo = norm(texto)
        guard !bajo.isEmpty else { return .crear }

        // RESUMEN: si menciona resumen/qué tengo… + alcance.
        if verbosResumen.contains(where: { bajo.hasPrefix($0) || bajo.contains(" \($0)") }) {
            if bajo.contains("semana") { return .resumen(.semana) }
            if bajo.contains("hoy") || bajo.contains("del dia") || bajo.contains("del día") {
                return .resumen(.hoy)
            }
            return .resumen(.pendientes)   // "pendientes", "todas", genérico
        }

        // MODIFICAR: "cambia la tarea X a/por Y".
        if let v = verbosModificar.first(where: { bajo.hasPrefix($0 + " ") || bajo == $0 }) {
            let resto = String(texto.dropFirst(v.count)).trimmingCharacters(in: .whitespaces)
            // separa por " a " o " por " (el último separador manda)
            let restoBajo = norm(resto)
            for sep in [" por ", " a "] {
                if let rango = restoBajo.range(of: sep, options: .backwards) {
                    let idx = restoBajo.distance(from: restoBajo.startIndex, to: rango.lowerBound)
                    let busca = String(resto.prefix(idx))
                    let nuevo = String(resto.dropFirst(idx + sep.count))
                    let b = limpiarObjetivo(busca)
                    if !b.isEmpty, !nuevo.trimmingCharacters(in: .whitespaces).isEmpty {
                        return .modificar(b, nuevo.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
            // sin separador claro: cae a crear (no adivinar un reemplazo)
            return .crear
        }

        // COMPLETAR / tachar / eliminar.
        if let v = verbosCompletar.first(where: { bajo.hasPrefix($0 + " ") || bajo == $0 }) {
            let resto = String(texto.dropFirst(v.count)).trimmingCharacters(in: .whitespaces)
            let objetivo = limpiarObjetivo(resto)
            if !objetivo.isEmpty { return .completar(objetivo) }
            return .crear
        }

        return .crear
    }
}
