import Foundation

/// QA puro del modo Aplicación. Inventaría y resuelve, pero NO abre apps, NO pega
/// texto y NO modifica la configuración. Uso: BTODICTA_APPTEST=1 <binario>.
enum AplicacionesMacQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_APPTEST"] == "1" else { return }
        var fallos = 0
        func validar(_ condicion: @autoclosure () -> Bool, _ nombre: String) {
            let ok = condicion()
            if !ok { fallos += 1 }
            print("APPTEST \(ok ? "OK" : "✗") \(nombre)")
        }

        let instaladas = AplicacionesMac.refrescar()
        validar(instaladas.count >= 20, "inventario=\(instaladas.count)")
        let claves = instaladas.map { $0.bundleId.isEmpty ? $0.ruta.lowercased() : $0.bundleId.lowercased() }
        validar(Set(claves).count == claves.count, "sin bundle/rutas duplicadas")
        validar(instaladas.contains(where: { $0.bundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame }),
                "Microsoft Word detectado")

        func encontrada(_ tokens: [String]) -> CoincidenciaAplicacionMac? {
            guard case .encontrada(let m) = AplicacionesMac.resolverPrefijo(tokens) else { return nil }
            return m
        }
        let word = encontrada(["word", "borrador", "del", "informe"])
        validar(word?.app.bundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
            && word?.palabrasConsumidas == 1, "Word + contenido")
        let microsoftWord = encontrada(["microsoft", "word", "borrador"])
        validar(microsoftWord?.app.bundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
            && microsoftWord?.palabrasConsumidas == 2, "prefijo más largo Microsoft Word")
        let world = encontrada(["world", "borrador"])
        validar(world?.app.bundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame,
                "alias STT World → Word")

        let fixture = [
            AplicacionMac(nombre: "Antigravity", bundleId: "test.antigravity", ruta: "/Applications/Antigravity.app",
                          alias: ["antigravity"]),
            AplicacionMac(nombre: "Antigravity IDE", bundleId: "test.antigravity.ide", ruta: "/Applications/Antigravity IDE.app",
                          alias: ["antigravity ide"]),
            AplicacionMac(nombre: "Editor Uno", bundleId: "test.editor.uno", ruta: "/Applications/Editor Uno.app",
                          alias: ["editor"]),
            AplicacionMac(nombre: "Editor Dos", bundleId: "test.editor.dos", ruta: "/Applications/Editor Dos.app",
                          alias: ["editor"]),
            AplicacionMac(nombre: "PowerPoint", bundleId: "test.powerpoint", ruta: "/Applications/PowerPoint.app",
                          alias: ["powerpoint"])
        ]
        if case .encontrada(let m) = AplicacionesMac.resolverPrefijo(["antigravity", "ide", "texto"], en: fixture) {
            validar(m.app.bundleId == "test.antigravity.ide" && m.palabrasConsumidas == 2,
                    "longest-prefix elige Antigravity IDE")
        } else { validar(false, "longest-prefix elige Antigravity IDE") }
        if case .ambiguas(let m) = AplicacionesMac.resolverPrefijo(["editor", "texto"], en: fixture) {
            validar(m.count == 2, "empate devuelve modal, no adivina")
        } else { validar(false, "empate devuelve modal, no adivina") }
        if case .encontrada(let m) = AplicacionesMac.resolverPrefijo(["powerpoin", "texto"], en: fixture) {
            validar(m.app.bundleId == "test.powerpoint" && !m.exacta, "fuzzy conservador")
        } else { validar(false, "fuzzy conservador") }
        if case .ninguna = AplicacionesMac.resolverPrefijo(["puerta", "principal"], en: fixture) {
            validar(true, "desconocida no abre nada")
        } else { validar(false, "desconocida no abre nada") }

        if Config.modoAplicaciones() {
            let catalogo = ModoCatalogo(modos: ModosStore.base)
            let explicito = ModoResolver.detectarExacto(
                "modo abrir aplicación Word, borrador del informe", catalogo: catalogo)
            validar(explicito?.modo.base == "aplicacion"
                && explicito?.modo.appBundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
                && explicito?.textoLimpio == "borrador del informe",
                "comando explícito resuelve y recorta")
            if let vivo = ModoResolver.detectarExacto("modo abrir aplicación Word", catalogo: catalogo) {
                let final = ModoResolver.aplicarVivo(vivo,
                    al: "modo abrir aplicación Word Pages es parte del contenido")
                validar(final.modo.appBundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
                    && final.textoLimpio == "Pages es parte del contenido",
                    "respaldo vivo no confunde contenido con otra app")
            } else { validar(false, "respaldo vivo no confunde contenido con otra app") }

            let natural = ModoPlanificador.detectarNatural(
                "Por favor abre Word: borrador del informe.", catalogo: catalogo)
            validar(natural?.cadena.acciones.first?.modo.base == "aplicacion"
                && natural?.cadena.acciones.first?.modo.appBundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
                && natural?.cadena.contenido == "borrador del informe.",
                "pedido natural propone confirmación")

            let naturalLargo = ModoPlanificador.detectarNatural(
                "Por favor abre la aplicación Microsoft Word: acta de la reunión.", catalogo: catalogo)
            validar(naturalLargo?.cadena.acciones.first?.modo.base == "aplicacion"
                && naturalLargo?.cadena.acciones.first?.modo.appBundleId.caseInsensitiveCompare("com.microsoft.Word") == .orderedSame
                && naturalLargo?.cadena.contenido == "acta de la reunión.",
                "pedido natural con «la aplicación»")

            let naturalCorrido = ModoPlanificador.detectarNatural(
                "Por favor abre Word y escribe borrador del informe", catalogo: catalogo)
            validar(naturalCorrido?.cadena.acciones.first?.modo.base == "aplicacion"
                && naturalCorrido?.cadena.contenido == "borrador del informe",
                "pedido corrido «abre Word y escribe…»")

            let cadena = ModosStore.detectarCadena(
                "modo traducir inglés abrir aplicación Word, good morning")
            validar(cadena?.transforms.map(\.id) == ["traducir"]
                && cadena?.acciones.first?.modo.base == "aplicacion"
                && cadena?.contenido == "good morning",
                "cadena traducir → Word")
        } else {
            print("APPTEST SKIP integración de voz: modo desactivado por el usuario")
        }

        let catalogoNeg = ModoCatalogo(modos: ModosStore.base)
        let negativos = [
            "Word es una aplicación para escribir documentos",
            "La guía explica cómo abrir Word desde Finder",
            "El modo de aplicación del reglamento es obligatorio",
            "Abre la puerta principal, por favor"
        ]
        for texto in negativos {
            let plan = ModoPlanificador.detectarNatural(texto, catalogo: catalogoNeg)
            validar(plan == nil, "NEG \(texto)")
        }

        print("APPTEST \(fallos == 0 ? "TODO OK" : "✗ \(fallos) FALLOS")")
        fflush(stdout)
        exit(fallos == 0 ? 0 : 4)
    }
}
