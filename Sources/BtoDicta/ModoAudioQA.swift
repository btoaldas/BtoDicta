import Foundation

/// E2E de voz sin ejecutar destinos: ElevenLabs convierte las frases a audio,
/// Apple Speech las vuelve a texto y recién entonces pasan por el resolvedor
/// determinista. No imprime ni copia la API key.
enum ModoAudioQA {
    private struct Caso {
        let frase: String
        let transforms: [String]
        let acciones: [String]
        let negativo: Bool
        let contiene: String?
        let idioma: String?
        let destinatario: String?
        init(frase: String, transforms: [String], acciones: [String], negativo: Bool,
             contiene: String? = nil, idioma: String? = nil, destinatario: String? = nil) {
            self.frase = frase; self.transforms = transforms; self.acciones = acciones
            self.negativo = negativo; self.contiene = contiene
            self.idioma = idioma; self.destinatario = destinatario
        }
    }

    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_MODOAUDIOQA"] == "1" else { return }
        let matriz = [
            Caso(frase: "Por favor, ayúdame a traducir lo siguiente: Necesito encontrar la forma de hacer algo bueno.",
                 transforms: ["traducir"], acciones: [], negativo: false),
            Caso(frase: "Por favor, traduce esto: La vida es bella. Y después envíalo por correo electrónico.",
                 transforms: ["traducir"], acciones: ["correo"], negativo: false,
                 contiene: "la vida es bella"),
            Caso(frase: "Resume, traduce al inglés y envía por WhatsApp a Andrés: mañana nos reunimos a las ocho.",
                 transforms: ["resumir", "traducir"], acciones: ["whatsapp"], negativo: false,
                 contiene: "mañana nos reunimos", idioma: "inglés", destinatario: "Andrés"),
            Caso(frase: "Modo buscar Wikipedia, Islas Galápagos.",
                 transforms: [], acciones: ["buscar"], negativo: false),
            Caso(frase: "Anótame una tarea: revisar el informe y configurar el router.",
                 transforms: ["tarea"], acciones: [], negativo: false, contiene: "revisar"),
            Caso(frase: "Guárdame una nota: la reunión será el viernes a las diez.",
                 transforms: ["nota"], acciones: [], negativo: false, contiene: "la reunión"),
            Caso(frase: "Formaliza y envía por Outlook lo siguiente: solicito permiso para el viernes.",
                 transforms: ["oficio"], acciones: ["outlook"], negativo: false, contiene: "solicito permiso"),
            Caso(frase: "Por favor, redacta un correo: necesitamos revisar el contrato.",
                 transforms: ["correo"], acciones: [], negativo: false, contiene: "necesitamos revisar"),
            Caso(frase: "Oye, Bto, crea una redacción de un verso sin esfuerzo, algo simpático, y después mándaselo a Andrés por WhatsApp.",
                 transforms: ["generar"], acciones: ["whatsapp"], negativo: false,
                 contiene: "redacción de un verso", destinatario: "Andrés"),
            Caso(frase: "Abre Gmail y escribe un correo para prueba arroba gmail punto com: necesitamos preparar el programa del evento.",
                 transforms: ["correo"], acciones: ["gmail"], negativo: false,
                 contiene: "necesitamos preparar", destinatario: "prueba@gmail.com"),
            Caso(frase: "Por favor, pregúntale al agente: qué tareas tengo para hoy.",
                 transforms: ["agente"], acciones: [], negativo: false, contiene: "qué tareas tengo"),
            Caso(frase: "Me gustaría que traduzcas al portugués lo siguiente: nos vemos mañana.",
                 transforms: ["traducir"], acciones: [], negativo: false,
                 contiene: "nos vemos mañana", idioma: "portugués"),
            Caso(frase: "Quiero que mandes por WhatsApp a Andrés: llego a las ocho.",
                 transforms: [], acciones: ["whatsapp"], negativo: false,
                 contiene: "llego a las ocho", destinatario: "Andrés"),
            Caso(frase: "Resume, traduce al quichua y envía por correo y WhatsApp a Andrés: mañana habrá reunión.",
                 transforms: ["resumir", "traducir"], acciones: ["correo", "whatsapp"],
                 negativo: false, contiene: "mañana habrá reunión",
                 idioma: "quichua", destinatario: "Andrés"),
            Caso(frase: "Necesito revisar el correo que llegó ayer.",
                 transforms: [], acciones: [], negativo: true),
            Caso(frase: "La tarea del agente es enviar un correo cuando termine.",
                 transforms: [], acciones: [], negativo: true),
            Caso(frase: "Ayer me preguntaste si traducíamos el documento y lo enviábamos por correo.",
                 transforms: [], acciones: [], negativo: true),
        ]
        let solicitado = Int(ProcessInfo.processInfo.environment["BTODICTA_MODOAUDIOCASE"] ?? "")
        let casos: [Caso]
        if let solicitado, solicitado >= 1, solicitado <= matriz.count {
            casos = [matriz[solicitado - 1]]
            print("MODOAUDIOQA caso aislado \(solicitado)/\(matriz.count)")
        } else { casos = matriz }
        guard Config.apiKey() != nil else {
            print("MODOAUDIOQA OMITIDO: no hay clave ElevenLabs"); exit(4)
        }
        guard AppleSpeechSTT.disponible else {
            print("MODOAUDIOQA OMITIDO: Apple Speech no disponible"); exit(4)
        }
        let catalogo = ModoCatalogo(modos: ModosStore.todos())
        var indice = 0, fallos = 0

