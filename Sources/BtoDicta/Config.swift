import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Configuración

struct Config {
    /// Dónde vive la configuración.
    ///
    /// **Por qué se puede desviar con una variable de entorno.**
    /// Los arneses de prueba escriben en estas mismas claves para comprobar el
    /// filtro, y uno de ellos dejó de restaurar cuando se le añadió una sección
    /// al final: cada pasada del QA sobrescribía la configuración real de quien
    /// tuviera el equipo delante. No se notó porque las listas todavía no tenían
    /// interfaz y nadie había escrito nada suyo en ellas — el día que la tuvieran,
    /// el QA le habría borrado lo que hubiera puesto.
    ///
    /// Restaurar al final es frágil: depende de que cada sección nueva se acuerde,
    /// y `exit()` no ejecuta un `defer`. Aquí se corta por lo sano — una prueba
    /// que apunta a otra carpeta no puede tocar el dato bueno aunque se olvide de
    /// todo.
    static let dir: URL = {
        if let desvio = ProcessInfo.processInfo.environment["BTODICTA_DIR"], !desvio.isEmpty {
            let u = URL(fileURLWithPath: (desvio as NSString).expandingTildeInPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        // Las pruebas unitarias corren en su propio proceso, sin desvío: escribían
        // en el registro real y hasta lo rotaban. El 21 de septiembre de 2026 una
        // rotación de otro proceso, a medianoche, sobrescribió el archivo de la
        // semana anterior con 29 líneas: una semana entera de registro perdida.
        if NSClassFromString("XCTestCase") != nil {
            let u = FileManager.default.temporaryDirectory
                .appendingPathComponent("btodicta-pruebas-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".btodicta")
    }()

    private static let lock = NSLock()
    private static let pasarelaTokenLock = NSLock()
    private static var cache: [String: Any]?

    private static func json() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return cache ?? [:] }
        cache = obj
        return obj
    }

    /// Lectura cruda de una clave, para los pocos sitios que guardan valores
    /// sin getter propio (estado de interfaz, no comportamiento).
    static func json0(_ clave: String) -> Any? { json()[clave] }

    static func hotkey() -> String { (json()["tecla"] as? String) ?? "fn" }
    static func maxSilence() -> TimeInterval { (json()["silencio_max_seg"] as? Double) ?? 120 }

    /// A partir de qué RMS se considera que alguien está hablando.
    ///
    /// Se compara contra el RMS **crudo**, no contra el valor del medidor. De
    /// fábrica 0,02, que sigue el mismo criterio que la bitácora
    /// (`bitacora_umbral_silencio` = 800 sobre 32768 ≈ 0,024) y está medido:
    /// una sala vacía da 0,0036, unas cinco veces por debajo.
    ///
    /// Subirlo hace falta oficina ruidosa; bajarlo, si se habla muy flojo. Un
    /// valor demasiado bajo devuelve el fallo que esto corrige: el dictado no se
    /// cierra nunca y se transcribe silencio, que se paga.
    /// 0 = automático (recomendado). Un valor > 0 lo fija a mano.
    ///
    /// **Por qué automático y no un número.** Un umbral fijo se eligió midiendo el
    /// ruido de una sala vacía (0,0036) y poniéndolo cinco veces por encima: 0,02.
    /// Al día siguiente, en una reunión real, la voz del usuario medía entre 0,010
    /// y 0,059 — por DEBAJO de ese umbral casi todo el tiempo. El dictado se
    /// cerraba a los quince segundos mientras él hablaba.
    ///
    /// La lección: la separación entre voz y ruido depende del micrófono, de la
    /// distancia y de la sala, y puede ser de apenas el doble. Ningún número fijo
    /// sirve para todos. Se mide el suelo de ruido de ESTA sesión y se decide
    /// contra él.
    static func umbralVozDictado() -> Double {
        let v = (json()["dictado_umbral_voz"] as? Double) ?? 0
        return v <= 0 ? 0 : min(max(v, 0.001), 0.5)
    }

    /// Cuántas veces por encima del suelo de ruido cuenta como voz. De fábrica 2.
    ///
    /// Medido con audio real: suelo 0,0036 y picos de voz 0,0112. Un factor de 3
    /// ya se los comía; con 2 quedan dentro y el ruido fuera.
    static func factorVozSobreRuido() -> Double {
        min(max((json()["dictado_factor_voz"] as? Double) ?? 2.0, 1.2), 10)
    }

    /// Cada cuántos minutos late el borde recordando que se está grabando.
    /// 0 = nunca. De fábrica 5.
    static func avisoGrabandoMin() -> Double {
        max((json()["dictado_aviso_min"] as? Double) ?? 5, 0)
    }

    /// ¿Se enciende el borde de la pantalla? De fábrica sí.
    ///
    /// Es lo único que se ve sin mirar. El contador del notch ya existía y no
    /// evitó ocho minutos de grabación en silencio.
    static func avisoGrabandoBorde() -> Bool {
        (json()["dictado_aviso_borde"] as? Bool) ?? true
    }

    /// Qué hacer al llegar al tope: `preguntar` (de fábrica), `parar` o `seguir`.
    static func alLlegarAlTope() -> String {
        let v = (json()["dictado_al_tope"] as? String) ?? "preguntar"
        return ["preguntar", "parar", "seguir"].contains(v) ? v : "preguntar"
    }

    /// Cuántos segundos se espera una respuesta antes de decidir solo.
    ///
    /// Si nadie contesta se PARA, que es el lado seguro: seguir grabando sin
    /// nadie delante es exactamente el fallo que esto corrige, y cuesta dinero.
    static func esperaEnElTopeSeg() -> Double {
        min(max((json()["dictado_tope_espera_seg"] as? Double) ?? 30, 5), 300)
    }

    /// Duraciones que ofrece «No mirar durante…» en el menú del icono, en
    /// minutos (spec 010). Parametrizable; se descartan las no positivas.
    static func opcionesPausaMin() -> [Double] {
        let v = ((json()["pausa_opciones_min"] as? [Double]) ?? [15, 30, 60, 120]).filter { $0 > 0 }
        return v.isEmpty ? [15, 30, 60, 120] : v
    }

    /// Red de seguridad del icono (spec 012). «No volver a avisar» de que el
    /// icono no se ve: lo pone el botón del propio aviso.
    static func iconoOcultoNoAvisar() -> Bool { (json()["icono_oculto_no_avisar"] as? Bool) ?? false }
    /// Segundos oculto sin interrupción antes de avisar. La barra se reconstruye
    /// un instante al arrancar o al cambiar de pantalla: eso no es un fallo.
    static func iconoOcultoGraciaSeg() -> Double {
        min(max((json()["icono_oculto_gracia_seg"] as? Double) ?? 30, 2), 600)
    }
    /// Cada cuántos minutos recordar que el modo reunión sigue puesto con el
    /// icono escondido. 0 = nunca.
    static func iconoOcultoRecordatorioMin() -> Double {
        let v = (json()["icono_oculto_recordatorio_min"] as? Double) ?? 30
        return v <= 0 ? 0 : min(max(v, 0.05), 24 * 60)
    }

    /// Tope absoluto de un dictado, en minutos. 0 = sin tope.
    ///
    /// El corte por silencio no basta: cualquier ruido por encima del umbral
    /// reinicia su cuenta, así que un golpe cada catorce segundos mantiene el
    /// dictado abierto indefinidamente. Esto es el freno que no depende de que
    /// haya o no ruido.
    static func maxDictadoMin() -> Double {
        max((json()["dictado_max_min"] as? Double) ?? 20, 0)
    }
    static func sounds() -> Bool { (json()["sonidos"] as? Bool) ?? true }
    static func escCancels() -> Bool { (json()["esc_cancela"] as? Bool) ?? true }
    static func duckMedia() -> Bool { (json()["atenuar_multimedia"] as? Bool) ?? true }
    static func duckVolume() -> Int { (json()["volumen_dictado"] as? Int) ?? 1 }
    static func postProcess() -> Bool { (json()["post_proceso"] as? Bool) ?? false }
    /// Qué IA hace el pulido (y la traducción). Cualquier proveedor de chat
    /// conectado, no solo Groq. Default "groq".
    static func pulidoProveedor() -> String { (json()["pulido_proveedor"] as? String) ?? "groq" }
    /// Cascada de FAILOVER de pulido: ids de proveedores en el ORDEN elegido por el
    /// usuario (1º intenta, si cae salta al siguiente). Vacío = automática (el
    /// proveedor de pulido primero, luego el resto de conectados).
    static func pulidoCascada() -> [String] { (json()["pulido_cascada"] as? [String]) ?? [] }
    /// Modelo ACTIVO elegido por el usuario para un proveedor de pulido (por id).
    /// Si no eligió, se usa el modelo por defecto del proveedor. Aplica a todos
    /// (Groq, OpenAI, OpenRouter, Gemini, locales…), no solo a los gateways.
    static func pulidoModelo(_ id: String) -> String? {
        guard let m = (json()["pulido_modelos"] as? [String: Any])?[id] as? String, !m.isEmpty else { return nil }
        return m
    }
    static func setPulidoModelo(_ id: String, _ modelo: String?) {
        var d = (json()["pulido_modelos"] as? [String: Any]) ?? [:]
        if let modelo, !modelo.isEmpty { d[id] = modelo } else { d[id] = nil }
        set("pulido_modelos", to: d)
    }
    /// Precio MANUAL puesto por el usuario para un (proveedor::modelo): USD por
    /// 1M tokens (entrada, salida). Tiene prioridad sobre el publicado/curado.
    static func precioManual(_ key: String) -> (Double, Double)? {
        guard let arr = (json()["precios_manuales"] as? [String: Any])?[key] as? [Double], arr.count == 2 else { return nil }
        return (arr[0], arr[1])
    }
    static func setPrecioManual(_ key: String, _ inOut: (Double, Double)?) {
        var d = (json()["precios_manuales"] as? [String: Any]) ?? [:]
        if let io = inOut { d[key] = [io.0, io.1] } else { d[key] = nil }
        set("precios_manuales", to: d)
    }
    static func customPrompt() -> String? {
        guard let s = json()["prompt_pulido"] as? String, !s.isEmpty else { return nil }
        return s
    }
    static func pausePlayback() -> Bool { (json()["pausar_multimedia"] as? Bool) ?? true }
    static func devMode() -> Bool { (json()["modo_desarrollo"] as? Bool) ?? false }
    /// Base por proveedor para textos cortos. El presupuesto adaptativo añade
    /// tiempo para dictados/contextos largos, hasta 120 s. Default 8.
    static func pulidoTimeout() -> Double { min(60, max(5, (json()["pulido_timeout_seg"] as? Double) ?? 8)) }
    static func showInDock() -> Bool { (json()["mostrar_en_dock"] as? Bool) ?? false }
    /// Al abrir la app, busca en silencio si hay versión nueva (GitHub) y la
    /// muestra abajo-izquierda ("Actualización disponible"). Parametrizable.
    static func buscarUpdateAlAbrir() -> Bool { (json()["buscar_update_al_abrir"] as? Bool) ?? true }
    /// Si encuentra actualización al abrir, la instala sola (sin pedir). OFF
    /// por defecto: reinstalar+reiniciar es una acción grande, es opt-in.
    static func autoactualizar() -> Bool { (json()["autoactualizar"] as? Bool) ?? false }
    /// Canal: auto sigue betas solo cuando la app instalada ya es beta; una
    /// versión estable permanece estable. "beta" incluye beta + estable.
    static func canalActualizaciones() -> String {
        let c = (json()["canal_actualizaciones"] as? String) ?? "auto"
        return ["auto", "estable", "beta"].contains(c) ? c : "auto"
    }
    /// Revisión tipo cron mientras BtoDicta permanece abierto. Solo consulta;
    /// no instala nada salvo que Autoactualizar esté activado explícitamente.
    static func actualizacionPeriodica() -> Bool { (json()["actualizacion_periodica"] as? Bool) ?? true }
    static func actualizacionIntervaloHoras() -> Double {
        min(24, max(1, (json()["actualizacion_intervalo_horas"] as? Double) ?? 6))
    }
    /// Muestra el aviso de privacidad cuando el pulido usa una IA de NUBE o un
    /// gateway de terceros (tu texto sale de tu Mac). Default ON. Parametrizable.
    static func avisoNube() -> Bool { (json()["aviso_privacidad_nube"] as? Bool) ?? true }
    /// Push-to-talk: mantener la tecla presionada graba, soltarla termina
    /// (en vez del modo toque-para-empezar / toque-para-terminar). Default OFF.
    static func pushToTalk() -> Bool { (json()["hold_para_hablar"] as? Bool) ?? false }
    /// Evita activaciones accidentales: en reposo exige dos pulsaciones rápidas.
    /// Para detener basta una. En push-to-talk, la segunda se mantiene presionada.
    static func doblePulsacionActivar() -> Bool { (json()["doble_pulsacion_activar"] as? Bool) ?? false }
    /// Preview EN VIVO en el notch (transcriptor nativo de Apple, macOS 26): mientras
    /// grabas, ves lo que vas diciendo. Solo visual; no toca la transcripción real.
    static func previewVivo() -> Bool { (json()["preview_vivo"] as? Bool) ?? true }
    /// Tiempo máximo entre el final de la primera pulsación y el inicio de la
    /// segunda. 0,45 s se siente como el doble clic estándar del Mac.
    static func doblePulsacionVentana() -> Double {
        min(1.0, max(0.25, (json()["doble_pulsacion_ventana"] as? Double) ?? 0.45))
    }
    /// Salvaguarda anti-inyección: si el texto PULIDO por la IA diverge
    /// groseramente del dictado (crece desmedido o mete comandos que el
    /// original no tenía), entrega el ORIGINAL. NUNCA bloquea, solo cae a tus
    /// palabras. Opt-in (default OFF) para no estorbar el uso normal.
    static func salvaguardaInyeccion() -> Bool { (json()["salvaguarda_inyeccion"] as? Bool) ?? false }
    /// Account ID de Cloudflare (va en la URL de Workers AI, como el chat).
    /// Sin él, el motor STT de Cloudflare no puede llamar (avisa en la UI).
    static func cloudflareAccountId() -> String { (json()["cloudflare_account_id"] as? String) ?? "" }
    /// Región de Azure AI Speech (ej. eastus) — va en la URL del endpoint.
    static func azureSpeechRegion() -> String { (json()["azure_speech_region"] as? String) ?? "" }
    /// Búsqueda SEMÁNTICA del historial (por significado, con embeddings). Opt-in
    /// (default OFF: necesita Ollama u otro motor de embeddings). Parametrizable:
    /// base + modelo + key. Default = Ollama local bge-m3 (gratis, privado).
    static func busquedaSemantica() -> Bool { (json()["busqueda_semantica"] as? Bool) ?? false }
    /// STT en vivo/streaming para motores de NUBE que lo soportan (hoy Deepgram
    /// por WebSocket). Opt-in (default OFF): si está apagado, esos motores
    /// transcriben por LOTES al soltar la tecla (como siempre). Additivo: no
    /// cambia el comportamiento del resto de la cascada.
    static func sttStreaming() -> Bool { (json()["stt_streaming"] as? Bool) ?? false }
    /// Motor de embeddings elegido ("ollama"|"openai"|"gemini"|"mistral"|"custom").
    /// Default Ollama (local), pero el usuario elige en Avanzado según lo que tenga.
    /// Motor de embeddings. Sin elección explícita: el INTERNO si su modelo ya está
    /// descargado (funciona sin instalar nada); si no, Ollama (comportamiento previo).
    static func embeddingProveedor() -> String {
        if let e = json()["embedding_proveedor"] as? String, !e.isEmpty { return e }
        return EmbeddingServer.disponible ? "interno" : "ollama"
    }
    /// Modo POR DEFECTO (sticky): al que se vuelve tras cada dictado si modoRevertir.
    /// Se fija en Ajustes → Modos ("Poner por defecto"). Default "dictado".
    static func modoDefecto() -> String { (json()["modo_defecto"] as? String) ?? "dictado" }
    /// Modo activo AHORA (qué hacer con lo dictado). Transitorio: el notch/menú lo
    /// cambia al vuelo; si modoRevertir está ON, vuelve al defecto tras cada dictado.
    static func modoActivo() -> String { (json()["modo_activo"] as? String) ?? modoDefecto() }
    /// El modo elegido en caliente (notch/menú) es de UN SOLO USO: tras dictar,
    /// vuelve al modo por defecto. Default ON (decisión de producto). Apágalo = sticky.
    static func modoRevertir() -> Bool { (json()["modo_revertir"] as? Bool) ?? true }
    /// Idiomas que el usuario agregó al selector de "Traducir" (además de los base).
    static func idiomasPersonales() -> [String] { (json()["idiomas_personales"] as? [String]) ?? [] }
    /// Activar un modo por VOZ: si el dictado empieza con la frase de un modo
    /// (ej. "modo tarea comprar la comida"), se usa ese modo y se quita la frase.
    /// Default ON (los modos base traen su frase; edítalas o vacíalas en Modos).
    static func modoPorVoz() -> Bool { (json()["modo_por_voz"] as? Bool) ?? true }
    /// Activar un modo por CONTEXTO: si estás en una app (ej. Outlook) o un sitio
    /// web (ej. tu intranet) que un modo declara, ese modo se aplica solo a ese dictado.
    /// Default ON (inofensivo: los modos base no traen apps/sitios hasta que los pongas).
    static func modoPorContexto() -> Bool { (json()["modo_por_contexto"] as? Bool) ?? true }
    /// Inventaría las apps instaladas para "modo abrir aplicación Word…". Puede
    /// apagarse sin afectar los modos de acción fijos. Default ON.
    static func modoAplicaciones() -> Bool { (json()["modo_aplicaciones"] as? Bool) ?? true }
    /// Tras abrir la app, intenta pegar solo si esa app llegó a ser la frontal.
    /// Nunca pulsa Enter ni envía el contenido. Default ON.
    static func aplicacionPegarAutomatico() -> Bool {
        (json()["aplicacion_pegar_automatico"] as? Bool) ?? true
    }
    /// Word/TextEdit/LibreOffice: crea un documento nuevo antes de pegar. En las
    /// demás apps se conserva la ventana actual. Default ON.
    static func aplicacionNuevoDocumento() -> Bool {
        (json()["aplicacion_nuevo_documento"] as? Bool) ?? true
    }
    /// WhatsApp: usar los Contactos de macOS además de la lista importada. Default ON.
    static func waUsarContactosMac() -> Bool { (json()["wa_usar_contactos_mac"] as? Bool) ?? true }
    /// Glosario INTELIGENTE: en el pulido, manda solo los términos afines al dictado
    /// (con embeddings) en vez de los 80 → prompt corto = más rápido. Default OFF (opt-in).
    static func glosarioInteligente() -> Bool { (json()["glosario_inteligente"] as? Bool) ?? false }
    /// Reconocimiento SEMÁNTICO de modos por voz (capa 3, embeddings): entiende el
    /// llamado del modo aunque lo digas de mil formas. Default OFF (opt-in).
    static func modoSemantico() -> Bool { (json()["modo_semantico"] as? Bool) ?? false }
    /// Modo EN VIVO: al decir "modo X" mientras hablas, el notch cambia YA de nombre y
    /// color (feedback de "te escuché") sin esperar a soltar la tecla. Default ON.
    static func modoVivo() -> Bool { (json()["modo_vivo"] as? Bool) ?? true }
    /// Capa GRAMATICAL: reconoce el verbo del modo en cualquier conjugación
    /// ("tradúceme esto", "quiero traducir…"). Ambiguo → pregunta con mini-modal.
    static func modoGramatical() -> Bool { (json()["modo_gramatical"] as? Bool) ?? true }
    /// Tiempo para leer una propuesta expandida. Al vencer, NO cancela: continúa
    /// con el modo normal, igual que pulsar X.
    static func modoConfirmacionSegundos() -> Double {
        min(30, max(6, (json()["modo_confirmacion_seg"] as? Double) ?? 14))
    }
    /// Ajuste local y acotado del umbral semántico a partir de los sí/no del modal.
    static func modoAutoMejora() -> Bool { (json()["modo_auto_mejora"] as? Bool) ?? true }
    /// Diferencia mínima entre el mejor modo semántico y el segundo para no adivinar.
    static func modoSemanticoMargen() -> Double {
        min(0.20, max(0.02, (json()["modo_sem_margen"] as? Double) ?? 0.06))
    }
    /// Último árbitro opcional: una IA activa interpreta solo la zona de intención
    /// cuando reglas y embeddings no pueden decidir. Nunca bloquea el dictado.
    static func modoIAEnrutamiento() -> Bool { (json()["modo_ia_enrutamiento"] as? Bool) ?? true }
    /// Vacío = la IA global de Pulido. Si el proveedor elegido deja de estar
    /// conectado, cae de forma transparente a la global o no usa IA.
    static func modoIAProveedor() -> String { (json()["modo_ia_proveedor"] as? String) ?? "" }
    static func modoIATimeout() -> Double {
        min(8, max(1.5, (json()["modo_ia_timeout"] as? Double) ?? 3.0))
    }
    static func modoIAPalabras() -> Int {
        min(30, max(6, (json()["modo_ia_palabras"] as? Int) ?? 16))
    }
    /// Una pausa al inicio confirma que terminó la orden "modo X", pero NO detiene
    /// la grabación. Permite continuar hablando naturalmente tras pensar. Default ON.
    static func modoVivoPausa() -> Bool { (json()["modo_vivo_pausa"] as? Bool) ?? true }
    static func modoVivoPausaSegundos() -> Double {
        min(4, max(0.8, (json()["modo_vivo_pausa_seg"] as? Double) ?? 2.0))
    }
    /// Límite de la zona-comando en parciales. El resto nunca se examina como orden.
    static func modoVivoPalabras() -> Int {
        min(14, max(3, (json()["modo_vivo_palabras"] as? Int) ?? 8))
    }
    /// Cuántas palabras del inicio se analizan como "zona-comando" (parametrizable).
    static func modoSemanticoPalabras() -> Int { (json()["modo_sem_palabras"] as? Int) ?? 5 }
    /// Umbral de cercanía (coseno) para aceptar un modo: más alto = más estricto.
    static func modoSemanticoUmbral() -> Double { (json()["modo_sem_umbral"] as? Double) ?? 0.5 }
    /// Registro detallado del subsistema de modos (~/.btodicta/logs/modos.jsonl). Default ON.
    static func logModos() -> Bool { (json()["log_modos"] as? Bool) ?? true }
    /// Apple Speech nativo (STT on-device, macOS 26+): idioma BCP-47. es-EC se
    /// mapea al español más cercano. Parametrizable.
    static func appleSpeechIdioma() -> String { (json()["apple_speech_idioma"] as? String) ?? "es-EC" }

    // TTS (texto→voz). Default OFF (opt-in).
    static func ttsActivo() -> Bool { (json()["tts_activo"] as? Bool) ?? false }
    static func ttsVoz() -> String { (json()["tts_voz"] as? String) ?? "" }
    static func ttsVelocidad() -> Double { (json()["tts_velocidad"] as? Double) ?? 0.5 }

    // Tareas y notas locales: avisos sin nube. Las fechas se guardan con cada
    // ítem; el reloj y los resúmenes son completamente opcionales.
    static func tareasAvisos() -> Bool { (json()["tareas_avisos"] as? Bool) ?? true }
    static func tareasAvisosSonido() -> Bool { (json()["tareas_avisos_sonido"] as? Bool) ?? true }
    static func tareasAvisosVoz() -> Bool { (json()["tareas_avisos_voz"] as? Bool) ?? false }
    static func tareasAvisarNotas() -> Bool { (json()["tareas_avisar_notas"] as? Bool) ?? false }
    static func tareasResumenManana() -> Bool { (json()["tareas_resumen_manana"] as? Bool) ?? false }
    static func tareasResumenTarde() -> Bool { (json()["tareas_resumen_tarde"] as? Bool) ?? false }
    static func tareasResumenMananaMinutos() -> Int {
        min(1439, max(0, (json()["tareas_resumen_manana_min"] as? Int) ?? 510)) // 08:30
    }
    static func tareasResumenTardeMinutos() -> Int {
        min(1439, max(0, (json()["tareas_resumen_tarde_min"] as? Int) ?? 1200)) // 20:00
    }
    static func tareasResumenIncluirSinFecha() -> Bool {
        (json()["tareas_resumen_sin_fecha"] as? Bool) ?? true
    }
    /// Reescribe el resumen determinista con la IA de pulido seleccionada. Es
    /// opt-in porque puede enviar hasta tres títulos de tareas al proveedor; si
    /// no hay IA o tarda, el reloj entrega el resumen local sin bloquearse.
    static func tareasResumenIA() -> Bool {
        (json()["tareas_resumen_ia"] as? Bool) ?? false
    }
    static func tareasResumenUltimo(_ periodo: String) -> String {
        (json()["tareas_resumen_ultimo_\(periodo)"] as? String) ?? ""
    }
    // Recordatorio PERIÓDICO de pendientes (cada N horas): resume solo lo que
    // falta, con notificación + voz. Reutiliza la triple salida existente.
    static func tareasResumenPeriodico() -> Bool { (json()["tareas_resumen_periodico"] as? Bool) ?? true }
    static func tareasResumenPeriodicoHoras() -> Int {
        min(24, max(1, (json()["tareas_resumen_periodico_horas"] as? Int) ?? 1))
    }
    static func tareasResumenPeriodicoVoz() -> Bool { (json()["tareas_resumen_periodico_voz"] as? Bool) ?? true }
    static func tareasResumenPeriodicoUltimo() -> Double { (json()["tareas_resumen_periodico_ultimo"] as? Double) ?? 0 }
    // Horas quietas: durante la ventana no suena ni habla (la notificación
    // escrita sí queda). Minutos del día; la ventana puede cruzar medianoche.
    static func tareasQuietasActivo() -> Bool { (json()["tareas_quietas_activo"] as? Bool) ?? true }
    static func tareasQuietasDesde() -> Int { min(1439, max(0, (json()["tareas_quietas_desde"] as? Int) ?? 1320)) } // 22:00
    static func tareasQuietasHasta() -> Int { min(1439, max(0, (json()["tareas_quietas_hasta"] as? Int) ?? 420)) }  // 07:00
    /// Cerebro del Modo Agente: "local" (IA configurada en BtoDicta) | "hermes" |
    /// "codex" (cuenta ChatGPT delegada al cliente oficial Codex). Parametrizable.
    static func agenteMotor() -> String { (json()["agente_motor"] as? String) ?? "local" }
    /// Ruta del binario hermes (vacío = autodetectar ~/.local/bin/hermes).
    static func hermesBin() -> String { (json()["hermes_bin"] as? String) ?? "" }

    /// El Modo Agente PEGA su respuesta donde estés (como el dictado). Default OFF:
    /// el agente es conversacional (notch + voz); actívalo si quieres el texto pegado.
    /// A futuro será inteligente según la intención (pedir texto → pega; preguntar → no).
    static func agentePega() -> Bool { (json()["agente_pega"] as? Bool) ?? false }

    /// Ruta explícita "dicta/escribe/corrige esto" dentro del Asistente. Es
    /// independiente de `agentePega`: una respuesta conversacional no se pega
    /// por defecto, pero una orden de dictado sí tiene como destino el campo activo.
    static func agenteDictadoAsistido() -> Bool {
        (json()["agente_dictado_asistido"] as? Bool) ?? true
    }
    static func agenteDictadoPulir() -> Bool {
        (json()["agente_dictado_pulir"] as? Bool) ?? true
    }
    static func agenteDictadoPegar() -> Bool {
        (json()["agente_dictado_pegar"] as? Bool) ?? true
    }
    static func agenteDictadoCopiar() -> Bool {
        (json()["agente_dictado_copiar"] as? Bool) ?? true
    }
    static func agenteDictadoAcuse() -> String {
        let s = (json()["agente_dictado_acuse"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "Dímelo." : String(s.prefix(80))
    }

    // MARK: Núcleo del asistente por voz

    /// El núcleo orquestador es aditivo: apagado, Agente conserva el camino de chat
    /// anterior y Dictado/Modos no cambian. Encendido por defecto para instalaciones
    /// nuevas; todas las herramientas tienen su propio interruptor.
    static func agenteNucleoActivo() -> Bool { (json()["agente_nucleo_activo"] as? Bool) ?? true }
    /// Nombre/presencia que usa al hablar. No está ligado a una voz concreta: puede
    /// llamarse Bto, Jarvis o como decida el usuario.
    static func agenteNombre() -> String {
        let s = (json()["agente_nombre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "Bto" : s
    }
    /// Personalidad libre y local. Se añade al prompt únicamente en Modo Agente.
    static func agentePersonalidad() -> String {
        (json()["agente_personalidad"] as? String)
            ?? "Cálido, directo, práctico y respetuoso. Habla en español natural y con respuestas breves."
    }
    /// Frases que invocan al asistente dentro de un dictado y, únicamente si el
    /// usuario activa la opción separada, también desde la escucha manos libres.
    static func agenteActivadores() -> [String] {
        let nombre = agenteNombre().trimmingCharacters(in: .whitespacesAndNewlines)
        let predeterminados = ["oye \(nombre)", "\(nombre) escucha"]
        let a = (json()["agente_activadores"] as? [String]) ?? predeterminados
        // Una sola palabra ("oye", solo el nombre, etc.) aparece con demasiada
        // frecuencia en un dictado normal. Se conserva en el JSON para que el
        // usuario no pierda su configuración, pero no puede despertar al agente.
        return FrasesConfigurables.activadoresSeguros(a)
    }
    /// Escucha manos libres en reposo. Es deliberadamente opt-in: al activarla
    /// macOS mantiene el indicador de micrófono visible. Todo el reconocimiento
    /// previo a la frase se procesa localmente y no se guarda.
    static func agenteActivacionReposo() -> Bool {
        (json()["agente_activacion_reposo"] as? Bool) ?? false
    }
    /// Cuando la escucha local ya ocupa el micrófono, macOS puede no entregar
    /// «Oye Siri» al detector nativo. Este respaldo reconoce únicamente
    /// «Oye Siri» + el nombre dinámico del asistente y abre el mismo turno; no
    /// intercepta órdenes generales dirigidas a Siri.
    static func agenteCompatibilidadSiriLocal() -> Bool {
        (json()["agente_siri_compatibilidad_local"] as? Bool) ?? true
    }
    /// Modo avanzado y opcional. Apagado por defecto: la frase funciona como
    /// un timbre, BtoDicta acusa recibo y recién entonces escucha la orden.
    /// Encendido conserva el gesto histórico de frase + orden en una sola toma.
    static func agenteActivacionOrdenCorrida() -> Bool {
        (json()["agente_activacion_orden_corrida"] as? Bool) ?? false
    }
    /// Silencio continuo que confirma que la frase terminó. Apple no siempre
    /// publica `isFinal` en dictado progresivo, por lo que esta pausa acústica
    /// es el respaldo determinista. Parametrizable para cada forma de hablar.
    static func agenteActivacionEsperaAcuse() -> Double {
        min(3.0, max(0.8,
                     (json()["agente_activacion_espera_acuse_seg"] as? Double) ?? 2.0))
    }
    /// Segundos de PCM conservados únicamente en RAM. Permiten que una orden
    /// corrida (frase configurada + orden) no pierda sus primeras palabras durante el
    /// traspaso Apple Speech → Recorder. Nunca se escriben antes de despertar.
    static func agenteActivacionPrebuffer() -> Double {
        min(8, max(2, (json()["agente_activacion_prebuffer_seg"] as? Double) ?? 4))
    }
    /// Acuse específico al despertar. Es independiente de las respuestas finales
    /// del Agente: puede apagarse o personalizarse sin alterar sus acciones.
    static func agenteActivacionAcuse() -> Bool {
        (json()["agente_activacion_acuse"] as? Bool) ?? true
    }
    /// "texto" | "texto_voz" | "voz". Si el formato incluye voz pero TTS no
    /// está activo, degrada de forma visible a texto para no dejar al usuario sin señal.
    static func agenteActivacionAcuseFormato() -> String {
        let guardado = json()["agente_activacion_acuse_formato"] as? String
        if let guardado, ["texto", "texto_voz", "voz"].contains(guardado) {
            return guardado
        }
        return "texto"
    }
    static func agenteActivacionAcuses() -> [String] {
        let nuevos = json()["agente_activacion_acuses"] as? [String]
        let legado = (json()["agente_activacion_acuse_texto"] as? String).map { [$0] }
        let base = nuevos ?? legado ?? ["Te escucho.", "Dímelo.", "Cuéntame.", "Aquí estoy."]
        var vistos = Set<String>()
        return base.compactMap { valor -> String? in
            let limpio = String(valor.replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(90))
            let firma = PerfilAgente.normalizar(limpio)
            guard !limpio.isEmpty, !firma.isEmpty, vistos.insert(firma).inserted else { return nil }
            return limpio
        }.prefix(12).map { $0 }
    }
    static func agenteActivacionAcuseTexto() -> String {
        agenteActivacionAcuses().first ?? "Te escucho."
    }
    static func agenteActivacionAcuseElegido() -> String {
        agenteActivacionAcuses().randomElement() ?? "Te escucho."
    }
    static func agenteActivacionAcuseConVoz() -> Bool {
        agenteActivacionAcuse()
            && canalesAcuse(formato: agenteActivacionAcuseFormato(),
                            ttsDisponible: ttsActivo()).voz
    }
    static func agenteActivacionAcuseMuestraTexto() -> Bool {
        guard agenteActivacionAcuse() else { return false }
        return canalesAcuse(formato: agenteActivacionAcuseFormato(),
                            ttsDisponible: ttsActivo()).texto
    }
    /// Capacidad local para la URL que abre un turno desde Atajos/Siri. No es
    /// una credencial de nube, pero impide que otra app o una web invoque la
    /// ruta genérica y encienda el Recorder. Se genera una sola vez por Mac y
    /// queda dentro de config.json (0600).
    static func agentePasarelaSiriToken() -> String {
        pasarelaTokenLock.lock(); defer { pasarelaTokenLock.unlock() }
        if let existente = json()["agente_pasarela_siri_token"] as? String,
           existente.count >= 32,
           existente.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            return existente
        }
        let nuevo = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        asegurarDirSeguro()
        set("agente_pasarela_siri_token", to: nuevo)
        return nuevo
    }
    /// Política pura compartida por producción y QA. Voz solicitada sin TTS
    /// degrada explícitamente a texto; ninguna combinación válida queda muda.
    static func canalesAcuse(formato: String, ttsDisponible: Bool)
        -> (texto: Bool, voz: Bool) {
        switch formato {
        case "texto_voz": return (true, ttsDisponible)
        case "voz": return (ttsDisponible ? false : true, ttsDisponible)
        default: return (true, false)
        }
    }
    /// Tres niveles: consultivo (todo pregunta), asistido (lecturas/aperturas seguras
    /// automáticas) y autónomo (también cambios locales reversibles). Enviar, comprar,
    /// borrar o publicar SIEMPRE exige confirmación, incluso en autónomo.
    static func agenteAutonomia() -> String {
        let s = (json()["agente_autonomia"] as? String) ?? "asistido"
        return ["consultivo", "asistido", "autonomo"].contains(s) ? s : "asistido"
    }
    /// Memoria conversacional corta, 100% local y acotada.
    static func agenteMemoriaActiva() -> Bool { (json()["agente_memoria_activa"] as? Bool) ?? true }
    /// La memoria siempre se almacena localmente. Este interruptor separado decide
    /// si también se adjunta como contexto al cerebro elegido (que puede ser nube).
    static func agenteMemoriaContextoIA() -> Bool { (json()["agente_memoria_contexto_ia"] as? Bool) ?? true }
    static func agenteMemoriaTurnos() -> Int {
        min(30, max(1, (json()["agente_memoria_turnos"] as? Int) ?? 8))
    }
    /// Si el cerebro elegido falla, prueba los respaldos disponibles.
    /// Conserva la clave histórica para no romper configuraciones existentes.
    static func agenteFallbackCerebro() -> Bool { (json()["agente_fallback_local"] as? Bool) ?? true }
    /// IA de chat exclusiva del agente. Vacío = la cascada global de pulido.
    static func agenteIAProveedor() -> String { (json()["agente_ia_proveedor"] as? String) ?? "" }
    static func agenteIAModelo() -> String { (json()["agente_ia_modelo"] as? String) ?? "" }

    /// Acuse breve del asistente para que una acción o una pregunta nunca quede
    /// silenciosa. Solo se aplica dentro de Modo Agente / una frase de presencia;
    /// Dictado y los Modos usados directamente conservan su comportamiento.
    static func agenteRespuestaActiva() -> Bool {
        (json()["agente_respuesta_activa"] as? Bool) ?? true
    }
    /// "texto" | "texto_voz". La voz usa exactamente la cascada TTS elegida por
    /// el usuario. Si TTS está apagado/no disponible, degrada a texto sin bloquear.
    static func agenteRespuestaFormato() -> String {
        let guardado = json()["agente_respuesta_formato"] as? String
        if let guardado, ["texto", "texto_voz"].contains(guardado) { return guardado }
        return ttsActivo() ? "texto_voz" : "texto"
    }
    static func agenteRespuestaConVoz() -> Bool {
        agenteRespuestaActiva() && agenteRespuestaFormato() == "texto_voz" && ttsActivo()
    }

    // Herramientas: cada una puede apagarse sin impedir que el agente responda.
    static func agenteHerramientaMusica() -> Bool { (json()["agente_tool_musica"] as? Bool) ?? true }
    static func agenteHerramientaCalendario() -> Bool { (json()["agente_tool_calendario"] as? Bool) ?? true }
    static func agenteHerramientaRecordatorios() -> Bool { (json()["agente_tool_recordatorios"] as? Bool) ?? true }
    static func agenteHerramientaArchivos() -> Bool { (json()["agente_tool_archivos"] as? Bool) ?? true }
    static func agenteHerramientaAplicaciones() -> Bool { (json()["agente_tool_aplicaciones"] as? Bool) ?? true }
    static func agenteHerramientaComunicaciones() -> Bool { (json()["agente_tool_comunicaciones"] as? Bool) ?? true }
    static func agenteHerramientaAtajos() -> Bool { (json()["agente_tool_atajos"] as? Bool) ?? false }
    static func agenteHerramientaCapturas() -> Bool { (json()["agente_tool_capturas"] as? Bool) ?? true }
    static func agenteHerramientaClima() -> Bool { (json()["agente_tool_clima"] as? Bool) ?? true }
    static func agenteHerramientaVolumen() -> Bool { (json()["agente_tool_volumen"] as? Bool) ?? true }
    /// Cantidad de puntos que cambia una orden relativa sin cifra, por ejemplo
    /// «sube el volumen». Un porcentaje explícito siempre tiene prioridad.
    static func agenteVolumenPaso() -> Int {
        min(50, max(1, (json()["agente_volumen_paso"] as? Int) ?? 10))
    }
    static func agenteHerramientaNotasApple() -> Bool {
        (json()["agente_tool_notas_apple"] as? Bool) ?? true
    }
    /// Conexiones API definidas por el usuario (acción "conexion"). Feature
    /// nueva: APAGADA por defecto hasta que el usuario la encienda.
    static func agenteHerramientaConexiones() -> Bool {
        (json()["agente_tool_conexiones"] as? Bool) ?? false
    }
    /// Router global por IA: cuando el ruteo determinista del asistente no
    /// encuentra nada concreto, la IA decide sobre el catálogo completo a qué
    /// capacidad cae. Degradable: sin IA/red sigue el cerebro de siempre.
    static func routerGlobalActivo() -> Bool { (json()["router_global_activo"] as? Bool) ?? true }
    /// Segundos para decidir el visto bueno de una conexión. Una propuesta
    /// larga (tabla de actividades) NECESITA lectura: mucho más generoso que
    /// la confirmación normal de modos, y configurable.
    static func conexionConfirmacionSegundos() -> Double {
        min(600, max(20, (json()["conexion_confirmacion_segundos"] as? Double)
            ?? (json()["conexion_confirmacion_segundos"] as? Int).map(Double.init) ?? 120))
    }
    /// Cuando una consulta no contiene ciudad, pide una ubicación puntual a
    /// Core Location. Nunca habilita seguimiento continuo ni persiste coordenadas.
    static func climaUsarUbicacionActual() -> Bool {
        (json()["clima_ubicacion_actual"] as? Bool) ?? true
    }
    /// Respaldo opcional si el usuario desactiva/deniega ubicación. Se geocodifica
    /// al consultar y no contiene coordenadas ni credenciales.
    static func climaUbicacionPredeterminada() -> String {
        String(((json()["clima_ubicacion_predeterminada"] as? String) ?? "")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
    }
    /// Vacío conserva la carpeta predeterminada de la cuenta predeterminada.
    /// Se limita porque termina como un literal escapado del diccionario oficial
    /// de automatización de Notes, nunca como código AppleScript.
    static func notasAppleCarpeta() -> String {
        String(((json()["notas_apple_carpeta"] as? String) ?? "")
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }
    static func notasAppleCrearCarpeta() -> Bool {
        (json()["notas_apple_crear_carpeta"] as? Bool) ?? true
    }
    static func notasAppleMostrarCreada() -> Bool {
        (json()["notas_apple_mostrar"] as? Bool) ?? true
    }
    /// Siri no ofrece una API pública para inyectarle órdenes arbitrarias. BtoDicta
    /// usa el puente oficial de Atajos y le pasa el texto a este atajo del usuario.
    static func agenteAtajoApple() -> String { (json()["agente_atajo_apple"] as? String) ?? "" }

    // Captura/grabación de pantalla. Cada salida es visible y reversible; una
    // ubicación dictada solo puede ser una de estas carpetas conocidas o el
    // selector nativo, nunca una ruta arbitraria interpretada por voz.
    static func capturaDestino() -> String { (json()["captura_destino"] as? String) ?? "escritorio" }
    static func capturaGuardarArchivo() -> Bool { (json()["captura_guardar"] as? Bool) ?? true }
    static func capturaCopiarPortapapeles() -> Bool { (json()["captura_copiar"] as? Bool) ?? false }
    static func capturaAbrirAlTerminar() -> Bool { (json()["captura_abrir"] as? Bool) ?? false }
    static func capturaGrabarMicrofono() -> Bool { (json()["captura_microfono"] as? Bool) ?? false }
    static func capturaMostrarClics() -> Bool { (json()["captura_mostrar_clics"] as? Bool) ?? false }
    /// Política explícita para una captura destinada a WhatsApp. Migra el toggle
    /// antiguo sin convertirlo jamás en autoenvío.
    static func capturaWhatsAppPolitica() -> PoliticaWhatsAppCaptura {
        if let s = json()["captura_whatsapp_accion"] as? String,
           let p = PoliticaWhatsAppCaptura(rawValue: s) { return p }
        if let antiguo = json()["captura_whatsapp_pegar"] as? Bool {
            return antiguo ? .preparar : .portapapeles
        }
        return .preparar
    }

    /// Compatibilidad para código/configuración anterior.
    static func capturaWhatsAppPegarAutomatico() -> Bool {
        capturaWhatsAppPolitica() != .portapapeles
    }
    /// 0 = la persona detiene la grabación desde BtoDicta (una pulsación de
    /// la tecla de dictado o la opción visible del menú).
    /// Un valor positivo se usa solo cuando la orden no trae una duración propia.
    static func capturaDuracionPredeterminada() -> Int {
        min(3_600, max(0, (json()["captura_duracion_predeterminada"] as? Int) ?? 0))
    }
    /// Una grabación manual cierra fragmentos periódicos para que un fallo no
    /// arriesgue todo el video. 60…1800 s; recomendado: 5 min.
    static func capturaSegmentoSegundos() -> Int {
        min(1_800, max(60, (json()["captura_segmento_segundos"] as? Int) ?? 300))
    }

    // Cuenta ChatGPT mediante el cliente oficial Codex. BtoDicta nunca lee las
    // credenciales de Codex. La ruta vacía se autodetecta y el timeout es finito.
    static func agenteCodexBin() -> String { (json()["agente_codex_bin"] as? String) ?? "" }
    /// Modelo usado por TODAS las capacidades de texto delegadas a la cuenta
    /// ChatGPT (asistente, Modos, traducción y pulido). "automatico" deja que
    /// el cliente oficial Codex elija uno permitido por el plan para esa tarea.
    static func codexCuentaModelo() -> String {
        let s = ((json()["codex_cuenta_modelo"] as? String) ?? "automatico")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let n = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return s.isEmpty || n == "automatico" ? "automatico" : s
    }
    /// Esfuerzo del modelo Codex: automático | low | medium | high | xhigh.
    /// Max/Ultra no se ofrecen en la ruta de voz porque disparan latencia y
    /// orquestación innecesaria para una transformación breve de texto.
    static func codexCuentaEsfuerzo() -> String {
        let s = ((json()["codex_cuenta_esfuerzo"] as? String) ?? "automatico")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["low", "medium", "high", "xhigh"].contains(s) ? s : "automatico"
    }
    static func agenteCodexTimeout() -> Double {
        min(180, max(15, (json()["agente_codex_timeout"] as? Double) ?? 60))
    }

    /// Cascada del modo Música. Los no disponibles se saltan; los proveedores web
    /// mantienen un respaldo que funciona aunque no haya ninguna app instalada.
    static func musicaCascada() -> [String] {
        let a = (json()["musica_cascada"] as? [String])
            ?? ["apple_music", "spotify", "btodicta_youtube", "youtube_music", "youtube"]
        return a.isEmpty ? ["apple_music", "btodicta_youtube", "youtube_music", "youtube"] : a
    }
    static func musicaIntentarReproducir() -> Bool { (json()["musica_intentar_reproducir"] as? Bool) ?? true }
    /// Qué hace “pon música” sin artista/título: una pista distinta al azar
    /// (predeterminado) o reanudar exactamente lo último que sonaba.
    static func musicaSinConsulta() -> String {
        let s = ((json()["musica_sin_consulta"] as? String) ?? "aleatorio").lowercased()
        return s == "reanudar" ? "reanudar" : "aleatorio"
    }
    /// BtoDicta incluye este Atajo ya construido. macOS requiere que cada usuario
    /// confirme su importación una vez; después puede reemplazarlo o desactivarlo.
    static func musicaAtajoApple() -> String {
        (json()["musica_atajo_apple"] as? String) ?? AppleAtajos.nombreMusicaIncluido
    }
    static func musicaAtajoPrimero() -> Bool { (json()["musica_atajo_primero"] as? Bool) ?? false }
    /// Busca el primer resultado del catálogo público y lo selecciona en la app
    /// Música con Accesibilidad. Sin permiso/red, continúa por el failover.
    static func musicaCatalogoAutomatico() -> Bool {
        (json()["musica_catalogo_automatico"] as? Bool) ?? true
    }
    /// Reproductor de YouTube embebido dentro de BtoDicta. La intención hablada
    /// sigue distinguiendo buscar/reproducir; este interruptor permite impedir el
    /// autoplay incluso cuando el usuario dijo “pon”.
    static func musicaInternaAutoReproducir() -> Bool {
        (json()["musica_interna_autoplay"] as? Bool) ?? true
    }
    static func musicaInternaAvanzarSolo() -> Bool {
        (json()["musica_interna_avanzar"] as? Bool) ?? true
    }
    static func musicaInternaCompacta() -> Bool {
        (json()["musica_interna_compacta"] as? Bool) ?? false
    }
    static func musicaInternaConsultaPredeterminada() -> String {
        let s = ((json()["musica_interna_consulta_default"] as? String) ?? "música para escuchar")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "música para escuchar" : String(s.prefix(160))
    }
    /// Desde junio de 2026 Google asigna por defecto 100 llamadas diarias a
    /// search.list. Es un límite local preventivo: el servidor sigue mandando.
    static func youtubeBusquedasDiarias() -> Int {
        min(10_000, max(1, (json()["youtube_busquedas_diarias"] as? Int) ?? 100))
    }
    /// Proveedores propios: [{nombre,url}], URL con {q}.
    static func musicaProveedoresPersonales() -> [[String: String]] {
        (json()["musica_proveedores_personales"] as? [[String: String]]) ?? []
    }

    /// Motor de TTS: "apple" (voz de macOS) | "elevenlabs" (voz clonada Bto) |
    /// "xtts_local" (tu clon local). Cascada de failover parametrizable.
    static func ttsProveedor() -> String { (json()["tts_proveedor"] as? String) ?? "apple" }
    /// voice_id de ElevenLabs para TTS (tu voz clonada "Bto"). Vacío = usar el default.
    static func ttsElevenVoz() -> String { (json()["tts_eleven_voz"] as? String) ?? "qoHnXuIkkICzacInt72I" }
    static func ttsElevenModelo() -> String { (json()["tts_eleven_modelo"] as? String) ?? "eleven_flash_v2_5" }
    /// Streaming por WebSocket para ElevenLabs (suena mientras se genera). Default ON.
    static func ttsElevenStreaming() -> Bool { (json()["tts_eleven_streaming"] as? Bool) ?? true }
    /// Parámetros POR proveedor TTS de nube (voz/modelo/streaming). Todo parametrizable.
    static func ttsCloudVoz(_ id: String) -> String { ((json()["tts_cloud_voz"] as? [String: String]) ?? [:])[id] ?? "" }
    static func ttsCloudModelo(_ id: String) -> String { ((json()["tts_cloud_modelo"] as? [String: String]) ?? [:])[id] ?? "" }
    /// Streaming por proveedor (solo aplica si el proveedor soporta WS). Default ON.
    static func ttsCloudStreaming(_ id: String) -> Bool { ((json()["tts_cloud_streaming"] as? [String: Bool]) ?? [:])[id] ?? true }
    static func fijarTtsCloud(_ campo: String, _ id: String, _ valor: Any) {
        var d = (json()[campo] as? [String: Any]) ?? [:]; d[id] = valor; set(campo, to: d)
    }
    /// Comando de shell para tu clon LOCAL XTTS (VozClon). {texto} y {salida}
    /// se sustituyen. Vacío = motor no configurado (failover). Parametrizable.
    /// (Compat: se usa si no hay voces en la biblioteca [[VocesLocales]].)
    static func ttsXttsCmd() -> String { (json()["tts_xtts_cmd"] as? String) ?? "" }
    /// Voz LOCAL clonada seleccionada de la biblioteca (id). Vacío = la primera.
    static func ttsVozLocal() -> String { (json()["tts_voz_local"] as? String) ?? "" }
    /// Entrenador Piper: URL del checkpoint base (fine-tune). Vacío = default conocido.
    static func piperBaseURL() -> String { (json()["piper_base_url"] as? String) ?? "" }
    /// Entrenador Piper: tamaño de lote (batch). Default 8 (CPU 64GB). Parametrizable.
    static func piperBatch() -> Int { (json()["piper_batch"] as? Int) ?? 8 }
    /// Preactivar el servidor XTTS residente (modelo cargado en RAM) cuando el clon
    /// local es el motor activo → respuesta rápida. Default ON. Parametrizable.
    static func ttsXttsPreactivar() -> Bool { (json()["tts_xtts_preactivar"] as? Bool) ?? true }
    /// Modo RÁPIDO del clon: streaming (suena en ~1-2s mientras genera) en vez de por
    /// lotes (~4s pero garantizado fluido). El server corre a baja prioridad + hilos
    /// limitados para que el audio no se trabe. Default OFF (el usuario lo activa).
    static func ttsXttsRapido() -> Bool { (json()["tts_xtts_rapido"] as? Bool) ?? false }
    /// Hilos de CPU para el clon (0 = auto: núcleos-4, deja CPU al audio). Parametrizable.
    static func ttsXttsHilos() -> Int { (json()["tts_xtts_hilos"] as? Int) ?? 0 }
    /// Colchón (caché) del modo rápido en SEGUNDOS: cuánto audio junta antes de sonar.
    /// Más = más fluido (cubre las pausas del XTTS) pero arranca un poco más tarde.
    /// Default 2.5s → suena en ~2.5s (vs 4s por lotes) y cubre las pausas. Parametrizable.
    static func ttsXttsColchonSeg() -> Double { (json()["tts_xtts_colchon_seg"] as? Double) ?? 2.5 }
    /// DORMIR el clon (descargar el modelo, liberar RAM/CPU) tras N minutos sin usarse;
    /// se despierta al grabar (fn). Default ON, 15 min. No satura la Mac cuando no lo usas.
    static func ttsXttsDormir() -> Bool { (json()["tts_xtts_dormir"] as? Bool) ?? true }
    static func ttsXttsDormirMin() -> Double { (json()["tts_xtts_dormir_min"] as? Double) ?? 15 }
    /// Ventana especial tras abrir BtoDicta: evita pagar la carga fría si el primer
    /// uso llega varios minutos después. Cero la desactiva. Solo conserva el motor activo.
    static func ttsXttsArranqueMin() -> Double { (json()["tts_xtts_arranque_min"] as? Double) ?? 60 }
    static func ttsXttsWarmupDummy() -> Bool { (json()["tts_xtts_warmup_dummy"] as? Bool) ?? true }
    static func ttsXttsWarmupTexto() -> String { (json()["tts_xtts_warmup_texto"] as? String) ?? "Hola." }
    /// Motor equilibrado Qwen3-TTS/MLX. Parámetros propios: no cambian XTTS ni Piper.
    static func ttsMlxPreactivar() -> Bool { (json()["tts_mlx_preactivar"] as? Bool) ?? true }
    static func ttsMlxDormir() -> Bool { (json()["tts_mlx_dormir"] as? Bool) ?? true }
    static func ttsMlxDormirMin() -> Double { (json()["tts_mlx_dormir_min"] as? Double) ?? 15 }
    static func ttsMlxArranqueMin() -> Double { (json()["tts_mlx_arranque_min"] as? Double) ?? 60 }
    static func ttsMlxWarmupDummy() -> Bool { (json()["tts_mlx_warmup_dummy"] as? Bool) ?? true }
    static func ttsMlxWarmupTexto() -> String { (json()["tts_mlx_warmup_texto"] as? String) ?? "Hola." }
    /// Audio acumulado antes de empezar a reproducir y tamaño de chunk generado.
    static func ttsMlxColchonSeg() -> Double { (json()["tts_mlx_colchon_seg"] as? Double) ?? 0.8 }
    static func ttsMlxIntervalo() -> Double { (json()["tts_mlx_intervalo"] as? Double) ?? 0.32 }
    /// Si una variante local falla, prueba otras variantes de ESA MISMA persona antes
    /// de caer a la voz de macOS. Nunca salta silenciosamente a otro clon.
    static func ttsLocalVariantesFailover() -> Bool {
        (json()["tts_local_variantes_failover"] as? Bool) ?? true
    }
    /// Modo AHORRO global: al inactivar (mismos minutos), libera lo pesado (clon + latido
    /// de red); fn despierta todo. Default ON. Parametrizable.
    static func ahorroGlobal() -> Bool { (json()["ahorro_global"] as? Bool) ?? true }
    /// Carpeta base de VozClon (para el botón "Detectar mis voces"). Parametrizable.
    static func vozClonBase() -> String { (json()["voz_clon_base"] as? String) ?? "~/Downloads/VozClon" }
    /// Buscadores propios del usuario: [{nombre, url}] (url con {q}). Para el modo Buscar.
    static func buscadoresPersonales() -> [[String: String]] { (json()["buscadores_personales"] as? [[String: String]]) ?? [] }
    /// Despertar el túnel de red al grabar (mitiga latencia del 1er dictado con VPN). Default ON.
    static func calentarRed() -> Bool { (json()["calentar_red"] as? Bool) ?? true }
    /// Cada cuántos segundos late la red para mantener la conexión caliente (pulido
    /// rápido aunque dictes cada varios minutos). Default 15s. Parametrizable.
    static func latidoRedSegundos() -> Double { (json()["latido_red_segundos"] as? Double) ?? 15 }
    static func embeddingBase() -> String { (json()["embedding_base"] as? String) ?? "http://localhost:11434" }
    static func embeddingModelo() -> String { (json()["embedding_modelo"] as? String) ?? "bge-m3" }
    static func embeddingKeyEnv() -> String { (json()["embedding_key_env"] as? String) ?? "OPENAI_API_KEY" }
    static func muteToo() -> Bool { (json()["silenciar_ademas"] as? Bool) ?? false }
    static func translate() -> Bool { (json()["traducir"] as? Bool) ?? false }
    static func translateTo() -> String { (json()["traducir_idioma"] as? String) ?? "inglés" }
    static func panelVisible() -> Bool { (json()["panel_visible"] as? Bool) ?? true }
    /// Autoayuda instantánea al posar el cursor sobre botones y enlaces. La
    /// descripción para VoiceOver permanece disponible aunque se apague la burbuja.
    static func autoAyudaControles() -> Bool { (json()["autoayuda_controles"] as? Bool) ?? true }
    static func exportFolder() -> URL {
        if let s = json()["carpeta_exportar"] as? String, !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func groqKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty { return env }
        let envFile = dir.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("GROQ_API_KEY=") {
            let key = String(line.dropFirst("GROQ_API_KEY=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return nil
    }

    /// Escribe un valor en config.json de forma ATÓMICA y serializada, para
    /// que la GUI y el dictado no corrompan el archivo al leer/escribir a la vez.
    static func set(_ key: String, to value: Any) {
        lock.lock()
        var obj = cache ?? {
            (try? Data(contentsOf: dir.appendingPathComponent("config.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        }()
        obj[key] = value
        cache = obj
        // Escribir DENTRO del lock: dos set() concurrentes escribían snapshots
        // viejos tras soltar el lock → se perdía una actualización EN DISCO
        // (la memoria quedaba bien, pero el próximo arranque la perdía).
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            let cfg = dir.appendingPathComponent("config.json")
            try? data.write(to: cfg, options: .atomic)
            protegerSecreto(cfg)
        }
        lock.unlock()
        if key == "agente_pasarela_siri_token" {
            Log.log(.config, "cambio: \(key) = [oculto]")
        } else {
            Log.log(.config, "cambio: \(key) = \(value)")
        }
    }

    /// Fija permisos 0600 a un archivo que puede contener secretos (claves,
    /// gateways). Defensa en profundidad además del ~/.btodicta a 0700.
    static func protegerSecreto(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Asegura que ~/.btodicta exista y quede en 0700 (solo el dueño).
    static func asegurarDirSeguro() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }
    /// Al arrancar: baja a 0600 los archivos con secretos que ya existan
    /// (para quien actualiza desde una versión que los dejaba en 0644).
    static func endurecerSecretosExistentes() {
        asegurarDirSeguro()
        for f in [".env", "config.json", "ia_personalizadas.json"] {
            let u = dir.appendingPathComponent(f)
            if FileManager.default.fileExists(atPath: u.path) { protegerSecreto(u) }
        }
    }
    static func model() -> String { (json()["modelo"] as? String) ?? "scribe_v2_realtime" }
    /// Segundos que el whisper-server local vive tras el último uso (mín. 10).
    static func whisperKeepAlive() -> TimeInterval { max(10, (json()["whisper_keepalive"] as? Double) ?? 120) }
    /// Micrófono: "" = integrado del Mac (default anti-iPhone) · "auto" =
    /// el del sistema · UID = dispositivo específico.
    static func microfono() -> String { (json()["microfono"] as? String) ?? "" }
    /// Aprender de tus correcciones en el sitio (lee el campo vía
    /// Accesibilidad). Opt-in: apagado por defecto.
    static func aprender() -> Bool { (json()["aprender_correcciones"] as? Bool) ?? false }
    /// Atajo global para "aprender de la selección" (funciona en cualquier
    /// app, incl. Claude Code CLI). Default ⌘⇧L.
    static func atajoAprender() -> String { (json()["atajo_aprender"] as? String) ?? "cmd+shift+l" }
    /// Corrección por SONIDO (fonética): corrige palabras que suenan como un
    /// término marcado, aunque no sea una variante exacta ya conocida.
    /// Opt-in: apagada por defecto (más agresiva, puede sobre-corregir).
    static func correccionPorSonido() -> Bool { (json()["correccion_por_sonido"] as? Bool) ?? false }
    /// Asistente de primer arranque: ¿ya lo terminó el usuario? Solo se marca
    /// true al pulsar "Finalizar" — así un reinicio por Accesibilidad a mitad
    /// del wizard lo reabre en el mismo paso en vez de saltárselo.
    // Qué hacer al TERMINAR un dictado (tras pegar). Todos opt-in, default off.
    /// Añade un espacio al final (separa dictados seguidos).
    static func espacioAlTerminar() -> Bool { (json()["espacio_al_terminar"] as? Bool) ?? false }
    /// Pulsa Enter al terminar (envía en chats / salta línea en editores).
    static func enterAlTerminar() -> Bool { (json()["enter_al_terminar"] as? Bool) ?? false }
    /// Pulsa Shift+Enter al terminar (salto de línea suave).
    static func shiftEnterAlTerminar() -> Bool { (json()["shift_enter_al_terminar"] as? Bool) ?? false }

    /// Coincidencia por AUDIO (experimental): reconocer un término por tu voz
    /// grabada, además del texto. Opt-in, apagado por defecto.
    static func matchPorAudio() -> Bool { (json()["match_por_audio"] as? Bool) ?? false }
    /// Umbral de distancia para el match por audio (nil = usar el default).
    static func umbralAudio() -> Double? { json()["umbral_audio"] as? Double }
    /// Umbral SEPARADO para el dictado real (spotting corre en otra escala que
    /// "probar por voz"). nil = cae al de probar hasta calibrarlo.
    static func umbralAudioDictado() -> Double? { json()["umbral_audio_dictado"] as? Double }

    static func wizardCompletado() -> Bool { (json()["wizard_completado"] as? Bool) ?? false }
    /// ¿Existe ya la decisión del wizard? (ausente = nunca se ha decidido;
    /// sirve para migrar a usuarios que actualizan desde una versión sin wizard).
    static func tieneWizardFlag() -> Bool { json()["wizard_completado"] != nil }
    /// Paso guardado del asistente (para reabrir donde iba tras un reinicio).
    static func wizardPaso() -> Int { (json()["wizard_paso"] as? Int) ?? 0 }
    /// Última versión que el usuario YA vio (para el modal de novedades).
    static func ultimaVersionVista() -> String { (json()["ultima_version_vista"] as? String) ?? "" }
    /// ¿Hay señales de que la app ya se usó antes en esta máquina? (config,
    /// historial, uso, claves…). Distingue "actualización" de "instalación nueva".
    static func instalacionPrevia() -> Bool {
        let fm = FileManager.default
        for f in ["config.json", "uso.jsonl", "providers.json", ".env", "keyterms.txt"] {
            if fm.fileExists(atPath: dir.appendingPathComponent(f).path) { return true }
        }
        return fm.fileExists(atPath: dir.appendingPathComponent("historial").path)
    }

    /// Tarifa por hora que TÚ pusiste para un motor (override del default).
    static func tarifa(_ motor: String) -> Double? { (json()["tarifas"] as? [String: Double])?[motor] }
    static func setTarifa(_ motor: String, _ valor: Double?) {
        var t = (json()["tarifas"] as? [String: Double]) ?? [:]
        if let valor { t[motor] = valor } else { t[motor] = nil }
        set("tarifas", to: t)
    }

    /// API key de ElevenLabs: variable de entorno → ~/.btodicta/.env
    /// (la pone la pestaña Modelos; nada de rutas de otras apps).
    static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !env.isEmpty {
            return env
        }
        let key = ApiKeys.get("ELEVENLABS_API_KEY")
        return key.isEmpty ? nil : key
    }

    static func keyterms() -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("keyterms.txt"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Glosario como "initial prompt" para motores familia Whisper (Groq,
    /// whisper-cli, whisper-server, y futuros OpenAI/Mistral). Una frase en
    /// español sesga mejor que una lista pelada. Vacío si no hay términos.
    /// Tope 80 términos: el initial prompt de Whisper admite ~224 tokens y
    /// trunca por el INICIO, así que pasarse silenciosamente pierde términos.
    /// Términos que se añaden al glosario SOLO durante una petición de la API
    /// local. No se guardan: el glosario es del usuario y una petición externa
    /// no tiene por qué cambiárselo para siempre.
    nonisolated(unsafe) static var glosarioExtraTemporal: [String] = []

    static func glosarioPrompt() -> String {
        // Los términos de una petición de la API local van PRIMERO: son los que
        // esa petición concreta necesita que se reconozcan bien.
        let terms = Array(glosarioExtraTemporal + keyterms()).prefix(80)
        guard !terms.isEmpty else { return "" }
        return "Glosario: \(terms.joined(separator: ", "))."
    }

    struct Replacement: Decodable {
        let original: String
        let replacement: String
        let isRegex: Bool?
        let activo: Bool?
        let porSonido: Bool?     // además de variantes exactas, corregir por sonido
        let sigla: Bool?         // es un acrónimo (DSTI): coloca por posición de audio
    }

    /// Solo las reglas activas (las desactivadas se conservan pero no se aplican).
    static func replacements() -> [Replacement] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("reemplazos.json")),
              let rules = try? JSONDecoder().decode([Replacement].self, from: data) else { return [] }
        return rules.filter { $0.activo ?? true }
    }

    // MARK: - Bitácora continua (audio + pantalla en segundo plano)
    //
    // Prefijo `continuo_` a propósito: `grabacionContinua` ya está tomado y
    // significa grabación de PANTALLA en curso (CapturaMac). Son cosas distintas
    // y confundirlas costaría caro.
    //
    // El dictado por doble Fn manda SIEMPRE. Que la bitácora ceda el micrófono
    // no es un ajuste: es invariante del código. Un interruptor ahí acabaría
    // rompiendo el dictado un día por descuido.

    /// Interruptor maestro. Apagado de fábrica: nada se graba sin decisión explícita.
    static func continuoActivo() -> Bool { (json()["continuo_activo"] as? Bool) ?? false }

    /// Carpeta raíz de la bitácora. Vacío = `~/BtoDicta Bitácora` (acceso rápido
    /// desde el Finder, igual que las grabaciones de pantalla).
    static func continuoCarpeta() -> URL {
        let s = (json()["continuo_carpeta"] as? String) ?? ""
        if !s.isEmpty { return URL(fileURLWithPath: (s as NSString).expandingTildeInPath) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("BtoDicta Bitácora")
    }

    // ---- Audio ----

    /// `siempre` graba todo; `voz` solo persiste cuando el detector oye habla;
    /// `manual` deja el audio en manos del dictado de siempre.
    static func continuoAudioModo() -> String {
        let s = (json()["continuo_audio_modo"] as? String) ?? "voz"
        return ["siempre", "voz", "manual"].contains(s) ? s : "voz"
    }

    /// RETIRADO, no configurable a propósito. La AUVoiceIO de Apple deja MUDAS
    /// las demás capturas del mismo proceso incluso tras desactivarla: con esto
    /// encendido, el dictado por doble Fn grababa silencio (verificado con
    /// prueba A/B: 0 bytes con VPIO, 181 912 sin él). El dictado manda, así que
    /// la cancelación de eco por hardware no se ofrece; el solape con el audio
    /// del sistema se mitiga con la puerta anti-eco de abajo.
    static func continuoAudioCancelacionEco() -> Bool { false }

    /// Puerta anti-eco por software: mientras el audio del SISTEMA suena, el
    /// umbral de voz del micrófono se multiplica por este factor, para no
    /// guardar como «dicho» lo que en realidad salió por los parlantes.
    /// 1 = desactivada. 1…10.
    static func continuoAudioFactorAntiEco() -> Double {
        min(10.0, max(1.0, (json()["continuo_audio_factor_antieco"] as? Double) ?? 3.0))
    }

    /// Umbral de la puerta de voz en modo `voz`: por debajo de este nivel el
    /// audio se considera ruido y no se guarda. Subirlo evita transcripciones
    /// inventadas sobre fragmentos que son casi silencio; bajarlo captura habla
    /// más lejana. 0,0005…0,05. Sin la cancelación por hardware, la señal cruda
    /// del micrófono integrado es baja: una voz normal ronda 0,002…0,004.
    static func continuoAudioUmbralVoz() -> Double {
        min(0.05, max(0.0005, (json()["continuo_audio_umbral_voz"] as? Double) ?? 0.0025))
    }

    /// Trozos cerrados periódicamente para que un corte de luz no arruine la
    /// jornada entera. 30…900 s.
    static func continuoAudioSegmentoSegundos() -> Int {
        min(900, max(30, (json()["continuo_audio_segmento_segundos"] as? Int) ?? 120))
    }

    /// Absorbe el audio que el dictado ya guardó mientras la bitácora estaba
    /// cedida. Así ceder el micrófono no deja hueco en la línea de tiempo.
    static func continuoAudioAdoptarDictado() -> Bool {
        (json()["continuo_audio_adoptar_dictado"] as? Bool) ?? true
    }

    // ---- Pantalla ----

    static func continuoPantallaActiva() -> Bool {
        (json()["continuo_pantalla_activa"] as? Bool) ?? true
    }

    /// Intervalo libre entre capturas. 5…3600 s.
    static func continuoPantallaIntervaloSegundos() -> Int {
        min(3_600, max(5, (json()["continuo_pantalla_intervalo_segundos"] as? Int) ?? 30))
    }

    static func continuoPantallaFormato() -> String {
        let s = (json()["continuo_pantalla_formato"] as? String) ?? "jpeg"
        return ["jpeg", "heic", "png"].contains(s) ? s : "jpeg"
    }

    /// Calidad de compresión con pérdida. 0,1…1,0 (ignorada en png).
    static func continuoPantallaCalidad() -> Double {
        min(1.0, max(0.1, (json()["continuo_pantalla_calidad"] as? Double) ?? 0.6))
    }

    /// Escala respecto al tamaño nativo. 0,25…1,0.
    static func continuoPantallaEscala() -> Double {
        min(1.0, max(0.25, (json()["continuo_pantalla_escala"] as? Double) ?? 0.5))
    }

    /// No guardar si la pantalla no cambió lo suficiente.
    static func continuoPantallaDeduplicar() -> Bool {
        (json()["continuo_pantalla_deduplicar"] as? Bool) ?? true
    }

    /// Cuánto debe cambiar la imagen para considerarla nueva. 0,0…0,2.
    static func continuoPantallaUmbralCambio() -> Double {
        min(0.2, max(0.0, (json()["continuo_pantalla_umbral_cambio"] as? Double) ?? 0.01))
    }

    /// Aunque no haya cambios, guardar un fotograma cada N minutos para que la
    /// línea de tiempo no quede en blanco. 0 = desactivado. 0…120 min.
    static func continuoPantallaForzarMinutos() -> Int {
        min(120, max(0, (json()["continuo_pantalla_forzar_minutos"] as? Int) ?? 5))
    }

    static func continuoPantallaPausarBloqueada() -> Bool {
        (json()["continuo_pantalla_pausar_bloqueada"] as? Bool) ?? true
    }

    /// Identificadores de paquete excluidos de la captura (banca, gestores de
    /// contraseñas y lo que el usuario decida).
    ///
    /// **De fábrica vienen los gestores de contraseñas y el llavero.** Estaba
    /// vacía, y era un agujero real: la bitácora fotografía la pantalla cada
    /// pocos segundos, esas capturas se indexan, y el índice alimenta el texto
    /// que se le manda a la IA para el resumen. Un gestor abierto en ese
    /// instante es una clave fotografiada, indexada y camino de un servidor
    /// ajeno. La exclusión la aplica el propio sistema al componer la imagen:
    /// esas ventanas no llegan a aparecer en ella.
    ///
    /// Quien quiera capturarlas puede vaciar la lista; lo que no puede pasar es
    /// que el valor de fábrica sea el peligroso.
    static func continuoPantallaAppsExcluidas() -> [String] {
        if let l = json()["continuo_pantalla_apps_excluidas"] as? [String] { return l }
        return [
            "com.1password.1password",          // 1Password 8
            "com.agilebits.onepassword7",       // 1Password 7
            "com.agilebits.onepassword-osx",    // 1Password 6
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc",
            "com.apple.keychainaccess",         // Acceso a Llaveros
            "com.apple.Passwords",              // Contraseñas (macOS 15+)
            "com.dashlane.dashlanephoenix",
            "in.sinew.Enpass-Desktop",
            "me.proton.pass.electron",
            "com.markmcguill.strongbox.mac",
            "com.nordpass.macos",
            "com.callpod.keeper-mac",
        ]
    }

    /// Guardar con cada captura qué aplicaciones estaban a la vista (la activa
    /// ya se guarda aparte). Contexto para el resumen: «activa Claude; también
    /// visibles Edge, Finder».
    static func continuoPantallaAppsVisibles() -> Bool {
        (json()["continuo_pantalla_apps_visibles"] as? Bool) ?? true
    }

    /// Capturar TODAS las pantallas conectadas. Es lo que uno espera al
    /// enchufar dos o tres monitores; apagado, manda la lista de abajo.
    /// Sin la clave, «todas» es el valor de fábrica SOLO si no hay lista
    /// explícita de monitores: quien restringió la captura a monitores
    /// concretos en una versión anterior conserva su restricción al
    /// actualizar, sin ampliar el alcance en silencio.
    static func continuoPantallaTodosMonitores() -> Bool {
        if let valor = json()["continuo_pantalla_todos_monitores"] as? Bool { return valor }
        return continuoPantallaMonitores().isEmpty
    }

    /// Con «todas» apagado: monitores concretos por identificador. Vacío = el
    /// principal.
    static func continuoPantallaMonitores() -> [Int] {
        (json()["continuo_pantalla_monitores"] as? [Int]) ?? []
    }

    // ---- Energía ----

    /// No trabajar con batería: ni capturas ni tandas de transcripción.
    static func continuoSoloConCorriente() -> Bool {
        (json()["continuo_solo_con_corriente"] as? Bool) ?? false
    }

    // ---- Retención ----

    /// Días que se conserva la bitácora. 0 = para siempre.
    static func continuoRetencionDias() -> Int {
        min(3_650, max(0, (json()["continuo_retencion_dias"] as? Int) ?? 90))
    }

    /// Purgar sin preguntar al cumplirse el plazo.
    static func continuoRetencionAutomatica() -> Bool {
        (json()["continuo_retencion_automatica"] as? Bool) ?? false
    }

    /// Avisar antes de borrar material que todavía no tiene transcripción ni
    /// texto reconocido: eso es información que nunca se llegó a extraer.
    static func continuoRetencionAvisarSinProcesar() -> Bool {
        (json()["continuo_retencion_avisar_sin_procesar"] as? Bool) ?? true
    }

    // ---- Tanda diferida ----
    //
    // Transcribir en caliente mantendría un modelo de voz comiendo CPU todo el
    // día. Se difiere a una pasada única, con el equipo enchufado.

    /// Cuándo corre la tanda. Combinables: `intervalo`, `hora`, `arranque`,
    /// `apagado`. Vacío = solo a mano desde la pestaña.
    static func continuoLoteDisparadores() -> [String] {
        let validos = ["intervalo", "hora", "arranque", "apagado"]
        let s = (json()["continuo_lote_disparadores"] as? [String]) ?? ["hora"]
        return s.filter { validos.contains($0) }
    }

    /// Con el disparador `intervalo`: cada cuántos minutos. 15…1440.
    static func continuoLoteIntervaloMinutos() -> Int {
        min(1_440, max(15, (json()["continuo_lote_intervalo_minutos"] as? Int) ?? 60))
    }

    /// Con el disparador `hora`: minutos desde medianoche. 0…1439.
    /// 1140 = 19:00.
    static func continuoLoteMinutoDelDia() -> Int {
        min(1_439, max(0, (json()["continuo_lote_minuto_del_dia"] as? Int) ?? 1_140))
    }

    /// Motor de transcripción de la tanda. `cadena` usa los proveedores activos
    /// en el orden configurado, con failover — lo mismo que el dictado. Un id
    /// concreto (`apple_speech`, `elevenlabs`, `groq`, `ollama_stt`…) fija ese
    /// y solo ese. No se valida contra una lista cerrada a propósito: el
    /// catálogo de proveedores crece y esto no debe quedarse atrás.
    /// Qué motores LOCALES hacen de portero en la bitácora: escuchan el trozo y
    /// deciden si alguien habló, antes de gastar el motor bueno. Vacío o `off`
    /// lo desactiva.
    ///
    /// Son DOS por seguridad, no por exceso. Para ABRIR la puerta basta con que
    /// uno oiga voz; para CERRARLA tienen que coincidir los dos. Así, descartar
    /// un trozo exige que dos motores independientes se equivoquen a la vez, y
    /// el caso caro —perder algo que el usuario dijo— se vuelve muy improbable.
    ///
    /// **Transcribir bien y detectar silencio bien no son lo mismo.** Medido el
    /// 2026-09-19 con ruido real de oficina, sobre los mismos 12 trozos:
    ///
    /// | portero | frena el ambiente | deja pasar la voz |
    /// |---|---|---|
    /// | Apple Speech | 10 de 12 | 4 de 4 |
    /// | Nemotron + Voxtral | **0 de 12** | 4 de 4 |
    ///
    /// Los dos locales que transcriben con 0,00 % de error no frenan NADA. El
    /// motivo es conocido: los modelos de esa familia **alucinan** sobre audio
    /// sin voz — inventan palabras donde solo hay ruido, y el portero las cuenta
    /// como habla. Apple Speech es más prudente y por eso distingue mejor.
    ///
    /// Y ojo con juntarlos: como para CERRAR hacen falta todos, añadir uno que
    /// alucina anula al que acierta. Dos porteros solo mejoran si los dos saben
    /// callarse.
    static func bitacoraPorteros() -> [String] {
        let s = (json()["bitacora_portero"] as? String) ?? "apple_speech"
        if s.isEmpty || s == "off" { return [] }
        return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// ¿Retirar los trozos que TODAS las puertas dan por mudos?
    ///
    /// Apagado de fábrica: borrar audio del usuario no es algo que una
    /// aplicación deba empezar a hacer sola. Al encenderlo, los trozos sin voz
    /// van a la papelera propia —recuperables—, nunca al vacío.
    /// Qué NO interesa que entre en la bitácora, por aplicación o por título de
    /// ventana. Vacías de fábrica: nada se filtra hasta que el usuario lo diga.
    ///
    /// - `bitacora_excluir_apps`    — p. ej. ["Dota 2", "VLC", "Steam"]
    /// - `bitacora_excluir_titulos` — p. ej. ["youtube", "netflix", "instagram"]
    /// - `bitacora_incluir_apps`    — excepciones que GANAN a lo anterior
    /// - `bitacora_incluir_titulos` — p. ej. ["meet.google", "teams", "zoom"]
    ///
    /// Gobiernan las dos pistas a la vez, la de pantalla y la de audio del
    /// sistema: excluir el sonido de un juego y seguir guardando sus capturas no
    /// tendría sentido.
    static func bitacoraFiltroConfigurado() -> Bool { FiltroBitacora.hayReglas }

    static func bitacoraRetirarSilencios() -> Bool {
        (json()["bitacora_retirar_silencios"] as? Bool) ?? false
    }

    /// Cuántos días se guarda en la papelera interna lo retirado por mudo.
    /// 0 = no se borra nunca (la papelera solo aparta, no elimina).
    static func bitacoraPapeleraDias() -> Int {
        max(0, (json()["bitacora_papelera_dias"] as? Int) ?? 7)
    }

    static func continuoLoteMotor() -> String {
        // Por defecto, Apple en el dispositivo: el audio de una jornada entera
        // NO debe irse a un STT de nube porque sí. «cadena» (los proveedores
        // del dictado, que pueden ser nube) es una elección explícita.
        let s = (json()["continuo_lote_motor"] as? String) ?? "apple_speech"
        return s.isEmpty ? "apple_speech" : s
    }

    /// RED DE SEGURIDAD del dictado: tras un dictado largo se vuelve a
    /// transcribir el audio COMPLETO por lotes y se entrega el resultado más
    /// completo. El motor en vivo puede elidir texto o congelarse en dictados
    /// largos; esto garantiza que nunca falte lo dictado.
    static func redSeguridadDictado() -> Bool {
        (json()["dictado_red_seguridad"] as? Bool) ?? true
    }
    /// Desde qué fracción del tope se avisa (0,15 = al bajar del 15 %). Solo
    /// aplica a proveedores con tope conocido, como ElevenLabs.
    static func saldoAvisoFraccion() -> Double {
        min(0.9, max(0, (json()["saldo_aviso_fraccion"] as? Double) ?? 0.15))
    }
    /// Y para los de saldo en dinero, desde qué cantidad avisar.
    static func saldoAvisoMinimoUSD() -> Double {
        max(0, (json()["saldo_aviso_minimo_usd"] as? Double) ?? 5)
    }

    // MARK: Correo (spec 003)
    /// Servidor de salida. La clave NO vive aquí: va en el almacén de secretos.
    static func smtpHost() -> String { (json()["smtp_host"] as? String) ?? "" }
    static func smtpPuerto() -> Int { min(65535, max(1, (json()["smtp_puerto"] as? Int) ?? 465)) }
    static func smtpUsuario() -> String { (json()["smtp_usuario"] as? String) ?? "" }
    static func smtpRemitente() -> String { (json()["smtp_remitente"] as? String) ?? "" }
    /// A quiénes se envía. Separados por coma en la interfaz.
    static func correoDestinatarios() -> [String] {
        ((json()["correo_destinatarios"] as? String) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("@") }
    }
    /// Envío automático del resumen y a qué hora (formato "HH:mm", varias
    /// separadas por coma). Cada hora lleva su periodo en `correo_periodo`.
    static func correoAutomatico() -> Bool { (json()["correo_automatico"] as? Bool) ?? false }
    static func correoHorarios() -> [String] {
        ((json()["correo_horarios"] as? String) ?? "07:00")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(":") }
    }
    /// "hoy" | "ayer" | "semana"
    static func correoPeriodo() -> String { (json()["correo_periodo"] as? String) ?? "ayer" }

    /// Pedir confirmación (repitiendo la acción) también al cancelar desde el
    /// notch, no solo con Escape. Apagado por omisión: la doble pulsación de
    /// Escape ya evita el accidente que motivó esto.
    static func cancelarConfirma() -> Bool { (json()["cancelar_confirma"] as? Bool) ?? false }
    /// Escape exige DOS pulsaciones seguidas para cancelar. Una sola no puede
    /// tumbar un dictado: mientras se graba, esa tecla está capturada en todo el
    /// sistema y el usuario suele pulsarla para cerrar una ventana ajena.
    static func escDoble() -> Bool { (json()["esc_doble"] as? Bool) ?? true }
    /// Cuánto tiempo cuenta como «seguidas» las dos pulsaciones de Escape.
    static func escDobleSegundos() -> Double {
        min(3, max(0.2, (json()["esc_doble_s"] as? Double) ?? 0.8))
    }
    /// Desde cuántos segundos un dictado CANCELADO se conserva en el historial
    /// en vez de borrarse. Cancelar nunca debe destruir lo grabado: por debajo
    /// de este umbral solo se descarta lo que no tiene nada dentro. 0 conserva
    /// siempre; subirlo evita guardar pulsaciones accidentales de medio segundo.
    static func cancelarConservaDesdeSegundos() -> Double {
        min(60, max(0, (json()["cancelar_conserva_desde_s"] as? Double) ?? 2))
    }
    /// Proveedores que NO deben avisar de saldo bajo.
    ///
    /// Para los que se sabe agotados y se ha decidido no renovar: avisar cada
    /// día de algo ya decidido no es información, es ruido — y el ruido entierra
    /// el aviso que sí importa.
    static func saldoAvisoSilenciados() -> [String] {
        (json()["saldo_aviso_silenciados"] as? [String]) ?? []
    }

    /// Escribir en el registro el TEXTO de lo dictado, no solo su medida.
    ///
    /// **Encendido de fábrica, y a conciencia.** El registro es local, rota cada
    /// semana y no sale de la máquina; a cambio, es la única forma de reconstruir
    /// después qué se dictó y qué entregó cada motor, que es lo que permite ver
    /// que un pulido recortó el texto o que un proveedor devolvió otra cosa. Sin
    /// él, el diagnóstico es adivinanza.
    ///
    /// Apagarlo deja las mismas líneas con la medida y el proveedor, pero sin el
    /// contenido. Tiene sentido si la pantalla se comparte a menudo, si el equipo
    /// es de trabajo compartido, o si se dictan datos de terceros.
    static func registroIncluyeTexto() -> Bool {
        (json()["registro_incluye_texto"] as? Bool) ?? true
    }

    /// Palabras en el TÍTULO de la ventana que también impiden la captura.
    ///
    /// Va aparte de la lista de aplicaciones porque un navegador se llama igual
    /// esté donde esté: lo que distingue una pestaña del banco es su título.
    /// Vacía de fábrica: una palabra demasiado común dejaría a la bitácora sin
    /// capturar media jornada, y esa decisión es de quien la usa.
    static func continuoPantallaTitulosExcluidos() -> [String] {
        (json()["continuo_pantalla_titulos_excluidos"] as? [String]) ?? []
    }

    /// Cuántos días se conserva el `.wav` de trabajo de cada dictado antes de
    /// barrerlo. Ese archivo es la copia que el grabador escribe mientras hablas
    /// —desde 0.63.4 el audio ya no vive en memoria—, y no sustituye al del
    /// historial, que se guarda aparte y no lo toca nadie.
    ///
    /// **0 = no barrer nunca.** Ronda los 115 MB por hora dictada.
    static func dictadosConservarDias() -> Int {
        min(365, max(0, (json()["dictados_conservar_dias"] as? Int) ?? 7))
    }
    /// Fish Audio: intentar primero su modelo de voz GRATUITO y caer al de pago
    /// solo si aquel falla. Ahorra crédito sin perder la voz; ponlo en false
    /// para ir siempre directo al modelo elegido.
    static func fishTtsAhorro() -> Bool {
        (json()["fish_tts_ahorro"] as? Bool) ?? true
    }
    /// Desde cuántos segundos se verifica (siempre, aunque no haya sospecha).
    static func redSeguridadDesdeSegundos() -> Int {
        min(3600, max(20, (json()["dictado_red_seguridad_desde_s"] as? Int) ?? 90))
    }
    /// Cuánto se espera como máximo a la verificación antes de entregar el vivo.
    static func redSeguridadTopeSegundos() -> Int {
        min(900, max(20, (json()["dictado_red_seguridad_tope_s"] as? Int) ?? 180))
    }
    /// Segundos SIN texto nuevo (teniendo voz) tras los que se da por colgado
    /// el motor en vivo y se relanza desde ese punto. 0 lo desactiva.
    /// Cuántas veces puede relanzarse el motor en vivo dentro de un mismo
    /// dictado. Un dictado largo puede colgarse varias veces.
    static func motorVivoRelanzosMax() -> Int {
        min(50, max(0, (json()["motor_vivo_relanzos_max"] as? Int) ?? 8))
    }
    static func motorVivoSinTextoSegundos() -> Int {
        let v = (json()["motor_vivo_sin_texto_s"] as? Int) ?? 12
        return v <= 0 ? 0 : min(120, max(5, v))
    }

    /// Comprimir el PCM crudo a m4a una vez transcrito.
    static func continuoLoteComprimir() -> Bool {
        (json()["continuo_lote_comprimir"] as? Bool) ?? true
    }

    /// Recomprimir en segundo plano el crudo que quedó sin comprimir estando
    /// ya transcrito (pasadas de 15 min, se detiene si empieza un dictado).
    static func continuoRecomprimirPendientes() -> Bool {
        (json()["continuo_recomprimir_pendientes"] as? Bool) ?? true
    }

    /// No capturar la pantalla mientras corre una tanda (el equipo va cargado
    /// y la captura puede tardar más que el intervalo). Apagado de fábrica:
    /// la línea de tiempo no se queda en blanco por defecto.
    static func continuoPantallaPausarEnTanda() -> Bool {
        (json()["continuo_pantalla_pausar_en_tanda"] as? Bool) ?? false
    }

    /// Tope de fragmentos por tanda, para que una pasada no se eternice. 10…5000.
    static func continuoLoteMaximoPorTanda() -> Int {
        min(5_000, max(10, (json()["continuo_lote_maximo_por_tanda"] as? Int) ?? 500))
    }

    /// No transcribir con batería.
    static func continuoLoteSoloConCorriente() -> Bool {
        (json()["continuo_lote_solo_con_corriente"] as? Bool) ?? true
    }

    // ---- Texto de las capturas (OCR) ----

    static func continuoOcrActivo() -> Bool { (json()["continuo_ocr_activo"] as? Bool) ?? true }

    /// Preciso reconoce mejor y tarda más; rápido va bien para buscar por
    /// palabras sueltas.
    static func continuoOcrPreciso() -> Bool { (json()["continuo_ocr_preciso"] as? Bool) ?? true }

    /// Sin fijar idioma, Vision lee el español como inglés mal escrito.
    static func continuoOcrIdiomas() -> [String] {
        let s = (json()["continuo_ocr_idiomas"] as? [String]) ?? ["es-ES", "en-US"]
        return s.isEmpty ? ["es-ES"] : s
    }

    /// Descarta lecturas dudosas. 0,0…1,0.
    static func continuoOcrConfianzaMinima() -> Double {
        min(1.0, max(0.0, (json()["continuo_ocr_confianza_minima"] as? Double) ?? 0.4))
    }

    /// Altura mínima del texto como fracción de la imagen: ignora el ruido de
    /// un píxel. 0,0…0,1.
    static func continuoOcrAlturaMinima() -> Double {
        min(0.1, max(0.0, (json()["continuo_ocr_altura_minima"] as? Double) ?? 0.008))
    }

    // ---- Resumen del día ----

    static func continuoResumenActivo() -> Bool { (json()["continuo_resumen_activo"] as? Bool) ?? false }

    /// Cuántos caracteres caben en UN envío al modelo (prompt e instrucción
    /// aparte). Es la ventana de contexto práctica de la IA elegida, no un
    /// límite de cuánto se procesa: lo que no quepa va en más envíos.
    /// 2000…400000.
    static func continuoResumenMaxCaracteres() -> Int {
        min(400_000, max(2_000, (json()["continuo_resumen_max_caracteres"] as? Int) ?? 18_000))
    }

    /// Si el día no cabe en un envío, trocearlo y enviarlo TODO en varias
    /// pasadas, y unir al final. Nada se descarta: diez envíos si hacen falta.
    /// Apagado, se vuelve al recorte por prioridad (con pérdida).
    static func continuoResumenTrocear() -> Bool {
        (json()["continuo_resumen_trocear"] as? Bool) ?? true
    }

    /// Tope cuerdo de envíos por documento. Si el material pide más partes que
    /// esto, las partes se agrandan para caber en el tope — no se pierde nada,
    /// solo se aprieta más por envío. 2…50.
    static func continuoResumenMaxPartes() -> Int {
        min(50, max(2, (json()["continuo_resumen_max_partes"] as? Int) ?? 20))
    }

    /// Prompt de la biblioteca que se usa al ejecutar a mano y en la
    /// programación. Ver `ContinuoPrompts`.
    static func continuoPromptActivo() -> String {
        (json()["continuo_prompt_activo"] as? String) ?? "resumen_diario"
    }

    /// Cerebro que redacta. `seleccionada` usa el mismo que el resto de la app;
    /// un id concreto (`groq`, `ollama`, `lmstudio`, `openai`…) fija ese. Sin
    /// lista cerrada: vale cualquiera que aparezca en `ChatIA.conectadas`.
    static func continuoResumenIA() -> String {
        let s = (json()["continuo_resumen_ia"] as? String) ?? "seleccionada"
        return s.isEmpty ? "seleccionada" : s
    }

    /// Instrucción que recibe el modelo. Vacío = la del prompt elegido.
    static func continuoResumenInstruccion() -> String {
        (json()["continuo_resumen_instruccion"] as? String) ?? ""
    }

    /// Incluir el texto leído de las capturas, además de lo hablado.
    static func continuoResumenIncluirPantalla() -> Bool {
        (json()["continuo_resumen_incluir_pantalla"] as? Bool) ?? true
    }

    /// La voz del micrófono manda. Cuando el día no cabe en el tope de
    /// caracteres, se recorta primero la pantalla, luego el audio del sistema,
    /// y lo hablado al micrófono solo en último extremo. Un videotutorial es
    /// contexto; la voz de la persona es el contenido.
    static func continuoResumenPrioridadMicrofono() -> Bool {
        (json()["continuo_resumen_prioridad_microfono"] as? Bool) ?? true
    }

    /// Cierra el material con el tiempo aproximado en primer plano por
    /// aplicación, deducido de las capturas.
    static func continuoResumenTiemposApp() -> Bool {
        (json()["continuo_resumen_tiempos_app"] as? Bool) ?? true
    }

    // ---- Diccionario propio ----
    //
    // BtoDicta ya sabe cómo habla su dueño: reemplazos, corrección por sonido,
    // siglas y glosario, afinados a fuerza de dictar. Ese conocimiento vale
    // igual para lo que graba la bitácora, y hasta más: ahí no hay nadie
    // revisando el texto en el momento.

    /// Pasar las transcripciones por las reglas de reemplazo, incluida la
    /// corrección fonética. Es lo que convierte «Kikox» en el término correcto.
    static func continuoDiccionarioAudio() -> Bool {
        (json()["continuo_diccionario_audio"] as? Bool) ?? true
    }

    /// Lo mismo para el texto leído de las capturas: el reconocimiento visual
    /// se equivoca con las mismas palabras raras que el de voz.
    static func continuoDiccionarioOcr() -> Bool {
        (json()["continuo_diccionario_ocr"] as? Bool) ?? true
    }

    /// Adjuntar el glosario al prompt para que el modelo tenga el contexto de
    /// los términos propios y pueda deducirlos cuando el audio los deformó.
    static func continuoGlosarioEnPrompt() -> Bool {
        (json()["continuo_glosario_en_prompt"] as? Bool) ?? true
    }

    // ---- Audio del sistema ----
    //
    // Lo que SUENA en el equipo: la otra parte de una videollamada, un vídeo,
    // una reunión. Pista separada de la del micrófono.

    static func continuoSistemaActivo() -> Bool {
        (json()["continuo_sistema_activo"] as? Bool) ?? false
    }

    /// Excluir el audio de la propia aplicación. Sin esto, la bitácora grabaría
    /// su propia voz sintetizada y se escucharía a sí misma.
    static func continuoSistemaExcluirPropia() -> Bool {
        (json()["continuo_sistema_excluir_propia"] as? Bool) ?? true
    }

    /// Guardar solo cuando el equipo suena de verdad: casi todo el día no suena
    /// nada y almacenar silencio llenaría el disco sin aportar.
    static func continuoSistemaSoloConSonido() -> Bool {
        (json()["continuo_sistema_solo_con_sonido"] as? Bool) ?? true
    }

    /// Nivel a partir del cual se considera que hay sonido. 0,0001…0,05.
    static func continuoSistemaUmbral() -> Double {
        min(0.05, max(0.0001, (json()["continuo_sistema_umbral"] as? Double) ?? 0.002))
    }
}
