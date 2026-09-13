import Foundation

// MARK: - Bench de latencia de red (evidencia del fix del latido keep-alive)
//
// Hace 2 peticiones al MISMO host sobre una URLSession con keep-alive y captura
// métricas. La 1ª paga handshake TLS (conexión fría). La 2ª debería REUSAR la
// conexión (isReusedConnection=true, sin secureConnection) → sin handshake = rápida.
// Eso es exactamente lo que hace el latido: dejar la conexión caliente para que el
// pulido la reuse y responda rápido aunque dictes cada varios minutos.

final class RedBench: NSObject, URLSessionTaskDelegate {
    private var session: URLSession!
    private var etiqueta = ""

    func correr(host: String, done: @escaping () -> Void) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        guard let u = URL(string: host) else { print("REDBENCH: host inválido"); done(); return }
        print("REDBENCH host=\(host)")
        pedir(u, "1ª (fría, con handshake)") { [weak self] in
            self?.pedir(u, "2ª (debería REUSAR, sin handshake)") { done() }
        }
    }

    private func pedir(_ u: URL, _ tag: String, _ next: @escaping () -> Void) {
        etiqueta = tag
        var r = URLRequest(url: u); r.httpMethod = "HEAD"
        let t0 = Date()
        session.dataTask(with: r) { _, _, err in
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if let err { print("REDBENCH \(tag): error \(err.localizedDescription) (\(ms)ms)") }
            else { print("REDBENCH \(tag): \(ms)ms total") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
        }.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let m = metrics.transactionMetrics.last else { return }
        let reuso = m.isReusedConnection
        func ms(_ a: Date?, _ b: Date?) -> String {
            guard let a, let b else { return "—" }
            return "\(Int(b.timeIntervalSince(a) * 1000))ms"
        }
        let tls = ms(m.secureConnectionStartDate, m.secureConnectionEndDate)
        let conn = ms(m.connectStartDate, m.connectEndDate)
        print("REDBENCH   → reusóConexión=\(reuso)  TCP=\(conn)  TLS=\(tls)")
    }
}
