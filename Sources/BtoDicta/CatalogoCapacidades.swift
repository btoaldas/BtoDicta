import Foundation

// MARK: - Catálogo de capacidades (Fase 1 del sistema agéntico)
//
// El "mapa" de TODO lo que BtoDicta puede hacer, para que la IA global sepa
// dónde cae una orden. Regla dura: NO es una lista guardada — se ENUMERA en
// vivo desde las fuentes reales (modos, rutinas, atajos, herramientas). Si
// mañana el usuario crea un modo/submodo por UI, o el código agrega una acción,
// aparece SOLO en la próxima lectura. Autoactualizable por construcción.
//
// Fase 1 solo LEE y describe; no cambia el ruteo ni la ejecución (eso es fase 3).

struct Capacidad: Equatable {
    var tipo: String            // "modo" | "conexion" | "rutina" | "atajo" | "herramienta" | "cerebro"
    var clave: String           // id estable para referenciar (modo.id, rutina.id, nombre de atajo…)
    var nombre: String
    var descripcion: String     // una línea: qué hace
    var frases: [String]        // cómo se pide por voz
    var riesgo: RiesgoAgente
    var fuente: String          // de dónde salió (diagnóstico)
    var hijos: [Capacidad]      // submodos (fase 5); hoy [] salvo endpoints informativos
}

enum CatalogoCapacidades {

    /// NÚCLEO PURO: arma el catálogo desde fuentes dadas. Testeable sin disco;
    /// la versión en vivo le pasa los stores reales. Añadir un modo/rutina a las
    /// fuentes se refleja aquí — no hay lista fija que mantener.
    static func ensamblar(modos: [Modo],
                          rutinas: [RutinaAgente],
                          atajos: [AtajoAppleDescubierto],
                          herramientas: Bool = true) -> [Capacidad] {
        var caps: [Capacidad] = []

        // 1. MODOS (los del usuario + base). Un modo con acción "conexion" es una
        //    capacidad de tipo conexión (con sus endpoints como hijos informativos).
        for m in modos where m.id != "dictado" {
            let frases = ModosStore.frasesVoz(m)
            if m.accion == "conexion", let cx = m.conexion {
                let endpoints = cx.endpoints.map { ep in
                    Capacidad(tipo: "endpoint", clave: ep.clave, nombre: ep.clave,
                              descripcion: ep.descripcion.isEmpty ? "\(ep.metodo)" : ep.descripcion,
                              frases: [], riesgo: ep.efectivamenteEscritura ? .externo : .reversible,
                              fuente: "conexion:\(m.id)", hijos: [])
                }
                caps.append(Capacidad(tipo: "conexion", clave: m.id, nombre: m.nombre,
                    descripcion: descripcionModo(m), frases: frases,
                    riesgo: ConexionesMotor.riesgo(cx), fuente: "modo", hijos: endpoints))
            } else {
                caps.append(Capacidad(tipo: "modo", clave: m.id, nombre: m.nombre,
                    descripcion: descripcionModo(m), frases: frases,
                    riesgo: riesgoModo(m), fuente: "modo", hijos: []))
            }
        }

        // 2. RUTINAS del agente (activas, con pasos).
        for r in rutinas where r.activa && !r.pasos.isEmpty {
            caps.append(Capacidad(tipo: "rutina", clave: r.id, nombre: r.nombre,
                descripcion: r.descripcion.isEmpty ? "rutina de \(r.pasos.count) paso(s)" : r.descripcion,
                frases: r.frases, riesgo: RutinasAgenteStore.riesgo(r), fuente: "rutina", hijos: []))
        }

        // 3. ATAJOS de Apple habilitados por el usuario.
        for a in atajos where a.habilitado && a.disponible {
            caps.append(Capacidad(tipo: "atajo", clave: a.nombre, nombre: a.nombre,
                descripcion: "Atajo de Apple / Siri", frases: [],
                riesgo: .externo, fuente: "atajo", hijos: []))
        }

        // 4. HERRAMIENTAS específicas del agente (deterministas, siempre presentes
        //    si su interruptor está encendido). Autoactualiza según Config.
        if herramientas {
            func tool(_ tipo: String, _ nombre: String, _ desc: String,
                      _ riesgo: RiesgoAgente, _ activo: Bool) {
                if activo { caps.append(Capacidad(tipo: "herramienta", clave: tipo,
                    nombre: nombre, descripcion: desc, frases: [], riesgo: riesgo,
                    fuente: "herramienta", hijos: [])) }
            }
            tool("clima", "Clima", "consulta el clima y pronóstico", .lectura, Config.agenteHerramientaClima())
            tool("volumen", "Volumen", "controla el volumen del Mac", .reversible, Config.agenteHerramientaVolumen())
            tool("capturas", "Capturas", "captura o graba la pantalla", .cambioLocal, Config.agenteHerramientaCapturas())
            tool("musica", "Música", "reproduce o busca música", .reversible, Config.agenteHerramientaMusica())
            tool("archivos", "Archivos", "busca y abre archivos", .reversible, Config.agenteHerramientaArchivos())
            tool("recordatorios", "Recordatorios", "crea recordatorios", .cambioLocal, Config.agenteHerramientaRecordatorios())
            tool("calendario", "Calendario", "crea eventos", .cambioLocal, Config.agenteHerramientaCalendario())
            tool("tareas_locales", "Tareas locales", "crea, tacha y resume tareas", .cambioLocal, true)
        }

        // 5. CEREBRO (respaldo conversacional). Siempre existe como última opción.
        caps.append(Capacidad(tipo: "cerebro", clave: "cerebro", nombre: "Conversar",
            descripcion: "responder o conversar cuando ninguna capacidad concreta aplica",
            frases: [], riesgo: .lectura, fuente: "cerebro", hijos: []))

        return caps
    }

