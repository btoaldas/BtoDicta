import Foundation

// MARK: - Proveedores de transcripción (nube y local) con orden y failover

/// Un proveedor de transcripción. El orden define la cascada de failover:
/// se intenta el activo #1; si falla, el #2; y así.
struct Provider: Codable, Identifiable {
    var id: String            // "elevenlabs", "groq", "openai", "mistral", "whisper_local"
    var nombre: String
    var tipo: String          // "nube" | "local"
    var activo: Bool
    var orden: Int
    var modelo: String?       // modelo elegido (cloud) o archivo ggml (local)
}

enum Providers {
    private static var url: URL { Config.dir.appendingPathComponent("providers.json") }

    static let porDefecto: [Provider] = [
        Provider(id: "elevenlabs", nombre: "ElevenLabs Scribe", tipo: "nube", activo: true, orden: 0, modelo: "scribe_v2"),
        Provider(id: "groq", nombre: "Groq Whisper", tipo: "nube", activo: true, orden: 1, modelo: "whisper-large-v3"),
        Provider(id: "whisper_local", nombre: "Whisper local", tipo: "local", activo: false, orden: 2, modelo: "ggml-large-v3-turbo.bin"),
    ]

    /// Proveedores cloud que se pueden añadir (con su config de conexión).
    static let cloudDisponibles: [(id: String, nombre: String, modelos: [String], keyEnv: String)] = [
        ("elevenlabs", "ElevenLabs Scribe", ["scribe_v2_realtime", "scribe_v2", "scribe_v1"], "ELEVENLABS_API_KEY"),
        ("groq", "Groq Whisper (gratis)", ["whisper-large-v3", "whisper-large-v3-turbo"], "GROQ_API_KEY"),
        ("openai", "OpenAI", ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"], "OPENAI_API_KEY"),
        ("mistral", "Mistral (Voxtral)", ["voxtral-mini-latest", "voxtral-small-latest"], "MISTRAL_API_KEY"),
        ("fireworks", "Fireworks (Whisper)", ["whisper-v3", "whisper-v3-turbo"], "FIREWORKS_API_KEY"),
        ("hf", "Hugging Face (Whisper, gratis)", ["openai/whisper-large-v3", "openai/whisper-large-v3-turbo", "distil-whisper/distil-large-v3"], "HF_API_KEY"),
        ("deepgram", "Deepgram (Nova)", ["nova-3", "nova-2", "nova-3-medical"], "DEEPGRAM_API_KEY"),
        ("assemblyai", "AssemblyAI (Universal)", ["universal-3-5-pro", "universal-2"], "ASSEMBLYAI_API_KEY"),
        ("soniox", "Soniox (premium, ES latino)", ["stt-async-v5", "stt-async-v4"], "SONIOX_API_KEY"),
        ("azure", "Azure AI Speech (es-EC)", ["azure-fast"], "AZURE_SPEECH_KEY"),
        ("fish", "Fish Audio (voz clonada + ASR)", ["transcribe-1"], "FISH_API_KEY"),
        ("gladia", "Gladia (gratis 10h/mes)", ["default"], "GLADIA_API_KEY"),
        ("speechmatics", "Speechmatics (gratis 480min/mes)", ["standard", "enhanced"], "SPEECHMATICS_API_KEY"),
        ("cloudflare_stt", "Cloudflare Workers AI (Whisper)", ["@cf/openai/whisper", "@cf/openai/whisper-large-v3-turbo"], "CLOUDFLARE_API_KEY"),
    ]

    /// Proveedores que se agregan a configs existentes cuando salen en una
    /// versión nueva (apagados, al final — el usuario decide activarlos).
    static let nuevos: [Provider] = [
        // Apple Speech nativo (on-device, macOS 26+): gratis, sin key, sin red.
        // El mismo motor que usa VoiceInk. Apagado por defecto; el usuario lo activa.
        Provider(id: "apple_speech", nombre: "Apple Speech (nativo, on-device)", tipo: "local", activo: false,
                 orden: 98, modelo: "es-EC"),
        Provider(id: "voxtral_local", nombre: "Voxtral local", tipo: "local", activo: false,
                 orden: 99, modelo: "Voxtral-Mini-4B-Realtime-2602-Q4_K_M.gguf"),
        Provider(id: "nemotron_local", nombre: "Nemotron local", tipo: "local", activo: false,
                 orden: 100, modelo: "nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf"),
        Provider(id: "canary_local", nombre: "Canary local", tipo: "local", activo: false,
                 orden: 101, modelo: "canary-1b-flash-Q8_0.gguf"),
        Provider(id: "openai", nombre: "OpenAI", tipo: "nube", activo: false,
                 orden: 102, modelo: "gpt-4o-mini-transcribe"),
        Provider(id: "mistral", nombre: "Mistral (Voxtral nube)", tipo: "nube", activo: false,
                 orden: 103, modelo: "voxtral-mini-latest"),
        Provider(id: "fireworks", nombre: "Fireworks (Whisper)", tipo: "nube", activo: false,
                 orden: 104, modelo: "whisper-v3"),
        // STT de API propia (no OpenAI-compat) — apagados; el usuario los activa.
        // HF y Gladia/Speechmatics tienen capa gratis (accesibilidad).
        Provider(id: "hf", nombre: "Hugging Face (Whisper)", tipo: "nube", activo: false,
                 orden: 107, modelo: "openai/whisper-large-v3"),
        Provider(id: "deepgram", nombre: "Deepgram (Nova)", tipo: "nube", activo: false,
                 orden: 108, modelo: "nova-3"),
        Provider(id: "assemblyai", nombre: "AssemblyAI (Universal)", tipo: "nube", activo: false,
                 orden: 109, modelo: "universal-3-5-pro"),
        // STT de PAGO premium (investigados jul-2026): Soniox = mejor valor +
        // español latino; Azure = único con es-EC (Ecuador).
        Provider(id: "soniox", nombre: "Soniox (ES latino)", tipo: "nube", activo: false,
                 orden: 113, modelo: "stt-async-v5"),
        Provider(id: "azure", nombre: "Azure AI Speech (es-EC)", tipo: "nube", activo: false,
                 orden: 114, modelo: "azure-fast"),
        Provider(id: "gladia", nombre: "Gladia", tipo: "nube", activo: false,
                 orden: 110, modelo: "default"),
        // Fish Audio: la misma clave sirve para transcribir y para hablar con
        // una voz clonada. La transcripción no tiene capa gratuita.
        Provider(id: "fish", nombre: "Fish Audio", tipo: "nube", activo: false,
                 orden: 115, modelo: "transcribe-1"),
        Provider(id: "speechmatics", nombre: "Speechmatics", tipo: "nube", activo: false,
                 orden: 111, modelo: "standard"),
        Provider(id: "cloudflare_stt", nombre: "Cloudflare (Whisper)", tipo: "nube", activo: false,
                 orden: 112, modelo: "@cf/openai/whisper"),
        // Locales STT: solo transcriben si tienen un modelo whisper (detección
        // inteligente: se ocultan/desactivan en Modelos si no lo tienen).
        Provider(id: "ollama_stt", nombre: "Ollama (local, whisper)", tipo: "local", activo: false,
                 orden: 105, modelo: nil),
        Provider(id: "lmstudio_stt", nombre: "LM Studio (local, whisper)", tipo: "local", activo: false,
                 orden: 106, modelo: nil),
    ]

    static func load() -> [Provider] {
        guard let data = try? Data(contentsOf: url),
              var list = try? JSONDecoder().decode([Provider].self, from: data), !list.isEmpty else {
            save(porDefecto + nuevos)
            return porDefecto + nuevos
        }
        // Migración 1: el viejo "tcpp_local" (mezclaba Nemotron/Canary/Voxtral)
        // se reparte a su proveedor de familia, conservando orden y estado.
        var migrado = false
        if let i = list.firstIndex(where: { $0.id == "tcpp_local" }) {
            let viejo = list.remove(at: i)
            let m = (viejo.modelo ?? "").lowercased()
            let destino = m.contains("canary") ? "canary_local"
                        : m.contains("nemotron") ? "nemotron_local" : "voxtral_local"
            if let j = list.firstIndex(where: { $0.id == destino }) {
                list[j].modelo = viejo.modelo
                list[j].activo = viejo.activo
                list[j].orden = viejo.orden
            } else {
                list.append(Provider(id: destino, nombre: destino == "canary_local" ? "Canary local"
                                        : destino == "nemotron_local" ? "Nemotron local" : "Voxtral local",
                                     tipo: "local", activo: viejo.activo, orden: viejo.orden, modelo: viejo.modelo))
            }
            migrado = true
        }
        // Migración 2: sumar proveedores nuevos que el JSON viejo no conoce.
        // Sin recursión: si save() fallara (disco lleno), igual devolvemos
        // la lista migrada en memoria y la app sigue funcionando.
        let faltantes = nuevos.filter { n in !list.contains { $0.id == n.id } }
        if !faltantes.isEmpty {
            list.append(contentsOf: faltantes)
        }
        // Sincroniza los GATEWAYS marcados "para voz" como filas de la cascada
        // (id "gw:<uuid>"): agrega los que falten (apagados, al final) y quita
        // los de gateways borrados o que ya no son de voz. Su orden/estado sí
        // se persisten; su config vive en el editor de IAs personalizadas.
        let vozGateways = PersonalizadaStore.cargar().filter { $0.paraVoz && !$0.base.isEmpty }
        let vozIds = Set(vozGateways.map { "gw:\($0.id)" })
        let sobran = list.filter { $0.id.hasPrefix("gw:") && !vozIds.contains($0.id) }
        if !sobran.isEmpty { list.removeAll { p in sobran.contains { $0.id == p.id } } }
        var nuevosGw = false
        for g in vozGateways where !list.contains(where: { $0.id == "gw:\(g.id)" }) {
            list.append(Provider(id: "gw:\(g.id)", nombre: g.nombre.isEmpty ? "Gateway de voz" : g.nombre,
                                 tipo: "nube", activo: false, orden: list.count, modelo: g.modelo))
            nuevosGw = true
        }
        if migrado || !faltantes.isEmpty || !sobran.isEmpty || nuevosGw {
            list.sort { $0.orden < $1.orden }
            save(list)
        }
        return list.sorted { $0.orden < $1.orden }
    }

    static func save(_ list: [Provider]) {
        CuarentenaSTT.limpiarTodo()   // cambió la cascada/modelo: lo que fallaba ya puede estar bien
        var ordenados = list
        for i in ordenados.indices { ordenados[i].orden = i }
        if let data = try? JSONEncoder().encode(ordenados) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func cadena() -> [Provider] { load().filter { $0.activo } }

    /// Pone el proveedor elegido de PRIMERO en la cascada (el resto conserva
    /// su orden relativo). Para el selector rápido del menú y del notch.
    static func moverAlFrente(_ id: String) {
        var lista = load()
        guard let i = lista.firstIndex(where: { $0.id == id }) else { return }
        let elegido = lista.remove(at: i)
        lista.insert(elegido, at: 0)
        save(lista)
        Log.log(.config, "proveedor principal → \(elegido.nombre)")
    }

    static func modelo(de id: String) -> String? {
        load().first { $0.id == id }?.modelo
    }
}

// MARK: - Gestión de claves de API en ~/.btodicta/.env

enum ApiKeys {
    private static var envURL: URL { Config.dir.appendingPathComponent(".env") }

    static func get(_ envName: String) -> String {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return "" }
        for line in text.split(separator: "\n") where line.hasPrefix("\(envName)=") {
            return String(line.dropFirst(envName.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    static func set(_ envName: String, _ value: String) {
        CuarentenaSTT.limpiarTodo()   // key nueva: el 401/403 anterior ya no aplica
        var lineas = (try? String(contentsOf: envURL, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init) ?? []
        lineas.removeAll { $0.hasPrefix("\(envName)=") }
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            lineas.append("\(envName)=\(value.trimmingCharacters(in: .whitespaces))")
        }
        let out = lineas.filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
        Config.asegurarDirSeguro()
        try? out.write(to: envURL, atomically: true, encoding: .utf8)
        Config.protegerSecreto(envURL)   // 0600: el .env guarda las API keys
        Log.log(.config, "API key actualizada: \(envName)")
    }
}
