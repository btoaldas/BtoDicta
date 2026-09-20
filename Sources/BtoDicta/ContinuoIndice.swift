import Foundation
import SQLite3

// MARK: - Índice de la bitácora continua
//
// Una base SQLite pequeña que sabe QUÉ se grabó, CUÁNDO y si ya se procesó.
// Los archivos pesados (audio y capturas) viven en disco; aquí solo van rutas,
// marcas de tiempo y el texto extraído.
//
// Sin dependencias: `import SQLite3` usa la biblioteca que ya trae macOS
// (3.51.0, con FTS5). Package.swift no se toca.
//
// Todo el acceso pasa por una cola serie: SQLite en modo WAL aguanta varios
// lectores, pero serializar aquí evita razonar sobre concurrencia en cada sitio.

/// Qué clase de material guarda una fila.
enum MaterialContinuo: String {
    case audio
    case pantalla
}

/// Una fila pendiente de procesar (transcribir u OCR).
struct PendienteContinuo {
    let id: Int64
    let material: MaterialContinuo
    let ruta: URL
    let instante: Date
}

/// Resumen de lo que ocuparía una purga, para poder avisar ANTES de borrar.
struct BalancePurga {
    let filas: Int
    let sinProcesar: Int
    let bytes: Int64

    var hayMaterialSinProcesar: Bool { sinProcesar > 0 }
}

final class ContinuoIndice {

    static let shared = ContinuoIndice()

    private var db: OpaquePointer?
    private let cola = DispatchQueue(label: "btodicta.continuo.indice")

    private init() {}

    // MARK: Apertura

    /// Abre (y crea si hace falta) la base dentro de la carpeta de la bitácora.
    /// Idempotente: llamarla dos veces no hace daño.
    func abrir() {
        cola.sync {
            guard db == nil else { return }
            let carpeta = Config.continuoCarpeta()
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            let ruta = carpeta.appendingPathComponent("bitacora.sqlite")

            // Permisos ANTES del primer PRAGMA: los archivos -wal y -shm heredan
            // el modo del principal, así que fijarlo después llega tarde.
            if !FileManager.default.fileExists(atPath: ruta.path) {
                FileManager.default.createFile(atPath: ruta.path, contents: nil,
                                               attributes: [.posixPermissions: 0o600])
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ruta.path)

            var puntero: OpaquePointer?
            guard sqlite3_open_v2(ruta.path, &puntero,
                                  SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                                  nil) == SQLITE_OK else {
                Log.log(.sistema, "bitácora: no pude abrir el índice en \(ruta.path)")
                return
            }
            db = puntero
            ejecutar("PRAGMA journal_mode=WAL;")
            ejecutar("PRAGMA synchronous=NORMAL;")
            ejecutar("PRAGMA busy_timeout=5000;")
            crearEsquema()
            Log.log(.sistema, "bitácora: índice abierto en \(ruta.path)")
        }
    }

    func cerrar() {
        cola.sync {
            guard let d = db else { return }
            sqlite3_close_v2(d)
            db = nil
        }
    }

    // MARK: Esquema

    private func crearEsquema() {
        // Dos tablas de contenido y DOS tablas de texto completo separadas.
        // Una sola FTS compartida obligaría a inventar un rowid único entre
        // ambas y colisionaría: más barato tener una por material.
        ejecutar("""
        CREATE TABLE IF NOT EXISTS audio (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            instante   REAL NOT NULL,
            ruta       TEXT NOT NULL UNIQUE,
            duracion   REAL NOT NULL DEFAULT 0,
            bytes      INTEGER NOT NULL DEFAULT 0,
            origen     TEXT NOT NULL DEFAULT 'continuo',
            procesado  INTEGER NOT NULL DEFAULT 0,
            texto      TEXT
        );
        """)
        ejecutar("CREATE INDEX IF NOT EXISTS audio_instante ON audio(instante);")
        ejecutar("CREATE INDEX IF NOT EXISTS audio_pendiente ON audio(procesado, instante);")

        ejecutar("""
        CREATE TABLE IF NOT EXISTS pantalla (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            instante   REAL NOT NULL,
            ruta       TEXT NOT NULL UNIQUE,
            bytes      INTEGER NOT NULL DEFAULT 0,
            app        TEXT,
            ventana    TEXT,
            monitor    INTEGER NOT NULL DEFAULT 0,
            procesado  INTEGER NOT NULL DEFAULT 0,
            texto      TEXT
        );
        """)
        ejecutar("CREATE INDEX IF NOT EXISTS pantalla_instante ON pantalla(instante);")
        // Migración suave: bases creadas antes de que existiera la columna.
        if !columnaExiste("pantalla", "visibles") {
            ejecutar("ALTER TABLE pantalla ADD COLUMN visibles TEXT;")
        }
        ejecutar("CREATE INDEX IF NOT EXISTS pantalla_pendiente ON pantalla(procesado, instante);")

        ejecutar("""
        CREATE VIRTUAL TABLE IF NOT EXISTS audio_texto
        USING fts5(texto, fila UNINDEXED, tokenize='unicode61 remove_diacritics 2');
        """)
        ejecutar("""
        CREATE VIRTUAL TABLE IF NOT EXISTS pantalla_texto
        USING fts5(texto, fila UNINDEXED, tokenize='unicode61 remove_diacritics 2');
        """)
    }