        func clasificar(_ texto: String) -> (t: [String], a: [String], contenido: String,
                                             idioma: String?, destinatario: String?)? {
            if let c = ModosStore.detectarCadena(texto) {
                return (c.transforms.map(\.id),
                        c.acciones.map { $0.modo.base == "buscar" ? "buscar" : $0.modo.accion },
                        c.contenido,
                        c.transforms.first(where: { $0.base == "traducir" })?.idiomaDestino,
                        c.acciones.compactMap(\.destinatario).first)
            }
            if let m = ModoResolver.detectarExacto(texto, catalogo: catalogo)
                ?? ModoResolver.detectarDifuso(texto, catalogo: catalogo) {
                if m.modo.base == "accion" || m.modo.base == "buscar" {
                    return ([], [m.modo.base == "buscar" ? "buscar" : m.modo.accion],
                            m.textoLimpio, nil, nil)
                }
                return ([m.modo.id], [], m.textoLimpio,
                        m.modo.base == "traducir" ? m.modo.idiomaDestino : nil, nil)
            }
            if let p = ModoPlanificador.detectarNatural(texto, catalogo: catalogo) {
                return (p.cadena.transforms.map(\.id),
                        p.cadena.acciones.map { $0.modo.base == "buscar" ? "buscar" : $0.modo.accion },
                        p.cadena.contenido,
                        p.cadena.transforms.first(where: { $0.base == "traducir" })?.idiomaDestino,
                        p.cadena.acciones.compactMap(\.destinatario).first)
            }
            return nil
        }

        func siguiente() {
            guard indice < casos.count else {
                print("MODOAUDIOQA \(fallos == 0 ? "TODO OK" : "✗ \(fallos) FALLOS")")
                fflush(stdout); exit(fallos == 0 ? 0 : 3)
            }
            let numero = indice
            let caso = casos[numero]
            indice += 1
            ElevenLabsTTS.decir(caso.frase) { mp3 in
                guard let mp3 else {
                    fallos += 1; print("MODOAUDIOQA ✗ ElevenLabs sin audio [\(numero + 1)]")
                    siguiente(); return
                }
                let base = FileManager.default.temporaryDirectory
                    .appendingPathComponent("btodicta-modoqa-\(ProcessInfo.processInfo.processIdentifier)-\(numero)")
                let mp3URL = base.appendingPathExtension("mp3")
                let wavURL = base.appendingPathExtension("wav")
                defer { try? FileManager.default.removeItem(at: mp3URL) }
                do { try mp3.write(to: mp3URL) }
                catch {
                    fallos += 1; print("MODOAUDIOQA ✗ no pude guardar audio [\(numero + 1)]")
                    siguiente(); return
                }
                let ff = Process()
                ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
                ff.arguments = ["-y", "-loglevel", "error", "-i", mp3URL.path,
                                "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wavURL.path]
                ff.standardError = Pipe(); ff.standardOutput = Pipe()
                do { try ff.run(); ff.waitUntilExit() }
                catch {
                    fallos += 1; print("MODOAUDIOQA ✗ ffmpeg [\(numero + 1)]: \(error.localizedDescription)")
                    siguiente(); return
                }
                guard ff.terminationStatus == 0, let wav = try? Data(contentsOf: wavURL) else {
                    fallos += 1; print("MODOAUDIOQA ✗ conversión [\(numero + 1)]")
                    siguiente(); return
                }
                try? FileManager.default.removeItem(at: wavURL)
                AppleSpeechSTT.run(wav: wav) { resultado in
                    switch resultado {
                    case .failure(let error):
                        fallos += 1
                        print("MODOAUDIOQA ✗ Apple STT [\(numero + 1)]: \(error.localizedDescription)")
                    case .success(let transcrito):
                        let r = clasificar(transcrito)
                        let destinatarioOK: Bool = {
                            guard let esperado = caso.destinatario else { return true }
                            guard let oido = r?.destinatario else { return false }
                            if oido.caseInsensitiveCompare(esperado) == .orderedSame { return true }
                            // Una dirección nunca se corrige por semejanza: una
                            // letra cambia el destinatario. El modal la muestra
                            // para confirmar, pero el QA de correo exige exactitud.
                            if esperado.contains("@") || oido.contains("@") { return false }
                            let muestra = [ContactoWA(nombre: esperado, numero: "593000000000")]
                            return ContactosWA.coincidencias(oido, en: muestra).contactos.first?.nombre == esperado
                        }()
                        let ok = caso.negativo
                            ? r == nil
                            : (r?.t == caso.transforms && r?.a == caso.acciones
                               && (caso.contiene == nil
                                   || r?.contenido.localizedCaseInsensitiveContains(caso.contiene!) == true)
                               && (caso.idioma == nil || r?.idioma == caso.idioma)
                               && destinatarioOK)
                        if !ok { fallos += 1 }
                        print("MODOAUDIOQA \(ok ? "OK" : "✗") [\(numero + 1)] voz=\"\(transcrito)\" → T=\(r?.t ?? []) A=\(r?.a ?? []) idi=\(r?.idioma ?? "-") dest=\(r?.destinatario ?? "-") C=\"\(r?.contenido ?? "")\"")
                    }
                    siguiente()
                }
            }
        }
        siguiente()
        RunLoop.main.run()
    }
}
