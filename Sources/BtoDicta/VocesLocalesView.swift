import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Editor de la biblioteca de voces locales (Fase 7)
//
// El usuario agrega/detecta/elige sus voces clonadas (XTTS local). Nada viene de
// fábrica: cada quien sube las suyas. Se elige UNA como activa para el Modo Agente.

// Control del MOTOR de voz interno (instalar/estado/quitar). El botón ES el permiso:
// el texto revela tamaño y ubicación antes de descargar.
struct MotorVozControl: View {
    @State private var estado = VozEngine.estado()
    @State private var progreso = ""
    @State private var instalando = false
    @State private var preactivar = Config.ttsXttsPreactivar()
    @State private var rapido = Config.ttsXttsRapido()
    @State private var colchonSeg = Config.ttsXttsColchonSeg()
    @State private var dormir = Config.ttsXttsDormir()
    @State private var dormirMin = Config.ttsXttsDormirMin()
    @State private var arranqueMin = Config.ttsXttsArranqueMin()
    @State private var warmupDummy = Config.ttsXttsWarmupDummy()
    @State private var warmupTexto = Config.ttsXttsWarmupTexto()
    @State private var reco = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch estado {
            case .listo:
                HStack {
                    Text("🟢 Motor de voz instalado (corre tus clones 100% local).").font(.caption)
                    Spacer()
                    Button("Quitar motor") {
                        guard ConfirmacionSegura.pedir("¿Quitar el motor XTTS?",
                            detalle: "Las voces, personas, variantes, entrenamientos y la restauración Máxima NO se borrarán. Para volver a hablar con XTTS tendrás que reinstalar su runtime.",
                            boton: "Quitar runtime") else { return }
                        VozEngine.desinstalar(); estado = VozEngine.estado()
                    }
                        .controlSize(.small)
                }
                Toggle("Preactivar (modelo en RAM → respuesta rápida)", isOn: $preactivar)
                    .font(.caption)
                    .onChange(of: preactivar) { _, v in Config.set("tts_xtts_preactivar", to: v); Voz.preactivarLocal() }
                Text("⚠️ Mantiene el clon (~2 GB) cargado en RAM mientras es tu voz activa: el Agente responde en ~1-2s en vez de recargar el modelo (~15s) cada vez. Si tu Mac va justa de memoria, apágalo (la 1ª respuesta tardará más). \(XttsServer.corriendo ? "🟢 en RAM ahora" : "⚪️ no cargado")")
                    .font(.caption2).foregroundStyle(.secondary)
                if preactivar {
                    HStack {
                        Text("Al abrir: conservar \(Int(arranqueMin)) min").font(.caption2)
                        Slider(value: $arranqueMin, in: 0...120, step: 5) { _ in
                            Config.set("tts_xtts_arranque_min", to: arranqueMin)
                        }.frame(width: 180)
                    }
                    Toggle("Calentar el generador con una frase silenciosa", isOn: $warmupDummy)
                        .font(.caption2)
                        .onChange(of: warmupDummy) { _, v in Config.set("tts_xtts_warmup_dummy", to: v) }
                    if warmupDummy {
                        TextField("Frase de calentamiento", text: $warmupTexto)
                            .font(.caption2)
                            .onChange(of: warmupTexto) { _, v in Config.set("tts_xtts_warmup_texto", to: v) }
                    }
                }
                // Modo rápido: streaming (suena en ~1-2s) con el server a baja prioridad.
                Toggle("Modo RÁPIDO (streaming: suena en ~1-2s mientras genera)", isOn: $rapido)
                    .font(.caption)
                    .onChange(of: rapido) { _, v in Config.set("tts_xtts_rapido", to: v); XttsServer.detener(); Voz.preactivarLocal() }
                Text("Suena mientras genera, arrancando en ~el caché de abajo (más caché = más fluido, cubre las pausas del XTTS). Apagado = por lotes (~4s, siempre fluido).")
                    .font(.caption2).foregroundStyle(.secondary)
                if rapido {
                    HStack {
                        Text("Caché \(String(format: "%.1f", colchonSeg))s").font(.caption2)
                        Slider(value: $colchonSeg, in: 1...6, step: 0.5) { _ in Config.set("tts_xtts_colchon_seg", to: colchonSeg) }
                            .frame(width: 200)
                        Text("(sube si se entrecorta)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                // Ahorro de recursos: dormir el clon tras N minutos (parametrizable).
                Toggle("Dormir el clon tras inactividad (libera RAM/CPU; fn lo despierta)", isOn: $dormir)
                    .font(.caption)
                    .onChange(of: dormir) { _, v in Config.set("tts_xtts_dormir", to: v) }
                if dormir {
                    HStack {
                        Text("Dormir tras \(Int(dormirMin)) min").font(.caption2)
                        Slider(value: $dormirMin, in: 1...30, step: 1) { _ in Config.set("tts_xtts_dormir_min", to: dormirMin) }
                            .frame(width: 200)
                    }
                }
                HStack {
                    Button("🔎 Recomendar según mi Mac") {
                        let i = Recursos.info(); let r = Recursos.recomendar(i)
                        preactivar = r.preactivarClon; Config.set("tts_xtts_preactivar", to: r.preactivarClon)
                        dormirMin = r.dormirMin; Config.set("tts_xtts_dormir_min", to: r.dormirMin)
                        dormir = true; Config.set("tts_xtts_dormir", to: true)
                        Voz.preactivarLocal()
                        reco = r.motivo + " (\(i.nucleos) núcleos, \(i.appleSilicon ? "Apple Silicon" : "Intel"))"
                    }.controlSize(.small)
                }
                if !reco.isEmpty { Text("💡 " + reco).font(.caption2).foregroundStyle(.secondary) }
            case .instalando:
                Text("⏳ Instalando el motor de voz…").font(.caption)
                if !progreso.isEmpty { Text(progreso).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            case .noInstalado:
                Text("El motor de voz (para correr tus clones) no está instalado. BtoDicta descargará su PROPIO Python + IA de voz (~3-4 GB) en ~/.btodicta/voz-engine/ — aislado, no toca tu sistema, borrable de un clic. Después es 100% local, sin internet.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("⬇︎ Instalar motor de voz (~3-4 GB)") {
                    instalando = true; estado = .instalando; progreso = "Empezando…"
                    VozEngine.instalar(onProgreso: { l in DispatchQueue.main.async { progreso = l } },
                                       completion: { ok, msg in
                        DispatchQueue.main.async { progreso = msg; instalando = false; estado = VozEngine.estado() }
                    })
                }.controlSize(.small).disabled(instalando)
            }
        }
        .padding(6).background(Color.secondary.opacity(0.06)).cornerRadius(6)
        .onAppear { estado = VozEngine.estado() }
    }
}

/// Runtime separado para la variante equilibrada. Instalarlo es opt-in y reversible;
/// no toca el entorno XTTS ni el modelo Piper/ONNX de ninguna voz.
struct MotorMlxControl: View {
    @State private var estado = MlxVozEngine.estado()
    @State private var progreso = ""
    @State private var instalando = false
    @State private var preactivar = Config.ttsMlxPreactivar()
    @State private var dormir = Config.ttsMlxDormir()
    @State private var dormirMin = Config.ttsMlxDormirMin()
    @State private var arranqueMin = Config.ttsMlxArranqueMin()
    @State private var warmupDummy = Config.ttsMlxWarmupDummy()
    @State private var warmupTexto = Config.ttsMlxWarmupTexto()
    @State private var colchon = Config.ttsMlxColchonSeg()
    @State private var intervalo = Config.ttsMlxIntervalo()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch estado {
            case .listo:
                HStack {
                    Text("🟢 Motor equilibrado Qwen3‑MLX instalado.").font(.caption)
                    Spacer()
                    Button("Quitar motor") {
                        guard ConfirmacionSegura.pedir("¿Quitar Qwen3‑MLX?",
                            detalle: "Se quitarán su runtime y caché común. Las muestras, transcripciones y demás variantes de cada persona se conservan.",
                            boton: "Quitar Qwen3‑MLX") else { return }
                        MlxVozEngine.desinstalar(); estado = MlxVozEngine.estado()
                    }
                        .controlSize(.small)
                }
                Text("Apple Silicon · clonación local · español · streaming. La primera activación descarga el modelo común (~2,6 GB); después funciona offline. No reemplaza XTTS ni ONNX.")
                    .font(.caption2).foregroundStyle(.secondary)
                Toggle("Preactivar la voz equilibrada (modelo en RAM)", isOn: $preactivar)
                    .font(.caption)
                    .onChange(of: preactivar) { _, v in
                        Config.set("tts_mlx_preactivar", to: v); Voz.preactivarLocal()
                    }
                if preactivar {
                    HStack {
                        Text("Al abrir: conservar \(Int(arranqueMin)) min").font(.caption2)
                        Slider(value: $arranqueMin, in: 0...120, step: 5) { _ in
                            Config.set("tts_mlx_arranque_min", to: arranqueMin)
                        }.frame(width: 180)
                    }
                    Toggle("Precompilar Metal con una frase silenciosa", isOn: $warmupDummy)
                        .font(.caption2)
                        .onChange(of: warmupDummy) { _, v in Config.set("tts_mlx_warmup_dummy", to: v) }
                    if warmupDummy {
                        TextField("Frase de calentamiento", text: $warmupTexto)
                            .font(.caption2)
                            .onChange(of: warmupTexto) { _, v in Config.set("tts_mlx_warmup_texto", to: v) }
                    }
                }
                Toggle("Dormir Qwen3‑MLX tras inactividad", isOn: $dormir)
                    .font(.caption)
                    .onChange(of: dormir) { _, v in Config.set("tts_mlx_dormir", to: v) }
                if dormir {
                    HStack {
                        Text("Dormir tras \(Int(dormirMin)) min").font(.caption2)
                        Slider(value: $dormirMin, in: 1...30, step: 1) { _ in
                            Config.set("tts_mlx_dormir_min", to: dormirMin)
                        }.frame(width: 180)
                    }
                }
                HStack {
                    Text("Inicio fluido: \(String(format: "%.1f", colchon))s").font(.caption2)
                    Slider(value: $colchon, in: 0.2...3, step: 0.2) { _ in
                        Config.set("tts_mlx_colchon_seg", to: colchon)
                    }.frame(width: 150)
                    Text("Chunk: \(String(format: "%.2f", intervalo))s").font(.caption2)
                    Slider(value: $intervalo, in: 0.16...1.0, step: 0.08) { _ in
                        Config.set("tts_mlx_intervalo", to: intervalo); MlxVozServer.detener(); Voz.preactivarLocal()
                    }.frame(width: 120)
                }
            case .instalando:
                Text("⏳ Instalando Qwen3‑MLX…").font(.caption)
                if !progreso.isEmpty { Text(progreso).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
            case .noInstalado:
                Text("⚖️ Opcional: instala el motor equilibrado Qwen3‑TTS/MLX en un Python aislado de BtoDicta. Descarga inicial del runtime y, al usarlo, ~2,6 GB del modelo. Después es 100% local.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("⬇︎ Instalar motor equilibrado") {
                    instalando = true; estado = .instalando; progreso = "Empezando…"
                    MlxVozEngine.instalar(onProgreso: { l in DispatchQueue.main.async { progreso = l } }) { _, msg in
                        progreso = msg; instalando = false; estado = MlxVozEngine.estado()
                    }
                }.controlSize(.small).disabled(instalando)
            }
        }
        .padding(6).background(Color.secondary.opacity(0.06)).cornerRadius(6)
        .onAppear { estado = MlxVozEngine.estado() }
    }
}

/// Restauración de máxima identidad. Runtime separado para poder quitarlo/reinstalarlo
/// sin tocar XTTS, Qwen, Piper, voces ni entrenamientos.
struct MotorMaximaControl: View {
    @State private var estado = VozMaximaEngine.estado()
    @State private var progreso = ""
    @State private var instalando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch estado {
            case .listo:
                HStack {
                    Text("🟢 Restauración ✨ Máxima instalada (Resemble Enhance local).").font(.caption)
                    Spacer()
                    Button("Quitar restauración") {
                        guard ConfirmacionSegura.pedir("¿Quitar la restauración Máxima?",
                            detalle: "No se borrará ninguna voz ni su XTTS. Máxima quedará disponible de nuevo al reinstalar este runtime; mientras tanto el failover usará Calidad.",
                            boton: "Quitar restauración") else { return }
                        VozMaximaEngine.desinstalar(); estado = VozMaximaEngine.estado()
                    }.controlSize(.small)
                }
                Text("Misma receta de mayor identidad: XTTS afinado → Enhance NFE 128 → normalización. Todo vive bajo ~/.btodicta; no llama a Hermes ni a Descargas.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .instalando:
                Text("⏳ Preparando restauración Máxima…").font(.caption)
                if !progreso.isEmpty { Text(progreso).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
            case .noInstalado:
                Text("✨ Opcional: instala la restauración de máxima identidad en un Python aislado (~2–3 GB entre runtime y modelo). Después funciona local y sirve para todos tus clones XTTS.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("⬇︎ Instalar restauración Máxima") {
                    instalando = true; estado = .instalando; progreso = "Empezando…"
                    VozMaximaEngine.instalar(onProgreso: { linea in
                        DispatchQueue.main.async { progreso = linea }
                    }) { _, mensaje in
                        progreso = mensaje; instalando = false; estado = VozMaximaEngine.estado()
                    }
                }.controlSize(.small).disabled(instalando || VozEngine.estado() != .listo)
            }
        }
        .padding(6).background(Color.secondary.opacity(0.06)).cornerRadius(6)
        .onAppear { estado = VozMaximaEngine.estado() }
    }
}

struct VocesLocalesEditor: View {
    @State private var voces: [VozLocal] = VocesLocales.todas()
    @State private var activa: String = Config.ttsVozLocal()
    @State private var mostrarAgregar = false
    @State private var nuevoNombre = ""
    @State private var nuevoCmd = ""
    @State private var nuevaPersona = ""
    @State private var detectadas: [(nombre: String, cmd: String)] = []
    @State private var estado = ""
    @State private var failoverVariantes = Config.ttsLocalVariantesFailover()
    @State private var papelera: [VocesLocales.VozPapelera] = VocesLocales.papelera()

