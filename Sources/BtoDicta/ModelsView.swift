import AppKit
import SwiftUI

private let acentoM = Color(red: 0.36, green: 0.28, blue: 0.62)

// MARK: - Pestaña Modelos: activos+orden, catálogo local, config cloud

/// Gestor de descargas que vive con la APP, no con la pestaña: salir de
/// Modelos (o cerrar la ventana) ya no mata una descarga en curso — al
/// volver, el progreso sigue ahí o el modelo aparece descargado.
final class Descargas: ObservableObject {
    static let shared = Descargas()
    @Published var progreso: [String: Double] = [:]      // clave → 0..1
    private var obs: [String: NSKeyValueObservation] = [:]
    private var tareas: [String: URLSessionDownloadTask] = [:]

    func bajar(url: URL, destino: URL, clave: String, nombre: String) {
        guard progreso[clave] == nil else { return }     // ya está bajando
        try? FileManager.default.createDirectory(at: destino.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        progreso[clave] = 0.0001
        Log.log(.ia, "descargando \(nombre)")
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmp, _, err in
            DispatchQueue.main.async {
                self?.obs[clave] = nil
                self?.tareas[clave] = nil
                self?.progreso[clave] = nil
                if let tmp, err == nil {
                    try? FileManager.default.removeItem(at: destino)
                    try? FileManager.default.moveItem(at: tmp, to: destino)
                    Log.log(.ia, "\(nombre) descargado")
                } else if (err as NSError?)?.code == NSURLErrorCancelled {
                    Log.log(.ia, "descarga \(nombre) cancelada por el usuario")
                } else {
                    Log.log(.ia, "descarga \(nombre) falló: \(err?.localizedDescription ?? "")")
                }
            }
        }
        tareas[clave] = task
        obs[clave] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async { self?.progreso[clave] = p.fractionCompleted }
        }
        task.resume()
    }

    /// Cancela la descarga (o descargas) de esas claves; no queda basura.
    func cancelar(_ claves: [String]) {
        for c in claves { tareas[c]?.cancel() }
    }
}

final class ProvidersModel: ObservableObject {
    @Published var lista: [Provider] = Providers.load()
    @Published var estadoLocal = ""
    /// Puente al gestor global (la vista observa Descargas.shared aparte).
    var descargas: [String: Double] { Descargas.shared.progreso }

    func recargar() { lista = Providers.load() }
    func guardar() { Providers.save(lista) }

    func toggle(_ id: String) {
        if let i = lista.firstIndex(where: { $0.id == id }) { lista[i].activo.toggle(); guardar() }
    }
    /// Cambia el modelo/parámetro de un proveedor (ej. idioma de Apple Speech).
    func fijarModelo(_ id: String, _ modelo: String) {
        if let i = lista.firstIndex(where: { $0.id == id }) { lista[i].modelo = modelo; guardar() }
    }
    func subir(_ i: Int) { guard i > 0 else { return }; lista.swapAt(i, i - 1); guardar() }
    func bajar(_ i: Int) { guard i < lista.count - 1 else { return }; lista.swapAt(i, i + 1); guardar() }

    /// Un proveedor es visible si no es un STT local sin modelo (Ollama/LM Studio).
    /// La MISMA regla que usa la vista, para que el reorder no se desalinee.
    func visible(_ p: Provider) -> Bool {
        if p.id == "ollama_stt" { return ChatIA.sttLocalModelo["ollama"] != nil }
        if p.id == "lmstudio_stt" { return ChatIA.sttLocalModelo["lmstudio"] != nil }
        return true
    }

    /// Reordena la cascada. `from`/`to` vienen con índices de la lista VISIBLE
    /// (filtrada). BUG anterior: se aplicaban a `lista` completa → con proveedores
    /// ocultos (Ollama/LM Studio STT sin modelo) los índices se corrían y el arrastre
    /// movía la fila equivocada o "no subía". Fix: reordenar SOLO entre las posiciones
    /// que ocupan los visibles; los ocultos quedan clavados en su sitio.
    func mover(from: IndexSet, to: Int, guardarEnDisco: Bool = true) {
        let idxVisibles = lista.indices.filter { visible(lista[$0]) }
        var visibles = idxVisibles.map { lista[$0] }
        // SwiftUI entrega índices válidos, pero un evento atrasado después de que
        // cambie el filtro (detección STT local) no debe provocar un crash.
        guard !from.isEmpty,
              from.allSatisfy({ visibles.indices.contains($0) }),
              to >= 0, to <= visibles.count else { return }
        visibles.move(fromOffsets: from, toOffset: to)
        var arr = lista
        for (k, fullIdx) in idxVisibles.enumerated() { arr[fullIdx] = visibles[k] }
        lista = arr
        if guardarEnDisco { guardar() }
    }

