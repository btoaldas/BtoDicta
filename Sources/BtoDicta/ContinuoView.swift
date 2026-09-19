import SwiftUI

/// Mismo púrpura del logo que usa la ventana de ajustes. Se repite aquí porque
/// allí es `private` y no merece la pena tocar ese archivo solo por un color.
private let acentoBitacora = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Pestaña "Bitácora" (grabación continua)
//
// Todo lo que hace el módulo se decide aquí. Una sola excepción deliberada:
// que la bitácora ceda el micrófono al dictado NO es un ajuste, es invariante
// del código. Se explica en pantalla, no se ofrece como interruptor.

final class ContinuoModel: ObservableObject {

    @Published var activo: Bool { didSet { Config.set("continuo_activo", to: activo); aplicar() } }
    @Published var carpeta: String { didSet { Config.set("continuo_carpeta", to: carpeta) } }

    @Published var audioModo: String { didSet { Config.set("continuo_audio_modo", to: audioModo); aplicar() } }
    @Published var audioAntiEco: Double { didSet { Config.set("continuo_audio_factor_antieco", to: audioAntiEco) } }
    @Published var audioSegmento: Double { didSet { Config.set("continuo_audio_segmento_segundos", to: Int(audioSegmento)) } }
    @Published var audioAdoptar: Bool { didSet { Config.set("continuo_audio_adoptar_dictado", to: audioAdoptar) } }
    @Published var audioUmbral: Double { didSet { Config.set("continuo_audio_umbral_voz", to: audioUmbral) } }
    @Published var sistemaActivo: Bool { didSet { Config.set("continuo_sistema_activo", to: sistemaActivo); aplicar() } }
    @Published var sistemaExcluirPropia: Bool { didSet { Config.set("continuo_sistema_excluir_propia", to: sistemaExcluirPropia); aplicar() } }
    @Published var sistemaSoloSonido: Bool { didSet { Config.set("continuo_sistema_solo_con_sonido", to: sistemaSoloSonido) } }
    @Published var sistemaUmbral: Double { didSet { Config.set("continuo_sistema_umbral", to: sistemaUmbral) } }

    @Published var pantallaActiva: Bool { didSet { Config.set("continuo_pantalla_activa", to: pantallaActiva); aplicar() } }
    @Published var pantallaIntervalo: Double { didSet { Config.set("continuo_pantalla_intervalo_segundos", to: Int(pantallaIntervalo)); aplicar() } }
    @Published var pantallaFormato: String { didSet { Config.set("continuo_pantalla_formato", to: pantallaFormato) } }
    @Published var pantallaCalidad: Double { didSet { Config.set("continuo_pantalla_calidad", to: pantallaCalidad) } }
    @Published var pantallaEscala: Double { didSet { Config.set("continuo_pantalla_escala", to: pantallaEscala) } }
    @Published var pantallaDedup: Bool { didSet { Config.set("continuo_pantalla_deduplicar", to: pantallaDedup) } }
    @Published var pantallaUmbral: Double { didSet { Config.set("continuo_pantalla_umbral_cambio", to: pantallaUmbral) } }
    @Published var pantallaForzar: Double { didSet { Config.set("continuo_pantalla_forzar_minutos", to: Int(pantallaForzar)) } }
    @Published var pantallaPausar: Bool { didSet { Config.set("continuo_pantalla_pausar_bloqueada", to: pantallaPausar) } }
    @Published var pantallaTodas: Bool { didSet { Config.set("continuo_pantalla_todos_monitores", to: pantallaTodas); aplicar() } }
    @Published var appsExcluidas: String { didSet { Config.set("continuo_pantalla_apps_excluidas", to: listaDe(appsExcluidas)) } }
    @Published var titulosExcluidos: String { didSet { Config.set("continuo_pantalla_titulos_excluidos", to: listaDe(titulosExcluidos)) } }

    @Published var soloCorriente: Bool { didSet { Config.set("continuo_solo_con_corriente", to: soloCorriente) } }

    @Published var retencionDias: Double { didSet { Config.set("continuo_retencion_dias", to: Int(retencionDias)) } }
    @Published var retencionAuto: Bool { didSet { Config.set("continuo_retencion_automatica", to: retencionAuto) } }
    @Published var retencionAvisar: Bool { didSet { Config.set("continuo_retencion_avisar_sin_procesar", to: retencionAvisar) } }

