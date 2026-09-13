import SwiftUI

// MARK: - Config por proveedor TTS de nube (voz/modelo/streaming + estado de key)

struct TTSNubeConfig: View {
    let id: String
    @State private var voz = ""
    @State private var modelo = ""
    @State private var streaming = true

    private var p: TTSNubeProveedor? { TTSCloud.proveedor(id) }
    private var tieneKey: Bool {
        guard let p else { return false }
        if let e = ProcessInfo.processInfo.environment[p.keyEnv], !e.isEmpty { return true }
        return !ApiKeys.get(p.keyEnv).isEmpty
    }

    var body: some View {
        if let p {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tieneKey ? "🟢 Key puesta" : "🔴 Falta la key")
                        .font(.caption).foregroundStyle(tieneKey ? .green : .red)
                    Text("(\(p.keyEnv), en pestaña Modelos)").font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Voz:").font(.caption).frame(width: 50, alignment: .leading)
                    TextField(p.vozDefault, text: $voz)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                        .onChange(of: voz) { _, v in Config.fijarTtsCloud("tts_cloud_voz", id, v) }
                }
                HStack {
                    Text("Modelo:").font(.caption).frame(width: 50, alignment: .leading)
                    TextField(p.modeloDefault, text: $modelo)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                        .onChange(of: modelo) { _, v in Config.fijarTtsCloud("tts_cloud_modelo", id, v) }
                }
                if p.ws {
                    Toggle("Streaming por WebSocket (suena mientras se genera)", isOn: $streaming)
                        .onChange(of: streaming) { _, v in Config.fijarTtsCloud("tts_cloud_streaming", id, v) }
                }
                Text(p.nota).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(6).background(Color.secondary.opacity(0.06)).cornerRadius(6)
            .onAppear {
                voz = Config.ttsCloudVoz(id); modelo = Config.ttsCloudModelo(id)
                streaming = Config.ttsCloudStreaming(id)
            }
        }
    }
}
