import AppKit
import Carbon.HIToolbox
import Darwin
import EventKit
import Foundation

// MARK: - Selección universal (texto o archivos de Finder)

struct SeleccionMacContenido {
    let texto: String?
    let archivos: [URL]
}

private struct InstantaneaPortapapeles {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pb: NSPasteboard) {
        items = (pb.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { tipo in
                item.data(forType: tipo).map { (tipo, $0) }
            })
        }
    }

    func restaurar(_ pb: NSPasteboard) {
        pb.clearContents()
        let restaurados: [NSPasteboardItem] = items.map { datos in
            let item = NSPasteboardItem()
            for (tipo, data) in datos { item.setData(data, forType: tipo) }
            return item
        }
        if !restaurados.isEmpty { pb.writeObjects(restaurados) }
    }
}

enum SeleccionMac {
    static func capturar(simular: SeleccionMacContenido? = nil,
                         completion: @escaping (Result<SeleccionMacContenido, Error>) -> Void) {
        if let simular { completion(.success(simular)); return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { capturar(completion: completion) }; return
        }
        let pb = NSPasteboard.general
        let anterior = InstantaneaPortapapeles(pb)
        let cambio = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard pb.changeCount != cambio else {
                anterior.restaurar(pb)
                completion(.failure(NSError(domain: "BtoDicta.Seleccion", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No detecté una selección. Selecciona texto o un archivo en Finder y vuelve a intentarlo."])))
                return
            }
            let texto = pb.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let archivos = (pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true
            ]) as? [URL]) ?? []
            anterior.restaurar(pb)
            let resultado = SeleccionMacContenido(
                texto: (texto?.isEmpty == false ? texto : nil),
                archivos: archivos.filter(\.isFileURL))
            guard resultado.texto != nil || !resultado.archivos.isEmpty else {
                completion(.failure(NSError(domain: "BtoDicta.Seleccion", code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "La selección no contiene texto ni archivos locales compatibles."]))); return
            }
            completion(.success(resultado))
        }
    }

    static func primerAudio(_ s: SeleccionMacContenido) -> URL? {
        let ext: Set<String> = ["wav", "mp3", "m4a", "aac", "aiff", "aif", "flac", "ogg", "oga", "caf"]
        return s.archivos.first { ext.contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - Estado local del Mac

struct EstadoMacDatos {
    var bateria: String
    var discoLibre: UInt64
    var discoTotal: UInt64
    var memoriaUsada: UInt64
    var memoriaTotal: UInt64
    var cpuPorcentaje: Double
    var interfaces: [String]
    var vpn: [String]
    var tuneles: [String] = []
}

enum EstadoMac {
    private static func ejecutar(_ ruta: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: ruta); p.arguments = args
        let o = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    private static func memoria() -> (UInt64, UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let paginas = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        return (min(total, paginas * UInt64(vm_kernel_page_size)), total)
    }

    private static func red() -> ([String], [String], [String]) {
        var inicio: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&inicio) == 0, let primero = inicio else { return ([], [], []) }
        defer { freeifaddrs(inicio) }
        var nombres = Set<String>(), vpn = Set<String>(), tuneles = Set<String>()
        var p: UnsafeMutablePointer<ifaddrs>? = primero
        while let actual = p {
            let f = actual.pointee
            let flags = Int32(f.ifa_flags)
            if flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let addr = f.ifa_addr,
               [AF_INET, AF_INET6].contains(Int32(addr.pointee.sa_family)) {
                let n = String(cString: f.ifa_name)
                let bajo = n.lowercased()
                if bajo.hasPrefix("en") || bajo.hasPrefix("bridge")
                    || ["utun", "tun", "tap", "ppp", "ipsec", "wg", "tailscale"]
                        .contains(where: bajo.hasPrefix) { nombres.insert(n) }
                if ["utun", "tun", "tap"].contains(where: bajo.hasPrefix) { tuneles.insert(n) }
                // Estos nombres son específicos; `utun` solo NO demuestra VPN
                // (iCloud/Continuity crean varios incluso sin VPN).
                if ["ppp", "ipsec", "wg", "tailscale"].contains(where: bajo.hasPrefix) {
                    vpn.insert(n)
                }
            }
            p = f.ifa_next
        }
        let servicios = ejecutar("/usr/sbin/scutil", ["--nc", "list"])
        for linea in servicios.split(separator: "\n") where linea.contains("(Connected)") {
            let s = String(linea)
            if let a = s.firstIndex(of: "\""), let b = s[s.index(after: a)...].firstIndex(of: "\"") {
                vpn.insert(String(s[s.index(after: a)..<b]))
            }
        }
        let ruta = ejecutar("/sbin/route", ["-n", "get", "default"])
        if let re = try? NSRegularExpression(pattern: #"interface:\s+(\S+)"#),
           let m = re.firstMatch(in: ruta, range: NSRange(ruta.startIndex..., in: ruta)),
           let r = Range(m.range(at: 1), in: ruta) {
            let interfaz = String(ruta[r])
            if ["utun", "tun", "tap", "ppp", "ipsec", "wg", "tailscale"]
                .contains(where: interfaz.lowercased().hasPrefix) { vpn.insert(interfaz + " (ruta principal)") }
        }
        return (nombres.sorted(), vpn.sorted(), tuneles.sorted())
    }

    private static func bateria(_ raw: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(\d{1,3})%"#),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range(at: 1), in: raw) else { return "sin batería detectada" }
        let porcentaje = String(raw[r]) + " %"
        let n = raw.lowercased()
        if n.contains("charged") { return porcentaje + ", cargada" }
        if n.contains("charging") || n.contains("ac attached") { return porcentaje + ", cargando" }
        return porcentaje + ", usando batería"
    }

    static func leer() -> EstadoMacDatos {
        let fs = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())) ?? [:]
        let total = (fs[.systemSize] as? NSNumber)?.uint64Value ?? 0
        let libre = (fs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        let cpu = min(100, max(0, loads[0] / Double(max(1, ProcessInfo.processInfo.activeProcessorCount)) * 100))
        let (memUsada, memTotal) = memoria()
        let (interfaces, vpn, tuneles) = red()
        let batt = bateria(ejecutar("/usr/bin/pmset", ["-g", "batt"]))
        return .init(bateria: batt,
                     discoLibre: libre, discoTotal: total,
                     memoriaUsada: memUsada, memoriaTotal: memTotal,
                     cpuPorcentaje: cpu, interfaces: interfaces, vpn: vpn, tuneles: tuneles)
    }

    static func formatear(_ d: EstadoMacDatos) -> String {
        let gb = 1_073_741_824.0
        let disco = d.discoTotal == 0 ? "sin dato" : String(format: "%.1f de %.1f GB libres",
            Double(d.discoLibre) / gb, Double(d.discoTotal) / gb)
        let memoria = d.memoriaTotal == 0 ? "sin dato" : String(format: "%.1f de %.1f GB en uso",
            Double(d.memoriaUsada) / gb, Double(d.memoriaTotal) / gb)
        let red = d.interfaces.isEmpty ? "sin interfaz activa" : d.interfaces.joined(separator: ", ")
        let vpn = d.vpn.isEmpty ? "sin VPN confirmada" : "VPN activa: " + d.vpn.joined(separator: ", ")
        let tunel = d.vpn.isEmpty && !d.tuneles.isEmpty
            ? " Hay \(d.tuneles.count) túnel(es) del sistema, pero no bastan para afirmar que exista una VPN."
            : ""
        return "Estado del Mac. Batería: \(d.bateria). Disco: \(disco). Memoria: \(memoria). CPU aproximada: \(Int(d.cpuPorcentaje.rounded())) %. Red: \(red); \(vpn).\(tunel)"
    }

    static func obtener(simular: EstadoMacDatos? = nil,
                        completion: @escaping (ResultadoHerramientaApple) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let d = simular ?? leer(), texto = formatear(d)
            DispatchQueue.main.async {
                completion(.init(ok: true, mensaje: texto,
                    evidencia: ["cpu": String(format: "%.1f", d.cpuPorcentaje),
                                "vpn": d.vpn.joined(separator: ","),
                                "interfaces": d.interfaces.joined(separator: ","),
                                "tuneles": d.tuneles.joined(separator: ","),
                                "salida": String(texto.prefix(2_000))]))
            }
        }
    }
}