    /// Cambia el modelo/archivo del proveedor local Whisper.
    func usarModeloLocal(_ archivo: String) {
        if let i = lista.firstIndex(where: { $0.id == "whisper_local" }) {
            lista[i].modelo = archivo; lista[i].activo = true; guardar()
        }
        WhisperLocal.modeloArchivo = archivo
        WhisperServer.apagar(motivo: "cambio de modelo local")
        recargar()
    }
    func modeloLocalActual() -> String {
        Providers.modelo(de: "whisper_local") ?? "ggml-large-v3-turbo.bin"
    }

    func descargar(_ m: WhisperModelo) {
        Descargas.shared.bajar(url: m.url, destino: m.localURL, clave: m.archivo, nombre: m.nombre)
    }
    func borrar(_ m: WhisperModelo) {
        try? FileManager.default.removeItem(at: m.localURL)
        Log.log(.ia, "modelo \(m.nombre) borrado")
        objectWillChange.send()
    }

    // ---- Exóticos (llama.cpp): varios archivos por modelo ----

    /// Progreso agregado del modelo (ponderado por tamaño de cada archivo).
    /// nil si ningún archivo del modelo está bajando.
    func progresoExotico(_ m: ExoticoModelo) -> Double? {
        var haypendiente = false
        var acumulado = 0.0
        let total = Double(m.tamañoMB)
        for (archivo, mb) in zip(m.archivos, m.tamañosMB) {
            if let p = descargas[archivo] {
                haypendiente = true
                acumulado += p * Double(mb)
            } else if ModelCatalog.exoticos.first(where: { $0.nombre == m.nombre }) != nil,
                      ExoticoModelo.esGGUFValido(VoxtralServer.modelsDir.appendingPathComponent(archivo), esperadoMB: mb) {
                acumulado += Double(mb)   // ya completo
            }
        }
        return haypendiente ? acumulado / total : nil
    }

    func descargarExotico(_ m: ExoticoModelo) {
        for ((url, destino), mb) in zip(zip(m.urls, m.localURLs), m.tamañosMB)
        where !ExoticoModelo.esGGUFValido(destino, esperadoMB: mb) {
            // Clave POR ARCHIVO: progresos independientes, sin pisar observers.
            Descargas.shared.bajar(url: url, destino: destino,
                                   clave: destino.lastPathComponent, nombre: destino.lastPathComponent)
        }
    }
    func borrarExotico(_ m: ExoticoModelo) {
        for u in m.localURLs { try? FileManager.default.removeItem(at: u) }
        Log.log(.ia, "modelo \(m.nombre) borrado")
        objectWillChange.send()
    }
    func usarExotico(_ m: ExoticoModelo) {
        var lista = Providers.load()
        if let i = lista.firstIndex(where: { $0.id == "voxtral_local" }) {
            lista[i].modelo = m.archivos[0]
            lista[i].activo = true
            Providers.save(lista)
        }
        VoxtralServer.apagar(motivo: "cambio de modelo")
        recargar()
    }

    // ---- Motor transcribe.cpp (Nemotron/Canary) ----

    func descargarTcpp(_ m: TcppModelo) {
        guard !m.descargado else { return }
        Descargas.shared.bajar(url: m.url, destino: m.localURL, clave: m.archivo, nombre: m.archivo)
    }
    func borrarTcpp(_ m: TcppModelo) {
        try? FileManager.default.removeItem(at: m.localURL)
        Log.log(.ia, "modelo \(m.nombre) borrado")
        objectWillChange.send()
    }
    func usarTcpp(_ m: TcppModelo, proveedor: String) {
        var lista = Providers.load()
        if let i = lista.firstIndex(where: { $0.id == proveedor }) {
            lista[i].modelo = m.archivo
            lista[i].activo = true
            Providers.save(lista)
        }
        if proveedor == "voxtral_local" {
            // Si el proveedor pasa al modelo Realtime, el server 3B sobra.
            VoxtralServer.apagar(motivo: "cambio a modelo realtime")
        }
        recargar()
    }

}

