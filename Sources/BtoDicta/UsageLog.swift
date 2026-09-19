import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Estadísticas de uso (odómetro por proveedor)

struct UsageLog {
    static var fileURL: URL { Config.dir.appendingPathComponent("uso.jsonl") }
    /// Tarifas por defecto (USD/hora de audio, 2026), por MODELO exacto.
    /// Refs: elevenlabs.io/pricing/api · openai.com/api/pricing · mistral.ai/pricing · groq.com/pricing
    static let tarifasDefecto: [String: Double] = [
        // Precios VERIFICADOS jul-2026 (workflow con fuentes + verificación
        // adversarial). USD/hora de audio. Ajustables por "Poner valor".
        // ElevenLabs
        "scribe_v2_realtime": 0.39, "scribe_v2": 0.22, "scribe_v1": 0.22,
        // Groq — whisper-large-v3 subió a $0.111; distil solo-inglés $0.02
        "whisper-large-v3": 0.111, "whisper-large-v3-turbo": 0.04, "distil-whisper-large-v3-en": 0.02,
        // OpenAI
        "whisper-1": 0.36, "gpt-4o-transcribe": 0.36, "gpt-4o-mini-transcribe": 0.18,
        // Mistral (Voxtral nube)
        "voxtral-mini-latest": 0.18, "voxtral-small-latest": 0.24,
        "voxtral-mini-transcribe": 0.18, "voxtral-realtime": 0.36,
        // Fireworks (Whisper) — $0.0015/min v3, $0.0009/min turbo ($0.054/h)
        "whisper-v3": 0.09, "whisper-v3-turbo": 0.054,
        // Hugging Face Inference (Whisper) — capa gratis DEPRECADA (2025); ahora
        // pass-through a Groq: large-v3 $0.111, turbo $0.04, distil $0.02.
        "openai/whisper-large-v3": 0.111, "openai/whisper-large-v3-turbo": 0.04,
        "distil-whisper/distil-large-v3": 0.02,
        // Deepgram Nova — $0.0043/min (~$0.258/h)
        "nova-3": 0.258, "nova-2": 0.258, "nova-3-medical": 0.312, "flux": 0.46,
        // AssemblyAI — best/nano/universal-3-pro son ALIAS viejos (→ universal-3-5-pro/universal-2)
        "best": 0.21, "nano": 0.15, "universal-3-5-pro": 0.21, "universal-3-pro": 0.21, "universal-2": 0.15,
        // Soniox — todo incluido (diarización/LID/formato); capa gratis
        "stt-rt-v5": 0.12, "stt-async-v5": 0.10, "stt-async-v4": 0.10,
        // Google Cloud STT v2 (Chirp) — streaming $0.96/h, batch dinámico $0.24/h
        "chirp_3": 0.96, "chirp_2": 0.96,
        // Azure AI Speech — batch $0.18/h, fast $0.36/h, real-time $1.00/h; es-EC
        "azure-fast": 0.36, "azure-batch": 0.18, "azure-realtime": 1.00,
        // Gladia — ~$0.0102/min (10 h/mes gratis)
        "default": 0.61,
        // Speechmatics — batch (480 min/mes gratis)
        "standard": 0.30, "enhanced": 0.40,
        // Cloudflare Workers AI (Whisper) — 10k neuronas/día gratis, luego $0.03/h
        "@cf/openai/whisper": 0.03, "@cf/openai/whisper-large-v3-turbo": 0.03,
        // (modelos locales / GGUF → no listados → $0, gratis)
    ]

    /// Fallback por MOTOR para registros viejos sin modelo guardado.
    static let tarifaProveedorFallback: [String: Double] = [
        "ElevenLabs": 0.39, "Groq": 0.04, "OpenAI": 0.18, "Mistral": 0.18,
    ]

    /// Tarifas de STT (USD/hora) desde ~/.btodicta/precios_stt.json — fuente
    /// mantenida (LiteLLM para los que cubre: OpenAI/Groq/Deepgram/…),
    /// refrescada por scripts/update-prices.sh SIN gastar IA. Igual que el
    /// precios_ia.json del pulido, pero para audio. Fresca > curado del código.
    static var tarifasArchivo: [String: Double] = [:]
    static func cargarTarifasArchivo() {
        let url = Config.dir.appendingPathComponent("precios_stt.json")
        guard let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else { return }
        if !j.isEmpty { tarifasArchivo = j }
    }

