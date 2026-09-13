import Foundation

/// Smoke test del último árbitro con la IA elegida por el usuario. Solo pide
/// planes y los inspecciona; jamás los confirma ni ejecuta.
enum ModoIAQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_MODOIATEST"] == "1" else { return }
        let casos: [(String, [String], [String])] = [
            ("Por favor, necesito traducir al inglés y después mandar por correo: la vida es bella.",
             ["traducir"], ["correo"]),
            ("Quisiera mandar un WhatsApp a Andrés: nos vemos mañana.",
             [], ["whatsapp"]),
            ("Por favor, resume, traduce al quichua y envía por correo y WhatsApp: mañana hay reunión.",
             ["resumir", "traducir"], ["correo", "whatsapp"]),
        ]
        var i = 0, fallos = 0
        func siguiente() {
            guard i < casos.count else {
                let negativo = "Necesito revisar el correo que llegó ayer."
                let gateOK = !ModoPlanificador.parecePedidoParaArbitraje(negativo)
                if !gateOK { fallos += 1 }
                print("MODOIATEST NEG \(gateOK ? "OK" : "✗") sin llamada IA")
                print("MODOIATEST \(fallos == 0 ? "TODO OK" : "✗ \(fallos) FALLOS")")
                fflush(stdout); exit(fallos == 0 ? 0 : 3)
            }
            let caso = casos[i]; i += 1
            ModoIAEnrutador.resolver(caso.0) { p in
                let t = p?.cadena.transforms.map(\.id) ?? []
                let a = p?.cadena.acciones.map { $0.modo.base == "buscar" ? "buscar" : $0.modo.accion } ?? []
                let ok = t == caso.1 && a == caso.2
                if !ok { fallos += 1 }
                print("MODOIATEST \(ok ? "OK" : "✗") T=\(t) A=\(a) fuente=\(p?.fuente.rawValue ?? "nil")")
                siguiente()
            }
        }
        siguiente()
        RunLoop.main.run()
    }
}
