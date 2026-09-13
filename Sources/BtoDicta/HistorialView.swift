import AppKit
import SwiftUI

private let acentoH = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Historial con buscador: todos tus dictados, filtrables al instante

struct EntradaHistorial: Identifiable {
    let id: URL           // el .txt original, identidad estable de la entrada
    let archivoTexto: URL // original o sidecar recuperado preferido
    let fecha: Date
    let versionTexto: Date // invalida embeddings si aparece/cambia el sidecar
    let texto: String
    let wav: URL?         // el audio hermano, si existe

    var duracion: String? {
        guard let wav, let attrs = try? FileManager.default.attributesOfItem(atPath: wav.path),
              let bytes = attrs[.size] as? Int, bytes > 44 else { return nil }
        let seg = Double(bytes - 44) / 32000.0
        return seg >= 60 ? String(format: "%.0f min %.0f s", seg / 60, seg.truncatingRemainder(dividingBy: 60))
                         : String(format: "%.0f s", seg)
    }
}

final class HistorialModel: ObservableObject {
    @Published var entradas: [EntradaHistorial] = []
    @Published var cargando = false

    func cargar() {
        cargando = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lista: [EntradaHistorial] = []
            let fm = FileManager.default
            if let en = fm.enumerator(at: HistoryWriter.historyDir,
                                      includingPropertiesForKeys: [.contentModificationDateKey]) {
                for case let url as URL in en where HistoryWriter.esTextoPrincipal(url) {
                    let preferido = HistoryWriter.textoPreferidoURL(para: url)
                    guard let texto = try? String(contentsOf: preferido, encoding: .utf8),
                          !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    let versionTexto = (try? preferido.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? fecha
                    let wav = url.deletingPathExtension().appendingPathExtension("wav")
                    lista.append(EntradaHistorial(id: url, archivoTexto: preferido,
                                                  fecha: fecha, versionTexto: versionTexto, texto: texto,
                                                  wav: fm.fileExists(atPath: wav.path) ? wav : nil))
                }
            }
            lista.sort { $0.fecha > $1.fecha }
            DispatchQueue.main.async {
                self?.entradas = lista
                self?.cargando = false
            }
        }
    }
}

struct HistorialView: View {
    @StateObject private var m = HistorialModel()
    @ObservedObject private var preview = AudioPreview.shared
    @State private var busqueda = ""
    @State private var copiado: URL?
    // Búsqueda semántica (por significado, con embeddings)
    @State private var semantica = Config.busquedaSemantica()
    @State private var buscandoSem = false
    @State private var progresoSem = (0, 0)
    @State private var rank: [String: Double] = [:]   // path del .txt → score coseno
    @State private var ordenSem: [URL] = []            // orden por cercanía
    @State private var errorSem: String?

