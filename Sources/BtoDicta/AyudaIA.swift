import AppKit
import SwiftUI

// MARK: - Ayuda por proveedor: tooltip + enlace a "conseguir la API key"
//
// Un solo lugar con, por cada proveedor (clave = su variable de entorno): qué
// es / para qué sirve (tooltip) y la URL OFICIAL donde sacar la key. Lo usan
// Ajustes → "Conectar más IAs" (chat) y Modelos → "Proveedores en la nube" (voz),
// así el usuario no pierde tiempo buscando dónde obtener cada clave.

enum AyudaIA {
    /// env var → (ayuda para el tooltip, URL oficial de las API keys).
    static let info: [String: (ayuda: String, url: String)] = [
        // ── Chat / pulido ──
        "OPENROUTER_API_KEY": ("Una sola key para cientos de modelos, muchos ':free'. Ideal si no sabes cuál usar.", "https://openrouter.ai/keys"),
        "GEMINI_API_KEY": ("Google AI Studio: Gemini Flash con capa gratis generosa (1M de contexto).", "https://aistudio.google.com/apikey"),
        "ANTHROPIC_API_KEY": ("Claude (Anthropic): excelente para pulir y traducir. De pago.", "https://console.anthropic.com/settings/keys"),
        "DEEPSEEK_API_KEY": ("DeepSeek: muy barato y capaz. De pago (centavos).", "https://platform.deepseek.com/api_keys"),
        "XAI_API_KEY": ("xAI (Grok). De pago; requiere créditos en tu equipo.", "https://console.x.ai"),
        "OPENAI_API_KEY": ("OpenAI (GPT): pulido y también transcripción (Whisper/gpt-4o-transcribe). De pago.", "https://platform.openai.com/api-keys"),
        "MOONSHOT_API_KEY": ("Moonshot AI Open Platform: Kimi K2.6 para chat, modos, agente, pulido y traducción. Pago por uso; esta key no usa tu membresía Kimi Code.", "https://platform.kimi.ai/console"),
        "KIMI_CODE_API_KEY": ("Kimi Code por CUENTA: crea una key desde tu membresía y consume la cuota del plan. Permite K3/K2.7 según el nivel y está orientado a coding/agentes externos autorizados; para uso general elige Moonshot API.", "https://www.kimi.com/code/console"),
        "MISTRAL_API_KEY": ("Mistral: pulido y voz (Voxtral). Capa gratis con opt-in a entrenamiento.", "https://console.mistral.ai/api-keys"),
        "CEREBRAS_API_KEY": ("Cerebras: ultrarrápido, ~1 millón de tokens/día GRATIS.", "https://cloud.cerebras.ai/platform/apikeys"),
        "GITHUB_MODELS_KEY": ("GitHub Models: GPT, Llama, Claude y más GRATIS con tu cuenta GitHub (token de acceso).", "https://github.com/settings/tokens"),
        "NVIDIA_API_KEY": ("NVIDIA NIM: 100+ modelos (incluido DeepSeek) GRATIS tras registrarte.", "https://build.nvidia.com"),
        "TOGETHER_API_KEY": ("Together AI: modelos abiertos; créditos gratis al registrarte.", "https://api.together.ai/settings/api-keys"),
        "NOVITA_API_KEY": ("Novita AI: modelos abiertos; créditos gratis.", "https://novita.ai/settings/key-management"),
        "ZAI_CHAT_API_KEY": ("Z.ai (GLM): el modelo GLM-4.5-Flash es GRATIS.", "https://z.ai/manage-apikey/apikey-list"),
        "SILICONFLOW_API_KEY": ("SiliconFlow: catálogo amplio con capa gratis.", "https://cloud.siliconflow.com/account/ak"),
        // ── Transcripción (voz) ──
        "ELEVENLABS_API_KEY": ("ElevenLabs Scribe: la mejor calidad, texto EN VIVO. De pago.", "https://elevenlabs.io/app/settings/api-keys"),
        "GROQ_API_KEY": ("Groq: Whisper GRATIS (2000/día, sin tarjeta) y pulido con Llama. El mejor 'gratis'.", "https://console.groq.com/keys"),
        "FIREWORKS_API_KEY": ("Fireworks: Whisper en la nube, barato; créditos gratis al empezar.", "https://app.fireworks.ai/settings/users/api-keys"),
        "HF_API_KEY": ("Hugging Face: Whisper en la capa gratuita (token de acceso 'read').", "https://huggingface.co/settings/tokens"),
        "DEEPGRAM_API_KEY": ("Deepgram (Nova): $200 de crédito gratis. Soporta texto EN VIVO.", "https://console.deepgram.com/"),
        "ASSEMBLYAI_API_KEY": ("AssemblyAI (Universal): $50 de crédito gratis. Soporta EN VIVO.", "https://www.assemblyai.com/app/api-keys"),
        "GLADIA_API_KEY": ("Gladia: 10 horas/mes GRATIS. Soporta EN VIVO.", "https://app.gladia.io/"),
        "SPEECHMATICS_API_KEY": ("Speechmatics: 480 min/mes GRATIS. Soporta EN VIVO.", "https://portal.speechmatics.com/"),
        "CLOUDFLARE_API_KEY": ("Cloudflare Workers AI (Whisper): 10 000 llamadas/día gratis. Necesita también tu Account ID.", "https://dash.cloudflare.com/profile/api-tokens"),
        "SONIOX_API_KEY": ("Soniox: premium, excelente español latino y el más barato del tier de pago. Capa gratis. EN VIVO.", "https://console.soniox.com/"),
        "AZURE_SPEECH_KEY": ("Azure AI Speech: muy buen español, único con locale es-EC (Ecuador). Necesita también la región.", "https://portal.azure.com/"),
    ]

    static func abrir(_ env: String) {
        guard let url = info[env]?.url, let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}

/// Icono de ayuda (?) con tooltip INSTANTÁNEO: aparece apenas pasas el mouse
/// (via onHover + popover), sin el retardo de ~1-2 s del .help() del sistema —
/// que daba la sensación de que no funcionaba. Además clic = fija/quita el
/// popover (por si prefieres clic). El enlace "Conseguir clave" va aparte.
struct AyudaKey: View {
    let env: String
    var soloIcono = false
    @State private var hover = false
    @State private var fijado = false   // clic lo deja abierto aunque salgas
    var body: some View {
        if let info = AyudaIA.info[env] {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(hover || fijado ? Color.accentColor : .secondary)
                    .onHover { h in hover = h }
                    .onTapGesture { fijado.toggle() }
                    .popover(isPresented: Binding(get: { hover || fijado },
                                                  set: { if !$0 { fijado = false } }),
                             arrowEdge: .bottom) {
                        Text(info.ayuda)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(width: 260)
                    }
                if !soloIcono {
                    Button("Conseguir clave") { AyudaIA.abrir(env) }
                        .buttonStyle(.link).font(.caption2)
                        .help("Abrir la página oficial donde sacas tu API key: \(info.url)")
                }
            }
        }
    }
}
