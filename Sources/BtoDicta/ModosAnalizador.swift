import AppKit
import SwiftUI

// MARK: - El sistema se mejora a sí mismo: analiza modos.jsonl y sugiere mejoras
//
// (1) AUTÓNOMO: heurísticas sobre el registro (comandos no reconocidos, "al filo",
//     WhatsApp sin match…) → sugerencias + agregar ejemplos con un clic.
// (2) IA: manda el resumen a la IA de chat conectada para sugerencias más finas.

enum ModosAnalizador {
    struct Evento { let ev: String; let d: [String: Any] }
    struct NoReconocido: Identifiable { let id = UUID(); let comando: String; let mejor: String; let score: Double }

    static func eventos() -> [Evento] {
        let url = Config.dir.appendingPathComponent("logs").appendingPathComponent("modos.jsonl")
        guard let txt = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return txt.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).compactMap { line in
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ev = d["ev"] as? String else { return nil }
            return Evento(ev: ev, d: d)
        }
    }

    /// Comandos semánticos NO reconocidos (aceptado=false) — candidatos a ejemplo.
    static func noReconocidos() -> [NoReconocido] {
        var vistos = Set<String>()
        return eventos().filter { $0.ev == "semantico" }.compactMap { e -> NoReconocido? in
            let aceptado = (e.d["aceptado"] as? Bool) ?? true
            let comando = (e.d["comando"] as? String) ?? ""
            guard !aceptado, !comando.isEmpty, vistos.insert(comando).inserted else { return nil }
            return NoReconocido(comando: comando, mejor: (e.d["mejor"] as? String) ?? "-", score: (e.d["score"] as? Double) ?? 0)
        }
    }

    static func resumenTexto() -> String {
        let evs = eventos()
        guard !evs.isEmpty else { return "Aún no hay registro de modos. Usa modos por voz y vuelve a analizar." }
        var out = "REGISTRO DE MODOS — \(evs.count) eventos\n\n"
        var porModo: [String: Int] = [:]
        for e in evs where e.ev == "despacho" { porModo[(e.d["modo"] as? String) ?? "?", default: 0] += 1 }
        if !porModo.isEmpty {
            out += "Uso por modo:\n" + porModo.sorted { $0.value > $1.value }.map { "  • \($0.key): \($0.value)" }.joined(separator: "\n") + "\n\n"
        }
        let sem = evs.filter { $0.ev == "semantico" }
        if !sem.isEmpty {
            let aceptados = sem.filter { ($0.d["aceptado"] as? Bool) ?? false }.count
            let scores = sem.compactMap { $0.d["score"] as? Double }
            out += "Semántico: \(sem.count) intentos · \(aceptados) reconocidos · \(sem.count - aceptados) NO"
            if !scores.isEmpty { out += " · score prom \(String(format: "%.2f", scores.reduce(0, +) / Double(scores.count)))" }
            out += "\n\n"
        }
        let nr = noReconocidos()
        if !nr.isEmpty {
            out += "⚠️ Comandos NO reconocidos (agrégalos como Ejemplo abajo):\n"
            out += nr.prefix(20).map { "  • \"\($0.comando)\" → ¿\($0.mejor)? (\(String(format: "%.2f", $0.score)))" }.joined(separator: "\n") + "\n\n"
        }
        let bl = sem.filter {
            let s = ($0.d["score"] as? Double) ?? 0, u = ($0.d["umbral"] as? Double) ?? 0.5
            return (($0.d["aceptado"] as? Bool) ?? false) && s < u + 0.06
        }
        if !bl.isEmpty {
            out += "Al filo (refuerza con ejemplos):\n"
            out += bl.prefix(10).map { "  • \"\(($0.d["comando"] as? String) ?? "")\" (\(($0.d["mejor"] as? String) ?? "")) \(String(format: "%.2f", ($0.d["score"] as? Double) ?? 0))" }.joined(separator: "\n") + "\n\n"
        }
        var wv = Set<String>()
        let wsm = evs.filter { $0.ev == "whatsapp" && ($0.d["resultado"] as? String) == "sin_match" }
            .compactMap { $0.d["nombre"] as? String }.filter { wv.insert($0).inserted }
        if !wsm.isEmpty { out += "WhatsApp sin coincidencia (revisa esos contactos): \(wsm.prefix(10).joined(separator: ", "))\n\n" }
        out += "SUGERENCIAS:\n"
        if !nr.isEmpty { out += "  → Agrega los comandos no reconocidos como 'Ejemplos' de sus modos (un clic abajo).\n" }
        if !bl.isEmpty { out += "  → Los 'al filo' mejoran con 1-2 ejemplos más, o baja un poco la sensibilidad.\n" }
        if !wsm.isEmpty { out += "  → Revisa nombre/número de los contactos sin match (código país 593…).\n" }
        if nr.isEmpty && bl.isEmpty && wsm.isEmpty { out += "  → Todo bien reconocido. 👍\n" }
        return out
    }

    /// Pide sugerencias a la IA de chat conectada.
    static func pedirIA(_ completion: @escaping (String) -> Void) {
        guard let ia = ChatIA.seleccionada() else { completion("No hay IA de chat conectada (pon una key en Modelos)."); return }
        let resumen = resumenTexto()
        let prompt = """
        Eres un asistente que MEJORA un sistema de reconocimiento de comandos de voz por "modos".
        Abajo el registro resumido (qué reconoció bien/mal). Da sugerencias CONCRETAS y accionables, en español, máx 12 líneas:
        - Qué frases de ejemplo agregar a cada modo para reconocer mejor.
        - Si conviene ajustar la sensibilidad (umbral) o las palabras analizadas.
        - Patrones de error que notes.

        \(resumen)
        """
        if ia.esCuentaCodex {
            AgenteCodex.transformar(prompt, modelo: ia.modeloEfectivo,
                                    timeout: Config.pulidoTimeout()) { salida in
                let texto = salida?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                completion(texto.isEmpty ? "La cuenta Codex no respondió." : texto)
            }
            return
        }
        guard let req = ia.requestChat(prompt: prompt, temperatura: 0.3, textLen: resumen.count) else { completion("No pude armar la consulta."); return }
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let txt = (data != nil && (200..<300).contains(code))
                ? (ia.extraerContenido(data!)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Respuesta vacía.")
                : "La IA no respondió (HTTP \(code))."
            DispatchQueue.main.async { completion(txt) }
        }.resume()
    }

    /// Agrega un comando como Ejemplo de un modo (y re-calienta los vectores).
    static func agregarEjemplo(comando: String, modoId: String) {
        var lista = ModosStore.todos()
        guard let i = lista.firstIndex(where: { $0.id == modoId }) else { return }
        if !lista[i].ejemplosVoz.contains(comando) { lista[i].ejemplosVoz.append(comando) }
        ModosStore.guardar(lista)
        EmbeddingSearch.calentarModos(lista.filter { $0.id != "dictado" }.map { ($0.id, ModosStore.ejemplos($0)) })
    }
}

