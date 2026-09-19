import Foundation

/// Cuánta memoria ocupa ESTE proceso, medida como la mide macOS para decidir
/// si hay presión.
///
/// La trampa que originó este archivo: las pruebas de memoria venían leyendo
/// `resident_size` (lo que `ps` llama RSS). En macOS el RSS incluye páginas que
/// el asignador liberó pero no devolvió al sistema —aparecen en `vmmap` como
/// `MALLOC_SMALL (empty)`— y que se reclaman solas en cuanto algo las necesita.
/// Medido el 2026-09-19 en esta misma aplicación: **RSS 5 564 MB con una huella
/// real de 56 MB**. Dos órdenes de magnitud de diferencia, y el número grande
/// era el falso.
///
/// `phys_footprint` es el contador que usa el sistema para la presión de
/// memoria y el que decide quién muere cuando falta RAM. Es el que hay que
/// mirar. `pico` además guarda el máximo histórico del proceso, que es la única
/// forma de ver un pico transitorio que ya pasó.
enum MemoriaProceso {

    /// Huella real actual, en MB. Devuelve -1 si el núcleo no contesta.
    static func huellaMB() -> Double { info().map { Double($0.phys_footprint) / 1_048_576 } ?? -1 }

    /// Mayor huella alcanzada por el proceso desde que arrancó, en MB.
    /// Un pico que ya se liberó no se ve de ninguna otra forma.
    static func picoMB() -> Double { info().map { Double($0.ledger_phys_footprint_peak) / 1_048_576 } ?? -1 }

    /// Lo que informa `ps`. Se conserva porque sirve para explicar la
    /// diferencia en un diagnóstico, nunca como criterio de una prueba.
    static func residenteMB() -> Double {
        var info = mach_task_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &n)
            }
        }
        return r == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    private static func info() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n)
            }
        }
        return r == KERN_SUCCESS ? info : nil
    }
}
