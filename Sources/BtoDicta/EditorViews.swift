import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

private let acentoEd = Color(red: 0.36, green: 0.28, blue: 0.62)

// Voz de la Mac para el botón "escuchar" (solo pronuncia el término; la
// corrección por sonido NO usa audio, trabaja con el texto).
private let ttsSintetizador = AVSpeechSynthesizer()
private func hablarTermino(_ texto: String) {
    let s = texto.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return }
    let u = AVSpeechUtterance(string: s)
    u.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
    u.rate = 0.42
    ttsSintetizador.stopSpeaking(at: .immediate)
    ttsSintetizador.speak(u)
}

// Popover "probar": escribes una palabra y te dice si la fonética la cazaría.
// Usa EXACTAMENTE el mismo triple candado que la corrección real.
struct ProbarSonidoView: View {
    let termino: String
    @State private var palabra = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Probar fonética → \(termino)").font(.headline)
            Text("Escribe una palabra y te digo si la corregiría a «\(termino)». Sin audio: compara cómo se escriben.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("ej: Gentrix, Sentrix, kilos…", text: $palabra).textFieldStyle(.roundedBorder)
            let p = palabra.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty {
                let caza = p.count >= 3 && !Aprendizaje.esComun(p) && Fonetica.coincide(palabra: p, termino: termino)
                HStack(spacing: 6) {
                    Image(systemName: caza ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(caza ? .green : .secondary)
                    Text(caza ? "sí → se cambia a «\(termino)»" : "no → se deja igual").bold().font(.subheadline)
                }
                Text("código  \(Fonetica.codigo(p))  vs  \(Fonetica.codigo(termino))")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(width: 280)
    }
}

// MARK: - Editor visual de keyterms (CRUD completo + activar/desactivar + import/export)

struct Keyterm: Identifiable {
    let id = UUID()
    var texto: String
    var activo: Bool
}

final class KeytermsStore: ObservableObject {
    @Published var items: [Keyterm] = []
    private var url: URL { Config.dir.appendingPathComponent("keyterms.txt") }

    init() { load() }

    func load() {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        items = text.split(separator: "\n").compactMap { raw in
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            // "# palabra" = desactivada (se conserva pero no se usa)
            if s.hasPrefix("#") {
                let t = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : Keyterm(texto: t, activo: false)
            }
            return Keyterm(texto: s, activo: true)
        }
    }
    func save() {
        let text = items.map { $0.activo ? $0.texto : "# \($0.texto)" }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    func add(_ w: String) {
        let t = w.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !items.contains(where: { $0.texto.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        items.insert(Keyterm(texto: t, activo: true), at: 0); save(); Log.log(.config, "glosario: +\(t)")
    }
    func remove(_ offsets: IndexSet) { items.remove(atOffsets: offsets); save(); Log.log(.config, "glosario: eliminada palabra") }
    var activas: Int { items.filter { $0.activo }.count }

    func exportar(to dest: URL) { try? String(contentsOf: url, encoding: .utf8).write(to: dest, atomically: true, encoding: .utf8) }
    func importar(from src: URL) {
        guard let nuevo = try? String(contentsOf: src, encoding: .utf8) else { return }
        for linea in nuevo.split(separator: "\n") {
            let s = linea.trimmingCharacters(in: .whitespaces)
            add(s.hasPrefix("#") ? String(s.dropFirst()).trimmingCharacters(in: .whitespaces) : s)
        }
    }
}

struct KeytermsEditor: View {
    @StateObject private var store = KeytermsStore()
    @State private var nueva = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Palabras del glosario").font(.title3).bold()
                    Text("\(store.activas) activas de \(store.items.count) · viajan al modelo")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Importar…") { importar() }
                    Button("Exportar…") { exportar() }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }
                    .frame(width: 44)
            }

            HStack {
                TextField("Nueva palabra…", text: $nueva)
                    .textFieldStyle(.roundedBorder).onSubmit { agregar() }
                Button("Agregar", action: agregar)
                    .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach($store.items) { $item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { item.activo },
                            set: { item.activo = $0; store.save() }))
                            .toggleStyle(.checkbox).labelsHidden()
                        TextField("", text: Binding(
                            get: { item.texto },
                            set: { item.texto = $0 }), onCommit: { store.save() })
                            .textFieldStyle(.plain)
                            .foregroundStyle(item.activo ? .primary : .secondary)
                            .strikethrough(!item.activo)
                        Spacer()
                        Button { borrar(item.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }.buttonStyle(.plain).help("Eliminar este término del glosario")
                    }
                }
                .onDelete { store.remove($0) }
            }
            .frame(minHeight: 280)
        }
        .padding(20).frame(width: 440, height: 520)
    }

    private func agregar() { store.add(nueva); nueva = "" }
    private func borrar(_ id: UUID) {
        if let i = store.items.firstIndex(where: { $0.id == id }) { store.remove(IndexSet(integer: i)) }
    }
    private func exportar() {
        let p = NSSavePanel(); p.nameFieldStringValue = "glosario-btodicta.txt"
        if p.runModal() == .OK, let url = p.url { store.exportar(to: url); Log.log(.config, "exportado a \(url.lastPathComponent)") }
    }
    private func importar() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.plainText, .text]
        if p.runModal() == .OK, let url = p.url { store.importar(from: url); Log.log(.config, "importado de \(url.lastPathComponent)") }
    }
}

