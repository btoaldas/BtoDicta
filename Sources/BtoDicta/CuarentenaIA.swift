import Foundation

// MARK: - No volver a llamar al que acaba de fallar
//
// La transcripción ya tenía esto (`CuarentenaSTT`): un proveedor que devuelve un
// fallo determinista se salta un rato en vez de gastar su plazo en cada dictado.
// El pulido no lo tenía, y se notaba.
//
// Medido en un día real: DeepSeek dejó de contestar y cada dictado pagaba su
// plazo entero antes de seguir la cascada. Un texto de 577 caracteres que se
// pulía en un segundo pasó a tardar veintitrés, porque la aplicación reintentaba
// el mismo proveedor caído una y otra vez y luego iba cayendo por los siguientes.
//
// Aquí no se aprende nada permanente: es una nota corta de «este no está para
// nadie ahora mismo», que caduca sola. Un proveedor bueno que tuvo un mal minuto
// vuelve a la cascada enseguida.
enum CuarentenaIA {

    private struct Entrada {
        let hasta: Date
        let motivo: String
    }

    private static var tabla: [String: Entrada] = [:]
    private static let candado = NSLock()

    /// Cuánto se aparta a un proveedor según lo que le pasó. Un plazo agotado no
    /// es lo mismo que una clave mala: lo primero se arregla solo, lo segundo no.
    private static func minutos(_ motivo: String) -> Double {
        let m = motivo.lowercased()
        if m.contains("401") || m.contains("403") || m.contains("clave") || m.contains("key") { return 30 }
        if m.contains("402") || m.contains("saldo") || m.contains("quota") || m.contains("credit") { return 30 }
        if m.contains("429") || m.contains("rate") { return 5 }
        if m.contains("plazo") || m.contains("timeout") || m.contains("tiempo") { return 3 }
        return 2
    }

    static func registrar(_ id: String, motivo: String) {
        let mins = minutos(motivo)
        candado.lock()
        tabla[id] = Entrada(hasta: Date().addingTimeInterval(mins * 60), motivo: motivo)
        candado.unlock()
        Log.write("pulido: \(id) apartado \(Int(mins)) min (\(motivo)) — no se vuelve a llamar hasta entonces")
    }

    static func activa(_ id: String) -> Bool {
        candado.lock(); defer { candado.unlock() }
        guard let e = tabla[id] else { return false }
        if Date() >= e.hasta { tabla.removeValue(forKey: id); return false }
        return true
    }

    /// Una respuesta buena limpia la nota: el proveedor volvió.
    static func limpiar(_ id: String) {
        candado.lock(); defer { candado.unlock() }
        tabla.removeValue(forKey: id)
    }

    static func limpiarTodo() {
        candado.lock(); tabla.removeAll(); candado.unlock()
    }

    /// La cascada sin los apartados. Si TODOS lo están se devuelve entera: más
    /// vale intentarlo con uno dudoso que quedarse sin pulir.
    static func filtrar(_ cadena: [ChatIA]) -> [ChatIA] {
        let vivos = cadena.filter { !activa($0.id) }
        return vivos.isEmpty ? cadena : vivos
    }

    /// Para la prueba propia y para enseñarlo en el registro.
    static func apartados() -> [String] {
        candado.lock(); defer { candado.unlock() }
        let ahora = Date()
        return tabla.filter { $0.value.hasta > ahora }.keys.sorted()
    }
}