    private func refrescar() {
        voces = VocesLocales.todas(); activa = VocesLocales.activa()?.id ?? ""
        papelera = VocesLocales.papelera()
    }

    private func subirPaquete() {
        let panel = NSOpenPanel()
        panel.title = "Elige la carpeta del paquete de voz"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ConfirmacionSegura.pedir("¿Importar este paquete de voz?",
            detalle: "Importa solo paquetes tuyos o de una fuente confiable. Los checkpoints .pth son modelos Python y no deben abrirse si provienen de desconocidos. BtoDicta reemplazará cualquier runner incluido por uno propio.",
            boton: "Importar paquete confiable") else { return }
        estado = "Importando el paquete…"
        DispatchQueue.global(qos: .userInitiated).async {
            let r = VocesLocales.importarPaquete(desde: url)
            DispatchQueue.main.async {
                switch r {
                case .ok(let v): estado = "Voz “\(v.nombre)” agregada y lista."
                case .faltaModelo: estado = "Esa carpeta no tiene un modelo de voz (.pth). No es un clon."
                case .faltaMuestras(let v):
                    estado = "“\(v.nombre)” agregada, pero le faltan MUESTRAS de voz. Usa “➕ muestras” para subir 3-10 audios (10-30s) de esa persona."
                }
                refrescar()
            }
        }
    }