// MARK: - Voz (experimental): grabar muestras del término + probar por voz

struct VozView: View {
    let termino: String
    @StateObject private var grabador = GrabadorVoz()
    @State private var muestras: [URL] = []
    @State private var reproductor: AVAudioPlayer?
    @State private var grabandoTipo: String?      // "correcta" | "falsa" | nil
    @State private var resultado: String?
    @State private var cazaria = false
    @State private var correctas: [Float] = []
    @State private var falsas: [Float] = []

    private var pruebaURL: URL { FileManager.default.temporaryDirectory.appendingPathComponent("beto-prueba-voz.wav") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voz para «\(termino)»").font(.headline)
            Text("Graba tu voz diciéndolo varias veces (más muestras = más robusto). Al dictar, con el flag activo, se reconoce por cómo suena, además del texto.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if muestras.isEmpty {
                Text("Sin muestras todavía.").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(muestras, id: \.self) { url in
                    HStack(spacing: 8) {
                        Text(url.lastPathComponent).font(.caption).monospaced()
                        Spacer()
                        Button { reproducir(url) } label: { Image(systemName: "play.circle") }
                            .buttonStyle(.borderless).help("Escuchar esta muestra de voz")
                        Button { AudioMatch.borrar(url); refrescar() } label: { Image(systemName: "trash").foregroundStyle(.red) }
                            .buttonStyle(.borderless).help("Eliminar esta muestra de voz")
                    }
                }
            }

            Button {
                if grabador.grabando { grabador.detener(); refrescar() }
                else { grabador.iniciar(a: AudioMatch.nuevaMuestraURL(termino)) }
            } label: {
                Label(grabador.grabando ? "Detener (guardar muestra)" : "Grabar muestra",
                      systemImage: grabador.grabando ? "stop.circle.fill" : "record.circle")
                    .foregroundStyle(grabador.grabando ? .red : acentoEd)
            }.buttonStyle(.bordered)

            Divider()
            Text("Probar: graba, di la palabra y evalúo. Etiqueta cada prueba para que aprenda la raya.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { toggle("correcta") } label: {
                    Label(grabandoTipo == "correcta" ? "Detener" : "Prueba correcta",
                          systemImage: grabandoTipo == "correcta" ? "stop.circle.fill" : "checkmark.circle")
                        .foregroundStyle(grabandoTipo == "correcta" ? .red : .green)
                }.buttonStyle(.bordered).disabled(muestras.isEmpty || grabandoTipo == "falsa")
                .help("Di la palabra CORRECTA («\(termino)»). Debe salir bajo.")
                Button { toggle("falsa") } label: {
                    Label(grabandoTipo == "falsa" ? "Detener" : "Prueba falsa",
                          systemImage: grabandoTipo == "falsa" ? "stop.circle.fill" : "xmark.circle")
                        .foregroundStyle(grabandoTipo == "falsa" ? .red : .orange)
                }.buttonStyle(.bordered).disabled(muestras.isEmpty || grabandoTipo == "correcta")
                .help("Di adrede una palabra PARECIDA o distinta. Debe salir alto.")
            }

