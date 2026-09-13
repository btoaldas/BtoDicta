import AppKit
import Foundation

enum RecetasRuntime {
    /// Devuelve true si el tipo pertenece al motor ampliado; false permite que
    /// el runner legado lo procese sin duplicar Música/Notas/EventKit/etc.
    @discardableResult
    static func ejecutar(tipo: String, valor: String, texto: String, resultadoPrevio: String,
                         simular: Bool,
                         completion: @escaping (ResultadoHerramientaApple) -> Void) -> Bool {
        switch tipo {
        case "resumen_dia":
            ResumenDia.obtener(simular: simular ? AgendaDiaDatos(
                eventos: ["09:00 reunión de prueba"], recordatorios: ["revisar informe"],
                calendarioDisponible: true, recordatoriosDisponibles: true) : nil,
                completion: completion)
        case "resumen_manana":
            ResumenDia.obtener(offsetDias: 1, simular: simular ? AgendaDiaDatos(
                eventos: ["10:00 actividad de mañana"], recordatorios: ["preparar materiales"],
                calendarioDisponible: true, recordatoriosDisponibles: true) : nil,
                completion: completion)
        case "estado_mac":
            let muestra = simular ? EstadoMacDatos(bateria: "85 %", discoLibre: 100 << 30,
                discoTotal: 500 << 30, memoriaUsada: 8 << 30, memoriaTotal: 16 << 30,
                cpuPorcentaje: 17, interfaces: ["en0"], vpn: []) : nil
            EstadoMac.obtener(simular: muestra, completion: completion)
        case "app_primera":
            ejecutarPrimeraApp(valor, simular: simular, completion: completion)
        case "seleccion_resumir", "seleccion_traducir", "seleccion_responder",
             "seleccion_tarea", "seleccion_leer", "seleccion_nota_apple":
            if simular {
                completion(.init(ok: true, mensaje: "Procesaría la selección con «\(tipo)».",
                                 evidencia: ["tipo": tipo, "simulado": "true"]))
            } else {
                SeleccionMac.capturar { r in
                    switch r {
                    case .failure(let e): completion(.init(ok: false, mensaje: e.localizedDescription))
                    case .success(let s):
                        guard let t = s.texto else {
                            completion(.init(ok: false, mensaje: "Selecciona texto antes de usar esta receta.")); return
                        }
                        procesarTextoSeleccionado(t, tipo: tipo, argumento: valor, completion: completion)
                    }
                }
            }
        case "audio_transcribir", "audio_resumir", "audio_traducir", "audio_correo", "audio_oficio":
            if simular {
                completion(.init(ok: true, mensaje: "Transcribiría el audio seleccionado con «\(tipo)».",
                                 evidencia: ["tipo": tipo, "simulado": "true"])); break
            }
            SeleccionMac.capturar { r in
                switch r {
                case .failure(let e): completion(.init(ok: false, mensaje: e.localizedDescription))
                case .success(let s):
                    guard let u = SeleccionMac.primerAudio(s) else {
                        completion(.init(ok: false,
                            mensaje: "Selecciona un archivo de audio compatible en Finder.")); return
                    }
                    procesarAudio(u, tipo: tipo, argumento: valor, completion: completion)
                }
            }
        case "captura_inteligente":
            if simular {
                completion(.init(ok: true, mensaje: "Prepararía una captura inteligente sin enviarla.",
                                 evidencia: ["simulado": "true"])); break
            }
            var solicitud = SolicitudCapturaMac.interpretar(valor, tipoForzado: .imagen)
            solicitud.guardar = true; solicitud.copiar = true
            if solicitud.nombre == nil {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy-MM-dd-HHmmss"
                solicitud.nombre = "Captura-BtoDicta-\(f.string(from: Date()))"
            }
            // “Preparar” significa que el archivo queda en portapapeles. Nunca
            // envía automáticamente desde esta receta.
            solicitud.compartirWhatsApp = false
            if let app = NSApp.delegate as? AppDelegate {
                app.ejecutarCapturaDesdeReceta(solicitud, completion: completion)
            } else {
                CapturaMac.ejecutar(solicitud) { r in
                    completion(.init(ok: r.ok, mensaje: r.mensaje,
                        evidencia: ["archivo": r.archivo?.path ?? "", "copiada": "\(r.solicitud.copiar)"]))
                }
            }
        case "cerrar_apps":
            cerrarAplicaciones(valor, simular: simular, completion: completion)
        default:
            return false
        }
        return true
    }

