import AppKit
import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// `Button` de SwiftUI pierde ocasionalmente su título AX dentro del ScrollView
/// largo de Ajustes en macOS. NSButton conserva título, acción y etiqueta para
/// VoiceOver sin depender de esa síntesis.
private struct BotonNativoAccesible: NSViewRepresentable {
    let titulo: String
    let etiqueta: String
    let accion: () -> Void

    final class Coordinator: NSObject {
        var accion: () -> Void
        init(_ accion: @escaping () -> Void) { self.accion = accion }
        @objc func ejecutar() { accion() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(accion) }

    func makeNSView(context: Context) -> NSButton {
        let boton = NSButton(title: titulo, target: context.coordinator,
                             action: #selector(Coordinator.ejecutar))
        boton.bezelStyle = .rounded
        boton.controlSize = .small
        boton.setAccessibilityLabel(etiqueta)
        return boton
    }

    func updateNSView(_ boton: NSButton, context: Context) {
        context.coordinator.accion = accion
        boton.title = titulo
        boton.setAccessibilityLabel(etiqueta)
    }
}

@MainActor
final class AgenteSettingsModel: ObservableObject {
    @Published var activo: Bool {
        didSet {
            Config.set("agente_nucleo_activo", to: activo)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var nombre: String {
        didSet {
            Config.set("agente_nombre", to: nombre)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var personalidad: String { didSet { Config.set("agente_personalidad", to: personalidad) } }
    @Published var activadores: String {
        didSet {
            let a = FrasesConfigurables.parsear(activadores)
            Config.set("agente_activadores", to: a)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var activacionReposo: Bool {
        didSet {
            Config.set("agente_activacion_reposo", to: activacionReposo)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var siriCompatibilidadLocal: Bool {
        didSet {
            Config.set("agente_siri_compatibilidad_local", to: siriCompatibilidadLocal)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var activacionPrebuffer: Double {
        didSet {
            Config.set("agente_activacion_prebuffer_seg", to: activacionPrebuffer)
            NotificationCenter.default.post(name: .betoActivacionVozConfiguracionCambio,
                                            object: nil)
        }
    }
    @Published var activacionOrdenCorrida: Bool {
        didSet { Config.set("agente_activacion_orden_corrida", to: activacionOrdenCorrida) }
    }
    @Published var activacionEsperaAcuse: Double {
        didSet { Config.set("agente_activacion_espera_acuse_seg", to: activacionEsperaAcuse) }
    }
    @Published var activacionAcuse: Bool {
        didSet { Config.set("agente_activacion_acuse", to: activacionAcuse) }
    }
    @Published var activacionAcuseFormato: String {
        didSet { Config.set("agente_activacion_acuse_formato", to: activacionAcuseFormato) }
    }
    @Published var activacionAcuses: String {
        didSet {
            let lista = activacionAcuses.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            Config.set("agente_activacion_acuses", to: lista)
        }
    }
    @Published var autonomia: String { didSet { Config.set("agente_autonomia", to: autonomia) } }
    @Published var motor: String { didSet { Config.set("agente_motor", to: motor) } }
    @Published var fallback: Bool { didSet { Config.set("agente_fallback_local", to: fallback) } }
    @Published var proveedorIA: String { didSet { Config.set("agente_ia_proveedor", to: proveedorIA) } }
    @Published var modeloIA: String { didSet { Config.set("agente_ia_modelo", to: modeloIA) } }
    @Published var memoria: Bool { didSet { Config.set("agente_memoria_activa", to: memoria) } }
    @Published var memoriaContexto: Bool { didSet { Config.set("agente_memoria_contexto_ia", to: memoriaContexto) } }
    @Published var turnos: Double { didSet { Config.set("agente_memoria_turnos", to: Int(turnos)) } }
    @Published var pegar: Bool { didSet { Config.set("agente_pega", to: pegar) } }
    @Published var dictadoAsistido: Bool {
        didSet { Config.set("agente_dictado_asistido", to: dictadoAsistido) }
    }
    @Published var dictadoPulir: Bool {
        didSet { Config.set("agente_dictado_pulir", to: dictadoPulir) }
    }
    @Published var dictadoPegar: Bool {
        didSet { Config.set("agente_dictado_pegar", to: dictadoPegar) }
    }
    @Published var dictadoCopiar: Bool {
        didSet { Config.set("agente_dictado_copiar", to: dictadoCopiar) }
    }
    @Published var dictadoAcuse: String {
        didSet { Config.set("agente_dictado_acuse", to: String(dictadoAcuse.prefix(80))) }
    }
    @Published var respuestaActiva: Bool { didSet { Config.set("agente_respuesta_activa", to: respuestaActiva) } }
    @Published var respuestaFormato: String { didSet { Config.set("agente_respuesta_formato", to: respuestaFormato) } }
    @Published var codexEstado = "Sin comprobar"
    @Published var codexConectado = false
    @Published var codexTrabajando = false
    @Published var codexBin: String { didSet { Config.set("agente_codex_bin", to: codexBin) } }
    @Published var codexTimeout: Double { didSet { Config.set("agente_codex_timeout", to: codexTimeout) } }
    @Published var codexModelo: String { didSet { Config.set("codex_cuenta_modelo", to: codexModelo) } }
    @Published var codexEsfuerzo: String { didSet { Config.set("codex_cuenta_esfuerzo", to: codexEsfuerzo) } }

    @Published var toolMusica: Bool { didSet { Config.set("agente_tool_musica", to: toolMusica) } }
    @Published var toolCalendario: Bool { didSet { Config.set("agente_tool_calendario", to: toolCalendario) } }
    @Published var toolRecordatorios: Bool { didSet { Config.set("agente_tool_recordatorios", to: toolRecordatorios) } }
    @Published var toolArchivos: Bool { didSet { Config.set("agente_tool_archivos", to: toolArchivos) } }
    @Published var toolAplicaciones: Bool { didSet { Config.set("agente_tool_aplicaciones", to: toolAplicaciones) } }
    @Published var toolComunicaciones: Bool { didSet { Config.set("agente_tool_comunicaciones", to: toolComunicaciones) } }
    @Published var toolAtajos: Bool { didSet { Config.set("agente_tool_atajos", to: toolAtajos) } }
    @Published var toolCapturas: Bool { didSet { Config.set("agente_tool_capturas", to: toolCapturas) } }
    @Published var toolClima: Bool { didSet { Config.set("agente_tool_clima", to: toolClima) } }
    @Published var toolVolumen: Bool { didSet { Config.set("agente_tool_volumen", to: toolVolumen) } }
    @Published var volumenPaso: Double {
        didSet { Config.set("agente_volumen_paso", to: Int(volumenPaso)) }
    }
    @Published var toolNotasApple: Bool { didSet { Config.set("agente_tool_notas_apple", to: toolNotasApple) } }
    @Published var toolConexiones: Bool { didSet { Config.set("agente_tool_conexiones", to: toolConexiones) } }
    @Published var conexionSegundos: Double {
        didSet { Config.set("conexion_confirmacion_segundos", to: min(600, max(20, conexionSegundos))) }
    }
    @Published var climaUbicacionActual: Bool { didSet { Config.set("clima_ubicacion_actual", to: climaUbicacionActual) } }
    @Published var climaUbicacionPredeterminada: String {
        didSet { Config.set("clima_ubicacion_predeterminada", to: climaUbicacionPredeterminada) }
    }
    @Published var notasAppleCarpeta: String { didSet { Config.set("notas_apple_carpeta", to: notasAppleCarpeta) } }
    @Published var notasAppleCrearCarpeta: Bool { didSet { Config.set("notas_apple_crear_carpeta", to: notasAppleCrearCarpeta) } }
    @Published var notasAppleMostrar: Bool { didSet { Config.set("notas_apple_mostrar", to: notasAppleMostrar) } }
    @Published var atajoApple: String { didSet { Config.set("agente_atajo_apple", to: atajoApple) } }
    @Published var atajos: [String] = []
    @Published var atajosDetalle: [AtajoAppleDescubierto] {
        didSet { AppleAtajosCatalogo.guardar(atajosDetalle) }
    }

    @Published var capturaDestino: String { didSet { Config.set("captura_destino", to: capturaDestino) } }
    @Published var capturaGuardar: Bool { didSet { Config.set("captura_guardar", to: capturaGuardar) } }
    @Published var capturaCopiar: Bool { didSet { Config.set("captura_copiar", to: capturaCopiar) } }
    @Published var capturaAbrir: Bool { didSet { Config.set("captura_abrir", to: capturaAbrir) } }
    @Published var capturaMicrofono: Bool { didSet { Config.set("captura_microfono", to: capturaMicrofono) } }
    @Published var capturaClics: Bool { didSet { Config.set("captura_mostrar_clics", to: capturaClics) } }
    @Published var capturaWhatsAppAccion: String { didSet { Config.set("captura_whatsapp_accion", to: capturaWhatsAppAccion) } }
    @Published var capturaDuracion: Int { didSet { Config.set("captura_duracion_predeterminada", to: capturaDuracion) } }
    @Published var capturaSegmento: Int { didSet { Config.set("captura_segmento_segundos", to: capturaSegmento) } }

    @Published var cascadaMusica: [String] { didSet { Config.set("musica_cascada", to: cascadaMusica) } }
    @Published var reproducir: Bool { didSet { Config.set("musica_intentar_reproducir", to: reproducir) } }
    @Published var musicaSinConsulta: String { didSet { Config.set("musica_sin_consulta", to: musicaSinConsulta) } }
    @Published var musicaCatalogo: Bool { didSet { Config.set("musica_catalogo_automatico", to: musicaCatalogo) } }
    @Published var musicaAtajo: String { didSet { Config.set("musica_atajo_apple", to: musicaAtajo) } }
    @Published var musicaAtajoPrimero: Bool { didSet { Config.set("musica_atajo_primero", to: musicaAtajoPrimero) } }
    @Published var musicaInternaAuto: Bool { didSet { Config.set("musica_interna_autoplay", to: musicaInternaAuto) } }
    @Published var musicaInternaAvanzar: Bool { didSet { Config.set("musica_interna_avanzar", to: musicaInternaAvanzar) } }
    @Published var musicaInternaCompacta: Bool {
        didSet {
            Config.set("musica_interna_compacta", to: musicaInternaCompacta)
            let valor = musicaInternaCompacta
            DispatchQueue.main.async { ReproductorYouTubeInterno.shared.configurarCompacto(valor) }
        }
    }
    @Published var musicaInternaConsulta: String {
        didSet { Config.set("musica_interna_consulta_default", to: String(musicaInternaConsulta.prefix(160))) }
    }
    @Published var youtubeBusquedasDiarias: Int {
        didSet { Config.set("youtube_busquedas_diarias", to: youtubeBusquedasDiarias) }
    }
    @Published var youtubeEstado = ""
    @Published var youtubeTrabajando = false
    @Published var rutinas: [RutinaAgente]
    @Published var aviso = ""
    @Published var permisosTick = 0

    init() {
        activo = Config.agenteNucleoActivo(); nombre = Config.agenteNombre()
        personalidad = Config.agentePersonalidad()
        activadores = FrasesConfigurables.formatear(Config.agenteActivadores())
        activacionReposo = Config.agenteActivacionReposo()
        siriCompatibilidadLocal = Config.agenteCompatibilidadSiriLocal()
        activacionPrebuffer = Config.agenteActivacionPrebuffer()
        activacionOrdenCorrida = Config.agenteActivacionOrdenCorrida()
        activacionEsperaAcuse = Config.agenteActivacionEsperaAcuse()
        activacionAcuse = Config.agenteActivacionAcuse()
        activacionAcuseFormato = Config.agenteActivacionAcuseFormato()
        activacionAcuses = Config.agenteActivacionAcuses().joined(separator: "\n")
        autonomia = Config.agenteAutonomia(); motor = Config.agenteMotor()
        fallback = Config.agenteFallbackCerebro(); proveedorIA = Config.agenteIAProveedor()
        modeloIA = Config.agenteIAModelo(); memoria = Config.agenteMemoriaActiva()
        memoriaContexto = Config.agenteMemoriaContextoIA()
        turnos = Double(Config.agenteMemoriaTurnos()); pegar = Config.agentePega()
        dictadoAsistido = Config.agenteDictadoAsistido()
        dictadoPulir = Config.agenteDictadoPulir()
        dictadoPegar = Config.agenteDictadoPegar()
        dictadoCopiar = Config.agenteDictadoCopiar()
        dictadoAcuse = Config.agenteDictadoAcuse()
        respuestaActiva = Config.agenteRespuestaActiva()
        respuestaFormato = Config.agenteRespuestaFormato()
        codexBin = Config.agenteCodexBin(); codexTimeout = Config.agenteCodexTimeout()
        codexModelo = Config.codexCuentaModelo(); codexEsfuerzo = Config.codexCuentaEsfuerzo()
        toolMusica = Config.agenteHerramientaMusica()
        toolCalendario = Config.agenteHerramientaCalendario()
        toolRecordatorios = Config.agenteHerramientaRecordatorios()
        toolArchivos = Config.agenteHerramientaArchivos()
        toolAplicaciones = Config.agenteHerramientaAplicaciones()
        toolComunicaciones = Config.agenteHerramientaComunicaciones()
        toolAtajos = Config.agenteHerramientaAtajos(); toolCapturas = Config.agenteHerramientaCapturas()
        toolClima = Config.agenteHerramientaClima()
        toolVolumen = Config.agenteHerramientaVolumen()
        volumenPaso = Double(Config.agenteVolumenPaso())
        toolNotasApple = Config.agenteHerramientaNotasApple()
        toolConexiones = Config.agenteHerramientaConexiones()
        conexionSegundos = Config.conexionConfirmacionSegundos()
        climaUbicacionActual = Config.climaUsarUbicacionActual()
        climaUbicacionPredeterminada = Config.climaUbicacionPredeterminada()
        notasAppleCarpeta = Config.notasAppleCarpeta()
        notasAppleCrearCarpeta = Config.notasAppleCrearCarpeta()
        notasAppleMostrar = Config.notasAppleMostrarCreada()
        atajoApple = Config.agenteAtajoApple()
        capturaDestino = Config.capturaDestino(); capturaGuardar = Config.capturaGuardarArchivo()
        capturaCopiar = Config.capturaCopiarPortapapeles()
        capturaAbrir = Config.capturaAbrirAlTerminar(); capturaMicrofono = Config.capturaGrabarMicrofono()
        capturaClics = Config.capturaMostrarClics()
        capturaWhatsAppAccion = Config.capturaWhatsAppPolitica().rawValue
        capturaDuracion = Config.capturaDuracionPredeterminada()
        capturaSegmento = Config.capturaSegmentoSegundos()
        cascadaMusica = Config.musicaCascada(); reproducir = Config.musicaIntentarReproducir()
        musicaSinConsulta = Config.musicaSinConsulta()
        musicaCatalogo = Config.musicaCatalogoAutomatico()
        musicaAtajo = Config.musicaAtajoApple(); musicaAtajoPrimero = Config.musicaAtajoPrimero()
        musicaInternaAuto = Config.musicaInternaAutoReproducir()
        musicaInternaAvanzar = Config.musicaInternaAvanzarSolo()
        musicaInternaCompacta = Config.musicaInternaCompacta()
        musicaInternaConsulta = Config.musicaInternaConsultaPredeterminada()
        youtubeBusquedasDiarias = Config.youtubeBusquedasDiarias()
        rutinas = RutinasAgenteStore.todas(); atajosDetalle = AppleAtajosCatalogo.todos()
        actualizarEstadoYouTube()
    }

    func moverMusica(_ i: Int, _ delta: Int) {
        let j = i + delta; guard i >= 0, i < cascadaMusica.count, j >= 0, j < cascadaMusica.count else { return }
        cascadaMusica.swapAt(i, j)
    }

    func quitarMusica(_ id: String) { cascadaMusica.removeAll { $0 == id } }
    func agregarMusica(_ id: String) {
        guard !cascadaMusica.contains(id) else { return }; cascadaMusica.append(id)
    }

    func agregarProveedor(nombre: String, url: String) -> Bool {
        let n = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, Musica.plantillaSegura(u) else {
            aviso = "Usa una URL HTTPS con {q} (HTTP solo en localhost)."; return false
        }
        var p = Config.musicaProveedoresPersonales()
        p.removeAll { PerfilAgente.normalizar($0["nombre"] ?? "") == PerfilAgente.normalizar(n) }
        p.append(["nombre": n, "url": u]); Config.set("musica_proveedores_personales", to: p)
        if let id = Musica.personales().first(where: { $0.nombre == n })?.id { agregarMusica(id) }
        aviso = "Proveedor «\(n)» agregado."; return true
    }

    func borrarProveedor(_ id: String) {
        guard let p = Musica.proveedor(id) else { return }
        let restantes = Config.musicaProveedoresPersonales().filter {
            PerfilAgente.normalizar($0["nombre"] ?? "") != PerfilAgente.normalizar(p.nombre)
        }
        Config.set("musica_proveedores_personales", to: restantes); quitarMusica(id)
    }

    func actualizarEstadoYouTube(mensaje: String? = nil) {
        if let mensaje { youtubeEstado = mensaje; return }
        if YouTubeOAuth.conectada {
            youtubeEstado = "✓ Cuenta Google conectada por OAuth externo"
        } else if YouTubeOAuth.tieneAPIKey {
            youtubeEstado = "✓ Clave de YouTube Data API guardada"
        } else if YouTubeOAuth.tieneCliente {
            youtubeEstado = "Credenciales OAuth importadas; falta autorizar la cuenta"
        } else {
            youtubeEstado = "Sin conexión: importa OAuth de escritorio o guarda una API key"
        }
    }

    func guardarYouTubeKey(_ valor: String) -> Bool {
        let key = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20, !key.contains("\n") else {
            actualizarEstadoYouTube(mensaje: "La clave no parece válida."); return false
        }
        ApiKeys.set("YOUTUBE_DATA_API_KEY", key); actualizarEstadoYouTube(); return true
    }

    func quitarYouTubeKey() { ApiKeys.set("YOUTUBE_DATA_API_KEY", ""); actualizarEstadoYouTube() }

    func reiniciarCuotaYouTube() {
        YouTubeCuotaBusqueda.reiniciarEstimacion()
        aviso = "Contador local reiniciado. Esto no amplía ni reinicia la cuota real de Google."
    }

    func importarOAuthYouTube() {
        let p = NSOpenPanel(); p.title = "Credenciales OAuth de Google para BtoDicta"
        p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        switch YouTubeOAuth.importarCliente(desde: u) {
        case .success:
            actualizarEstadoYouTube(mensaje: "Credenciales OAuth importadas. Pulsa «Conectar cuenta Google». ")
        case .failure(let e): actualizarEstadoYouTube(mensaje: e.localizedDescription)
        }
    }

    func conectarYouTube() {
        youtubeTrabajando = true; youtubeEstado = "Esperando autorización en tu navegador…"
        YouTubeOAuth.conectar { [weak self] ok, mensaje in
            self?.youtubeTrabajando = false
            self?.actualizarEstadoYouTube(mensaje: ok ? "✓ \(mensaje)" : mensaje)
        }
    }

    func desconectarYouTube() {
        youtubeTrabajando = true
        YouTubeOAuth.desconectar { [weak self] mensaje in
            self?.youtubeTrabajando = false; self?.actualizarEstadoYouTube(mensaje: mensaje)
        }
    }

    func abrirReproductorInterno() { ReproductorYouTubeInterno.shared.mostrar() }

    func cargarAtajos() {
        AppleAtajosCatalogo.refrescar { [weak self] items in
            self?.atajosDetalle = items
            self?.atajos = items.filter(\.disponible).map(\.nombre)
        }
    }
    func instalarAtajoMusica() {
        instalarAtajoIncluido(.musica)
    }
    func estaInstalado(_ id: AtajoIncluidoID) -> Bool {
        AtajosIncluidos.estaInstalado(id, nombreAgente: nombre, nombres: atajos)
    }
    func instalarAtajoIncluido(_ id: AtajoIncluidoID) {
        let r = AtajosIncluidos.instalar(id, nombreAgente: nombre)
        aviso = r.mensaje
        if r.ok {
            if id == .musica {
                musicaAtajo = AppleAtajos.nombreMusicaIncluido
                musicaAtajoPrimero = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.cargarAtajos() }
        }
    }
    func probarClima() {
        aviso = "Consultando Open-Meteo…"
        let lugar = climaUbicacionPredeterminada.trimmingCharacters(in: .whitespacesAndNewlines)
        let consulta = lugar.isEmpty ? "clima de hoy" : "clima de \(lugar)"
        ClimaServicio.consultar(consulta) { [weak self] r in
            self?.permisosTick += 1
            self?.aviso = r.mensaje
        }
    }
    func actualizarCodex() {
        codexTrabajando = true
        AgenteCodex.estado { [weak self] estado in
            self?.codexEstado = estado.texto; self?.codexConectado = estado == .chatgpt
            self?.codexTrabajando = false
        }
    }
    func conectarCodex() {
        codexTrabajando = true; codexEstado = "Esperando autorización en el navegador…"
        AgenteCodex.autorizar { [weak self] ok, mensaje in
            self?.codexConectado = ok; self?.codexEstado = mensaje
            self?.codexTrabajando = false
        }
    }
    func guardarRutinas() { RutinasAgenteStore.guardar(rutinas); aviso = "Rutinas guardadas." }
    func nuevaRutina() { var r = RutinaAgente(nombre: "Nueva rutina"); r.pasos = [PasoRutinaAgente()]; rutinas.append(r) }
    func borrarRutina(_ i: Int) { guard rutinas.indices.contains(i) else { return }; rutinas.remove(at: i) }
    func exportarRutinas(categoria: String? = nil) {
        let seleccion = categoria.map { c in rutinas.filter { $0.categoria == c } } ?? rutinas
        let p = NSSavePanel(); p.title = "Exportar biblioteca de recetas"
        p.nameFieldStringValue = categoria.map { "Recetas-BtoDicta-\($0).json" }
            ?? "Recetas-BtoDicta.json"
        guard p.runModal() == .OK, let u = p.url else { return }
        aviso = RecetasPortables.exportar(seleccion, a: u).mensaje
    }
    func importarRutinas() {
        let p = NSOpenPanel(); p.title = "Importar recetas de BtoDicta"
        p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        switch RecetasPortables.importar(desde: u, actuales: rutinas) {
        case .success(let nuevas):
            rutinas = nuevas; RutinasAgenteStore.guardar(nuevas)
            aviso = "Importé las recetas compatibles de «\(u.lastPathComponent)»."
        case .failure(let e): aviso = "No pude importar: \(e.localizedDescription)"
        }
    }
    func copiarEjemploUniversal() {
        let orden = OrdenUniversalBeto(accion: "musica",
            parametros: ["texto": "música andina"])
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? e.encode(orden), let s = String(data: d, encoding: .utf8) else { return }
        copyText(s); aviso = "Copié una acción estructurada de ejemplo."
    }
    func probarUniversal() {
        let orden = OrdenUniversalBeto(accion: "estado_mac")
        AtajoUniversalBtoDicta.ejecutar(orden, simular: true) { [weak self] r in
            self?.aviso = r.ok ? "Contrato universal validado: \(r.mensaje)" : r.mensaje
        }
    }
}

struct AgenteView: View {
    @StateObject private var m = AgenteSettingsModel()
    @State private var proveedorNombre = ""
    @State private var proveedorURL = ""
    @State private var youtubeKey = ""
    @State private var estadoActivacion = ActivacionVoz.shared.estado

    private let violeta = Color(red: 0.36, green: 0.28, blue: 0.62)

    private var ejemploActivador: String {
        FrasesConfigurables.activadoresSeguros(FrasesConfigurables.parsear(m.activadores)).first
            ?? "la frase configurada"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Asistente por voz").font(.title2).bold()
                Text("El cerebro orquesta tus Modos y herramientas. Dictado sigue siendo Dictado: puedes apagar este núcleo sin perder nada de lo anterior.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            card("Presencia y personalidad", "person.wave.2.fill") {
                Toggle("Activar el núcleo del asistente", isOn: $m.activo)
                field("Nombre", text: $m.nombre, placeholder: "Bto, Jarvis…")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frases de activación al iniciar un dictado").font(.subheadline)
                    TextEditor(text: $m.activadores)
                        .font(.body).frame(minHeight: 58, maxHeight: 82)
                        .padding(5).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(m.activacionReposo
                         ? "Una frase por línea y mínimo dos palabras. La puntuación no importa: el ejemplo “\(ejemploActivador)” también coincide si el transcriptor agrega comas. Activadores genéricos de una palabra se ignoran. Funcionan tanto con fn como en la escucha local opcional de abajo."
                         : "Una frase por línea y mínimo dos palabras. La puntuación no importa. Activadores de una palabra como “oye” o solo el nombre se ignoran para que un dictado normal no llame al agente. Funciona dentro del dictado iniciado con fn; el micrófono no queda escuchando en reposo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Activar manos libres al decir una frase de presencia",
                       isOn: $m.activacionReposo)
                    .accessibilityHint("Mantiene Apple Speech local escuchando solo las frases configuradas")
                if m.activacionReposo {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(estadoActivacion.activo ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(estadoActivacion.descripcion).font(.caption)
                    }
                    Toggle("Permitir frase + orden en una sola toma (avanzado)",
                           isOn: $m.activacionOrdenCorrida)
                    if m.activacionOrdenCorrida {
                        HStack {
                            Text("Conservar \(String(format: "%.1f", m.activacionPrebuffer)) s en RAM")
                                .font(.caption)
                            Slider(value: $m.activacionPrebuffer, in: 2...8, step: 0.5)
                                .frame(maxWidth: 230)
                        }
                    }
                    HStack {
                        Text("Pausa para abrir el turno: \(String(format: "%.1f", m.activacionEsperaAcuse)) s")
                            .font(.caption)
                        Slider(value: $m.activacionEsperaAcuse, in: 0.8...3.0, step: 0.1)
                            .frame(maxWidth: 230)
                    }
                    Toggle("Responder al reconocer la frase", isOn: $m.activacionAcuse)
                    if m.activacionAcuse {
                        Picker("Acuse", selection: $m.activacionAcuseFormato) {
                            Text("Solo texto").tag("texto")
                            Text("Texto y voz").tag("texto_voz")
                            Text("Solo voz").tag("voz")
                        }.pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Respuestas rápidas · una por línea").font(.subheadline)
                            TextEditor(text: $m.activacionAcuses)
                                .font(.body).frame(minHeight: 62, maxHeight: 88)
                                .padding(5).background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text("BtoDicta elige una al azar y luego abre un turno limpio.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if ["texto_voz", "voz"].contains(m.activacionAcuseFormato),
                           !Config.ttsActivo() {
                            Text("TTS está apagado: por seguridad se mostrará el acuse en texto. Activa la voz del asistente en Avanzado para oírlo.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(m.activacionOrdenCorrida
                         ? "Puedes decir solo “\(ejemploActivador)” o añadir la orden en la misma toma."
                         : "Di solamente “\(ejemploActivador)” y haz una pausa. El silencio acústico configurado confirma el timbre; después del acuse, habla tu pedido en un turno limpio. Si aparece contenido pegado, el candidato se cancela.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Antes de despertar, BtoDicta conserva únicamente el búfer circular en RAM: no guarda ni sube audio y no registra texto ambiental. Como una app de terceros mantiene el micrófono en uso, macOS muestra obligatoriamente su indicador de privacidad. Para no verlo, deja esta opción apagada y usa fn o un Atajo invocado mediante Siri.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !ActivacionVoz.disponible {
                        Text("La activación flexible local requiere macOS 26. En versiones anteriores, fn y las frases dentro del dictado siguen funcionando normalmente.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pasarela inversa con Siri").font(.subheadline)
                    Text("Instala el Atajo incluido con el nombre “\(PasarelaSiriBeto.nombreSugerido(m.nombre))”. Con manos libres apagado, puedes decir “Oye Siri, \(PasarelaSiriBeto.nombreSugerido(m.nombre))” y Siri abrirá un turno limpio.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Mantener esa frase cuando BtoDicta ya usa el micrófono",
                           isOn: $m.siriCompatibilidadLocal)
                    Text(m.activacionReposo && m.siriCompatibilidadLocal
                         ? "Mientras la escucha continua ocupa el micrófono, BtoDicta reconoce localmente solo “Oye Siri” + tu nombre configurado. No suplanta a Siri ni intercepta otras órdenes; el registro distingue esta ruta local."
                         : "Con la escucha continua apagada, la frase pasa por Siri y el Atajo importado. Si la enciendes, activa este respaldo para evitar la competencia por el micrófono.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button(m.estaInstalado(.asistente) ? "Reinstalar Atajo…" : "Instalar Atajo…") {
                            m.instalarAtajoIncluido(.asistente)
                        }
                        Button("Probar pasarela") {
                            let r = PasarelaSiriBeto.probar()
                            m.aviso = r.mensaje
                        }
                    }
                    Text("El paquete viaja firmado dentro de BtoDicta y no contiene claves. macOS siempre te muestra sus acciones y exige que confirmes la importación. Si cambias el nombre del asistente, reinstálalo con el nombre nuevo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalidad").font(.subheadline)
                    TextEditor(text: $m.personalidad).font(.body).frame(minHeight: 90)
                        .padding(5).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Define tono, trato, longitud y manera de expresarse. La voz TTS se elige aparte.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            card("Autonomía", "shield.lefthalf.filled") {
                Picker("Nivel", selection: $m.autonomia) {
                    ForEach(NivelAutonomiaAgente.allCases) { Text($0.nombre).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                Text(NivelAutonomiaAgente(rawValue: m.autonomia)?.detalle ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Enviar mensajes/correos, publicar, comprar o borrar siempre exige confirmación, incluso en Autónomo.")
                    .font(.caption).foregroundStyle(.orange)
            }

            card("Respuestas", "waveform.and.speech.bubble.fill") {
                Toggle("Responder al actuar, preguntar o no entender", isOn: $m.respuestaActiva)
                if m.respuestaActiva {
                    Picker("Formato", selection: $m.respuestaFormato) {
                        Text("Solo texto").tag("texto")
                        Text("Texto y voz").tag("texto_voz")
                    }.pickerStyle(.segmented)
                    Text("Usa la personalidad y la voz preconfiguradas. Las confirmaciones se leen en voz, y cada acción responde brevemente sin inventar que tuvo éxito.")
                        .font(.caption).foregroundStyle(.secondary)
                    if m.respuestaFormato == "texto_voz", !Config.ttsActivo() {
                        Text("Activa “Que BtoDicta pueda hablarte (TTS)” en Avanzado para oírla; mientras tanto seguirá respondiendo por texto.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            card("Dictado asistido sin manos", "text.cursor") {
                Toggle("Entender órdenes como “dicta esto” o “mejora lo siguiente”",
                       isOn: $m.dictadoAsistido)
                if m.dictadoAsistido {
                    Toggle("Pulir el texto con la cascada de IA", isOn: $m.dictadoPulir)
                    Toggle("Pegar el resultado en la aplicación activa", isOn: $m.dictadoPegar)
                    Toggle("Conservar también el resultado en el portapapeles",
                           isOn: $m.dictadoCopiar)
                    field("Respuesta antes de la segunda toma", text: $m.dictadoAcuse,
                          placeholder: "Dímelo.")
                    Text("Después de la frase de presencia puedes decir “dicta esto: …”, “transcribe esto: …”, “escribe esto: …”, “corrige esto: …”, “actualiza esto: …” o “mejora esto: …”. Si dices solamente “dictado”, usa la respuesta configurada y abre otro turno automáticamente. Esta ruta no llama al cerebro ni ejecuta una aplicación.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !m.dictadoPegar && !m.dictadoCopiar {
                        Text("Activa Pegar o Portapapeles para poder recuperar el resultado.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            card("Cerebro y memoria", "brain.head.profile") {
                Picker("Cerebro principal", selection: $m.motor) {
                    Text("IA configurada en BtoDicta").tag("local")
                    Text("Hermes").tag("hermes")
                    Text("ChatGPT por cuenta (Codex)").tag("codex")
                }
                if m.motor == "hermes" || m.fallback {
                    Text(AgenteHermes.disponible
                         ? "Hermes detectado. Solo razona y responde: las acciones pasan por la política de autonomía de BtoDicta."
                         : "Hermes no está disponible; se omite sin detener al asistente.")
                        .font(.caption).foregroundStyle(AgenteHermes.disponible ? Color.secondary : Color.orange)
                    Button("Nueva conversación con Hermes") { AgenteHermes.reiniciar(); m.aviso = "Conversación de Hermes reiniciada." }
                        .controlSize(.small)
                }
                if m.motor == "codex" || m.fallback {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Circle().fill(m.codexConectado ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(m.codexEstado).font(.caption)
                            Spacer()
                            Button("Comprobar") { m.actualizarCodex() }
                                .controlSize(.small).disabled(m.codexTrabajando)
                            Button("Conectar en navegador") { m.conectarCodex() }
                                .controlSize(.small).disabled(m.codexTrabajando || !AgenteCodex.disponible)
                        }
                        Text("La autorización y renovación pertenecen al cliente oficial Codex; BtoDicta no recibe tu contraseña, cookies ni token. Consume el cupo de Codex incluido en tu plan ChatGPT, no créditos del API.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Modelo Codex", selection: $m.codexModelo) {
                            ForEach(AgenteCodex.modelosDisponibles()) { modelo in
                                Text(modelo.nombre + (modelo.oculto ? " · compatibilidad" : ""))
                                    .tag(modelo.id)
                            }
                        }
                        Picker("Razonamiento", selection: $m.codexEsfuerzo) {
                            ForEach(AgenteCodex.esfuerzosDisponibles) { esfuerzo in
                                Text(esfuerzo.nombre).tag(esfuerzo.id)
                            }
                        }
                        Text(AgenteCodex.descripcionModelo(m.codexModelo))
                            .font(.caption2).foregroundStyle(.secondary)
                        field("Ruta Codex (opcional)", text: $m.codexBin,
                              placeholder: "Vacío = autodetectar ~/.local/bin/codex")
                        HStack {
                            Text("Esperar hasta \(Int(m.codexTimeout)) s").font(.caption)
                            Slider(value: $m.codexTimeout, in: 15...180, step: 5).frame(maxWidth: 260)
                        }
                    }
                }
                Toggle("Si el cerebro principal falla, probar cerebros de respaldo", isOn: $m.fallback)
                let conectadas = ChatIA.conectadasPulido
                Picker("IA del asistente", selection: $m.proveedorIA) {
                    Text("Cascada global de pulido").tag("")
                    ForEach(conectadas, id: \.id) { Text($0.etiqueta).tag($0.id) }
                }
                field("Modelo (opcional)", text: $m.modeloIA, placeholder: "Vacío = modelo activo del proveedor")
                VStack(alignment: .leading, spacing: 3) {
                    Text("El plan mensual de ChatGPT y el API de OpenAI siguen separados. La opción Codex sirve como cerebro conversacional oficial; STT y TTS continúan usando Apple, motores locales o sus propias APIs.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Abrir plataforma API de OpenAI", destination: URL(string: "https://platform.openai.com/")!)
                        .font(.caption)
                }
                Toggle("Memoria conversacional corta (local)", isOn: $m.memoria)
                if m.memoria {
                    HStack {
                        Text("Recordar \(Int(m.turnos)) turnos").font(.subheadline)
                        Slider(value: $m.turnos, in: 1...30, step: 1).frame(maxWidth: 260)
                        Button("Borrar memoria") { MemoriaAgente.limpiar(); m.aviso = "Memoria corta borrada." }
                            .controlSize(.small)
                    }
                    Toggle("Usar esa memoria como contexto del cerebro", isOn: $m.memoriaContexto)
                    Text("Si eliges una IA de nube, el contexto necesario se envía a ese proveedor. Apágalo para conservar solo los seguimientos locales.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Pegar también la respuesta en la aplicación activa", isOn: $m.pegar)
            }

            card("Herramientas nativas", "wrench.and.screwdriver.fill") {
                Toggle("Clima actual y pronóstico", isOn: $m.toolClima)
                if m.toolClima {
                    Toggle("Usar mi ubicación actual si no digo una ciudad",
                           isOn: $m.climaUbicacionActual)
                    field("Ubicación de respaldo", text: $m.climaUbicacionPredeterminada,
                          placeholder: "Ej.: Quito, Pichincha, Ecuador")
                    HStack {
                        Text("Ubicación: \(UbicacionClima.nombreEstado())")
                        Spacer()
                        Button(UbicacionClima.estado() == .notDetermined
                               ? "Solicitar permiso" : "Ajustes de ubicación…") {
                            if UbicacionClima.estado() == .notDetermined {
                                UbicacionClima.shared.solicitarPermiso()
                            } else { UbicacionClima.abrirPrivacidad() }
                            m.permisosTick += 1
                        }.controlSize(.small)
                        Button("Probar clima ahora") { m.probarClima() }.controlSize(.small)
                    }.font(.caption)
                    Text("Solo pide una ubicación aproximada al consultar; no te rastrea ni guarda coordenadas. Para obtener el clima, envía la ciudad o las coordenadas actuales por HTTPS a Open-Meteo. Si dices una ciudad, no usa GPS.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Datos meteorológicos: Open-Meteo",
                         destination: URL(string: "https://open-meteo.com/")!)
                        .font(.caption)
                }
                Divider()
                Toggle("Música", isOn: $m.toolMusica)
                Toggle("Controlar el volumen del Mac", isOn: $m.toolVolumen)
                if m.toolVolumen {
                    HStack {
                        Text("Subir/bajar sin cifra: \(Int(m.volumenPaso)) puntos")
                            .font(.caption)
                        Slider(value: $m.volumenPaso, in: 5...30, step: 5)
                            .frame(maxWidth: 230)
                    }
                    Text("Entiende porcentajes, máximo, silencio y reactivar. Se ejecuta localmente y comprueba el nivel final; no usa IA.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Aplicaciones instaladas", isOn: $m.toolAplicaciones)
                Toggle("Borradores en Gmail, Mail, Outlook, WhatsApp y Mensajes", isOn: $m.toolComunicaciones)
                Text("Prepara y abre el borrador con destinatario/asunto/cuerpo. Nunca pulsa Enviar por ti.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Buscar y abrir archivos (Spotlight)", isOn: $m.toolArchivos)
                Divider()
                Toggle("Capturas y grabaciones de pantalla", isOn: $m.toolCapturas)
                if m.toolCapturas {
                    Picker("Guardar por defecto", selection: $m.capturaDestino) {
                        ForEach(DestinoCapturaMac.allCases) { Text($0.nombre).tag($0.rawValue) }
                    }
                    Toggle("Guardar un archivo por defecto", isOn: $m.capturaGuardar)
                    Toggle("Copiar también las capturas al portapapeles", isOn: $m.capturaCopiar)
                    Toggle("Abrir el resultado al terminar", isOn: $m.capturaAbrir)
                    Picker("Al compartir por WhatsApp", selection: $m.capturaWhatsAppAccion) {
                        ForEach(PoliticaWhatsAppCaptura.allCases) { p in
                            Text(p.nombre).tag(p.rawValue)
                        }
                    }
                    Toggle("Incluir micrófono en grabaciones", isOn: $m.capturaMicrofono)
                    Toggle("Mostrar clics en grabaciones", isOn: $m.capturaClics)
                    Picker("Si no dices duración", selection: $m.capturaDuracion) {
                        Text("Hasta que la detenga en BtoDicta").tag(0)
                        Text("15 segundos").tag(15)
                        Text("30 segundos").tag(30)
                        Text("1 minuto").tag(60)
                        Text("2 minutos").tag(120)
                        Text("5 minutos").tag(300)
                    }
                    if m.capturaDuracion == 0 {
                        Picker("Proteger grabación cada", selection: $m.capturaSegmento) {
                            Text("1 minuto").tag(60)
                            Text("5 minutos · recomendado").tag(300)
                            Text("10 minutos").tag(600)
                            Text("15 minutos").tag(900)
                            Text("30 minutos").tag(1800)
                        }
                    }
                    HStack {
                        Text("Permiso de pantalla: \(CapturaMac.permisoConcedido() ? "Permitido" : "Pendiente")")
                        Spacer()
                        Button("Solicitar permiso") {
                            let ok = CapturaMac.solicitarPermiso()
                            m.permisosTick += 1
                            m.aviso = ok ? "Permiso de pantalla concedido."
                                : "Autoriza BtoDicta en Privacidad y seguridad → Grabación de pantalla."
                        }.controlSize(.small)
                    }.font(.caption)
                    Text("Con duración, BtoDicta se detiene solo. Sin duración, empieza de inmediato: una sola pulsación de tu tecla de dictado —o ‘Detener y guardar’ en el menú— cierra el .mov. Los fragmentos periódicos protegen las grabaciones largas. El notch permanece oculto. En WhatsApp puedes dejar el archivo en el portapapeles, pegarlo para revisar o activar expresamente el autoenvío.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Recordatorios de Mac (EventKit)", isOn: $m.toolRecordatorios)
                Toggle("Calendario de Mac (EventKit)", isOn: $m.toolCalendario)
                HStack {
                    Text("Recordatorios: \(AppleAgenda.nombreEstado(AppleAgenda.estadoRecordatorios()))")
                    Spacer()
                    Button("Solicitar permiso") { AppleAgenda.solicitarRecordatorios { _ in m.permisosTick += 1 } }
                        .controlSize(.small)
                }.font(.caption)
                HStack {
                    Text("Calendario: \(AppleAgenda.nombreEstado(AppleAgenda.estadoEventos()))")
                    Spacer()
                    Button("Solicitar permiso") { AppleAgenda.solicitarEventos { _ in m.permisosTick += 1 } }
                        .controlSize(.small)
                }.font(.caption)
                let _ = m.permisosTick
                Divider()
                Toggle("Conexiones API (modos con conexión propia)", isOn: $m.toolConexiones)
                if m.toolConexiones {
                    Text("Un modo con acción «Conexión API» llama la API que TÚ declares (URL, autenticación, endpoints) en Ajustes → Modos. La escritura siempre pide tu visto bueno.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Text("Tiempo para decidir el visto bueno:").font(.caption)
                        TextField("120", value: $m.conexionSegundos, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 55)
                        Text("segundos (se estira solo si la propuesta es larga; el silencio cancela)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("Notas de Apple (crear y verificar)", isOn: $m.toolNotasApple)
                if m.toolNotasApple {
                    field("Carpeta de Notas", text: $m.notasAppleCarpeta,
                          placeholder: "Vacío = carpeta predeterminada")
                    Toggle("Crear la carpeta si todavía no existe",
                           isOn: $m.notasAppleCrearCarpeta)
                    Toggle("Mostrar la nota después de crearla",
                           isOn: $m.notasAppleMostrar)
                    HStack {
                        Text("Automatización de Notas: \(NotasApple.nombreEstadoPermiso(NotasApple.estadoPermiso()))")
                        Spacer()
                        Button("Solicitar permiso") {
                            let estado = NotasApple.solicitarPermiso()
                            m.permisosTick += 1
                            m.aviso = estado == noErr
                                ? "Automatización de Notas permitida."
                                : "Autoriza BtoDicta en Privacidad y seguridad → Automatización → Notas."
                        }.controlSize(.small)
                        Button("Probar sin dejar nota") {
                            NotasApple.probarFlujoReal { r in
                                m.permisosTick += 1; m.aviso = r.mensaje
                            }
                        }.controlSize(.small)
                    }.font(.caption)
                    Text("Crea una nota real mediante la automatización oficial, vuelve a leerla y solo entonces confirma el éxito. Entiende títulos, párrafos, encabezados, listas, casillas y citas. “Nota local” sigue siendo la biblioteca interna de BtoDicta.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Toggle("Pasarela Apple mediante Atajos", isOn: $m.toolAtajos)
                if m.toolAtajos {
                    field("Atajo que recibe el texto", text: $m.atajoApple, placeholder: "Mi atajo de BtoDicta")
                    if !m.atajos.isEmpty {
                        Picker("Atajos encontrados", selection: $m.atajoApple) {
                            Text("Elegir…").tag("")
                            ForEach(m.atajos, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Button("Actualizar lista de Atajos") { m.cargarAtajos() }.controlSize(.small)
                    if !m.atajosDetalle.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Atajos habilitados como herramientas").font(.subheadline).bold()
                            ForEach($m.atajosDetalle) { $atajo in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: $atajo.habilitado)
                                        .labelsHidden().disabled(!atajo.disponible)
                                    Text(atajo.nombre).font(.caption).lineLimit(1)
                                        .foregroundStyle(atajo.disponible ? Color.primary : Color.secondary)
                                    Spacer()
                                    Picker("", selection: $atajo.riesgo) {
                                        ForEach(RiesgoAtajoApple.allCases) { r in Text(r.nombre).tag(r) }
                                    }.labelsHidden().frame(width: 135).disabled(!atajo.disponible)
                                }
                            }
                        }
                        .padding(8).background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Cada Atajo descubierto empieza apagado y con un nivel de riesgo propio. BtoDicta lo ejecuta por la pasarela oficial, con timeout y evidencia; HomeKit y Concentración nunca se activan sin tu autorización.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            instaladoresAtajos
            universal
            musica
            rutinas

            if !m.aviso.isEmpty { Text(m.aviso).font(.caption).foregroundStyle(violeta) }
        }
        .onAppear { m.cargarAtajos(); m.actualizarCodex() }
        .onReceive(NotificationCenter.default.publisher(for: .betoUbicacionClimaCambio)) { _ in
            m.permisosTick += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .betoActivacionVozEstadoCambio)) { _ in
            estadoActivacion = ActivacionVoz.shared.estado
        }
    }

    private var instaladoresAtajos: some View {
        card("Atajos incluidos y reinstalables", "square.and.arrow.down.on.square") {
            Text("BtoDicta trae tres paquetes firmados. Tú decides cuál importar; la app nunca acepta permisos ni pulsa “Añadir atajo” por ti. Las recetas Trabajo, Universidad o Casa usan el Atajo Universal y no necesitan duplicarse.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(AtajoIncluidoID.allCases) { id in
                let info = AtajosIncluidos.info(id, nombreAgente: m.nombre)
                let instalado = m.estaInstalado(id)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: instalado ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(instalado ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.nombre).font(.subheadline).bold()
                        Text(info.detalle).font(.caption2).foregroundStyle(.secondary)
                        Text("Riesgo sugerido: \(info.riesgo.nombre)"
                             + (info.requiereScripts ? " · usa el puente local firmado" : ""))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(instalado ? "Reinstalar…" : "Instalar…") {
                        m.instalarAtajoIncluido(id)
                    }.controlSize(.small)
                }
            }
            Button("Actualizar estado") { m.cargarAtajos() }.controlSize(.small)
            Text("Los Atajos con scripts pueden pedir una autorización adicional de macOS la primera vez que se ejecutan. Ese permiso también queda bajo tu control.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var universal: some View {
        card("Atajo universal BtoDicta", "point.3.connected.trianglepath.dotted") {
            Text("Un solo contrato JSON despacha música, calendario, recordatorios, aplicaciones, HomeKit, Concentración, capturas, estado del Mac y resumen del día. Devuelve ok, mensaje y evidencia; las acciones fuera del nivel de autonomía exigen confirmación.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                BotonNativoAccesible(titulo: "Copiar JSON de ejemplo",
                                     etiqueta: "Copiar JSON de ejemplo") {
                    m.copiarEjemploUniversal()
                }.fixedSize()
                BotonNativoAccesible(titulo: "Validar sin ejecutar",
                                     etiqueta: "Validar el Atajo universal sin ejecutar acciones") {
                    m.probarUniversal()
                }.fixedSize()
                BotonNativoAccesible(titulo: m.estaInstalado(.universal)
                                     ? "Reinstalar…" : "Instalar…",
                                     etiqueta: "Instalar el Atajo universal incluido") {
                    m.instalarAtajoIncluido(.universal)
                }.fixedSize()
            }.controlSize(.small)
            Text("Los Atajos Apple siguen siendo herramientas externas: debes habilitar cada uno arriba. El contrato nunca contiene ni exporta claves.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var musica: some View {
        card("Modo Música y failover", "music.note.list") {
            Toggle("Intentar reproducir una coincidencia de la biblioteca de Apple Music", isOn: $m.reproducir)
            Picker("Al decir “pon música” sin artista", selection: $m.musicaSinConsulta) {
                Text("Poner una canción aleatoria").tag("aleatorio")
                Text("Reanudar lo último").tag("reanudar")
            }
            Toggle("Reproducir el primer resultado del catálogo de Apple Music",
                   isOn: $m.musicaCatalogo)
            Text("Usa el buscador público de Apple y Accesibilidad; verifica título y artista. Si falla, continúa por la cascada.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Si no puede reproducir o la app no está, continúa por la cascada y termina en búsqueda web.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Reproductor interno de BtoDicta", systemImage: "music.note.house.fill")
                        .font(.subheadline).bold()
                    Spacer()
                    Button("Abrir reproductor") { m.abrirReproductorInterno() }
                        .controlSize(.small)
                        .help("Abrir el buscador y reproductor musical dentro de BtoDicta")
                }
                Text("Busca con la API oficial de YouTube y reproduce con el IFrame Player oficial. No raspa páginas ni guarda tu contraseña de Google.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Reproducir automáticamente el primer resultado cuando digo “pon”",
                       isOn: $m.musicaInternaAuto)
                    .help("Apágalo si prefieres revisar los resultados antes de pulsar Play")
                Toggle("Avanzar al resultado siguiente cuando termine una canción",
                       isOn: $m.musicaInternaAvanzar)
                    .help("Continúa automáticamente por la cola visible del reproductor")
                Toggle("Abrir el reproductor en vista compacta",
                       isOn: $m.musicaInternaCompacta)
                    .help("Conserva visible el reproductor oficial de YouTube en su tamaño mínimo; YouTube no permite ocultar el video ni separar solo el audio")
                field("Si digo solo “pon música”", text: $m.musicaInternaConsulta,
                      placeholder: "música para escuchar")

                HStack(spacing: 7) {
                    Circle().fill(YouTubeOAuth.conectada || YouTubeOAuth.tieneAPIKey ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(m.youtubeEstado).font(.caption).foregroundStyle(.secondary)
                    if m.youtubeTrabajando { ProgressView().controlSize(.small) }
                }

                HStack {
                    SecureField(YouTubeOAuth.tieneAPIKey ? "Clave guardada (escribe para reemplazar)" : "YouTube Data API key",
                                text: $youtubeKey)
                        .textFieldStyle(.roundedBorder)
                        .help("Clave propia de YouTube Data API v3; se guarda con permisos 0600")
                    Button("Guardar clave") {
                        if m.guardarYouTubeKey(youtubeKey) { youtubeKey = "" }
                    }.controlSize(.small).disabled(youtubeKey.isEmpty)
                        .help("Guardar la clave de forma local y privada")
                    if YouTubeOAuth.tieneAPIKey {
                        Button("Quitar") { m.quitarYouTubeKey() }.controlSize(.small)
                            .help("Eliminar la clave de YouTube guardada en esta Mac")
                    }
                }

                HStack(spacing: 8) {
                    Button("Importar OAuth de escritorio…") { m.importarOAuthYouTube() }
                        .controlSize(.small)
                        .help("Importar el JSON descargado de Google Cloud para una aplicación de escritorio")
                    if YouTubeOAuth.tieneCliente && !YouTubeOAuth.conectada {
                        Button("Conectar cuenta Google") { m.conectarYouTube() }
                            .controlSize(.small).disabled(m.youtubeTrabajando)
                            .help("Autorizar YouTube en el navegador externo; BtoDicta nunca ve tu contraseña")
                    }
                    if YouTubeOAuth.conectada {
                        Button("Desconectar cuenta") { m.desconectarYouTube() }
                            .controlSize(.small).disabled(m.youtubeTrabajando)
                            .help("Borrar el token revocable guardado en esta Mac")
                    }
                    Spacer()
                    Button("Activar API en Google Cloud ↗") {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!)
                    }.controlSize(.small)
                        .help("Abrir la página oficial de YouTube Data API v3")
                    Button("Crear cliente OAuth ↗") {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    }.controlSize(.small)
                        .help("Crear credenciales OAuth de tipo Aplicación de escritorio para leer tus listas")
                }
                Text("Búsquedas públicas: basta la API key. Mis listas: 1) activa YouTube Data API; 2) crea un cliente OAuth “Aplicación de escritorio”; 3) descarga su JSON e impórtalo; 4) pulsa Conectar cuenta Google. La autorización se abre en tu navegador y BtoDicta nunca recibe tu contraseña.")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    Stepper("Límite preventivo diario: \(m.youtubeBusquedasDiarias)",
                            value: $m.youtubeBusquedasDiarias, in: 1...10_000)
                        .help("Google asigna 100 búsquedas diarias por defecto; aumenta este valor solo si tu proyecto obtuvo más cuota")
                    Spacer()
                    Button("Reiniciar estimación") { m.reiniciarCuotaYouTube() }
                        .controlSize(.small)
                        .help("Usar al cambiar de proyecto; no reinicia la cuota real de Google")
                }
                Text(YouTubeCuotaBusqueda.resumen())
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Al agotarse la cuota o fallar la red, BtoDicta busca sin conexión en resultados previos, favoritos, cola, historial y listas que ya abriste.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()
            Toggle("Probar primero un Atajo de Apple Music", isOn: $m.musicaAtajoPrimero)
            if m.musicaAtajoPrimero {
                field("Atajo de música", text: $m.musicaAtajo, placeholder: "Reproducir con BtoDicta")
                let instalado = m.estaInstalado(.musica)
                HStack(spacing: 8) {
                    Image(systemName: instalado ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(instalado ? .green : .orange)
                    Text(instalado ? "Atajo incluido instalado" : "Falta autorizar el Atajo incluido una vez")
                        .font(.caption)
                    if m.musicaAtajo == AppleAtajos.nombreMusicaIncluido {
                        Button(instalado ? "Reinstalar…" : "Instalar…") {
                            m.instalarAtajoMusica()
                        }.controlSize(.small)
                    }
                }
                if !m.atajos.isEmpty {
                    Picker("Atajo encontrado", selection: $m.musicaAtajo) {
                        Text("Elegir…").tag("")
                        ForEach(m.atajos, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("BtoDicta trae «\(AppleAtajos.nombreMusicaIncluido)» ya construido y lo prueba primero. macOS exige confirmar su importación una vez. Busca una coincidencia en tu biblioteca; BtoDicta verifica título/artista y, si no coincide, continúa por la cascada. Puedes editarlo o sustituirlo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(m.cascadaMusica.enumerated()), id: \.element) { i, id in
                HStack {
                    Text("\(i + 1). \(Musica.nombre(id))").font(.subheadline)
                    Spacer()
                    Button { m.moverMusica(i, -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.plain).disabled(i == 0)
                        .help("Subir este proveedor en el failover de música")
                    Button { m.moverMusica(i, 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).disabled(i == m.cascadaMusica.count - 1)
                        .help("Bajar este proveedor en el failover de música")
                    Button { m.quitarMusica(id) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).help("Quitar este proveedor del failover de música")
                }
            }
            let faltan = Musica.catalogo().filter { !m.cascadaMusica.contains($0.id) }
            if !faltan.isEmpty {
                Menu("Agregar a la cascada") {
                    ForEach(faltan) { p in Button(p.nombre) { m.agregarMusica(p.id) } }
                }.controlSize(.small)
            }
            Divider()
            Text("Proveedor propio").font(.subheadline).bold()
            TextField("Nombre", text: $proveedorNombre).textFieldStyle(.roundedBorder)
            TextField("https://servicio.example/buscar?q={q}", text: $proveedorURL).textFieldStyle(.roundedBorder)
            HStack {
                Button("Agregar") {
                    if m.agregarProveedor(nombre: proveedorNombre, url: proveedorURL) {
                        proveedorNombre = ""; proveedorURL = ""
                    }
                }.controlSize(.small)
            }
            ForEach(Musica.personales()) { p in
                HStack {
                    Text(p.nombre).font(.caption)
                    Spacer()
                    Button("Quitar") { m.borrarProveedor(p.id) }.controlSize(.small)
                }
            }
        }
    }

    private var rutinas: some View {
        card("Recetas y rutinas portables", "list.bullet.rectangle.portrait") {
            Text("BtoDicta incluye Resumen del día, jornadas, reunión, selección, estado del Mac, captura, HomeKit y audio de Finder. {texto}, {resultado} y {fecha} enlazan los pasos. Los fallos opcionales no detienen el resto.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($m.rutinas) { $rutina in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("", isOn: $rutina.activa).labelsHidden()
                        TextField("Nombre", text: $rutina.nombre)
                            .textFieldStyle(.roundedBorder)
                        Text(rutina.categoria).font(.caption2).foregroundStyle(.secondary)
                        let riesgo = RutinasAgenteStore.riesgo(rutina)
                        Text(riesgo == .lectura ? "lectura" : (riesgo == .reversible ? "reversible" :
                            (riesgo == .cambioLocal ? "cambio local" : (riesgo == .externo ? "externo" : "confirmar siempre"))))
                            .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(riesgo >= .externo ? Color.orange.opacity(0.18) : Color.green.opacity(0.14))
                            .clipShape(Capsule())
                        if !rutina.incluida {
                            Button(role: .destructive) {
                                m.rutinas.removeAll { $0.id == rutina.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).help("Eliminar esta rutina personal")
                        }
                    }
                    if !rutina.descripcion.isEmpty {
                        Text(rutina.descripcion).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Frases separadas por coma", text: Binding(
                        get: { rutina.frases.joined(separator: ", ") },
                        set: { valor in rutina.frases = valor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    )).textFieldStyle(.roundedBorder)
                    ForEach($rutina.pasos) { $paso in
                        HStack {
                            Picker("", selection: $paso.tipo) {
                                Text("Música").tag("musica"); Text("Aplicación").tag("app")
                                Text("Primera app disponible").tag("app_primera")
                                Text("URL").tag("url"); Text("Atajo Apple").tag("atajo")
                                Text("Tarea local").tag("tarea"); Text("Nota local").tag("nota")
                                Text("Nota de Apple").tag("nota_apple")
                                Text("Recordatorio").tag("recordatorio"); Text("Calendario").tag("calendario")
                                Text("Archivo").tag("archivo")
                                Text("Captura de pantalla").tag("captura")
                                Text("Grabación de pantalla").tag("grabacion")
                                Divider()
                                Text("Resumen del día").tag("resumen_dia")
                                Text("Preparación de mañana").tag("resumen_manana")
                                Text("Estado del Mac").tag("estado_mac")
                                Text("Captura inteligente").tag("captura_inteligente")
                                Text("Leer selección").tag("seleccion_leer")
                                Text("Resumir selección").tag("seleccion_resumir")
                                Text("Traducir selección").tag("seleccion_traducir")
                                Text("Responder selección").tag("seleccion_responder")
                                Text("Selección a tarea").tag("seleccion_tarea")
                                Text("Selección a Nota de Apple").tag("seleccion_nota_apple")
                                Text("Transcribir audio seleccionado").tag("audio_transcribir")
                                Text("Resumir audio seleccionado").tag("audio_resumir")
                                Text("Traducir audio seleccionado").tag("audio_traducir")
                                Text("Audio a correo").tag("audio_correo")
                                Text("Audio a oficio").tag("audio_oficio")
                                Text("Cerrar aplicaciones (confirmar)").tag("cerrar_apps")
                                Divider()
                                Text("Conexión API (modo)").tag("conexion")
                            }.labelsHidden().frame(width: 190)
                            if paso.tipo == "conexion" {
                                // El valor es el ID del modo-conexión; se elige por nombre.
                                Picker("", selection: $paso.valor) {
                                    Text("Elige un modo-conexión…").tag("")
                                    ForEach(ModosStore.todos().filter { $0.accion == "conexion" && $0.conexion != nil }) { mc in
                                        Text(mc.nombre).tag(mc.id)
                                    }
                                }.labelsHidden().frame(minWidth: 160)
                            } else {
                                TextField("Valor o {texto}", text: $paso.valor)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Toggle("Opcional", isOn: $paso.opcional).font(.caption)
                            Button { rutina.pasos.removeAll { $0.id == paso.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).help("Quitar este paso de la rutina")
                        }
                    }
                    HStack {
                        Button("Agregar paso") { rutina.pasos.append(PasoRutinaAgente()) }.controlSize(.small)
                        Toggle("Mostrar/hablar el resultado", isOn: $rutina.devuelveResultado)
                            .font(.caption).toggleStyle(.switch).controlSize(.mini)
                            .help("La respuesta consolidada de la rutina se muestra y se lee en voz alta (útil con pasos de conexión API o resúmenes)")
                    }
                }
                .padding(10).background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Nueva rutina") { m.nuevaRutina() }
                Button("Guardar rutinas") { m.guardarRutinas() }.buttonStyle(.borderedProminent).tint(violeta)
                Spacer()
                Button("Importar JSON…") { m.importarRutinas() }
                Menu("Exportar JSON…") {
                    Button("Toda la biblioteca") { m.exportarRutinas() }
                    Button("Paquete Trabajo") { m.exportarRutinas(categoria: "Trabajo") }
                    Button("Paquete Universidad") { m.exportarRutinas(categoria: "Universidad") }
                    Button("Paquete Casa") { m.exportarRutinas(categoria: "Casa") }
                    Button("Mis recetas") { m.exportarRutinas(categoria: "Personal") }
                }
            }.controlSize(.small)
            Text("Los paquetes JSON no contienen claves. Al importar se validan tipos, tamaño y URLs; los Atajos siguen necesitando habilitación individual.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func field(_ titulo: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(titulo).font(.subheadline).frame(width: 170, alignment: .leading)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func card<Content: View>(_ titulo: String, _ icono: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(violeta)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