    // ---- Tanda diferida ----
    @Published var dispIntervalo: Bool { didSet { guardarDisparadores() } }
    @Published var dispHora: Bool { didSet { guardarDisparadores() } }
    @Published var dispArranque: Bool { didSet { guardarDisparadores() } }
    @Published var dispApagado: Bool { didSet { guardarDisparadores() } }
    @Published var loteIntervalo: Double { didSet { Config.set("continuo_lote_intervalo_minutos", to: Int(loteIntervalo)); ContinuoPlanificador.reconfigurar() } }
    @Published var loteMinutoDia: Double { didSet { Config.set("continuo_lote_minuto_del_dia", to: Int(loteMinutoDia)); ContinuoPlanificador.reconfigurar() } }
    @Published var loteMotor: String { didSet { Config.set("continuo_lote_motor", to: loteMotor) } }
    @Published var resumenIA: String { didSet { Config.set("continuo_resumen_ia", to: resumenIA) } }
    @Published var promptActivo: String { didSet { Config.set("continuo_prompt_activo", to: promptActivo); cargarPrompt() } }
    @Published var promptTexto: String = ""
    @Published var promptNombre: String = ""
    @Published var loteComprimir: Bool { didSet { Config.set("continuo_lote_comprimir", to: loteComprimir) } }
    @Published var loteRecomprimir: Bool { didSet { Config.set("continuo_recomprimir_pendientes", to: loteRecomprimir) } }
    @Published var pantallaPausarEnTanda: Bool { didSet { Config.set("continuo_pantalla_pausar_en_tanda", to: pantallaPausarEnTanda) } }
    @Published var loteCorriente: Bool { didSet { Config.set("continuo_lote_solo_con_corriente", to: loteCorriente) } }
    @Published var ocrActivo: Bool { didSet { Config.set("continuo_ocr_activo", to: ocrActivo) } }
    @Published var ocrPreciso: Bool { didSet { Config.set("continuo_ocr_preciso", to: ocrPreciso) } }
    @Published var resumenActivo: Bool { didSet { Config.set("continuo_resumen_activo", to: resumenActivo) } }
    @Published var resumenPantalla: Bool { didSet { Config.set("continuo_resumen_incluir_pantalla", to: resumenPantalla) } }
    @Published var resumenPrioridadMic: Bool { didSet { Config.set("continuo_resumen_prioridad_microfono", to: resumenPrioridadMic) } }
    @Published var resumenTiempos: Bool { didSet { Config.set("continuo_resumen_tiempos_app", to: resumenTiempos) } }
    @Published var pantallaVisibles: Bool { didSet { Config.set("continuo_pantalla_apps_visibles", to: pantallaVisibles) } }
    @Published var resumenMax: Double { didSet { Config.set("continuo_resumen_max_caracteres", to: Int(resumenMax)) } }
    @Published var resumenTrocear: Bool { didSet { Config.set("continuo_resumen_trocear", to: resumenTrocear) } }
    @Published var resumenMaxPartes: Double { didSet { Config.set("continuo_resumen_max_partes", to: Int(resumenMaxPartes)) } }
    @Published var resumenInstruccion: String { didSet { Config.set("continuo_resumen_instruccion", to: resumenInstruccion) } }
    @Published var diccAudio: Bool { didSet { Config.set("continuo_diccionario_audio", to: diccAudio) } }
    @Published var diccOcr: Bool { didSet { Config.set("continuo_diccionario_ocr", to: diccOcr) } }
    @Published var glosarioPrompt: Bool { didSet { Config.set("continuo_glosario_en_prompt", to: glosarioPrompt) } }
    /// Rutinas: cualquier mutación (toggle, slider, alta, baja) persiste y
    /// reprograma al instante.
    @Published var rutinas: [RutinaResumen] = ContinuoRutinas.todas() {
        didSet {
            ContinuoRutinas.guardar(rutinas)
            ContinuoPlanificador.reconfigurar()
        }
    }
    /// Material de la ejecución manual: hoy / últimas N horas / rango exacto.
    @Published var manualMaterial: String { didSet { Config.set("continuo_manual_material", to: manualMaterial) } }
    @Published var manualHoras: Double { didSet { Config.set("continuo_manual_horas", to: Int(manualHoras)) } }
    @Published var manualDesde: Date = Calendar.current.startOfDay(for: Date())
    @Published var manualHasta: Date = Date()
    @Published var resumenEstado: String = "—"
    @Published var loteEstado: String = "—"
    @Published var recompresionEstado: String = ""
    @Published var loteCorriendo = false

    // ---- Explorador de lo guardado ----
    @Published var explorarTipo: String = "voz"
    @Published var explorarAudio: [ContinuoIndice.ElementoReciente] = []
    @Published var explorarPantalla: [ContinuoIndice.ElementoReciente] = []
    @Published var explorarDocs: [URL] = []
    @Published var explorarTrans: [URL] = []