            if let r = resultado {
                HStack(spacing: 6) {
                    Image(systemName: cazaria ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(cazaria ? .green : .secondary)
                    Text(r).font(.subheadline).bold()
                }
            }
            if !correctas.isEmpty || !falsas.isEmpty {
                Divider()
                if !correctas.isEmpty {
                    Text(String(format: "✅ Correctas (%d): %.2f–%.2f", correctas.count, correctas.min() ?? 0, correctas.max() ?? 0))
                        .font(.caption).foregroundStyle(.green)
                    Text(correctas.map { String(format: "%.2f", $0) }.joined(separator: ", "))
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                }
                if !falsas.isEmpty {
                    Text(String(format: "✗ Falsas (%d): %.2f–%.2f", falsas.count, falsas.min() ?? 0, falsas.max() ?? 0))
                        .font(.caption).foregroundStyle(.orange)
                    Text(falsas.map { String(format: "%.2f", $0) }.joined(separator: ", "))
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14).frame(width: 300)
        .onAppear { refrescar(); recargarPruebas() }
    }

    private func refrescar() { muestras = AudioMatch.muestras(termino) }
    private func recargarPruebas() {
        correctas = AudioMatch.recientesPorTipo(termino, tipo: "correcta")
        falsas = AudioMatch.recientesPorTipo(termino, tipo: "falsa")
    }
    private func reproducir(_ url: URL) {
        reproductor = try? AVAudioPlayer(contentsOf: url); reproductor?.play()
    }
    private func toggle(_ tipo: String) {
        if grabandoTipo == tipo { evaluar(tipo: tipo) }
        else { resultado = nil; grabador.iniciar(a: pruebaURL); grabandoTipo = tipo }
    }
    private func evaluar(tipo: String) {
        grabador.detener(); grabandoTipo = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let d = AudioMatch.distancia(pruebaURL: pruebaURL, termino: termino) else {
                resultado = "no pude leer el audio"; cazaria = false; return
            }
            let u = AudioMatch.umbral()
            cazaria = d <= u
            resultado = String(format: "%@ · distancia %.2f (raya %.2f) → %@",
                               tipo == "correcta" ? "correcta" : "falsa", d, u,
                               cazaria ? "reconoce" : "no")
            AudioMatch.registrarPrueba(termino: termino, dist: d, umbral: u, caza: cazaria, tipo: tipo)
            recargarPruebas()
        }
    }
}

// MARK: - Editor visual de reemplazos (CRUD + activar/desactivar + import/export)

struct Rule: Identifiable {
    let id = UUID()
    var original: String
    var replacement: String
    var isRegex: Bool
    var activo: Bool
    var porSonido: Bool = false
    var sigla: Bool = false
}

final class RulesStore: ObservableObject {
    @Published var rules: [Rule] = []
    private var url: URL { Config.dir.appendingPathComponent("reemplazos.json") }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        rules = arr.map { Rule(original: $0["original"] as? String ?? "",
                               replacement: $0["replacement"] as? String ?? "",
                               isRegex: $0["isRegex"] as? Bool ?? false,
                               activo: $0["activo"] as? Bool ?? true,
                               porSonido: $0["porSonido"] as? Bool ?? false,
                               sigla: $0["sigla"] as? Bool ?? false) }
    }
    /// Guarda descartando filas totalmente vacías (así no quedan huérfanas).
    func save() {
        let limpias = rules.filter {
            !($0.original.trimmingCharacters(in: .whitespaces).isEmpty &&
              $0.replacement.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        let arr = limpias.map { r -> [String: Any] in
            var d: [String: Any] = ["original": r.original, "replacement": r.replacement]
            if r.isRegex { d["isRegex"] = true }
            if !r.activo { d["activo"] = false }
            if r.porSonido { d["porSonido"] = true }
            if r.sigla { d["sigla"] = true }
            return d
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }
    func purgarVacias() {
        rules.removeAll {
            $0.original.trimmingCharacters(in: .whitespaces).isEmpty &&
            $0.replacement.trimmingCharacters(in: .whitespaces).isEmpty
        }
        save()
    }
    func add() { rules.append(Rule(original: "", replacement: "", isRegex: false, activo: true)); Log.log(.config, "reemplazos: +fila") }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id }; save(); Log.log(.config, "reemplazos: eliminada regla") }

    func exportar(to dest: URL) { try? Data(contentsOf: url).write(to: dest) }
    func importar(from src: URL) {
        guard let data = try? Data(contentsOf: src),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for d in arr {
            rules.append(Rule(original: d["original"] as? String ?? "",
                              replacement: d["replacement"] as? String ?? "",
                              isRegex: d["isRegex"] as? Bool ?? false,
                              activo: d["activo"] as? Bool ?? true))
        }
        save()
    }
}