    /// Tarifa efectiva de un MODELO (USD/hora). Precedencia: la que TÚ pusiste a
    /// mano > el curado VERIFICADO del código > el archivo mantenido (LiteLLM).
    /// OJO: aquí el curado va ANTES que el archivo (al revés que en el chat)
    /// porque los datos de audio de LiteLLM tienen colisiones de nombre entre
    /// proveedores (whisper-large-v3-turbo groq $0.04 vs watsonx $0.36) y algunos
    /// precios viejos; nuestro curado está verificado por proveedor. El archivo
    /// solo rellena el long-tail de modelos que no curamos. Locales → $0.
    static func tarifaModelo(_ modelo: String) -> Double {
        if let manual = Config.tarifa(modelo) { return manual }    // tu valor manda
        if let curado = tarifasDefecto[modelo] { return curado }   // curado verificado (provider-correcto)
        return tarifasArchivo[modelo] ?? 0                         // LiteLLM: rellena huecos
    }

    /// Tarifa de un registro: por su modelo si lo tiene; si no (registro
    /// viejo), fallback por motor canónico.
    static func tarifaRegistro(modelo: String?, motor: String) -> Double {
        if let m = modelo, !m.isEmpty { return tarifaModelo(m) }
        return tarifaProveedorFallback[motor] ?? 0
    }

    /// Texto de referencia de precios para mostrar en la app.
    static let referenciaPrecios = "Precios aprox. por hora de audio (2026): Groq $0.04–0.11 · Fireworks $0.05–0.09 · Soniox $0.10 · Cloudflare $0.03 · Azure $0.18–1.00 (es-EC) · Deepgram $0.26 · Speechmatics $0.30–0.40 · AssemblyAI $0.15–0.21 · OpenAI $0.18–0.36 · ElevenLabs $0.22–0.39 · Gladia $0.61 · Google Chirp $0.96 · Hugging Face $0.02–0.11 · motores locales GRATIS. Se actualizan solos desde LiteLLM; ajústalos por modelo en Modelos."

    /// Consolida las MUCHAS etiquetas históricas ("scribe_v2_realtime",
    /// "ElevenLabs (en vivo)", "ElevenLabs Scribe"…) en un motor único —
    /// sin esto el uso salía fragmentado y con líneas viejas en 0.
    static func motorCanonico(_ p: String) -> String {
        let s = p.lowercased()
        if s.contains("eleven") || s.contains("scribe") { return "ElevenLabs" }
        if s.contains("groq") { return "Groq" }
        if s.contains("voxtral") { return "Voxtral" }
        if s.contains("nemotron") { return "Nemotron" }
        if s.contains("canary") { return "Canary" }
        if s.contains("whisper") { return "Whisper" }
        if s.contains("openai") { return "OpenAI" }
        if s.contains("mistral") { return "Mistral" }
        if s.contains("local") { return "Local" }
        return p
    }

