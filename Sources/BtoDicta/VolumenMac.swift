import AppKit
import Foundation

// MARK: - Volumen del sistema para el Asistente

enum OperacionVolumenMac: Equatable {
    case fijar(Int)
    case variar(Int)
    case silenciar
    case activar

    var codigo: String {
        switch self {
        case .fijar(let valor): return "fijar:\(max(0, min(100, valor)))"
        case .variar(let delta): return "variar:\(max(-100, min(100, delta)))"
        case .silenciar: return "silenciar"
        case .activar: return "activar"
        }
    }

    init?(codigo: String) {
        let partes = codigo.split(separator: ":", maxSplits: 1).map(String.init)
        switch partes.first {
        case "fijar" where partes.count == 2:
            guard let valor = Int(partes[1]) else { return nil }
            self = .fijar(max(0, min(100, valor)))
        case "variar" where partes.count == 2:
            guard let delta = Int(partes[1]), delta != 0 else { return nil }
            self = .variar(max(-100, min(100, delta)))
        case "silenciar": self = .silenciar
        case "activar": self = .activar
        default: return nil
        }
    }

    var descripcion: String {
        switch self {
        case .fijar(100): return "Poner el volumen del Mac al máximo"
        case .fijar(let valor): return "Poner el volumen del Mac al \(valor)%"
        case .variar(let delta) where delta > 0:
            return "Subir el volumen del Mac \(delta) puntos"
        case .variar(let delta):
            return "Bajar el volumen del Mac \(-delta) puntos"
        case .silenciar: return "Silenciar el sonido del Mac"
        case .activar: return "Activar el sonido del Mac"
        }
    }
}

struct EstadoVolumenMac: Equatable {
    var volumen: Int
    var silenciado: Bool

    init(volumen: Int, silenciado: Bool) {
        self.volumen = max(0, min(100, volumen))
        self.silenciado = silenciado
    }
}

struct SolicitudVolumenMac: Equatable {
    let operacion: OperacionVolumenMac

    var codigo: String { operacion.codigo }
    var descripcion: String { operacion.descripcion }

    init(_ operacion: OperacionVolumenMac) { self.operacion = operacion }

    init?(codigo: String) {
        guard let operacion = OperacionVolumenMac(codigo: codigo) else { return nil }
        self.operacion = operacion
    }

    private static let verbosSubir: Set<String> = [
        "sube", "subeme", "alza", "alzale", "aumenta", "aumentale", "eleva", "elevale",
    ]
    private static let verbosBajar: Set<String> = [
        "baja", "bajame", "bajale", "reduce", "reducele", "disminuye", "disminuyele",
    ]
    private static let verbosFijar: Set<String> = [
        "pon", "ponme", "ponlo", "coloca", "ajusta", "fija", "dejalo", "deja", "lleva",
    ]
    private static let objetivos: Set<String> = ["volumen", "sonido", "audio"]

