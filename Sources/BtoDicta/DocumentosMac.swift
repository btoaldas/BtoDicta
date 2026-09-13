import AppKit
import Foundation

/// Creación verificable de documentos en aplicaciones que exponen una API
/// nativa. El camino genérico por teclado sigue disponible para las demás apps,
/// pero Word no debe anunciar éxito solo porque la aplicación se abrió.
enum DocumentosMac {
    enum AlineacionWord: String {
        case izquierda, derecha, centro, justificada

        var appleScript: String {
            // Word para Mac acepta aquí los valores VBA canónicos 0...3. Su
            // SDEF 16.x publica constantes desplazadas ("right" termina en
            // justify), por eso usamos los enteros que Word devuelve visualmente:
            // 0 izquierda, 1 centro, 2 derecha, 3 justificada.
            switch self {
            case .izquierda: return "0"
            case .derecha: return "2"
            case .centro: return "1"
            case .justificada: return "3"
            }
        }
    }

    struct EstiloParrafoWord: Equatable {
        let indice: Int
        let rol: String
        let negrita: Bool
        let tamano: Int
        let alineacion: AlineacionWord
        let espacioAntes: Int
        let espacioDespues: Int
    }

    struct PlanWord {
        let texto: String
        let esEstructurado: Bool
        let estilos: [EstiloParrafoWord]
    }

    private static func literalAppleScript(_ texto: String) -> String {
        let limpio = texto.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(limpio)\""
    }

