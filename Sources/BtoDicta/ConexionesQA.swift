import Foundation

// MARK: - QA de Conexiones API (espejo puro, sin tocar la config del usuario)
//
//   BTODICTA_CONEXIONTEST=1     → pruebas puras (modelo, motor, invariantes)
//   BTODICTA_CONEXIONTEST_RED=1 → además, un GET real a una API pública
//     (separado a propósito: el QA base debe pasar sin internet)

enum ConexionesQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_CONEXIONTEST"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("CONEXIONTEST \(pasa ? "OK" : "✗") \(nombre)")
        }

        // 1. Decode tolerante: un modos.json VIEJO (sin `conexion`) sigue cargando.
        let modoViejo = #"{"id":"propio-x","nombre":"Viejo","icono":"bolt","base":"pulir"}"#
        let viejo = try? JSONDecoder().decode(Modo.self, from: Data(modoViejo.utf8))
        check("modo viejo sin conexion decodifica", viejo != nil && viejo?.conexion == nil)

        // 2. Round-trip: un modo CON conexión persiste y vuelve completo.
        var modo = Modo(id: "propio-qa", nombre: "Clima QA", icono: "bolt", base: "accion",
                        esFijo: false, accion: "conexion")
        modo.conexion = ConexionAPI(
            baseURL: "https://api.open-meteo.com",
            auth: AuthConexion(tipo: "ninguna"),
            headers: ["Accept": "application/json"],
            endpoints: [EndpointAPI(clave: "clima", metodo: "GET", ruta: "/v1/forecast",
                                    descripcion: "clima actual",
                                    query: "latitude=-1.49&longitude=-78.0&current_weather=true")])
        let data = try? JSONEncoder().encode(modo)
        let vuelto = data.flatMap { try? JSONDecoder().decode(Modo.self, from: $0) }
        check("round-trip conserva la conexión",
              vuelto?.conexion?.baseURL == "https://api.open-meteo.com"
              && vuelto?.conexion?.endpoints.first?.clave == "clima"
              && vuelto?.conexion?.headers["Accept"] == "application/json")

        // 3. URL segura: mismo criterio fail-closed de toda la casa.
        check("https válida", ConexionesMotor.urlSegura("https://api.ejemplo.com/v1"))
        check("http localhost válida", ConexionesMotor.urlSegura("http://localhost:8080"))
        check("http remota RECHAZADA", !ConexionesMotor.urlSegura("http://api.ejemplo.com"))
        check("ftp RECHAZADA", !ConexionesMotor.urlSegura("ftp://ejemplo.com"))
        check("sin host RECHAZADA", !ConexionesMotor.urlSegura("https://"))

        // 4. Valores de ruta: nada que cambie de endpoint.
        check("valor de ruta simple", ConexionesMotor.valorSeguroParaRuta("Quito"))
        check("valor con / RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("a/b"))
        check("valor con .. RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("..%2f"))
        check("valor vacío RECHAZADO", !ConexionesMotor.valorSeguroParaRuta("  "))

        // 5. Plantillas: extracción de {variables}.
        check("variables de plantilla",
              ConexionesMotor.variablesEnPlantilla("/w/{ciudad}?q={texto}") == ["ciudad", "texto"])

        // 6. Construcción de URL: encode de tildes/espacios, query con {texto}.
        let ep = EndpointAPI(clave: "w", metodo: "GET", ruta: "/{ciudad}", query: "format=3&q={texto}")
        let url = ConexionesMotor.construirURL(base: "https://wttr.in/",
                                               endpoint: ep,
                                               valores: ["ciudad": "Baños de Agua Santa", "texto": "¿qué?"])
        check("URL construida y codificada",
              url?.absoluteString == "https://wttr.in/Ba%C3%B1os%20de%20Agua%20Santa?format=3&q=%C2%BFqu%C3%A9%3F")
        check("ruta con variable insegura → nil",
              ConexionesMotor.construirURL(base: "https://wttr.in",
                                           endpoint: ep,
                                           valores: ["ciudad": "../admin", "texto": "x"]) == nil)
        check("base http remota → nil",
              ConexionesMotor.construirURL(base: "http://wttr.in", endpoint: ep,
                                           valores: ["ciudad": "Quito", "texto": "x"]) == nil)

        // 7. Body JSON-aware: tipos reales, nada de pegar strings.
        let plantilla = #"{"nota":"{texto}","minutos":"{min}","items":"{items}","fijo":1}"#
        let valores: [String: Any] = [
            "texto": "dijo: \"hola\"\ncon tilde á",
            "min": 90,
            "items": [["detalle": "uno", "min": 30], ["detalle": "dos", "min": 60]],
        ]
        let body = ConexionesMotor.sustituirBody(plantilla, valores: valores)
        let obj = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("body: string con comillas/salto/tilde intacto",
              (obj?["nota"] as? String) == "dijo: \"hola\"\ncon tilde á")
        check("body: número tipado (no string)", (obj?["minutos"] as? Int) == 90)
        check("body: lista tipada con 2 ítems", (obj?["items"] as? [[String: Any]])?.count == 2)
        check("body: campo fijo intacto", (obj?["fijo"] as? Int) == 1)
        check("plantilla inválida → nil", ConexionesMotor.sustituirBody("{no es json", valores: [:]) == nil)
        let mixto = ConexionesMotor.sustituirBody(#"{"saludo":"hola {texto}"}"#, valores: ["texto": "Beto"])
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check("body: interpolación en string mixto", (mixto?["saludo"] as? String) == "hola Beto")

        // 8. Validación de valores contra el esquema del endpoint.
        var epVars = EndpointAPI(clave: "reg", metodo: "POST", ruta: "/x", esEscritura: true)
        epVars.variables = [VariableAPI(nombre: "min", tipo: "numero", requerida: true),
                            VariableAPI(nombre: "items", tipo: "lista")]
        check("falta requerida detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: [:]).isEmpty)
        check("no declarada detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": 5, "otra": 1]).isEmpty)
        check("número inválido detectado",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": "noesnum"]).isEmpty)
        check("lista inválida detectada",
              !ConexionesMotor.validarValores(endpoint: epVars, valores: ["min": 5, "items": "plano"]).isEmpty)
        check("valores correctos pasan",
              ConexionesMotor.validarValores(endpoint: epVars,
                                             valores: ["min": 5, "items": [1, 2]]).isEmpty)
        check("{hoy} es variable implícita (no exige declaración)",
              ConexionesMotor.validarValores(endpoint: epVars,
                                             valores: ["min": 5, "hoy": "2026-07-20"]).isEmpty)

        // 8b. Texto hablable: sin emojis, espacios colapsados, con tope.
        let hablable = ConexionesMotor.textoParaVoz("Quito: 🌤️  +16°C\nviento ↓ 5km/h")
        if hablable != "Quito, 16 grados viento 5 kilómetros por hora" {
            print("CONEXIONTEST debug voz: «\(hablable)»")
        }
        check("texto para voz en español hablado",
              hablable == "Quito, 16 grados viento 5 kilómetros por hora")
        check("voz: negativos y porcentajes",
              ConexionesMotor.textoParaVoz("Quito: -3°C, humedad 92%")
              == "Quito, menos 3 grados, humedad 92 por ciento")
        check("voz: hora intacta",
              ConexionesMotor.textoParaVoz("actualizado 14:30") == "actualizado 14:30")

        // 9. Evidencia sin secretos.
        check("token enmascarado",
              !ConexionesMotor.enmascarar("Bearer abc123xyz falló", secretos: ["abc123xyz"]).contains("abc123xyz"))

        // 10. Riesgo/escritura: método manda aunque la casilla mienta.
        check("POST es escritura aunque no esté marcado",
              EndpointAPI(clave: "p", metodo: "POST").efectivamenteEscritura)
        check("GET lectura no es escritura", !EndpointAPI(clave: "g", metodo: "GET").efectivamenteEscritura)
        check("conexión de lectura = reversible",
              ConexionesMotor.riesgo(modo.conexion) == .reversible)
        var conEscritura = modo.conexion!
        conEscritura.endpoints.append(EndpointAPI(clave: "pub", metodo: "POST"))
        check("conexión con escritura = externo", ConexionesMotor.riesgo(conEscritura) == .externo)
        check("conexión ausente = externo (prudencia)", ConexionesMotor.riesgo(nil) == .externo)

        // 11. Catálogo y descripciones.
        check("acción conexion existe en el catálogo", Acciones.valido("conexion"))
        check("descripción de etapa legible",
              ModoPlanificador.descripcionEtapa(modo).contains("Usar la conexión"))

        // 12. INVARIANTE del árbitro IA: una acción sintética "accion:conexion"
        // (sin API embebida) se rechaza; solo el MODO del usuario la lleva.
        let jsonArbitro = #"{"intent":true,"confidence":0.95,"prefix_words":0,"suffix_words":0,"stages":[{"key":"accion:conexion","idioma":null,"destinatario":null}],"alternatives":[]}"#
        check("árbitro rechaza accion:conexion sintética",
              ModoIAEnrutador.interpretar(jsonArbitro, textoOriginal: "consulta el clima de hoy",
                                          catalogo: ModoCatalogo(modos: ModosStore.base)) == nil)

        // 13. Runner fail-closed sin red: cada camino de error responde claro.
        func esperar(_ arranca: (@escaping (ResultadoHerramientaApple) -> Void) -> Void,
                     segundos: TimeInterval = 5)
            -> ResultadoHerramientaApple? {
            var r: ResultadoHerramientaApple?
            arranca { r = $0 }
            let limite = Date().addingTimeInterval(segundos)
            while r == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            return r
        }
        var sinConexion = modo; sinConexion.conexion = nil
        let r1 = esperar { ConexionesRunner.ejecutar(modo: sinConexion, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("runner sin conexión configurada falla claro",
              r1?.ok == false && r1?.mensaje.lowercased().contains("conexión") == true)
        var urlMala = modo; urlMala.conexion?.baseURL = "http://remoto.ejemplo.com"
        let r2 = esperar { ConexionesRunner.ejecutar(modo: urlMala, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("runner con URL insegura falla claro",
              r2?.ok == false && r2?.mensaje.lowercased().contains("segura") == true)
        var soloEscritura = modo
        soloEscritura.conexion?.endpoints = [EndpointAPI(clave: "pub", metodo: "POST", ruta: "/p")]
        soloEscritura.conexion?.usarIA = false
        let r3 = esperar { ConexionesRunner.ejecutar(modo: soloEscritura, texto: "hola",
                                                     ignorarInterruptor: true, completion: $0) }
        check("solo-escritura sin IA ni clave dictada falla claro",
              r3?.ok == false && r3?.mensaje.lowercased().contains("escritura") == true)
        // Con el interruptor RESPETADO y apagado, el gate responde apagado.
        if !Config.agenteHerramientaConexiones() {
            let r4 = esperar { ConexionesRunner.ejecutar(modo: modo, texto: "hola", completion: $0) }
            check("interruptor apagado bloquea el runner",
                  r4?.ok == false && r4?.mensaje.lowercased().contains("apagadas") == true)
        }

        // 14. Selección de endpoint sin IA: clave dictada gana; si no, primer GET.
        var multi = modo.conexion!
        multi.endpoints = [EndpointAPI(clave: "clima", metodo: "GET", ruta: "/a"),
                           EndpointAPI(clave: "noticias", metodo: "GET", ruta: "/b"),
                           EndpointAPI(clave: "pub", metodo: "POST", ruta: "/c")]
        check("clave dictada elige endpoint",
              ConexionesRunner.endpointPara(multi, texto: "noticias de hoy")?.clave == "noticias")
        check("sin clave usa el primer GET",
              ConexionesRunner.endpointPara(multi, texto: "cualquier cosa")?.clave == "clima")

        // 15. FASE 2 — interpretar: la respuesta de la IA se valida ESTRICTA.
        var conexIA = ConexionAPI(baseURL: "https://wttr.in")
        var epCiudad = EndpointAPI(clave: "clima", metodo: "GET", ruta: "/{ciudad}",
                                   descripcion: "clima de una ciudad", query: "format=3")
        epCiudad.variables = [VariableAPI(nombre: "ciudad", tipo: "texto", requerida: true,
                                          descripcion: "nombre de la ciudad")]
        var epLista = EndpointAPI(clave: "registrar", metodo: "POST", ruta: "/reg", esEscritura: true)
        epLista.variables = [VariableAPI(nombre: "items", tipo: "lista")]
        conexIA.endpoints = [epCiudad, epLista]

        func esPlan(_ r: ResultadoPlanConexion) -> PlanConexion? {
            if case .plan(let p) = r { return p }; return nil
        }
        func esFaltan(_ r: ResultadoPlanConexion) -> [String]? {
            if case .faltan(let f) = r { return f }; return nil
        }
        func esInvalido(_ r: ResultadoPlanConexion) -> Bool {
            if case .invalido = r { return true }; return false
        }

        let planOK = ConexionesIA.interpretar(
            #"{"endpoint":"clima","variables":{"ciudad":"Quito"},"resumen":"Clima de Quito","faltan":[]}"#,
            conexion: conexIA, textoDictado: "qué clima hace en Quito")
        check("plan válido aceptado con valores",
              esPlan(planOK)?.endpoint.clave == "clima"
              && (esPlan(planOK)?.valores["ciudad"] as? String) == "Quito"
              && esPlan(planOK)?.resumen == "Clima de Quito")
        check("plan añade {texto} automático",
              (esPlan(planOK)?.valores["texto"] as? String) == "qué clima hace en Quito")
        let fence = ConexionesIA.interpretar(
            "```json\n{\"endpoint\":\"clima\",\"variables\":{\"ciudad\":\"Tena\"},\"resumen\":\"ok\",\"faltan\":[]}\n```",
            conexion: conexIA, textoDictado: "x")
        check("plan dentro de fence markdown se extrae", esPlan(fence)?.endpoint.clave == "clima")
        check("endpoint inexistente rechazado",
              esInvalido(ConexionesIA.interpretar(#"{"endpoint":"otro","variables":{}}"#,
                                                  conexion: conexIA, textoDictado: "x")))
        // Fase 3: la IA SÍ puede proponer escritura (irá a confirmación)…
        check("escritura aceptada como plan (irá a confirmación)",
              esPlan(ConexionesIA.interpretar(#"{"endpoint":"registrar","variables":{"items":[]}}"#,
                                              conexion: conexIA, textoDictado: "x"))?.endpoint.clave == "registrar")
        // …pero jamás el endpoint de 2ª fase directo.
        var conexConfirm = conexIA; conexConfirm.confirmEndpointId = "registrar"
        check("endpoint de 2ª fase no se elige directo",
              esInvalido(ConexionesIA.interpretar(#"{"endpoint":"registrar","variables":{"items":[]}}"#,
                                                  conexion: conexConfirm, textoDictado: "x")))
        check("catálogo del prompt excluye la 2ª fase",
              !ConexionesIA.catalogoTexto(conexConfirm).contains("registrar"))
        check("JSON roto → inválido",
              esInvalido(ConexionesIA.interpretar("no hay json aquí", conexion: conexIA, textoDictado: "x")))
        check("faltan declarado se respeta",
              esFaltan(ConexionesIA.interpretar(#"{"endpoint":"clima","variables":{},"faltan":["ciudad"]}"#,
                                                conexion: conexIA, textoDictado: "x")) == ["ciudad"])
        check("requerida ausente se detecta aunque la IA no la liste",
              esFaltan(ConexionesIA.interpretar(#"{"endpoint":"clima","variables":{},"faltan":[]}"#,
                                                conexion: conexIA, textoDictado: "x")) == ["ciudad"])
        check("faltan inventadas se filtran",
              esFaltan(ConexionesIA.interpretar(#"{"endpoint":"clima","variables":{"ciudad":"Quito"},"faltan":["inventada"]}"#,
                                                conexion: conexIA, textoDictado: "x")) == nil)
        check("variable no declarada en plan rechazada",
              esInvalido(ConexionesIA.interpretar(#"{"endpoint":"clima","variables":{"ciudad":"Quito","extra":1}}"#,
                                                  conexion: conexIA, textoDictado: "x")))
        check("prompt lleva catálogo y sobre anti-inyección",
              {
                  let p = ConexionesIA.promptPara(modo: modo, conexion: conexIA, texto: "hola")
                  return p.contains("clima (GET)") && p.contains("INSTRUCCIONES_INTERNAS_NO_REPRODUCIR")
                      && p.contains("ciudad (texto, requerida)")
                      && p.contains("registrar (POST, escritura: se pedirá confirmación)")
              }())

        // FASE 3 — auth y flujo proponer→confirmar (parte pura, sin red)
        check("dot-path plano", ConexionesAuth.valorDotPath(["token": "abc"], ruta: "token") as? String == "abc")
        check("dot-path anidado",
              ConexionesAuth.valorDotPath(["data": ["access_token": "xyz"]], ruta: "data.access_token") as? String == "xyz")
        check("dot-path ausente",
              ConexionesAuth.valorDotPath(["data": [:]], ruta: "data.token") == nil)
        check("form-encode escapa y ordena",
              String(data: ConexionesAuth.formEncode([("user", "a b&c"), ("pass", "ñ=1")]), encoding: .utf8)
              == "user=a%20b%26c&pass=%C3%B1%3D1")
        ConexionesAuth.invalidar("qa-cache")
        ConexionesAuth.cachear("tok-qa", modoId: "qa-cache", ttlMinutos: 5)
        check("token cacheado se recupera", ConexionesAuth.tokenCacheado("qa-cache") == "tok-qa")
        ConexionesAuth.invalidar("qa-cache")
        check("token invalidado desaparece", ConexionesAuth.tokenCacheado("qa-cache") == nil)
        // Endpoint de escritura elegible por clave dictada; 2ª fase jamás.
        var conexEscritura = conexIA; conexEscritura.confirmEndpointId = ""
        check("clave dictada puede elegir escritura",
              ConexionesRunner.endpointPara(conexEscritura, texto: "registrar dos horas")?.clave == "registrar")
        check("2ª fase nunca elegible por clave",
              ConexionesRunner.endpointPara(conexConfirm, texto: "registrar dos horas")?.clave != "registrar")
        // Escritura sin confirmador: jamás se ejecuta (fail-closed, sin red).
        var modoEscritura = modo
        modoEscritura.conexion = conexEscritura
        modoEscritura.conexion?.usarIA = false
        let rSinConf = esperar { ConexionesRunner.ejecutar(modo: modoEscritura, texto: "registrar algo",
                                                           ignorarInterruptor: true, completion: $0) }
        check("escritura sin confirmador se niega",
              rSinConf?.ok == false && rSinConf?.mensaje.contains("confirmación") == true)
        // Confirmador que dice NO: cancela sin tocar la red (URL inalcanzable a propósito).
        var modoCancela = modoEscritura
        modoCancela.conexion?.baseURL = "https://jamas-resuelve.invalido"
        let rNo = esperar { done in
            ConexionesRunner.ejecutar(modo: modoCancela, texto: "registrar algo",
                                      ignorarInterruptor: true,
                                      confirmar: { _, _, responder in responder(false) },
                                      completion: done)
        }
        check("confirmador en NO cancela sin llamar",
              rNo?.ok == false && rNo?.evidencia["cancelado"] == "usuario")

        // 15b1. Formateo legible de una respuesta JSON para el visto bueno.
        let legibles = ConexionesMotor.lineasLegibles([
            "summary": ["create": [["tarea": "Revisión de impresoras", "minutos": 120]],
                        "totals": ["items": 1]],
            "previewId": String(repeating: "j", count: 2700),
            "expiresInSeconds": 600,
        ] as [String: Any])
        check("legible: claves y valores en líneas",
              legibles.contains { $0.contains("tarea: Revisión de impresoras") }
              && legibles.contains { $0.contains("expiresInSeconds: 600") })
        check("legible: el JWT gigante se omite",
              !legibles.contains { $0.contains("jjjj") })

        // 15a9. Detección tolerante agente→modo-conexión (los casos REALES que
        // fallaron: cortesía inicial, «en» intercalado, nombre a secas).
        var modoAct = Modo(id: "qa-det", nombre: "Registro de Tareas", icono: "bolt",
                           base: "accion", esFijo: false,
                           palabraVoz: "modo registro, pon mis tareas, registra mis tareas, mis tareas",
                           accion: "conexion")
        modoAct.conexion = ConexionAPI(baseURL: "https://x.ejemplo.com")
        let catalogoDet = [modoAct, ModosStore.base[0]]
        func det(_ t: String) -> (modo: Modo, contenido: String)? {
            ConexionesDeteccion.detectar(t, modos: catalogoDet, nombreAsistente: "Jarvis")
        }
        check("detecta frase exacta",
              det("pon mis tareas que hice algo")?.modo.id == "qa-det")
        check("tolera cortesía inicial y «en» intercalado",
              det("por favor, pon en mis tareas que estoy haciendo una API nueva")?.modo.id == "qa-det")
        check("contenido conserva el pedido",
              det("por favor, pon en mis tareas que estoy haciendo una API nueva")?
                .contenido.contains("API nueva") == true)
        check("nombre del modo a secas activa (repreguntará)",
              det("registro")?.modo.id == "qa-det" && det("registro")?.contenido == "")
        check("«modo registro» sin más también",
              det("modo registro")?.modo.id == "qa-det")
        check("arranque libre: «debes ingresar en mis tareas»",
              det("debes ingresar en mis tareas que hice pruebas del conector")?.modo.id == "qa-det")
        check("descripción del modal es neutra",
              ModoPlanificador.descripcionEtapa(modoAct) == "Usar la conexión Registro de Tareas")
        check("conjugación tolerada: «pongo en mis tareas»",
              det("pongo en mis tareas que hice pruebas del conector durante 15 minutos")?.modo.id == "qa-det")
        check("conjugación tolerada: «registro … tareas»",
              det("registro mis tareas de hoy")?.modo.id == "qa-det")
        check("no roba pedidos ajenos", det("ponme una canción de Julio Jaramillo") == nil)
        check("no matchea narración sin frase", det("hoy estuve revisando tareas del taller") == nil)

        // 15b0. Iteración sobre propuesta rechazada («cámbiala, no la rechaces»).
        ConexionesIA.limpiarPendiente(modoId: "qa-iter")
        var modoIter = modo; modoIter.id = "qa-iter"
        check("sin rechazo previo el prompt va limpio",
              !ConexionesIA.promptPara(modo: modoIter, conexion: conexIA, texto: "x")
                .contains("PROPUESTA ANTERIOR"))
        ConexionesIA.registrarRechazo(modoId: "qa-iter", pedido: "registra 2 horas de soporte",
                                      tabla: ["tarea: Revisión de impresoras", "minutos: 120"])
        let promptIter = ConexionesIA.promptPara(modo: modoIter, conexion: conexIA,
                                                 texto: "mejor ponle 90 minutos")
        check("el rechazo entra al prompt como propuesta anterior",
              promptIter.contains("PROPUESTA ANTERIOR")
              && promptIter.contains("minutos: 120")
              && promptIter.contains("registra 2 horas de soporte"))
        ConexionesIA.limpiarPendiente(modoId: "qa-iter")
        check("al limpiar desaparece del prompt",
              !ConexionesIA.promptPara(modo: modoIter, conexion: conexIA, texto: "x")
                .contains("PROPUESTA ANTERIOR"))
        check("timeout de lectura configurable con piso y techo",
              Config.conexionConfirmacionSegundos() >= 20
              && Config.conexionConfirmacionSegundos() <= 600)

        // 15b1b. Explicación de propuesta: apagada por defecto y sin bloquear.
        var esperaExplicacion: String?? = nil
        ConexionesIA.explicarPropuesta(modo: modo, conexion: conexIA, pedido: "x",
                                       cuerpo: #"{"a":1}"#) { esperaExplicacion = $0 }
        let limiteExp = Date().addingTimeInterval(2)
        while esperaExplicacion == nil, Date() < limiteExp {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        check("propuesta con IA apagada por defecto → sin explicación",
              (esperaExplicacion ?? "no llegó") == nil)

        // 15b1c. La redacción sabe qué operación fue: consulta jamás se narra
        // como registro (pasó en producción: leyó el día y dijo «quedó registrada»).
        let promptOp = ConexionesIA.promptRedaccion(instrucciones: "resume",
                                                    pedido: "pon mis tareas",
                                                    respuestaAPI: "{\"count\":1}",
                                                    operacion: "hoy (consulta de solo lectura): tareas del día")
        check("la redacción recibe la operación ejecutada",
              promptOp.contains("OPERACIÓN EJECUTADA: hoy (consulta de solo lectura)")
              && promptOp.contains("jamás digas que algo «quedó registrado»"))
        check("regla del plan: narración = escritura",
              ConexionesIA.promptPara(modo: modo, conexion: conexIA, texto: "x")
                .contains("elige el endpoint de ESCRITURA correspondiente aunque el verbo sea raro"))

        // 15b2. Prompt de vuelta (redacción): estructura y datos no confiables.
        check("prompt de vuelta lleva instrucciones, pedido y respuesta",
              {
                  let p = ConexionesIA.promptRedaccion(instrucciones: "ciudad, grados y consejo",
                                                       pedido: "clima de Quito",
                                                       respuestaAPI: "Quito: +16°C")
                  return p.contains("ciudad, grados y consejo") && p.contains("clima de Quito")
                      && p.contains("Quito: +16°C") && p.contains("NO CONFIABLES")
                      && p.contains("INSTRUCCIONES_INTERNAS_NO_REPRODUCIR")
              }())

        // 15c. (Opcional) E2E contra el servidor LOCAL de prueba (login→token,
        // re-auth 401, proponer→confirmar con {previewId}, expiración). Lo
        // levanta el harness externo en 127.0.0.1:8765 (scripts/conexiones-qa-server.py).
        if ProcessInfo.processInfo.environment["BTODICTA_CONEXIONTEST_SRV"] == "1" {
            let modoSrvId = "qa-srv-modo"
            SecretosKeychain.guardar("clave-qa-123", cuenta: modoSrvId)
            ConexionesAuth.invalidar(modoSrvId)
            var conexSrv = ConexionAPI(
                baseURL: "http://127.0.0.1:8765",
                auth: AuthConexion(tipo: "login", usuario: "beto",
                                   loginRuta: "/login", loginFormato: "json",
                                   campoUsuario: "user", campoClave: "pass",
                                   campoToken: "data.access_token", ttlMinutos: 45),
                timeoutSegundos: 8, usarIA: false)
            var epSaldo = EndpointAPI(clave: "saldo", metodo: "GET", ruta: "/saldo",
                                      descripcion: "saldo actual")
            var epPreview = EndpointAPI(clave: "registrar", metodo: "POST", ruta: "/preview",
                                        descripcion: "propone un registro", esEscritura: true)
            epPreview.bodyPlantilla = #"{"nota":"{texto}"}"#
            var epConfirm = EndpointAPI(clave: "confirmar", metodo: "POST", ruta: "/confirm",
                                        descripcion: "confirma la propuesta", esEscritura: true)
            epConfirm.bodyPlantilla = #"{"previewId":"{previewId}"}"#
            conexSrv.endpoints = [epSaldo, epPreview, epConfirm]
            conexSrv.confirmEndpointId = "confirmar"
            conexSrv.previewEndpointId = "registrar"   // «registrar» = propuesta dry-run designada
            var modoSrv = Modo(id: modoSrvId, nombre: "QA Server", icono: "bolt",
                               base: "accion", esFijo: false, accion: "conexion")
            modoSrv.conexion = conexSrv

            var okProbar: (Bool, String)?
            ConexionesRunner.probar(conexSrv, modoId: modoSrvId) { okProbar = ($0, $1) }
            var limite = Date().addingTimeInterval(10)
            while okProbar == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            check("srv: login real correcto", okProbar?.0 == true)

            let rSaldo = esperar({ ConexionesRunner.ejecutar(modo: modoSrv, texto: "saldo",
                                                             ignorarInterruptor: true, completion: $0) },
                                 segundos: 10)
            check("srv: GET protegido con token", rSaldo?.ok == true && rSaldo?.mensaje.contains("42") == true)

            // El servidor caduca el token → la siguiente llamada debe re-loguear sola.
            var req = URLRequest(url: URL(string: "http://127.0.0.1:8765/caducar-token")!)
            req.httpMethod = "POST"
            var caducado = false
            URLSession.shared.dataTask(with: req) { _, r, _ in
                caducado = ((r as? HTTPURLResponse)?.statusCode ?? 0) == 200
            }.resume()
            limite = Date().addingTimeInterval(5)
            while !caducado, Date() < limite {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            let rReauth = esperar({ ConexionesRunner.ejecutar(modo: modoSrv, texto: "saldo",
                                                              ignorarInterruptor: true, completion: $0) },
                                  segundos: 10)
            check("srv: re-login transparente tras 401", rReauth?.ok == true && rReauth?.mensaje.contains("42") == true)

            // Dos fases feliz: propuesta del servidor → OK → confirmación con {previewId}.
            var confirmaciones = 0
            var propuestaVista = ""
            let rDosFases = esperar({ done in
                ConexionesRunner.ejecutar(modo: modoSrv, texto: "registrar la nota de hoy",
                                          ignorarInterruptor: true,
                                          confirmar: { _, detalles, responder in
                                              confirmaciones += 1
                                              propuestaVista = detalles.joined(separator: " ")
                                              responder(true)
                                          }, completion: done)
            }, segundos: 12)
            check("srv: dos fases publica con previewId LARGO (JWT ~2700 chars)",
                  rDosFases?.ok == true && rDosFases?.mensaje.contains("entryId") == true)
            check("srv: la propuesta se muestra LEGIBLE (no JSON crudo)",
                  propuestaVista.contains("actividad: nota de prueba")
                  && propuestaVista.contains("minutos: 60")
                  && !propuestaVista.contains("{"))
            check("srv: el token gigante no ensucia la propuesta",
                  !propuestaVista.contains("xxxxxxxxxx"))
            check("srv: exactamente una confirmación", confirmaciones == 1)

            // #2 post-review: una escritura que NO es la propuesta designada se
            // confirma LOCALMENTE antes de ejecutar (jamás dispara sin visto bueno).
            var conexPeligro = conexSrv
            conexPeligro.previewEndpointId = "registrar"   // solo «registrar» es dry-run
            conexPeligro.endpoints.append(EndpointAPI(clave: "borrar", metodo: "DELETE", ruta: "/preview",
                                                      descripcion: "borra algo", esEscritura: true))
            var modoPeligro = modoSrv; modoPeligro.conexion = conexPeligro
            var vioModal = false, ejecutoSinModal = true
            let rPeligro = esperar({ done in
                // forzamos la elección de «borrar» (no la propuesta) por clave dictada
                ConexionesRunner.ejecutar(modo: modoPeligro, texto: "borrar algo",
                                          ignorarInterruptor: true,
                                          confirmar: { _, _, responder in vioModal = true; responder(false) },
                                          completion: { r in ejecutoSinModal = r.ok; done(r) })
            }, segundos: 8)
            check("un DELETE que no es la propuesta pide confirmación local (no se ejecuta solo)",
                  vioModal && rPeligro?.ok == false && !ejecutoSinModal)

            // Expiración: la 1ª confirmación caduca el preview en el servidor →
            // el confirm devuelve 410 → re-propuesta → 2ª confirmación → publica.
            confirmaciones = 0
            let rExpira = esperar({ done in
                ConexionesRunner.ejecutar(modo: modoSrv, texto: "registrar otra nota",
                                          ignorarInterruptor: true,
                                          confirmar: { _, _, responder in
                                              confirmaciones += 1
                                              if confirmaciones == 1 {
                                                  var rq = URLRequest(url: URL(string: "http://127.0.0.1:8765/caducar-preview")!)
                                                  rq.httpMethod = "POST"
                                                  URLSession.shared.dataTask(with: rq) { _, _, _ in
                                                      DispatchQueue.main.async { responder(true) }
                                                  }.resume()
                                              } else {
                                                  responder(true)
                                              }
                                          }, completion: done)
            }, segundos: 15)
            check("srv: preview vencido re-propone y re-confirma",
                  rExpira?.ok == true && confirmaciones == 2)

            // FASE 4 — paso de rutina "conexion" de punta a punta: el modo QA
            // se registra de verdad en ModosStore (y se limpia al final).
            var lista = ModosStore.todos()
            lista.removeAll { $0.id == modoSrvId }
            lista.append(modoSrv)
            ModosStore.guardar(lista)
            var rutinaConexion = RutinaAgente(nombre: "QA conexión")
            rutinaConexion.pasos = [PasoRutinaAgente(tipo: "conexion", valor: modoSrvId)]
            rutinaConexion.devuelveResultado = true
            // El modo QA tiene escritura ⇒ la rutina que lo usa es externa.
            check("rutina con conexión de escritura = riesgo externo",
                  RutinasAgenteStore.riesgo(rutinaConexion) == .externo)
            // Una conexión SOLO lectura referenciada = reversible.
            var soloLectura = modoSrv
            soloLectura.id = "qa-srv-lectura"
            soloLectura.conexion?.endpoints = [epSaldo]
            var listaLect = ModosStore.todos()
            listaLect.removeAll { $0.id == soloLectura.id }
            listaLect.append(soloLectura); ModosStore.guardar(listaLect)
            var rutinaLectura = RutinaAgente(nombre: "QA lectura")
            rutinaLectura.pasos = [PasoRutinaAgente(tipo: "conexion", valor: soloLectura.id)]
            check("rutina con conexión de solo lectura = riesgo reversible",
                  RutinasAgenteStore.riesgo(rutinaLectura) == .reversible)
            listaLect = ModosStore.todos(); listaLect.removeAll { $0.id == soloLectura.id }
            ModosStore.guardar(listaLect)
            let rSim = esperar { RutinasAgenteRunner.ejecutar(rutina: rutinaConexion, texto: "saldo",
                                                              simular: true, completion: $0) }
            check("paso conexión simulado no llama la red",
                  rSim?.ok == true && rSim?.mensaje.contains("Llamaría") == true)
            let rPaso = esperar({ RutinasAgenteRunner.ejecutar(rutina: rutinaConexion, texto: "saldo",
                                                               simular: false, completion: $0) },
                                segundos: 12)
            check("rutina ejecuta la conexión real y consolida la salida",
                  rPaso?.ok == true && rPaso?.mensaje.contains("42") == true)
            var rutinaRota = RutinaAgente(nombre: "QA rota")
            rutinaRota.pasos = [PasoRutinaAgente(tipo: "conexion", valor: "modo-inexistente")]
            let rRota = esperar { RutinasAgenteRunner.ejecutar(rutina: rutinaRota, texto: "x",
                                                               simular: false, completion: $0) }
            check("paso con modo inexistente falla claro",
                  rRota?.ok == false && rRota?.mensaje.contains("ya no existe") == true)
            lista = ModosStore.todos(); lista.removeAll { $0.id == modoSrvId }
            ModosStore.guardar(lista)

            SecretosKeychain.borrar(cuenta: modoSrvId)
            ConexionesAuth.invalidar(modoSrvId)
        }

        // 16. (Opcional) plan con IA REAL configurada — exige red + proveedor.
        if ProcessInfo.processInfo.environment["BTODICTA_CONEXIONTEST_IA"] == "1" {
            var modoIA = modo; modoIA.conexion = conexIA
            var rIA: ResultadoPlanConexion?
            ConexionesIA.resolver(modo: modoIA, conexion: conexIA,
                                  texto: "dime el clima que hace en Baños de Agua Santa") { rIA = $0 }
            let limite = Date().addingTimeInterval(30)
            while rIA == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            let p = rIA.flatMap(esPlan)
            check("IA real arma el plan (endpoint clima + ciudad)",
                  p?.endpoint.clave == "clima"
                  && ((p?.valores["ciudad"] as? String)?.lowercased().contains("baños") ?? false))
            print("CONEXIONTEST ia: \(p.map { "\($0.endpoint.clave) \($0.valores["ciudad"] ?? "-") · \($0.resumen)" } ?? "sin plan")")

            // El caso REAL que falló en producción: narración con duración debe
            // ir a ESCRITURA, jamás a la consulta.
            var conexReg = conexIA
            var epRegistrar = EndpointAPI(clave: "registrar", metodo: "POST", ruta: "/reg",
                                          descripcion: "registrar el trabajo narrado", esEscritura: true)
            epRegistrar.bodyPlantilla = #"{"items":"{items}"}"#
            epRegistrar.variables = [VariableAPI(nombre: "items", tipo: "lista", requerida: true,
                                                 descripcion: "trabajos narrados con minutos")]
            var epHoy = EndpointAPI(clave: "hoy", metodo: "GET", ruta: "/entries",
                                    descripcion: "consultar lo ya registrado hoy", query: "date={hoy}")
            conexReg.endpoints = [epHoy, epRegistrar, epLista]
            var modoReg = modo; modoReg.conexion = conexReg
            modoReg.prompt = "Estructura el trabajo narrado como items para registrar."
            var rReg: ResultadoPlanConexion?
            ConexionesIA.resolver(modo: modoReg, conexion: conexReg,
                                  texto: "pon en mis tareas que hice pruebas del conector 15 minutos") { rReg = $0 }
            let limiteReg = Date().addingTimeInterval(30)
            while rReg == nil, Date() < limiteReg {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            let pReg = rReg.flatMap(esPlan)
            check("IA real: narración con duración elige ESCRITURA (no la consulta)",
                  pReg?.endpoint.clave == "registrar")
            print("CONEXIONTEST plan-real: \(pReg?.endpoint.clave ?? "sin plan / \(rReg.map { String(describing: $0) } ?? "-")")")

            // Prompt de vuelta con IA real: redacción con datos, sin inventos.
            var conexVuelta = conexIA
            conexVuelta.promptRespuesta = "Dime la ciudad, los grados y un consejo corto de abrigo si hace frío."
            var redactado: String??
            ConexionesIA.redactarRespuesta(modo: modoIA, conexion: conexVuelta,
                                           pedido: "dime el clima de Quito",
                                           respuestaAPI: "Quito: +16°C, humedad 92%") { redactado = $0 }
            let limiteR = Date().addingTimeInterval(30)
            while redactado == nil, Date() < limiteR {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            let rTexto = (redactado ?? nil) ?? ""
            check("IA real redacta la vuelta con los datos",
                  rTexto.lowercased().contains("quito")
                  && (rTexto.contains("16") || rTexto.lowercased().contains("dieciséis")
                      || rTexto.lowercased().contains("dieciseis")))
            print("CONEXIONTEST vuelta: \(String(rTexto.prefix(220)))")
        }

        // 17. (Opcional) GET real a una API pública — exige internet.
        if ProcessInfo.processInfo.environment["BTODICTA_CONEXIONTEST_RED"] == "1" {
            let rReal = esperar { done in
                ConexionesRunner.probar(modo.conexion!, modoId: "qa-red") { ok, msg in
                    done(.init(ok: ok, mensaje: msg))
                }
            }
            check("GET real a Open-Meteo responde", rReal?.ok == true)
            print("CONEXIONTEST red: \(String((rReal?.mensaje ?? "sin respuesta").prefix(160)))")
        }

        // 18. Export/import de modos (fase 6): round-trip SIN secretos.
        SecretosKeychain.guardar("clave-super-secreta-xyz", cuenta: "modo-exp-qa")
        var modoExp = Modo(id: "modo-exp-qa", nombre: "Conector Demo", icono: "bolt",
                           base: "accion", esFijo: false, accion: "conexion")
        modoExp.proveedorId = "custom:abc"; modoExp.modelo = "gpt-x"
        modoExp.conexion = ConexionAPI(
            baseURL: "https://api.ejemplo.com",
            auth: AuthConexion(tipo: "login", usuario: "persona@ejemplo.com"),
            endpoints: [EndpointAPI(clave: "reg", metodo: "POST", ruta: "/r", esEscritura: true,
                                    variables: [VariableAPI(nombre: "items", tipo: "lista", requerida: true)])],
            confirmEndpointId: "", promptRespuesta: "cuenta el resultado")
        let base0 = ModosStore.base[0]
        let paquete = ModosPortables.exportar([modoExp, base0])
        check("export produce un paquete", paquete != nil)
        let texto = paquete.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("export: la clave del Llavero NUNCA viaja",
              !texto.contains("clave-super-secreta-xyz"))
        check("export: el usuario del exportador se vacía", !texto.contains("persona@ejemplo.com"))
        check("export: la IA local del exportador se vacía",
              !texto.contains("custom:abc") && !texto.contains("gpt-x"))
        // Import a una biblioteca que YA tiene ese id → id nuevo, no pisa.
        let (validos, errores) = ModosPortables.importar(paquete ?? Data(),
                                                         existentes: [modoExp])
        check("import: modo base descartado, propio aceptado",
              validos.count == 1 && validos.first?.nombre == "Conector Demo")
        check("import: id en conflicto se renombra",
              validos.first?.id != "modo-exp-qa" && validos.first?.id.hasPrefix("propio-") == true)
        check("import: la conexión llega completa (endpoints/prompt)",
              validos.first?.conexion?.endpoints.first?.clave == "reg"
              && validos.first?.conexion?.promptRespuesta == "cuenta el resultado")
        check("import: llega sin usuario (lo pone el receptor)",
              validos.first?.conexion?.auth.usuario == "")
        check("import: necesita secreto se detecta",
              ModosPortables.necesitaSecreto(validos.first ?? base0) == true
              || (validos.first?.conexion?.auth.tipo == "login"))
        // URL insegura → rechazada con motivo.
        var modoMalo = modoExp; modoMalo.id = "malo"; modoMalo.conexion?.baseURL = "http://remoto.com"
        let paqMalo = ModosPortables.exportar([modoMalo])
        let (v2, e2) = ModosPortables.importar(paqMalo ?? Data(), existentes: [])
        check("import: URL insegura rechazada con motivo",
              v2.isEmpty && e2.contains { $0.contains("segura") })
        check("import: archivo basura da error claro",
              ModosPortables.importar(Data("no soy json".utf8), existentes: []).errores.isEmpty == false)
        _ = errores
        // Post-review: fixes de seguridad pinneados.
        // #1 path traversal: id importado SIEMPRE se regenera (no solo en colisión).
        var modoEvil = modoExp; modoEvil.id = "../../../../tmp/pwn"
        let paqEvil = ModosPortables.exportar([modoEvil])
        let (vEvil, _) = ModosPortables.importar(paqEvil ?? Data(), existentes: [])
        check("import: id malicioso se regenera (no path traversal)",
              vEvil.first?.id.hasPrefix("propio-") == true && !(vEvil.first?.id.contains("..") ?? true))
        // #7 export scrub: un secreto en un header NO viaja.
        var modoHdr = modoExp; modoHdr.id = "hdr"
        modoHdr.conexion?.headers = ["Authorization": "Bearer FUGA_SECRETA_999", "Accept": "application/json"]
        modoHdr.apps = ["Quipux"]; modoHdr.sitios = ["intranet.interna"]
        let paqHdr = ModosPortables.exportar([modoHdr])
        let textoHdr = paqHdr.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("export: secreto en header NO viaja",
              !textoHdr.contains("FUGA_SECRETA_999"))
        check("export: header no sensible se conserva", textoHdr.contains("Accept"))
        check("export: apps/sitios del entorno se vacían",
              !textoHdr.contains("Quipux") && !textoHdr.contains("intranet.interna"))
        SecretosKeychain.borrar(cuenta: "modo-exp-qa")

        print(fallos == 0 ? "CONEXIONTEST TODO OK" : "CONEXIONTEST ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}
