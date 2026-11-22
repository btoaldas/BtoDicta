import AppKit
import Foundation

// MARK: - Mirar la pantalla con un modelo que ve (spec 023)
//
// Si el proveedor del asistente tiene un modelo con visión (formato OpenAI), se le
// manda la captura reducida (JPEG, 1600 px). Si no hay o falla, BtoDicta lee el
// texto con el OCR de Apple, como antes. La imagen nunca se guarda.

enum VisionIA {
    /// El modelo con visión: el configurado o el conocido del proveedor; nil = solo OCR.
    static func modelo(para ia: ChatIA?) -> String? {
        let dado = Config.agenteVisionModelo().trimmingCharacters(in: .whitespaces)
        if dado == "-" { return nil }                 // apagado a propósito
        if !dado.isEmpty { return dado }
        guard let ia, ia.formato == .openai, !ia.local else { return nil }
        switch ia.id {
        case "zai": return "glm-4.6v"
        case "openai": return "gpt-4.1-mini"
        default: return nil
        }
    }

    /// Captura reducida a JPEG (máx. 1600 px de lado) o nil.
    static func jpeg(_ png: URL, lado: CGFloat = 1600) -> Data? {
        guard let img = NSImage(contentsOf: png), let rep = img.representations.first else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let k = min(1, lado / max(w, h))
        let tam = NSSize(width: (w * k).rounded(), height: (h * k).rounded())
        guard let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(tam.width), pixelsHigh: Int(tam.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
        img.draw(in: NSRect(origin: .zero, size: tam))
        NSGraphicsContext.restoreGraphicsState()
        return bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    /// Cuerpo de la petición (puro).
    static func cuerpo(modelo: String, pregunta: String, jpeg: Data, proveedor: String) -> [String: Any] {
        var c: [String: Any] = [
            "model": modelo, "max_tokens": 900,
            "messages": [["role": "user", "content": [
                ["type": "text", "text": pregunta],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]],
            ]]],
        ]
        if proveedor == "zai" { c["thinking"] = ["type": "disabled"] }   // si no, gasta los tokens pensando
        return c
    }

    /// Pregunta sobre la imagen. Respuesta en main; nil si falla.
    static func preguntar(_ ia: ChatIA, modelo: String, pregunta: String, jpeg: Data, fin: @escaping (String?) -> Void) {
        guard ia.baseSegura, let url = URL(string: ia.base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"),
              let body = try? JSONSerialization.data(withJSONObject: cuerpo(modelo: modelo, pregunta: pregunta, jpeg: jpeg, proveedor: ia.id))
        else { fin(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ia.aplicarAuth(&req)
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let t = codigo == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { (($0["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String } : nil
            if t == nil { Log.write("visión: \(modelo) no respondió (HTTP \(codigo)) — uso el OCR") }
            DispatchQueue.main.async { fin(t?.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVacio) }
        }.resume()
    }
}

private extension String { var nilSiVacio: String? { isEmpty ? nil : self } }