// MARK: - Resumen del día (EventKit + pendientes locales)

struct AgendaDiaDatos {
    var eventos: [String]
    var recordatorios: [String]
    var calendarioDisponible: Bool
    var recordatoriosDisponibles: Bool
}

enum ResumenDia {
    static func formatear(_ d: AgendaDiaDatos, tareas: [Pendiente],
                          offsetDias: Int = 0) -> String {
        let cal = Calendar.current
        let inicio = cal.date(byAdding: .day, value: offsetDias,
                              to: cal.startOfDay(for: Date()))!
        let fin = cal.date(byAdding: .day, value: 1, to: inicio)!
        let pendientes = tareas.filter {
            guard $0.tipo == "tarea", !$0.hecho else { return false }
            guard offsetDias != 0 else { return true }
            guard let ts = $0.fechaObjetivo else { return true }
            let f = Date(timeIntervalSince1970: ts); return f >= inicio && f < fin
        }
        var partes: [String] = []
        if !d.eventos.isEmpty { partes.append("Calendario: " + d.eventos.prefix(6).joined(separator: "; ")) }
        else {
            let cuando = offsetDias == 1 ? "mañana" : "hoy"
            partes.append(d.calendarioDisponible ? "No tienes eventos \(cuando)" : "Calendario sin permiso")
        }
        if !d.recordatorios.isEmpty { partes.append("Recordatorios: " + d.recordatorios.prefix(6).joined(separator: "; ")) }
        else if !d.recordatoriosDisponibles { partes.append("Recordatorios de Mac sin permiso") }
        if !pendientes.isEmpty {
            partes.append("Tareas de BtoDicta: " + pendientes.prefix(6).map(\.texto).joined(separator: "; "))
        } else { partes.append("No tienes tareas pendientes en BtoDicta") }
        let titulo = offsetDias == 1 ? "Preparación de mañana" : "Resumen del día"
        return titulo + ". " + partes.joined(separator: ". ") + "."
    }

