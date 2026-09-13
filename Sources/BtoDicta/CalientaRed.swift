import Foundation

// MARK: - Mantiene la red/conexión CALIENTE (mata la latencia del pulido tras inactividad)
//
// Problema real: si el pulido se usa cada varios minutos, la primera petición tras
// el reposo es LENTA (~10-14s). Dos causas se suman:
//   1) La VPN (WireGuard/OpenVPN/…) DUERME el túnel al quedar inactivo → el primer
//      paquete lo despierta (y a veces se cae y hay que reintentar).
//   2) URLSession suelta las conexiones ociosas del pool → la 1ª petición paga un
//      handshake TLS COMPLETO (lento, más aún despertando el túnel).
//
// Antes usábamos "Connection: close" (conexión fresca cada vez) para no reusar un
// socket MUERTO. Pero eso obliga a pagar el handshake SIEMPRE → seguía lento al
// arrancar. La solución correcta es MANTENER una conexión caliente:
//
//   • LATIDO: cada pocos segundos, un HEAD keep-alive al host del pulido. Mantiene
//     el túnel VPN despierto Y una conexión TLS viva en el pool de URLSession.shared.
//   • El pulido (y demás llamadas al MISMO host, misma URLSession.shared) REUSA esa
//     conexión caliente → responde rápido desde el primer uso, sin handshake.
//   • Si aun así el socket murió (VPN lo mató entre latidos), el pulido reintenta
//     con conexión fresca (ya implementado) → nunca se cuelga.
//
// Todo fire-and-forget, agnóstico de la VPN (o sin VPN), parametrizable, y si el
// pulido es LOCAL (localhost) no hace nada. Nada detiene el dictado.

enum CalientaRed {
    private static var latido: Timer?

    /// Un toque AHORA: despierta el túnel y calienta la conexión (keep-alive, para
    /// que el pool la conserve y el pulido la reuse). Se llama al empezar a grabar.
    static func despertar() {
        guard Config.calentarRed() else { return }
        guard let u = hostPulido() else { return }
        var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 6
        // keep-alive (SIN "Connection: close"): deja la conexión viva en el pool.
        URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()   // resultado ignorado
    }

    /// Arranca el LATIDO periódico (al lanzar la app). Mantiene la conexión caliente
    /// aunque el usuario dicte solo cada varios minutos. Parametrizable.
    static func iniciarLatido() {
        detenerLatido()
        guard Config.calentarRed() else { return }
        let cada = max(5.0, Config.latidoRedSegundos())
        Log.log(.config, "latido de red cada \(Int(cada))s (mantiene la conexión caliente para el pulido)")
        DispatchQueue.main.async {
            let t = Timer(timeInterval: cada, repeats: true) { _ in despertar() }
            RunLoop.main.add(t, forMode: .common)   // .common: sigue latiendo con menús abiertos
            latido = t
            despertar()   // primer toque inmediato
        }
    }

    static func detenerLatido() { latido?.invalidate(); latido = nil }

    /// URL del host del pulido (nil si es local o inválido).
    private static func hostPulido() -> URL? {
        let base = ChatIA.seleccionada()?.base ?? "https://api.groq.com"
        guard let u = URL(string: base), let host = u.host?.lowercased(),
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return nil }
        return u
    }
}
