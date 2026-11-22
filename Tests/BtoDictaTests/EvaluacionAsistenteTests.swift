import XCTest
@testable import BtoDicta

/// Evaluación del asistente (spec 017): pedidos de oficina con lo que debería
/// hacer. Las reglas fijas se miden siempre; el plan de la IA, solo con
/// BTODICTA_IA_REAL=<proveedor> (y BTODICTA_IA_GRAPH=1 para Microsoft). No ejecuta nada.
final class EvaluacionAsistenteTests: XCTestCase {
    /// (pedido, esperado). Datos genéricos.
    static let casos: [(String, String)] = [
        ("¿Qué tengo en mi agenda esta semana?", "graph:ver_agenda"),
        ("Revisa mis correos de hoy, los más importantes", "graph:leer_correo"),
        ("Revisa mi correo personal de hoy, por favor.", "graph:leer_correo"),
        ("Archiva esos tres correos que me leíste", "graph:archivar_correo"),
        ("Resúmeme el Excel de gastos que bajé", "graph:leer_documento"),
        ("Abre YouTube en Edge y pon una canción alegre", "graph:reproducir_youtube"),
        ("Dame el resumen de la mañana", "graph:resumen_manana"),
        ("Graba esta reunión", "graph:grabar_reunion"),
        ("Ya terminó la reunión, hazme el acta", "graph:terminar_reunion"),
        ("Avísame si Paul no me responde hasta el viernes", "graph:seguir_correo"),
        ("Anota en Obsidian que el switch del laboratorio quedó configurado", "graph:obsidian_anotar"),
        ("¿Qué decidimos sobre el proyecto de wifi en los buses? Búscalo en mis notas", "graph:obsidian_buscar"),
        ("¿Qué tengo pendiente en Quipux?", "graph:delegar_agente"),
        ("Recuérdame responder el último correo de mi correo personal el viernes a las 9", "graph:correo_a_tarea"),
        ("Prepárame la proforma para el SERCOP de la empresa Mitad del Mundo, mantenimiento de Quipux por mil dólares", "graph:delegar_agente"),
        ("Archiva el último correo que me llegó a mi correo personal", "graph:archivar_correo"),
        ("Abre Claude Code en el proyecto BtoDicta", "graph:abrir_sesion_ia|comando"),
        ("Quiero firmar el PDF que me llegó, ábremelo para firmarlo", "graph:firmar_documento"),
        ("Busca los correos de persona@ejemplo.com", "graph:buscar_correo"),
        ("Hazme un borrador para persona@ejemplo.com con asunto Prueba diciendo hola", "graph:borrador_correo"),
        ("Agéndame una reunión con el equipo mañana a las diez por una hora", "graph:crear_evento"),
        ("Responde al correo número 1 diciendo recibido, gracias", "graph:responder_correo"),
        ("Envía el borrador que preparaste", "graph:enviar_borrador"),
        ("¿Cuál es el correo de la directora de talento humano?", "graph:buscar_persona"),
        ("Recuérdame en 10 minutos revisar el informe de la red", "accion:recordatorios|regla:recordatorios"),
        ("Crea una tarea: enviar el oficio del cableado", "modo:tarea|regla:tarea_local"),
        ("Tacha la tarea enviar el oficio del cableado", "regla:tachar"),
        ("Cállate", "regla:callar"),
        ("Silencia la computadora", "regla:volumen"),
        ("Sube el volumen al 50 por ciento", "regla:volumen"),
        ("Abre la calculadora", "comando|accion:aplicacion|modo:aplicacion|regla:aplicacion"),
        ("Abre Microsoft Teams", "comando|accion:aplicacion|modo:aplicacion|regla:aplicacion"),
        ("¿Cuánto espacio libre tengo en el disco?", "comando"),
        ("¿Qué hora es en Madrid?", "comando"),
        ("Toma una captura de pantalla", "accion:captura_pantalla|comando|regla:captura_pantalla"),
        ("Crea un documento de Word con un memo de prueba para el equipo de TI", "graph:crear_documento"),
        ("Crea un Excel con gastos: transporte 10, almuerzo 8, internet 25", "graph:crear_hoja"),
        ("Hazme un oficio formal para el director pidiendo permiso el viernes", "graph:crear_documento"),
        ("¿Qué dicté la semana pasada sobre el switch del laboratorio?", "graph:buscar_historial"),
        ("Transcribe el último audio que descargué", "graph:transcribir_archivo"),
        ("Resume mi bitácora de hoy", "graph:resumen_bitacora"),
        ("¿Qué significa el error que tengo en la pantalla?", "graph:ver_pantalla"),
        ("Corrige la ortografía del texto que seleccioné", "graph:editar_seleccion"),
        ("Crea una habilidad: cuando te pida un informe semanal usa las secciones logros, pendientes y riesgos", "graph:crear_habilidad"),
        ("Busca en internet la seguridad de los autos eléctricos", "modo:buscar|comando|regla:buscar"),
        ("Borra todos los correos de hoy", "respuesta|graph:papelera_correo"),
        ("Hola, ¿cómo estás?", "respuesta"),
        ("¿Qué tareas tengo pendientes en BtoDicta?", "graph:tareas_resumen"),
        ("Recuerda que mi jefe directo se llama Pedro Gómez", "graph:recordar"),
    ]