    /// Búsqueda insensible a mayúsculas y tildes ("perez" encuentra "Pérez").
    private var filtradas: [EntradaHistorial] {
        // Modo SEMÁNTICO: ya ordenado por cercanía (top primero), con score. Se
        // muestran los 40 más afines (el resto sería ruido de baja relevancia).
        if semantica, !rank.isEmpty {
            let porPath = Dictionary(uniqueKeysWithValues: m.entradas.map { ($0.id.path, $0) })
            return ordenSem.prefix(40).compactMap { porPath[$0.path] }
        }
        let q = busqueda.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return m.entradas }
        return m.entradas.filter {
            $0.texto.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
                .contains(q)
        }
    }

    /// Lanza la búsqueda semántica: embebe la consulta y ordena por cercanía.
    private func buscarSemantica() {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard semantica, !q.isEmpty else { rank = [:]; ordenSem = []; return }
        buscandoSem = true; errorSem = nil; progresoSem = (0, m.entradas.count)
        let items = m.entradas.map {
            (path: $0.id.path, mtime: $0.versionTexto.timeIntervalSince1970, texto: $0.texto)
        }
        EmbeddingSearch.buscar(consulta: q, items: items,
                               progreso: { hechos, total in progresoSem = (hechos, total) },
                               done: { r in
            buscandoSem = false
            switch r {
            case .failure(let e):
                errorSem = "No pude buscar por significado: \(e.localizedDescription). ¿Está corriendo Ollama (bge-m3)?"
                rank = [:]; ordenSem = []
            case .success(let res):
                rank = Dictionary(uniqueKeysWithValues: res.map { ($0.path, $0.score) })
                ordenSem = res.map { URL(fileURLWithPath: $0.path) }
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Historial de dictados", systemImage: "clock.arrow.circlepath")
                .font(.headline).foregroundStyle(acentoH)

            HStack(spacing: 8) {
                Image(systemName: semantica ? "brain" : "magnifyingglass").foregroundStyle(semantica ? acentoH : .secondary)
                TextField(semantica ? "Buscar por SIGNIFICADO… (Enter para buscar)" : "Buscar en todos tus dictados…", text: $busqueda)
                    .textFieldStyle(.plain)
                    .onSubmit { if semantica { buscarSemantica() } }
                    .onChange(of: busqueda) { _, nuevo in if nuevo.isEmpty { rank = [:]; ordenSem = [] } }
                if buscandoSem { ProgressView().controlSize(.small) }
                if !busqueda.isEmpty {
                    Button { busqueda = ""; rank = [:]; ordenSem = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help("Limpiar la búsqueda del historial")
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Toggle(isOn: $semantica) {
                    Label("Buscar por significado (semántica)", systemImage: "brain")
                        .font(.caption)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: semantica) { _, on in
                    Config.set("busqueda_semantica", to: on)
                    rank = [:]; ordenSem = []; errorSem = nil
                    if on, !busqueda.trimmingCharacters(in: .whitespaces).isEmpty { buscarSemantica() }
                }
                if semantica {
                    Text(buscandoSem ? "Indexando \(progresoSem.0)/\(progresoSem.1)…"
                                     : "Encuentra por idea, no por palabra exacta. Motor: \(Config.embeddingModelo()) (local).")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let e = errorSem {
                Text(e).font(.caption2).foregroundStyle(.orange)
            }

            if m.cargando {
                ProgressView("Leyendo historial…").frame(maxWidth: .infinity)
            } else if filtradas.isEmpty {
                Text(busqueda.isEmpty ? "Aún no hay dictados guardados."
                                      : "Nada contiene “\(busqueda)”.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 30)
            } else {
                Text("\(filtradas.count) dictado\(filtradas.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filtradas.prefix(300)) { e in
                        fila(e)
                    }
                    if filtradas.count > 300 {
                        Text("Mostrando los 300 más recientes — afina la búsqueda para ver más antiguos.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { m.cargar() }
    }

    private func fila(_ e: EntradaHistorial) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(Self.formatoFecha.string(from: e.fecha))
                    .font(.caption).bold().foregroundStyle(acentoH)
                if let d = e.duracion {
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
                if semantica, let s = rank[e.id.path] {
                    Text("\(Int(max(0, s) * 100))% afín")
                        .font(.system(size: 9)).bold()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(acentoH.opacity(0.25)).clipShape(Capsule())
                }
                Spacer()
                if let wav = e.wav {
                    Button { preview.toggle(wav) } label: {
                        Image(systemName: preview.sonando == wav ? "stop.circle.fill" : "play.circle")
                            .foregroundStyle(acentoH)
                    }.buttonStyle(.plain).help("Escuchar el audio")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(e.texto, forType: .string)
                    copiado = e.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiado == e.id { copiado = nil }
                    }
                } label: {
                    Image(systemName: copiado == e.id ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .foregroundStyle(copiado == e.id ? .green : acentoH)
                }.buttonStyle(.plain).help("Copiar el texto")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([e.archivoTexto])
                } label: {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Mostrar en Finder")
            }
            Text(e.texto)
                .font(.callout)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private static let formatoFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()
}
