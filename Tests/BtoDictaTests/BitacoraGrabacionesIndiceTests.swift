import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import BtoDicta

/// Fixtures sintéticos y bases propias: no se usa el índice compartido, no se
/// ejecutan motores, OCR, purgas ni cambios de configuración. Las carpetas de
/// cada prueba son nuevas y permanecen disponibles como evidencia temporal.
final class BitacoraGrabacionesIndiceTests: XCTestCase {

    func testFechaDeHuerfanosConservaHoraConNombresAnterioresYSufijosNuevos() throws {
        let indice = ContinuoIndice()
        let anterior = try XCTUnwrap(indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/10/06/audio/09-14-25.pcm")))
        let nuevo = indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/10/06/sistema/09-14-25-1234abcd.pcm"))
        let pantalla = indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/10/06/pantalla/09-14-25-m2-1234abcd.png"))
        XCTAssertEqual(nuevo, anterior)
        XCTAssertEqual(pantalla, anterior)
        let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: anterior)
        XCTAssertEqual(partes.year, 2026)
        XCTAssertEqual(partes.month, 10)
        XCTAssertEqual(partes.day, 6)
        XCTAssertEqual(partes.hour, 9)
        XCTAssertEqual(partes.minute, 14)
        XCTAssertEqual(partes.second, 25)
        XCTAssertNil(indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/10/06/audio/99-14-25-1234abcd.pcm")))
        XCTAssertNil(indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/02/30/audio/09-14-25-1234abcd.pcm")))
        XCTAssertNil(indice.fechaDe(URL(fileURLWithPath: "/fixture/2026/10/06/audio/09-14-25invalido.pcm")))
    }

    func testMigracionAditivaRepetidaConservaFilasFtsYArchivos() throws {
        let carpeta = try carpetaTemporal()
        let audio = carpeta.appendingPathComponent("audio-original.pcm")
        let pantalla = carpeta.appendingPathComponent("pantalla-original.png")
        try Data([1, 3, 5, 7, 9]).write(to: audio)
        try Data("imagen sintética de prueba".utf8).write(to: pantalla)
        try crearEsquemaAnterior(en: carpeta, audio: audio, pantalla: pantalla)

        let consultas = [
            "SELECT id, instante, ruta, duracion, bytes, origen, procesado, texto FROM audio ORDER BY id;",
            "SELECT id, instante, ruta, bytes, app, ventana, monitor, procesado, texto FROM pantalla ORDER BY id;",
            "SELECT rowid, texto, fila FROM audio_texto ORDER BY rowid;",
            "SELECT rowid, texto, fila FROM pantalla_texto ORDER BY rowid;",
            "SELECT name, seq FROM sqlite_sequence ORDER BY name;"
        ]
        let antes = try consultas.map { try filas($0, en: carpeta) }
        let huellas = try [audio, pantalla].map(huella)
        let indice = ContinuoIndice()
        defer { indice.cerrar() }

        for _ in 0..<3 {
            indice.abrir(carpeta: carpeta)
            XCTAssertEqual(try consultas.map { try filas($0, en: carpeta) }, antes)
            XCTAssertEqual(try [audio, pantalla].map(huella), huellas)
            for tabla in ["audio", "pantalla"] {
                let columnas = try filas("PRAGMA table_info(\(tabla));", en: carpeta)
                XCTAssertEqual(columnas.filter { $0[1] == "sesion" }.count, 1)
                XCTAssertEqual(try filas("SELECT DISTINCT COALESCE(sesion, '') FROM \(tabla);", en: carpeta), [[""]])
            }
            XCTAssertTrue(indice.pendientes(material: .audio, soloGrabaciones: true).isEmpty)
            XCTAssertTrue(indice.pendientes(material: .pantalla, soloGrabaciones: true).isEmpty)
            XCTAssertEqual(indice.pendientes(material: .audio).map(\.id), [12],
                           "el dictado anterior sin transcripción sigue pendiente y sin reclasificar")
            XCTAssertEqual(indice.pendientes(material: .pantalla).map(\.id), [22])
            XCTAssertEqual(try filas("SELECT fila FROM audio_texto WHERE audio_texto MATCH 'cafe';", en: carpeta), [["11"]])
            XCTAssertEqual(try filas("SELECT fila FROM pantalla_texto WHERE pantalla_texto MATCH 'informe';", en: carpeta), [["21"]])
            indice.cerrar()
        }
    }

    func testFiltroDeSesionYCanalVaAntesDelLimiteDelLote() throws {
        let carpeta = try carpetaTemporal()
        let indice = ContinuoIndice()
        indice.abrir(carpeta: carpeta)
        defer { indice.cerrar() }
        let instante = Date(timeIntervalSince1970: 1_000)
        for n in 0..<12 {
            _ = indice.registrarAudio(ruta: carpeta.appendingPathComponent("ambiente-\(n).pcm"),
                                      instante: instante.addingTimeInterval(Double(n)), duracion: 1,
                                      origen: n.isMultiple(of: 2) ? "continuo" : "sistema")
            _ = indice.registrarPantalla(ruta: carpeta.appendingPathComponent("ambiente-\(n).png"),
                                         instante: instante.addingTimeInterval(Double(n)),
                                         app: "Editor", ventana: "Ejemplo", monitor: 0)
        }
        let voz = try XCTUnwrap(indice.registrarAudio(ruta: carpeta.appendingPathComponent("voz.pcm"),
                                                     instante: instante.addingTimeInterval(30), duracion: 1,
                                                     origen: "dictado", sesion: "grabacion-a"))
        let sistema = try XCTUnwrap(indice.registrarAudio(ruta: carpeta.appendingPathComponent("sistema.pcm"),
                                                         instante: instante.addingTimeInterval(31), duracion: 1,
                                                         origen: "sistema", sesion: "grabacion-b"))
        let pantalla = try XCTUnwrap(indice.registrarPantalla(ruta: carpeta.appendingPathComponent("grabacion.png"),
                                                             instante: instante.addingTimeInterval(32),
                                                             app: "Editor", ventana: nil, monitor: 0,
                                                             sesion: "grabacion-b"))

        XCTAssertEqual(indice.pendientes(material: .audio, limite: 1, soloGrabaciones: true).map(\.id), [voz])
        XCTAssertEqual(indice.pendientes(material: .audio, limite: 1, canal: "sistema", soloGrabaciones: true).map(\.id), [sistema])
        XCTAssertEqual(indice.pendientes(material: .audio, limite: 1, canal: "voz", soloGrabaciones: true).map(\.id), [voz])
        XCTAssertEqual(indice.pendientes(material: .pantalla, limite: 1, soloGrabaciones: true).map(\.id), [pantalla])
        XCTAssertEqual(indice.pendientes(material: .audio, soloGrabaciones: true).map(\.sesion), ["grabacion-a", "grabacion-b"])
        XCTAssertEqual(indice.pendientes(material: .audio).count, 14, "filtrar no consume el backlog")
        XCTAssertEqual(indice.pendientes(material: .pantalla).count, 13)
    }

    func testSeleccionManualIncluyeBacklogYAutomaticaConservaSuProcedencia() throws {
        let carpeta = try carpetaTemporal()
        let indice = ContinuoIndice()
        indice.abrir(carpeta: carpeta)
        defer { indice.cerrar() }
        let ruta = carpeta.appendingPathComponent("ambiental.pcm")
        let ambiental = try XCTUnwrap(indice.registrarAudio(ruta: ruta,
                                                          instante: Date(timeIntervalSince1970: 10), duracion: 1))
        let autorizado = try XCTUnwrap(indice.registrarAudio(ruta: carpeta.appendingPathComponent("autorizado.pcm"),
                                                            instante: Date(timeIntervalSince1970: 20), duracion: 1,
                                                            origen: "sistema", sesion: "grabacion-c"))
        func seleccionar(manual: Bool, soloGrabaciones: Bool) -> [Int64] {
            ContinuoLote.pendientesDeAudio(en: indice, manual: manual, limite: 1,
                                           soloGrabaciones: soloGrabaciones).map(\.id)
        }
        XCTAssertEqual(seleccionar(manual: false, soloGrabaciones: true), [autorizado])
        XCTAssertEqual(seleccionar(manual: true, soloGrabaciones: true), [ambiental])
        XCTAssertEqual(seleccionar(manual: false, soloGrabaciones: false), [ambiental])
        XCTAssertTrue(ContinuoLote.pendientesDeAudio(en: indice, manual: true, canal: "pantalla", limite: 1,
                                                    soloGrabaciones: true).isEmpty)

        // Reingresar una ruta ya ambiental durante otra grabación no puede
        // cambiar a posteriori la autorización de su contenido original.
        _ = indice.registrarAudio(ruta: ruta, instante: Date(), duracion: 99,
                                  origen: "dictado", sesion: "grabacion-posterior")
        indice.cerrar()
        indice.abrir(carpeta: carpeta)
        XCTAssertEqual(seleccionar(manual: false, soloGrabaciones: true), [autorizado])
        let primero = try XCTUnwrap(indice.pendientes(material: .audio).first)
        XCTAssertEqual(primero.id, ambiental)
        XCTAssertNil(primero.sesion)
        XCTAssertEqual(try filas("SELECT origen, duracion, sesion FROM audio WHERE id = \(ambiental);", en: carpeta),
                       [["continuo", "1.0", ""]])
    }

    func testDictadoTranscritoNoSeRepiteYElHistorialConservaTodosLosOrigenes() throws {
        let carpeta = try carpetaTemporal()
        let indice = ContinuoIndice()
        indice.abrir(carpeta: carpeta)
        defer { indice.cerrar() }
        let instante = Date(timeIntervalSince1970: 2_000)
        let dictado = try XCTUnwrap(indice.registrarAudio(ruta: carpeta.appendingPathComponent("dictado.wav"),
                                                        instante: instante, duracion: 1,
                                                        origen: "dictado", sesion: "grabacion-d"))
        indice.anotarTexto("texto dictado disponible", material: .audio, id: dictado)
        let anterior = try XCTUnwrap(indice.registrarAudio(ruta: carpeta.appendingPathComponent("anterior.pcm"),
                                                         instante: instante.addingTimeInterval(-1), duracion: 1))
        indice.anotarTexto("texto ambiental conservado", material: .audio, id: anterior)
        XCTAssertTrue(indice.anotarTextoDeNavegador(texto: "texto de página autorizado",
                                                   url: "https://example.com/prueba", titulo: "Ejemplo", app: "Navegador",
                                                   instante: instante.addingTimeInterval(1), sesion: "grabacion-d"))
        XCTAssertTrue(indice.pendientes(material: .audio, soloGrabaciones: true).isEmpty,
                      "la transcripción adoptada no vuelve a solicitar STT")
        XCTAssertTrue(indice.pendientes(material: .pantalla, soloGrabaciones: true).isEmpty,
                      "el navegador ya aporta su texto, no debe pedir OCR")
        XCTAssertEqual(indice.materialEntre(desde: instante.addingTimeInterval(-5),
                                           hasta: instante.addingTimeInterval(5), incluirPantalla: true).map(\.texto),
                       ["texto ambiental conservado", "texto dictado disponible", "texto de página autorizado"])
        XCTAssertEqual(try filas("SELECT sesion, procesado FROM pantalla;", en: carpeta), [["grabacion-d", "1"]])
        XCTAssertEqual(try filas("SELECT fila FROM audio_texto WHERE audio_texto MATCH 'dictado';", en: carpeta), [[String(dictado)]])
    }

    func testPoliticaSeReevaluaEntreSolicitudesSinAutorizarPorOrigen() {
        let sesiones: [String?] = [nil, "", "   "]
        for sesion in sesiones {
            XCTAssertFalse(ContinuoLote.permiteProcesar(sesion: sesion, manual: false, soloGrabaciones: true))
            XCTAssertTrue(ContinuoLote.permiteProcesar(sesion: sesion, manual: true, soloGrabaciones: true))
            XCTAssertTrue(ContinuoLote.permiteProcesar(sesion: sesion, manual: false, soloGrabaciones: false))
        }
        XCTAssertTrue(ContinuoLote.permiteProcesar(sesion: "grabacion-e", manual: false, soloGrabaciones: true))
        var modo = false
        let permitirSolicitud = { ContinuoLote.permiteProcesar(sesion: nil, manual: false, soloGrabaciones: modo) }
        XCTAssertTrue(permitirSolicitud())
        modo = true
        XCTAssertFalse(permitirSolicitud(), "el mismo pendiente no autoriza otra petición tras el cambio de modo")
    }

    private func carpetaTemporal() throws -> URL {
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-indice-013-\(UUID().uuidString)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: carpeta.path))
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: false)
        return carpeta
    }

    private func huella(_ ruta: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: ruta)).map { String(format: "%02x", $0) }.joined()
    }

    private func crearEsquemaAnterior(en carpeta: URL, audio: URL, pantalla: URL) throws {
        try conBase(en: carpeta, escritura: true) { db in
            let sql = """
            CREATE TABLE audio (id INTEGER PRIMARY KEY AUTOINCREMENT, instante REAL NOT NULL,
              ruta TEXT NOT NULL UNIQUE, duracion REAL NOT NULL DEFAULT 0, bytes INTEGER NOT NULL DEFAULT 0,
              origen TEXT NOT NULL DEFAULT 'continuo', procesado INTEGER NOT NULL DEFAULT 0, texto TEXT);
            CREATE TABLE pantalla (id INTEGER PRIMARY KEY AUTOINCREMENT, instante REAL NOT NULL,
              ruta TEXT NOT NULL UNIQUE, bytes INTEGER NOT NULL DEFAULT 0, app TEXT, ventana TEXT,
              monitor INTEGER NOT NULL DEFAULT 0, procesado INTEGER NOT NULL DEFAULT 0, texto TEXT);
            CREATE VIRTUAL TABLE audio_texto USING fts5(texto, fila UNINDEXED, tokenize='unicode61 remove_diacritics 2');
            CREATE VIRTUAL TABLE pantalla_texto USING fts5(texto, fila UNINDEXED, tokenize='unicode61 remove_diacritics 2');
            INSERT INTO audio VALUES (11, 1000, '\(literal(audio.path))', 2.5, 5, 'continuo', 1, 'Café de prueba');
            INSERT INTO audio VALUES (12, 1001, 'pendiente-anterior.wav', 3, 7, 'dictado', 0, NULL);
            INSERT INTO pantalla VALUES (21, 1002, '\(literal(pantalla.path))', 26, 'Editor', 'Muestra', 1, 1, 'Informe de muestra');
            INSERT INTO pantalla VALUES (22, 1003, 'pendiente-anterior.png', 9, 'Editor', NULL, 0, 0, NULL);
            INSERT INTO audio_texto(rowid, texto, fila) VALUES (81, 'Café de prueba', 11);
            INSERT INTO pantalla_texto(rowid, texto, fila) VALUES (91, 'Informe de muestra', 21);
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error(db) }
        }
    }

    private func filas(_ sql: String, en carpeta: URL) throws -> [[String]] {
        try conBase(en: carpeta, escritura: false) { db in
            var sentencia: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &sentencia, nil) == SQLITE_OK else { throw error(db) }
            defer { sqlite3_finalize(sentencia) }
            var resultado: [[String]] = []
            var estado = sqlite3_step(sentencia)
            while estado == SQLITE_ROW {
                resultado.append((0..<sqlite3_column_count(sentencia)).map { columna in
                    sqlite3_column_text(sentencia, columna).map { String(cString: $0) } ?? "<nulo>"
                })
                estado = sqlite3_step(sentencia)
            }
            guard estado == SQLITE_DONE else { throw error(db) }
            return resultado
        }
    }

    private func conBase<T>(en carpeta: URL, escritura: Bool, _ cuerpo: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = escritura ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(carpeta.appendingPathComponent("bitacora.sqlite").path, &db, flags, nil) == SQLITE_OK,
              let base = db else {
            if let db { sqlite3_close_v2(db) }
            throw NSError(domain: "BitacoraGrabacionesIndiceTests", code: 1)
        }
        defer { sqlite3_close_v2(base) }
        return try cuerpo(base)
    }

    private func literal(_ valor: String) -> String { valor.replacingOccurrences(of: "'", with: "''") }

    private func error(_ db: OpaquePointer) -> NSError {
        NSError(domain: "BitacoraGrabacionesIndiceTests", code: Int(sqlite3_errcode(db)),
                userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
    }
}
