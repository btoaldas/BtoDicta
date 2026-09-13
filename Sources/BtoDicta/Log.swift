import Foundation
import Compression

// MARK: - Registro total con rotación semanal y compresión

/// Registra TODO lo que hace la app (categorías: UI, dictado, IA, media,
/// config, sistema). El archivo vivo es `btodicta.log`. Cada semana se
/// archiva comprimido (.gz) en logs/ y se conservan máximo 12 semanas; los
/// más viejos se borran solos para no llenar el disco.
enum Log {
    private static let queue = DispatchQueue(label: "ec.bto.btodicta.log")
    private static var currentWeekStamp: String?
    private static let maxArchivos = 12

    static var fileURL: URL { Config.dir.appendingPathComponent("btodicta.log") }
    private static var logsDir: URL { Config.dir.appendingPathComponent("logs") }

    enum Cat: String {
        case ui = "UI", dictado = "DICT", ia = "IA", media = "MEDIA",
             config = "CONF", sistema = "SYS", debug = "DBG"
    }

    /// Registro general (siempre se escribe).
    static func write(_ message: String) { log(.sistema, message) }

    /// Nota de depuración (solo si modo_desarrollo está activo).
    static func debug(_ message: String) {
        guard Config.devMode() else { return }
        log(.debug, message)
    }

    /// Registro categorizado — la vía para "todo se registra".
    static func log(_ cat: Cat, _ message: String) {
        queue.async {
            rotateIfNeeded()
            let line = "[\(stamp("yyyy-MM-dd HH:mm:ss"))] [\(cat.rawValue)] \(message)\n"
            append(line)
        }
    }

    // MARK: internos

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }

    private static func stamp(_ fmt: String) -> String {
        let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: Date())
    }

    /// Si cambió la semana ISO, archiva el log actual comprimido y arranca uno nuevo.
    private static func rotateIfNeeded() {
        let week = stamp("yyyy-'W'ww")
        if currentWeekStamp == nil { currentWeekStamp = readWeekMarker() ?? week }
        guard currentWeekStamp != week else { return }

        if FileManager.default.fileExists(atPath: fileURL.path),
           let contenido = try? Data(contentsOf: fileURL), !contenido.isEmpty {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let destino = logsDir.appendingPathComponent("btodicta-\(currentWeekStamp!).log.gz")
            if let comprimido = gzip(contenido) { try? comprimido.write(to: destino) }
            try? FileManager.default.removeItem(at: fileURL)
        }
        currentWeekStamp = week
        writeWeekMarker(week)
        podarArchivos()
    }

    private static func podarArchivos() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDir, includingPropertiesForKeys: nil) else { return }
        let gz = files.filter { $0.pathExtension == "gz" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for viejo in gz.dropFirst(maxArchivos) { try? FileManager.default.removeItem(at: viejo) }
    }

    private static var markerURL: URL { logsDir.appendingPathComponent(".semana") }
    private static func readWeekMarker() -> String? {
        try? String(contentsOf: markerURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func writeWeekMarker(_ w: String) {
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try? w.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    // gzip nativo (Compression.framework), sin dependencias externas.
    private static func gzip(_ data: Data) -> Data? {
        var out = Data([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0xff])   // cabecera gzip
        guard let deflated = deflate(data) else { return nil }
        out.append(deflated)
        var crc = crc32(data).littleEndian
        out.append(Data(bytes: &crc, count: 4))
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        out.append(Data(bytes: &size, count: 4))
        return out
    }

    private static func deflate(_ data: Data) -> Data? {
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Data? in
            let cap = data.count + 4096
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
            defer { dst.deallocate() }
            let n = compression_encode_buffer(dst, cap,
                        src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB)
            return n > 0 ? Data(bytes: dst, count: n) : nil
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for b in data {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return ~crc
    }
}
