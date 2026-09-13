import Foundation

/// Hooks reproducibles del perfil de voz local. Corren antes de AppKit para poder
/// reparar una biblioteca aun desde SSH/sandbox, usando exactamente las APIs de la GUI.
enum VozLocalQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if env["BTODICTA_MAXIMAINSTALLTEST"] == "1" {
            do {
                var ultima = ""
                try VozMaximaEngine.instalarSincrono { linea in ultima = linea }
                if let id = env["BTODICTA_MAXIMA_VOZ_ID"], !id.isEmpty {
                    guard VocesLocales.vincularMaximaInterna(a: id, activar: true,
                                                             quitarLegacy: true) != nil else {
                        print("MAXIMAINSTALLTEST runtime=OK migración=FALLA id=\(id)"); exit(3)
                    }
                    VocesLocales.fijarActiva(id); Config.set("tts_proveedor", to: "xtts_local")
                }
                print("MAXIMAINSTALLTEST OK estado=listo último=\(ultima)")
                exit(0)
            } catch {
                print("MAXIMAINSTALLTEST FALLA \(error.localizedDescription)"); exit(2)
            }
        }
        if env["BTODICTA_TRAINPIPELINETEST"] == "1" {
            do {
                var ultima = ""
                try VozEngine.instalarEntrenamientoSincrono { linea in ultima = linea }
                print("TRAINPIPELINETEST \(VozEngine.entrenoListo ? "OK" : "FALLA") último=\(ultima)")
                exit(VozEngine.entrenoListo ? 0 : 3)
            } catch {
                print("TRAINPIPELINETEST FALLA \(error.localizedDescription)"); exit(2)
            }
        }
        if env["BTODICTA_VOZSAFETYTEST"] == "1" {
            let biblioteca = Config.dir.appendingPathComponent("voces_locales.json")
            let original = try? Data(contentsOf: biblioteca)
            let temporal = VocesLocales.agregar(nombre: "QA Papelera \(UUID().uuidString.prefix(6))",
                                                 cmd: "echo {texto} {salida}")
            let movida = VocesLocales.borrar(temporal.id)
            let entrada = VocesLocales.papelera().first { $0.voz.id == temporal.id }
            let restaurada = entrada.flatMap { VocesLocales.restaurar($0.id) }
            let ok = movida && entrada != nil && restaurada?.id == temporal.id
            if let original {
                try? original.write(to: biblioteca, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                        ofItemAtPath: biblioteca.path)
            }
            if let entrada {
                try? FileManager.default.removeItem(at: Config.dir
                    .appendingPathComponent("papelera-voces/\(entrada.id)"))
            }
            print("VOZSAFETYTEST papelera=\(movida) restaurada=\(restaurada?.id ?? "nil")")
            exit(ok ? 0 : 3)
        }
        if env["BTODICTA_VOZPERSONATEST"] == "1" {
            let fm = FileManager.default
            let biblioteca = Config.dir.appendingPathComponent("voces_locales.json")
            let original = try? Data(contentsOf: biblioteca)
            let temporal = fm.temporaryDirectory
                .appendingPathComponent("bd-persona-skill-\(UUID().uuidString)")
            try? fm.createDirectory(at: temporal, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temporal) }
            try? Data([0x42, 0x44]).write(to: temporal.appendingPathComponent("modelo-slim.pth"))
            try? "{}".write(to: temporal.appendingPathComponent("config.json"),
                              atomically: true, encoding: .utf8)
            try? "{}".write(to: temporal.appendingPathComponent("vocab.json"),
                              atomically: true, encoding: .utf8)
            try? Data("RIFF-qa".utf8).write(to: temporal.appendingPathComponent("referencia.wav"))
            let estilo = "# Persona QA\nHabla con cariño y termina diciendo chao chao."
            try? estilo.write(to: temporal.appendingPathComponent("persona_SKILL.md"),
                               atomically: true, encoding: .utf8)

            var importada: VozLocal?
            switch VocesLocales.importarPaquete(desde: temporal) {
            case .ok(let voz), .faltaMuestras(let voz): importada = voz
            case .faltaModelo: break
            }
            let voz = importada.flatMap { nueva in
                VocesLocales.todas().first { $0.id == nueva.id }
            }
            let skill = voz.map { URL(fileURLWithPath: $0.paquete)
                .appendingPathComponent("persona_SKILL.md") }
            let permisos = skill.flatMap { try? fm.attributesOfItem(atPath: $0.path)[.posixPermissions] as? NSNumber }
            let ok = voz?.persona.contains("chao chao") == true
                && skill.map { fm.fileExists(atPath: $0.path) } == true
                && permisos?.intValue == 0o600

            if let voz { try? fm.removeItem(at: URL(fileURLWithPath: voz.paquete)) }
            if let original {
                try? original.write(to: biblioteca, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: biblioteca.path)
            } else { try? fm.removeItem(at: biblioteca) }
            print("VOZPERSONATEST importada=\(voz != nil) persona=\(voz?.persona.contains("chao chao") == true) skill0600=\(permisos?.intValue == 0o600)")
            exit(ok ? 0 : 4)
        }
        if let texto = env["BTODICTA_MAXIMATEST"], !texto.isEmpty {
            guard let voz = VocesLocales.activa(), voz.maximaInterna,
                  VozMaximaEngine.estado() == .listo else {
                print("MAXIMATEST no-listo"); exit(2)
            }
            var terminado = false; var generado: URL?
            VozMaximaEngine.decir(voz: voz, texto: texto) { url in
                generado = url; terminado = true
            }
            let limite = Date().addingTimeInterval(600)
            while !terminado, Date() < limite {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            guard let generado, FileManager.default.fileExists(atPath: generado.path) else {
                print("MAXIMATEST FALLA sin-audio"); exit(3)
            }
            if let salida = env["BTODICTA_MAXIMA_OUT"], !salida.isEmpty {
                let dst = URL(fileURLWithPath: salida)
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: generado, to: dst)
            }
            let bytes = (try? generado.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("MAXIMATEST OK id=\(voz.id) bytes=\(bytes) cmdLegacy=\(!voz.cmd.isEmpty)")
            exit(bytes > 44 ? 0 : 4)
        }
        if let variante = env["BTODICTA_VOZVARIANTTEST"], !variante.isEmpty {
            guard let voz = VocesLocales.activa() else {
                print("VOZVARIANTTEST sin voz activa"); exit(2)
            }
            VocesLocales.fijarVariante(voz.id, variante)
            let final = VocesLocales.todas().first { $0.id == voz.id }
            print("VOZVARIANTTEST id=\(voz.id) pedida=\(variante) activa=\(final?.variante ?? "nil")")
            exit(final?.variante == variante ? 0 : 3)
        }
        guard let pkg = env["BTODICTA_VOZRECOVERTEST"], !pkg.isEmpty else { return }

        let importada: VozLocal
        switch VocesLocales.importarPaquete(desde: URL(fileURLWithPath: pkg)) {
        case .ok(let v), .faltaMuestras(let v): importada = v
        case .faltaModelo:
            print("VOZRECOVERTEST faltaModelo"); exit(2)
        }
        if let onnx = env["BTODICTA_VOZRECOVER_ONNX"], !onnx.isEmpty {
            guard VocesLocales.vincularPiper(desde: URL(fileURLWithPath: onnx),
                                             a: importada.id, activar: false) != nil else {
                print("VOZRECOVERTEST piper falló"); exit(3)
            }
        }
        if let ref = env["BTODICTA_VOZRECOVER_MLXREF"], !ref.isEmpty,
           let texto = env["BTODICTA_VOZRECOVER_MLXTEXT"], !texto.isEmpty {
            let modelo = env["BTODICTA_VOZRECOVER_MLXMODEL"] ?? MlxVozEngine.modeloDefault
            guard VocesLocales.vincularMlx(referencia: URL(fileURLWithPath: ref),
                                           transcripcion: texto, modelo: modelo,
                                           a: importada.id, activar: false) != nil else {
                print("VOZRECOVERTEST mlx falló"); exit(4)
            }
        }
        if let cmd = env["BTODICTA_VOZRECOVER_CMD"], !cmd.isEmpty {
            guard VocesLocales.vincularMaxima(cmd: cmd, a: importada.id) != nil else {
                print("VOZRECOVERTEST máxima falló"); exit(5)
            }
        }
        VocesLocales.fijarActiva(importada.id)
        Config.set("tts_proveedor", to: "xtts_local")
        Config.set("tts_local_variantes_failover", to: true)
        let final = VocesLocales.todas().first { $0.id == importada.id }
        let ok = final?.tieneMaxima == true && !((final?.paquete ?? "").isEmpty)
            && final?.tieneMlx == true && !((final?.onnx ?? "").isEmpty)
            && final?.variante == "maxima"
        print("VOZRECOVERTEST id=\(importada.id) máxima=\(final?.tieneMaxima == true) xtts=\(!(final?.paquete ?? "").isEmpty) mlx=\(final?.tieneMlx == true) onnx=\(!(final?.onnx ?? "").isEmpty) activa=\(final?.variante ?? "nil")")
        exit(ok ? 0 : 6)
    }
}
