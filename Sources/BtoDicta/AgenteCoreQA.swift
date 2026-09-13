import AppKit
import Foundation

/// QA puro del nuevo núcleo. No abre apps, no reproduce música, no pide permisos,
/// no llama IAs y no escribe configuración.
enum AgenteCoreQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_AGENTCORETEST"] == "1" else { return }
        var resultados: [Bool] = []
        func comprobar(_ nombre: String, _ condicion: @autoclosure () -> Bool, _ detalle: String = "") {
            let ok = condicion(); resultados.append(ok)
            print("AGENTCORE \(ok ? "OK" : "✗") \(nombre)\(detalle.isEmpty ? "" : " | " + detalle)")
        }

        let nombreQA = "Atenea"
        let fraseQA = "Oye \(nombreQA)"
        let fraseAlternaQA = "Hola Nicanor"
        let activadores = [fraseQA, fraseAlternaQA, "Escucha Ñusta"]
        let a = PerfilAgente.invocacion(en: "Oye, \(nombreQA): ¿qué tareas tengo hoy?", activadores: activadores)
        comprobar("activación con nombre inyectado", a?.contenido == "¿qué tareas tengo hoy?", a?.contenido ?? "nil")
        let b = PerfilAgente.invocacion(en: "\(fraseAlternaQA), recuérdame llamar a Rafael", activadores: activadores)
        comprobar("activación personalizada", b?.frase == fraseAlternaQA && b?.contenido.hasPrefix("recuérdame") == true)
        comprobar("sin falso positivo intermedio",
                  PerfilAgente.invocacion(en: "Ayer dije \(fraseAlternaQA) en una película", activadores: activadores) == nil)
        let listaActivadores = FrasesConfigurables.parsear("\"Oye, \(nombreQA)\"\n\(fraseAlternaQA)\n“Escucha, Ñusta”")
        comprobar("activadores con coma/comillas",
                  listaActivadores == ["Oye, \(nombreQA)", fraseAlternaQA, "Escucha, Ñusta"],
                  listaActivadores.joined(separator: " | "))
        comprobar("coma del STT no cambia la activación",
                  PerfilAgente.invocacion(en: "Oye, \(nombreQA), abre Gmail", activadores: listaActivadores)?.contenido == "abre Gmail")
        comprobar("no degrada a activador de una palabra",
                  PerfilAgente.invocacion(en: "Oye, ¿qué pasó?", activadores: listaActivadores) == nil)
        let activadoresPeligrosos = ["oye", nombreQA, nombreQA.lowercased(), fraseQA]
        comprobar("ignora activadores configurados de una palabra",
                  PerfilAgente.invocacion(en: "Oye, qué tontera, esto era solo un dictado",
                                           activadores: activadoresPeligrosos) == nil
                    && PerfilAgente.invocacion(en: "\(nombreQA) está trabajando hoy",
                                               activadores: activadoresPeligrosos) == nil)
        comprobar("conserva activador deliberado de dos palabras",
                  PerfilAgente.invocacion(en: "Oye, \(nombreQA), abre Gmail",
                                           activadores: activadoresPeligrosos)?.contenido == "abre Gmail")

        let dicta = DictadoAsistido.detectar(
            "Dicta esto: mañana llego a las ocho y llevo el informe.")
        comprobar("dictado asistido separa orden y contenido",
                  dicta?.operacion == .dictar
                    && dicta?.contenido == "mañana llego a las ocho y llevo el informe.",
                  dicta?.contenido ?? "nil")
        let transcribe = DictadoAsistido.detectar(
            "Por favor, transcribe lo siguiente: ¿Qué día es hoy?")
        comprobar("dictado asistido conserva pregunta y cortesía",
                  transcribe?.operacion == .transcribir
                    && transcribe?.contenido == "¿Qué día es hoy?",
                  transcribe?.contenido ?? "nil")
        comprobar("dictado asistido reconoce escribir con marcador",
                  DictadoAsistido.detectar("Escribe esto, nos vemos mañana.")
                    == SolicitudDictadoAsistido(operacion: .escribir,
                                                frase: "Escribe esto",
                                                contenido: "nos vemos mañana."))
        comprobar("dictado asistido reconoce corregir acentuado",
                  DictadoAsistido.detectar("Corrígeme este texto: ahi nos vemos.")?.operacion
                    == .corregir)
        comprobar("dictado asistido reconoce actualizar",
                  DictadoAsistido.detectar("Actualiza esto: la reunión cambió al viernes.")?.contenido
                    == "la reunión cambió al viernes.")
        comprobar("dictado asistido reconoce mejorar",
                  DictadoAsistido.detectar("Mejora lo siguiente — necesitamos apoyo.")?.operacion
                    == .mejorar)
        comprobar("dictado asistido reconoce crear un dictado",
                  DictadoAsistido.detectar("Crea un dictado de esto: informe para rectorado.")?.contenido
                    == "informe para rectorado.")
        comprobar("dictado solo abre continuación",
                  DictadoAsistido.detectar("Dictado")?.contenido.isEmpty == true)
        comprobar("dictado con dos puntos conserva el cuerpo",
                  DictadoAsistido.detectar("Dictado: este es el contenido.")?.contenido
                    == "este es el contenido.")
        comprobar("continuación entiende cancelación local",
                  DictadoAsistido.esCancelacion("Olvídalo")
                    && !DictadoAsistido.esCancelacion("olvidé adjuntar el informe"))

        // Falsos positivos deliberados: estas órdenes pertenecen al planificador
        // de herramientas o a un dictado normal, nunca a la salida local.
        comprobar("escribir correo no se roba",
                  DictadoAsistido.detectar("Escribe un correo para Andrés") == nil)
        comprobar("actualizar sistema no se roba",
                  DictadoAsistido.detectar("Actualiza el sistema esta noche") == nil)
        comprobar("mejora continua no se roba",
                  DictadoAsistido.detectar("La mejora continua del equipo funciona") == nil)
        comprobar("orden intermedia no se roba",
                  DictadoAsistido.detectar("Ayer dije dicta esto durante la reunión") == nil)
        comprobar("dictado como sustantivo no se roba",
                  DictadoAsistido.detectar("El dictado médico quedó archivado") == nil)

        let seguimiento = AgenteNucleo.completarSeguimiento(
            "Mándaselo a Andrés por WhatsApp", referencia: "La reunión será mañana a las ocho.")
        let planSeguimiento = seguimiento.flatMap { ModoPlanificador.detectarNatural($0,
            catalogo: ModoCatalogo(modos: ModosStore.todos())) }
        comprobar("memoria resuelve pronombre con confirmación",
                  planSeguimiento?.cadena.acciones.first?.modo.accion == "whatsapp"
                    && planSeguimiento?.cadena.acciones.first?.destinatario == "Andrés"
                    && planSeguimiento?.cadena.contenido.contains("reunión será mañana") == true)
        let seguimientoReal = AgenteNucleo.planificar(
            "Mándaselo a Andrés por WhatsApp",
            catalogo: ModoCatalogo(modos: ModosStore.todos()),
            referencia: "La reunión será mañana a las ocho.",
            ignorarInterruptor: true)
        comprobar("seguimiento atraviesa el núcleo",
                  seguimientoReal?.cadena.acciones.first?.destinatario == "Andrés"
                    && seguimientoReal?.cadena.contenido.contains("reunión será mañana") == true)
        comprobar("memoria no invade una narración",
                  AgenteNucleo.completarSeguimiento("Ayer lo envié por WhatsApp", referencia: "secreto") == nil)

        let climaQuito = AgenteNucleo.planificarClima(
            "¿Me puedes decir el clima de Quito, Pichincha, Ecuador?")
        comprobar("clima explícito entra antes de la IA",
                  climaQuito?.cadena.acciones.first?.modo.accion == "clima"
                    && climaQuito?.cadena.contenido.contains("Quito") == true)
        let climaActual = AgenteNucleo.planificarClima(
            "¿Puedes decirme cómo está el clima del día de hoy?")
        comprobar("clima sin ciudad usa herramienta local",
                  climaActual?.cadena.acciones.first?.modo.accion == "clima")
        comprobar("narración meteorológica no se desvía",
                  AgenteNucleo.planificarClima(
                    "Ayer conversamos sobre el clima de Quito durante la reunión") == nil)
        let climaResolver = ModoResolver.detectarPedidoNatural(
            "Qué tiempo hará mañana en Quito", catalogo: ModoCatalogo(modos: ModosStore.todos()))
        comprobar("resolver natural conserva el día y la ciudad",
                  climaResolver?.cadena.acciones.first?.modo.accion == "clima"
                    && climaResolver?.cadena.contenido == "Qué tiempo hará mañana en Quito")

        let generarYEnviar = AgenteNucleo.planificar(
            "crea una redacción de un verso sin esfuerzo, algo como ejemplo, y después mándaselo a Andrés por WhatsApp",
            catalogo: ModoCatalogo(modos: ModosStore.todos()),
            ignorarInterruptor: true)
        comprobar("generación encadena WhatsApp y destinatario",
                  generarYEnviar?.cadena.transforms.map(\.id) == ["generar"]
                    && generarYEnviar?.cadena.acciones.map(\.modo.accion) == ["whatsapp"]
                    && generarYEnviar?.cadena.acciones.first?.destinatario == "Andrés"
                    && generarYEnviar?.cadena.contenido.localizedCaseInsensitiveContains("redacción de un verso") == true,
                  generarYEnviar.map { "\($0.descripcion) | \($0.cadena.contenido)" } ?? "nil")
        comprobar("generación libre no confunde una narración",
                  AgenteNucleo.planificar(
                    "Ayer creé un verso y después lo envié a Andrés por WhatsApp",
                    catalogo: ModoCatalogo(modos: ModosStore.todos()),
                    ignorarInterruptor: true) == nil)

        comprobar("proveedor Spotify", Musica.reconocerProveedor(en: "en Spotify") == "spotify")
        comprobar("proveedor Apple Music", Musica.reconocerProveedor(en: "Apple Music") == "apple_music")
        comprobar("proveedor interno por voz",
                  Musica.reconocerProveedor(en: "interno") == "btodicta_youtube"
                    && Musica.reconocerProveedorCompuesto("reproductor interno") == "btodicta_youtube"
                    && Musica.reconocerProveedor(en: "BtoDicta") == "btodicta_youtube")
        comprobar("proveedor YouTube Music conserva la consulta",
                  Musica.reconocerProveedor(en: "Reproduce en YouTube Music pasillo ecuatoriano")
                    == "youtube_music"
                    && Musica.extraerConsulta(
                        "Reproduce en YouTube Music pasillo ecuatoriano.",
                        proveedor: "youtube_music") == "pasillo ecuatoriano")
        comprobar("consulta musical limpia",
                  Musica.extraerConsulta("reproduce en Spotify música de Jessy Uribe", proveedor: "spotify") == "Jessy Uribe",
                  Musica.extraerConsulta("reproduce en Spotify música de Jessy Uribe", proveedor: "spotify"))
        comprobar("Spotify conserva reproducir y limpia puntuación final",
                  Musica.intencion("Reproduce en Spotify música andina.") == .reproducir
                    && Musica.extraerConsulta("Reproduce en Spotify música andina.",
                                              proveedor: "spotify") == "andina")
        comprobar("Spotify solo acepta un botón de reproducción verificable",
                  SpotifyControl.esBotonReproducir(rol: "AXButton",
                                                    descripcion: "Reproducir", titulo: "")
                    && SpotifyControl.esBotonReproducir(rol: "AXButton",
                                                        descripcion: "Play", titulo: "")
                    && !SpotifyControl.esBotonReproducir(rol: "AXButton",
                                                         descripcion: "Pausar", titulo: "")
                    && !SpotifyControl.esBotonReproducir(rol: "AXGroup",
                                                         descripcion: "Reproducir", titulo: ""))
        let pwaYouTubeMusic = AplicacionMac(
            nombre: "YouTube Music",
            bundleId: "com.ejemplo.browser.app.hash-distinto",
            ruta: "/Users/prueba/Applications/YouTube Music.app",
            alias: ["youtube music"])
        comprobar("YouTube Music descubre cualquier PWA por nombre, no por hash",
                  YouTubeMusicControl.aplicacionInstalada(en: [pwaYouTubeMusic])?.bundleId
                    == pwaYouTubeMusic.bundleId)
        comprobar("YouTube Music solo acepta resultados etiquetados",
                  YouTubeMusicControl.esBotonResultado(
                    rol: "AXButton", descripcion: "Reproducir Música Andina: Carnavalito")
                    && YouTubeMusicControl.esBotonResultado(
                        rol: "AXButton", descripcion: "Play Nuestro Juramento — Julio Jaramillo")
                    && !YouTubeMusicControl.esBotonResultado(
                        rol: "AXButton", descripcion: "Reproducir")
                    && !YouTubeMusicControl.esBotonResultado(
                        rol: "AXGroup", descripcion: "Reproducir Música Andina"))
        comprobar("YouTube Music verifica consulta contra título, artista o álbum",
                  YouTubeMusicControl.coincide(
                    consulta: "música andina",
                    contexto: "El Cóndor Pasa · Los Sikuris · Música Andina: Carnavalito")
                    && YouTubeMusicControl.coincide(
                        consulta: "pasillo ecuatoriano",
                        contexto: "PASILLOS ECUATORIANOS ANTIGUOS")
                    && YouTubeMusicControl.coincide(
                        consulta: "Julio Jaramillo",
                        contexto: "Nuestro Juramento · Julio Jaramillo")
                    && !YouTubeMusicControl.coincide(
                        consulta: "Julio Jaramillo",
                        contexto: "No veo bien · RØZ y Nsqk"))
        comprobar("Apple Music tiene espera acotada de arranque en frío",
                  Musica.esperasArranqueApple(yaAbierto: true).first == 0
                    && Musica.esperasArranqueApple(yaAbierto: true).count
                        < Musica.esperasArranqueApple(yaAbierto: false).count
                    && Musica.esperasArranqueApple(yaAbierto: false).reduce(0, +) < 5)
        comprobar("música distingue reproducir de buscar",
                  Musica.intencion("modo música, pon una canción de Julio Jaramillo") == .reproducir
                    && Musica.intencion("modo música, busca Julio Jaramillo") == .buscar
                    && Musica.intencion("busca Julio Jaramillo") == .buscar)
        comprobar("consulta quita relleno de canción cualquiera",
                  Musica.extraerConsulta("modo música, pon una canción cualquiera de Julio Jaramillo",
                                         proveedor: "auto") == "Julio Jaramillo",
                  Musica.extraerConsulta("modo música, pon una canción cualquiera de Julio Jaramillo",
                                         proveedor: "auto"))
        comprobar("consulta de búsqueda musical queda limpia",
                  Musica.extraerConsulta("modo música, busca Julio Jaramillo",
                                         proveedor: "auto") == "Julio Jaramillo")
        comprobar("consulta del reproductor interno queda limpia",
                  Musica.extraerConsulta("modo música interno, reproduce Julio Jaramillo",
                                         proveedor: "btodicta_youtube") == "Julio Jaramillo",
                  Musica.extraerConsulta("modo música interno, reproduce Julio Jaramillo",
                                         proveedor: "btodicta_youtube"))
        comprobar("IDs y enlaces oficiales de YouTube se validan",
                  YouTubeDataAPI.idDirecto("dQw4w9WgXcQ") == "dQw4w9WgXcQ"
                    && YouTubeDataAPI.idDirecto("https://music.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"
                    && YouTubeDataAPI.idDirecto("https://example.com/watch?v=dQw4w9WgXcQ") == nil)
        let oauthEscritorio = #"{"installed":{"client_id":"qa.apps.googleusercontent.com","client_secret":"solo-qa"}}"#.data(using: .utf8)!
        let oauthWeb = #"{"web":{"client_id":"qa.apps.googleusercontent.com","client_secret":"solo-qa"}}"#.data(using: .utf8)!
        let oauthInyectado = #"{"installed":{"client_id":"qa.apps.googleusercontent.com","client_secret":"abc\nOTRA_CLAVE=1"}}"#.data(using: .utf8)!
        comprobar("OAuth YouTube acepta escritorio y rechaza web/inyección",
                  YouTubeOAuth.clienteEsValido(oauthEscritorio)
                    && !YouTubeOAuth.clienteEsValido(oauthWeb)
                    && !YouTubeOAuth.clienteEsValido(oauthInyectado))
        let ordenMusicaAgente = PerfilAgente.invocacion(
            en: "Oye, \(nombreQA), pon música", activadores: activadores)?.contenido
        let planMusicaAgente = ordenMusicaAgente.flatMap {
            AgenteNucleo.planificar($0, catalogo: ModoCatalogo(modos: ModosStore.todos()),
                                    ignorarInterruptor: true)
        }
        comprobar("nombre inyectado + música atraviesa activador y núcleo",
                  ordenMusicaAgente == "pon música"
                    && planMusicaAgente?.cadena.acciones.first?.modo.base == "musica"
                    && planMusicaAgente?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && planMusicaAgente?.cadena.contenido.isEmpty == true)
        let catalogoFixture = """
        {"resultCount":1,"results":[{"trackId":154339650,"trackName":"Nuestro Juramento","artistName":"julio jaramillo","trackViewUrl":"https://music.apple.com/ec/album/nuestro-juramento/154339397?i=154339650"}]}
        """.data(using: .utf8)!
        let cancionCatalogo = AppleMusicCatalogo.decodificar(catalogoFixture)
        comprobar("catálogo Apple decodifica primer resultado seguro",
                  cancionCatalogo?.id == "154339650"
                    && cancionCatalogo?.url.scheme == "music"
                    && cancionCatalogo?.url.host == "music.apple.com")
        comprobar("catálogo Apple verifica título y artista",
                  cancionCatalogo.map {
                    AppleMusicCatalogo.coincide($0, titulo: "Nuestro Juramento",
                                                artista: "Julio Jaramillo")
                        && !AppleMusicCatalogo.coincide($0, titulo: "AnaLucia_01", artista: "")
                  } == true)
        comprobar("búsqueda de catálogo es HTTPS y acotada",
                  AppleMusicCatalogo.urlBusqueda("Julio Jaramillo", pais: "EC")?.absoluteString
                    .contains("limit=1") == true)
        comprobar("URL propia segura", Musica.plantillaSegura("https://ejemplo.test/buscar?q={q}"))
        comprobar("rechaza esquema ejecutable", !Musica.plantillaSegura("javascript:alert('{q}')"))
        comprobar("HTTP solo local", Musica.plantillaSegura("http://localhost:8080/?q={q}")
                    && !Musica.plantillaSegura("http://ejemplo.test/?q={q}"))
        comprobar("Atajo musical verifica artista real",
                  AppleAtajos.coincideMusica(consulta: "Jessi Uribe",
                                              titulo: "Dulce pecado", artista: "Jessi Uribe"))
        comprobar("Atajo musical verifica título real",
                  AppleAtajos.coincideMusica(consulta: "La vida es bella",
                                              titulo: "La vida es bella", artista: "Artista"))
        comprobar("Atajo musical rechaza pista anterior",
                  !AppleAtajos.coincideMusica(consulta: "Jessi Uribe",
                                               titulo: "AnaLucia_01", artista: "Voz local"))

        let fraseCapturaExacta = "Haz una captura de una sección, guárdala en Descargas con el nombre \"informe\", cópiala y ábrela."
        let captura = SolicitudCapturaMac.interpretar(fraseCapturaExacta)
        comprobar("captura interpreta área, salida y nombre",
                  captura.tipo == .imagen && captura.area == .seleccion
                    && captura.destino == .descargas && captura.nombre == "informe"
                    && captura.guardar && captura.copiar && captura.abrir,
                  "\(captura.area.rawValue) · \(captura.destino.rawValue) · \(captura.nombre ?? "nil")")
        let capturaSTT = SolicitudCapturaMac.interpretar(
            "Oye, \(nombreQA), haz una captura de una sección, guárdala en Descargas con el nombre de informe y, por favor, copia la y luego abre la.")
        comprobar("captura tolera pronombres separados por STT",
                  capturaSTT.area == .seleccion && capturaSTT.destino == .descargas
                    && capturaSTT.nombre == "informe" && capturaSTT.guardar
                    && capturaSTT.copiar && capturaSTT.abrir,
                  "nombre=\(capturaSTT.nombre ?? "nil") copiar=\(capturaSTT.copiar) abrir=\(capturaSTT.abrir)")

        // Prueba la orquestación de la segunda mitad (archivo → copiar → abrir)
        // con destinos inyectados: no cambia el clipboard del usuario ni lanza
        // Preview durante el pipeline de QA. La implementación real usa AppKit.
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-captura-qa-\(UUID().uuidString).png")
        let fixtureData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlGDfQAAAAASUVORK5CYII=")
        let fixtureOK = fixtureData.flatMap {
            do { try $0.write(to: fixture, options: .atomic); return true }
            catch { return false }
        } ?? false
        var urlCopiada: URL?
        var tipoCopiado: TipoCapturaMac?
        var urlAbierta: URL?
        let post = CapturaMac.accionesPosteriores(
            captura, archivo: fixture,
            copiador: { url, tipo in
                urlCopiada = url; tipoCopiado = tipo
                return NSImage(contentsOf: url) != nil
            },
            abridor: { url in urlAbierta = url; return true })
        comprobar("captura ejecuta copiar y abrir después de guardar",
                  fixtureOK && post.copiada && post.abierta && post.completo
                    && urlCopiada == fixture && tipoCopiado == .imagen && urlAbierta == fixture,
                  "copiada=\(post.copiada) abierta=\(post.abierta) completa=\(post.completo)")
        let postAperturaFallida = CapturaMac.accionesPosteriores(
            captura, archivo: fixture,
            copiador: { _, _ in true },
            abridor: { _ in false })
        comprobar("captura no declara éxito si una acción final falla",
                  postAperturaFallida.copiada && !postAperturaFallida.abierta
                    && !postAperturaFallida.completo)
        try? FileManager.default.removeItem(at: fixture)
        let grabacion = SolicitudCapturaMac.interpretar(
            "Graba la pantalla durante 15 segundos con micrófono y guarda en Documentos",
            duracionPredeterminada: 0)
        comprobar("grabación interpreta duración y audio",
                  grabacion.tipo == .video && grabacion.duracion == 15
                    && grabacion.microfono && grabacion.destino == .documentos)
        let nombreVideoAutomatico = CapturaMac.nombreSeguro(nil, tipo: .video)
        comprobar("grabación automática conserva segundos y termina en .mov",
                  nombreVideoAutomatico.hasSuffix(".mov")
                    && nombreVideoAutomatico.range(
                        of: #"\d{2}\.\d{2}\.\d{2}\.mov$"#,
                        options: .regularExpression) != nil,
                  nombreVideoAutomatico)
        comprobar("extensión de video incompatible se normaliza a .mov",
                  CapturaMac.nombreSeguro("demostración.mp4", tipo: .video)
                    == "demostración.mov")
        comprobar("puntos del nombre no se confunden con una extensión",
                  CapturaMac.nombreSeguro("informe.final", tipo: .video)
                    == "informe.final.mov")
        comprobar("captura automática termina en .png",
                  CapturaMac.nombreSeguro(nil, tipo: .imagen).hasSuffix(".png"))
        let fraseGrabacionExacta =
            "Graba la pantalla durante 15 segundos con micrófono y guarda en documentos."
        let planGrabacion = ModoResolver.detectarPedidoNatural(
            fraseGrabacionExacta, catalogo: ModoCatalogo(modos: ModosStore.todos()),
            permitirCapturas: true)
        comprobar("grabación natural funciona sin activador ni modo",
                  planGrabacion?.cadena.acciones.first?.modo.accion == "grabar_pantalla"
                    && planGrabacion?.cadena.contenido == fraseGrabacionExacta,
                  planGrabacion?.descripcion ?? "nil")
        var resolucionGrabacion: ResultadoModo?
        ModoResolver.resolver(texto: fraseGrabacionExacta,
                              modoBase: ModosStore.modo("dictado"),
                              contexto: nil, vivo: nil) { resolucionGrabacion = $0 }
        let usaConfirmacion: Bool
        if case let .preguntarPlan(p)? = resolucionGrabacion {
            usaConfirmacion = p.cadena.acciones.first?.modo.accion == "grabar_pantalla"
        } else { usaConfirmacion = false }
        comprobar("resolver principal propone grabación en vez de dictarla",
                  usaConfirmacion)
        let planGrabemos = AgenteNucleo.planificarCaptura(
            "Oye, Bto, grabemos la pantalla, por favor.")
        comprobar("grabemos la pantalla entra al ejecutor local",
                  planGrabemos?.cadena.acciones.first?.modo.accion == "grabar_pantalla")
        let frasesRealesAclaracion = [
            "Grabemos.",
            "Hagamos una grabación.",
            "Inicia una grabación.",
            "Comienza una grabación.",
        ]
        for frase in frasesRealesAclaracion {
            comprobar("grabación ambigua pregunta área · \(frase)",
                      AgenteNucleo.necesitaAclararAreaCaptura(frase)
                        && AgenteNucleo.planificarCaptura(frase) == nil)
        }
        let pedidoAmbiguo = "Hagamos una grabación y guárdala en Documentos"
        let pedidoPantalla = AgenteNucleo.completarAclaracionCaptura(
            pedido: pedidoAmbiguo, respuesta: "Toda la pantalla, por favor")
        let pedidoVentana = AgenteNucleo.completarAclaracionCaptura(
            pedido: pedidoAmbiguo, respuesta: "Una ventana")
        comprobar("aclaración conserva pedido y completa pantalla",
                  pedidoPantalla.map {
                    AgenteNucleo.planificarCaptura($0)?.cadena.acciones.first?.modo.accion
                        == "grabar_pantalla"
                        && SolicitudCapturaMac.interpretar($0, tipoForzado: .video).area == .completa
                        && $0.contains("guárdala en Documentos")
                  } == true,
                  pedidoPantalla ?? "nil")
        comprobar("aclaración conserva pedido y completa ventana",
                  pedidoVentana.map {
                    AgenteNucleo.planificarCaptura($0)?.cadena.acciones.first?.modo.accion
                        == "grabar_pantalla"
                        && SolicitudCapturaMac.interpretar($0, tipoForzado: .video).area == .ventana
                        && $0.contains("guárdala en Documentos")
                  } == true,
                  pedidoVentana ?? "nil")
        comprobar("aclaración no consume una respuesta ajena",
                  AgenteNucleo.completarAclaracionCaptura(
                    pedido: pedidoAmbiguo, respuesta: "Este es un dictado normal") == nil)
        comprobar("grabación de audio no se convierte en pantalla",
                  AgenteNucleo.planificarCaptura(
                    "Hagamos una grabación de audio para el podcast") == nil)
        comprobar("narración futura no ejecuta una grabación",
                  AgenteNucleo.planificarCaptura(
                    "Cuando grabemos la pantalla mañana, avísame") == nil
                    && !AgenteNucleo.necesitaAclararAreaCaptura(
                        "Cuando comience una grabación, guarda silencio"))
        let modoGrabacion = planGrabacion?.cadena.acciones.first?.modo
            ?? Modo(id: "qa-grabacion", nombre: "Grabación", icono: "record.circle",
                    base: "accion", accion: "grabar_pantalla")
        let cadenaGrabacion = ModoCadena(
            transforms: [],
            acciones: [ModoAccionPlan(modo: modoGrabacion, destinatario: nil)],
            contenido: fraseGrabacionExacta)
        comprobar("grabación exige silencio total del asistente",
                  MensajesAgente.requiereSilencioTotal(cadenaGrabacion))

        let fraseManualWA = "Oye, \(nombreQA), haz una grabación en pantalla y luego guarda en mis documentos, "
            + "cópialo en el portapapeles o envíalo por WhatsApp a Andrés"
        let grabacionManualWA = SolicitudCapturaMac.interpretar(
            fraseManualWA, duracionPredeterminada: 0)
        let argsManualWA = CapturaMac.argumentos(grabacionManualWA,
            archivo: URL(fileURLWithPath: "/tmp/btodicta-manual.mov"))
        comprobar("grabación sin duración queda continua y conserva toda la cadena",
                  grabacionManualWA.tipo == .video
                    && grabacionManualWA.duracion == nil
                    && grabacionManualWA.detencion == "continua_btodicta"
                    && grabacionManualWA.destino == .documentos
                    && grabacionManualWA.copiar
                    && grabacionManualWA.compartirWhatsApp
                    && grabacionManualWA.contactoWhatsApp == "Andrés"
                    && argsManualWA.contains("-v") && !argsManualWA.contains("-i")
                    && !argsManualWA.contains("-U") && !argsManualWA.contains("-V"),
                  grabacionManualWA.detallePlan + " | " + argsManualWA.joined(separator: " "))
        let grabacionDocumentosSinPreposicion = SolicitudCapturaMac.interpretar(
            "Oye, \(nombreQA), graba la pantalla hasta que yo la detenga y guarda mis documentos",
            duracionPredeterminada: 30)
        comprobar("guarda mis documentos conserva destino y control continuo",
                  grabacionDocumentosSinPreposicion.destino == .documentos
                    && grabacionDocumentosSinPreposicion.controlContinuoBtoDicta
                    && grabacionDocumentosSinPreposicion.duracion == nil)
        let grabacionPredeterminada = SolicitudCapturaMac.interpretar(
            "Haz una grabación de pantalla y guarda en Documentos",
            duracionPredeterminada: 30)
        comprobar("duración predeterminada parametrizable detiene sola",
                  grabacionPredeterminada.duracionAutomatica == 30
                    && CapturaMac.argumentos(grabacionPredeterminada,
                        archivo: URL(fileURLWithPath: "/tmp/btodicta-30.mov"))
                        .suffix(3).contains("30"),
                  grabacionPredeterminada.detallePlan)
        let grabacionManualExplicita = SolicitudCapturaMac.interpretar(
            "Graba la pantalla hasta que yo la detenga", duracionPredeterminada: 30)
        comprobar("orden manual explícita vence al tiempo configurado",
                  grabacionManualExplicita.duracion == nil
                    && grabacionManualExplicita.detencion == "continua_btodicta")
        let modoCompartirVideo = Modo(id: "qa-video-wa", nombre: "Video WhatsApp",
            icono: "record.circle", base: "accion", accion: "captura_compartir")
        let cadenaVideoWA = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoCompartirVideo, destinatario: "Andrés")],
            contenido: fraseManualWA)
        comprobar("video para WhatsApp también silencia voz y sonidos",
                  MensajesAgente.requiereSilencioTotal(cadenaVideoWA))
        var modoTraducir = ModosStore.modo("traducir")
        modoTraducir.id = "qa-traducir"
        let cadenaTransformaYGraba = ModoCadena(
            transforms: [modoTraducir],
            acciones: cadenaGrabacion.acciones,
            contenido: "traduce y graba la pantalla")
        comprobar("cadena con grabación también queda silenciosa",
                  MensajesAgente.requiereSilencioTotal(cadenaTransformaYGraba))
        let modoCaptura = Modo(id: "qa-captura", nombre: "Captura", icono: "camera",
                               base: "accion", accion: "captura_pantalla")
        let cadenaCapturaSilencio = ModoCadena(
            transforms: [],
            acciones: [ModoAccionPlan(modo: modoCaptura, destinatario: nil)],
            contenido: "captura la pantalla")
        comprobar("captura estática conserva respuestas configuradas",
                  !MensajesAgente.requiereSilencioTotal(cadenaCapturaSilencio))
        comprobar("captura responde al resultado y no deja acuse previo pegado",
                  MensajesAgente.esperaResultado(cadenaCapturaSilencio))
        comprobar("narración sobre grabación no ejecuta la herramienta",
                  AgenteNucleo.planificarCaptura(
                    "El programa graba la pantalla durante 15 segundos para una demostración.") == nil)
        let compartirCaptura = SolicitudCapturaMac.interpretar(
            "Toma una captura de pantalla y envíala por WhatsApp al grupo TI Noticias")
        comprobar("WhatsApp queda como preparación segura",
                  compartirCaptura.compartirWhatsApp && compartirCaptura.copiar
                    && compartirCaptura.contactoWhatsApp == "grupo TI Noticias",
                  compartirCaptura.contactoWhatsApp ?? "nil")
        let fraseTomoWA = "Tomo una captura y la envío por WhatsApp a Andrés."
        let planTomoWA = AgenteNucleo.planificarCaptura(fraseTomoWA)
        let solicitudTomoWA = SolicitudCapturaMac.interpretar(fraseTomoWA)
        comprobar("STT toma→tomo conserva captura a contacto",
                  planTomoWA?.cadena.acciones.first?.modo.accion == "captura_compartir"
                    && solicitudTomoWA.compartirWhatsApp
                    && solicitudTomoWA.contactoWhatsApp == "Andrés",
                  solicitudTomoWA.contactoWhatsApp ?? "nil")
        comprobar("tomo narrativo no acciona captura",
                  AgenteNucleo.planificarCaptura(
                    "Tomo capturas para mis informes todos los días.") == nil
                    && AgenteNucleo.planificarCaptura(
                        "Ayer tomó una captura y la envió por WhatsApp.") == nil)
        comprobar("pegado WA espera foco y nunca confunde otra app",
                  PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                    bundleFrente: "com.apple.finder", bundleEsperado: "net.whatsapp.WhatsApp",
                    intento: 2, maxIntentos: 25) == .esperar
                    && PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 3, maxIntentos: 25) == .pegar(autoEnviar: false)
                    && PegadoWhatsApp.decidir(politica: .enviar, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 3, maxIntentos: 25) == .pegar(autoEnviar: true)
                    && PegadoWhatsApp.decidir(politica: .preparar, appDisponible: true,
                        bundleFrente: "com.apple.finder",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 25, maxIntentos: 25) == .manual
                    && PegadoWhatsApp.decidir(politica: .portapapeles, appDisponible: true,
                        bundleFrente: "net.whatsapp.WhatsApp",
                        bundleEsperado: "net.whatsapp.WhatsApp",
                        intento: 0, maxIntentos: 25) == .manual)
        SeguridadTeclado.bloquearRetorno(durante: 1)
        comprobar("adjunto WhatsApp bloquea Enter automático pendiente",
                  !SeguridadTeclado.retornoPermitido)
        let waAntes = EstadoAdjuntoWhatsApp(imagenes: 4, dialogos: 0,
            marcadores: 0, botonesEnviar: 1)
        comprobar("autoenvío WA exige evidencia nueva del adjunto",
                  !WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                    despues: waAntes)
                    && WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                        despues: EstadoAdjuntoWhatsApp(imagenes: 5, dialogos: 0,
                            marcadores: 0, botonesEnviar: 1))
                    && !WhatsAppAccesibilidad.adjuntoConfirmado(antes: waAntes,
                        despues: EstadoAdjuntoWhatsApp(imagenes: 5, dialogos: 0,
                            marcadores: 0, botonesEnviar: 0)))
        let cuarto = SolicitudCapturaMac.interpretar(
            "Captura el cuadrante superior derecho y guarda en el escritorio")
        let argsCuarto = CapturaMac.argumentos(cuarto,
            archivo: URL(fileURLWithPath: "/tmp/btodicta-qa.png"))
        let regionValida = argsCuarto.firstIndex(of: "-R").flatMap { i -> Bool? in
            guard i + 1 < argsCuarto.count else { return false }
            let nums = argsCuarto[i + 1].split(separator: ",").compactMap { Double($0) }
            return nums.count == 4 && nums[2] > 0 && nums[3] > 0
        } ?? false
        comprobar("cuadrante usa región o selector nativo seguro",
                  cuarto.area == .superiorDerecha
                    && (regionValida || (argsCuarto.contains("-i") && argsCuarto.contains("-s"))),
                  argsCuarto.joined(separator: " "))
        comprobar("acciones de pantalla registradas",
                  Acciones.valido("captura_pantalla") && Acciones.valido("grabar_pantalla")
                    && Acciones.valido("captura_compartir"))
        comprobar("núcleo enruta captura natural",
                  AgenteNucleo.planificarCaptura("Por favor, haz una captura de la ventana y guárdala en Descargas")?
                    .cadena.acciones.first?.modo.accion == "captura_pantalla")
        let planCapturaSinActivador = ModoResolver.detectarPedidoNatural(
            fraseCapturaExacta, catalogo: ModoCatalogo(modos: ModosStore.todos()),
            permitirCapturas: true)
        comprobar("captura exacta funciona sin activador ni modo",
                  planCapturaSinActivador?.cadena.acciones.first?.modo.accion == "captura_pantalla"
                    && planCapturaSinActivador?.cadena.contenido == fraseCapturaExacta)
        comprobar("narración de captura no acciona",
                  AgenteNucleo.planificarCaptura("La captura de pantalla del informe fue enviada ayer") == nil)

        let modoMusicaRespuesta = ModosStore.modo("musica")
        let cadenaSoloMusica = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoMusicaRespuesta, destinatario: nil)],
            contenido: "música andina")
        comprobar("Música espera resultado real", MensajesAgente.esperaResultado(cadenaSoloMusica))
        let modoArchivo = Modo(id: "qa-archivo", nombre: "Archivo", icono: "doc",
                               base: "accion", accion: "archivo")
        let cadenaArchivo = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: modoArchivo, destinatario: nil)],
            contenido: "informe final")
        comprobar("acuse operativo breve",
                  MensajesAgente.acuse(cadenaArchivo).hasPrefix("De acuerdo, voy a "))
        let preguntaArchivo = ModoPlanificador.pregunta(para: cadenaArchivo)
        let preguntaHablada = MensajesAgente.confirmacion(preguntaArchivo,
                                                           modoNormal: ModosStore.modo("dictado"))
        comprobar("pregunta hablada explica fn y X",
                  preguntaHablada.contains("función una vez")
                    && preguntaHablada.contains("X") && preguntaHablada.contains("Dictado")
                    && preguntaHablada.contains("buscar un archivo")
                    && !preguntaHablada.contains("abrir buscar"),
                  preguntaHablada)
        if let apple = Musica.proveedor("apple_music") {
            let tocando = Musica.mensaje(estado: .reproduciendo, proveedor: apple,
                                         consulta: "música andina", intencion: .reproducir)
            let buscando = Musica.mensaje(estado: .busqueda, proveedor: apple,
                                          consulta: "música andina", intencion: .reproducir)
            let buscarSolo = Musica.mensaje(estado: .busqueda, proveedor: apple,
                                            consulta: "música andina", intencion: .buscar)
            comprobar("Música distingue play de búsqueda",
                      tocando.contains("reproduciendo")
                        && buscando.contains("No pude reproducir")
                        && buscando.contains("búsqueda")
                        && buscarSolo.contains("te abrí la búsqueda")
                        && !buscarSolo.contains("No pude"),
                      tocando + " | " + buscando + " | " + buscarSolo)
        } else { comprobar("proveedor Apple disponible en catálogo", false) }
        comprobar("formatos de respuesta estables",
                  FormatoRespuestaAgente.texto.rawValue == "texto"
                    && FormatoRespuestaAgente.textoVoz.rawValue == "texto_voz")

        let moonshot = ChatIA.fijos.first { $0.id == "moonshot" }
        let reqMoonshot = moonshot?.requestChat(prompt: "Corrige este texto", temperatura: 0.15, textLen: 18)
        let bodyMoonshot = reqMoonshot?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        comprobar("Kimi API usa endpoint y parámetros oficiales",
                  reqMoonshot?.url?.absoluteString == "https://api.moonshot.ai/v1/chat/completions"
                    && bodyMoonshot?["model"] as? String == "kimi-k2.6"
                    && (bodyMoonshot?["thinking"] as? [String: String])?["type"] == "disabled"
                    && bodyMoonshot?["temperature"] == nil)
        let kimiCuenta = ChatIA.fijos.first { $0.id == "kimi_code" }
        let reqKimiCuenta = kimiCuenta?.requestChat(prompt: "Corrige este texto", temperatura: 0.15, textLen: 18)
        let bodyKimiCuenta = reqKimiCuenta?.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        comprobar("Kimi por cuenta queda separado e identificado",
                  reqKimiCuenta?.url?.absoluteString == "https://api.kimi.com/coding/v1/chat/completions"
                    && bodyKimiCuenta?["model"] as? String == "kimi-for-coding"
                    && bodyKimiCuenta?["temperature"] == nil
                    && reqKimiCuenta?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("BtoDicta/") == true
                    && ChatIA.precioDe("kimi_code", "kimi-for-coding")?.contains("cuenta") == true)
        let codexCuenta = ChatIA.fijos.first { $0.id == "codex_account" }
        comprobar("ChatGPT por cuenta es texto vía Codex y no una API falsa",
                  codexCuenta?.esCuentaCodex == true
                    && codexCuenta?.base == "codex://account"
                    && codexCuenta?.requestChat(prompt: "Corrige", temperatura: 0,
                                                textLen: 7) == nil
                    && ChatIA.precioDe("codex_account", "automático")?.contains("plan ChatGPT") == true)
        comprobar("cuenta Codex no se anuncia como motor de embeddings",
                  !EmbeddingSearch.motores.contains(where: { $0.id == "codex_account" }))
        comprobar("catálogo de pulido excluye clasificadores y audio",
                  !ChatIA.modeloAptoParaPulido("meta-llama/llama-prompt-guard-2-86m")
                    && !ChatIA.modeloAptoParaPulido("meta-llama/Llama-Guard-4-12B")
                    && !ChatIA.modeloAptoParaPulido("whisper-large-v3-turbo")
                    && !ChatIA.modeloAptoParaPulido("nomic-embed-text")
                    && ChatIA.modeloAptoParaPulido("openai/gpt-oss-120b"))
        comprobar("selección no generativa cae al modelo seguro",
                  ChatIA.modeloSeguroParaPulido(
                    "meta-llama/llama-prompt-guard-2-86m",
                    respaldo: "llama-3.3-70b-versatile") == "llama-3.3-70b-versatile")
        let qaGroq = ChatIA(id: "qa-groq", nombre: "QA Groq", base: "https://example.com/v1",
                            modelo: "qa-chat", keyEnv: "", local: false)
        let qaCodex = ChatIA(id: "qa-codex", nombre: "QA Codex", base: "codex://qa",
                             modelo: "qa-chat", keyEnv: "", local: false)
        let qaLocal = ChatIA(id: "qa-local", nombre: "QA Local", base: "http://localhost:1/v1",
                             modelo: "qa-chat", keyEnv: "", local: true)
        let ordenPulido = ChatIA.ordenarPulido(
            [qaGroq, qaCodex, qaLocal], preferida: qaCodex.id,
            orden: [qaGroq.id, qaLocal.id, qaGroq.id])
        comprobar("IA elegida encabeza la cascada sin duplicados",
                  ordenPulido.map(\.id) == [qaCodex.id, qaGroq.id, qaLocal.id],
                  ordenPulido.map(\.id).joined(separator: ", "))
        let originalPulidoQA = "Necesitamos revisar mañana el informe completo con todo el equipo."
        comprobar("pulido rechaza puntaje de clasificador",
                  LLMPostProcess.razonPulidoInvalido(
                    original: originalPulidoQA, pulido: "0.9381640553474426") != nil)
        comprobar("pulido rechaza colapso de contenido verbal",
                  LLMPostProcess.razonPulidoInvalido(
                    original: originalPulidoQA, pulido: "42") != nil)
        comprobar("pulido acepta texto corregido y decimal dictado intacto",
                  LLMPostProcess.razonPulidoInvalido(
                    original: originalPulidoQA,
                    pulido: "Necesitamos revisar mañana el informe completo con todo el equipo.") == nil
                    && LLMPostProcess.razonPulidoInvalido(
                        original: "0.9381640553474426", pulido: "0.9381640553474426") == nil)
        comprobar("marcador STT de silencio no llega al pulido",
                  TextoTranscrito.limpiar(" (empty) \n").isEmpty
                    && TextoTranscrito.limpiar("<|no_speech|>").isEmpty)
        comprobar("una frase real que menciona empty se conserva",
                  TextoTranscrito.limpiar("La palabra empty aparece en el informe.")
                    == "La palabra empty aparece en el informe.")
        comprobar("pulido adapta espera al texto y al contexto",
                  PoliticaPulido.espera(texto: 120, contexto: 2000) == 8
                    && PoliticaPulido.espera(texto: 10000, contexto: 12000) > 90
                    && PoliticaPulido.espera(texto: 120, contexto: 15000) > 30)
        let historialPrincipalQA = URL(fileURLWithPath: "/tmp/12-34-56.txt")
        let historialRecuperadoQA = HistoryWriter.textoRecuperadoURL(para: historialPrincipalQA)
        comprobar("historial asocia el rescate sin duplicarlo como otro dictado",
                  HistoryWriter.esTextoPrincipal(historialPrincipalQA)
                    && !HistoryWriter.esTextoPrincipal(historialRecuperadoQA)
                    && historialRecuperadoQA.lastPathComponent == "12-34-56.recuperado.txt")
        let modelosCodex = AgenteCodex.modelosDisponibles()
        comprobar("selector Codex enumera automático y familia 5.6",
                  modelosCodex.first?.id == "automatico"
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-sol" })
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-terra" })
                    && modelosCodex.contains(where: { $0.id == "gpt-5.6-luna" }),
                  modelosCodex.map(\.id).joined(separator: ", "))
        comprobar("razonamiento Codex acotado para voz",
                  AgenteCodex.esfuerzosDisponibles.map(\.id)
                    == ["automatico", "low", "medium", "high", "xhigh"])

        let catalogo = ModoCatalogo(modos: ModosStore.todos())
        let gmailLargo = "\(fraseQA), abre Gmail y escribe un correo electrónico bien estructurado para usuario@example.com y que diga lo siguiente y que trate sobre el siguiente asunto: Necesito que se prepare un programa para un evento mañana en la universidad."
        let invGmail = PerfilAgente.invocacion(en: gmailLargo, activadores: activadores)
        let planGmail = invGmail.flatMap { OrdenEstructurada.detectar($0.contenido,
            catalogo: catalogo, aplicaciones: []) }
        comprobar("orden global Gmail",
                  planGmail?.cadena.transforms.first?.id == "correo"
                    && planGmail?.cadena.acciones.first?.modo.accion == "gmail"
                    && planGmail?.cadena.acciones.first?.destinatario == "usuario@example.com"
                    && planGmail?.cadena.contenido.hasPrefix("Necesito que se prepare") == true,
                  "\(planGmail?.descripcion ?? "nil") | \(planGmail?.cadena.contenido ?? "nil")")
        let gmailHablado = OrdenEstructurada.detectar(
            "Abre Gmail y escribe un correo para ana perez arroba example punto com: prueba de dirección dictada.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("correo dictado con arroba/punto",
                  gmailHablado?.cadena.acciones.first?.destinatario == "anaperez@example.com",
                  gmailHablado?.cadena.acciones.first?.destinatario ?? "nil")
        let gmailPunto = OrdenEstructurada.detectar(
            "Abre Gmail y escribe un correo para beto@example.com. Necesitamos preparar el programa del evento.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("punto del STT separa cabecera y cuerpo",
                  gmailPunto?.cadena.contenido == "Necesitamos preparar el programa del evento.",
                  gmailPunto?.cadena.contenido ?? "nil")

        let outlook = OrdenEstructurada.detectar(
            "Abre Outlook y escribe un correo para equipo@example.com. Asunto: Reunión de mañana. Cuerpo: Nos reunimos a las diez.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("Outlook separa destinatario/asunto/cuerpo",
                  outlook?.cadena.acciones.first?.modo.accion == "outlook"
                    && outlook?.cadena.acciones.first?.destinatario == "equipo@example.com"
                    && outlook?.cadena.acciones.first?.asunto == "Reunión de mañana"
                    && outlook?.cadena.contenido == "Nos reunimos a las diez.",
                  "asunto=\(outlook?.cadena.acciones.first?.asunto ?? "nil") cuerpo=\(outlook?.cadena.contenido ?? "nil")")

        let word = AplicacionMac(nombre: "Microsoft Word", bundleId: "com.microsoft.Word",
                                 ruta: "/Applications/Microsoft Word.app",
                                 alias: ["microsoft word", "word"])
        let planWord = OrdenEstructurada.detectar(
            "Por favor abre Word y crea un oficio totalmente completo con encabezado, fecha, destinatario y cierre solicitando apoyo para los juegos internos de la universidad.",
            catalogo: catalogo, aplicaciones: [word])
        comprobar("orden global Word + oficio",
                  planWord?.cadena.transforms.first?.id == "oficio"
                    && planWord?.cadena.acciones.first?.modo.base == "aplicacion"
                    && planWord?.cadena.acciones.first?.modo.appBundleId == "com.microsoft.Word"
                    && planWord?.cadena.contenido.contains("totalmente completo") == true,
                  "\(planWord?.descripcion ?? "nil") | \(planWord?.cadena.contenido ?? "nil")")
        let oficioEstructurado = """
        OFICIO N° [___________]
        Quito, 18 de julio de 2026

        Señor [___________]
        [___________]

        Asunto: Solicitud de apoyo

        Estimado señor [___________],

        Solicito su apoyo para los juegos internos de la institución.

        Atentamente,

        [___________]
        """
        let preservado = DocumentosMac.contenidoParaAplicacion(oficioEstructurado,
                                                                consumidas: 0)
        comprobar("Word conserva los saltos generados por el modo Oficio",
                  preservado == oficioEstructurado && preservado.contains("\n\nAsunto:"))
        let trasPuente = DocumentosMac.contenidoParaAplicacion(
            "Word y escribe:\nPrimera línea.\n\nSegunda línea.", consumidas: 1)
        comprobar("Word quita la orden sin aplanar el documento",
                  trasPuente == "Primera línea.\n\nSegunda línea.", trasPuente)
        let formatoOficio = DocumentosMac.planWord(oficioEstructurado)
        comprobar("Oficio recibe formato profesional determinista",
                  formatoOficio.esEstructurado
                    && formatoOficio.estilos.first?.rol == "encabezado"
                    && formatoOficio.estilos.first?.negrita == true
                    && formatoOficio.estilos.first?.alineacion == .derecha
                    && formatoOficio.estilos.contains { $0.rol == "asunto" && $0.negrita }
                    && formatoOficio.estilos.contains { $0.rol == "cuerpo" && $0.alineacion == .justificada }
                    && formatoOficio.estilos.contains { $0.rol == "firma" && $0.alineacion == .centro })
        comprobar("Word usa alineaciones VBA reales, no constantes SDEF desplazadas",
                  DocumentosMac.AlineacionWord.izquierda.appleScript == "0"
                    && DocumentosMac.AlineacionWord.centro.appleScript == "1"
                    && DocumentosMac.AlineacionWord.derecha.appleScript == "2"
                    && DocumentosMac.AlineacionWord.justificada.appleScript == "3")
        comprobar("texto común de Word no se fuerza como oficio",
                  !DocumentosMac.planWord("Hola, ¿qué tal?").esEstructurado)
        let wordMencionaGmail = OrdenEstructurada.detectar(
            "Abre Word y crea un oficio que explique cómo utilizar Gmail en la universidad.",
            catalogo: catalogo, aplicaciones: [word])
        comprobar("una app citada en el contenido no roba el destino",
                  wordMencionaGmail?.cadena.acciones.first?.modo.appBundleId == "com.microsoft.Word"
                    && wordMencionaGmail?.cadena.acciones.first?.modo.base == "aplicacion")

        var modosZentrix = ModosStore.todos()
        modosZentrix.append(Modo(id: "qa-zentrix", nombre: "Zentrix", icono: "globe",
                                base: "accion", prompt: "https://zentrix.example/", esFijo: false,
                                accion: "url"))
        let planZentrix = OrdenEstructurada.detectar(
            "Abre Zentrix y crea un oficio: solicito la revisión del trámite.",
            catalogo: ModoCatalogo(modos: modosZentrix), aplicaciones: [])
        comprobar("conector web propio reutilizable",
                  planZentrix?.cadena.acciones.first?.modo.id == "qa-zentrix"
                    && planZentrix?.cadena.contenido == "solicito la revisión del trámite.")
        comprobar("web propia exige HTTPS o localhost",
                  Acciones.plantillaURLSegura("https://zentrix.example/?q={q}")
                    && Acciones.plantillaURLSegura("http://127.0.0.1:8080/?q={q}")
                    && !Acciones.plantillaURLSegura("http://zentrix.example/?q={q}")
                    && !Acciones.plantillaURLSegura("javascript:alert('{q}')"))
        comprobar("redactar sin destino no abre una app",
                  OrdenEstructurada.detectar("Redacta un correo: revisemos el contrato.",
                                             catalogo: catalogo, aplicaciones: []) == nil)
        let crearArchivo = OrdenEstructurada.detectar(
            "Crea un archivo llamado agenda de mañana: comprar materiales y llamar a Rafael.",
            catalogo: catalogo, aplicaciones: [])
        comprobar("crear archivo pide ubicación y conserva texto",
                  crearArchivo?.cadena.transforms.isEmpty == true
                    && crearArchivo?.cadena.acciones.first?.modo.accion == "archivo_nuevo"
                    && crearArchivo?.cadena.acciones.first?.nombreArchivo == "agenda de mañana"
                    && crearArchivo?.cadena.contenido == "comprar materiales y llamar a Rafael.",
                  "nombre=\(crearArchivo?.cadena.acciones.first?.nombreArchivo ?? "nil") contenido=\(crearArchivo?.cadena.contenido ?? "nil")")
        comprobar("narración no se vuelve trabajo autónomo",
                  OrdenEstructurada.detectar("Ayer abrí Word y escribí un oficio para explicar el proceso.",
                                             catalogo: catalogo, aplicaciones: [word]) == nil)

        let borrador = BorradoresCorreo.preparar(
            texto: "ASUNTO: Programa del evento\n\nEstimada Ana:\nAdjunto el programa.",
            destinatario: "ana@example.com", asuntoSugerido: nil)
        let gmailURL = BorradoresCorreo.urlGmail(borrador)
        let gmailItems = gmailURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        comprobar("borrador extrae asunto sin enviarlo",
                  borrador.asunto == "Programa del evento"
                    && !borrador.cuerpo.contains("ASUNTO:")
                    && gmailURL?.scheme == "https"
                    && gmailItems?.first(where: { $0.name == "to" })?.value == "ana@example.com"
                    && gmailItems?.first(where: { $0.name == "su" })?.value == "Programa del evento",
                  gmailURL?.absoluteString ?? "nil")

        let outlookBorrador = BorradorCorreoPreparado(
            destinatario: "equipo@example.com", asunto: "Reunión",
            cuerpo: "Nos vemos mañana")
        let outlookMailto = BorradoresCorreo.urlMail(outlookBorrador)
        let outlookItems = outlookMailto.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
        }
        comprobar("Outlook recibe un mailto con los tres campos",
                  outlookMailto?.scheme == "mailto"
                    && outlookMailto?.path == "equipo@example.com"
                    && outlookItems?.first(where: { $0.name == "subject" })?.value == "Reunión"
                    && outlookItems?.first(where: { $0.name == "body" })?.value == "Nos vemos mañana",
                  outlookMailto?.absoluteString ?? "nil")

        let musicaExacta = ModoResolver.detectarExacto(
            "modo música Spotify, Jessy Uribe", catalogo: catalogo)
        comprobar("modo Música exacto con proveedor",
                  musicaExacta?.modo.base == "musica"
                    && musicaExacta?.modo.musicaProveedor == "spotify"
                    && musicaExacta?.textoLimpio == "Jessy Uribe",
                  "base=\(musicaExacta?.modo.base ?? "nil") proveedor=\(musicaExacta?.modo.musicaProveedor ?? "nil") texto=\(musicaExacta?.textoLimpio ?? "nil")")
        let musicaInternaExacta = ModoResolver.detectarExacto(
            "modo música interno, Julio Jaramillo", catalogo: catalogo)
        comprobar("modo Música interno exacto",
                  musicaInternaExacta?.modo.musicaProveedor == "btodicta_youtube"
                    && musicaInternaExacta?.textoLimpio == "Julio Jaramillo",
                  "proveedor=\(musicaInternaExacta?.modo.musicaProveedor ?? "nil") texto=\(musicaInternaExacta?.textoLimpio ?? "nil")")
        let cadenaMusica = ModosStore.detectarCadena(
            "modo traducir inglés modo música YouTube Music, buenos días")
        comprobar("Música coexiste en cadena",
                  cadenaMusica?.transforms.map(\.id) == ["traducir"]
                    && cadenaMusica?.acciones.first?.modo.base == "musica"
                    && cadenaMusica?.acciones.first?.modo.musicaProveedor == "youtube_music"
                    && cadenaMusica?.contenido == "buenos días")
        let buscarMusicaNatural = ModoPlanificador.detectarNatural(
            "Busca música de Julio Jaramillo", catalogo: catalogo)
        comprobar("búsqueda musical natural no reproduce",
                  buscarMusicaNatural?.cadena.acciones.first?.modo.base == "musica"
                    && buscarMusicaNatural?.cadena.acciones.first?.modo.musicaAccion == "buscar"
                    && buscarMusicaNatural?.cadena.contenido.localizedCaseInsensitiveContains("Julio Jaramillo") == true,
                  "acción=\(buscarMusicaNatural?.cadena.acciones.first?.modo.musicaAccion ?? "nil") · \(buscarMusicaNatural?.cadena.contenido ?? "nil")")
        let reproducirMusicaNatural = ModoPlanificador.detectarNatural(
            "Pon una canción cualquiera de Julio Jaramillo", catalogo: catalogo)
        comprobar("reproducción musical natural conserva intención",
                  reproducirMusicaNatural?.cadena.acciones.first?.modo.base == "musica"
                    && reproducirMusicaNatural?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && Musica.extraerConsulta(reproducirMusicaNatural?.cadena.contenido ?? "",
                                              proveedor: "auto") == "Julio Jaramillo",
                  "acción=\(reproducirMusicaNatural?.cadena.acciones.first?.modo.musicaAccion ?? "nil") · \(reproducirMusicaNatural?.cadena.contenido ?? "nil")")
        let musicaInternaNatural = ModoPlanificador.detectarNatural(
            "Reproduce en reproductor interno música de Julio Jaramillo", catalogo: catalogo)
        comprobar("planificador elige reproductor interno",
                  musicaInternaNatural?.cadena.acciones.first?.modo.base == "musica"
                    && musicaInternaNatural?.cadena.acciones.first?.modo.musicaProveedor == "btodicta_youtube"
                    && musicaInternaNatural?.cadena.acciones.first?.modo.musicaAccion == "reproducir",
                  "proveedor=\(musicaInternaNatural?.cadena.acciones.first?.modo.musicaProveedor ?? "nil")")
        let musicaNuestroJuramento = ModoPlanificador.detectarNatural(
            "Pon música de Julio Jaramillo, Nuestro juramento", catalogo: catalogo)
        comprobar("artista y título se conservan completos",
                  musicaNuestroJuramento?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && Musica.extraerConsulta(musicaNuestroJuramento?.cadena.contenido ?? "",
                                              proveedor: "auto")
                        .localizedCaseInsensitiveContains("Julio Jaramillo") == true
                    && musicaNuestroJuramento?.cadena.contenido
                        .localizedCaseInsensitiveContains("Nuestro juramento") == true,
                  musicaNuestroJuramento?.cadena.contenido ?? "nil")
        let tutorialNatural = ModoPlanificador.detectarNatural(
            "Busca tutoriales de video de viajes a China", catalogo: catalogo)
        comprobar("tutorial usa el reproductor interno y búsqueda general",
                  tutorialNatural?.cadena.acciones.first?.modo.base == "musica"
                    && tutorialNatural?.cadena.acciones.first?.modo.musicaAccion == "buscar"
                    && tutorialNatural?.cadena.acciones.first?.modo.musicaProveedor == "btodicta_youtube"
                    && TipoBusquedaYouTube.inferir(tutorialNatural?.cadena.contenido ?? "") == .videos,
                  tutorialNatural?.cadena.contenido ?? "nil")
        let tutorialSinRepetirVideo = ModoPlanificador.detectarNatural(
            "Busca tutoriales de viajes a China", catalogo: catalogo)
        comprobar("tutorial conserva su tipo aunque no diga video",
                  tutorialSinRepetirVideo?.cadena.acciones.first?.modo.musicaProveedor == "btodicta_youtube"
                    && TipoBusquedaYouTube.inferir(tutorialSinRepetirVideo?.cadena.contenido ?? "") == .videos,
                  tutorialSinRepetirVideo?.cadena.contenido ?? "nil")
        comprobar("modo música interno conserva la orden buscar",
                  Musica.intencion("modo música interno, busca tutoriales de viajes a China") == .buscar)
        let qMusica = YouTubeDataAPI.componentesBusqueda("Julio Jaramillo", tipo: .musica)
        let qTutorial = YouTubeDataAPI.componentesBusqueda("tutoriales de Swift", tipo: .videos)
        comprobar("API separa música de tutoriales",
                  qMusica.queryItems?.contains(where: { $0.name == "videoCategoryId" && $0.value == "10" }) == true
                    && qTutorial.queryItems?.contains(where: { $0.name == "videoCategoryId" }) == false)
        let videoCodable = VideoYouTubeInterno(id: "M7lc1UVf-VE", titulo: "QA",
                                                canal: "YouTube", miniatura: nil)
        let videoRedondo = try? JSONDecoder().decode(VideoYouTubeInterno.self,
            from: JSONEncoder().encode(videoCodable))
        comprobar("favorito portable conserva metadatos", videoRedondo == videoCodable)
        let musicaExactaPausa = ModoResolver.detectarExacto("modo música, pausa", catalogo: catalogo)
        comprobar("modo música exacto también controla",
                  musicaExactaPausa.map {
                    Musica.comando($0.textoLimpio,
                                   accionConfigurada: $0.modo.musicaAccion) == .pausar
                  } == true)
        let controles: [(String, ComandoMusica)] = [
            ("Pausa la música", .pausar), ("pausa", .pausar),
            ("Reanuda la música", .reanudar), ("detén la música", .detener),
            ("siguiente canción", .siguiente), ("canción anterior", .anterior),
            ("cierra el reproductor", .cerrar),
            ("mezcla la música", .aleatorio),
            ("pon el video a pantalla completa", .pantallaCompleta),
            ("pon la música en modo compacto", .compacto),
        ]
        for (frase, esperado) in controles {
            let plan = ModoPlanificador.detectarNatural(frase, catalogo: catalogo)
            comprobar("control musical \(esperado.rawValue)",
                      plan?.cadena.acciones.first?.modo.musicaAccion == esperado.rawValue,
                      "\(frase) → \(plan?.cadena.acciones.first?.modo.musicaAccion ?? "nil")")
        }
        let vacio = EstadoControlMusica.vacio
        let sonando = EstadoControlMusica(reproduciendo: true, tieneContenido: true,
                                          tieneCola: true, interfazVisible: true)
        let pausado = EstadoControlMusica(reproduciendo: false, tieneContenido: true,
                                          tieneCola: true, interfazVisible: true)
        comprobar("control sin sesión vuelve al dictado",
                  !ComandoMusica.pausar.esAplicable(en: vacio)
                    && !ComandoMusica.detener.esAplicable(en: vacio)
                    && !ComandoMusica.siguiente.esAplicable(en: vacio)
                    && !ComandoMusica.anterior.esAplicable(en: vacio)
                    && !ComandoMusica.aleatorio.esAplicable(en: vacio))
        comprobar("pausa y stop exigen audio reproduciéndose",
                  ComandoMusica.pausar.esAplicable(en: sonando)
                    && ComandoMusica.detener.esAplicable(en: sonando)
                    && !ComandoMusica.pausar.esAplicable(en: pausado)
                    && !ComandoMusica.detener.esAplicable(en: pausado))
        comprobar("reanudar exige contenido pausado",
                  ComandoMusica.reanudar.esAplicable(en: pausado)
                    && !ComandoMusica.reanudar.esAplicable(en: sonando)
                    && !ComandoMusica.reanudar.esAplicable(en: vacio))
        comprobar("anterior/siguiente exigen cola",
                  ComandoMusica.siguiente.esAplicable(en: sonando)
                    && ComandoMusica.anterior.esAplicable(en: sonando)
                    && ComandoMusica.aleatorio.esAplicable(en: sonando)
                    && !ComandoMusica.siguiente.esAplicable(en: .init(
                        reproduciendo: true, tieneContenido: true,
                        tieneCola: false, interfazVisible: true)))
        let planControl = ModoPlanificador.detectarNatural("Detén la música", catalogo: catalogo)
        comprobar("compuerta reconoce solo control musical puro",
                  planControl.flatMap { Musica.controlExclusivo(en: $0.cadena) } == .detener)
        comprobar("compacto conserva el mínimo oficial de YouTube",
                  ReproductorYouTubeModel.cumpleMinimoYouTube(
                    ReproductorYouTubeModel.tamanoVideoCompacto))
        let bibliotecaQA = [
            VideoYouTubeInterno(id: "aaaaaaaaaaa", titulo: "Nuestro juramento",
                                canal: "Julio Jaramillo", miniatura: nil),
            VideoYouTubeInterno(id: "bbbbbbbbbbb", titulo: "Historia del Ecuador",
                                canal: "Aula", miniatura: nil),
            VideoYouTubeInterno(id: "ccccccccccc", titulo: "Fatalidad",
                                canal: "Julio Jaramillo", miniatura: nil),
        ]
        comprobar("filtro local busca título o canal sin red",
                  ReproductorYouTubeModel.filtrar(bibliotecaQA, por: "Jaramillo").count == 2
                    && ReproductorYouTubeModel.filtrar(bibliotecaQA, por: "historia").count == 1)
        comprobar("respaldo local ignora palabras operativas y conserva la intención",
                  YouTubeBibliotecaCache.buscar("pon música de Julio Jaramillo",
                                                en: bibliotecaQA).count == 2
                    && YouTubeBibliotecaCache.buscar("tutorial del Ecuador",
                                                     en: bibliotecaQA).map(\.id) == ["bbbbbbbbbbb"])
        comprobar("respaldo aleatorio usa toda la biblioteca sin consulta útil",
                  YouTubeBibliotecaCache.buscar("pon música", en: bibliotecaQA,
                                                permitirTodos: true).count == 3)
        comprobar("error de cuota queda tipado para activar el failover local",
                  ErrorYouTubeInterno.cuotaAgotada("QA").esCuotaAgotada
                    && !ErrorYouTubeInterno.red("QA").esCuotaAgotada)
        comprobar("aleatorio evita lo recién escuchado si hay alternativa",
                  ReproductorYouTubeModel.candidatosAleatorios(
                    bibliotecaQA, evitando: ["aaaaaaaaaaa", "bbbbbbbbbbb"]) == [2])
        comprobar("video no embebible salta una sola vuelta sin bucle",
                  ReproductorYouTubeModel.siguienteDisponible(
                    en: bibliotecaQA, despuesDe: 0, omitiendo: ["aaaaaaaaaaa"]) == 1
                    && ReproductorYouTubeModel.siguienteDisponible(
                        en: bibliotecaQA, despuesDe: 0,
                        omitiendo: Set(bibliotecaQA.map(\.id))) == nil)
        comprobar("continúa el informe no controla música",
                  ModoPlanificador.detectarNatural("Continúa el informe para rectorado",
                                                    catalogo: catalogo) == nil)
        let repetida = ModoPlanificador.detectarNatural("Pon música, pon música", catalogo: catalogo)
        comprobar("pon música repetido conserva consulta vacía",
                  repetida?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && Musica.extraerConsulta(repetida?.cadena.contenido ?? "",
                                              proveedor: "auto").isEmpty,
                  repetida?.cadena.contenido ?? "nil")
        let sinConsulta = ModoPlanificador.detectarNatural("Pon música", catalogo: catalogo)
        comprobar("pon música funciona sin artista",
                  sinConsulta?.cadena.acciones.first?.modo.musicaAccion == "reproducir"
                    && sinConsulta?.cadena.contenido.isEmpty == true)
        comprobar("siguiente sección no salta una canción",
                  ModoPlanificador.detectarNatural("Siguiente sección del informe",
                                                    catalogo: catalogo) == nil)
        var simBuscar: ResultadoMusica?
        Musica.ejecutar("Julio Jaramillo", intencion: .buscar, simular: true) { simBuscar = $0 }
        comprobar("simulación buscar solo abre resultados", simBuscar?.estado == .busqueda)
        var simReproducir: ResultadoMusica?
        Musica.ejecutar("Julio Jaramillo", intencion: .reproducir, simular: true) { simReproducir = $0 }
        comprobar("simulación reproducir exige reproducción", simReproducir?.estado == .reproduciendo)
        struct Plan { let texto: String; let accion: String; let proveedor: String?; let contiene: String }
        let planes = [
            Plan(texto: "Pon música de Jessy Uribe", accion: "musica", proveedor: nil, contiene: "Jessy Uribe"),
            Plan(texto: "Reproduce en Spotify música andina", accion: "musica", proveedor: "spotify", contiene: "andina"),
            Plan(texto: "Recuérdame mañana a las 8 llamar a Rafael", accion: "recordatorios", proveedor: nil, contiene: "mañana"),
            Plan(texto: "Agenda una reunión mañana a las 10", accion: "calendario", proveedor: nil, contiene: "mañana"),
            Plan(texto: "Busca el archivo informe final", accion: "archivo", proveedor: nil, contiene: "informe final"),
        ]
        for c in planes {
            let p = ModoPlanificador.detectarNatural(c.texto, catalogo: catalogo)
            let e = p?.cadena.acciones.first?.modo
            let id = e?.base == "musica" ? "musica" : e?.accion
            let ok = id == c.accion && (c.proveedor == nil || e?.musicaProveedor == c.proveedor)
                && p?.cadena.contenido.localizedCaseInsensitiveContains(c.contiene) == true
            comprobar("plan \(c.accion)", ok, "\(id ?? "nil") · \(p?.cadena.contenido ?? "nil")")
        }

        let notaApple = ModoPlanificador.detectarNatural(
            "Crea una nota en Notas de Apple: comprar filtros mañana.", catalogo: catalogo)
        comprobar("Nota de Apple se distingue de Nota local",
                  notaApple?.cadena.acciones.first?.modo.accion == "notas"
                    && notaApple?.cadena.transforms.isEmpty == true
                    && notaApple?.cadena.contenido == "comprar filtros mañana.",
                  "\(notaApple?.descripcion ?? "nil") · \(notaApple?.cadena.contenido ?? "nil")")
        let notaMacSTT = ModoPlanificador.detectarNatural(
            "Guarda en la aplicación Notas que diga llamar a mamá.", catalogo: catalogo)
        comprobar("Nota de Apple tolera aplicación Notas y que diga",
                  notaMacSTT?.cadena.acciones.first?.modo.accion == "notas"
                    && notaMacSTT?.cadena.contenido == "llamar a mamá.",
                  "\(notaMacSTT?.descripcion ?? "nil") · \(notaMacSTT?.cadena.contenido ?? "nil")")
        let notaAplicacion = ModoPlanificador.detectarNatural(
            "Crea una nota en la aplicación Notas: revisar el presupuesto.", catalogo: catalogo)
        comprobar("Nota de Apple consume el nombre completo de la aplicación",
                  notaAplicacion?.cadena.acciones.first?.modo.accion == "notas"
                    && notaAplicacion?.cadena.contenido == "revisar el presupuesto.",
                  notaAplicacion?.cadena.contenido ?? "nil")
        let notaLocal = ModoPlanificador.detectarNatural(
            "Crea una nota clara sobre la reunión de mañana.", catalogo: catalogo)
        comprobar("nota sin Apple conserva el modo local",
                  notaLocal?.cadena.transforms.first?.id == "nota"
                    && notaLocal?.cadena.acciones.isEmpty == true)
        comprobar("mención narrativa de Notas no ejecuta",
                  ModoPlanificador.detectarNatural(
                    "Las notas de Apple se sincronizan con el teléfono.",
                    catalogo: catalogo) == nil)
        let notaOtraApp = ModoPlanificador.detectarNatural(
            "Crea una nota en la aplicación de contabilidad sobre el cierre.", catalogo: catalogo)
        comprobar("aplicación genérica no se confunde con Notas de Apple",
                  notaOtraApp?.cadena.acciones.first?.modo.accion != "notas")

        let finderPlan = ModoPlanificador.detectarNatural(
            "Busca el archivo informe final y muéstralo en Finder", catalogo: catalogo)
        let finderSolicitud = finderPlan.map {
            ArchivosMac.interpretarSolicitud(
                $0.cadena.contenido,
                forzarFinder: $0.cadena.acciones.first?.modo.prompt == "finder")
        }
        comprobar("buscar archivo puede mostrar todos los resultados en Finder",
                  finderPlan?.cadena.acciones.first?.modo.accion == "archivo"
                    && finderPlan?.cadena.acciones.first?.modo.prompt == "finder"
                    && finderSolicitud?.mostrarEnFinder == true
                    && finderSolicitud?.consulta == "informe final",
                  "\(finderSolicitud?.consulta ?? "nil") · finder=\(finderSolicitud?.mostrarEnFinder ?? false)")
        let finderDirecto = ModoPlanificador.detectarNatural(
            "Mostrar en Finder el archivo informe final", catalogo: catalogo)
        comprobar("mostrar en Finder es una orden de archivo",
                  finderDirecto?.cadena.acciones.first?.modo.accion == "archivo"
                    && finderDirecto?.cadena.acciones.first?.modo.prompt == "finder"
                    && finderDirecto.map {
                        ArchivosMac.interpretarSolicitud(
                            $0.cadena.contenido, forzarFinder: true).consulta
                    } == "informe final")
        let finderAlFinal = ArchivosMac.interpretarSolicitud("informe final en Finder")
        comprobar("en Finder al final se separa de la consulta",
                  finderAlFinal.mostrarEnFinder && finderAlFinal.consulta == "informe final")
        comprobar("mencionar Finder como nombre no fuerza visualización",
                  !ArchivosMac.interpretarSolicitud("informe sobre Finder").mostrarEnFinder)
        let candidatosArchivo = [
            URL(fileURLWithPath: "/Users/prueba/pdot2023.txt"),
            URL(fileURLWithPath: "/Users/prueba/MANUAL.md"),
            URL(fileURLWithPath: "/Users/prueba/Informe_Final_2026.docx"),
            URL(fileURLWithPath: "/Users/prueba/final-informe-firmado.pdf"),
            URL(fileURLWithPath: "/Users/prueba/rclone-drive.log"),
        ]
        let rankingArchivo = ArchivosMac.ordenarCoincidenciasPorNombre(
            candidatosArchivo, consulta: "informe final")
        comprobar("preview de archivos filtra resultados que coinciden solo por contenido",
                  rankingArchivo.map(\.lastPathComponent) == [
                    "Informe_Final_2026.docx", "final-informe-firmado.pdf"
                  ], rankingArchivo.map(\.lastPathComponent).joined(separator: " | "))
        comprobar("preview no inventa sugerencias sin coincidencia por nombre",
                  ArchivosMac.ordenarCoincidenciasPorNombre(
                    Array(candidatosArchivo.prefix(2)), consulta: "informe final").isEmpty)

        let negativos = [
            "La música del informe fue agradable",
            "Ayer recordé la reunión del calendario",
            "El archivo explica cómo buscar música",
            "Spotify anunció una nueva tarifa",
            "Mi mamá puso música mientras trabajaba",
        ]
        for t in negativos {
            comprobar("narración no acciona", ModoPlanificador.detectarNatural(t, catalogo: catalogo) == nil, t)
        }

        let musica = ModosStore.modo("musica")
        let reversible = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: musica, destinatario: nil)], contenido: "algo")
        let recordatorio = Modo(id: "qa-rem", nombre: "Recordatorio", icono: "bell", base: "accion", accion: "recordatorios")
        let cambio = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: recordatorio, destinatario: nil)], contenido: "algo")
        let whatsapp = Modo(id: "qa-wa", nombre: "WhatsApp", icono: "message", base: "accion", accion: "whatsapp")
        let externo = ModoCadena(transforms: [], acciones: [ModoAccionPlan(modo: whatsapp, destinatario: "Andrés")], contenido: "hola")
        let capturaLocal = Modo(id: "qa-captura", nombre: "Captura", icono: "camera",
                                base: "accion", accion: "captura_pantalla")
        let cadenaCaptura = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: capturaLocal, destinatario: nil)], contenido: "pantalla")
        let capturaWA = Modo(id: "qa-captura-wa", nombre: "Captura WhatsApp", icono: "camera",
                             base: "accion", accion: "captura_compartir")
        let cadenaCapturaWA = ModoCadena(transforms: [],
            acciones: [ModoAccionPlan(modo: capturaWA, destinatario: nil)], contenido: "pantalla")
        comprobar("consultivo siempre pregunta", !PoliticaAgente.autoEjecutar(reversible, nivel: .consultivo))
        comprobar("asistido abre música", PoliticaAgente.autoEjecutar(reversible, nivel: .asistido))
        comprobar("asistido confirma cambio", !PoliticaAgente.autoEjecutar(cambio, nivel: .asistido))
        comprobar("autónomo crea local", PoliticaAgente.autoEjecutar(cambio, nivel: .autonomo))
        comprobar("externo siempre confirma", !PoliticaAgente.autoEjecutar(externo, nivel: .autonomo))
        comprobar("captura local confirma en asistido",
                  !PoliticaAgente.autoEjecutar(cadenaCaptura, nivel: .asistido)
                    && PoliticaAgente.autoEjecutar(cadenaCaptura, nivel: .autonomo))
        comprobar("captura para WhatsApp siempre confirma",
                  !PoliticaAgente.autoEjecutar(cadenaCapturaWA, nivel: .autonomo))

        var rutina = RutinaAgente(nombre: "Empezar oficina")
        rutina.frases = ["empezar oficina", "iniciar trabajo"]
        rutina.pasos = [PasoRutinaAgente(tipo: "musica", valor: "{texto}"),
                         PasoRutinaAgente(tipo: "recordatorio", valor: "revisar correo")]
        let dr = RutinasAgenteStore.detectar("Empezar oficina música andina", en: [rutina])
        comprobar("rutina parametrizable", dr?.rutina.id == rutina.id && dr?.contenido == "música andina")
        comprobar("riesgo de rutina consolidado", RutinasAgenteStore.riesgo(rutina) == .cambioLocal)

        let atajo = AppleAtajos.url(nombre: "Casa Prueba", texto: "enciende la luz & música")?.absoluteString ?? ""
        comprobar("Atajo codifica el texto", atajo.hasPrefix("shortcuts://run-shortcut?")
                    && atajo.contains("Casa%20Prueba") && !atajo.contains(" & "), atajo)

        let planRecordatorioHora = ModoPlanificador.detectarNatural(
            "recuérdame mañana a las 8:00 p.m. llamar a Rafael", catalogo: catalogo)
        comprobar("dos puntos de una hora no cortan el contenido",
                  planRecordatorioHora?.cadena.acciones.first?.modo.accion == "recordatorios"
                    && planRecordatorioHora?.cadena.contenido == "mañana a las 8:00 p.m. llamar a Rafael",
                  planRecordatorioHora?.cadena.contenido ?? "nil")
        let planCalendarioHora = ModoPlanificador.detectarNatural(
            "Agenda una reunión mañana a las 10:00 a.m.", catalogo: catalogo)
        comprobar("calendario tampoco corta la hora",
                  planCalendarioHora?.cadena.acciones.first?.modo.accion == "calendario"
                    && planCalendarioHora?.cadena.contenido == "una reunión mañana a las 10:00 a.m.",
                  planCalendarioHora?.cadena.contenido ?? "nil")
        let planHorario = ModoPlanificador.detectarNatural(
            "Agenda un horario mañana a las 10:00", catalogo: catalogo)
        comprobar("agenda un horario enruta a Calendario y conserva título",
                  planHorario?.cadena.acciones.first?.modo.accion == "calendario"
                    && planHorario?.cadena.contenido == "un horario mañana a las 10:00",
                  planHorario?.cadena.contenido ?? "nil")
        comprobar("narración sobre un horario no crea evento",
                  ModoPlanificador.detectarNatural(
                    "La agenda de la oficina tiene un horario mañana a las 10:00",
                    catalogo: catalogo) == nil)

        let referencia = Calendar.current.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 14, minute: 30))!
        let manana = Calendar.current.date(byAdding: .day, value: 1, to: referencia)!
        func agendaCoincide(_ texto: String, hora: Int, minuto: Int = 0,
                            titulo: String = "llamar a Rafael") -> Bool {
            let p = AppleAgenda.previsualizar(texto, ahora: referencia)
            guard let f = p.fecha, p.error == nil else { return false }
            return Calendar.current.isDate(f, inSameDayAs: manana)
                && Calendar.current.component(.hour, from: f) == hora
                && Calendar.current.component(.minute, from: f) == minuto
                && p.titulo == titulo
        }
        comprobar("recordatorio exacto 8 p.m.",
                  agendaCoincide("mañana a las 8:00 p.m. llamar a Rafael", hora: 20))
        comprobar("recordatorio p. m. separado",
                  agendaCoincide("mañana a las 8:00 p. m. llamar a Rafael", hora: 20))
        comprobar("recordatorio 8 a.m.",
                  agendaCoincide("mañana a las 8:00 a.m. llamar a Rafael", hora: 8))
        comprobar("recordatorio 24 horas",
                  agendaCoincide("mañana a las 20:15 llamar a Rafael", hora: 20, minuto: 15))
        comprobar("horario natural llega completo a EventKit",
                  agendaCoincide("un horario mañana a las 10:00", hora: 10,
                                 titulo: "un horario"))
        comprobar("medianoche y mediodía no se confunden",
                  agendaCoincide("mañana a las 12:00 a.m. llamar a Rafael", hora: 0)
                    && agendaCoincide("mañana a las 12:00 p.m. llamar a Rafael", hora: 12))
        comprobar("franja de la noche",
                  agendaCoincide("mañana a las 8 de la noche llamar a Rafael", hora: 20))
        let agendaLimpia = AppleAgenda.previsualizar(
            "para mañana a las 3:00 p.m. de la tarde, una reunión con Israel", ahora: referencia)
        comprobar("fecha se retira del título",
                  agendaLimpia.error == nil && agendaLimpia.titulo == "una reunión con Israel"
                    && agendaLimpia.fecha.map { Calendar.current.component(.hour, from: $0) } == 15,
                  agendaLimpia.titulo)
        let invalida = AppleAgenda.previsualizar(
            "mañana a las 00:00 p.m. llamar a Rafael", ahora: referencia)
        comprobar("hora inválida no inventa medianoche",
                  invalida.fecha == nil && invalida.error != nil,
                  invalida.error ?? "sin error")

        let fallos = resultados.filter { !$0 }.count
        if fallos == 0 { print("AGENTCORE TODO OK") }
        else { print("AGENTCORE ✗ \(fallos) FALLOS") }
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}