    private static func ejecutarPrimeraApp(_ valor: String, simular: Bool,
                                           completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let nombres = valor.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        for nombre in nombres where !nombre.isEmpty {
            let t = PerfilAgente.normalizar(nombre).split(separator: " ").map(String.init)
            if case .encontrada(let m) = AplicacionesMac.resolverPrefijo(t) {
                if !simular {
                    NSWorkspace.shared.openApplication(at: m.app.url, configuration: .init(), completionHandler: nil)
                }
                completion(.init(ok: true, mensaje: "Abrí \(m.app.nombre).",
                                 evidencia: ["app": m.app.nombre, "bundle": m.app.bundleId])); return
            }
        }
        completion(.init(ok: false, mensaje: "No encontré ninguna de estas aplicaciones: \(nombres.joined(separator: ", "))."))
    }

    private static func procesarTextoSeleccionado(_ texto: String, tipo: String, argumento: String,
                                                   completion: @escaping (ResultadoHerramientaApple) -> Void) {
        if tipo == "seleccion_nota_apple" {
            NotasApple.crear(texto, completion: completion)
            return
        }
        if tipo == "seleccion_leer" {
            guard Config.ttsActivo() else {
                completion(.init(ok: false, mensaje: "Activa TTS para leer la selección.")); return
            }
            Voz.decir(texto, completion: {
                completion(.init(ok: true, mensaje: "Leí la selección con la voz configurada.",
                                 evidencia: ["caracteres": "\(texto.count)"]))
            })
            return
        }
        var modo: Modo
        switch tipo {
        case "seleccion_resumir": modo = ModosStore.modo("resumir")
        case "seleccion_traducir":
            modo = ModosStore.modo("traducir")
            for tok in ModoResolver.tokensNormalizados(argumento) {
                if let idioma = Idiomas.reconocer(tok) { modo.idiomaDestino = idioma; break }
            }
        case "seleccion_responder": modo = ModosStore.modo("asistente")
        case "seleccion_tarea": modo = ModosStore.modo("tarea")
        default:
            completion(.init(ok: false, mensaje: "Transformación de selección no compatible.")); return
        }
        LLMPostProcess.procesarModo(texto, modo: modo) { salida in
            if tipo == "seleccion_tarea" { NotasStore.agregar(tipo: "tarea", texto: salida) }
            copyText(salida)
            let verbo = tipo == "seleccion_tarea" ? "Creé la tarea" : "Procesé la selección"
            completion(.init(ok: true, mensaje: "\(verbo) y dejé el resultado en el portapapeles. \(salida)",
                             evidencia: ["modo": modo.id, "salida": String(salida.prefix(2_000))]))
        }
    }

    private static func convertirAWav(_ url: URL,
                                       completion: @escaping (Result<Data, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = Config.dir.appendingPathComponent("recetas-temp", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let wav = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
            defer { try? FileManager.default.removeItem(at: wav) }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            p.arguments = ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", url.path, wav.path]
            p.standardOutput = FileHandle.nullDevice; let err = Pipe(); p.standardError = err
            do { try p.run() } catch {
                DispatchQueue.main.async { completion(.failure(error)) }; return
            }
            let limite = Date().addingTimeInterval(120)
            while p.isRunning, Date() < limite { Thread.sleep(forTimeInterval: 0.05) }
            if p.isRunning { p.terminate() }; p.waitUntilExit()
            let bytes = ((try? FileManager.default.attributesOfItem(atPath: wav.path)[.size])
                as? NSNumber)?.int64Value ?? 0
            guard p.terminationStatus == 0, bytes > 0, bytes <= 536_870_912,
                  let data = try? Data(contentsOf: wav, options: .mappedIfSafe), !data.isEmpty else {
                let d = err.fileHandleForReading.readDataToEndOfFile()
                let e = bytes > 536_870_912
                    ? "El audio convertido supera 512 MB; usa Transcribir para dividir un archivo tan largo."
                    : (String(data: d, encoding: .utf8) ?? "afconvert falló")
                DispatchQueue.main.async { completion(.failure(NSError(domain: "BtoDicta.AudioSeleccion", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(e.prefix(500))]))) }; return
            }
            DispatchQueue.main.async { completion(.success(data)) }
        }
    }