    /// Exporta un documento a donde el usuario elija.
    func exportar(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { [weak self] r in
            guard r == .OK, let destino = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destino.path) {
                    try FileManager.default.removeItem(at: destino)
                }
                try FileManager.default.copyItem(at: url, to: destino)
                self?.resumenEstado = "Exportado a \(destino.lastPathComponent)"
            } catch {
                self?.resumenEstado = "No pude exportar: \(error.localizedDescription)"
            }
        }
    }

    /// Elimina un documento, con confirmación. Es recuperable por diseño: los
    /// diarios se regeneran en la próxima tanda y un documento de IA se puede
    /// volver a pedir sobre la misma fecha.
    func eliminar(_ url: URL) {
        let alerta = NSAlert()
        alerta.messageText = "¿Eliminar \(url.lastPathComponent)?"
        alerta.informativeText = "Un diario se regenera en la próxima tanda; un documento de IA se puede volver a generar sobre la misma fecha."
        alerta.addButton(withTitle: "Eliminar")
        alerta.addButton(withTitle: "Cancelar")
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: url)
        cargarExplorador()
    }

    /// Regenera el día de un documento con el prompt HOY elegido en el
    /// selector. No pisa el original: el nuevo sale con la hora en el nombre.
    func regenerar(_ url: URL) {
        // El interruptor maestro del resumen con IA manda también aquí: es el
        // consentimiento de que el material pueda salir hacia un modelo. Con él
        // apagado, este botón no envía nada.
        guard Config.continuoResumenActivo() else {
            resumenEstado = "El resumen con IA está desactivado. Actívalo en «Resumen del día con IA» para regenerar."
            return
        }
        // La fecha viaja en el nombre: <prompt>-AAAA-MM-DD[-HHmm].md
        let nombre = url.deletingPathExtension().lastPathComponent
        guard let rango = nombre.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else {
            resumenEstado = "No reconozco la fecha en «\(nombre)»."
            return
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let dia = f.date(from: String(nombre[rango])) else {
            resumenEstado = "Fecha inválida en «\(nombre)»."
            return
        }
        let prompt = ContinuoPrompts.activo()
        resumenEstado = "Regenerando el \(String(nombre[rango])) con «\(prompt.nombre)»…"
        ContinuoResumen.generar(dia: dia, promptId: prompt.id) { [weak self] r in
            switch r {
            case .success(let nuevo): self?.resumenEstado = "Escrito: \(nuevo.lastPathComponent)"
            case .failure(let e): self?.resumenEstado = "No pude: \(e.localizedDescription)"
            }
            self?.cargarExplorador()
        }
    }

    func cargarExplorador() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            ContinuoIndice.shared.abrir()
            let a = ContinuoIndice.shared.recientes(material: .audio)
            let p = ContinuoIndice.shared.recientes(material: .pantalla)
            // Un solo recorrido del árbol para las dos listas: antes eran dos
            // pasadas completas por refresco.
            let (d, tr) = ContinuoBitacora.documentosYTranscripciones()
            DispatchQueue.main.async {
                self?.explorarAudio = a
                self?.explorarPantalla = p
                self?.explorarDocs = d
                self?.explorarTrans = tr
            }
        }
    }

    @Published var resumen: String = "—"
    @Published var aviso: String?

    init() {
        activo = Config.continuoActivo()
        let raiz = Config.continuoCarpeta().path
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        carpeta = raiz.hasPrefix(casa) ? "~" + raiz.dropFirst(casa.count) : raiz
        audioModo = Config.continuoAudioModo()
        audioAntiEco = Config.continuoAudioFactorAntiEco()
        audioSegmento = Double(Config.continuoAudioSegmentoSegundos())
        audioAdoptar = Config.continuoAudioAdoptarDictado()
        audioUmbral = Config.continuoAudioUmbralVoz()
        sistemaActivo = Config.continuoSistemaActivo()
        sistemaExcluirPropia = Config.continuoSistemaExcluirPropia()
        sistemaSoloSonido = Config.continuoSistemaSoloConSonido()
        sistemaUmbral = Config.continuoSistemaUmbral()
        pantallaActiva = Config.continuoPantallaActiva()
        pantallaIntervalo = Double(Config.continuoPantallaIntervaloSegundos())
        pantallaFormato = Config.continuoPantallaFormato()
        pantallaCalidad = Config.continuoPantallaCalidad()
        pantallaEscala = Config.continuoPantallaEscala()
        pantallaDedup = Config.continuoPantallaDeduplicar()
        pantallaUmbral = Config.continuoPantallaUmbralCambio()
        pantallaForzar = Double(Config.continuoPantallaForzarMinutos())
        pantallaPausar = Config.continuoPantallaPausarBloqueada()
        pantallaTodas = Config.continuoPantallaTodosMonitores()
        appsExcluidas = Config.continuoPantallaAppsExcluidas().joined(separator: ", ")
        titulosExcluidos = Config.continuoPantallaTitulosExcluidos().joined(separator: ", ")
        soloCorriente = Config.continuoSoloConCorriente()
        retencionDias = Double(Config.continuoRetencionDias())
        retencionAuto = Config.continuoRetencionAutomatica()
        retencionAvisar = Config.continuoRetencionAvisarSinProcesar()
        let disp = Config.continuoLoteDisparadores()
        dispIntervalo = disp.contains("intervalo")
        dispHora = disp.contains("hora")
        dispArranque = disp.contains("arranque")
        dispApagado = disp.contains("apagado")
        loteIntervalo = Double(Config.continuoLoteIntervaloMinutos())
        loteMinutoDia = Double(Config.continuoLoteMinutoDelDia())
        loteMotor = Config.continuoLoteMotor()
        resumenIA = Config.continuoResumenIA()
        promptActivo = Config.continuoPromptActivo()
        loteComprimir = Config.continuoLoteComprimir()
        loteRecomprimir = Config.continuoRecomprimirPendientes()
        pantallaPausarEnTanda = Config.continuoPantallaPausarEnTanda()
        loteCorriente = Config.continuoLoteSoloConCorriente()
        ocrActivo = Config.continuoOcrActivo()
        ocrPreciso = Config.continuoOcrPreciso()
        resumenActivo = Config.continuoResumenActivo()
        resumenPantalla = Config.continuoResumenIncluirPantalla()
        resumenPrioridadMic = Config.continuoResumenPrioridadMicrofono()
        resumenTiempos = Config.continuoResumenTiemposApp()
        manualMaterial = (Config.json0("continuo_manual_material") as? String) ?? "dia"
        manualHoras = Double((Config.json0("continuo_manual_horas") as? Int) ?? 1)
        pantallaVisibles = Config.continuoPantallaAppsVisibles()
        diccAudio = Config.continuoDiccionarioAudio()
        diccOcr = Config.continuoDiccionarioOcr()
        glosarioPrompt = Config.continuoGlosarioEnPrompt()
        resumenMax = Double(Config.continuoResumenMaxCaracteres())
        resumenTrocear = Config.continuoResumenTrocear()
        resumenMaxPartes = Double(Config.continuoResumenMaxPartes())
        resumenInstruccion = Config.continuoResumenInstruccion()
        let p0 = ContinuoPrompts.activo()
        promptTexto = p0.texto
        promptNombre = p0.nombre
        refrescar()
        loteEstado = ContinuoPlanificador.descripcion()
    }

    private func guardarDisparadores() {
        var d: [String] = []
        if dispIntervalo { d.append("intervalo") }
        if dispHora { d.append("hora") }
        if dispArranque { d.append("arranque") }
        if dispApagado { d.append("apagado") }
        Config.set("continuo_lote_disparadores", to: d)
        ContinuoPlanificador.reconfigurar()
        loteEstado = ContinuoPlanificador.descripcion()
    }

    /// Lanza una tanda a mano, del canal que se pida. Salta la condición de
    /// energía: lo pidió alguien que está mirando la pantalla.
    func transcribirAhora(canal: String = "todo") {
        guard !loteCorriendo else { return }
        loteCorriendo = true
        loteEstado = canal == "todo" ? "Procesando todo…" : "Procesando \(canal)…"
        ContinuoLote.ejecutar(manual: true, canal: canal) { [weak self] resultado in
            self?.loteCorriendo = false
            self?.loteEstado = resultado
            self?.refrescar()
            self?.cargarExplorador()
        }
    }

    /// Pasada manual de recompresión del crudo pendiente.
    func recomprimirAhora() {
        guard !loteCorriendo else { return }
        loteCorriendo = true
        recompresionEstado = "recomprimiendo…"
        ContinuoLote.recomprimirPendientes(manual: true) { [weak self] resultado in
            self?.loteCorriendo = false
            self?.recompresionEstado = resultado
            self?.refrescar()
        }
    }

    /// Motores de transcripción que el usuario tiene activos, más la cadena.
    var motoresSTT: [(String, String)] {
        [("cadena", "Cadena configurada (con failover)")]
            + Providers.cadena().map { ($0.id, $0.nombre) }
    }

    /// Cerebros de chat conectados: nube con clave, cuenta de sesión o local.
    var cerebros: [(String, String)] {
        [("seleccionada", "El del resto de la app")]
            + ChatIA.conectadas.map { ($0.id, $0.nombre) }
    }

    var prompts: [PromptContinuo] { ContinuoPrompts.todos() }

    func cargarPrompt() {
        let p = ContinuoPrompts.activo()
        promptTexto = p.texto
        promptNombre = p.nombre
    }

    func guardarPrompt() {
        guard var p = ContinuoPrompts.porId(promptActivo) else { return }
        p.texto = promptTexto
        p.nombre = promptNombre
        ContinuoPrompts.guardar(p)
        resumenEstado = "Prompt «\(p.nombre)» guardado."
    }

    func restaurarPrompt() {
        guard let base = ContinuoPrompts.restaurar(id: promptActivo) else {
            resumenEstado = "Ese prompt es tuyo: no tiene original al que volver."
            return
        }
        promptTexto = base.texto
        promptNombre = base.nombre
        resumenEstado = "Prompt «\(base.nombre)» restaurado al original."
    }

    /// Ejecuta el prompt activo sobre el material elegido. Por defecto, el día
    /// hasta ahora; o las últimas N horas; o un rango exacto con fecha.
    func resumirAhora() {
        resumenEstado = "Redactando…"
        var desde: Date? = nil
        var hasta: Date? = nil
        switch manualMaterial {
        case "horas":
            desde = Date().addingTimeInterval(-manualHoras * 3600)
        case "rango":
            desde = manualDesde
            hasta = manualHasta
        default:
            break   // día natural hasta ahora
        }
        ContinuoResumen.generar(promptId: Config.continuoPromptActivo(),
                                desde: desde, hasta: hasta) { [weak self] r in
            switch r {
            case .success(let url): self?.resumenEstado = "Escrito: \(url.lastPathComponent)"
            case .failure(let e): self?.resumenEstado = "No pude: \(e.localizedDescription)"
            }
            self?.refrescar()
        }
    }

    private func listaDe(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func aplicar() {
        ContinuoBitacora.reconfigurar()
    }

    func refrescar() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            ContinuoIndice.shared.abrir()
            let r = ContinuoIndice.shared.resumen()
            let texto = "\(r.audio) fragmentos de audio · \(r.pantalla) capturas · "
                + ContinuoBitacora.tamanoLegible(r.bytes)
                + (r.pendientes > 0 ? " · \(r.pendientes) sin procesar" : " · todo procesado")
            DispatchQueue.main.async { self?.resumen = texto }
        }
    }

    /// Consulta la purga y avisa si se llevaría material sin procesar.
    func revisarPurga() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let balance = ContinuoBitacora.revisarPurga() else {
                DispatchQueue.main.async { self?.aviso = "Retención en «para siempre»: no hay nada que purgar." }
                return
            }
            let t = ContinuoBitacora.tamanoLegible(balance.bytes)
            let msg: String
            if balance.filas == 0 {
                msg = "Nada que purgar todavía."
            } else if balance.hayMaterialSinProcesar {
                msg = "⚠️ Se borrarían \(balance.filas) elementos (\(t)), y \(balance.sinProcesar) de ellos NO tienen transcripción ni texto reconocido. Esa información se perdería."
            } else {
                msg = "Se borrarían \(balance.filas) elementos (\(t)). Todos están ya procesados."
            }
            DispatchQueue.main.async { self?.aviso = msg }
        }
    }

    func purgar(forzar: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let r = ContinuoBitacora.purgar(forzar: forzar)
            let msg = r.bloqueada
                ? "Purga detenida: hay material sin procesar. Usa «Purgar de todos modos» si aceptas perderlo."
                : "Purgados \(r.borradas) elementos."
            DispatchQueue.main.async { self?.aviso = msg; self?.refrescar() }
        }
    }
}