    private static func sinCortesia(_ texto: String) -> String {
        var salida = PerfilAgente.normalizar(texto)
        for prefijo in ["por favor ", "porfavor ", "porfa "] where salida.hasPrefix(prefijo) {
            salida.removeFirst(prefijo.count)
            break
        }
        return salida.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contiene(_ patron: String, en texto: String) -> Bool {
        texto.range(of: patron, options: .regularExpression) != nil
    }

    /// Evita convertir una explicación en una acción del sistema. El control de
    /// audio solo gana si la orden está al inicio y no habla de otro significado
    /// de «volumen» ni intenta encadenar una segunda herramienta todavía.
    private static func contextoSeguro(_ texto: String) -> Bool {
        let noAudio = [
            "volumen de ventas", "volumen del informe", "volumen de datos",
            "volumen del documento", "volumen del libro", "volumen de la caja",
            "volumen del cilindro",
        ]
        guard !noAudio.contains(where: texto.contains) else { return false }
        let segundaAccion = #"\by\s+(?:abre|crea|escribe|envia|manda|traduce|resume|busca|graba|captura|agenda|recuerda)\b"#
        return !contiene(segundaAccion, en: texto)
    }

    private static func numeroEspanol(_ tokens: ArraySlice<String>) -> Int? {
        guard let primero = tokens.first else { return nil }
        if let numero = Int(primero) { return (0...100).contains(numero) ? numero : nil }

        let directos: [String: Int] = [
            "cero": 0, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
            "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
            "diez": 10, "once": 11, "doce": 12, "trece": 13, "catorce": 14,
            "quince": 15, "dieciseis": 16, "diecisiete": 17, "dieciocho": 18,
            "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintidos": 22,
            "veintitres": 23, "veinticuatro": 24, "veinticinco": 25,
            "veintiseis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
            "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
            "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
            "ciento": 100,
        ]
        guard let base = directos[primero] else { return nil }
        if base >= 30, base < 100, tokens.count >= 3,
           tokens[tokens.index(after: tokens.startIndex)] == "y" {
            let tercero = tokens[tokens.index(tokens.startIndex, offsetBy: 2)]
            if let unidad = directos[tercero], (1...9).contains(unidad) { return base + unidad }
        }
        return base
    }

    /// Devuelve el marcador («al», «en», «un»…) y el número que aparece después
    /// de volumen/sonido/audio. Soporta 75 y «setenta y cinco por ciento».
    private static func valorDespuesDelObjetivo(_ tokens: [String]) -> (marcador: String, valor: Int)? {
        guard let i = tokens.firstIndex(where: objetivos.contains), i + 1 < tokens.count else { return nil }
        var j = i + 1
        var marcador = ""
        if ["a", "al", "hasta", "en", "un", "una"].contains(tokens[j]) {
            marcador = tokens[j]; j += 1
        }
        if j < tokens.count, ["el", "un", "una"].contains(tokens[j]) {
            if marcador.isEmpty { marcador = tokens[j] }
            j += 1
        }
        guard j < tokens.count, let valor = numeroEspanol(tokens[j...]) else { return nil }
        return (marcador, valor)
    }

    static func interpretar(_ texto: String, pasoPredeterminado: Int = 10) -> SolicitudVolumenMac? {
        let normal = sinCortesia(texto)
        guard !normal.isEmpty, contextoSeguro(normal) else { return nil }
        let tokens = normal.split(separator: " ").map(String.init)
        guard let verbo = tokens.first else { return nil }
        let paso = max(1, min(50, pasoPredeterminado))

        if ["mute", "silencio", "silencia", "silenciar", "mutea", "mutear"].contains(normal)
            || contiene(#"^(?:pon|ponme|ponlo|deja|dejalo)\s+(?:(?:el\s+)?(?:volumen|sonido|audio)\s+)?(?:en\s+)?(?:mute|silencio|mudo)\b"#, en: normal)
            || contiene(#"^(?:silencia|silenciar|mutea|mutear|apaga)\s+(?:el\s+)?(?:sonido|audio|volumen)\b"#, en: normal) {
            return SolicitudVolumenMac(.silenciar)
        }

        if contiene(#"^(?:activa|activar|reactiva|reactivar|enciende|encender|desmutea|desmutear)\s+(?:el\s+)?(?:sonido|audio|volumen)\b"#, en: normal)
            || contiene(#"^(?:quita|quitar|saca|sacar|desactiva|desactivar)\s+(?:el\s+)?(?:mute|silencio)\b"#, en: normal) {
            return SolicitudVolumenMac(.activar)
        }

        guard tokens.contains(where: objetivos.contains) else { return nil }
        let esSubir = verbosSubir.contains(verbo)
        let esBajar = verbosBajar.contains(verbo)
        let esFijar = verbosFijar.contains(verbo) || objetivos.contains(verbo)
        guard esSubir || esBajar || esFijar else { return nil }

        if contiene(#"\b(?:maximo|tope|todo|cien(?:\s+por\s+ciento)?)\b"#, en: normal),
           esSubir || esFijar {
            return SolicitudVolumenMac(.fijar(100))
        }

        if let numero = valorDespuesDelObjetivo(tokens) {
            if ["a", "al", "hasta"].contains(numero.marcador) || esFijar {
                return SolicitudVolumenMac(.fijar(numero.valor))
            }
            if esSubir { return SolicitudVolumenMac(.variar(max(1, numero.valor))) }
            if esBajar { return SolicitudVolumenMac(.variar(-max(1, numero.valor))) }
        }

        if esSubir { return SolicitudVolumenMac(.variar(paso)) }
        if esBajar { return SolicitudVolumenMac(.variar(-paso)) }
        return nil
    }
}

enum VolumenMac {
    /// Parte pura y testeable. «Activar» conserva el nivel existente; si estaba
    /// realmente en cero, usa el paso configurado para volver a ser audible.
    static func estadoResultante(_ solicitud: SolicitudVolumenMac,
                                 desde estado: EstadoVolumenMac,
                                 pasoPredeterminado: Int = 10) -> EstadoVolumenMac {
        switch solicitud.operacion {
        case .fijar(let valor):
            return EstadoVolumenMac(volumen: valor, silenciado: false)
        case .variar(let delta):
            return EstadoVolumenMac(volumen: estado.volumen + delta, silenciado: false)
        case .silenciar:
            return EstadoVolumenMac(volumen: estado.volumen, silenciado: true)
        case .activar:
            let audible = estado.volumen == 0 ? max(1, min(50, pasoPredeterminado)) : estado.volumen
            return EstadoVolumenMac(volumen: audible, silenciado: false)
        }
    }

    private static func osa(_ fuente: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let resultado = NSAppleScript(source: fuente)?.executeAndReturnError(&error)
        if let error {
            Log.debug("volumen Mac: AppleScript falló: \(error)")
            return nil
        }
        return resultado
    }

    static func estadoActual() -> EstadoVolumenMac? {
        guard let volumen = osa("output volume of (get volume settings)"),
              let silenciado = osa("output muted of (get volume settings)") else { return nil }
        return EstadoVolumenMac(volumen: Int(volumen.int32Value),
                                silenciado: silenciado.booleanValue)
    }

    private static func aplicar(_ estado: EstadoVolumenMac) -> Bool {
        guard osa("set volume output volume \(estado.volumen)") != nil else { return false }
        return osa("set volume output muted \(estado.silenciado)") != nil
    }

    /// Ejecuta en main porque NSAppleScript y la respuesta del notch pertenecen
    /// al flujo AppKit. Siempre vuelve a leer el Mac: no anuncia éxito por haber
    /// enviado el comando, sino por comprobar el nivel y el mute reales.
    static func ejecutar(_ solicitud: SolicitudVolumenMac,
                         pasoPredeterminado: Int = Config.agenteVolumenPaso(),
                         completion: @escaping (ResultadoHerramientaApple) -> Void) {
        let trabajo = {
            guard let inicial = estadoActual() else {
                completion(.init(ok: false,
                    mensaje: "No pude leer el volumen de salida de esta Mac."))
                return
            }
            let esperado = estadoResultante(solicitud, desde: inicial,
                                             pasoPredeterminado: pasoPredeterminado)
            guard aplicar(esperado), let final = estadoActual() else {
                completion(.init(ok: false,
                    mensaje: "No pude cambiar el volumen de salida de esta Mac.",
                    evidencia: ["volumen_inicial": "\(inicial.volumen)",
                                "mute_inicial": "\(inicial.silenciado)"]))
                return
            }
            let coincideVolumen = abs(final.volumen - esperado.volumen) <= 1
            let coincideMute = final.silenciado == esperado.silenciado
            let ok = coincideVolumen && coincideMute
            let mensaje: String
            if !ok {
                mensaje = "El Mac no confirmó el cambio: quedó en \(final.volumen)%\(final.silenciado ? " y en silencio" : "")."
            } else if final.silenciado {
                mensaje = "Sonido silenciado."
            } else {
                mensaje = "Volumen al \(final.volumen)%."
            }
            completion(.init(ok: ok, mensaje: mensaje, evidencia: [
                "operacion": solicitud.codigo,
                "volumen_inicial": "\(inicial.volumen)",
                "mute_inicial": "\(inicial.silenciado)",
                "volumen_final": "\(final.volumen)",
                "mute_final": "\(final.silenciado)",
                "verificado": "\(ok)",
            ]))
        }
        if Thread.isMainThread { trabajo() }
        else { DispatchQueue.main.async(execute: trabajo) }
    }
}

/// QA focalizado: no modifica el volumen real. Valida lenguaje, congelación del
/// plan y cálculo de estado con un dispositivo simulado.
enum VolumenMacQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_VOLUMETEST"] == "1" else { return }
        var fallos = 0
        func comprobar(_ nombre: String, _ condicion: @autoclosure () -> Bool) {
            let ok = condicion()
            if !ok { fallos += 1 }
            print("VOLUMETEST \(ok ? "OK" : "FALLA") \(nombre)")
        }
        func operacion(_ texto: String, paso: Int = 10) -> OperacionVolumenMac? {
            SolicitudVolumenMac.interpretar(texto,
                                             pasoPredeterminado: paso)?.operacion
        }

        comprobar("fija 50 por ciento", operacion("Pon el volumen al 50%") == .fijar(50))
        comprobar("fija 70 por ciento", operacion("Ajusta el sonido a 70 por ciento") == .fijar(70))
        comprobar("fija setenta y cinco hablado",
                  operacion("Pon el volumen al setenta y cinco por ciento") == .fijar(75))
        comprobar("baja con paso configurado", operacion("Baja el volumen", paso: 15) == .variar(-15))
        comprobar("sube con paso configurado", operacion("Sube el sonido", paso: 5) == .variar(5))
        comprobar("baja cantidad relativa", operacion("Baja el volumen un 20%") == .variar(-20))
        comprobar("sube a nivel absoluto", operacion("Sube el volumen al 70%") == .fijar(70))
        comprobar("máximo coloquial", operacion("Alza el sonido a todo") == .fijar(100))
        comprobar("máximo explícito", operacion("Pon el volumen al máximo") == .fijar(100))
        comprobar("mute inglés", operacion("Pon mute") == .silenciar)
        comprobar("silencio español", operacion("Silencia el sonido") == .silenciar)
        comprobar("reactiva sonido", operacion("Activa el sonido") == .activar)
        comprobar("quita silencio", operacion("Quita el silencio") == .activar)
        comprobar("cortesía inicial", operacion("Por favor, pon el audio al 25%") == .fijar(25))

        comprobar("narración no acciona",
                  operacion("Ayer bajé el volumen mientras trabajaba") == nil)
        comprobar("volumen de ventas no acciona",
                  operacion("Baja el volumen de ventas del informe") == nil)
        comprobar("volumen del documento no acciona",
                  operacion("Baja el volumen del documento") == nil)
        comprobar("segunda herramienta no se pierde",
                  operacion("Baja el volumen y abre Outlook") == nil)
        comprobar("HomeKit no se confunde con mute",
                  operacion("Apaga las luces") == nil)
        comprobar("porcentaje sin orden no acciona",
                  operacion("El volumen está al 50 por ciento") == nil)

        let inicial = EstadoVolumenMac(volumen: 42, silenciado: false)
        comprobar("simulación fija y desmutea",
                  VolumenMac.estadoResultante(.init(.fijar(75)), desde: inicial)
                    == EstadoVolumenMac(volumen: 75, silenciado: false))
        comprobar("simulación limita al cien",
                  VolumenMac.estadoResultante(.init(.variar(90)), desde: inicial)
                    == EstadoVolumenMac(volumen: 100, silenciado: false))
        comprobar("simulación limita a cero",
                  VolumenMac.estadoResultante(.init(.variar(-90)), desde: inicial)
                    == EstadoVolumenMac(volumen: 0, silenciado: false))
        comprobar("silenciar conserva nivel",
                  VolumenMac.estadoResultante(.init(.silenciar), desde: inicial)
                    == EstadoVolumenMac(volumen: 42, silenciado: true))
        comprobar("activar desde cero recupera paso",
                  VolumenMac.estadoResultante(.init(.activar),
                    desde: .init(volumen: 0, silenciado: true), pasoPredeterminado: 15)
                    == EstadoVolumenMac(volumen: 15, silenciado: false))

        let plan = AgenteNucleo.planificarVolumen("Pon el volumen al 75%",
                                                   permitir: true, paso: 10)
        comprobar("plan congela operación",
                  plan?.cadena.acciones.first?.modo.accion == "volumen"
                    && plan?.cadena.acciones.first?.modo.prompt == "fijar:75")
        comprobar("plan describe la cifra",
                  plan?.descripcion == "Poner el volumen del Mac al 75%")
        comprobar("acción reversible en asistido",
                  plan.map { PoliticaAgente.riesgo(de: $0.cadena) == .reversible
                    && PoliticaAgente.autoEjecutar($0.cadena, nivel: .asistido) } == true)
        comprobar("respuesta espera evidencia real",
                  plan.map { MensajesAgente.esperaResultado($0.cadena) } == true)

        print(fallos == 0 ? "VOLUMETEST TODO OK" : "VOLUMETEST \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}