    // MARK: Altas

    /// Registra un fragmento de audio recién cerrado. `origen` distingue lo que
    /// grabó la bitácora de lo que adoptó del dictado.
    @discardableResult
    func registrarAudio(ruta: URL, instante: Date, duracion: TimeInterval, origen: String = "continuo") -> Int64? {
        let bytes = tamano(de: ruta)
        return cola.sync {
            guard let d = db else { return nil }
            var st: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO audio (instante, ruta, duracion, bytes, origen)
            VALUES (?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, instante.timeIntervalSince1970)
            bindTexto(st, 2, ruta.path)
            sqlite3_bind_double(st, 3, duracion)
            sqlite3_bind_int64(st, 4, bytes)
            bindTexto(st, 5, origen)
            guard sqlite3_step(st) == SQLITE_DONE else { return nil }
            return sqlite3_last_insert_rowid(d)
        }
    }

    /// Registra una captura de pantalla ya escrita en disco.
    @discardableResult
    func registrarPantalla(ruta: URL, instante: Date, app: String?, ventana: String?,
                           monitor: Int, visibles: [String] = []) -> Int64? {
        let bytes = tamano(de: ruta)
        return cola.sync {
            guard let d = db else { return nil }
            var st: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO pantalla (instante, ruta, bytes, app, ventana, monitor, visibles)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, instante.timeIntervalSince1970)
            bindTexto(st, 2, ruta.path)
            sqlite3_bind_int64(st, 3, bytes)
            bindTexto(st, 4, app ?? "")
            bindTexto(st, 5, ventana ?? "")
            sqlite3_bind_int(st, 6, Int32(monitor))
            bindTexto(st, 7, visibles.joined(separator: ", "))
            guard sqlite3_step(st) == SQLITE_DONE else { return nil }
            return sqlite3_last_insert_rowid(d)
        }
    }

    // MARK: Marcado de procesado

    /// Guarda el texto extraído y marca la fila como procesada.
    /// Guarda el texto de una página que envió la extensión (spec 006, RF-02).
    ///
    /// Se registra como material de pantalla —es lo que se estaba viendo— pero
    /// **con su texto ya escrito**, sin archivo de imagen. Eso lo deja fuera del
    /// alcance del OCR, que solo recoge lo que llega sin texto, y ahorra el
    /// reconocimiento de imagen entero: leer una página deja de costar lo que
    /// cuesta mirar una foto de ella.
    ///
    /// Devuelve `true` si quedó anotado.
    @discardableResult
    func anotarTextoDeNavegador(texto: String, url: String, titulo: String,
                                app: String, instante: Date) -> Bool {
        cola.sync {
            guard let d = db else { return false }
            var st: OpaquePointer?
            // `ruta` lleva la dirección en vez de un archivo: no hay imagen que
            // guardar, y así la línea de tiempo sigue pudiendo decir de dónde
            // salió cada cosa.
            let sql = """
            INSERT INTO pantalla (instante, ruta, bytes, app, ventana, monitor, visibles, texto, procesado)
            VALUES (?, ?, 0, ?, ?, 0, '', ?, 1);
            """
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(st) }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_double(st, 1, instante.timeIntervalSince1970)
            sqlite3_bind_text(st, 2, url, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 3, app, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 4, titulo, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(st, 5, texto, -1, SQLITE_TRANSIENT)
            return sqlite3_step(st) == SQLITE_DONE
        }
    }

    func anotarTexto(_ texto: String, material: MaterialContinuo, id: Int64) {
        cola.sync {
            guard let d = db else { return }
            let tabla = material.rawValue
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(d, "UPDATE \(tabla) SET texto = ?, procesado = 1 WHERE id = ?;", -1, &st, nil) == SQLITE_OK else { return }
            bindTexto(st, 1, texto)
            sqlite3_bind_int64(st, 2, id)
            sqlite3_step(st)
            sqlite3_finalize(st)

            guard !texto.isEmpty else { return }
            var ft: OpaquePointer?
            guard sqlite3_prepare_v2(d, "INSERT INTO \(tabla)_texto (texto, fila) VALUES (?, ?);", -1, &ft, nil) == SQLITE_OK else { return }
            bindTexto(ft, 1, texto)
            sqlite3_bind_int64(ft, 2, id)
            sqlite3_step(ft)
            sqlite3_finalize(ft)
        }
    }

    /// Cambia la ruta de una fila tras comprimir el archivo, conservando su
    /// texto y su marca de procesado. Devuelve false si el índice no quedó
    /// actualizado (base cerrada, fila inexistente, base ocupada): quien
    /// comprime NO debe soltar el crudo en ese caso.
    @discardableResult
    func reemplazarRuta(id: Int64, material: MaterialContinuo, por url: URL, bytes: Int64) -> Bool {
        cola.sync {
            guard let d = db else { return false }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(d, "UPDATE \(material.rawValue) SET ruta = ?, bytes = ? WHERE id = ?;", -1, &st, nil) == SQLITE_OK else { return false }
            defer { sqlite3_finalize(st) }
            bindTexto(st, 1, url.path)
            sqlite3_bind_int64(st, 2, bytes)
            sqlite3_bind_int64(st, 3, id)
            return sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(d) == 1
        }
    }

    /// Lo que falta por transcribir o reconocer, de lo más viejo a lo más nuevo.
    /// `canal` (solo audio): "sistema" trae únicamente el audio del sistema;
    /// "voz" el resto (micrófono y dictados adoptados). El filtro va en el SQL,
    /// ANTES del límite: filtrar después de cortar dejaba tandas vacías cuando
    /// los fragmentos más viejos eran mayoritariamente del otro canal.
    func pendientes(material: MaterialContinuo, limite: Int = 500,
                    canal: String? = nil) -> [PendienteContinuo] {
        cola.sync {
            guard let d = db else { return [] }
            var st: OpaquePointer?
            var filtro = ""
            if material == .audio {
                if canal == "sistema" { filtro = "AND origen = 'sistema' " }
                else if canal == "voz" { filtro = "AND origen != 'sistema' " }
            }
            let sql = "SELECT id, ruta, instante FROM \(material.rawValue) WHERE procesado = 0 \(filtro)ORDER BY instante ASC LIMIT ?;"
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int(st, 1, Int32(limite))
            var salida: [PendienteContinuo] = []
            while sqlite3_step(st) == SQLITE_ROW {
                guard let c = sqlite3_column_text(st, 1) else { continue }
                salida.append(PendienteContinuo(
                    id: sqlite3_column_int64(st, 0),
                    material: material,
                    ruta: URL(fileURLWithPath: String(cString: c)),
                    instante: Date(timeIntervalSince1970: sqlite3_column_double(st, 2))
                ))
            }
            return salida
        }
    }

    /// Audio ya transcrito que sigue en PCM crudo dentro de la carpeta de la
    /// bitácora: candidatos a recompresión, de lo más viejo a lo más nuevo.
    /// Fuera de la carpeta (archivos adoptados del historial) no se toca nada.
    func audiosCrudosProcesados(limite: Int, carpeta: URL) -> [PendienteContinuo] {
        cola.sync {
            guard let d = db else { return [] }
            var st: OpaquePointer?
            let sql = "SELECT id, ruta, instante FROM audio WHERE procesado = 1 AND ruta LIKE ? AND ruta LIKE '%.pcm' ORDER BY instante ASC LIMIT ?;"
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            bindTexto(st, 1, carpeta.path + "/%")
            sqlite3_bind_int(st, 2, Int32(max(1, limite)))
            var salida: [PendienteContinuo] = []
            while sqlite3_step(st) == SQLITE_ROW {
                guard let c = sqlite3_column_text(st, 1) else { continue }
                salida.append(PendienteContinuo(
                    id: sqlite3_column_int64(st, 0),
                    material: .audio,
                    ruta: URL(fileURLWithPath: String(cString: c)),
                    instante: Date(timeIntervalSince1970: sqlite3_column_double(st, 2))
                ))
            }
            return salida
        }
    }

    /// Una pieza del día para armar el resumen.
    struct PiezaDia {
        let instante: Date
        let material: MaterialContinuo
        /// Audio: origen (continuo/dictado/sistema). Pantalla: app activa.
        let fuente: String
        /// Solo pantalla: las demás aplicaciones a la vista en ese momento.
        let visibles: String
        let texto: String
    }

    /// Todo lo registrado de un día, en orden, ya filtrado de vacíos.
    func materialDelDia(_ dia: Date, incluirPantalla: Bool) -> [PiezaDia] {
        let inicio = Calendar.current.startOfDay(for: dia)
        return materialEntre(desde: inicio, hasta: inicio.addingTimeInterval(86_400),
                             incluirPantalla: incluirPantalla)
    }

    /// Material en un rango arbitrario: es lo que usan las rutinas de «últimas
    /// N horas», que pueden cruzar la medianoche sin perder el tramo anterior.
    func materialEntre(desde inicioRango: Date, hasta finRango: Date,
                       incluirPantalla: Bool) -> [PiezaDia] {
        let desde = inicioRango.timeIntervalSince1970
        let hasta = finRango.timeIntervalSince1970
        return cola.sync {
            guard let d = db else { return [] }
            var salida: [PiezaDia] = []
            var tablas: [(String, MaterialContinuo)] = [("audio", .audio)]
            if incluirPantalla { tablas.append(("pantalla", .pantalla)) }
            for (tabla, material) in tablas {
                let campos = tabla == "pantalla"
                    ? "COALESCE(app,''), COALESCE(visibles,'')"
                    : "origen, ''"
                let sql = """
                SELECT instante, \(campos), texto FROM \(tabla)
                WHERE instante >= ? AND instante < ?
                  AND texto IS NOT NULL AND length(trim(texto)) > 0
                ORDER BY instante ASC;
                """
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { continue }
                sqlite3_bind_double(st, 1, desde)
                sqlite3_bind_double(st, 2, hasta)
                while sqlite3_step(st) == SQLITE_ROW {
                    salida.append(PiezaDia(
                        instante: Date(timeIntervalSince1970: sqlite3_column_double(st, 0)),
                        material: material,
                        fuente: sqlite3_column_text(st, 1).map { String(cString: $0) } ?? "",
                        visibles: sqlite3_column_text(st, 2).map { String(cString: $0) } ?? "",
                        texto: sqlite3_column_text(st, 3).map { String(cString: $0) } ?? ""
                    ))
                }
                sqlite3_finalize(st)
            }
            return salida.sorted { $0.instante < $1.instante }
        }
    }

    /// Elemento para el explorador de la pestaña.
    struct ElementoReciente: Identifiable {
        let id: Int64
        let ruta: URL
        let instante: Date
        /// Audio: origen. Pantalla: app activa.
        let fuente: String
        let texto: String
        let duracion: Double
    }

    /// Los últimos elementos de un material, más nuevos primero. Para navegar
    /// lo guardado sin salir de la app.
    func recientes(material: MaterialContinuo, limite: Int = 60) -> [ElementoReciente] {
        cola.sync {
            guard let d = db else { return [] }
            let campos = material == .audio
                ? "id, ruta, instante, origen, COALESCE(texto,''), duracion"
                : "id, ruta, instante, COALESCE(app,''), COALESCE(texto,''), 0"
            var st: OpaquePointer?
            let sql = "SELECT \(campos) FROM \(material.rawValue) ORDER BY instante DESC LIMIT ?;"
            guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_int(st, 1, Int32(limite))
            var salida: [ElementoReciente] = []
            while sqlite3_step(st) == SQLITE_ROW {
                guard let r = sqlite3_column_text(st, 1) else { continue }
                salida.append(ElementoReciente(
                    id: sqlite3_column_int64(st, 0),
                    ruta: URL(fileURLWithPath: String(cString: r)),
                    instante: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
                    fuente: sqlite3_column_text(st, 3).map { String(cString: $0) } ?? "",
                    texto: sqlite3_column_text(st, 4).map { String(cString: $0) } ?? "",
                    duracion: sqlite3_column_double(st, 5)
                ))
            }
            return salida
        }
    }

    private func columnaExiste(_ tabla: String, _ columna: String) -> Bool {
        guard let d = db else { return true }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(d, "PRAGMA table_info(\(tabla));", -1, &st, nil) == SQLITE_OK else { return true }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            if let c = sqlite3_column_text(st, 1), String(cString: c) == columna { return true }
        }
        return false
    }

    /// Registra los archivos que están en disco pero no en el índice.
    ///
    /// Pasa siempre que la aplicación termina de golpe: el fragmento que estaba
    /// abierto nunca llega a registrarse y queda invisible aunque el audio esté
    /// entero. Sin esto, la promesa de «lo grabado sobrevive a cualquier corte»
    /// se cumple a medias: el archivo sobrevive, pero nadie vuelve a mirarlo.
    @discardableResult
    func rescatarHuerfanos() -> Int {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return 0 }
        var rescatados = 0
        var migajas = 0
        var enCurso = 0
        let fm = FileManager.default
        for caso in e {
            guard let url = caso as? URL else { continue }
            let ext = url.pathExtension.lowercased()
            let carpeta = url.deletingLastPathComponent().lastPathComponent

            let material: MaterialContinuo
            if ["pcm", "m4a", "wav"].contains(ext), ["audio", "sistema"].contains(carpeta) {
                material = .audio
            } else if ["jpg", "jpeg", "heic", "png"].contains(ext), carpeta == "pantalla" {
                material = .pantalla
            } else {
                continue
            }
            guard !contiene(ruta: url.path, material: material) else { continue }

            // El instante se reconstruye del nombre HH-mm-ss dentro de la
            // carpeta aaaa/MM/dd; si no cuadra, se usa la fecha del archivo.
            let instante = fechaDe(url) ?? ((try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil) ?? Date()
            let bytes = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0

            // Migajas: menos de medio segundo de audio. No tienen contenido que
            // transcribir, así que no entran al índice — y por eso ANTES se
            // quedaban en disco para siempre, porque la purga solo borra lo que
            // está indexado. Se retiran aquí, que es donde se descubren.
            if bytes <= 16_000 {
                if bytes == 0 || material == .audio {
                    try? fm.removeItem(at: url)
                    migajas += 1
                }
                continue
            }

            // El trozo que se está grabando AHORA MISMO no se toca. Indexarlo a
            // medio escribir lo deja con una duración y un tamaño que no son los
            // definitivos, y esos metadatos provisionales se quedan: el archivo
            // ya consta, así que nadie vuelve a mirarlo. La bitácora cierra sus
            // trozos cada pocos minutos; con un minuto de margen basta para no
            // pillar ninguno a medias.
            let modificado = ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
            guard Date().timeIntervalSince(modificado) > 60 else { enCurso += 1; continue }

            if material == .audio {
                let duracion = ext == "pcm" ? Double(bytes) / 32_000.0 : 0
                registrarAudio(ruta: url, instante: instante, duracion: duracion,
                               origen: carpeta == "sistema" ? "sistema" : "continuo")
            } else {
                registrarPantalla(ruta: url, instante: instante, app: nil, ventana: nil, monitor: 0)
            }
            rescatados += 1
        }
        if migajas > 0 {
            Log.log(.sistema, "bitácora: retiradas \(migajas) migajas de audio de menos de medio segundo — no se pueden transcribir y no las alcanzaba la limpieza")
        }
        if enCurso > 0 {
            Log.debug("bitácora: \(enCurso) archivos aún en escritura — se indexarán cuando se cierren")
        }
        if rescatados > 0 {
            Log.log(.sistema, "bitácora: \(rescatados) archivos huérfanos incorporados al índice")
        }
        return rescatados
    }

    private func contiene(ruta: String, material: MaterialContinuo) -> Bool {
        cola.sync {
            guard let d = db else { return true }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(d, "SELECT 1 FROM \(material.rawValue) WHERE ruta = ? LIMIT 1;", -1, &st, nil) == SQLITE_OK else { return true }
            defer { sqlite3_finalize(st) }
            bindTexto(st, 1, ruta)
            return sqlite3_step(st) == SQLITE_ROW
        }
    }

    /// aaaa/MM/dd/<sub>/HH-mm-ss.ext → fecha completa.
    private func fechaDe(_ url: URL) -> Date? {
        let partes = url.pathComponents
        guard partes.count >= 5 else { return nil }
        let dia = partes[partes.count - 2 - 1]
        let mes = partes[partes.count - 3 - 1]
        let anio = partes[partes.count - 4 - 1]
        let hora = url.deletingPathExtension().lastPathComponent
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH-mm-ss"
        return f.date(from: "\(anio)/\(mes)/\(dia) \(hora)")
    }

    // MARK: Retención

    /// Qué se llevaría por delante una purga anterior a `limite`, y cuánto de
    /// eso todavía no se ha procesado. Se consulta ANTES de borrar nada.
    func balanceAnteriorA(_ limite: Date) -> BalancePurga {
        cola.sync {
            guard let d = db else { return BalancePurga(filas: 0, sinProcesar: 0, bytes: 0) }
            var filas = 0, sinProcesar = 0
            var bytes: Int64 = 0
            for tabla in ["audio", "pantalla"] {
                var st: OpaquePointer?
                let sql = """
                SELECT COUNT(*), COALESCE(SUM(bytes), 0), COALESCE(SUM(CASE WHEN procesado = 0 THEN 1 ELSE 0 END), 0)
                FROM \(tabla) WHERE instante < ?;
                """
                guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { continue }
                sqlite3_bind_double(st, 1, limite.timeIntervalSince1970)
                if sqlite3_step(st) == SQLITE_ROW {
                    filas += Int(sqlite3_column_int(st, 0))
                    bytes += sqlite3_column_int64(st, 1)
                    sinProcesar += Int(sqlite3_column_int(st, 2))
                }
                sqlite3_finalize(st)
            }
            return BalancePurga(filas: filas, sinProcesar: sinProcesar, bytes: bytes)
        }
    }

    /// Borra archivos y filas anteriores a `limite`. Devuelve cuántas filas se
    /// fueron. No pregunta nada: quien llama ya decidió.
    @discardableResult
    /// Cuántas filas hay anteriores a una fecha. Solo para las pruebas.
    func contarAnterioresA(_ limite: Date) -> Int {
        var total = 0
        cola.sync {
            guard let d = db else { return }
            for tabla in ["audio", "pantalla"] {
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(d, "SELECT COUNT(*) FROM \(tabla) WHERE instante < ?;", -1, &st, nil) == SQLITE_OK else { continue }
                sqlite3_bind_double(st, 1, limite.timeIntervalSince1970)
                if sqlite3_step(st) == SQLITE_ROW { total += Int(sqlite3_column_int64(st, 0)) }
                sqlite3_finalize(st)
            }
        }
        return total
    }

    /// ¿Esta ruta sigue en el índice? Solo para las pruebas.
    func estaIndexado(ruta: String) -> Bool {
        var hay = false
        cola.sync {
            guard let d = db else { return }
            for tabla in ["audio", "pantalla"] where !hay {
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(d, "SELECT 1 FROM \(tabla) WHERE ruta = ? LIMIT 1;", -1, &st, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(st, 1, (ruta as NSString).utf8String, -1, nil)
                if sqlite3_step(st) == SQLITE_ROW { hay = true }
                sqlite3_finalize(st)
            }
        }
        return hay
    }

    func purgarAnteriorA(_ limite: Date) -> Int {
        // TRES tramos, y solo los de SQL retienen la cola. El borrado físico de
        // miles de archivos va FUERA: con él dentro, un registrarAudio desde el
        // cierre de un dictado (main) esperaba minutos y congelaba la app.
        var borradas = 0
        for tabla in ["audio", "pantalla"] {
            // 1) Leer qué cae (cola retenida milisegundos).
            var rutas: [String] = []
            var ids: [Int64] = []   // -1 marca «no se pudo borrar su archivo»
            cola.sync {
                guard let d = db else { return }
                var st: OpaquePointer?
                guard sqlite3_prepare_v2(d, "SELECT id, ruta FROM \(tabla) WHERE instante < ?;", -1, &st, nil) == SQLITE_OK else { return }
                sqlite3_bind_double(st, 1, limite.timeIntervalSince1970)
                while sqlite3_step(st) == SQLITE_ROW {
                    ids.append(sqlite3_column_int64(st, 0))
                    if let c = sqlite3_column_text(st, 1) { rutas.append(String(cString: c)) }
                }
                sqlite3_finalize(st)
            }

            // 2) Borrar archivos SIN retener la cola — y SOLO los que viven
            //    dentro de la bitácora. Un .wav adoptado del historial de
            //    dictado se des-indexa, pero JAMÁS se borra de disco: es del
            //    historial del usuario, no nuestro.
            let raiz = Config.continuoCarpeta().path
            let fm = FileManager.default
            var fallados = 0
            for r in rutas where r.hasPrefix(raiz) {
                // Si el archivo NO se puede borrar —permisos, disco lleno, un
                // volumen que se desconectó— la fila se queda: des-indexarla
                // dejaría el archivo en disco sin nadie que sepa que existe, y
                // la retención que el usuario pidió no se estaría cumpliendo
                // aunque el índice dijera que sí. Se reintenta en la próxima
                // purga, que ahora vuelve a correr sola cada pocas horas.
                if fm.fileExists(atPath: r) {
                    do { try fm.removeItem(atPath: r) }
                    catch {
                        fallados += 1
                        if let idx = rutas.firstIndex(of: r), idx < ids.count { ids[idx] = -1 }
                        continue
                    }
                }
                // El .txt hermano acompaña al audio: purgar el sonido y dejar
                // la transcripción en claro burlaría la retención.
                let txt = (r as NSString).deletingPathExtension + ".txt"
                try? fm.removeItem(atPath: txt)
            }
            if fallados > 0 {
                Log.log(.sistema, "bitácora: \(fallados) archivos no se pudieron borrar en la purga — siguen indexados y se reintentan en la próxima")
            }
            let idsBorrables = Set(ids.filter { $0 >= 0 })

            // 3) Borrar filas y texto indexado (cola retenida milisegundos).
            cola.sync {
                guard let d = db else { return }
                for id in idsBorrables {
                    var bt: OpaquePointer?
                    if sqlite3_prepare_v2(d, "DELETE FROM \(tabla)_texto WHERE fila = ?;", -1, &bt, nil) == SQLITE_OK {
                        sqlite3_bind_int64(bt, 1, id)
                        sqlite3_step(bt)
                        sqlite3_finalize(bt)
                    }
                    // Fila a fila, y solo las de los archivos que SÍ se borraron:
                    // un `DELETE ... WHERE instante <` se llevaría por delante
                    // también las de los que fallaron.
                    var ft: OpaquePointer?
                    if sqlite3_prepare_v2(d, "DELETE FROM \(tabla) WHERE id = ?;", -1, &ft, nil) == SQLITE_OK {
                        sqlite3_bind_int64(ft, 1, id)
                        if sqlite3_step(ft) == SQLITE_DONE { borradas += Int(sqlite3_changes(d)) }
                        sqlite3_finalize(ft)
                    }
                }
            }
        }
        return borradas
    }

    // MARK: Estado para la interfaz

    /// Cuántas filas hay y cuánto ocupan, por material. Para la pestaña.
    func resumen() -> (audio: Int, pantalla: Int, bytes: Int64, pendientes: Int) {
        cola.sync {
            guard let d = db else { return (0, 0, 0, 0) }
            func cuenta(_ tabla: String) -> (Int, Int64, Int) {
                var st: OpaquePointer?
                let sql = """
                SELECT COUNT(*), COALESCE(SUM(bytes), 0), COALESCE(SUM(CASE WHEN procesado = 0 THEN 1 ELSE 0 END), 0)
                FROM \(tabla);
                """
                guard sqlite3_prepare_v2(d, sql, -1, &st, nil) == SQLITE_OK else { return (0, 0, 0) }
                defer { sqlite3_finalize(st) }
                guard sqlite3_step(st) == SQLITE_ROW else { return (0, 0, 0) }
                return (Int(sqlite3_column_int(st, 0)), sqlite3_column_int64(st, 1), Int(sqlite3_column_int(st, 2)))
            }
            let a = cuenta("audio")
            let p = cuenta("pantalla")
            return (a.0, p.0, a.1 + p.1, a.2 + p.2)
        }
    }

    // MARK: Utilidades

    private func ejecutar(_ sql: String) {
        guard let d = db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(d, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            Log.log(.sistema, "bitácora: SQL falló — \(String(cString: e))")
            sqlite3_free(err)
        }
    }

    /// SQLITE_TRANSIENT: SQLite copia la cadena en vez de quedarse el puntero,
    /// que en Swift muere al salir de la llamada.
    private func bindTexto(_ st: OpaquePointer?, _ pos: Int32, _ valor: String) {
        let transitorio = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(st, pos, valor, -1, transitorio)
    }

    private func tamano(de url: URL) -> Int64 {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (a?[.size] as? Int64) ?? 0
    }
}