struct ContinuoView: View {
    @StateObject private var m = ContinuoModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Bitácora continua")
                .font(.title2).bold().foregroundStyle(acentoBitacora)
            Text("Graba audio y toma capturas en segundo plano para reconstruir el día. La captura y el índice son locales; revisa el motor de transcripción y el cerebro elegidos, porque ahí decides si algo sale del equipo.")
                .font(.callout).foregroundStyle(.secondary)

            Toggle("Activar la bitácora", isOn: $m.activo)
                .help("Apagada de fábrica. Nada se graba hasta que la enciendas.")

            Text(m.resumen).font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Abrir carpeta") { ContinuoBitacora.abrirCarpeta() }
                Button("Actualizar") { m.refrescar() }
                Text(m.carpeta).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Divider()

            SeccionPlegable("Explorar lo guardado", icono: "folder", abierto: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Button("Voz de hoy") { ContinuoBitacora.abrirCarpetaHoy("audio") }
                        Button("Sistema de hoy") { ContinuoBitacora.abrirCarpetaHoy("sistema") }
                        Button("Capturas de hoy") { ContinuoBitacora.abrirCarpetaHoy("pantalla") }
                        Button("Transcripciones") { ContinuoBitacora.abrirCarpetaHoy("transcripciones") }
                        Button("Documentos") { ContinuoBitacora.abrirCarpetaHoy("documentos") }
                    }
                    Text("Cada botón abre esa carpeta en el Finder (se crea si aún no existe).")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker("", selection: $m.explorarTipo) {
                        Text("Voz").tag("voz")
                        Text("Capturas").tag("capturas")
                        Text("Transcripciones").tag("trans")
                        Text("Documentos").tag("docs")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 420)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if m.explorarTipo == "voz" {
                                ForEach(m.explorarAudio) { e in
                                    filaExplorador(
                                        titulo: "\(Self.horaCorta(e.instante)) · \(e.fuente) · \(Int(e.duracion)) s",
                                        detalle: e.texto.isEmpty ? "(sin transcribir todavía)" : e.texto,
                                        url: e.ruta)
                                }
                            } else if m.explorarTipo == "capturas" {
                                ForEach(m.explorarPantalla) { e in
                                    filaExplorador(
                                        titulo: "\(Self.horaCorta(e.instante)) · \(e.fuente)",
                                        detalle: e.texto.isEmpty ? "(sin leer todavía)" : e.texto,
                                        url: e.ruta)
                                }
                            } else if m.explorarTipo == "trans" {
                                ForEach(m.explorarTrans, id: \.self) { url in
                                    filaExplorador(titulo: url.lastPathComponent,
                                                   detalle: url.deletingLastPathComponent().lastPathComponent,
                                                   url: url)
                                }
                            } else {
                                ForEach(m.explorarDocs, id: \.self) { url in
                                    filaDocumento(url)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 260)

                    Button("Actualizar la lista") { m.cargarExplorador() }
                }
            }

            SeccionPlegable("Audio", icono: "waveform", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Qué se graba", selection: $m.audioModo) {
                        Text("Siempre").tag("siempre")
                        Text("Solo cuando hay voz").tag("voz")
                        Text("Solo al dictar").tag("manual")
                    }.pickerStyle(.radioGroup)

                    HStack {
                        Text("Puerta anti-eco")
                        Slider(value: $m.audioAntiEco, in: 1...10, step: 0.5).frame(width: 160)
                        Text(m.audioAntiEco <= 1 ? "apagada" : String(format: "×%.1f", m.audioAntiEco)).monospacedDigit().font(.caption)
                    }
                    Text("Mientras suena algo por los parlantes, el micrófono exige ese factor más de nivel para considerar que hablas tú y no el altavoz. Con auriculares no hace falta.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Cerrar un trozo cada")
                        Slider(value: $m.audioSegmento, in: 30...900, step: 30).frame(width: 200)
                        Text("\(Int(m.audioSegmento)) s").monospacedDigit()
                    }

                    if m.audioModo == "voz" {
                        HStack {
                            Text("Sensibilidad")
                            Slider(value: $m.audioUmbral, in: 0.001...0.05).frame(width: 180)
                            Text(String(format: "%.4f", m.audioUmbral)).monospacedDigit().font(.caption)
                        }
                        Text("Más bajo capta voces lejanas; más alto evita que se transcriba ruido como si fuera habla.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Incorporar también el audio de los dictados", isOn: $m.audioAdoptar)
                        .help("Mientras dictas, la bitácora cede el micrófono. Con esto, el audio que graba el dictado se suma a la línea de tiempo y no queda hueco.")

                    Label("Al dictar con la tecla de siempre, la bitácora suelta el micrófono y vuelve sola al terminar. El dictado manda: eso no se puede desactivar.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Audio del sistema", icono: "speaker.wave.2", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lo que SUENA en el equipo: la otra parte de una videollamada, un vídeo, una reunión. Es la mitad que el micrófono no capta bien. Se guarda en pista aparte de la tuya.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Grabar el audio del sistema", isOn: $m.sistemaActivo)
                        .help("Usa el permiso de grabación de pantalla, que es la única vía de macOS para tomar el sonido de salida sin instalar un controlador de audio virtual.")
                    Toggle("Excluir el audio de la propia aplicación", isOn: $m.sistemaExcluirPropia)
                        .help("Sin esto, la bitácora grabaría su propia voz sintetizada y se escucharía a sí misma.")
                    Toggle("Guardar solo cuando suene algo", isOn: $m.sistemaSoloSonido)
                    if m.sistemaSoloSonido {
                        HStack {
                            Text("A partir de")
                            Slider(value: $m.sistemaUmbral, in: 0.0001...0.05).frame(width: 170)
                            Text(String(format: "%.4f", m.sistemaUmbral)).monospacedDigit().font(.caption)
                        }
                    }

                    Label("Grabar la voz de otras personas en una llamada puede exigir su consentimiento. Es tu responsabilidad avisar.",
                          systemImage: "exclamationmark.shield")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SeccionPlegable("Pantalla", icono: "camera.viewfinder", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Tomar capturas", isOn: $m.pantallaActiva)

                    HStack {
                        Text("Cada")
                        Slider(value: $m.pantallaIntervalo, in: 5...3600, step: 5).frame(width: 200)
                        Text(intervaloLegible(Int(m.pantallaIntervalo))).monospacedDigit()
                    }

                    Picker("Formato", selection: $m.pantallaFormato) {
                        Text("JPEG").tag("jpeg")
                        Text("HEIC").tag("heic")
                        Text("PNG (sin pérdida)").tag("png")
                    }.pickerStyle(.segmented).frame(width: 320)

                    HStack {
                        Text("Calidad")
                        Slider(value: $m.pantallaCalidad, in: 0.1...1.0).frame(width: 160)
                        Text(String(format: "%.0f %%", m.pantallaCalidad * 100)).monospacedDigit()
                    }
                    HStack {
                        Text("Escala")
                        Slider(value: $m.pantallaEscala, in: 0.25...1.0).frame(width: 160)
                        Text(String(format: "%.0f %%", m.pantallaEscala * 100)).monospacedDigit()
                    }

                    Toggle("No guardar si la pantalla no cambió", isOn: $m.pantallaDedup)
                    if m.pantallaDedup {
                        HStack {
                            Text("Cuánto debe cambiar")
                            Slider(value: $m.pantallaUmbral, in: 0.0...0.2).frame(width: 160)
                            Text(String(format: "%.1f %%", m.pantallaUmbral * 100)).monospacedDigit()
                        }
                    }
                    HStack {
                        Text("Forzar una captura cada")
                        Slider(value: $m.pantallaForzar, in: 0...120, step: 5).frame(width: 160)
                        Text(m.pantallaForzar == 0 ? "nunca" : "\(Int(m.pantallaForzar)) min").monospacedDigit()
                    }

                    Toggle("Capturar todas las pantallas conectadas", isOn: $m.pantallaTodas)
                        .help("Con dos o tres monitores, cada uno se captura y se deduplica por separado. Apagado, solo el principal.")
                    Toggle("Pausar con la pantalla bloqueada o dormida", isOn: $m.pantallaPausar)
                    Toggle("Pausar la pantalla mientras corre una tanda", isOn: $m.pantallaPausarEnTanda)
                        .help("Con el equipo transcribiendo en local una captura puede tardar más que el intervalo. Apagado, se sigue capturando y se espera a que termine.")
                    Toggle("Anotar qué aplicaciones estaban a la vista", isOn: $m.pantallaVisibles)
                        .help("Con cada captura se guarda la app activa y las demás visibles: «activa Claude; también a la vista Edge, Finder».")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apps excluidas (identificadores separados por comas)").font(.caption)
                        TextField("com.ejemplo.banca, com.ejemplo.claves", text: $m.appsExcluidas)
                            .textFieldStyle(.roundedBorder)
                        Text("De fábrica vienen los gestores de contraseñas y el llavero del sistema: sus ventanas no aparecen en la captura. Vacía el campo si quieres capturarlas.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("Títulos de ventana excluidos (palabras separadas por comas)").font(.caption)
                        TextField("banco, extracto, tarjeta", text: $m.titulosExcluidos)
                            .textFieldStyle(.roundedBorder)
                        Text("Para lo que no se puede excluir por aplicación: una pestaña del banco en el navegador. Si el título contiene una de estas palabras, no se guarda la captura. Vacío de fábrica, porque una palabra demasiado común te dejaría sin bitácora media jornada.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            SeccionPlegable("Procesamiento diferido", icono: "text.badge.checkmark", abierto: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Transcribir mientras grabas mantendría un modelo de voz ocupando el procesador todo el día. Se hace en una sola pasada, cuando tú digas.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Cuándo").font(.caption).foregroundStyle(.secondary)
                    Toggle("Cada cierto tiempo", isOn: $m.dispIntervalo)
                    if m.dispIntervalo {
                        HStack {
                            Slider(value: $m.loteIntervalo, in: 15...1440, step: 15).frame(width: 200)
                            Text(m.loteIntervalo < 60
                                 ? "\(Int(m.loteIntervalo)) min"
                                 : String(format: "%.1f h", m.loteIntervalo / 60)).monospacedDigit()
                        }
                    }
                    Toggle("A una hora fija", isOn: $m.dispHora)
                    if m.dispHora {
                        HStack {
                            Slider(value: $m.loteMinutoDia, in: 0...1439, step: 15).frame(width: 200)
                            Text(String(format: "%02d:%02d", Int(m.loteMinutoDia) / 60, Int(m.loteMinutoDia) % 60))
                                .monospacedDigit()
                        }
                    }
                    Toggle("Al abrir la aplicación", isOn: $m.dispArranque)
                    Toggle("Al apagar el equipo", isOn: $m.dispApagado)
                        .help("macOS da un margen corto al apagar. Se transcribe lo que alcance; el resto queda pendiente para la próxima.")

                    Divider()

                    Picker("Motor de transcripción", selection: $m.loteMotor) {
                        ForEach(m.motoresSTT, id: \.0) { par in
                            Text(par.1).tag(par.0)
                        }
                    }
                    Text("Se listan los proveedores que tengas activos en Modelos: nube con clave, cuenta de sesión o local. La cadena respeta tu orden y salta al siguiente si uno cae.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Comprimir el audio al transcribirlo", isOn: $m.loteComprimir)
                        .help("El crudo se guarda sin comprimir para sobrevivir a un corte. Ya transcrito, se comprime y se libera espacio.")
                    Toggle("Recomprimir en segundo plano el crudo que quedó sin comprimir", isOn: $m.loteRecomprimir)
                        .help("Pasadas cada 15 min sobre el audio ya transcrito que sigue en PCM; se detiene si empieza un dictado. Cada m4a se valida antes de borrar su crudo.")
                    HStack {
                        Button("Recomprimir ahora") { m.recomprimirAhora() }
                            .disabled(m.loteCorriendo)
                        Text(m.recompresionEstado).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Solo con el equipo enchufado", isOn: $m.loteCorriente)

                    Text("A petición — procesa solo lo que elijas, ahora mismo").font(.caption)
                    HStack {
                        Button("Todo") { m.transcribirAhora() }
                        Button("Solo voz") { m.transcribirAhora(canal: "voz") }
                        Button("Solo sistema") { m.transcribirAhora(canal: "sistema") }
                        Button("Solo pantalla (OCR)") { m.transcribirAhora(canal: "pantalla") }
                    }.disabled(m.loteCorriendo)
                    Text(m.loteEstado).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SeccionPlegable("Texto de las capturas", icono: "text.viewfinder") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Leer el texto de las capturas", isOn: $m.ocrActivo)
                        .help("Reconocimiento en el dispositivo, con Vision. No sale nada del equipo y no consume cuota.")
                    Toggle("Modo preciso", isOn: $m.ocrPreciso)
                        .help("Preciso reconoce mejor y tarda más. Rápido basta para buscar por palabras sueltas.")
                    Text("Se ejecuta en la misma pasada que la transcripción.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Diccionario propio", icono: "character.book.closed") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("BtoDicta ya sabe cómo hablas: reemplazos, siglas, corrección por sonido y glosario, afinados a fuerza de dictar. La bitácora usa ese mismo conocimiento — y ahí hace más falta, porque nadie está revisando el texto en el momento.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Corregir las transcripciones con el diccionario", isOn: $m.diccAudio)
                        .help("Aplica tus reglas de reemplazo, incluidas las de corrección por sonido.")
                    Toggle("Corregir también el texto leído de la pantalla", isOn: $m.diccOcr)
                        .help("El reconocimiento visual se equivoca con las mismas palabras propias que el de voz.")
                    Toggle("Pasar el glosario a la IA", isOn: $m.glosarioPrompt)
                        .help("Le da el contexto de tus términos para que deduzca los que el audio deformó demasiado como para que el reemplazo literal los alcance.")

                    Text("Reglas activas: \(Config.replacements().count) · términos de glosario: \(Config.keyterms().count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Resumen del día con IA", icono: "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Esto es lo ÚNICO del módulo que puede salir del equipo: si el cerebro elegido es de nube, se le manda el texto del día. Apagado de fábrica a propósito.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Redactar un resumen del día", isOn: $m.resumenActivo)
                    Toggle("Incluir también el texto de las capturas", isOn: $m.resumenPantalla)
                    Toggle("Tu voz manda sobre el resto", isOn: $m.resumenPrioridadMic)
                        .help("Si el día no cabe en el tope, se recortan primero las capturas y el audio del sistema. Lo que dijiste tú entra entero: un videotutorial es contexto, tu voz es el contenido.")
                    Toggle("Cerrar con el tiempo por aplicación", isOn: $m.resumenTiempos)
                        .help("Minutos aproximados en primer plano por app, deducidos de las capturas.")

                    HStack {
                        Text("Capacidad por envío")
                        Slider(value: $m.resumenMax, in: 2000...400000, step: 2000).frame(width: 180)
                        Text("\(Int(m.resumenMax)) caracteres").monospacedDigit().font(.caption)
                    }
                    Text("Ajústalo a la ventana de contexto de la IA elegida. No limita cuánto se procesa: es cuánto cabe en CADA envío.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Si el día no cabe, enviarlo en partes y unirlas (sin perder nada)", isOn: $m.resumenTrocear)
                        .help("El día se trocea en envíos del tamaño de arriba, cada parte se procesa con la misma instrucción, y una pasada final las une en un solo documento. Diez envíos si hacen falta.")
                    if m.resumenTrocear {
                        HStack {
                            Text("Máximo de envíos")
                            Slider(value: $m.resumenMaxPartes, in: 2...50, step: 1).frame(width: 160)
                            Text("\(Int(m.resumenMaxPartes))").monospacedDigit().font(.caption)
                        }
                        Text("Si el material pidiera más, las partes se agrandan para caber: se aprieta, no se pierde.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("⚠️ Apagado: lo que no quepa se recorta (primero capturas, luego audio del sistema, tu voz al final).")
                            .font(.caption).foregroundStyle(.orange)
                    }

                    Picker("Cerebro", selection: $m.resumenIA) {
                        ForEach(m.cerebros, id: \.0) { par in
                            Text(par.1).tag(par.0)
                        }
                    }
                    Text("Cualquiera de las que tengas conectadas. Si eliges una local (Ollama, LM Studio), nada sale del equipo.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Picker("Qué hacer con el día", selection: $m.promptActivo) {
                        ForEach(m.prompts) { p in
                            Text(p.nombre).tag(p.id)
                        }
                    }
                    if let d = m.prompts.first(where: { $0.id == m.promptActivo })?.descripcion {
                        Text(d).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Instrucción").font(.caption)
                            Spacer()
                            if m.prompts.first(where: { $0.id == m.promptActivo })?.modificado == true {
                                Text("modificado").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        TextEditor(text: $m.promptTexto)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 130)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                        HStack {
                            Button("Guardar prompt") { m.guardarPrompt() }
                            Button("Restaurar el original") { m.restaurarPrompt() }
                                .help("Vuelve al texto que trae la aplicación. Lo tuyo se descarta.")
                        }
                    }

                    Divider()

                    Text("Rutinas programadas").font(.caption).bold()
                    Text("Órdenes permanentes, cada una con su horario, su prompt y su material. Conviven: mediodía y noche, cada 3 horas… Ningún documento pisa a otro.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach($m.rutinas) { $r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle("", isOn: $r.activa).labelsHidden()
                                Text(r.descripcion).font(.caption).bold()
                                Spacer()
                                Button {
                                    m.rutinas.removeAll { $0.id == r.id }
                                } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                            }
                            if r.activa {
                                Picker("Prompt", selection: $r.promptId) {
                                    ForEach(m.prompts) { p in Text(p.nombre).tag(p.id) }
                                }
                                Picker("Cuándo", selection: $r.cuando) {
                                    Text("A una hora fija").tag("hora")
                                    Text("Cada cierto tiempo").tag("intervalo")
                                }.pickerStyle(.segmented).frame(width: 300)
                                if r.cuando == "hora" {
                                    HStack {
                                        Slider(value: Binding(get: { Double(r.minutoDelDia) },
                                                              set: { r.minutoDelDia = Int($0) }),
                                               in: 0...1439, step: 15).frame(width: 180)
                                        Text(String(format: "%02d:%02d", r.minutoDelDia / 60, r.minutoDelDia % 60))
                                            .monospacedDigit().font(.caption)
                                    }
                                } else {
                                    HStack {
                                        Slider(value: Binding(get: { Double(r.cadaMinutos) },
                                                              set: { r.cadaMinutos = Int($0) }),
                                               in: 30...720, step: 30).frame(width: 180)
                                        Text(r.cadaMinutos % 60 == 0 ? "cada \(r.cadaMinutos / 60) h" : "cada \(r.cadaMinutos) min")
                                            .monospacedDigit().font(.caption)
                                    }
                                }
                                Picker("Material", selection: $r.rango) {
                                    Text("Todo el día").tag("dia")
                                    Text("Últimas horas").tag("horas")
                                }.pickerStyle(.segmented).frame(width: 300)
                                if r.rango == "horas" {
                                    HStack {
                                        Slider(value: Binding(get: { Double(r.rangoHoras) },
                                                              set: { r.rangoHoras = Int($0) }),
                                               in: 1...24, step: 1).frame(width: 180)
                                        Text("\(r.rangoHoras) h").monospacedDigit().font(.caption)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.06)))
                    }
                    Button {
                        m.rutinas.append(RutinaResumen.nueva())
                    } label: { Label("Añadir rutina", systemImage: "plus") }

                    Text("Material de la ejecución manual").font(.caption)
                    Picker("", selection: $m.manualMaterial) {
                        Text("Hoy hasta ahora").tag("dia")
                        Text("Últimas horas").tag("horas")
                        Text("Rango exacto").tag("rango")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 340)
                    if m.manualMaterial == "horas" {
                        HStack {
                            Slider(value: $m.manualHoras, in: 1...24, step: 1).frame(width: 180)
                            Text("última\(Int(m.manualHoras) == 1 ? "" : "s") \(Int(m.manualHoras)) h").monospacedDigit().font(.caption)
                        }
                    } else if m.manualMaterial == "rango" {
                        HStack {
                            DatePicker("De", selection: $m.manualDesde).frame(width: 220)
                            DatePicker("a", selection: $m.manualHasta).frame(width: 220)
                        }.font(.caption)
                    }

                    HStack {
                        Button("Ejecutar") { m.resumirAhora() }
                        Text(m.resumenEstado).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("El resultado se guarda como <prompt>-AAAA-MM-DD.md dentro de la carpeta del día, así que puedes tener varios del mismo día sin pisarse.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SeccionPlegable("Energía", icono: "bolt") {
                Toggle("Trabajar solo con el equipo enchufado", isOn: $m.soloCorriente)
                    .help("Con batería, transcribir y capturar consume bastante. Con esto la bitácora espera a la corriente.")
            }

            SeccionPlegable("Retención y borrado", icono: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Conservar")
                        Slider(value: $m.retencionDias, in: 0...365, step: 30).frame(width: 200)
                        Text(m.retencionDias == 0 ? "para siempre" : "\(Int(m.retencionDias)) días").monospacedDigit()
                    }
                    Toggle("Purgar automáticamente al cumplirse el plazo", isOn: $m.retencionAuto)
                    Toggle("Avisar si va a borrar material sin transcribir ni reconocer", isOn: $m.retencionAvisar)
                        .help("Recomendado. Borrar audio sin transcribir es perder información que nunca se llegó a extraer.")

                    HStack {
                        Button("Ver qué se borraría") { m.revisarPurga() }
                        Button("Purgar") { m.purgar(forzar: false) }
                        Button("Purgar de todos modos") { m.purgar(forzar: true) }
                            .help("Borra también lo que todavía no se ha procesado. No hay vuelta atrás.")
                    }
                    if let aviso = m.aviso {
                        Text(aviso).font(.caption)
                            .foregroundStyle(aviso.hasPrefix("⚠️") ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Label("Grabar conversaciones de terceros puede requerir su consentimiento. Revisa qué te obliga la normativa de tu país antes de usarla en reuniones.",
                  systemImage: "exclamationmark.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { m.refrescar(); m.cargarExplorador() }
    }

    /// Una fila del explorador: hora + resumen + revelar/abrir en el Finder.
    private func filaExplorador(titulo: String, detalle: String, url: URL) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.caption).bold()
                if !detalle.isEmpty {
                    Text(detalle).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button { ContinuoBitacora.abrir(url) } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain).help("Abrir con la app predeterminada")
            Button { ContinuoBitacora.revelar(url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Mostrar en el Finder")
        }
        .padding(.vertical, 2)
    }

    /// Fila de un documento generado: abrir (= editar en tu editor), revelar,
    /// exportar, regenerar con el prompt hoy elegido, y eliminar.
    private func filaDocumento(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Text(url.lastPathComponent).font(.caption).bold()
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { ContinuoBitacora.abrir(url) } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).help("Abrir para leer o modificar")
            Button { ContinuoBitacora.revelar(url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Mostrar en el Finder")
            Button { m.exportar(url) } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.plain).help("Exportar una copia a donde elijas")
            Button { m.regenerar(url) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).help("Regenerar ese día con el prompt elegido arriba (no pisa este archivo)")
            Button { m.eliminar(url) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).help("Eliminar (con confirmación)")
        }
        .padding(.vertical, 2)
    }

    private static func horaCorta(_ f: Date) -> String {
        let d = DateFormatter(); d.dateFormat = "d MMM HH:mm"
        return d.string(from: f)
    }

    private func intervaloLegible(_ s: Int) -> String {
        s < 60 ? "\(s) s" : (s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s")
    }
}