    /// Conversaciones encadenadas: lo que el usuario dice DESPUÉS de una acción.
    static let cadenas: [(contexto: String, pedido: String, esperado: String)] = {
        let lista = "MEMORIA CORTA DE ESTA CONVERSACIÓN:\nUsuario: léeme los tres últimos de mi correo personal\nBeto: Revisé los 3 correos más recientes. 1) Ana Pérez — Informe trimestral (trae un PDF); 2) Paul — Reunión del lunes; 3) Banco — Estado de cuenta."
        let borrador = "MEMORIA CORTA DE ESTA CONVERSACIÓN:\nUsuario: escríbele a paul@ejemplo.org que confirmo la reunión del lunes\nBeto: Preparé un borrador para paul@ejemplo.org, asunto «Reunión del lunes». ¿Lo envío o lo cambio?"
        let acta = "MEMORIA CORTA DE ESTA CONVERSACIÓN:\nUsuario: terminó la reunión\nBeto: Listo, el acta de «Plan de red»: 2 acuerdos y 3 tareas. Acuerdos: cambiar el switch; abrir la VLAN 30. ¿Preparo el correo de seguimiento?"
        return [
            (lista, "Archívalos", "graph:archivar_correo"),
            (lista, "Responde al 2 que mañana lo reviso", "graph:responder_correo"),
            (lista, "Baja los adjuntos del primero", "graph:adjuntos_correo"),
            (lista, "Márcalos como leídos", "graph:marcar_correo"),
            (lista, "Recuérdame contestarle a Ana el lunes a las 9", "graph:correo_a_tarea"),
            (lista, "Manda el del banco a la papelera", "graph:papelera_correo"),
            (borrador, "Sí, envíalo", "graph:enviar_borrador"),
            (borrador, "Adjúntale el último PDF que bajé", "graph:adjuntar_archivo"),
            (borrador, "Mejor hazlo más formal", "graph:modificar_borrador"),
            (acta, "Sí, prepáralo para ana@ejemplo.org", "graph:borrador_correo"),
        ]
    }()

    func testCadenasConIA() throws {
        let id = ProcessInfo.processInfo.environment["BTODICTA_IA_REAL"] ?? ""
        try XCTSkipIf(id.isEmpty)
        let base = try XCTUnwrap(ChatIA.catalogo.first { $0.id == id })
        let modelo = ProcessInfo.processInfo.environment["BTODICTA_IA_MODELO"] ?? ""
        let ia = modelo.isEmpty ? base : base.conModelo(modelo)
        let caps = CatalogoCapacidades.todas().filter { ["modo", "conexion", "rutina"].contains($0.tipo) && $0.clave != "agente" }
        Arnes.preparar(catalogo: CatalogoCapacidades.todas())
        var aciertos = 0
        for c in Self.cadenas {
            var obtenido = AgenteEvaluacion.porReglas(c.pedido, graph: true)
            if obtenido == nil {
                let e = expectation(description: c.pedido)
                let p = AgenteTerminal.promptMixto(pedido: c.pedido, contexto: c.contexto,
                                                   catalogo: CatalogoCapacidades.paraIA(caps), correo: true,
                                                   arnes: Arnes.contexto(para: c.pedido), memoria: Arnes.memoria())
                let t0 = Date()
                RouterGlobalIA.llamarIA(ia, prompt: p, textLen: p.count, plazo: 40) { r in
                    obtenido = AgenteEvaluacion.porIA(r ?? "", catalogo: caps, texto: c.pedido)
                    if !AgenteEvaluacion.acierta(obtenido ?? "", esperado: c.esperado) {
                        print("CADENA CRUDO \(c.pedido): \((r ?? "nil").prefix(300))")
                    }
                    print(String(format: "CADENA tiempo %.1f s", Date().timeIntervalSince(t0)))
                    e.fulfill()
                }
                wait(for: [e], timeout: 60)
            }
            let ok = AgenteEvaluacion.acierta(obtenido ?? "", esperado: c.esperado)
            if ok { aciertos += 1 }
            print("CADENA \(ok ? "✓" : "✗") \(c.pedido) → \(obtenido ?? "-") (esperado \(c.esperado))")
        }
        print("CADENA TOTAL \(aciertos)/\(Self.cadenas.count)")
    }

