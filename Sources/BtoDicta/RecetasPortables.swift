import AppKit
import Foundation

// MARK: - Paquetes JSON portables

struct PaqueteRecetasBeto: Codable {
    var esquema: Int
    var nombre: String
    var creadoEn: String
    var recetas: [RutinaAgente]
}

enum RecetasPortables {
    static let tiposPermitidos: Set<String> = [
        "musica", "app", "app_primera", "url", "atajo", "tarea", "nota", "nota_apple",
        "recordatorio", "calendario", "archivo", "captura", "grabacion",
        "resumen_dia", "resumen_manana", "estado_mac", "captura_inteligente", "cerrar_apps",
        "seleccion_resumir", "seleccion_traducir", "seleccion_responder",
        "seleccion_tarea", "seleccion_leer", "seleccion_nota_apple",
        "audio_transcribir", "audio_resumir",
        "audio_traducir", "audio_correo", "audio_oficio"
    ]

    static func validar(_ paquete: PaqueteRecetasBeto) -> String? {
        guard paquete.esquema == 1 else { return "El paquete usa un esquema no compatible." }
        guard !paquete.recetas.isEmpty, paquete.recetas.count <= 100 else {
            return "El paquete debe contener entre 1 y 100 recetas."
        }
        for r in paquete.recetas {
            guard !r.nombre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  r.id.count <= 200, r.nombre.count <= 120,
                  r.categoria.count <= 80, r.descripcion.count <= 2_000,
                  r.frases.count <= 40, r.frases.allSatisfy({ $0.count <= 500 }),
                  r.pasos.count <= 30 else {
                return "La receta «\(r.nombre)» supera los límites permitidos."
            }
            for p in r.pasos {
                guard p.id.count <= 200, tiposPermitidos.contains(p.tipo),
                      p.valor.count <= 5_000 else {
                    return "El paso «\(p.tipo)» de «\(r.nombre)» no es compatible."
                }
                if p.tipo == "url", !p.valor.isEmpty {
                    let muestra = p.valor.replacingOccurrences(of: "{texto}", with: "prueba")
                        .replacingOccurrences(of: "{resultado}", with: "prueba")
                        .replacingOccurrences(of: "{fecha}", with: "2026-07-19")
                    guard let u = URL(string: muestra), let e = u.scheme?.lowercased(),
                          let h = u.host?.lowercased(),
                          u.user == nil, u.password == nil,
                          e == "https" || (e == "http" && ["localhost", "127.0.0.1", "::1"].contains(h)) else {
                        return "La receta «\(r.nombre)» contiene una URL insegura."
                    }
                }
            }
        }
        guard let bytes = try? JSONEncoder().encode(paquete), bytes.count <= 2_000_000 else {
            return "El paquete supera 2 MB."
        }
        return nil
    }

    static func exportar(_ recetas: [RutinaAgente], a url: URL) -> ResultadoHerramientaApple {
        let f = ISO8601DateFormatter()
        let p = PaqueteRecetasBeto(esquema: 1, nombre: "Biblioteca BtoDicta",
                                   creadoEn: f.string(from: Date()), recetas: recetas)
        if let error = validar(p) { return .init(ok: false, mensaje: error) }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try enc.encode(p).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return .init(ok: true, mensaje: "Exporté \(recetas.count) recetas a «\(url.lastPathComponent)».")
        } catch { return .init(ok: false, mensaje: "No pude exportar: \(error.localizedDescription)") }
    }

    static func importar(desde url: URL, actuales: [RutinaAgente])
        -> Result<[RutinaAgente], Error> {
        do {
            let d = try Data(contentsOf: url)
            guard d.count <= 2_000_000 else { throw NSError(domain: "BtoDicta.Recetas", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "El paquete supera 2 MB."]) }
            let p = try JSONDecoder().decode(PaqueteRecetasBeto.self, from: d)
            if let error = validar(p) { throw NSError(domain: "BtoDicta.Recetas", code: 2,
                userInfo: [NSLocalizedDescriptionKey: error]) }
            var ids = Set(actuales.map(\.id)), salida = actuales
            for var r in p.recetas {
                if ids.contains(r.id) { r.id = "importada-" + UUID().uuidString }
                r.incluida = false; ids.insert(r.id); salida.append(r)
            }
            return .success(salida)
        } catch { return .failure(error) }
    }
}

