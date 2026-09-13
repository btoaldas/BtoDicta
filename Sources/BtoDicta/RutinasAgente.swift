import AppKit
import Foundation

struct PasoRutinaAgente: Codable, Identifiable, Equatable {
    var id: String
    var tipo: String       // musica|app|url|atajo|tarea|nota|recordatorio|calendario|archivo|captura|grabacion|...
    var valor: String      // admite {texto}
    /// Un paso opcional no invalida toda la receta si, por ejemplo, Teams no
    /// está instalado o el usuario aún no habilitó su Atajo de Concentración.
    var opcional: Bool

    init(tipo: String = "musica", valor: String = "{texto}", opcional: Bool = false) {
        id = UUID().uuidString; self.tipo = tipo; self.valor = valor
        self.opcional = opcional
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tipo = (try? c.decode(String.self, forKey: .tipo)) ?? "musica"
        valor = (try? c.decode(String.self, forKey: .valor)) ?? "{texto}"
        opcional = (try? c.decode(Bool.self, forKey: .opcional)) ?? false
    }
}

struct RutinaAgente: Codable, Identifiable, Equatable {
    var id: String
    var nombre: String
    var frases: [String]
    var activa: Bool
    var pasos: [PasoRutinaAgente]
    var categoria: String
    var descripcion: String
    var version: Int
    var incluida: Bool
    /// Algunas frases deben ganar antes que el parser general. Ejemplo:
    /// “resume la selección” no debe resumir las palabras “la selección”.
    var prioritaria: Bool
    /// La respuesta consolidada debe mostrarse/hablarse, no solo un acuse.
    var devuelveResultado: Bool

    init(nombre: String = "Mi rutina") {
        id = UUID().uuidString; self.nombre = nombre
        frases = ["rutina \(nombre.lowercased())"]; activa = true; pasos = []
        categoria = "Personal"; descripcion = ""; version = 1; incluida = false
        prioritaria = false; devuelveResultado = false
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        nombre = (try? c.decode(String.self, forKey: .nombre)) ?? "Rutina"
        frases = (try? c.decode([String].self, forKey: .frases)) ?? []
        activa = (try? c.decode(Bool.self, forKey: .activa)) ?? true
        pasos = (try? c.decode([PasoRutinaAgente].self, forKey: .pasos)) ?? []
        categoria = (try? c.decode(String.self, forKey: .categoria)) ?? "Personal"
        descripcion = (try? c.decode(String.self, forKey: .descripcion)) ?? ""
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        incluida = (try? c.decode(Bool.self, forKey: .incluida)) ?? false
        prioritaria = (try? c.decode(Bool.self, forKey: .prioritaria)) ?? false
        devuelveResultado = (try? c.decode(Bool.self, forKey: .devuelveResultado)) ?? false
    }
}

struct DeteccionRutinaAgente {
    let rutina: RutinaAgente
    let contenido: String
}

enum RutinasAgenteStore {
    private static var url: URL { Config.dir.appendingPathComponent("agente_rutinas.json") }
    private static let lock = NSLock()

    private static func leerGuardadasSinLock() -> [RutinaAgente] {
        guard let d = try? Data(contentsOf: url),
              let r = try? JSONDecoder().decode([RutinaAgente].self, from: d) else { return [] }
        return r
    }