    private static func procesarAudio(_ url: URL, tipo: String, argumento: String,
                                      completion: @escaping (ResultadoHerramientaApple) -> Void) {
        convertirAWav(url) { conversion in
            switch conversion {
            case .failure(let e): completion(.init(ok: false, mensaje: "No pude preparar el audio: \(e.localizedDescription)"))
            case .success(let wav):
                Failover.transcribe(wav: wav) { r in
                    switch r {
                    case .failure(let e): completion(.init(ok: false, mensaje: "No pude transcribir: \(e.localizedDescription)"))
                    case .success(let (texto0, proveedor, modelo)):
                        let texto = applyReplacements(texto0)
                        if tipo == "audio_transcribir" {
                            copyText(texto)
                            completion(.init(ok: true,
                                mensaje: "Transcribí «\(url.lastPathComponent)» y copié el texto. \(texto)",
                                evidencia: ["archivo": url.lastPathComponent, "proveedor": proveedor,
                                            "modelo": modelo, "salida": String(texto.prefix(2_000))])); return
                        }
                        var modo: Modo
                        switch tipo {
                        case "audio_resumir": modo = ModosStore.modo("resumir")
                        case "audio_traducir":
                            modo = ModosStore.modo("traducir")
                            for tok in ModoResolver.tokensNormalizados(argumento) {
                                if let idioma = Idiomas.reconocer(tok) { modo.idiomaDestino = idioma; break }
                            }
                        case "audio_correo": modo = ModosStore.modo("correo")
                        case "audio_oficio": modo = ModosStore.modo("oficio")
                        default:
                            completion(.init(ok: false, mensaje: "Proceso de audio no compatible.")); return
                        }
                        LLMPostProcess.procesarModo(texto, modo: modo) { salida in
                            copyText(salida)
                            completion(.init(ok: true,
                                mensaje: "Procesé el audio como \(modo.nombre) y copié el resultado. \(salida)",
                                evidencia: ["archivo": url.lastPathComponent, "proveedor": proveedor,
                                            "modelo": modelo, "modo": modo.id,
                                            "salida": String(salida.prefix(2_000))]))
                        }
                    }
                }
            }
        }
    }

    private static func cerrarAplicaciones(_ valor: String, simular: Bool,
                                            completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let nombres = valor.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !nombres.isEmpty else {
            completion(.init(ok: false, mensaje: "Indica qué aplicaciones quieres cerrar.")); return
        }
        var cerradas: [String] = [], faltantes: [String] = []
        for nombre in nombres {
            let toks = PerfilAgente.normalizar(nombre).split(separator: " ").map(String.init)
            guard case .encontrada(let m) = AplicacionesMac.resolverPrefijo(toks),
                  m.app.bundleId != "com.apple.finder" else { faltantes.append(nombre); continue }
            if simular { cerradas.append(m.app.nombre); continue }
            let vivas = NSRunningApplication.runningApplications(withBundleIdentifier: m.app.bundleId)
            if vivas.isEmpty { faltantes.append(m.app.nombre) }
            else { vivas.forEach { _ = $0.terminate() }; cerradas.append(m.app.nombre) }
        }
        let ok = !cerradas.isEmpty
        completion(.init(ok: ok, mensaje: ok
            ? "Solicité cerrar: \(cerradas.joined(separator: ", ")).\(faltantes.isEmpty ? "" : " No estaban abiertas: \(faltantes.joined(separator: ", ")).")"
            : "No encontré aplicaciones abiertas para cerrar.",
            evidencia: ["cerradas": cerradas.joined(separator: ","),
                        "faltantes": faltantes.joined(separator: ",")]))
    }
}
