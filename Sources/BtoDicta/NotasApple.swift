import AppKit
import CoreServices
import Foundation

/// Creación verificable en Notas de Apple.
///
/// Notes no ofrece un framework Swift público para crear notas, pero sí publica
/// un diccionario de automatización oficial. Esta ruta usa ese diccionario y
/// vuelve a leer el `plaintext` de la nota antes de anunciar éxito. El camino
/// anterior (abrir → esperar → ⌘N → ⌘V) se conserva únicamente como respaldo
/// manual: jamás declara que creó una nota si solo abrió la aplicación.
enum NotasApple {
    private static let cola = DispatchQueue(label: "ec.bto.btodicta.notas-apple",
                                            qos: .userInitiated)
    private static let separador = "\u{001e}"

    struct Plan: Equatable {
        let original: String
        let titulo: String
        let cuerpo: String
        let cuerpoHTML: String
    }

    struct Preferencias: Equatable {
        var carpeta: String
        var crearCarpeta: Bool
        var mostrar: Bool

        static var actuales: Preferencias {
            .init(carpeta: Config.notasAppleCarpeta(),
                  crearCarpeta: Config.notasAppleCrearCarpeta(),
                  mostrar: Config.notasAppleMostrarCreada())
        }
    }

    private static func normalizarSaltos(_ texto: String) -> String {
        texto.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: separador, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// En macOS 26, `tell application id "com.apple.Notes"` puede devolver
    /// -1728 aunque la app exista. Resolver la URL con LaunchServices y usar su
    /// ruta evita depender del nombre localizado y de ese fallo de AppleScript.
    static func rutaAplicacion() -> String? {
        if let ruta = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Notes")?.path {
            return ruta
        }
        // Los hooks de QA se ejecutan antes de que NSApplication termine de
        // registrarse y LaunchServices puede devolver nil en ese instante.
        // Notes es parte del sistema; estas son sus dos ubicaciones oficiales
        // en macOS moderno y en versiones antiguas.
        for ruta in ["/System/Applications/Notes.app", "/Applications/Notes.app"]
        where FileManager.default.fileExists(atPath: ruta) {
            return ruta
        }
        return nil
    }

