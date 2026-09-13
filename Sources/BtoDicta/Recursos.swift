import Foundation

// MARK: - Recursos de la Mac + recomendación de parámetros (wizard/test de rendimiento)
//
// Idea: en vez de defaults ciegos, mirar los recursos ACTUALES de la máquina
// (RAM, núcleos, GPU) y RECOMENDAR qué activar (precargar el clon, cada cuánto dormir…).
// Así en una Mac potente se aprovecha; en una modesta no se satura. El usuario decide.

enum Recursos {
    struct Info {
        var ramGB: Double          // RAM total
        var ramLibreGB: Double     // RAM DISPONIBLE ahora (libre+inactiva+purgeable)
        var ramUsadaGB: Double     // en uso ahora
        var nucleos: Int           // núcleos de CPU
        var cargaCPU: Double       // carga actual (loadavg 1min / núcleos): 0=libre, 1=full
        var appleSilicon: Bool
    }

    struct Recomendacion {
        var preactivarClon: Bool   // mantener el modelo XTTS en RAM
        var dormirMin: Double      // minutos de inactividad para dormirlo
        var motivo: String         // por qué (para mostrar)
    }

    static func info() -> Info {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        let libre = ramLibreGB()
        var silicon = false
        #if arch(arm64)
        silicon = true
        #endif
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var load = [Double](repeating: 0, count: 3); getloadavg(&load, 3)
        return Info(ramGB: total, ramLibreGB: libre, ramUsadaGB: max(0, total - libre),
                    nucleos: cores, cargaCPU: cores > 0 ? load[0] / Double(cores) : 0, appleSilicon: silicon)
    }

    /// Recomienda según lo que está DISPONIBLE ahora (no solo el total): el clon XTTS
    /// residente ocupa ~2 GB, así que importa cuánta RAM libre hay y qué tan cargado
    /// está el CPU en este momento.
    static func recomendar(_ i: Info = info()) -> Recomendacion {
        let usoTxt = "libre \(fmt(i.ramLibreGB)) de \(fmt(i.ramGB)) GB, CPU \(Int(i.cargaCPU * 100))%"
        // RAM disponible manda (el clon necesita ~2 GB para quedar residente).
        if i.ramLibreGB < 3 {
            return Recomendacion(preactivarClon: false, dormirMin: 2,
                                  motivo: "Poca RAM libre ahora (\(usoTxt)). NO precargar el clon (colgaría 2 GB que no hay); duerme a los 2 min. Cierra apps si quieres precargar.")
        }
        if i.cargaCPU > 0.85 {
            return Recomendacion(preactivarClon: false, dormirMin: 3,
                                  motivo: "CPU muy ocupado ahora (\(usoTxt)). Mejor no precargar todavía; duerme a los 3 min. Vuelve a recomendar cuando baje la carga.")
        }
        if i.ramLibreGB >= 16 {
            return Recomendacion(preactivarClon: true, dormirMin: 15,
                                  motivo: "RAM de sobra (\(usoTxt)). Clon precargado (respuesta rápida) y duerme a los 15 min.")
        }
        if i.ramLibreGB >= 6 {
            return Recomendacion(preactivarClon: true, dormirMin: 5,
                                  motivo: "RAM suficiente (\(usoTxt)). Clon precargado y duerme a los 5 min para liberar cuando no lo uses.")
        }
        return Recomendacion(preactivarClon: true, dormirMin: 3,
                              motivo: "RAM justa (\(usoTxt)). Precargar con dormida corta (3 min) para no retener 2 GB de más.")
    }

    /// RAM DISPONIBLE aprox (libre + inactiva + purgeable), en GB.
    private static func ramLibreGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        // Disponible ≈ libre + inactiva + purgeable (reclamable al instante).
        let libres = (Double(stats.free_count) + Double(stats.inactive_count) + Double(stats.purgeable_count)) * page
        return libres / 1_073_741_824.0
    }

    private static func fmt(_ g: Double) -> String { String(format: "%.0f", g) }
}
