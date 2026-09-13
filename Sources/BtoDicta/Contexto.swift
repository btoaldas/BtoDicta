import Foundation

// MARK: - Contexto BAJO DEMANDA para el Agente (no meter todo siempre)
//
// Problema: si a cada capacidad le metemos su contexto FIJO en el prompt
// (hora, tareas, web, archivos…), el prompt crece sin control → mucha RAM, muchos
// tokens (caro/lento) y el modelo se pierde. Solución: cada capacidad es una FUENTE
// de contexto con sus disparadores; solo se INYECTA la que toca el tema del pedido.
//
// v1 = por palabras clave (barato, determinista, sin IA). v2 = embeddings/vectores:
// misma estructura, pero el match query↔fuente se hará por similitud semántica
// (reutilizando EmbeddingSearch), para entender el tema aunque no use la palabra exacta.

enum Contexto {
    struct Fuente {
        let nombre: String
        let disparadores: [String]     // palabras que activan esta fuente (v1)
        let generar: () -> String      // el texto de contexto (se calcula solo si aplica)
    }

    static let fuentes: [Fuente] = [
        Fuente(nombre: "fecha-hora",
               disparadores: ["hora", "fecha", "dia", "día", "hoy", "mañana", "manana", "ayer",
                              "ahora", "tiempo", "semana", "mes", "año", "ano", "minuto", "temprano", "tarde"],
               generar: {
                   let f = DateFormatter()
                   f.locale = Locale(identifier: "es_EC"); f.timeZone = .current
                   f.dateFormat = "EEEE d 'de' MMMM 'de' yyyy, h:mm a"
                   return "AHORA MISMO (fecha y hora local, úsala tal cual, NO inventes): \(f.string(from: Date()))."
               }),
        Fuente(nombre: "tareas-notas",
               disparadores: ["tarea", "tareas", "nota", "notas", "pendiente", "pendientes", "apunt",
                              "recuerda", "recuérda", "recordar", "lista", "agenda", "quehacer", "que tengo", "qué tengo", "que debo"],
               generar: {
                   let t = NotasStore.tareas().filter { !$0.hecho }.prefix(30).map { "- \($0.texto)" }.joined(separator: "\n")
                   let n = NotasStore.notas().prefix(30).map { "- \($0.texto)" }.joined(separator: "\n")
                   return "TAREAS pendientes:\n\(t.isEmpty ? "(ninguna)" : t)\nNOTAS guardadas:\n\(n.isEmpty ? "(ninguna)" : n)"
               }),
    ]

    /// Devuelve SOLO el contexto de las fuentes cuyo tema aparece en el pedido.
    /// Vacío si el pedido no toca ninguna (prompt mínimo → rápido y barato).
    static func paraPedido(_ texto: String) -> String {
        let t = normalizar(texto)
        var bloques: [String] = []
        for f in fuentes where f.disparadores.contains(where: { t.contains(normalizar($0)) }) {
            let c = f.generar()
            if !c.isEmpty { bloques.append(c) }
        }
        return bloques.joined(separator: "\n")
    }

    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