    private static func tituloCorto(_ texto: String, maximo: Int = 72) -> String {
        let unaLinea = texto.replacingOccurrences(of: #"\s+"#, with: " ",
                                                   options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard unaLinea.count > maximo else { return unaLinea }
        let prefijo = String(unaLinea.prefix(maximo + 1))
        if let corte = prefijo.lastIndex(where: { $0.isWhitespace }),
           corte > prefijo.index(prefijo.startIndex, offsetBy: maximo / 2) {
            return String(prefijo[..<corte]).trimmingCharacters(in: .whitespaces)
        }
        return String(unaLinea.prefix(maximo)).trimmingCharacters(in: .whitespaces)
    }

    private static func escaparHTML(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func lineaSemantica(_ linea: String) -> String {
        var t = linea.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashes = t.prefix { $0 == "#" }.count
        if (1...3).contains(hashes), t.dropFirst(hashes).hasPrefix(" ") {
            t = String(t.dropFirst(hashes + 1))
        }
        if t.hasPrefix("> ") { t = String(t.dropFirst(2)) }
        if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
            t = String(t.dropFirst(6))
        } else if t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ") {
            t = String(t.dropFirst(2))
        } else if let rango = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            t.removeSubrange(rango)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mantiene párrafos, títulos, citas, listas y casillas simples en vez de
    /// convertir todo el dictado en una sola línea. Todo se escapa antes de
    /// entrar al HTML de Notes; el usuario nunca puede inyectar AppleScript/HTML.
    static func htmlSeguro(_ texto: String) -> String {
        let lineas = normalizarSaltos(texto).components(separatedBy: "\n")
        var salida: [String] = []
        var lista: String?
        func cerrarLista() {
            if let lista { salida.append("</\(lista)>") }
            lista = nil
        }
        func abrirLista(_ tipo: String) {
            if lista != tipo { cerrarLista(); salida.append("<\(tipo)>"); lista = tipo }
        }
        for linea in lineas {
            let t = linea.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [ ] ") || t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                abrirLista("ul")
                let marcada = t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ")
                let contenido = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                salida.append("<li>\(marcada ? "☑︎" : "☐") \(escaparHTML(contenido))</li>")
            } else if t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ") {
                abrirLista("ul")
                let contenido = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                salida.append("<li>\(escaparHTML(contenido))</li>")
            } else if let rango = t.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                abrirLista("ol")
                var contenido = t; contenido.removeSubrange(rango)
                salida.append("<li>\(escaparHTML(contenido))</li>")
            } else {
                cerrarLista()
                let hashes = t.prefix { $0 == "#" }.count
                if (1...3).contains(hashes), t.dropFirst(hashes).hasPrefix(" ") {
                    let contenido = String(t.dropFirst(hashes + 1))
                    salida.append("<h\(hashes)>\(escaparHTML(contenido))</h\(hashes)>")
                } else if t.hasPrefix("> ") {
                    salida.append("<blockquote>\(escaparHTML(String(t.dropFirst(2))))</blockquote>")
                } else {
                    salida.append(t.isEmpty ? "<div><br></div>" : "<div>\(escaparHTML(t))</div>")
                }
            }
        }
        cerrarLista()
        return salida.isEmpty ? "<div><br></div>" : salida.joined()
    }

    /// La primera línea breve se vuelve el título. También entiende las formas
    /// explícitas «Título: Compras» y «Titulada Compras: ...» sin guardar esas
    /// palabras de control dentro de la nota.
    static func preparar(_ texto: String) -> Plan? {
        let limpio = normalizarSaltos(texto)
        guard !limpio.isEmpty else { return nil }
        var lineas = limpio.components(separatedBy: "\n")
        let indicesNoVacios = lineas.indices.filter {
            !lineas[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let primero = indicesNoVacios.first else { return nil }
        var primera = lineas[primero].trimmingCharacters(in: .whitespacesAndNewlines)
        var tituloExplicito: String?
        let plegada = primera.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                      locale: Locale(identifier: "es_EC")).lowercased()
        if plegada.hasPrefix("titulo:"), let dosPuntos = primera.firstIndex(of: ":") {
            tituloExplicito = String(primera[primera.index(after: dosPuntos)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lineas.remove(at: primero)
            primera = tituloExplicito ?? primera
        } else if plegada.hasPrefix("titulada ") || plegada.hasPrefix("titulado "),
                  let dosPuntos = primera.firstIndex(of: ":") {
            let inicio = primera.index(primera.startIndex, offsetBy: 9)
            tituloExplicito = String(primera[inicio..<dosPuntos])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resto = String(primera[primera.index(after: dosPuntos)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lineas[primero] = resto
            primera = tituloExplicito ?? primera
        }
        guard let tituloBase = tituloExplicito?.isEmpty == false ? tituloExplicito : primera,
              !tituloBase.isEmpty else { return nil }
        let titulo = tituloCorto(tituloBase)
        let cuerpo: String
        let lineasConContenido = lineas.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if tituloExplicito != nil {
            cuerpo = lineas.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lineasConContenido.count == 1, primera.count <= 72 {
            cuerpo = ""
        } else if titulo == primera {
            cuerpo = lineas.dropFirst(primero + 1).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            cuerpo = limpio
        }
        // Sin título explícito, el respaldo conserva byte por byte el dictado
        // normalizado: el título sintético nunca debe duplicarse al copiar.
        let original = tituloExplicito == nil ? limpio
            : ([titulo] + (cuerpo.isEmpty ? [] : [cuerpo])).joined(separator: "\n")
        return Plan(original: original, titulo: titulo, cuerpo: cuerpo,
                    cuerpoHTML: htmlSeguro(cuerpo))
    }

    private static func literalAppleScript(_ texto: String) -> String {
        let seguro = texto.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(seguro)\""
    }

    private static func compacto(_ texto: String) -> String {
        texto.replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Visible para QA: la nota devuelta puede incluir el título antes del cuerpo,
    /// pero debe conservar todo el texto original, en orden y sin truncarlo.
    /// Notes omite los caracteres `-`/`•` de una lista en `plaintext`, aunque la
    /// lista siga visible; por eso comprobamos cada línea semántica en secuencia.
    static func contenidoVerificado(plan: Plan, plaintext: String) -> Bool {
        let recibido = compacto(plaintext)
        let esperadas = normalizarSaltos(plan.original).components(separatedBy: "\n")
            .map { linea -> String in
                compacto(lineaSemantica(linea))
            }
            .filter { !$0.isEmpty }
        guard !recibido.isEmpty, !esperadas.isEmpty else { return false }
        var inicio = recibido.startIndex
        for esperado in esperadas {
            guard let rango = recibido.range(of: esperado,
                                              options: [.literal],
                                              range: inicio..<recibido.endIndex) else {
                return false
            }
            inicio = rango.upperBound
        }
        return true
    }

    private static func fuente(_ plan: Plan, rutaNotas: String,
                               preferencias: Preferencias,
                               eliminarDespues: Bool,
                               mostrar: Bool? = nil) -> String {
        let debeMostrar = mostrar ?? preferencias.mostrar
        let mostrarLinea = debeMostrar ? "show notaBtoDicta" : ""
        let activarLinea = debeMostrar ? "activate" : ""
        let eliminarLinea = eliminarDespues ? "delete notaBtoDicta" : ""
        let configurarCarpeta: String
        if preferencias.carpeta.isEmpty {
            configurarCarpeta = ""
        } else {
            let crear = preferencias.crearCarpeta ? "true" : "false"
            configurarCarpeta = """
            set nombreCarpetaBtoDicta to \(literalAppleScript(preferencias.carpeta))
            set encontroCarpetaBtoDicta to false
            repeat with candidataBtoDicta in every folder of cuentaBtoDicta
                try
                    if (name of candidataBtoDicta as text) is nombreCarpetaBtoDicta then
                        set carpetaBtoDicta to candidataBtoDicta
                        set encontroCarpetaBtoDicta to true
                        exit repeat
                    end if
                end try
            end repeat
            if encontroCarpetaBtoDicta is false then
                if \(crear) then
                    set carpetaBtoDicta to make new folder at cuentaBtoDicta with properties {name:nombreCarpetaBtoDicta}
                else
                    error "BTODICTA_FOLDER_NOT_FOUND" number -2700
                end if
            end if
            """
        }
        return """
        set separadorBtoDicta to character id 30
        tell application \(literalAppleScript(rutaNotas))
            launch
            \(activarLinea)
            set cuentaBtoDicta to default account
            set carpetaBtoDicta to default folder of cuentaBtoDicta
            \(configurarCarpeta)
            set notaBtoDicta to make new note at carpetaBtoDicta with properties {name:\(literalAppleScript(plan.titulo)), body:\(literalAppleScript(plan.cuerpoHTML))}
            set idBtoDicta to id of notaBtoDicta
            set textoBtoDicta to plaintext of notaBtoDicta
            set nombreCarpetaRealBtoDicta to name of carpetaBtoDicta
            \(mostrarLinea)
            \(eliminarLinea)
            return (idBtoDicta as text) & separadorBtoDicta & (nombreCarpetaRealBtoDicta as text) & separadorBtoDicta & textoBtoDicta
        end tell
        """
    }

    private static func crearSincrono(_ plan: Plan, rutaNotas: String,
                                      preferencias: Preferencias,
                                      eliminarDespues: Bool = false,
                                      mostrar: Bool? = nil) -> ResultadoHerramientaApple {
        var error: NSDictionary?
        let salida = NSAppleScript(source: fuente(plan, rutaNotas: rutaNotas,
                                                  preferencias: preferencias,
                                                  eliminarDespues: eliminarDespues,
                                                  mostrar: mostrar))?
            .executeAndReturnError(&error).stringValue
        guard error == nil, let salida else {
            let numero = error?[NSAppleScript.errorNumber] as? Int ?? 0
            let detalle = (error?[NSAppleScript.errorMessage] as? String)
                ?? "Notas rechazó la automatización."
            let detalleLog = detalle.replacingOccurrences(of: #"\s+"#, with: " ",
                                                           options: .regularExpression)
            Log.write("⚠️ Notas de Apple: error \(numero): \(String(detalleLog.prefix(240)))")
            AgenteLog.registrar("nota_apple", [
                "ok": false, "verificada": false, "error": numero,
                "titulo": plan.titulo, "caracteres": plan.original.count,
            ])
            let permiso = numero == -1743
                ? " Autoriza BtoDicta en Ajustes del Sistema → Privacidad y seguridad → Automatización → Notas."
                : ""
            let carpeta = numero == -2700 && detalle.contains("BTODICTA_FOLDER_NOT_FOUND")
                ? " La carpeta configurada no existe y elegiste no crearla."
                : ""
            return .init(ok: false,
                mensaje: "No pude crear la nota automáticamente.\(permiso)\(carpeta) Dejé el texto completo en el portapapeles.",
                evidencia: ["verificada": "false", "error": "\(numero)"])
        }
        let partes = salida.components(separatedBy: separador)
        guard partes.count >= 3 else {
            Log.write("⚠️ Notas de Apple: respuesta sin evidencia estructurada")
            return .init(ok: false,
                mensaje: "Notas respondió, pero no pude verificar el resultado. El original sigue completo en el portapapeles.",
                evidencia: ["verificada": "false", "error": "respuesta_incompleta"])
        }
        let idNota = partes[0]
        let carpetaReal = partes[1]
        let plaintext = partes.dropFirst(2).joined(separator: separador)
        let verificada = contenidoVerificado(plan: plan, plaintext: plaintext)
        AgenteLog.registrar("nota_apple", [
            "ok": verificada, "verificada": verificada,
            "titulo": plan.titulo, "carpeta": carpetaReal,
            "id": String(idNota.prefix(160)), "caracteres": plan.original.count,
        ])
        let evidencia = [
            "verificada": "\(verificada)", "titulo": plan.titulo,
            "carpeta": carpetaReal, "nota_id": String(idNota.prefix(160)),
            "caracteres": "\(plan.original.count)",
        ]
        guard verificada else {
            Log.write("⚠️ Notas de Apple: la verificación del contenido no coincidió")
            return .init(ok: false,
                mensaje: "Notas creó un elemento, pero no pude comprobar que contenga todo el texto. El original sigue completo en el portapapeles.",
                evidencia: evidencia)
        }
        let destino = carpetaReal.isEmpty ? "" : " en «\(carpetaReal)»"
        return .init(ok: true,
            mensaje: "Creé y verifiqué la nota «\(plan.titulo)»\(destino) de Notas de Apple.",
            evidencia: evidencia)
    }

    /// Solicita el consentimiento TCC desde el hilo principal, antes de mandar
    /// el trabajo a la cola. Esto evita congelar el notch mientras Notes arranca
    /// y, a la vez, evita que el diálogo inicial se pierda en un callback de fondo.
    private static func permisoAutomatizacion(preguntar: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        guard let destino = descriptor.aeDesc else { return OSStatus(paramErr) }
        return AEDeterminePermissionToAutomateTarget(
            destino, typeWildCard, typeWildCard, preguntar)
    }

    static func estadoPermiso() -> OSStatus { permisoAutomatizacion(preguntar: false) }

    static func nombreEstadoPermiso(_ estado: OSStatus) -> String {
        if estado == noErr { return "Permitido" }
        if estado == errAEEventNotPermitted { return "Pendiente o bloqueado" }
        return "No disponible (\(estado))"
    }

    @discardableResult
    static func solicitarPermiso() -> OSStatus {
        permisoAutomatizacion(preguntar: true)
    }

    static func crear(_ texto: String,
                      completion: @escaping (ResultadoHerramientaApple) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { crear(texto, completion: completion) }
            return
        }
        guard let plan = preparar(texto) else {
            completion(.init(ok: false, mensaje: "Dime qué quieres guardar en la nota."))
            return
        }
        guard Config.agenteHerramientaNotasApple() else {
            completion(.init(ok: false,
                mensaje: "La herramienta Notas de Apple está apagada en Ajustes → Asistente."))
            return
        }
        // Respaldo antes de cualquier Apple Event. Si falta permiso o Notes falla,
        // el usuario conserva exactamente su dictado y puede pegarlo manualmente.
        copyText(plan.original)
        guard let rutaNotas = rutaAplicacion() else {
            completion(.init(ok: false,
                mensaje: "No encontré Notas de Apple. Dejé el texto en el portapapeles."))
            return
        }
        let preferencias = Preferencias.actuales
        let permiso = permisoAutomatizacion(preguntar: true)
        guard permiso == noErr else {
            AgenteLog.registrar("nota_apple", [
                "ok": false, "verificada": false, "error": Int(permiso),
                "titulo": plan.titulo, "caracteres": plan.original.count,
            ])
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: rutaNotas),
                                               configuration: .init(),
                                               completionHandler: nil)
            completion(.init(ok: false,
                mensaje: "No tengo permiso para crear la nota. Activa BtoDicta en Ajustes del Sistema → Privacidad y seguridad → Automatización → Notas. Abrí Notas y dejé el texto completo en el portapapeles."))
            return
        }
        cola.async {
            let resultado = crearSincrono(plan, rutaNotas: rutaNotas,
                                          preferencias: preferencias)
            DispatchQueue.main.async {
                if !resultado.ok {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: rutaNotas),
                                                       configuration: .init(),
                                                       completionHandler: nil)
                }
                completion(resultado)
            }
        }
    }

    /// Misma ruta de permiso + cola usada por producción, pero elimina el ítem
    /// temporal después de volver a leerlo. Requiere un run loop de AppKit.
    static func probarFlujoReal(completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let muestra = """
        Título: Nota temporal BtoDicta

        # Ruta asíncrona
        1. Contenido verificado
        - [ ] Sin truncar el texto
        > Esta nota se elimina al terminar
        """
        guard let plan = preparar(muestra) else {
            completion(.init(ok: false, mensaje: "No se pudo preparar la nota QA.")); return
        }
        guard let rutaNotas = rutaAplicacion() else {
            completion(.init(ok: false, mensaje: "No se encontró Notas de Apple.")); return
        }
        let permiso = permisoAutomatizacion(preguntar: true)
        guard permiso == noErr else {
            completion(.init(ok: false,
                mensaje: "Automatización de Notas no autorizada (\(permiso)).")); return
        }
        cola.async {
            let predeterminada = Preferencias(carpeta: "", crearCarpeta: false,
                                               mostrar: false)
            let base = crearSincrono(plan, rutaNotas: rutaNotas,
                                     preferencias: predeterminada,
                                     eliminarDespues: true, mostrar: false)
            guard base.ok, let carpeta = base.evidencia["carpeta"], !carpeta.isEmpty else {
                DispatchQueue.main.async { completion(base) }; return
            }
            // Segundo ángulo: vuelve a crear/eliminar el mismo contenido
            // seleccionando por nombre la carpeta que acabamos de verificar.
            // Así el botón prueba también la preferencia de carpeta sin dejar
            // una carpeta artificial ni modificar la configuración del usuario.
            let nombrada = Preferencias(carpeta: carpeta, crearCarpeta: false,
                                        mostrar: false)
            let porCarpeta = crearSincrono(plan, rutaNotas: rutaNotas,
                                           preferencias: nombrada,
                                           eliminarDespues: true, mostrar: false)
            let resultado = porCarpeta.ok
                ? ResultadoHerramientaApple(ok: true,
                    mensaje: "Notas funciona: creé, verifiqué y borré la nota temporal en la carpeta «\(carpeta)».",
                    evidencia: porCarpeta.evidencia)
                : porCarpeta
            DispatchQueue.main.async { completion(resultado) }
        }
    }

    /// `BTODICTA_NOTASAPPLETEST=1`: QA puro, sin abrir Notas.
    /// `BTODICTA_NOTASAPPLETEST=real`: crea, vuelve a leer y elimina una nota QA.
    static func ejecutarPruebaSiSePidio() {
        guard let modo = ProcessInfo.processInfo.environment["BTODICTA_NOTASAPPLETEST"] else {
            return
        }
        let muestra = """
        Minuta segura de BtoDicta

        - Revisar el informe & anexos
        - Confirmar <fecha> con “Andrés”
        """
        guard let plan = preparar(muestra) else {
            print("NOTASAPPLETEST FALLA no se creó el plan"); exit(3)
        }
        let puro = plan.titulo == "Minuta segura de BtoDicta"
            && plan.cuerpo.contains("Revisar el informe & anexos")
            && plan.cuerpoHTML.contains("&amp;")
            && plan.cuerpoHTML.contains("&lt;fecha&gt;")
            && plan.cuerpoHTML.contains("<ul>")
            && htmlSeguro("# Encabezado\n1. Uno\n2. Dos\n> Cita").contains("<ol>")
            && htmlSeguro("# Encabezado\n1. Uno\n2. Dos\n> Cita").contains("<blockquote>")
            && contenidoVerificado(plan: plan, plaintext: muestra)
            && contenidoVerificado(plan: plan, plaintext: """
                Minuta segura de BtoDicta

                Revisar el informe & anexos
                Confirmar <fecha> con “Andrés”
                """)
            && preparar("Título: Compras\n\n- Pan\n- Café")?.titulo == "Compras"
            && preparar("Titulada Compras: pan y café")?.cuerpo == "pan y café"
            && preparar("Titulada Compras: pan y café")?.original == "Compras\npan y café"
            && preparar(String(repeating: "texto largo ", count: 12))?.original
                == String(repeating: "texto largo ", count: 12)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            && !fuente(plan, rutaNotas: "/System/Applications/Notes.app",
                       preferencias: .init(carpeta: "BtoDicta QA", crearCarpeta: true,
                                           mostrar: false),
                       eliminarDespues: true).contains("tell application id")
        guard modo.lowercased() == "real" else {
            print("NOTASAPPLETEST \(puro ? "OK" : "FALLA") puro")
            exit(puro ? 0 : 3)
        }
        guard puro else { print("NOTASAPPLETEST FALLA prevalidación"); exit(3) }
        guard let rutaNotas = rutaAplicacion() else {
            print("NOTASAPPLETEST FALLA no se encontró Notas"); exit(3)
        }
        let p = Preferencias(carpeta: "", crearCarpeta: false, mostrar: false)
        let resultado = crearSincrono(plan, rutaNotas: rutaNotas,
                                      preferencias: p,
                                      eliminarDespues: true, mostrar: false)
        print("NOTASAPPLETEST \(resultado.ok ? "OK" : "FALLA") real | \(resultado.mensaje)")
        exit(resultado.ok ? 0 : 3)
    }
}