    /// Recetas de producto. Son acciones de BtoDicta, no automatizaciones
    /// instaladas a escondidas en la biblioteca de Atajos de macOS. Las etapas
    /// “atajo” se ejecutan únicamente si la persona habilitó ese Atajo concreto.
    static func incluidas() -> [RutinaAgente] {
        func receta(_ id: String, _ nombre: String, _ categoria: String,
                    _ descripcion: String, frases: [String],
                    pasos: [PasoRutinaAgente], prioritaria: Bool = false,
                    devuelve: Bool = false) -> RutinaAgente {
            var r = RutinaAgente(nombre: nombre)
            r.id = id; r.categoria = categoria; r.descripcion = descripcion
            r.frases = frases; r.pasos = pasos; r.incluida = true
            r.prioritaria = prioritaria; r.devuelveResultado = devuelve
            return r
        }
        return [
            receta("beto-resumen-dia", "Resumen del día", "Trabajo",
                   "Calendario, recordatorios y tareas locales en una sola respuesta.",
                   frases: ["resumen del dia", "que tengo para hoy", "dime mi agenda de hoy"],
                   pasos: [.init(tipo: "resumen_dia", valor: "")], devuelve: true),
            receta("beto-empezar-jornada", "Empezar jornada", "Trabajo",
                   "Abre las herramientas de trabajo, música y Concentración cuando esté autorizado.",
                   frases: ["empezar jornada", "iniciar jornada", "comenzar el trabajo"],
                   pasos: [
                    .init(tipo: "app", valor: "Outlook", opcional: true),
                    .init(tipo: "app", valor: "Word", opcional: true),
                    .init(tipo: "app", valor: "Calendario", opcional: true),
                    .init(tipo: "musica", valor: "música para trabajar", opcional: true),
                    .init(tipo: "atajo", valor: "BtoDicta · Enfoque trabajo", opcional: true),
                   ]),
            receta("beto-cerrar-jornada", "Cerrar jornada", "Trabajo",
                   "Resume pendientes y guarda una nota de cierre. No cierra aplicaciones por defecto.",
                   frases: ["cerrar jornada", "terminar jornada", "fin de jornada"],
                   pasos: [.init(tipo: "resumen_dia", valor: ""),
                           .init(tipo: "nota", valor: "Cierre {fecha}: {resultado}"),
                           .init(tipo: "resumen_manana", valor: "")],
                   devuelve: true),
            receta("beto-modo-reunion", "Modo reunión", "Trabajo",
                   "Activa el Atajo de reunión, abre Teams o Zoom y crea una nota fechada.",
                   frases: ["modo reunion", "empezar reunion", "preparar reunion"],
                   pasos: [.init(tipo: "atajo", valor: "BtoDicta · Modo reunión", opcional: true),
                           .init(tipo: "app_primera", valor: "Teams|Zoom", opcional: true),
                           .init(tipo: "nota", valor: "Reunión {fecha}: {texto}")]),
            receta("beto-seleccion-resumir", "Resumir selección", "Trabajo",
                   "Resume el texto seleccionado y deja el resultado en el portapapeles.",
                   frases: ["resume la seleccion", "resumir seleccion", "resume este texto seleccionado"],
                   pasos: [.init(tipo: "seleccion_resumir", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-seleccion-traducir", "Traducir selección", "Trabajo",
                   "Traduce el texto seleccionado con el modo Traducir configurado.",
                   frases: ["traduce la seleccion", "traducir seleccion", "traduce este texto seleccionado"],
                   pasos: [.init(tipo: "seleccion_traducir", valor: "{texto}")],
                   prioritaria: true, devuelve: true),
            receta("beto-seleccion-responder", "Responder selección", "Trabajo",
                   "Redacta una respuesta al texto seleccionado.",
                   frases: ["responde la seleccion", "responder seleccion", "responde a este texto seleccionado"],
                   pasos: [.init(tipo: "seleccion_responder", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-seleccion-tarea", "Selección a tarea", "Trabajo",
                   "Convierte el texto seleccionado en una tarea local.",
                   frases: ["convierte la seleccion en tarea", "seleccion a tarea", "crea una tarea con la seleccion"],
                   pasos: [.init(tipo: "seleccion_tarea", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-leer-seleccion", "Leer selección", "Trabajo",
                   "Lee el texto seleccionado con la cascada TTS elegida.",
                   frases: ["lee la seleccion", "leer seleccion", "leeme el texto seleccionado"],
                   pasos: [.init(tipo: "seleccion_leer", valor: "")],
                   prioritaria: true, devuelve: false),
            receta("beto-seleccion-nota-apple", "Selección a Nota de Apple", "Trabajo",
                   "Crea y verifica una nota real con el texto seleccionado.",
                   frases: ["guarda la seleccion en notas de apple",
                            "crea una nota de apple con la seleccion",
                            "seleccion a notas de apple"],
                   pasos: [.init(tipo: "seleccion_nota_apple", valor: "")],
                   prioritaria: true, devuelve: false),
            receta("beto-estado-mac", "Estado del Mac", "Casa",
                   "Batería, disco, CPU, memoria, red y VPN, todo en local.",
                   frases: ["como esta la computadora", "estado del mac", "diagnostico del mac"],
                   pasos: [.init(tipo: "estado_mac", valor: "")], devuelve: true),
            receta("beto-captura-inteligente", "Captura inteligente", "Trabajo",
                   "Captura con nombre automático; puede copiar, abrir o preparar para compartir sin enviar.",
                   frases: ["captura inteligente", "haz una captura inteligente"],
                   pasos: [.init(tipo: "captura_inteligente", valor: "{texto}")], devuelve: true),
            receta("beto-audio-transcribir", "Transcribir audio seleccionado", "Trabajo",
                   "Transcribe el archivo de audio seleccionado en Finder.",
                   frases: ["transcribe el audio seleccionado", "transcribir audio seleccionado"],
                   pasos: [.init(tipo: "audio_transcribir", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-audio-resumir", "Resumir audio seleccionado", "Universidad",
                   "Transcribe y resume el audio seleccionado en Finder.",
                   frases: ["resume el audio seleccionado", "resumir audio seleccionado"],
                   pasos: [.init(tipo: "audio_resumir", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-audio-traducir", "Traducir audio seleccionado", "Universidad",
                   "Transcribe y traduce el audio seleccionado en Finder.",
                   frases: ["traduce el audio seleccionado", "traducir audio seleccionado"],
                   pasos: [.init(tipo: "audio_traducir", valor: "{texto}")],
                   prioritaria: true, devuelve: true),
            receta("beto-audio-correo", "Audio seleccionado a correo", "Trabajo",
                   "Transcribe el audio seleccionado y lo convierte en correo.",
                   frases: ["convierte el audio seleccionado en correo", "audio seleccionado a correo"],
                   pasos: [.init(tipo: "audio_correo", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-audio-oficio", "Audio seleccionado a oficio", "Universidad",
                   "Transcribe el audio seleccionado y lo convierte en oficio.",
                   frases: ["convierte el audio seleccionado en oficio", "audio seleccionado a oficio"],
                   pasos: [.init(tipo: "audio_oficio", valor: "")],
                   prioritaria: true, devuelve: true),
            receta("beto-modo-oficina", "Escena: modo oficina", "Casa",
                   "Ejecuta únicamente el Atajo HomeKit que habilites.",
                   frases: ["modo oficina", "activa modo oficina"],
                   pasos: [.init(tipo: "atajo", valor: "BtoDicta · Modo oficina")]),
            receta("beto-modo-noche", "Escena: modo noche", "Casa",
                   "Ejecuta únicamente el Atajo HomeKit que habilites.",
                   frases: ["modo noche", "activa modo noche"],
                   pasos: [.init(tipo: "atajo", valor: "BtoDicta · Modo noche")]),
            receta("beto-apagar-luces", "Escena: apagar luces", "Casa",
                   "Usa un Atajo HomeKit habilitado; nunca controla la casa por una API oculta.",
                   frases: ["apaga las luces", "apagar las luces"],
                   pasos: [.init(tipo: "atajo", valor: "Oye Siri apaga las luces")]),
        ]
    }

    private static func fusionar(_ guardadas: [RutinaAgente]) -> [RutinaAgente] {
        var salida = guardadas
        let ids = Set(guardadas.map(\.id))
        salida.append(contentsOf: incluidas().filter { !ids.contains($0.id) })
        return salida
    }

    static func todas() -> [RutinaAgente] {
        lock.lock(); defer { lock.unlock() }; return fusionar(leerGuardadasSinLock())
    }

    static func guardar(_ rutinas: [RutinaAgente]) {
        lock.lock(); defer { lock.unlock() }
        Config.asegurarDirSeguro()
        if let d = try? JSONEncoder().encode(rutinas) {
            try? d.write(to: url, options: .atomic); Config.protegerSecreto(url)
        }
    }

    static func detectar(_ texto: String) -> DeteccionRutinaAgente? {
        detectar(texto, en: todas())
    }

    static func detectarPrioritaria(_ texto: String) -> DeteccionRutinaAgente? {
        detectar(texto, en: todas().filter(\.prioritaria))
    }

    /// Órdenes deliberadamente cortas para actuar sobre la selección actual.
    /// Solo coinciden si TODO el pedido es la frase breve; así “resume el
    /// informe de mañana” conserva el modo normal y no intenta leer el
    /// portapapeles.
    static func detectarSeleccionBreve(_ texto: String) -> DeteccionRutinaAgente? {
        let n = PerfilAgente.normalizar(texto)
        let ids: [String: String] = [
            "resume": "beto-seleccion-resumir", "resumir": "beto-seleccion-resumir",
            "traduce": "beto-seleccion-traducir", "traducir": "beto-seleccion-traducir",
            "responde": "beto-seleccion-responder", "responder": "beto-seleccion-responder",
            "convierte en tarea": "beto-seleccion-tarea",
            "convertir en tarea": "beto-seleccion-tarea",
            "lee": "beto-leer-seleccion", "leer": "beto-leer-seleccion",
        ]
        guard let id = ids[n],
              let r = todas().first(where: { $0.id == id && $0.activa && !$0.pasos.isEmpty })
        else { return nil }
        return .init(rutina: r, contenido: "")
    }

    static func detectar(_ texto: String, en lista: [RutinaAgente]) -> DeteccionRutinaAgente? {
        let originales = texto.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let normal = originales.map(PerfilAgente.normalizar)
        let rutinas = lista.filter { $0.activa && !$0.pasos.isEmpty }
        var candidatos: [(RutinaAgente, Int)] = []
        for r in rutinas {
            var frases = r.frases
            frases.append("rutina \(r.nombre)")
            for f in frases {
                let ft = PerfilAgente.normalizar(f).split(separator: " ").map(String.init)
                guard !ft.isEmpty, ft.count <= normal.count,
                      Array(normal.prefix(ft.count)) == ft else { continue }
                candidatos.append((r, ft.count))
            }
        }
        guard let mejor = candidatos.max(by: { $0.1 < $1.1 }) else { return nil }
        let contenido = originales.dropFirst(mejor.1).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?¡¿—-"))
        return DeteccionRutinaAgente(rutina: mejor.0, contenido: contenido)
    }

    static func riesgo(id: String) -> RiesgoAgente {
        guard let r = todas().first(where: { $0.id == id }) else { return .externo }
        return riesgo(r)
    }

    static func riesgo(_ r: RutinaAgente) -> RiesgoAgente {
        var maximo: RiesgoAgente = .lectura
        for p in r.pasos {
            let x: RiesgoAgente
            switch p.tipo {
            case "resumen_dia", "resumen_manana", "estado_mac", "seleccion_leer": x = .lectura
            case "musica", "app", "app_primera", "url", "archivo",
                 "seleccion_resumir", "seleccion_traducir", "seleccion_responder",
                 "audio_transcribir", "audio_resumir", "audio_traducir",
                 "audio_correo", "audio_oficio": x = .reversible
            case "tarea", "nota", "nota_apple", "recordatorio", "calendario", "captura", "grabacion",
                 "captura_inteligente", "seleccion_tarea", "seleccion_nota_apple": x = .cambioLocal
            case "atajo": x = AppleAtajosCatalogo.riesgo(nombre: p.valor)
            case "conexion":
                // El riesgo real es el de la conexión del modo referenciado:
                // solo lectura = reversible; con escritura (o modo ausente) = externo.
                x = ConexionesMotor.riesgo(ModosStore.todos()
                    .first { $0.id == p.valor && $0.accion == "conexion" }?.conexion)
            case "cerrar_apps": x = .destructivo
            default: x = .externo
            }
            if x > maximo { maximo = x }
        }
        return maximo
    }

    static func devuelveResultado(id: String) -> Bool {
        todas().first(where: { $0.id == id })?.devuelveResultado ?? false
    }
}

enum RutinasAgenteRunner {
    private static func interpolar(_ plantilla: String, texto: String,
                                   resultado: String) -> String {
        let p = plantilla.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p == "{texto}" { return texto }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return p.replacingOccurrences(of: "{texto}", with: texto)
            .replacingOccurrences(of: "{resultado}", with: resultado)
            .replacingOccurrences(of: "{fecha}", with: f.string(from: Date()))
    }

    private static func abrirApp(_ nombre: String, simular: Bool) -> ResultadoHerramientaApple {
        let toks = PerfilAgente.normalizar(nombre).split(separator: " ").map(String.init)
        guard case .encontrada(let m) = AplicacionesMac.resolverPrefijo(toks) else {
            return .init(ok: false, mensaje: "No encontré la aplicación «\(nombre)».")
        }
        if !simular {
            NSWorkspace.shared.openApplication(at: m.app.url, configuration: .init(), completionHandler: nil)
        }
        return .init(ok: true, mensaje: "Abrí \(m.app.nombre).")
    }

    private static func abrirURL(_ raw: String, texto: String, resultado: String,
                                 simular: Bool) -> ResultadoHerramientaApple {
        var c = CharacterSet.urlQueryAllowed; c.remove(charactersIn: "&=+#")
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: c) ?? s
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let s = raw.replacingOccurrences(of: "{texto}", with: enc(texto))
            .replacingOccurrences(of: "{resultado}", with: enc(resultado))
            .replacingOccurrences(of: "{fecha}", with: enc(f.string(from: Date())))
        guard let u = URL(string: s), let esquema = u.scheme?.lowercased(),
              let host = u.host?.lowercased(),
              esquema == "https" || (esquema == "http"
                && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            return .init(ok: false, mensaje: "La URL de la rutina no es válida.")
        }
        if !simular, !NSWorkspace.shared.open(u) {
            return .init(ok: false, mensaje: "No pude abrir \(u.host ?? "la URL").")
        }
        return .init(ok: true, mensaje: "Abrí \(u.host ?? "la URL").")
    }

    static func ejecutar(id: String, texto: String, simular: Bool = false,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard let rutina = RutinasAgenteStore.todas().first(where: { $0.id == id && $0.activa }) else {
            completion(.init(ok: false, mensaje: "La rutina ya no existe o está apagada.")); return
        }
        ejecutar(rutina: rutina, texto: texto, simular: simular, completion: completion)
    }

    static func ejecutar(rutina: RutinaAgente, texto: String, simular: Bool = false,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        var mensajes: [String] = []
        var todoOK = true
        var ultimoResultado = ""
        var salidas: [String] = []
        var evidencia: [String: String] = ["receta": rutina.id, "nombre": rutina.nombre]

        func siguiente(_ i: Int) {
            guard i < rutina.pasos.count else {
                let prefijo = todoOK ? "Rutina «\(rutina.nombre)» completada." : "Rutina «\(rutina.nombre)» terminó con avisos."
                AgenteLog.registrar("rutina", ["id": rutina.id, "nombre": rutina.nombre,
                                               "ok": todoOK, "pasos": rutina.pasos.count,
                                               "simular": simular])
                evidencia["pasos"] = "\(rutina.pasos.count)"
                let salidaConsolidada = salidas.joined(separator: "\n\n")
                evidencia["salida"] = String(salidaConsolidada.prefix(2_000))
                let detalle = prefijo + (mensajes.isEmpty ? "" : " " + mensajes.joined(separator: " "))
                completion(.init(ok: todoOK,
                    mensaje: rutina.devuelveResultado && !salidaConsolidada.isEmpty
                        ? salidaConsolidada : detalle,
                    evidencia: evidencia)); return
            }
            let paso = rutina.pasos[i]
            let valor = interpolar(paso.valor, texto: texto, resultado: ultimoResultado)
            func listo(_ r: ResultadoHerramientaApple) {
                if !r.ok, !paso.opcional { todoOK = false }
                let mensaje = !r.ok && paso.opcional ? "Omití el paso opcional: \(r.mensaje)" : r.mensaje
                mensajes.append(mensaje)
                let salida = r.evidencia["salida"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let salida, !salida.isEmpty {
                    ultimoResultado = salida
                    if salidas.last != salida { salidas.append(salida) }
                }
                evidencia["paso_\(i + 1)"] = r.ok ? "ok" : (paso.opcional ? "omitido" : "fallo")
                for (k, v) in r.evidencia where !v.isEmpty {
                    evidencia["paso_\(i + 1)_\(k)"] = String(v.prefix(2_000))
                }
                siguiente(i + 1)
            }
            if RecetasRuntime.ejecutar(tipo: paso.tipo, valor: valor, texto: texto,
                                       resultadoPrevio: ultimoResultado,
                                       simular: simular, completion: listo) { return }
            switch paso.tipo {
            case "musica":
                guard Config.agenteHerramientaMusica() else {
                    listo(.init(ok: false, mensaje: "La herramienta Música está apagada.")); break
                }
                Musica.ejecutar(valor, simular: simular) { listo(.init(ok: $0.ok, mensaje: $0.mensaje)) }
            case "app":
                listo(Config.agenteHerramientaAplicaciones()
                    ? abrirApp(valor, simular: simular)
                    : .init(ok: false, mensaje: "La herramienta Aplicaciones está apagada."))
            case "url":
                listo(abrirURL(paso.valor, texto: texto, resultado: ultimoResultado,
                               simular: simular))
            case "atajo":
                guard Config.agenteHerramientaAtajos() else {
                    listo(.init(ok: false, mensaje: "La pasarela de Atajos está apagada.")); break
                }
                AppleAtajos.ejecutarVerificado(nombre: valor, texto: texto,
                                                simular: simular, completion: listo)
            case "conexion":
                // El paso referencia un modo-conexión por su id; el texto de la
                // rutina viaja como dictado. La escritura pedirá SU visto bueno
                // (modal de conexión) además del riesgo externo de la rutina.
                guard Config.agenteHerramientaConexiones() else {
                    listo(.init(ok: false, mensaje: "Las conexiones API están apagadas.")); break
                }
                guard let modoConexion = ModosStore.todos()
                    .first(where: { $0.id == paso.valor && $0.accion == "conexion" && $0.conexion != nil }) else {
                    listo(.init(ok: false, mensaje: "El paso apunta a un modo-conexión que ya no existe.")); break
                }
                if simular {
                    listo(.init(ok: true, mensaje: "Llamaría la conexión «\(modoConexion.nombre)».",
                                evidencia: ["conexion": modoConexion.id, "simulado": "true"])); break
                }
                // NSApp puede no existir (QA corre antes de crear NSApplication):
                // sin app no hay modal — la escritura fallará con mensaje claro.
                let confirmador: ConfirmadorConexion? = {
                    guard let app = NSApp, let d = app.delegate as? AppDelegate else { return nil }
                    return d.confirmadorConexionUI()
                }()
                ConexionesRunner.ejecutar(modo: modoConexion, texto: valor == paso.valor ? texto : valor,
                                          confirmar: confirmador, completion: listo)
            case "tarea":
                if !simular { NotasStore.agregar(tipo: "tarea", texto: valor) }
                listo(.init(ok: true, mensaje: "Agregué una tarea local."))
            case "nota":
                if !simular { NotasStore.agregar(tipo: "nota", texto: valor) }
                listo(.init(ok: true, mensaje: "Agregué una nota local."))
            case "nota_apple":
                guard Config.agenteHerramientaNotasApple() else {
                    listo(.init(ok: false, mensaje: "La herramienta Notas de Apple está apagada.")); break
                }
                if simular {
                    listo(.init(ok: true, mensaje: "Crearía y verificaría una nota en Notas de Apple."))
                } else {
                    NotasApple.crear(valor, completion: listo)
                }
            case "recordatorio":
                guard Config.agenteHerramientaRecordatorios() else {
                    listo(.init(ok: false, mensaje: "La herramienta Recordatorios está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Crearía un recordatorio.")) }
                else { AppleAgenda.crearRecordatorio(valor, completion: listo) }
            case "calendario":
                guard Config.agenteHerramientaCalendario() else {
                    listo(.init(ok: false, mensaje: "La herramienta Calendario está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Crearía un evento.")) }
                else { AppleAgenda.crearEvento(valor, completion: listo) }
            case "archivo":
                guard Config.agenteHerramientaArchivos() else {
                    listo(.init(ok: false, mensaje: "La herramienta Archivos está apagada.")); break
                }
                if simular { listo(.init(ok: true, mensaje: "Buscaría el archivo «\(valor)».")) }
                else {
                    ArchivosMac.buscar(valor) { urls in
                        if let u = urls.first { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                        listo(.init(ok: !urls.isEmpty, mensaje: urls.isEmpty
                            ? "No encontré el archivo «\(valor)»." : "Encontré \(urls.count) archivo(s)."))
                    }
                }
            case "captura", "grabacion":
                guard Config.agenteHerramientaCapturas() else {
                    listo(.init(ok: false, mensaje: "La herramienta Capturas está apagada.")); break
                }
                let pedido = paso.tipo == "grabacion" ? "graba la pantalla \(valor)" : "captura de pantalla \(valor)"
                CapturaMac.ejecutar(SolicitudCapturaMac.interpretar(pedido), simular: simular) {
                    listo(.init(ok: $0.ok, mensaje: $0.mensaje))
                }
            default: listo(.init(ok: false, mensaje: "El paso «\(paso.tipo)» no es compatible."))
            }
        }
        siguiente(0)
    }
}
