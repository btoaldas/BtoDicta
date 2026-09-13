import Foundation

/// Regresiones puras que pueden correr con la app instalada abierta. No abren
/// aplicaciones, no escriben config y no ejecutan acciones.
enum ModoRegressionQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_MODEREGRESSION"] == "1" else { return }
        var fallos = 0
        let catalogo = ModoCatalogo(modos: ModosStore.todos())

        let fuzzy: [(String, String?)] = [
            ("modo traductor buenos días", "traducir"),
            ("molde traductor hola", "traducir"),
            ("moto agente qué hora es", "agente"),
            ("modo tradutor como estás", "traducir"),
            ("mudo tarea comprar pan", "tarea"),
            ("moda de invierno para damas", nil),
            ("modo de empleo del taladro", nil),
            ("todo agente tiene un jefe", nil)
        ]
        for (texto, esperado) in fuzzy {
            let got = ModoResolver.detectarExacto(texto, catalogo: catalogo)?.modo.id
                ?? ModoResolver.detectarDifuso(texto, catalogo: catalogo)?.modo.id
            let ok = got == esperado
            if !ok { fallos += 1 }
            print("MODEREGRESSION FUZZY \(ok ? "OK" : "✗") \(got ?? "nil") ← \(texto)")
        }

        let lista = [
            Modo(id: "correo", nombre: "Correo", icono: "envelope.fill", base: "pulir",
                 apps: ["Outlook", "com.microsoft.Outlook"]),
            Modo(id: "oficio", nombre: "Oficio", icono: "doc.text.fill", base: "pulir",
                 sitios: ["intranet.example.com"]),
            Modo(id: "dictado", nombre: "Dictado", icono: "mic.fill", base: "pulir",
                 apps: ["Finder"])
        ]
        let contextos: [(String, String, String?, String?)] = [
            ("com.microsoft.Outlook", "Microsoft Outlook", nil, "correo"),
            ("com.otra.cosa", "Outlook para Mac", nil, "correo"),
            ("com.apple.Safari", "Safari", "https://intranet.example.com/inicio", "oficio"),
            ("com.apple.Safari", "Safari", "https://google.com", nil),
            ("com.apple.finder", "Finder", nil, nil)
        ]
        for (bid, nombre, url, esperado) in contextos {
            let got = ModosStore.coincidePorContexto(lista, bundleId: bid, nombre: nombre, url: url)?.id
            let ok = got == esperado
            if !ok { fallos += 1 }
            print("MODEREGRESSION CONTEXTO \(ok ? "OK" : "✗") \(got ?? "nil") ← \(nombre)")
        }

        // Estado vivo aislado por UUID + recorte variable + pausa pura.
        let sesion = UUID()
        var cambios: [String] = []
        ModoVivo.empezar(sesion: sesion) { cambios.append($0.modo.id) }
        for p in ["modo", "modo agen", "modo agente", "modo agente qué hora es"] {
            ModoVivo.evaluar(p, sesion: sesion)
        }
        _ = ModoVivo.confirmarPausa(sesion: sesion)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let vivo = ModoVivo.terminar(sesion: sesion)
        let vivoOK = vivo?.modo.id == "agente" && vivo?.confirmadoPorPausa == true
        if !vivoOK { fallos += 1 }
        print("MODEREGRESSION VIVO \(vivoOK ? "OK" : "✗") cambios=\(cambios) final=\(vivo?.modo.id ?? "nil")")

        // Un parcial tardío o una cancelación nunca pueden alimentar la sesión
        // siguiente ni una transcripción de archivo.
        let vieja = UUID(), nueva = UUID()
        ModoVivo.empezar(sesion: vieja) { _ in }
        ModoVivo.evaluar("modo agente", sesion: vieja)
        ModoVivo.empezar(sesion: nueva) { _ in }
        ModoVivo.evaluar("modo traducir", sesion: vieja) // callback obsoleto
        let aislado = ModoVivo.terminar(sesion: nueva) == nil
        let cancelada = UUID()
        ModoVivo.empezar(sesion: cancelada) { _ in }
        ModoVivo.evaluar("modo tarea", sesion: cancelada)
        ModoVivo.cancelar(sesion: cancelada)
        let cancelarOK = ModoVivo.terminar(sesion: cancelada) == nil
        if !aislado || !cancelarOK { fallos += 1 }
        print("MODEREGRESSION AISLAMIENTO \(aislado && cancelarOK ? "OK" : "✗") tardío=\(aislado) cancel=\(cancelarOK)")

        let base = ModoResolver.detectarExacto("modo traducir quichua", catalogo: catalogo)!
        let alineado = ModoResolver.aplicarVivo(base, al: "moldo traducir quichua Buenos días")
        let recorteOK = alineado.modo.idiomaDestino == "quichua"
            && alineado.textoLimpio == "Buenos días" && alineado.palabrasConsumidas == 3
        if !recorteOK { fallos += 1 }
        print("MODEREGRESSION RECORTE \(recorteOK ? "OK" : "✗") \(alineado.textoLimpio)")

        let t0 = Date(timeIntervalSince1970: 1_000)
        let pausaOK = !ModoPausaGate.debeConfirmar(ahora: t0.addingTimeInterval(1.9),
                                                    ultimaVoz: t0, huboVoz: true,
                                                    yaDisparada: false, segundos: 2)
            && ModoPausaGate.debeConfirmar(ahora: t0.addingTimeInterval(2),
                                           ultimaVoz: t0, huboVoz: true,
                                           yaDisparada: false, segundos: 2)
        if !pausaOK { fallos += 1 }
        print("MODEREGRESSION PAUSA \(pausaOK ? "OK" : "✗")")

        // “reproduce” y “busca” son intenciones DENTRO del modo Música. No
        // deben convertir una orden simple en una cadena música+música o
        // música+búsqueda web.
        let musicaReproducir = "modo música spotify reproduce música andina"
        let musicaBuscar = "modo música busca Julio Jaramillo"
        let reproducir = ModoResolver.detectarExacto(musicaReproducir, catalogo: catalogo)
        let buscar = ModoResolver.detectarExacto(musicaBuscar, catalogo: catalogo)
        let musicaOK = ModosStore.detectarCadena(musicaReproducir) == nil
            && ModosStore.detectarCadena(musicaBuscar) == nil
            && reproducir?.modo.id == "musica"
            && reproducir?.modo.musicaProveedor == "spotify"
            && reproducir?.textoLimpio == "reproduce música andina"
            && buscar?.modo.id == "musica"
            && buscar?.textoLimpio == "busca Julio Jaramillo"
        if !musicaOK { fallos += 1 }
        print("MODEREGRESSION MUSICA \(musicaOK ? "OK" : "✗") reproducir=\(reproducir?.textoLimpio ?? "nil") buscar=\(buscar?.textoLimpio ?? "nil")")
        print("MODEREGRESSION \(fallos == 0 ? "TODO OK" : "✗ \(fallos) FALLOS")")
        fflush(stdout)
        exit(fallos == 0 ? 0 : 3)
    }
}