    private func generarPersona(_ v: VozLocal) {
        estado = "Generando la persona de “\(v.nombre)” (transcribe sus muestras, tarda)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = VocesLocales.autogenerarPersona(v.id, stamp: "ui")
            DispatchQueue.main.async {
                estado = ok ? "Persona de “\(v.nombre)” lista." : "No pude generar la persona (¿motor de entrenamiento listo? ¿tiene muestras?)."
                refrescar()
            }
        }
    }

    private func subirPiper() {
        let panel = NSOpenPanel()
        panel.title = "Elige la voz Piper (.onnx)"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["onnx"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        estado = "Importando la voz rápida…"
        DispatchQueue.global(qos: .userInitiated).async {
            let v = VocesLocales.importarPiper(desde: url)
            DispatchQueue.main.async {
                estado = v != nil ? "Voz rápida “\(v!.nombre)” agregada ⚡" : "No pude importar el .onnx (¿está su .onnx.json al lado?)."
                refrescar()
            }
        }
    }

    private func muestras(_ v: VozLocal) {
        let panel = NSOpenPanel()
        panel.title = "Muestras de voz para “\(v.nombre)” (wav 10-30s)"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        VocesLocales.agregarMuestras(v.id, wavs: panel.urls)
        estado = "Muestras agregadas a “\(v.nombre)”."; refrescar()
    }

    private func descargar(_ v: VozLocal) {
        let panel = NSOpenPanel()
        panel.title = "¿Dónde guardo el paquete “\(v.nombre)”?"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Guardar aquí"
        guard panel.runModal() == .OK, let dst = panel.url else { return }
        let destino = dst.appendingPathComponent("Voz-" + v.id)
        let existe = FileManager.default.fileExists(atPath: destino.path)
        if existe, !ConfirmacionSegura.pedir("¿Reemplazar el paquete exportado?",
            detalle: "Ya existe \(destino.lastPathComponent). Se reemplazará únicamente esa copia exportada; la voz dentro de BtoDicta permanecerá intacta.",
            boton: "Reemplazar copia") { return }
        estado = "Copiando el paquete…"
        DispatchQueue.global(qos: .userInitiated).async {
            let out = VocesLocales.exportarPaquete(v, a: dst, reemplazar: existe)
            DispatchQueue.main.async { estado = out != nil ? "Descargado en \(out!.path)" : "No pude copiar el paquete." }
        }
    }

    /// Asocia una muestra exacta y su transcripción al carril Qwen3‑MLX. La muestra
    /// viaja en el paquete portable; las pesas comunes del modelo no se duplican.
    private func prepararMlx(_ v: VozLocal) {
        if v.tieneMlx, !ConfirmacionSegura.pedir("¿Cambiar la variante Equilibrada?",
            detalle: "Se reemplazarán únicamente su muestra y transcripción Qwen3‑MLX. XTTS, Máxima, ONNX y la persona se conservan.",
            boton: "Elegir otra muestra") { return }
        let panel = NSOpenPanel()
        panel.title = "Muestra limpia de \(v.nombre) (5–20 s)"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.wav]
        if !v.paquete.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: v.paquete).appendingPathComponent("refs")
        }
        guard panel.runModal() == .OK, let ref = panel.url else { return }

        let alerta = NSAlert()
        alerta.messageText = "¿Qué dice exactamente la muestra?"
        alerta.informativeText = "La transcripción literal conserva mejor el acento. Elige el modelo equilibrado recomendado o el de mayor calidad."
        alerta.addButton(withTitle: "Vincular")
        alerta.addButton(withTitle: "Cancelar")
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 500, height: 74))
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let campo = NSTextField(string: v.mlxRefText)
        campo.placeholderString = "Transcripción literal del audio"
        campo.frame.size.width = 500
        let modelos = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 500, height: 26))
        modelos.addItems(withTitles: ["⚖️ 0.6B — equilibrado (recomendado)", "✨ 1.7B — más calidad, más RAM"])
        if v.mlxModelo == MlxVozEngine.modeloCalidad { modelos.selectItem(at: 1) }
        stack.addArrangedSubview(campo); stack.addArrangedSubview(modelos); alerta.accessoryView = stack
        guard alerta.runModal() == .alertFirstButtonReturn else { return }
        let texto = campo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { estado = "Falta escribir exactamente lo que dice la muestra."; return }
        let modelo = modelos.indexOfSelectedItem == 1 ? MlxVozEngine.modeloCalidad : MlxVozEngine.modeloDefault
        let activar = MlxVozEngine.estado() == .listo
        let nueva = VocesLocales.vincularMlx(referencia: ref, transcripcion: texto,
                                             modelo: modelo, a: v.id, activar: activar)
        estado = nueva == nil ? "No pude vincular la muestra."
            : (activar ? "Voz equilibrada lista; preparando el modelo local…"
                       : "Muestra guardada. Instala el motor equilibrado para activarla.")
        refrescar(); if activar { Voz.preactivarLocal() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MotorVozControl()
            MotorMaximaControl()
            MotorMlxControl()
            Text("Tus voces clonadas (100% local). Cada persona puede conservar Máxima XTTS restaurada, Calidad XTTS, Equilibrada Qwen3‑MLX y Rápida Piper/ONNX.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Si una variante falla, probar otra de la misma persona", isOn: $failoverVariantes)
                .font(.caption)
                .onChange(of: failoverVariantes) { _, v in
                    Config.set("tts_local_variantes_failover", to: v)
                }
                .help("Mantiene la identidad: nunca cambia silenciosamente a otra persona; al final usa macOS")

            if voces.isEmpty {
                Text("Todavía no agregaste ninguna voz.").font(.caption).italic().foregroundStyle(.secondary)
            } else {
                ForEach(voces) { v in
                    HStack(spacing: 8) {
                        Button {
                            if activa != v.id,
                               !ConfirmacionSegura.pedir("¿Cambiar la voz activa?",
                                detalle: "BtoDicta dejará de hablar con \(VocesLocales.activa()?.nombre ?? "la voz actual") y usará \(v.nombre). No se borra ninguna voz.",
                                boton: "Usar \(v.nombre)") { return }
                            VocesLocales.fijarActiva(v.id); activa = v.id; Voz.preactivarLocal()
                        } label: {
                            Image(systemName: activa == v.id ? "largecircle.fill.circle" : "circle")
                        }.buttonStyle(.plain).help("Usar la voz local \(v.nombre)")
                        Text(v.nombre).font(.callout)
                        if v.tieneMaxima { Text("✨").font(.caption2).help("Máxima identidad: XTTS con restauración") }
                        if v.tieneMlx { Text("⚖️").font(.caption2).help("Voz equilibrada Qwen3‑MLX") }
                        if !v.onnx.isEmpty { Text("⚡").font(.caption2).help("Voz rápida (Piper)") }
                        if !v.persona.isEmpty { Text("· persona ✓").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        let cantidadVariantes = (v.tieneMaxima ? 1 : 0) + (!v.paquete.isEmpty ? 1 : 0)
                            + (v.tieneMlx ? 1 : 0) + (!v.onnx.isEmpty ? 1 : 0)
                        if cantidadVariantes > 1 {
                            Picker("", selection: Binding(
                                get: { v.variante },
                                set: { nueva in
                                    guard nueva != v.variante else { return }
                                    let antes = ConfirmacionSegura.nombreVariante(v.variante)
                                    let despues = ConfirmacionSegura.nombreVariante(nueva)
                                    guard ConfirmacionSegura.pedir("¿Cambiar la variante de \(v.nombre)?",
                                        detalle: "Cambiará de \(antes) a \(despues). Ningún modelo se elimina y puedes volver cuando quieras.",
                                        boton: "Cambiar a \(despues)") else { refrescar(); return }
                                    VocesLocales.fijarVariante(v.id, nueva); refrescar(); Voz.preactivarLocal()
                                })) {
                                if v.tieneMaxima { Text("✨ Máxima").tag("maxima") }
                                if !v.paquete.isEmpty { Text("Calidad").tag("xtts") }
                                if v.tieneMlx { Text("⚖️ Equilibrada").tag("mlx") }
                                if !v.onnx.isEmpty { Text("⚡ Rápida").tag("onnx") }
                            }.pickerStyle(.menu).frame(width: 126)
                                .help("Elige el equilibrio de esta misma persona; ninguna variante se borra")
                        }
                        Button("🔊") {
                            estado = "Generando “\(v.nombre)”…"
                            Voz.probarVozLocal(v) { estado = "" }
                        }.controlSize(.small).help("Probar esta voz (genera en local, tarda)")
                        if !v.paquete.isEmpty && v.persona.isEmpty {
                            Button("🧠") { generarPersona(v) }.controlSize(.small).help("Generar la persona (cómo habla) transcribiendo sus muestras")
                        }
                        if !v.paquete.isEmpty {
                            if !v.maximaInterna {
                                Button(v.tieneMaxima ? "Hacer propia ✨" : "Crear ✨") {
                                    let quitarLegacy = v.tieneMaxima
                                    guard !quitarLegacy || ConfirmacionSegura.pedir(
                                        "¿Independizar la voz Máxima?",
                                        detalle: "BtoDicta conservará el clon y su calidad, copiará la misma receta a su entorno propio y dejará de llamar al comando externo. Hermes y Descargas ya no serán necesarios.",
                                        boton: "Hacer propia") else { return }
                                    _ = VocesLocales.vincularMaximaInterna(a: v.id, activar: true,
                                                                           quitarLegacy: quitarLegacy)
                                    estado = "Máxima de “\(v.nombre)” ya es interna e independiente."
                                    refrescar(); Voz.preactivarLocal()
                                }.controlSize(.small)
                            }
                            Button(v.tieneMlx ? "Cambiar ⚖️" : "Crear ⚖️") { prepararMlx(v) }
                                .controlSize(.small)
                                .help("Vincular Qwen3‑MLX: más natural que Piper y más rápido que XTTS")
                            Button(v.onnx.isEmpty ? "Crear ⚡" : "Recrear ⚡") {
                                if !v.onnx.isEmpty,
                                   !ConfirmacionSegura.pedir("¿Recrear la variante Rápida?",
                                    detalle: "La ONNX actual seguirá intacta hasta que la nueva termine y sea validada. XTTS, Máxima y Qwen no cambian.",
                                    boton: "Abrir destilador") { return }
                                DestiladorPiperWindow.show(voz: v)
                            }.controlSize(.small)
                                .help("Destilar esta voz XTTS a una variante Piper/ONNX rápida, sin borrar la original")
                            Toggle("stream", isOn: Binding(
                                get: { v.streaming },
                                set: { VocesLocales.fijarStreaming(v.id, $0); refrescar() }))
                                .toggleStyle(.checkbox).font(.caption2)
                                .help("Suena mientras genera (más rápido). Apágalo para generar completo y luego sonar.")
                            Button("➕🎙") { muestras(v) }.controlSize(.small).help("Agregar muestras de voz (wavs de 10-30s)")
                            Button("⬇︎") { descargar(v) }.controlSize(.small).help("Descargar el paquete para llevarlo")
                        }
                        Button("Quitar") {
                            guard ConfirmacionSegura.pedir("¿Quitar “\(v.nombre)”?",
                                detalle: "Se moverá completa a la Papelera de voces (modelo, persona y todas sus variantes). Podrás restaurarla; no se eliminará definitivamente.",
                                boton: "Mover a Papelera") else { return }
                            estado = VocesLocales.borrar(v.id)
                                ? "“\(v.nombre)” está en la Papelera y se puede restaurar."
                                : "No pude preservar la voz; no se quitó nada."
                            refrescar()
                        }.controlSize(.small)
                    }
                }
            }

            HStack {
                Button("🎓 Entrenar una voz nueva") { EntrenadorWindow.show() }.controlSize(.small)
                    .help("Crea un clon XTTS desde una carpeta de audios (calidad, clona al vuelo)")
                Button("⚡ Entrenar voz Piper (rápida)") { EntrenadorPiperWindow.show() }.controlSize(.small)
                    .help("Hornea una voz FIJA veloz (.onnx) desde una carpeta de audios")
                Button("⬆︎ Subir voz (paquete)") { subirPaquete() }.controlSize(.small)
                    .help("Elige una carpeta de paquete de voz portable (con voz_gen.py)")
                Button("⚡ Subir voz rápida (.onnx)") { subirPiper() }.controlSize(.small)
                    .help("Voz Piper (.onnx): rápida, casi instantánea")
                Button("➕ Agregar voz") { mostrarAgregar.toggle() }.controlSize(.small)
                Button("🔍 Detectar mis voces (VozClon)") {
                    detectadas = VocesLocales.detectarDeVozClon()
                    estado = detectadas.isEmpty ? "No encontré proyectos entrenados en \(Config.vozClonBase())." : ""
                }.controlSize(.small)
            }

            if !detectadas.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Encontradas — pulsa para agregar:").font(.caption).bold()
                    ForEach(Array(detectadas.enumerated()), id: \.offset) { _, d in
                        HStack {
                            Text(d.nombre).font(.caption)
                            Spacer()
                            Button("Agregar") {
                                VocesLocales.agregar(nombre: d.nombre, cmd: d.cmd)
                                detectadas.removeAll { $0.nombre == d.nombre }; refrescar()
                            }.controlSize(.small)
                        }
                    }
                }.padding(6).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            }

            if !papelera.isEmpty {
                DisclosureGroup("Papelera de voces (\(papelera.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(papelera) { entrada in
                            HStack {
                                Text(entrada.voz.nombre).font(.caption)
                                Text(Date(timeIntervalSince1970: entrada.borradaEn), style: .date)
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Restaurar") {
                                    if let voz = VocesLocales.restaurar(entrada.id) {
                                        estado = "“\(voz.nombre)” restaurada con sus variantes."
                                    } else { estado = "No pude restaurar esa voz; no se borró la copia de Papelera." }
                                    refrescar()
                                }.controlSize(.small)
                            }
                        }
                    }.padding(.top, 4)
                }.font(.caption)
            }

            if mostrarAgregar {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Nombre (ej. Voz clonada)", text: $nuevoNombre)
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    TextField("Comando con {texto} y {salida}", text: $nuevoCmd)
                        .textFieldStyle(.roundedBorder).frame(width: 460)
                    Text("Persona (opcional): cómo habla esa persona. El Agente redacta en ese estilo antes de que la voz lo lea.").font(.caption2).foregroundStyle(.secondary)
                    TextField("ej. Habla cariñosa: usa diminutivos, frases cortas, se despide con 'hasta pronto'…", text: $nuevaPersona, axis: .vertical)
                        .textFieldStyle(.roundedBorder).frame(width: 460).lineLimit(2...5)
                    HStack {
                        Button("Guardar") {
                            let n = nuevoNombre.trimmingCharacters(in: .whitespaces)
                            let c = nuevoCmd.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty, c.contains("{texto}") else { estado = "Falta nombre o {texto} en el comando."; return }
                            VocesLocales.agregar(nombre: n, cmd: c, persona: nuevaPersona.trimmingCharacters(in: .whitespaces))
                            nuevoNombre = ""; nuevoCmd = ""; nuevaPersona = ""; mostrarAgregar = false; estado = ""; refrescar()
                        }.controlSize(.small)
                        Button("Cancelar") { mostrarAgregar = false }.controlSize(.small)
                    }
                }.padding(6).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            }

            if !estado.isEmpty { Text(estado).font(.caption).foregroundStyle(.secondary) }
            Text("Los paquetes y runtimes gestionados viven en ~/.btodicta. “Detectar VozClon” queda solo para migrar proyectos antiguos; crear, usar, restaurar y exportar voces nuevas ya es propio de BtoDicta.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { refrescar() }
    }
}