    private static func normalizar(_ texto: String) -> String {
        texto.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quita el nombre/puente hablado de una aplicación sin reconstruir el texto
    /// palabra por palabra. Reconstruirlo destruía todos los saltos que la IA ya
    /// había generado para oficios, correos y documentos profesionales.
    static func contenidoParaAplicacion(_ texto: String, consumidas: Int) -> String {
        var restante = texto
        if consumidas > 0 {
            let ns = restante as NSString
            let re = try! NSRegularExpression(pattern: #"\S+"#)
            let palabras = re.matches(in: restante,
                range: NSRange(location: 0, length: ns.length))
            if palabras.count >= consumidas {
                restante = ns.substring(from: NSMaxRange(palabras[consumidas - 1].range))
            }
        }
        restante = restante.trimmingCharacters(in: .whitespacesAndNewlines)
        restante = restante.replacingOccurrences(
            of: #"^[,.:;—-]+\s*"#, with: "",
            options: [.regularExpression])
        restante = restante.replacingOccurrences(
            of: #"^(?:(?:y\s+)?(?:escribe|pega|pon|coloca)(?:\s+(?:lo\s+siguiente|el\s+texto))?|lo\s+siguiente|el\s+texto)\s*[,.:;—-]?\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return restante.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convierte la estructura textual en un plan visual determinista. La IA
    /// redacta; BtoDicta decide la presentación para no depender de que cada
    /// proveedor conozca el diccionario de estilos de Microsoft Word.
    static func planWord(_ texto: String) -> PlanWord {
        let limpio = normalizar(texto)
        let lineas = limpio.components(separatedBy: "\n")
        let noVacias = lineas.indices.filter {
            !lineas[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let primero = noVacias.first else {
            return .init(texto: limpio, esEstructurado: false, estilos: [])
        }
        let inicio = PerfilAgente.normalizar(lineas[primero])
        let estructurado = inicio.hasPrefix("oficio ") || inicio == "oficio"
            || inicio.hasPrefix("memorando ") || inicio == "memorando"
            || inicio.hasPrefix("circular ") || inicio == "circular"
        guard estructurado else {
            return .init(texto: limpio, esEstructurado: false, estilos: [])
        }

        let segundo = noVacias.dropFirst().first
        var estilos: [EstiloParrafoWord] = []
        var vioAsunto = false
        var enCuerpo = false
        var despuesDeFirma = false
        for i in noVacias {
            let linea = lineas[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let n = PerfilAgente.normalizar(linea)
            let estilo: EstiloParrafoWord
            if i == primero {
                estilo = .init(indice: i + 1, rol: "encabezado", negrita: true,
                               tamano: 12, alineacion: .derecha,
                               espacioAntes: 0, espacioDespues: 12)
            } else if i == segundo,
                      linea.contains(",") && (n.contains(" de ") || linea.contains("[")) {
                estilo = .init(indice: i + 1, rol: "fecha", negrita: false,
                               tamano: 11, alineacion: .derecha,
                               espacioAntes: 0, espacioDespues: 12)
            } else if n.hasPrefix("asunto ") || n == "asunto" {
                vioAsunto = true
                estilo = .init(indice: i + 1, rol: "asunto", negrita: true,
                               tamano: 11, alineacion: .izquierda,
                               espacioAntes: 10, espacioDespues: 10)
            } else if n.hasPrefix("estimado ") || n.hasPrefix("estimada ")
                        || n.hasPrefix("de mi consideracion") {
                enCuerpo = true
                estilo = .init(indice: i + 1, rol: "saludo", negrita: false,
                               tamano: 11, alineacion: .izquierda,
                               espacioAntes: 0, espacioDespues: 8)
            } else if n.hasPrefix("atentamente") || n.hasPrefix("cordialmente") {
                despuesDeFirma = true; enCuerpo = false
                estilo = .init(indice: i + 1, rol: "cierre", negrita: true,
                               tamano: 11, alineacion: .izquierda,
                               espacioAntes: 14, espacioDespues: 10)
            } else if despuesDeFirma {
                estilo = .init(indice: i + 1, rol: "firma", negrita: false,
                               tamano: 11, alineacion: .centro,
                               espacioAntes: 0, espacioDespues: 2)
            } else if enCuerpo || (vioAsunto && linea.count >= 60) {
                estilo = .init(indice: i + 1, rol: "cuerpo", negrita: false,
                               tamano: 11, alineacion: .justificada,
                               espacioAntes: 0, espacioDespues: 8)
            } else {
                estilo = .init(indice: i + 1, rol: "destinatario", negrita: false,
                               tamano: 11, alineacion: .izquierda,
                               espacioAntes: 0, espacioDespues: 2)
            }
            estilos.append(estilo)
        }
        return .init(texto: limpio, esEstructurado: true, estilos: estilos)
    }

    private static func fuenteWord(_ plan: PlanWord, cerrarDespues: Bool) -> String {
        let cerrar = cerrarDespues ? "close documentoBtoDicta saving no" : ""
        let formato: String
        if plan.esEstructurado {
            let porParrafo = plan.estilos.map { e in
                """
                set parrafoBtoDicta to paragraph \(e.indice) of rangoBtoDicta
                set bold of font object of text object of parrafoBtoDicta to \(e.negrita ? "true" : "false")
                set font size of font object of text object of parrafoBtoDicta to \(e.tamano)
                set alignment of parrafoBtoDicta to \(e.alineacion.appleScript)
                set space before of parrafoBtoDicta to \(e.espacioAntes)
                set space after of parrafoBtoDicta to \(e.espacioDespues)
                """
            }.joined(separator: "\n")
            formato = """
            set rangoBtoDicta to text object of documentoBtoDicta
            set name of font object of rangoBtoDicta to "Arial"
            set font size of font object of rangoBtoDicta to 11
            set line spacing rule of paragraph format of rangoBtoDicta to line space1 pt5
            set top margin of page setup of rangoBtoDicta to 71
            set bottom margin of page setup of rangoBtoDicta to 71
            set left margin of page setup of rangoBtoDicta to 71
            set right margin of page setup of rangoBtoDicta to 71
            \(porParrafo)
            """
        } else {
            formato = ""
        }
        return """
        tell application id "com.microsoft.Word"
            activate
            set documentoBtoDicta to create new document
            set content of text object of documentoBtoDicta to \(literalAppleScript(plan.texto))
            \(formato)
            set verificacionBtoDicta to content of text object of documentoBtoDicta
            \(cerrar)
            return verificacionBtoDicta
        end tell
        """
    }

    /// Crea el documento mediante el diccionario AppleScript oficial de Word,
    /// coloca el contenido y lo vuelve a leer. Solo entonces devuelve `ok`.
    private static func crearWordSincrono(_ texto: String,
                                           cerrarDespues: Bool = false)
        -> ResultadoHerramientaApple {
        let plan = planWord(texto)
        let esperado = plan.texto
        guard !esperado.isEmpty else {
            return .init(ok: false, mensaje: "No hay contenido para crear en Word.")
        }
        let fuente = fuenteWord(plan, cerrarDespues: cerrarDespues)
        var error: NSDictionary?
        let devuelto = NSAppleScript(source: fuente)?.executeAndReturnError(&error).stringValue
        guard error == nil, let devuelto else {
            let detalle = (error?[NSAppleScript.errorMessage] as? String)
                ?? "Word rechazó la automatización."
            Log.write("⚠️ Word: no se pudo crear el documento: \(detalle)")
            return .init(ok: false,
                mensaje: "Abrí Word, pero no pude crear el documento. Autoriza BtoDicta en Privacidad y seguridad → Automatización → Microsoft Word y vuelve a intentarlo.")
        }
        guard normalizar(devuelto) == esperado else {
            Log.write("⚠️ Word: abrió documento, pero la verificación del contenido no coincidió")
            return .init(ok: false,
                mensaje: "Word abrió un documento, pero no pude comprobar que recibió el texto completo. Lo dejé en el portapapeles para que puedas pegarlo.")
        }
        if plan.esEstructurado {
            Log.write("  Word: formato profesional aplicado a \(plan.estilos.count) párrafos")
        }
        return .init(ok: true,
            mensaje: plan.esEstructurado
                ? "Creé el documento en Word con estructura, espaciado y estilos verificados."
                : "Creé un documento nuevo en Word y comprobé que contiene el texto completo.")
    }

    static func crearEnWord(_ texto: String,
                            completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { crearEnWord(texto, completion: completion) }
            return
        }
        guard NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.microsoft.Word") != nil else {
            completion(.init(ok: false, mensaje: "Microsoft Word no está instalado."))
            return
        }
        // Conserva un respaldo incluso si Word o el permiso de Automatización fallan.
        copyText(planWord(texto).texto)
        DispatchQueue.global(qos: .userInitiated).async {
            let resultado = crearWordSincrono(texto)
            DispatchQueue.main.async { completion(resultado) }
        }
    }

    /// Hook de integración real. Crea, verifica y cierra un documento temporal;
    /// nunca guarda archivos. Se ejecuta antes de NSApplication.
    static func ejecutarPruebaSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_WORDTEST"] == "1" else { return }
        let muestra = """
        OFICIO N° [___________]
        Quito, 18 de julio de 2026

        Señor [___________]
        [___________]

        Asunto: Solicitud de apoyo

        Estimado señor [___________],

        Solicito su apoyo para los juegos internos de la institución.

        Atentamente,

        [___________]
        """
        let resultado = crearWordSincrono(muestra, cerrarDespues: true)
        print("WORDTEST \(resultado.ok ? "OK" : "FALLA") \(resultado.mensaje)")
        exit(resultado.ok ? 0 : 3)
    }
}
