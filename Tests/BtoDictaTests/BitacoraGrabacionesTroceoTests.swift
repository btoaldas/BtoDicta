import Foundation
import XCTest
@testable import BtoDicta

/// Solo PCM sintético y proveedores simulados. La configuración y el aprendizaje
/// de límites quedan en el directorio de pruebas aislado del proceso.
final class BitacoraGrabacionesTroceoTests: XCTestCase {

    func testDenegacionInicialNoLeeElArchivoNiInvocaElProveedor() throws {
        var envios = 0, completadas = 0
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.archivo(URL(fileURLWithPath: "/audio-sintetico-inexistente")),
                              motor: motorNuevo(), permitirSolicitud: { false }, enviar: { _, _ in
            envios += 1
        }) { resultado in
            completadas += 1
            salida = resultado
        }
        XCTAssertEqual(envios, 0)
        XCTAssertEqual(completadas, 1)
        if case .success = try XCTUnwrap(salida) { XCTFail("el material denegado no puede enviarse") }
    }

    func testRespuestaTruncadaEnVueloSeConservaSinAbrirOtraPeticion() throws {
        let wav = audioSintetico(segundos: 160)
        let motor = motorNuevo()
        XCTAssertTrue(Troceo.pareceTruncado(texto: "texto ya recibido", segundosDeVoz: Troceo.segundosDeVoz(.datos(wav))))
        var permitido = true, envios = 0, completadas = 0
        var resolver: ((Result<String, Error>) -> Void)?
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.datos(wav), motor: motor, permitirSolicitud: { permitido }, enviar: { _, fin in
            envios += 1
            resolver = fin
        }) { resultado in
            completadas += 1
            salida = resultado
        }
        XCTAssertEqual(envios, 1)
        XCTAssertNil(salida, "la respuesta sigue en vuelo")
        permitido = false
        try XCTUnwrap(resolver)(.success("texto ya recibido"))
        XCTAssertEqual(try XCTUnwrap(salida).get(), "texto ya recibido")
        XCTAssertEqual(envios, 1, "la reparación del truncado tampoco puede abrir nuevas solicitudes")
        XCTAssertEqual(completadas, 1)
        XCTAssertNil(Troceo.tamanoSeguro(motor), "suspender una petición no enseña un falso techo al proveedor")
    }

    func testFalloDeTamanoEnVueloNoIniciaParticionTrasCambiarElPermiso() throws {
        let wav = audioSintetico(segundos: 160)
        var permitido = true, envios = 0
        var resolver: ((Result<String, Error>) -> Void)?
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.datos(wav), motor: motorNuevo(), permitirSolicitud: { permitido }, enviar: { _, fin in
            envios += 1
            resolver = fin
        }) { salida = $0 }
        permitido = false
        try XCTUnwrap(resolver)(.failure(ScribeError.http(413, "límite sintético")))
        XCTAssertEqual(envios, 1)
        switch try XCTUnwrap(salida) {
        case .failure(let error):
            if case ScribeError.http(413, _) = error {} else { XCTFail("debe conservar el fallo original") }
        case .success: XCTFail("un fallo sin texto no puede convertirse en éxito")
        }
    }

    func testParticionConservaTramosAnterioresYRespuestaEnVueloAlSuspender() throws {
        let wav = audioSintetico(segundos: 160)
        var permitido = true, envios = 0, completadas = 0
        var resolver: ((Result<String, Error>) -> Void)?
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.datos(wav), motor: motorNuevo(), permitirSolicitud: { permitido }, enviar: { _, fin in
            envios += 1
            switch envios {
            case 1: fin(.failure(ScribeError.http(413, "límite sintético")))
            case 2: fin(.success("primer tramo"))
            case 3: resolver = fin
            default: XCTFail("se abrió una solicitud después de suspender"); fin(.failure(ScribeError.sinTexto))
            }
        }) { resultado in
            completadas += 1
            salida = resultado
        }
        XCTAssertEqual(envios, 3)
        XCTAssertNil(salida)
        permitido = false
        try XCTUnwrap(resolver)(.success("segundo tramo"))
        XCTAssertEqual(try XCTUnwrap(salida).get(), "primer tramo segundo tramo")
        XCTAssertEqual(envios, 3, "no se abre el tercer tramo todavía pendiente")
        XCTAssertEqual(completadas, 1)
    }

    func testParticionConservaPrimerTramoSiElSiguienteFallaDespuesDeSuspender() throws {
        let wav = audioSintetico(segundos: 160)
        var permitido = true, envios = 0
        var resolver: ((Result<String, Error>) -> Void)?
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.datos(wav), motor: motorNuevo(), permitirSolicitud: { permitido }, enviar: { _, fin in
            envios += 1
            switch envios {
            case 1: fin(.failure(ScribeError.http(413, "límite sintético")))
            case 2: fin(.success("primer tramo conservado"))
            case 3: resolver = fin
            default: XCTFail("se abrió una solicitud después de suspender"); fin(.failure(ScribeError.sinTexto))
            }
        }) { salida = $0 }
        permitido = false
        try XCTUnwrap(resolver)(.failure(ScribeError.http(503, "fallo sintético")))
        XCTAssertEqual(try XCTUnwrap(salida).get(), "primer tramo conservado")
        XCTAssertEqual(envios, 3)
    }

    func testSinGuardiaConservaLaReparacionHeredadaDelTruncado() throws {
        let wav = audioSintetico(segundos: 160)
        let partes = Troceo.tramos(wav, bytesPorTramo: RedSeguridadDictado.par((wav.count - 44) / 2))
        XCTAssertGreaterThan(partes.count, 1)
        var envios = 0
        var salida: Result<String, Error>?
        Troceo.enviarPartiendo(.datos(wav), motor: motorNuevo(), enviar: { _, fin in
            envios += 1
            fin(.success(envios == 1 ? "respuesta corta" : "fragmento \(envios - 1)"))
        }) { salida = $0 }
        XCTAssertEqual(envios, 1 + partes.count, "el parámetro opcional conserva el flujo anterior")
        let esperado = (1...partes.count).map { "fragmento \($0)" }.joined(separator: " ")
        XCTAssertEqual(try XCTUnwrap(salida).get(), esperado)
    }

    private func motorNuevo() -> String { "qa-troceo-013-\(UUID().uuidString)" }

    private func audioSintetico(segundos: Int) -> Data {
        var pcm = Data(count: segundos * RedSeguridadDictado.bytesPorSegundo)
        pcm.withUnsafeMutableBytes { bytes in
            let muestras = bytes.bindMemory(to: Int16.self)
            for indice in muestras.indices { muestras[indice] = Int16.max.littleEndian }
        }
        return HistoryWriter.wavData(pcm: pcm)
    }
}