// MARK: Vista

private let acentoAn = Color(red: 0.36, green: 0.28, blue: 0.62)

struct AnalizadorModosView: View {
    @State private var resumen = ModosAnalizador.resumenTexto()
    @State private var noRec = ModosAnalizador.noReconocidos()
    @State private var respIA = ""
    @State private var pidiendo = false
    @State private var asignar: [UUID: String] = [:]   // NoReconocido.id → modoId elegido
    private var modos: [Modo] { ModosStore.todos().filter { $0.id != "dictado" } }

    private func recargar() { resumen = ModosAnalizador.resumenTexto(); noRec = ModosAnalizador.noReconocidos() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("El sistema se mejora a sí mismo", systemImage: "wand.and.stars.inverse")
                        .font(.headline).foregroundStyle(acentoAn)
                    Spacer()
                    Button { recargar() } label: { Image(systemName: "arrow.clockwise") }.help("Recargar")
                }
                Text("Analiza el registro de modos y sugiere mejoras — de forma autónoma o con tu IA.")
                    .font(.caption).foregroundStyle(.secondary)

                Text(resumen).font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))

                if !noRec.isEmpty {
                    Text("Agregar comandos no reconocidos como Ejemplo:").font(.subheadline).bold()
                    ForEach(noRec) { nr in
                        HStack(spacing: 8) {
                            Text("\"\(nr.comando)\"").font(.callout).lineLimit(1)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { asignar[nr.id] ?? (modos.first { $0.id == nr.mejor }?.id ?? modos.first?.id ?? "") },
                                set: { asignar[nr.id] = $0 })) {
                                ForEach(modos, id: \.id) { Text($0.nombre).tag($0.id) }
                            }.labelsHidden().frame(width: 160)
                            Button("Agregar") {
                                let mid = asignar[nr.id] ?? (modos.first { $0.id == nr.mejor }?.id ?? "")
                                if !mid.isEmpty { ModosAnalizador.agregarEjemplo(comando: nr.comando, modoId: mid); recargar() }
                            }.controlSize(.small)
                        }
                    }
                }

                Divider()
                HStack {
                    Button {
                        pidiendo = true; respIA = ""
                        ModosAnalizador.pedirIA { r in respIA = r; pidiendo = false }
                    } label: { Label("Pedir sugerencias a la IA", systemImage: "sparkles") }
                        .disabled(pidiendo)
                    if pidiendo { ProgressView().controlSize(.small) }
                }
                if !respIA.isEmpty {
                    Text(respIA).font(.callout).textSelection(.enabled)
                        .padding(10).background(acentoAn.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }.padding(18)
        }.frame(minWidth: 560, minHeight: 480)
    }
}

enum AnalizadorWindow {
    private static var win: NSWindow?
    static func show() {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AnalizadorModosView()))
            w.title = "Mejorar modos · BtoDicta"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            win = w
        }
        NSApp.activate(ignoringOtherApps: true); win?.center(); win?.makeKeyAndOrderFront(nil)
    }
}
