import Foundation

// MARK: - QA del Catálogo de capacidades (Fase 1)
//   BTODICTA_CATALOGOQA=1 → pruebas PURAS del ensamblado (sin tocar los datos
//   del usuario). Verifica sobre todo que el catálogo se AUTOACTUALIZA.

enum CatalogoQA {
    static func ejecutarSiSePidio() {
        // Volcado del catálogo REAL en vivo (solo lectura; para ver qué conoce
        // el agente HOY en este equipo). No modifica nada.
        if ProcessInfo.processInfo.environment["BTODICTA_CATALOGODUMP"] == "1" {
            let caps = CatalogoCapacidades.todas()
            print("CATÁLOGO EN VIVO — \(caps.count) capacidades:")
            for c in caps {
                let h = c.hijos.isEmpty ? "" : " · \(c.hijos.count) endpoint(s)"
                print("  [\(c.tipo)] \(c.nombre) — \(String(c.descripcion.prefix(60)))\(h)")
            }
            fflush(stdout); exit(0)
        }
        // Demo EN VIVO: el router IA decide sobre frases reales contra el
        // catálogo real (necesita IA/red). Solo diagnóstico, no ejecuta.
        if ProcessInfo.processInfo.environment["BTODICTA_ROUTERDEMO"] == "1" {
            let caps = CatalogoCapacidades.todas()
            let frases = ["en el sistema de actividades, registra que trabajé una hora en la universidad",
                          "hazme una tarea de comparar pan para mañana",
                          "qué clima hace en el Puyo",
                          "abre Word y escribe el informe",
                          "resume mis tareas pendientes",
                          "traduce esto al inglés",
                          "cuéntame un chiste"]
            let grupo = DispatchGroup()
            var salida: [String] = []
            for f in frases {
                grupo.enter()
                RouterGlobalIA.decidir(f, catalogo: caps) { d in
                    salida.append("  «\(f)» → \(d.map { "[\($0.tipo):\($0.clave)] \($0.nombre) conf=\($0.confianza) · «\($0.contenido.prefix(30))»" } ?? "SIN DECISIÓN")")
                    grupo.leave()
                }
            }
            grupo.notify(queue: .main) {
                print("ROUTER EN VIVO (IA sobre \(caps.count) capacidades):")
                salida.sorted().forEach { print($0) }
                fflush(stdout); exit(0)
            }
            RunLoop.main.run()
        }
        // Prueba en vivo: el plan de la conexión UEA real con un verbo de
        // escritura, ¿elige "registrar" (no "hoy")? Verifica el fix de evitar Codex.
        if ProcessInfo.processInfo.environment["BTODICTA_UEAPLANTEST"] == "1" {
            guard let uea = ModosStore.todos().first(where: {
                $0.accion == "conexion" && ($0.nombre.lowercased().contains("actividad"))
            }), let cx = uea.conexion else {
                print("UEAPLANTEST: no hay modo de actividades configurado"); exit(4)
            }
            print("IA del plan: \(ConexionesIA.iaDisponible(uea)?.etiqueta ?? "ninguna")")
            var resultado: String?
            ConexionesIA.resolver(modo: uea, conexion: cx,
                                  texto: "en el sistema de actividades registra que trabajé una hora en la universidad") { r in
                switch r {
                case .plan(let p): resultado = "endpoint elegido: \(p.endpoint.clave)"
                case .faltan(let f): resultado = "faltan: \(f.joined(separator: ","))"
                case .invalido(let m): resultado = "invalido: \(m)"
                }
            }
            let limite = Date().addingTimeInterval(30)
            while resultado == nil, Date() < limite { _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
            print("UEAPLANTEST → \(resultado ?? "SIN RESPUESTA (timeout)")")
            fflush(stdout); exit(0)
        }
        // Prueba en vivo del fix del árbitro: en CONTEXTO DE AGENTE, una frase
        // natural que NO nombra una conexión ("hazme una tarea…") debe caer al
        // MODO AGENTE (para que decida el router global), no ser secuestrada por
        // el árbitro de modos hacia la conexión UEA. Reproduce el flujo real.
        if ProcessInfo.processInfo.environment["BTODICTA_AGENTEROUTETEST"] == "1" {
            let agente = ModosStore.modo("agente")
            let frases = ["hazme una tarea de comparar pan para mañana",
                          "recuérdame comprar leche",
                          "cuéntame un chiste"]
            let grupo = DispatchGroup()
            var lineas: [String] = []
            for f in frases {
                grupo.enter()
                ModoResolver.resolver(texto: f, modoBase: agente, contexto: nil, vivo: nil) { r in
                    let destino: String
                    switch r {
                    case .modo(let m): destino = "modo:\(m.modo.base)/\(m.modo.id)"
                    case .cadena: destino = "cadena"
                    case .preguntar(let m): destino = "preguntar:\(m.modo.nombre)"
                    case .preguntarPlan(let p): destino = "plan:\(p.cadena.acciones.first?.modo.nombre ?? "?")"
                    case .preguntarCadena(let c, _): destino = "planCadena:\(c.acciones.first?.modo.nombre ?? "?")"
                    }
                    lineas.append("  «\(f)» → \(destino)")
                    grupo.leave()
                }
            }
            grupo.notify(queue: .main) {
                print("AGENTEROUTETEST (en contexto agente, sin árbitro que secuestre):")
                lineas.sorted().forEach { print($0) }
                fflush(stdout); exit(0)
            }
            RunLoop.main.run()
        }
        guard ProcessInfo.processInfo.environment["BTODICTA_CATALOGOQA"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("CATALOGOQA \(pasa ? "OK" : "✗") \(nombre)")
        }
        func tiene(_ caps: [Capacidad], tipo: String, clave: String) -> Bool {
            caps.contains { $0.tipo == tipo && $0.clave == clave }
        }

        // Fuentes de prueba controladas (no la biblioteca real del usuario).
        var modoCorreo = Modo(id: "correo", nombre: "Correo", icono: "envelope", base: "pulir",
                              esFijo: true, palabraVoz: "modo correo")
        modoCorreo.prompt = "Reescribe como correo."
        var modoUEA = Modo(id: "propio-uea", nombre: "Actividades UEA", icono: "bolt",
                           base: "accion", esFijo: false, palabraVoz: "modo actividades", accion: "conexion")
        modoUEA.conexion = ConexionAPI(baseURL: "https://x.ejemplo.com",
            endpoints: [EndpointAPI(clave: "registrar", metodo: "POST", ruta: "/r", esEscritura: true),
                        EndpointAPI(clave: "hoy", metodo: "GET", ruta: "/h")])
        var rutina = RutinaAgente(nombre: "Empezar jornada")
        rutina.pasos = [PasoRutinaAgente(tipo: "app", valor: "Word")]
        rutina.frases = ["empezar jornada"]
        let atajoOn = AtajoAppleDescubierto(id: "a1", nombre: "Enfoque", habilitado: true)
        let atajoOff = AtajoAppleDescubierto(id: "a2", nombre: "Secreto", habilitado: false)

        let base = CatalogoCapacidades.ensamblar(
            modos: [Modo(id: "dictado", nombre: "Dictado", icono: "mic", base: "pulir"),
                    modoCorreo, modoUEA],
            rutinas: [rutina], atajos: [atajoOn, atajoOff], herramientas: true)

        check("incluye el modo correo", tiene(base, tipo: "modo", clave: "correo"))
        check("dictado NO se cataloga", !tiene(base, tipo: "modo", clave: "dictado"))
        check("el modo con conexión es tipo conexion", tiene(base, tipo: "conexion", clave: "propio-uea"))
        check("la conexión trae sus endpoints como hijos",
              base.first { $0.clave == "propio-uea" }?.hijos.count == 2)
        check("incluye la rutina activa", tiene(base, tipo: "rutina", clave: rutina.id))
        check("incluye el atajo habilitado", tiene(base, tipo: "atajo", clave: "Enfoque"))
        check("NO incluye el atajo deshabilitado", !tiene(base, tipo: "atajo", clave: "Secreto"))
        check("incluye herramientas específicas (clima)", tiene(base, tipo: "herramienta", clave: "clima"))
        check("incluye el cerebro como último recurso", tiene(base, tipo: "cerebro", clave: "cerebro"))
        check("la conexión hereda su riesgo (escritura → externo)",
              base.first { $0.clave == "propio-uea" }?.riesgo == .externo)

        // AUTOACTUALIZACIÓN: agregar un modo NUEVO a las fuentes → aparece solo.
        var modoNuevo = Modo(id: "propio-inventado", nombre: "Mi modo nuevo", icono: "star",
                             base: "pulir", esFijo: false, palabraVoz: "modo inventado")
        modoNuevo.prompt = "Haz algo nuevo."
        let conNuevo = CatalogoCapacidades.ensamblar(
            modos: [modoCorreo, modoNuevo], rutinas: [], atajos: [], herramientas: false)
        check("un modo recién creado aparece sin tocar código",
              tiene(conNuevo, tipo: "modo", clave: "propio-inventado"))
        check("quitar fuentes reduce el catálogo (no hay lista fija)",
              conNuevo.filter { $0.tipo == "rutina" }.isEmpty)

        // El menú para la IA es un catálogo cerrado legible.
        let menu = CatalogoCapacidades.paraIA(base)
        check("paraIA lista con tipo:clave",
              menu.contains("[modo:correo]") && menu.contains("[conexion:propio-uea]"))
        check("paraIA no filtra secretos ni vacíos", !menu.contains("[atajo:Secreto]"))

        // ROUTER GLOBAL (fase 3, núcleo): valida la elección contra el catálogo.
        func decisionValida(_ j: String) -> DecisionRouter? {
            RouterGlobalIA.interpretar(j, catalogo: base, texto: "haz una tarea de comprar pan")
        }
        check("router acepta una capacidad real del catálogo",
              decisionValida(#"{"tipo":"modo","clave":"correo","confianza":0.9,"contenido":"hola"}"#)?.clave == "correo")
        check("router usa el contenido devuelto",
              decisionValida(#"{"tipo":"modo","clave":"correo","contenido":"cuerpo del correo"}"#)?.contenido == "cuerpo del correo")
        check("router RECHAZA una capacidad inventada (no está en el catálogo)",
              decisionValida(#"{"tipo":"modo","clave":"inexistente-xyz","confianza":0.99}"#) == nil)
        check("router acepta el cerebro como salida",
              decisionValida(#"{"tipo":"cerebro","clave":"cerebro","confianza":0.4}"#)?.tipo == "cerebro")
        check("router con JSON basura → nil (no ejecuta a ciegas)",
              decisionValida("no soy json") == nil)
        check("router valida la conexión del catálogo",
              decisionValida(#"{"tipo":"conexion","clave":"propio-uea","contenido":"registra 1 hora"}"#)?.clave == "propio-uea")
        check("router: contenido vacío cae al texto original",
              decisionValida(#"{"tipo":"modo","clave":"correo","contenido":""}"#)?.contenido == "haz una tarea de comprar pan")
        check("prompt del router lleva catálogo cerrado y anti-inyección",
              {
                  let p = RouterGlobalIA.prompt(catalogo: base, texto: "x")
                  return p.contains("[modo:correo]") && p.contains("INSTRUCCIONES_INTERNAS_NO_REPRODUCIR")
                      && p.contains("Jamás inventes")
              }())

        print(fallos == 0 ? "CATALOGOQA TODO OK" : "CATALOGOQA ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 3)
    }
}