    func testCasosValidos() {
        XCTAssertTrue(AgenteEvaluacion.acierta("regla:volumen", esperado: "regla:volumen"))
        XCTAssertTrue(AgenteEvaluacion.acierta("comando", esperado: "graph:x|comando"))
        XCTAssertFalse(AgenteEvaluacion.acierta("respuesta", esperado: "comando"))
        XCTAssertEqual(AgenteEvaluacion.porReglas("Silencia la computadora", graph: false), "regla:volumen")
        XCTAssertEqual(AgenteEvaluacion.porReglas("Cállate", graph: false), "regla:callar")
    }

    func testEvaluacionConIA() throws {
        let id = ProcessInfo.processInfo.environment["BTODICTA_IA_REAL"] ?? ""
        try XCTSkipIf(id.isEmpty)
        let base = try XCTUnwrap(ChatIA.catalogo.first { $0.id == id })
        let modelo = ProcessInfo.processInfo.environment["BTODICTA_IA_MODELO"] ?? ""
        let ia = modelo.isEmpty ? base : base.conModelo(modelo)
        let graph = ProcessInfo.processInfo.environment["BTODICTA_IA_GRAPH"] == "1"
        let caps = CatalogoCapacidades.todas().filter { ["modo", "conexion", "rutina"].contains($0.tipo) && $0.clave != "agente" }
        Arnes.preparar(catalogo: CatalogoCapacidades.todas())
        var aciertos = 0
        for (pedido, esperado) in Self.casos {
            var obtenido = AgenteEvaluacion.porReglas(pedido, graph: graph)
            if obtenido == nil {
                let e = expectation(description: pedido)
                // Lo que en la app ya habría pasado en turnos anteriores.
                let contexto = "MEMORIA CORTA DE ESTA CONVERSACIÓN:\nUsuario: revisa mis correos de hoy\nBeto: Revisé 5 correos de los últimos 1 día(s).\nUsuario: hazme un borrador para colega@ejemplo.org sobre el informe\nBeto: Preparé un borrador en Microsoft para colega@ejemplo.org, asunto «Informe semanal»."
                let p = AgenteTerminal.promptMixto(pedido: pedido, contexto: contexto,
                                                   catalogo: CatalogoCapacidades.paraIA(caps), correo: graph,
                                                   arnes: Arnes.contexto(para: pedido), memoria: Arnes.memoria())
                RouterGlobalIA.llamarIA(ia, prompt: p, textLen: p.count, plazo: 40) { r in
                    obtenido = AgenteEvaluacion.porIA(r ?? "", catalogo: caps, texto: pedido)
                    if !AgenteEvaluacion.acierta(obtenido ?? "", esperado: esperado) {
                        print("EVAL CRUDO \(pedido): \((r ?? "nil").prefix(300))")
                    }
                    e.fulfill()
                }
                wait(for: [e], timeout: 60)
            }
            let ok = AgenteEvaluacion.acierta(obtenido ?? "", esperado: esperado)
            if ok { aciertos += 1 }
            print("EVAL \(ok ? "✓" : "✗") \(pedido) → \(obtenido ?? "-") (esperado \(esperado))")
        }
        print(String(format: "EVAL TOTAL %d/%d = %.0f %%", aciertos, Self.casos.count,
                     100 * Double(aciertos) / Double(Self.casos.count)))
    }
}