struct RulesEditor: View {
    @StateObject private var store = RulesStore()
    @State private var probarID: UUID?     // fila con el popover "probar" abierto
    @State private var vozID: UUID?        // fila con el popover de voz abierto
    @State private var porAudio = Config.matchPorAudio()
    @State private var umbral = Double(AudioMatch.umbral())   // raya de sensibilidad (probar)
    @State private var umbralDict = Double(AudioMatch.umbralDictado())  // raya del dictado real
    @State private var refrescarSugerido = 0                  // bump al cerrar popover de voz

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reemplazos").font(.title3).bold()
                    Text("Si el modelo escucha lo de la izquierda, lo cambia por lo de la derecha.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Importar…") { importar() }
                    Button("Exportar…") { exportar() }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }.frame(width: 44)
                Button { store.add() } label: { Image(systemName: "plus") }
                    .help("Agregar una regla de reemplazo")
            }
            // Flag experimental: coincidir por AUDIO (tu voz grabada).
            Toggle(isOn: Binding(get: { porAudio },
                                 set: { porAudio = $0; Config.set("match_por_audio", to: $0) })) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.badge.plus")
                    Text("Coincidir por audio (experimental)").font(.subheadline)
                }
            }.toggleStyle(.switch).tint(acentoEd)
            if porAudio {
                Text("Graba tu voz diciendo el término (botón 🎙 de cada fila) y, al dictar, se reconoce por cómo suena — además del texto. Apagado no cambia nada.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("Sensibilidad (raya): \(String(format: "%.1f", umbral))")
                        .font(.caption).frame(width: 155, alignment: .leading)
                    Slider(value: Binding(get: { umbral },
                                          set: { umbral = $0; Config.set("umbral_audio", to: $0) }),
                           in: 2.0...7.0, step: 0.1).tint(acentoEd)
                    Button("Restablecer") {
                        umbral = Double(AudioMatch.umbralDefecto)
                        Config.set("umbral_audio", to: umbral)
                    }.controlSize(.small)
                }
                Text("Es la distancia máxima para dar por buena una palabra. Más ALTA = más permisivo: reconoce aunque lo digas distinto, pero puede confundir palabras parecidas (falsos positivos). Más BAJA = más estricto: casi no confunde, pero puede no reconocer tu propia palabra.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                // Umbral SUGERIDO a partir de tus pruebas reales (todas las filas).
                let _ = refrescarSugerido      // fuerza recálculo al cerrar un popover
                if let s = AudioMatch.umbralSugerido() {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").foregroundStyle(acentoEd)
                        Text(String(format: "Sugerido para tu voz: %.1f", s.valor)).font(.caption).bold()
                        Text(String(format: "(correctas ≤%.1f · falsas ≥%.1f · %d+%d pruebas)", s.corrHi, s.falsLo, s.nCorr, s.nFals))
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("Usar") { umbral = Double(s.valor); Config.set("umbral_audio", to: umbral) }.controlSize(.small)
                    }
                    if s.traslape {
                        Text("⚠️ Tus correctas y falsas se traslapan: el audio no separa limpio para tu voz. Graba más muestras limpias, o mejor quédate con el texto.")
                            .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Haz pruebas etiquetadas (🎙 → “Prueba correcta” / “Prueba falsa”) y te sugiero una raya a tu medida (necesita ≥2 de cada una).")
                        .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                // Raya del DICTADO real (escala PROPIA, más alta que probar).
                HStack(spacing: 10) {
                    Text("Raya al dictar: \(String(format: "%.1f", umbralDict))")
                        .font(.caption).frame(width: 155, alignment: .leading)
                    Slider(value: Binding(get: { umbralDict },
                                          set: { umbralDict = $0; Config.set("umbral_audio_dictado", to: $0) }),
                           in: 6.0...16.0, step: 0.1).tint(acentoEd)
                    Button("Restablecer") {
                        umbralDict = Double(AudioMatch.umbralDictadoDefecto)
                        Config.set("umbral_audio_dictado", to: umbralDict)
                    }.controlSize(.small)
                }
                Text("Es la raya para corregir DENTRO de un dictado (frase completa). Corre en escala más alta que “probar por voz” (~8–13). Default 10.4.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                if let sd = AudioMatch.umbralDictadoSugerido() {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").foregroundStyle(acentoEd)
                        Text(String(format: "Sugerido al dictar: %.1f", sd.valor)).font(.caption).bold()
                        Text(String(format: "(dijiste ≤%.1f · no ≥%.1f · %d+%d dictados)", sd.corrHi, sd.falsLo, sd.nCorr, sd.nFals))
                            .font(.caption2).foregroundStyle(.secondary)
                        Button("Usar") { umbralDict = Double(sd.valor); Config.set("umbral_audio_dictado", to: umbralDict) }.controlSize(.small)
                    }
                    if sd.traslape {
                        Text("⚠️ En dictado tus con/sin se traslapan — margen fino. Más muestras del término ayudan.")
                            .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("").frame(width: 22)
                Text("Escuchado (variantes con coma)").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                Text("Se escribe").font(.caption).frame(width: 120, alignment: .leading)
                Text("").frame(width: 22)
            }
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach($store.rules) { $rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(get: { rule.activo },
                                                 set: { rule.activo = $0; store.save() }))
                            .toggleStyle(.checkbox).labelsHidden().frame(width: 22)
                        TextField("sentrix, senbox…", text: $rule.original, onCommit: { store.save() })
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Zentrix", text: $rule.replacement, onCommit: { store.save() })
                            .textFieldStyle(.roundedBorder).frame(width: 110)
                        // Escuchar (TTS): solo pronuncia el término. NO es cómo
                        // funciona la corrección (esa es por texto) — es comodidad.
                        Button { hablarTermino(rule.replacement) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(rule.replacement.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Escuchar la pronunciación (voz de la Mac). Solo para oírlo — la corrección no usa audio.")
                        // Probar: ¿qué palabras cazaría la fonética de este término?
                        Button { probarID = (probarID == rule.id ? nil : rule.id) } label: {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .disabled(rule.replacement.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Probar: escribe una palabra y te digo si la fonética la corregiría.")
                        .popover(isPresented: Binding(get: { probarID == rule.id },
                                                      set: { if !$0 { probarID = nil } })) {
                            ProbarSonidoView(termino: rule.replacement)
                        }
                        // Voz (experimental): grabar muestras + probar por voz.
                        if porAudio {
                            Button { vozID = (vozID == rule.id ? nil : rule.id) } label: {
                                Image(systemName: AudioMatch.tieneMuestras(rule.replacement) ? "mic.fill" : "mic")
                                    .foregroundStyle(AudioMatch.tieneMuestras(rule.replacement) ? acentoEd : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(rule.replacement.trimmingCharacters(in: .whitespaces).isEmpty)
                            .help("Grabar tu voz para este término y probar por voz.")
                            .popover(isPresented: Binding(get: { vozID == rule.id },
                                                          set: { if !$0 { vozID = nil; refrescarSugerido += 1; umbral = Double(AudioMatch.umbral()) } })) {
                                VozView(termino: rule.replacement)
                            }
                            // Sigla: acrónimo (DSTI) → coloca por posición del audio.
                            Toggle(isOn: Binding(get: { rule.sigla }, set: { rule.sigla = $0; store.save() })) {
                                Image(systemName: "textformat.abc")
                            }
                            .toggleStyle(.checkbox)
                            .help("Es una SIGLA/acrónimo (DSTI, UNESCO). El audio la coloca por DÓNDE sonó, no por parecido de letras (las siglas deletreadas no suenan a sus letras).")
                        }
                        // Interruptor de la corrección por sonido (fonética).
                        Toggle(isOn: Binding(get: { rule.porSonido },
                                             set: { rule.porSonido = $0; store.save() })) {
                            Image(systemName: "waveform")
                        }
                        .toggleStyle(.checkbox)
                        .help("Corrección por SONIDO (fonética): además de las variantes exactas de la izquierda, corrige palabras cuyo TEXTO se escribe/suena parecido a «\(rule.replacement)». Se deduce de las letras, no del audio.")
                        Button { store.remove(rule.id) } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }.buttonStyle(.plain).frame(width: 22)
                            .help("Eliminar esta regla de reemplazo")
                    }
                    .opacity(rule.activo ? 1 : 0.5)
                }
            }
            // Leyenda: aclara que NADA de esto es audio.
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                Text("\(Image(systemName: "speaker.wave.2.fill")) escuchar la pronunciación · \(Image(systemName: "sparkle.magnifyingglass")) probar qué caza · \(Image(systemName: "waveform")) corregir por sonido (fonética de las LETRAS, no audio).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        }
        .frame(width: 660, height: porAudio ? 640 : 540)
        .onDisappear { store.purgarVacias() }   // al cerrar, limpia filas en blanco
    }

    private func exportar() {
        let p = NSSavePanel(); p.nameFieldStringValue = "reemplazos-btodicta.json"
        if p.runModal() == .OK, let url = p.url { store.exportar(to: url); Log.log(.config, "exportado a \(url.lastPathComponent)") }
    }
    private func importar() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url { store.importar(from: url); Log.log(.config, "importado de \(url.lastPathComponent)") }
    }
}

// MARK: - Ventanas contenedoras

enum EditorWindows {
    private static var keytermsWin: NSWindow?
    private static var rulesWin: NSWindow?

    static func showKeyterms() { show(&keytermsWin, "Glosario · BtoDicta", KeytermsEditor()) }
    static func showRules() { show(&rulesWin, "Reemplazos · BtoDicta", RulesEditor()) }

    private static func show<V: View>(_ win: inout NSWindow?, _ title: String, _ view: V) {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.center()
        win?.makeKeyAndOrderFront(nil)
    }
}
