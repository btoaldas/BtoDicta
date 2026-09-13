import Foundation

// MARK: - Streaming local NATIVO (bto-stream + transcribe.cpp)
//
// Un proceso bto-stream por dictado: recibe PCM int16 por stdin y emite
// parciales JSON por stdout mientras hablas — texto en vivo 100% offline
// con modelos streaming cache-aware (Nemotron 3.5, multilingüe).
//
// El modelo tarda ~7 s en cargar; mientras tanto los chunks se acumulan
// en el pipe y el motor los alcanza a 32x — para el usuario el texto
// simplemente empieza a fluir a los pocos segundos de hablar.

final class TcppStreamClient {
    var onPartial: ((String) -> Void)?   // committed + tentative acumulado
    var onFinal: ((String) -> Void)?

    private let process = Process()
    private let entrada = Pipe()
    private let salida = Pipe()
    private let colaEscritura = DispatchQueue(label: "beto.tcpp.stream.write")
    private var bufferLineas = Data()
    private var terminado = false

    static var binURL: URL? {
        if let p = Bundle.main.path(forResource: "bto-stream", ofType: nil, inDirectory: "bin") { return URL(fileURLWithPath: p) }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/BtoDicta/native/bto-stream")
        return FileManager.default.isExecutableFile(atPath: dev.path) ? dev : nil
    }

    /// ¿Este archivo de modelo soporta streaming cache-aware?
    static func esModeloStreaming(_ archivo: String) -> Bool {
        let a = archivo.lowercased()
        return a.contains("streaming") || a.contains("realtime")
    }

    /// Idioma que se le pasa al motor: Nemotron exige uno explícito,
    /// Voxtral Realtime solo auto-detecta.
    static func idioma(para archivo: String) -> String {
        archivo.lowercased().contains("realtime") ? "auto" : "es-US"
    }

    /// ¿Este proveedor puede dictar en vivo con el motor local?
    /// (binario presente + su modelo es streaming + está descargado)
    static func disponible(proveedor id: String) -> Bool {
        guard binURL != nil,
              let m = Providers.modelo(de: id), esModeloStreaming(m) else { return false }
        return FileManager.default.fileExists(
            atPath: TranscribeCpp.modelsDir.appendingPathComponent(m).path)
    }

    let proveedorId: String
    init(proveedor id: String) { proveedorId = id }

    func start() throws {
        guard let bin = Self.binURL, let modelo = Providers.modelo(de: proveedorId) else {
            throw ScribeError.ws("bto-stream no disponible")
        }
        // Un pipe roto no debe tumbar la app (el proceso puede morir a mitad).
        signal(SIGPIPE, SIG_IGN)

        process.executableURL = bin
        process.arguments = [TranscribeCpp.modelsDir.appendingPathComponent(modelo).path,
                             Self.idioma(para: modelo), "400"]
        process.standardInput = entrada
        process.standardOutput = salida
        // El motor avisa por stderr de sus propios truncamientos («output
        // truncated at the … context cap») y de los fallos de feed/finalize.
        // Mandarlo a /dev/null dejaba esos avisos invisibles: ahora las líneas
        // que importan van al registro (el ruido de Metal se filtra).
        let errores = Pipe()
        process.standardError = errores
        errores.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            for linea in s.split(separator: "\n") {
                let l = linea.trimmingCharacters(in: .whitespaces)
                guard !l.isEmpty, !l.hasPrefix("ggml_"), !l.hasPrefix("load"),
                      !l.contains("dummy_kernel"), !l.contains("compiling pipeline") else { continue }
                Log.log(.ia, "bto-stream: \(l.prefix(200))")
            }
        }

        salida.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.procesar(data) }
        }
        try process.run()
        Log.log(.ia, "bto-stream arrancó (pid \(process.processIdentifier)) con \(modelo)")
    }

    /// true una vez encolado el cierre de stdin — protegido por colaEscritura.
    private var entradaCerrada = false

    /// PCM int16 16 kHz mono, tal cual sale del Recorder.
    /// El fd se toca SOLO dentro de colaEscritura y con el guard de cierre:
    /// pedir .fileDescriptor a un handle ya cerrado crashea con NSException.
    func send(chunk: Data) {
        colaEscritura.async { [weak self] in
            guard let self, !self.entradaCerrada else { return }
            let fd = self.entrada.fileHandleForWriting.fileDescriptor
            chunk.withUnsafeBytes { buf in
                var restante = buf.count
                var p = buf.baseAddress!
                while restante > 0 {
                    let n = write(fd, p, restante)
                    if n <= 0 { return }   // pipe roto: el proceso murió, el failover cubre
                    restante -= n
                    p += n
                }
            }
        }
    }

    /// Fin del dictado: cerrar stdin → el motor hace finalize y emite {"f":…}.
    func finish() {
        colaEscritura.async { [weak self] in
            guard let self, !self.entradaCerrada else { return }
            self.entradaCerrada = true
            try? self.entrada.fileHandleForWriting.close()
        }
    }

    func cancel() {
        terminado = true
        salida.fileHandleForReading.readabilityHandler = nil
        colaEscritura.async { [weak self] in
            guard let self, !self.entradaCerrada else { return }
            self.entradaCerrada = true
            try? self.entrada.fileHandleForWriting.close()
        }
        if process.isRunning { process.terminate() }
    }

    private func procesar(_ data: Data) {
        guard !terminado else { return }
        bufferLineas.append(data)
        while let nl = bufferLineas.firstIndex(of: 0x0A) {
            let linea = bufferLineas.prefix(upTo: nl)
            bufferLineas.removeSubrange(...nl)
            manejar(String(data: linea, encoding: .utf8) ?? "")
        }
    }

    private func manejar(_ linea: String) {
        guard !linea.isEmpty, linea != "READY" else { return }
        guard let json = try? JSONSerialization.jsonObject(with: Data(linea.utf8)) as? [String: String] else { return }
        if let final = json["f"] {
            terminado = true
            salida.fileHandleForReading.readabilityHandler = nil
            onFinal?(final.trimmingCharacters(in: .whitespaces))
        } else {
            let c = json["c"] ?? ""
            let t = json["t"] ?? ""
            let texto = (c + " " + t).trimmingCharacters(in: .whitespaces)
            if !texto.isEmpty { onPartial?(texto) }
        }
    }
}