// MARK: - Contrato del Atajo universal

struct OrdenUniversalBeto: Codable {
    var esquema: Int = 1
    var accion: String
    var parametros: [String: String] = [:]
    /// Acciones por encima del nivel de autonomía solo se aceptan después de
    /// una confirmación visible en BtoDicta/Atajos.
    var confirmado: Bool? = nil
}

struct RespuestaUniversalBeto: Codable {
    var esquema: Int = 1
    var ok: Bool
    var mensaje: String
    var evidencia: [String: String]
}

enum AtajoUniversalBtoDicta {
    static let acciones = ["musica", "calendario", "recordatorio", "aplicacion",
                           "atajo", "homekit", "foco", "captura", "estado_mac", "resumen_dia"]

    static func decodificar(_ data: Data) throws -> OrdenUniversalBeto {
        guard data.count <= 64_000 else { throw NSError(domain: "BtoDicta.Universal", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "La acción estructurada supera 64 KB."]) }
        let o = try JSONDecoder().decode(OrdenUniversalBeto.self, from: data)
        guard o.esquema == 1, acciones.contains(o.accion), o.parametros.count <= 30,
              o.parametros.allSatisfy({ $0.key.count <= 80 && $0.value.count <= 5_000 }) else {
            throw NSError(domain: "BtoDicta.Universal", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "La acción estructurada no es válida."])
        }
        return o
    }

    static func decodificar(desde url: URL) throws -> OrdenUniversalBeto {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        let n = (a[.size] as? NSNumber)?.intValue ?? 0
        guard n <= 64_000 else { throw NSError(domain: "BtoDicta.Universal", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "La acción estructurada supera 64 KB."]) }
        return try decodificar(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func paso(_ o: OrdenUniversalBeto) -> PasoRutinaAgente? {
        let texto = o.parametros["texto"] ?? ""
        switch o.accion {
        case "musica": return .init(tipo: "musica", valor: texto)
        case "calendario": return .init(tipo: "calendario", valor: texto)
        case "recordatorio": return .init(tipo: "recordatorio", valor: texto)
        case "aplicacion": return .init(tipo: "app", valor: o.parametros["nombre"] ?? texto)
        case "atajo", "homekit", "foco":
            return .init(tipo: "atajo", valor: o.parametros["atajo"] ?? "")
        case "captura": return .init(tipo: "captura_inteligente", valor: texto)
        case "estado_mac": return .init(tipo: "estado_mac", valor: "")
        case "resumen_dia": return .init(tipo: "resumen_dia", valor: "")
        default: return nil
        }
    }

    static func ejecutar(_ orden: OrdenUniversalBeto, simular: Bool = false,
                         completion: @escaping (RespuestaUniversalBeto) -> Void) {
        guard let p = paso(orden) else {
            completion(.init(ok: false, mensaje: "Acción no compatible.", evidencia: [:])); return
        }
        var r = RutinaAgente(nombre: "Atajo universal")
        r.id = "beto-universal-temporal"; r.pasos = [p]
        let riesgo = RutinasAgenteStore.riesgo(r)
        let permitido: Bool
        switch PoliticaAgente.nivel {
        case .consultivo: permitido = false
        case .asistido: permitido = riesgo <= .reversible
        case .autonomo: permitido = riesgo <= .cambioLocal
        }
        if !simular, !permitido, orden.confirmado != true {
            completion(.init(ok: false,
                mensaje: "La acción requiere confirmación en BtoDicta.",
                evidencia: ["riesgo": "\(riesgo.rawValue)", "requiere_confirmacion": "true"])); return
        }
        RutinasAgenteRunner.ejecutar(rutina: r, texto: orden.parametros["texto"] ?? "",
                                     simular: simular) { x in
            completion(.init(ok: x.ok, mensaje: x.mensaje, evidencia: x.evidencia))
        }
    }

    static func respuestaJSON(_ r: RespuestaUniversalBeto) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? e.encode(r)) ?? Data()
    }
}