    /// Versión EN VIVO: lee los stores reales. Cada llamada refleja el estado
    /// actual — modos/rutinas/atajos nuevos aparecen sin tocar este código.
    static func todas() -> [Capacidad] {
        ensamblar(modos: ModosStore.todos(),
                  rutinas: RutinasAgenteStore.todas(),
                  atajos: AppleAtajosCatalogo.todos())
    }

    /// Menú compacto para el prompt de la IA (catálogo CERRADO — la IA elige de
    /// aquí y nada más, patrón ModoIAEnrutador). Fase 3 lo consumirá.
    static func paraIA(_ caps: [Capacidad]) -> String {
        caps.map { c in
            var linea = "- [\(c.tipo):\(c.clave)] \(c.nombre): \(c.descripcion)"
            if !c.frases.isEmpty { linea += " (se pide: \(c.frases.prefix(3).joined(separator: " / ")))" }
            return linea
        }.joined(separator: "\n")
    }

    // MARK: descripciones/riesgo por modo (reusa la semántica existente)

    private static func descripcionModo(_ m: Modo) -> String {
        if !m.prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(m.prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }
        switch m.base {
        case "traducir": return "traduce el dictado a \(m.idiomaDestino)"
        case "buscar": return "busca en \(Buscadores.nombre(m.buscador))"
        case "musica": return "reproduce o busca música"
        case "aplicacion": return "abre una aplicación y coloca el texto"
        case "agente": return "asistente conversacional"
        case "accion": return "acción: \(Acciones.nombre(m.accion))"
        default: return m.almacen == "tarea" ? "crea/gestiona tareas"
            : (m.almacen == "nota" ? "crea notas" : "da forma al dictado")
        }
    }

    private static func riesgoModo(_ m: Modo) -> RiesgoAgente {
        switch m.base {
        case "musica", "aplicacion", "buscar": return .reversible
        case "accion":
            switch m.accion {
            case "clima": return .lectura
            case "gmail", "correo", "outlook", "whatsapp", "mensajes", "url": return .externo
            case "recordatorios", "calendario", "notas", "nota_local", "tarea_local": return .cambioLocal
            default: return .reversible
            }
        default: return m.almacen.isEmpty ? .lectura : .cambioLocal
        }
    }
}