    static func obtener(offsetDias: Int = 0, simular: AgendaDiaDatos? = nil,
                        completion: @escaping (ResultadoHerramientaApple) -> Void) {
        if let simular {
            let t = formatear(simular, tareas: NotasStore.todos(), offsetDias: offsetDias)
            completion(.init(ok: true, mensaje: t,
                             evidencia: ["eventos": "\(simular.eventos.count)",
                                         "recordatorios": "\(simular.recordatorios.count)",
                                         "salida": String(t.prefix(2_000))])); return
        }
        let store = EKEventStore(), cal = Calendar.current
        let inicio = cal.date(byAdding: .day, value: offsetDias,
                              to: cal.startOfDay(for: Date()))!
        let fin = cal.date(byAdding: .day, value: 1, to: inicio)!
        store.requestFullAccessToEvents { permitidoEventos, _ in
            let eventos: [String] = permitidoEventos ? store.events(matching:
                store.predicateForEvents(withStart: inicio, end: fin, calendars: nil))
                .sorted { $0.startDate < $1.startDate }.map { e in
                    let f = DateFormatter(); f.locale = Locale(identifier: "es_EC"); f.dateFormat = "HH:mm"
                    return e.isAllDay ? e.title : "\(f.string(from: e.startDate)) \(e.title ?? "Evento")"
                } : []
            store.requestFullAccessToReminders { permitidoRecordatorios, _ in
                guard permitidoRecordatorios else {
                    let d = AgendaDiaDatos(eventos: eventos, recordatorios: [],
                                           calendarioDisponible: permitidoEventos,
                                           recordatoriosDisponibles: false)
                    let texto = formatear(d, tareas: NotasStore.todos(), offsetDias: offsetDias)
                    DispatchQueue.main.async { completion(.init(ok: true, mensaje: texto,
                        evidencia: ["eventos": "\(eventos.count)", "recordatorios": "0",
                                    "salida": String(texto.prefix(2_000))])) }
                    return
                }
                let desde = offsetDias == 0 ? Date.distantPast : inicio
                let pred = store.predicateForIncompleteReminders(withDueDateStarting: desde,
                                                                  ending: fin, calendars: nil)
                store.fetchReminders(matching: pred) { reminders in
                    let rs = (reminders ?? []).compactMap(\.title).filter { !$0.isEmpty }
                    let d = AgendaDiaDatos(eventos: eventos, recordatorios: rs,
                                           calendarioDisponible: permitidoEventos,
                                           recordatoriosDisponibles: true)
                    let texto = formatear(d, tareas: NotasStore.todos(), offsetDias: offsetDias)
                    DispatchQueue.main.async {
                        completion(.init(ok: true, mensaje: texto,
                            evidencia: ["eventos": "\(eventos.count)",
                                        "recordatorios": "\(rs.count)",
                                        "tareas": "\(NotasStore.tareas().filter { !$0.hecho }.count)",
                                        "salida": String(texto.prefix(2_000))]))
                    }
                }
            }
        }
    }
}
