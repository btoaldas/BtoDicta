import AppKit
import ApplicationServices
import Foundation

struct BorradorCorreoPreparado {
    let destinatario: String
    let asunto: String
    let cuerpo: String
}

struct ResultadoBorradorOutlook {
    let ok: Bool
    let verificado: Bool
    let destino: String
    let mensaje: String
}

/// Construye borradores; nunca pulsa “Enviar”. Las URL se forman con
/// URLComponents para que destinatario, asunto y cuerpo no se mezclen.
enum BorradoresCorreo {
    private static let lineaAsunto = try! NSRegularExpression(
        pattern: #"^\s*(?:ASUNTO|SUBJECT)\s*:\s*(.+?)\s*(?:\r?\n|$)"#,
        options: [.caseInsensitive])

    static func preparar(texto: String, destinatario: String?, asuntoSugerido: String?)
        -> BorradorCorreoPreparado {
        let original = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = original as NSString
        var cuerpo = original
        var asuntoIA: String?
        if let m = lineaAsunto.firstMatch(in: original,
                                          range: NSRange(location: 0, length: ns.length)),
           m.numberOfRanges > 1 {
            asuntoIA = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cuerpo = ns.substring(from: NSMaxRange(m.range))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sugerido = asuntoSugerido?.trimmingCharacters(in: .whitespacesAndNewlines)
        let asunto = limitarAsunto((sugerido?.isEmpty == false ? sugerido : nil)
                                   ?? asuntoIA ?? sugerirAsunto(cuerpo))
        return BorradorCorreoPreparado(
            destinatario: destinatario?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            asunto: asunto,
            cuerpo: cuerpo)
    }

    static func sugerirAsunto(_ texto: String) -> String {
        let lineas = texto.split(whereSeparator: { $0.isNewline }).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let saludos = ["estimado", "estimada", "estimados", "estimadas", "hola", "buenos dias", "buenas tardes"]
        let candidata = lineas.first { linea in
            let n = PerfilAgente.normalizar(linea)
            return !n.isEmpty && !saludos.contains(where: { n == $0 || n.hasPrefix($0 + " ") })
        } ?? texto
        return limitarAsunto(candidata.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t\r\n,.;:!?¡¿—-\"“”«»")))
    }

    private static func limitarAsunto(_ asunto: String) -> String {
        let limpio = asunto.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard limpio.count > 96 else { return limpio }
        let corte = limpio.index(limpio.startIndex, offsetBy: 96)
        let prefijo = String(limpio[..<corte])
        if let espacio = prefijo.lastIndex(of: " ") { return String(prefijo[..<espacio]) + "…" }
        return prefijo + "…"
    }

    static func urlGmail(_ b: BorradorCorreoPreparado) -> URL? {
        var c = URLComponents(string: "https://mail.google.com/mail/")
        c?.queryItems = [
            URLQueryItem(name: "view", value: "cm"), URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "to", value: b.destinatario),
            URLQueryItem(name: "su", value: b.asunto),
            URLQueryItem(name: "body", value: b.cuerpo),
        ]
        return c?.url
    }

    static func urlMail(_ b: BorradorCorreoPreparado) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"; c.path = b.destinatario
        c.queryItems = [URLQueryItem(name: "subject", value: b.asunto),
                        URLQueryItem(name: "body", value: b.cuerpo)]
        return c.url
    }

    static func urlOutlookWeb(_ b: BorradorCorreoPreparado) -> URL? {
        var c = URLComponents(string: "https://outlook.office.com/mail/deeplink/compose")
        c?.queryItems = [URLQueryItem(name: "to", value: b.destinatario),
                         URLQueryItem(name: "subject", value: b.asunto),
                         URLQueryItem(name: "body", value: b.cuerpo)]
        return c?.url
    }

    /// Outlook para Mac registra `ms-outlook://`, pero la versión nueva puede
    /// limitarse a activar la aplicación sin crear el mensaje. Microsoft sí
    /// soporta los enlaces `mailto:`. Los entregamos EXPLÍCITAMENTE a Outlook y
    /// comprobamos por Accesibilidad que apareció una ventana de composición.
    static func abrirOutlook(_ b: BorradorCorreoPreparado,
                             completion: @escaping (ResultadoBorradorOutlook) -> Void) {
        guard let mailto = urlMail(b) else {
            completion(.init(ok: false, verificado: false, destino: "ninguno",
                             mensaje: "No pude construir el borrador de Outlook."))
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.microsoft.Outlook") else {
            abrirOutlookWeb(b, completion: completion)
            return
        }

        let anteriores = titulosVentanasOutlook()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.promptsUserIfNeeded = true
        NSWorkspace.shared.open([mailto], withApplicationAt: appURL,
                                configuration: config) { _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    abrirOutlookWeb(b, completion: completion)
                    return
                }
                guard AXIsProcessTrusted() else {
                    completion(.init(ok: true, verificado: false,
                        destino: "outlook_app_sin_verificar",
                        mensaje: "Pedí a Outlook crear el borrador; no pude comprobar la ventana porque falta el permiso de Accesibilidad."))
                    return
                }
                esperarVentanaOutlook(asunto: b.asunto, anteriores: anteriores,
                                      intento: 0) { verificado in
                    if verificado {
                        completion(.init(ok: true, verificado: true,
                            destino: "outlook_app",
                            mensaje: "Abrí un borrador real en Outlook; revísalo antes de enviarlo."))
                    } else {
                        abrirOutlookWeb(b, completion: completion)
                    }
                }
            }
        }
    }

    private static func abrirOutlookWeb(_ b: BorradorCorreoPreparado,
                                        completion: @escaping (ResultadoBorradorOutlook) -> Void) {
        let abierto = urlOutlookWeb(b).map { NSWorkspace.shared.open($0) } ?? false
        // `open` únicamente confirma que el navegador aceptó la URL; no que la
        // sesión de Outlook web terminó de cargar el formulario.
        completion(.init(ok: abierto, verificado: false,
                         destino: abierto ? "outlook_web" : "ninguno",
                         mensaje: abierto
                            ? "Outlook de escritorio no confirmó el borrador; abrí un borrador en Outlook web."
                            : "No pude crear el borrador ni en Outlook ni en Outlook web."))
    }

    private static func esperarVentanaOutlook(asunto: String, anteriores: Set<String>?,
                                               intento: Int,
                                               completion: @escaping (Bool) -> Void) {
        let actuales = titulosVentanasOutlook() ?? []
        let nuevas = anteriores.map { actuales.subtracting($0) } ?? actuales
        let asuntoN = PerfilAgente.normalizar(asunto)
        // Una ventana antigua con el mismo asunto no demuestra que esta orden
        // haya creado un correo nuevo.
        let porAsunto = !asuntoN.isEmpty && nuevas.contains {
            PerfilAgente.normalizar($0).contains(asuntoN)
        }
        let ventanaNueva = !nuevas.isEmpty
        if porAsunto || ventanaNueva { completion(true); return }
        guard intento < 12 else { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            esperarVentanaOutlook(asunto: asunto, anteriores: anteriores,
                                  intento: intento + 1, completion: completion)
        }
    }

    private static func titulosVentanasOutlook() -> Set<String>? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.microsoft.Outlook").first else { return nil }
        let elemento = AXUIElementCreateApplication(app.processIdentifier)
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXWindowsAttribute as CFString,
                                            &valor) == .success,
              let ventanas = valor as? [AXUIElement] else { return [] }
        return Set(ventanas.compactMap { ventana in
            var titulo: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ventana, kAXTitleAttribute as CFString,
                                                &titulo) == .success else { return nil }
            return titulo as? String
        })
    }
}