struct ModelsView: View {
    @StateObject private var m = ProvidersModel()
    // Observa el gestor GLOBAL: el progreso se pinta aunque la pestaña se
    // haya cerrado y reabierto a mitad de la descarga.
    @ObservedObject private var descargas = Descargas.shared
    @State private var sttTick = 0   // re-render tras detectar STT local
    @State private var chatTick = 0  // re-render tras comprobar cuenta Codex

    /// DETECCIÓN INTELIGENTE: oculta los motores STT locales que NO tienen un
    /// modelo que escuche (Ollama/LM Studio sin whisper). Van al final (orden
    /// alto), así ocultarlos no descoloca el orden de la cascada.
    private var listaVisible: [Provider] {
        let _ = sttTick
        return m.lista.filter { m.visible($0) }
    }
    /// Modelo a mostrar para un proveedor (los STT locales usan el whisper detectado).
    private func modeloDe(_ p: Provider) -> String {
        if p.id == "ollama_stt" { return ChatIA.sttLocalModelo["ollama"] ?? "" }
        if p.id == "lmstudio_stt" { return ChatIA.sttLocalModelo["lmstudio"] ?? "" }
        return p.modelo ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // ── Cascada de failover ──
            seccion("Cascada de failover", "arrow.triangle.branch") {
                Text("Se usa el activo #1; si falla, salta al #2, luego al #3. Arrastra las filas para ordenarlas.")
                    .font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(Array(listaVisible.enumerated()), id: \.element.id) { i, p in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                            Text("\(i + 1)").font(.system(.body, design: .rounded)).bold()
                                .frame(width: 20).foregroundStyle(p.activo ? acentoM : .secondary)
                            Toggle("", isOn: Binding(get: { p.activo }, set: { _ in m.toggle(p.id) }))
                                .toggleStyle(.switch).labelsHidden().tint(acentoM)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(p.nombre).font(.subheadline).bold()
                                    BadgeVivo(id: p.id, modelo: p.modelo ?? "")
                                }
                                Text("\(p.tipo == "nube" ? "☁️ nube" : "💾 local") · \(modeloDe(p))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color(nsColor: .controlBackgroundColor))
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in m.mover(from: from, to: to) }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(listaVisible.count) * 46 + 8)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Los motores locales de transcripción (Ollama/LM Studio) solo aparecen si tienen un modelo whisper. Si no lo ves, haz 'ollama pull whisper' (o carga uno en LM Studio).")
                    .font(.caption2).foregroundStyle(.secondary)
                // Parámetro de Apple Speech (idioma): se asoma abajo si el proveedor existe.
                if let apple = m.lista.first(where: { $0.id == "apple_speech" }) {
                    HStack(spacing: 8) {
                        Text("Apple Speech · idioma:").font(.caption)
                        Picker("", selection: Binding(
                            get: { apple.modelo ?? "es-EC" },
                            set: { m.fijarModelo("apple_speech", $0) })) {
                            Text("Español (Ecuador)").tag("es-EC")
                            Text("Español (México)").tag("es-MX")
                            Text("Español (España)").tag("es-ES")
                            Text("Español (EE.UU.)").tag("es-US")
                            Text("Inglés (EE.UU.)").tag("en-US")
                        }.labelsHidden().frame(width: 200)
                        Text("on-device; es-EC se mapea al español más cercano").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { ChatIA.detectarSTTLocales { sttTick += 1 } }

            // ── Modelos locales (catálogo descargable) ──
            seccion("Modelos locales (Whisper)", "internaldrive") {
                Text("100% offline y gratis. Descarga el que quieras y actívalo como proveedor local.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ModelCatalog.whisper) { modelo in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(modelo.nombre).font(.subheadline).bold()
                                if m.modeloLocalActual() == modelo.archivo {
                                    Text("EN USO").font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(acentoM).foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(modelo.tamañoMB) MB · \(modelo.nota)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let prog = m.descargas[modelo.archivo] {
                            progreso(prog, cancelar: [modelo.archivo])
                        } else if modelo.descargado {
                            Button("Usar") { m.usarModeloLocal(modelo.archivo) }
                                .disabled(m.modeloLocalActual() == modelo.archivo)
                            Button { m.borrar(modelo) } label: { Image(systemName: "trash").foregroundStyle(.red) }
                                .buttonStyle(.plain).help("Eliminar este modelo local descargado")
                        } else {
                            Button { m.descargar(modelo) } label: {
                                Image(systemName: "arrow.down.circle").foregroundStyle(acentoM)
                            }.buttonStyle(.plain).help("Descargar este modelo para usarlo localmente")
                        }
                    }
                    .padding(10).background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // ── Voxtral: dos modelos, dos motores, un proveedor ──
            seccion("Modelos locales (Voxtral)", "brain") {
                Text("Mistral · entienden contexto y respetan mejor las siglas. El Realtime dicta EN VIVO.")
                    .font(.caption).foregroundStyle(.secondary)
                if VoxtralServer.serverBinURL == nil {
                    Label("Falta el motor llama.cpp (viene incluido en la app instalada)",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                // Mini 3B (motor llama.cpp, por lotes)
                ForEach(ModelCatalog.exoticos) { modelo in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(modelo.nombre).font(.subheadline).bold()
                                badgeEnUso(proveedor: "voxtral_local", archivo: modelo.archivos[0])
                                if VoxtralServer.corriendo {
                                    Text("● residente").font(.system(size: 9)).foregroundStyle(.green)
                                }
                            }
                            Text("\(modelo.tamañoMB) MB · \(modelo.nota)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let prog = m.progresoExotico(modelo) {
                            progreso(prog, cancelar: modelo.archivos)
                        } else if modelo.descargado {
                            Button("Usar") { m.usarExotico(modelo) }
                                .disabled(VoxtralServer.serverBinURL == nil)
                            botonBorrar { m.borrarExotico(modelo) }
                        } else {
                            botonDescargar { m.descargarExotico(modelo) }
                        }
                    }
                    .padding(10).background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                // Realtime 4B (motor transcribe.cpp, en vivo)
                ForEach(ModelCatalog.voxtralRealtime) { modelo in
                    filaTcpp(modelo, proveedor: "voxtral_local")
                }
            }

            // ── Nemotron (motor transcribe.cpp, en vivo) ──
            seccion("Modelos locales (Nemotron)", "bolt.badge.clock") {
                Text("NVIDIA · streaming EN VIVO cache-aware, liviano. Sin glosario nativo — los reemplazos corrigen después.")
                    .font(.caption).foregroundStyle(.secondary)
                avisoMotorTcpp
                ForEach(ModelCatalog.nemotron) { modelo in
                    filaTcpp(modelo, proveedor: "nemotron_local")
                }
            }

            // ── Canary (motor transcribe.cpp, por lotes) ──
            seccion("Modelos locales (Canary)", "hare") {
                Text("NVIDIA · el más veloz por lotes (93x). NO tiene modo en vivo: el texto aparece al soltar la tecla.")
                    .font(.caption).foregroundStyle(.secondary)
                avisoMotorTcpp
                ForEach(ModelCatalog.canary) { modelo in
                    filaTcpp(modelo, proveedor: "canary_local")
                }
            }

            // ── Conexión de proveedores cloud (API keys + modelo) ──
            seccion("Proveedores en la nube", "key") {
                Text("Pon tu API key de cada servicio y elige el modelo. Las claves viven solo en tu Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Providers.cloudDisponibles, id: \.id) { c in
                    CloudRow(id: c.id, nombre: c.nombre, modelos: c.modelos, keyEnv: c.keyEnv, onChange: { m.recargar() })
                }
            }

            // No mezclarlo con la cascada STT: una cuenta ChatGPT no transcribe
            // audio. Es un proveedor adicional de TEXTO para pulido y Modos.
            seccion("IA de texto por cuenta · NO transcribe audio", "brain.head.profile") {
                let _ = chatTick
                Label("Esta conexión no pertenece a la cascada de voz→texto. Primero transcribe Groq, Apple, ElevenLabs u otro STT; después Codex puede pulir, traducir, aplicar un Modo o responder.",
                      systemImage: "info.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                CodexCuentaConexionView { chatTick += 1 }
                Text("Cuando esté conectada aparecerá como «ChatGPT por cuenta (Codex)» en Ajustes → Pulido y en la IA propia de cada Modo. OpenAI por API y los motores STT permanecen separados.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func seccion<C: View>(_ titulo: String, _ icono: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(titulo, systemImage: icono).font(.headline).foregroundStyle(acentoM)
            content()
        }
    }

    // ---- piezas compartidas de las filas de modelos ----

    @ViewBuilder
    private var avisoMotorTcpp: some View {
        if TranscribeCpp.cliURL == nil {
            Label("Falta el motor transcribe.cpp (compilar en ~/transcribe.cpp)",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func badgeEnUso(proveedor: String, archivo: String) -> some View {
        if Providers.modelo(de: proveedor) == archivo,
           Providers.cadena().contains(where: { $0.id == proveedor }) {
            Text("EN USO").font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(acentoM).foregroundStyle(.white)
                .clipShape(Capsule())
        }
    }

    /// Barra de progreso con botón ✕ para cancelar la descarga.
    private func progreso(_ p: Double, cancelar claves: [String]) -> some View {
        HStack(spacing: 6) {
            VStack(spacing: 2) {
                ProgressView(value: p).frame(width: 60).tint(acentoM)
                Text("\(Int(p * 100))%").font(.system(size: 9))
            }
            Button { Descargas.shared.cancelar(claves) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancelar descarga")
        }
    }
    private func botonBorrar(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "trash").foregroundStyle(.red) }
            .buttonStyle(.plain).help("Eliminar este modelo local descargado")
    }
    private func botonDescargar(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "arrow.down.circle").foregroundStyle(acentoM) }
            .buttonStyle(.plain).help("Descargar este modelo para usarlo localmente")
    }

    /// Fila estándar de un modelo del motor transcribe.cpp.
    private func filaTcpp(_ modelo: TcppModelo, proveedor: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(modelo.nombre).font(.subheadline).bold()
                    badgeEnUso(proveedor: proveedor, archivo: modelo.archivo)
                    if TcppStreamClient.esModeloStreaming(modelo.archivo) {
                        Text("EN VIVO").font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green.opacity(0.85)).foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                Text("\(modelo.tamañoMB) MB · \(modelo.nota)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let prog = m.descargas[modelo.archivo] {
                progreso(prog, cancelar: [modelo.archivo])
            } else if modelo.descargado {
                Button("Usar") { m.usarTcpp(modelo, proveedor: proveedor) }
                    .disabled(TranscribeCpp.cliURL == nil)
                botonBorrar { m.borrarTcpp(modelo) }
            } else {
                botonDescargar { m.descargarTcpp(modelo) }
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Badge "EN VIVO" (streaming) por proveedor
//
// Marca los motores que transcriben EN VIVO (texto mientras hablas): locales
// streaming (Nemotron/Voxtral RT), ElevenLabs realtime, y los de NUBE con
// WebSocket (Deepgram, Soniox, AssemblyAI, Speechmatics, Gladia). Verde = en
// vivo ACTIVO; gris = lo soporta pero falta activarlo (Avanzado → STT en vivo).
struct BadgeVivo: View {
    let id: String
    let modelo: String
    var body: some View {
        let e = Self.estado(id: id, modelo: modelo)
        if e.mostrar {
            Text(e.activo ? "EN VIVO" : "en vivo")
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(e.activo ? Color.green.opacity(0.85) : Color.gray.opacity(0.55))
                .foregroundStyle(.white).clipShape(Capsule())
                .help(e.activo
                      ? "Transcribe EN VIVO por WebSocket — ves el texto mientras hablas."
                      : "Soporta texto EN VIVO. Actívalo en Ajustes → Avanzado → 'STT en vivo para la nube'.")
        }
    }
    /// (¿mostrar badge?, ¿está activo el modo vivo?)
    static func estado(id: String, modelo: String) -> (mostrar: Bool, activo: Bool) {
        if TcppStreamClient.esModeloStreaming(modelo) { return (true, true) }       // local streaming
        if id == "elevenlabs" && modelo == "scribe_v2_realtime" { return (true, true) }
        if LiveNube.soportan[id] != nil { return (true, Config.sttStreaming()) }    // nube WS: activo solo con el flag
        return (false, false)
    }
}

// MARK: - Fila de proveedor cloud (key + modelo)

struct CloudRow: View {
    let id: String
    let nombre: String
    let modelos: [String]
    let keyEnv: String
    let onChange: () -> Void

    @State private var key = ""
    @State private var modelo = ""
    @State private var mostrarKey = false
    @State private var reciénGuardado = false
    @State private var accountId = ""   // solo Cloudflare (va en la URL)
    @State private var azureRegion = "" // solo Azure (va en la URL)

    /// Precio aproximado por hora de audio (2026), por proveedor de nube.
    static let precios: [String: String] = [
        "elevenlabs": "~$0.39/h en vivo · $0.22 lotes",
        "groq": "~$0.04–0.11/h (capa gratis)",
        "openai": "~$0.18–0.36/h",
        "mistral": "~$0.18–0.36/h",
    ]

    private func guardar() {
        ApiKeys.set(keyEnv, key)
        onChange()
        withAnimation { reciénGuardado = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { reciénGuardado = false }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(nombre).font(.subheadline).bold()
                BadgeVivo(id: id, modelo: modelo)
                if let precio = Self.precios[id] {
                    Text(precio).font(.caption2).foregroundStyle(.secondary)
                }
                AyudaKey(env: keyEnv)   // ayuda (tooltip) + "Conseguir clave" oficial
                Spacer()
                if reciénGuardado {
                    Label("Guardado", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(Color.green)
                        .transition(.opacity)
                } else {
                    Text(key.isEmpty ? "sin clave" : "conectado")
                        .font(.caption2)
                        .foregroundStyle(key.isEmpty ? Color.secondary : Color.green)
                }
            }
            HStack {
                Group {
                    if mostrarKey {
                        TextField("API key…", text: $key)
                    } else {
                        SecureField("API key…", text: $key)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit { guardar() }
                Button { mostrarKey.toggle() } label: {
                    Image(systemName: mostrarKey ? "eye.slash" : "eye")
                }.buttonStyle(.plain)
                    .help(mostrarKey ? "Ocultar la clave de API" : "Mostrar temporalmente la clave de API")
                Button("Guardar") { guardar() }
            }
            // Cloudflare Workers AI necesita el Account ID en la URL (como el chat).
            if id == "cloudflare_stt" {
                HStack {
                    TextField("Account ID de Cloudflare (Dashboard → Workers AI)", text: $accountId)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Config.set("cloudflare_account_id", to: accountId); onChange() }
                    Button("Guardar ID") { Config.set("cloudflare_account_id", to: accountId); onChange() }
                }
                Text("10.000 llamadas/día gratis. Pega tu Account ID y el token de API arriba.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // Azure AI Speech necesita la REGIÓN en la URL (ej. eastus).
            if id == "azure" {
                HStack {
                    TextField("Región de Azure (ej. eastus, brazilsouth)", text: $azureRegion)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Config.set("azure_speech_region", to: azureRegion); onChange() }
                    Button("Guardar región") { Config.set("azure_speech_region", to: azureRegion); onChange() }
                }
                Text("Muy buen español, con locale es-EC (Ecuador). Pon la región de tu recurso de Speech y la key arriba.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Picker("Modelo:", selection: $modelo) {
                ForEach(modelos, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: modelo) { _, nuevo in
                var lista = Providers.load()
                if let i = lista.firstIndex(where: { $0.id == id }) {
                    lista[i].modelo = nuevo; Providers.save(lista); onChange()
                }
                tarifa = String(format: "%.2f", UsageLog.tarifaModelo(nuevo))  // tarifa del modelo elegido
            }
            // Tarifa POR MODELO (para el cálculo de costo). Default = investigado.
            HStack(spacing: 6) {
                Text("Costo $/hora de \(modelo.isEmpty ? "este modelo" : modelo):").font(.caption)
                TextField("", text: $tarifa).frame(width: 55).textFieldStyle(.roundedBorder)
                Button("Poner valor") { guardarTarifa() }.controlSize(.small)
                if tarifaGuardada {
                    Label("Guardado", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green).transition(.opacity)
                }
                Spacer()
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            key = ApiKeys.get(keyEnv)
            modelo = Providers.modelo(de: id) ?? modelos.first ?? ""
            tarifa = String(format: "%.2f", UsageLog.tarifaModelo(modelo))
            if id == "cloudflare_stt" { accountId = Config.cloudflareAccountId() }
            if id == "azure" { azureRegion = Config.azureSpeechRegion() }
        }
    }

    @State private var tarifa = ""
    @State private var tarifaGuardada = false
    /// Guarda la tarifa del MODELO seleccionado (cada modelo tiene su precio).
    private func guardarTarifa() {
        guard !modelo.isEmpty else { return }
        let v = Double(tarifa.replacingOccurrences(of: ",", with: "."))
        Config.setTarifa(modelo, v)                     // nil/0 = volver al default
        tarifa = String(format: "%.2f", UsageLog.tarifaModelo(modelo))
        withAnimation { tarifaGuardada = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { tarifaGuardada = false } }
    }
}
