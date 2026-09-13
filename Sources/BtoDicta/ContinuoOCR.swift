import AppKit
import Vision

// MARK: - Bitácora continua: texto de las capturas
//
// Lee lo que había escrito en pantalla usando Vision, que reconoce texto en el
// propio dispositivo: no sale nada del equipo y no cuesta cuota.
//
// Va en la tanda diferida, junto a la transcripción, por el mismo motivo: hacer
// esto en caliente cada vez que se toma una captura mantendría el reconocedor
// trabajando todo el día para nada.

enum ContinuoOCR {

    /// Procesa las capturas pendientes. Devuelve cuántas quedaron con texto y
    /// los DÍAS (startOfDay) de las que ganaron texto, para que el llamador
    /// regenere también los diarios de días anteriores: las capturas
    /// pendientes llegan sin filtrar por fecha, igual que el audio.
    /// `deteneteSi` permite abortar limpio si empieza un dictado.
    @discardableResult
    static func procesarPendientes(limite: Int, deteneteSi: (() -> Bool)? = nil) -> (hechas: Int, conTexto: Int, dias: Set<Date>) {
        ContinuoIndice.shared.abrir()
        let pendientes = ContinuoIndice.shared.pendientes(material: .pantalla, limite: limite)
        guard !pendientes.isEmpty else { return (0, 0, []) }

        var hechas = 0, conTexto = 0
        var dias = Set<Date>()
        for p in pendientes {
            if deteneteSi?() == true { break }
            guard FileManager.default.fileExists(atPath: p.ruta.path) else {
                // Se borró por fuera: se marca para no reintentarlo eternamente.
                ContinuoIndice.shared.anotarTexto("", material: .pantalla, id: p.id)
                continue
            }
            let texto = leer(p.ruta)
            ContinuoIndice.shared.anotarTexto(texto, material: .pantalla, id: p.id)
            hechas += 1
            if !texto.isEmpty {
                conTexto += 1
                dias.insert(Calendar.current.startOfDay(for: p.instante))
            }
        }
        return (hechas, conTexto, dias)
    }

    // MARK: Reconocimiento

    /// Texto de una imagen. Cadena vacía si no hay nada legible: eso también es
    /// un resultado válido y evita reprocesarla en cada tanda.
    static func leer(_ url: URL) -> String {
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, nil) else { return "" }

        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = Config.continuoOcrPreciso() ? .accurate : .fast
        // El idioma importa: sin fijarlo, Vision tiende a leer el español como
        // inglés mal escrito y el texto queda inservible para buscar.
        peticion.recognitionLanguages = Config.continuoOcrIdiomas()
        peticion.usesLanguageCorrection = true
        peticion.minimumTextHeight = Float(Config.continuoOcrAlturaMinima())

        let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
        do {
            try manejador.perform([peticion])
        } catch {
            Log.log(.sistema, "bitácora: no pude leer \(url.lastPathComponent) — \(error.localizedDescription)")
            return ""
        }

        guard let observaciones = peticion.results else { return "" }
        let confianzaMinima = Float(Config.continuoOcrConfianzaMinima())
        let lineas = observaciones.compactMap { obs -> String? in
            guard let mejor = obs.topCandidates(1).first, mejor.confidence >= confianzaMinima else { return nil }
            let s = mejor.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        let texto = lineas.joined(separator: "\n")
        // El reconocimiento visual se equivoca con las mismas palabras propias
        // que el de voz, así que pasa por el mismo diccionario.
        return Config.continuoDiccionarioOcr() ? applyReplacements(texto) : texto
    }
}
