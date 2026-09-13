import XCTest
@testable import BtoDicta

final class RespuestaQA: URLProtocol {
    static var responder: ((URLRequest) throws -> (Int, String)?)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let (code, body) = try Self.responder?(request) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class CascadaTests: XCTestCase {
    let frase = "Mañana revisamos el informe completo con todo el equipo."
    func ia(_ nombre: String) -> ChatIA {
        ChatIA(id: "custom:qa-\(nombre)-\(UUID())", nombre: nombre,
               base: "https://\(nombre).invalid/v1", modelo: "qa-chat", keyEnv: "", local: false)
    }
    func respuesta(_ texto: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": texto], "finish_reason": "stop"]],
        ]), encoding: .utf8)!
    }
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RespuestaQA.self]
        LLMPostProcess.sesionHTTP = URLSession(configuration: config)
    }
    override func tearDown() {
        LLMPostProcess.sesionHTTP.invalidateAndCancel()
        LLMPostProcess.sesionHTTP = .shared
        RespuestaQA.responder = nil
    }
    func testPresupuestosYCuerpo() throws {
        XCTAssertEqual(PoliticaPulido.espera(texto: 130, contexto: 2200), 8)
        XCTAssertGreaterThan(PoliticaPulido.espera(texto: 6000, contexto: 8000), 60)
        XCTAssertGreaterThan(PoliticaPulido.espera(texto: 130, contexto: 16000), 30)
        XCTAssertEqual(PoliticaPulido.espera(texto: 100000, contexto: 130000), 120)
        let deepseek = ChatIA.fijos.first { $0.id == "deepseek" }!
        XCTAssertEqual(deepseek.modelo, "deepseek-flash")
        let req = try XCTUnwrap(deepseek.requestChat(prompt: String(repeating: "a", count: 16000), temperatura: 0, textLen: 10000))
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertGreaterThan(req.timeoutInterval, 90)
        let groq = ChatIA.fijos.first { $0.id == "groq" }!
        XCTAssertEqual(groq.modelo, "openai/gpt-oss-20b")
        XCTAssertFalse(ChatIA.modeloAptoParaPulido("meta-llama/llama-prompt-guard-2-86m"))
    }
    func testCuarentenaExpiraYAislaModeloCredencial() {
        let q = CuarentenaPulido(), ahora = Date(timeIntervalSince1970: 10000)
        q.registrar("p", local: false, codigo: 429, cuerpo: "insufficient_quota", error: nil, ahora: ahora)
        XCTAssertTrue(q.activa("p", local: false, ahora: ahora.addingTimeInterval(1799)))
        XCTAssertFalse(q.activa("p", local: false, ahora: ahora.addingTimeInterval(1801)))
        XCTAssertFalse(q.activa("otro-modelo", local: false, ahora: ahora))
        q.registrar("p", local: false, codigo: 0, cuerpo: "", error: URLError(.notConnectedToInternet), ahora: ahora)
        XCTAssertTrue(q.activa("otra-nube", local: false, ahora: ahora))
        XCTAssertFalse(q.activa("local", local: true, ahora: ahora))
        XCTAssertFalse(q.activa("otra-nube", local: false, ahora: ahora.addingTimeInterval(16)))
        XCTAssertEqual(CuarentenaPulido.duracion(codigo: 413, cuerpo: "too large", error: nil), 0)
        XCTAssertEqual(CuarentenaPulido.duracion(codigo: 429, cuerpo: "rate_limit", error: nil), 60)
        var proveedor = ia("identidad")
        let primero = CuarentenaPulido.identidad(proveedor)
        proveedor.keyDirecta = "credencial-sintetica-qa"
        XCTAssertNotEqual(primero, CuarentenaPulido.identidad(proveedor))
    }
    func testCuotaSaltaYNoSeReintentaEnSiguienteDictado() {
        let primero = ia("sin-cuota"), segundo = ia("disponible")
        var llamadas = [String]()
        RespuestaQA.responder = { req in
            let host = req.url!.host!
            llamadas.append(host)
            return host == "sin-cuota.invalid" ? (401, "quota_exceeded") : (200, self.respuesta(self.frase))
        }
        for _ in 0..<2 {
            let fin = expectation(description: "failover cuota")
            LLMPostProcess.hacerProveedor(primero, textoOriginal: frase, inicio: Date(), intento: 1,
                                         prompt: "Corrige: \(frase)", temp: 0, resto: [segundo]) { salida in
                XCTAssertEqual(salida, self.frase); fin.fulfill()
            }
            wait(for: [fin], timeout: 3)
        }
        XCTAssertEqual(llamadas, ["sin-cuota.invalid", "disponible.invalid", "disponible.invalid"])
    }
    func testTimeoutSinReintentoClasificadorYSinPerderOriginal() {
        let lento = ia("lento"), clasificador = ia("clasificador"), roto = ia("roto")
        var llamadas = [String]()
        RespuestaQA.responder = { req in
            let host = req.url!.host!; llamadas.append(host)
            if host == "lento.invalid" { throw URLError(.timedOut) }
            if host == "clasificador.invalid" { return (200, self.respuesta("0.923487123487123")) }
            return (503, "unavailable")
        }
        let fin = expectation(description: "conserva original")
        LLMPostProcess.hacerProveedor(lento, textoOriginal: frase, inicio: Date(), intento: 1,
                                     prompt: "Corrige: \(frase)", temp: 0, resto: [clasificador, roto]) { salida in
            XCTAssertEqual(salida, self.frase); fin.fulfill()
        }
        wait(for: [fin], timeout: 3)
        XCTAssertEqual(llamadas, ["lento.invalid", "clasificador.invalid", "roto.invalid"])
    }
    func testLimiteRealEntregaUnaSolaRespuesta() {
        RespuestaQA.responder = { _ in nil } // Socket abierto que nunca responde.
        var req = URLRequest(url: URL(string: "https://lento.invalid")!)
        req.timeoutInterval = 0.15
        var respuestas = 0
        let inicio = Date(), fin = expectation(description: "deadline")
        PeticionPulido.ejecutar(req, session: LLMPostProcess.sesionHTTP) { _, _, error in
            respuestas += 1
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
            fin.fulfill()
        }
        wait(for: [fin], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(inicio), 1)
        let tardio = expectation(description: "sin callback tardío")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tardio.fulfill() }
        wait(for: [tardio], timeout: 1)
        XCTAssertEqual(respuestas, 1)
    }
    func testCascadaComparteElPlazoTotal() {
        XCTAssertEqual(PoliticaPulido.esperaTotal(texto: 120, contexto: 2000), 24)
        XCTAssertEqual(PoliticaPulido.esperaTotal(texto: 100000, contexto: 120000), 240)
        var llamadas = 0
        RespuestaQA.responder = { _ in llamadas += 1; return nil }
        let fin = expectation(description: "presupuesto compartido")
        LLMPostProcess.hacerProveedor(ia("sin-respuesta"), textoOriginal: frase, inicio: Date(), intento: 1,
                                     prompt: frase, temp: 0, resto: [ia("no-debe-iniciar")],
                                     plazo: Date().addingTimeInterval(0.15)) { salida in
            XCTAssertEqual(salida, self.frase); fin.fulfill()
        }
        wait(for: [fin], timeout: 2)
        XCTAssertEqual(llamadas, 1)
    }
    func testTextoLargoNoSeRecortaAEsperaCorta() {
        let proveedor = ia("largo"), original = String(repeating: "Hay que revisar el documento. ", count: 350)
        RespuestaQA.responder = { req in
            XCTAssertGreaterThan(req.timeoutInterval, 90)
            return (200, self.respuesta(original))
        }
        let fin = expectation(description: "largo")
        LLMPostProcess.hacerProveedor(proveedor, textoOriginal: original, inicio: Date(), intento: 1,
                                     prompt: original, temp: 0, resto: []) { salida in
            XCTAssertEqual(salida, original.trimmingCharacters(in: .whitespacesAndNewlines)); fin.fulfill()
        }
        wait(for: [fin], timeout: 3)
    }

    func testSoloAdmiteArchivosLocalesRegulares() {
        XCTAssertThrowsError(try AudioArchivo.normalizar(URL(string: "https://audio.invalid/prueba.mp3")!))
        XCTAssertThrowsError(try AudioArchivo.normalizar(FileManager.default.temporaryDirectory))
    }

    func testFormatosUsanWAVYCascadaSinModificarOriginales() throws {
        let fm = FileManager.default
        let carpeta = fm.temporaryDirectory.appendingPathComponent("btodicta-formatos-\(UUID())")
        try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: carpeta) }
        let fuente = carpeta.appendingPathComponent("fuente.wav")
        var pcm = Data()
        for i in 0..<32000 {
            var valor = Int16(sin(Double(i) * 2 * .pi * 440 / 16000) * 4000).littleEndian
            withUnsafeBytes(of: &valor) { pcm.append(contentsOf: $0) }
        }
        try AudioArchivo.wav(pcm).write(to: fuente)
        let ffmpeg = try XCTUnwrap(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { fm.isExecutableFile(atPath: $0) })
        for formato in ["wav", "mp3", "m4a", "mp4", "mov", "ogg"] {
            let url = carpeta.appendingPathComponent("prueba.\(formato)")
            let proc = Process(); proc.executableURL = URL(fileURLWithPath: ffmpeg)
            proc.arguments = ["-nostdin", "-v", "error", "-i", fuente.path]
            if ["mp4", "mov"].contains(formato) {
                proc.arguments! += ["-f", "lavfi", "-i", "color=size=32x32:rate=5:duration=2",
                                    "-c:v", "mpeg4", "-shortest"]
            }
            proc.arguments! += ["-ar", "48000", "-ac", "2", url.path]
            try proc.run(); proc.waitUntilExit(); XCTAssertEqual(proc.terminationStatus, 0)
            let antes = try Data(contentsOf: url)
            let fin = expectation(description: formato)
            AudioArchivo.transcribir(url, motor: { wav, completar in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(String(data: wav.prefix(4), encoding: .utf8), "RIFF")
                XCTAssertEqual(Array(wav[22..<24]), [1, 0]) // mono
                XCTAssertEqual(Array(wav[24..<28]), [128, 62, 0, 0]) // 16000 Hz
                XCTAssertEqual(Array(wav[34..<36]), [16, 0])
                XCTAssertGreaterThan(wav.count, 60000)
                XCTAssertLessThan(wav.count, 70000)
                completar(.success(("Audio correcto.", "cascada-qa", "modelo-qa")))
            }) { resultado in
                guard case .success(let (texto, proveedor, _)) = resultado else {
                    XCTFail("\(formato): \(resultado)"); fin.fulfill(); return
                }
                XCTAssertEqual(texto, "Audio correcto."); XCTAssertEqual(proveedor, "cascada-qa")
                fin.fulfill()
            }
            wait(for: [fin], timeout: 15)
            XCTAssertEqual(antes, try Data(contentsOf: url))
        }
        let invalido = carpeta.appendingPathComponent("invalido.mp3")
        try Data("archivo roto".utf8).write(to: invalido)
        let fin = expectation(description: "archivo inválido no sale a la nube")
        AudioArchivo.transcribir(invalido, motor: { _, _ in XCTFail("No debe llamar un proveedor") }) { r in
            if case .success = r { XCTFail("Debía fallar conversión") }
            fin.fulfill()
        }
        wait(for: [fin], timeout: 10)
    }
}
