import Foundation

/// Ejecuta matrices TSV del resolvedor de modos sin crear `NSApplication` ni
/// despachar acciones. Esto permite probar una instalación aunque BtoDicta ya
/// esté abierta: únicamente lee el catálogo y compara la intención detectada.
///
/// Formato por línea:
///   frase<TAB>esperado(id|-|cadena|plan)<TAB>textoEsperado|*<TAB>arg=valor
enum MatrizModosQA {
    static func ejecutarSiSePidio() {
        guard let ruta = ProcessInfo.processInfo.environment["BTODICTA_MATRIZTEST"],
              !ruta.isEmpty else { return }
        ejecutar(ruta: ruta)
    }

    private static func firmaAccion(_ modo: Modo) -> String {
        switch modo.base {
        case "buscar": return "buscar:\(modo.buscador)"
        case "musica": return "musica:\(modo.musicaProveedor)"
        case "aplicacion":
            let destino = !modo.appBundleId.isEmpty ? modo.appBundleId : modo.appRuta
            return "aplicacion:\(destino)"
        default: return modo.accion.isEmpty ? modo.id : modo.accion
        }
    }

    private static func ejecutar(ruta: String) -> Never {
        guard let tsv = try? String(contentsOf: URL(fileURLWithPath: ruta), encoding: .utf8) else {
            print("MATRIZTEST sin archivo"); exit(1)
        }
        var mal = 0, total = 0
        for linea in tsv.split(separator: "\n") {
            let c = linea.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard c.count >= 2, !c[0].hasPrefix("#") else { continue }
            total += 1
            let frase = c[0], esperado = c[1]
            var detId = "-", detTexto = "", detArg = ""
            if let cad = ModosStore.detectarCadena(frase) {
                detId = "cadena"; detTexto = cad.contenido
                detArg = "etapas=" + (cad.transforms.map(\.id)
                    + cad.acciones.map { firmaAccion($0.modo) }).joined(separator: "+")
            } else if let m = ModoResolver.detectarExacto(frase)
                        ?? ModoResolver.detectarDifuso(frase) {
                detId = m.modo.id; detTexto = m.textoLimpio
                if m.modo.base == "traducir" { detArg = "idioma=\(m.modo.idiomaDestino)" }
                if m.modo.base == "buscar" { detArg = "buscador=\(m.modo.buscador)" }
                if m.modo.base == "musica" { detArg = "proveedor=\(m.modo.musicaProveedor)" }
            } else if let p = ModoPlanificador.detectarNatural(frase) {
                detId = "plan"; detTexto = p.cadena.contenido
                detArg = "etapas=" + (p.cadena.transforms.map(\.id)
                    + p.cadena.acciones.map { firmaAccion($0.modo) }).joined(separator: "+")
            }
            var ok = detId == esperado
            if ok, c.count >= 3, !c[2].isEmpty, c[2] != "*" { ok = detTexto == c[2] }
            if ok, c.count >= 4, !c[3].isEmpty { ok = detArg == c[3] }
            if !ok { mal += 1 }
            let argumento = detArg.isEmpty ? "" : " [\(detArg)]"
            let esperadoDetalle = c.dropFirst(1).joined(separator: " ")
            print("MATRIZTEST \(ok ? "OK" : "FALLA") '\(frase)' → \(detId)\(argumento) texto='\(detTexto)'\(ok ? "" : "  ESPERADO: \(esperadoDetalle)")")
        }
        print("MATRIZTEST \(mal == 0 ? "TODO OK" : "FALLOS=\(mal)")/\(total)")
        fflush(stdout)
        exit(mal == 0 ? 0 : 1)
    }
}
