import Foundation

/// Integración opt-in del binario real. Nunca guarda ni pega la respuesta.
enum CascadaArchivoQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if let archivo = env["BETODICTA_ARCHIVOCASCADATEST"] {
            let inicio = Date()
            AudioArchivo.transcribir(URL(fileURLWithPath: archivo)) { r in
                switch r {
                case .success(let (texto, proveedor, modelo)):
                    print("ARCHIVOCASCADATEST OK proveedor=\(proveedor) modelo=\(modelo) segundos=\(Date().timeIntervalSince(inicio)) texto=\(texto)")
                    fflush(stdout); exit(0)
                case .failure(let error):
                    print("ARCHIVOCASCADATEST FALLA \(error.localizedDescription)")
                    fflush(stdout); exit(2)
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(240))
            exit(4)
        }
        if let id = env["BETODICTA_PULIDOADAPTATIVOTEST"],
           let ia = ChatIA.fijos.first(where: { $0.id == id }) {
            let original = "mañana revisamos el informe completo y luego enviamos la respuesta"
            let inicio = Date()
            LLMPostProcess.hacerProveedor(ia, textoOriginal: original, inicio: inicio, intento: 1,
                                         prompt: "Corrige solo puntuación y mayúsculas. Devuelve únicamente el texto: \(original)",
                                         temp: 0, resto: []) { salida in
                let ok = salida != original && LLMPostProcess.razonPulidoInvalido(original: original, pulido: salida) == nil
                print("PULIDOADAPTATIVOTEST \(ok ? "OK" : "FALLA") proveedor=\(ia.id) modelo=\(ia.modeloEfectivo) segundos=\(Date().timeIntervalSince(inicio)) texto=\(salida)")
                fflush(stdout); exit(ok ? 0 : 2)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(130))
            exit(4)
        }
    }
}