    static func record(provider: String, modelo: String = "", seconds: Double) {
        let iso = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "fecha": iso, "proveedor": motorCanonico(provider), "modelo": modelo, "segundos": seconds,
        ]), var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = FileHandle(forWritingAtPath: fileURL.path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    struct Totales {
        var hoyMin = 0.0, semanaMin = 0.0, mesMin = 0.0, añoMin = 0.0
        var mesCosto = 0.0
        var dictadosHoy = 0
        var porDiaSemana: [Double] = Array(repeating: 0, count: 7)  // últimos 7 días, en minutos
    }

    /// Datos numéricos para las gráficas del panel de estadísticas.
    static func totales() -> Totales {
        var t = Totales()
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return t }
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let now = Date()
        let día = cal.startOfDay(for: now)
        let semana = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? día
        let mes = cal.dateInterval(of: .month, for: now)?.start ?? día
        let año = cal.dateInterval(of: .year, for: now)?.start ?? día

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let seg = json["segundos"] as? Double else { continue }
            let prov = motorCanonico(json["proveedor"] as? String ?? "")
            let mod = json["modelo"] as? String
            let min = seg / 60
            if fecha >= año { t.añoMin += min }
            if fecha >= mes {
                t.mesMin += min
                t.mesCosto += tarifaRegistro(modelo: mod, motor: prov) * seg / 3600
            }
            if fecha >= semana { t.semanaMin += min }
            if fecha >= día { t.hoyMin += min; t.dictadosHoy += 1 }
            // últimos 7 días
            let diasAtras = cal.dateComponents([.day], from: cal.startOfDay(for: fecha), to: día).day ?? 99
            if diasAtras >= 0 && diasAtras < 7 { t.porDiaSemana[6 - diasAtras] += min }
        }
        return t
    }

    /// Minutos por proveedor en [hoy, semana, mes, año] + costo estimado del mes.
    /// Lo gastado por MES y por motor, para el panel de salud.
    ///
    /// `resumen()` ya calculaba el coste, pero solo del mes en curso y recortado
    /// a los tres primeros motores del menú. Saber qué cuesta cada motor al cabo
    /// de los meses es lo que permite decidir si uno vale lo que cobra — y eso
    /// no cabe en una línea de menú.
    struct GastoMes: Identifiable {
        var id: String { mes }
        let mes: String              // "2026-09"
        let porMotor: [(String, Double, Double)]   // motor, horas, dólares
        var horas: Double { porMotor.reduce(0) { $0 + $1.1 } }
        var dolares: Double { porMotor.reduce(0) { $0 + $1.2 } }
    }

    static func gastoPorMes(ultimos: Int = 6) -> [GastoMes] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        var acc: [String: [String: (Double, Double)]] = [:]   // mes → motor → (seg, $)
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let proveedorRaw = json["proveedor"] as? String,
                  let seg = json["segundos"] as? Double else { continue }
            let mes = String(fechaStr.prefix(7))
            _ = fecha
            let motor = motorCanonico(proveedorRaw)
            let coste = tarifaRegistro(modelo: json["modelo"] as? String, motor: motor) * seg / 3600
            var porMotor = acc[mes] ?? [:]
            let previo = porMotor[motor] ?? (0, 0)
            porMotor[motor] = (previo.0 + seg, previo.1 + coste)
            acc[mes] = porMotor
        }
        return acc.keys.sorted(by: >).prefix(ultimos).map { mes in
            let motores = (acc[mes] ?? [:])
                .map { ($0.key, $0.value.0 / 3600, $0.value.1) }
                .sorted { $0.2 == $1.2 ? $0.1 > $1.1 : $0.2 > $1.2 }
            return GastoMes(mes: mes, porMotor: motores)
        }
    }

    static func resumen() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ["Sin uso registrado todavía"]
        }
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let now = Date()
        let día = cal.startOfDay(for: now)
        let semana = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? día
        let mes = cal.dateInterval(of: .month, for: now)?.start ?? día
        let año = cal.dateInterval(of: .year, for: now)?.start ?? día

        var acc: [String: (d: Double, s: Double, m: Double, a: Double, costo: Double)] = [:]
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let fechaStr = json["fecha"] as? String,
                  let fecha = iso.date(from: fechaStr),
                  let proveedorRaw = json["proveedor"] as? String,
                  let seg = json["segundos"] as? Double else { continue }
            let proveedor = motorCanonico(proveedorRaw)
            var t = acc[proveedor] ?? (0, 0, 0, 0, 0)
            if fecha >= año { t.a += seg }
            if fecha >= mes {
                t.m += seg
                t.costo += tarifaRegistro(modelo: json["modelo"] as? String, motor: proveedor) * seg / 3600
            }
            if fecha >= semana { t.s += seg }
            if fecha >= día { t.d += seg }
            acc[proveedor] = t
        }
        guard !acc.isEmpty else { return ["Sin uso registrado todavía"] }

        func fmt(_ seg: Double) -> String {
            seg >= 60 ? String(format: "%.1fm", seg / 60) : String(format: "%.0fs", seg)
        }
        var lines: [String] = []
        for (proveedor, t) in acc.sorted(by: { $0.value.a > $1.value.a }) {
            lines.append("\(proveedor): hoy \(fmt(t.d)) · sem \(fmt(t.s)) · mes \(fmt(t.m)) · año \(fmt(t.a)) (mes ≈ $\(String(format: "%.2f", t.costo)))")
        }
        return lines
    }
}

