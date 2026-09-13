import Foundation

enum RecetasQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_RECIPETEST"] == "1" else { return }
        var fallos = 0
        func check(_ nombre: String, _ ok: @autoclosure () -> Bool) {
            let pasa = ok(); if !pasa { fallos += 1 }
            print("RECIPETEST \(pasa ? "OK" : "✗") \(nombre)")
        }
        func esperar(_ iniciar: (@escaping (ResultadoHerramientaApple) -> Void) -> Void,
                     segundos: TimeInterval = 3) -> ResultadoHerramientaApple? {
            var resultado: ResultadoHerramientaApple?
            iniciar { resultado = $0 }
            let limite = Date().addingTimeInterval(segundos)
            while resultado == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default,
                                        before: Date().addingTimeInterval(0.02))
            }
            return resultado
        }
        func esperarUniversal(_ orden: OrdenUniversalBeto, simular: Bool)
            -> RespuestaUniversalBeto? {
            var resultado: RespuestaUniversalBeto?
            AtajoUniversalBtoDicta.ejecutar(orden, simular: simular) { resultado = $0 }
            let limite = Date().addingTimeInterval(3)
            while resultado == nil, Date() < limite {
                _ = RunLoop.current.run(mode: .default,
                                        before: Date().addingTimeInterval(0.02))
            }
            return resultado
        }
        let incluidas = RutinasAgenteStore.incluidas()
        check("biblioteca completa", incluidas.count >= 20)
        check("categorías portables", Set(incluidas.map(\.categoria)).isSuperset(of: ["Trabajo", "Universidad", "Casa"]))
        check("resumen del día", RutinasAgenteStore.detectar(
            "Resumen del día", en: incluidas)?.rutina.id == "beto-resumen-dia")
        let planResumen = AgenteNucleo.planificar("Resumen del día",
                                                  ignorarInterruptor: true)
        check("núcleo prioriza receta sobre verbo resumir",
              planResumen?.cadena.acciones.first?.modo.prompt == "beto-resumen-dia")
        check("jornada", RutinasAgenteStore.detectar(
            "Empezar jornada", en: incluidas)?.rutina.id == "beto-empezar-jornada")
        for receta in incluidas {
            guard let frase = receta.frases.first else { continue }
            let p = AgenteNucleo.planificar(frase, ignorarInterruptor: true)
            check("núcleo enruta: \(receta.nombre)",
                  p?.cadena.acciones.first?.modo.prompt == receta.id)
        }
        check("selección prioritaria", RutinasAgenteStore.detectar(
            "Resume la selección", en: incluidas)?.rutina.id == "beto-seleccion-resumir")
        check("selección breve exacta", RutinasAgenteStore.detectarSeleccionBreve(
            "resume")?.rutina.id == "beto-seleccion-resumir")
        check("selección breve no roba contenido", RutinasAgenteStore.detectarSeleccionBreve(
            "resume el informe de mañana") == nil)
        check("selección a Notas de Apple", RutinasAgenteStore.detectar(
            "Guarda la selección en Notas de Apple", en: incluidas)?.rutina.id
                == "beto-seleccion-nota-apple")
        check("Nota de Apple es cambio local", incluidas.first(where: {
            $0.id == "beto-seleccion-nota-apple"
        }).map(RutinasAgenteStore.riesgo) == .cambioLocal)
        check("audio Finder", RutinasAgenteStore.detectar(
            "Convierte el audio seleccionado en oficio", en: incluidas)?.rutina.id == "beto-audio-oficio")
        check("no invade narración", RutinasAgenteStore.detectar(
            "Ayer escribí un resumen del día para el informe", en: incluidas) == nil)
        check("HomeKit riesgo externo", incluidas.first(where: { $0.id == "beto-apagar-luces" })
            .map(RutinasAgenteStore.riesgo) == .externo)
        var destructiva = RutinaAgente(nombre: "Cerrar apps")
        destructiva.pasos = [.init(tipo: "cerrar_apps", valor: "Word")]
        check("cerrar siempre destructivo", RutinasAgenteStore.riesgo(destructiva) == .destructivo)

        let datos = EstadoMacDatos(bateria: "80 %", discoLibre: 50 << 30, discoTotal: 100 << 30,
                                   memoriaUsada: 8 << 30, memoriaTotal: 16 << 30,
                                   cpuPorcentaje: 25, interfaces: ["en0"], vpn: ["utun4"])
        let estado = EstadoMac.formatear(datos)
        check("estado incluye seis señales", estado.contains("Batería") && estado.contains("Disco")
            && estado.contains("Memoria") && estado.contains("CPU") && estado.contains("Red")
            && estado.contains("VPN activa"))
        let agenda = ResumenDia.formatear(.init(eventos: ["09:00 reunión"],
            recordatorios: ["llamar"], calendarioDisponible: true,
            recordatoriosDisponibles: true), tareas: [])
        check("resumen agenda", agenda.contains("09:00 reunión") && agenda.contains("llamar"))

        let universal = OrdenUniversalBeto(accion: "homekit", parametros: ["atajo": "Casa · Noche"])
        check("universal estructura HomeKit", AtajoUniversalBtoDicta.paso(universal)?.tipo == "atajo")
        let listado = AppleAtajos.parsearListadoConIdentificadores(
            "Mi Atajo (con paréntesis) (91CC624C-869A-409C-80E7-6EF2BF771982)\nOtro (A07836E1-2C80-4578-98F4-AE84D6BB25E4)")
        check("descubrimiento conserva UUID y paréntesis", listado.count == 2
            && listado[0].nombre == "Mi Atajo (con paréntesis)"
            && listado[0].id == "91CC624C-869A-409C-80E7-6EF2BF771982")
        check("tres instaladores viajan con BtoDicta",
              AtajoIncluidoID.allCases.allSatisfy {
                  guard let u = AtajosIncluidos.paquete($0),
                        let a = try? FileManager.default.attributesOfItem(atPath: u.path),
                        let n = a[.size] as? NSNumber else { return false }
                  return n.intValue > 1_000
              })
        check("instalador Siri usa nombre dinámico",
              AtajosIncluidos.nombreEsperado(.asistente, nombreAgente: "Ñusta") == "Ñusta"
                && AtajosIncluidos.estaInstalado(.asistente, nombreAgente: "Ñusta",
                                                 nombres: ["Ñusta"])
                && !AtajosIncluidos.estaInstalado(.asistente, nombreAgente: "Ñusta",
                                                  nombres: ["Bto", "Gloria"]))
        let instaladorDinamico = AtajosIncluidos.paqueteParaInstalar(
            .asistente, nombreAgente: "Ñusta")
        let permisosInstalador = instaladorDinamico.flatMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.posixPermissions]
                as? NSNumber
        }?.intValue
        let mismoPaquete = instaladorDinamico.flatMap { try? Data(contentsOf: $0) }
            == AtajosIncluidos.paquete(.asistente).flatMap { try? Data(contentsOf: $0) }
        check("copia dinámica conserva firma y queda privada",
              instaladorDinamico?.lastPathComponent == "Ñusta.shortcut"
                && permisosInstalador == 0o600 && mismoPaquete)
        check("Atajo Universal reemplaza copias por receta",
              AtajosIncluidos.nombreEsperado(.universal, nombreAgente: "Otro")
                == "BtoDicta Universal")
        let paquete = PaqueteRecetasBeto(esquema: 1, nombre: "QA", creadoEn: "2026-07-19",
                                         recetas: incluidas)
        check("paquete válido", RecetasPortables.validar(paquete) == nil)
        let portable = FileManager.default.temporaryDirectory
            .appendingPathComponent("btodicta-recetas-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: portable) }
        let exportado = RecetasPortables.exportar(incluidas, a: portable)
        let atributos = try? FileManager.default.attributesOfItem(atPath: portable.path)
        let permisos = (atributos?[.posixPermissions] as? NSNumber)?.intValue
        let reimportadas: [RutinaAgente]
        if case .success(let x) = RecetasPortables.importar(desde: portable, actuales: []) {
            reimportadas = x
        } else { reimportadas = [] }
        check("paquete exporta/importa 0600", exportado.ok
            && reimportadas.count == incluidas.count && permisos == 0o600)
        var insegura = RutinaAgente(nombre: "Mala")
        insegura.pasos = [.init(tipo: "url", valor: "http://ejemplo.com/{texto}")]
        check("URL insegura bloqueada", RecetasPortables.validar(.init(
            esquema: 1, nombre: "QA", creadoEn: "", recetas: [insegura])) != nil)
        insegura.pasos = [.init(tipo: "url", valor: "https://usuario:clave@example.com/")]
        check("URL con credencial embebida bloqueada", RecetasPortables.validar(.init(
            esquema: 1, nombre: "QA", creadoEn: "", recetas: [insegura])) != nil)
        check("orden universal limita memoria",
              (try? AtajoUniversalBtoDicta.decodificar(Data(repeating: 0x20,
                                                              count: 64_001))) == nil)
        var recetaURL = RutinaAgente(nombre: "URL QA")
        recetaURL.pasos = [.init(tipo: "url",
            valor: "https://example.com/buscar?q={texto}&r={resultado}")]
        let salidaURL = esperar { RutinasAgenteRunner.ejecutar(
            rutina: recetaURL, texto: "hola mundo", simular: true, completion: $0) }
        check("URL portable codifica variables", salidaURL?.ok == true)

        // Recorre las recetas completas sin abrir apps, controlar HomeKit,
        // capturar, hablar ni escribir datos reales. Las tres escenas pueden
        // quedar denegadas si su Atajo no fue habilitado: ese bloqueo es el
        // comportamiento seguro esperado, no un fallo del motor.
        let escenas = Set(["beto-modo-oficina", "beto-modo-noche", "beto-apagar-luces"])
        for receta in incluidas {
            let r = esperar { RutinasAgenteRunner.ejecutar(
                rutina: receta, texto: "contenido de prueba", simular: true,
                completion: $0) }
            check("receta completa: \(receta.nombre)", r != nil
                && !(r?.mensaje.contains("no es compatible") ?? true)
                && ((r?.ok == true) || (escenas.contains(receta.id)
                    && (r?.mensaje.contains("no está habilitado") == true))))
        }
        if let cierre = incluidas.first(where: { $0.id == "beto-cerrar-jornada" }) {
            let r = esperar { RutinasAgenteRunner.ejecutar(
                rutina: cierre, texto: "", simular: true, completion: $0) }
            check("cierre consolida hoy y mañana", r?.mensaje.contains("Resumen del día") == true
                && r?.mensaje.contains("Preparación de mañana") == true)
        }

        for accion in AtajoUniversalBtoDicta.acciones {
            var parametros: [String: String] = ["texto": "prueba"]
            if accion == "aplicacion" { parametros["nombre"] = "Finder" }
            if ["atajo", "homekit", "foco"].contains(accion) {
                parametros["atajo"] = "BtoDicta QA inexistente"
            }
            let paso = AtajoUniversalBtoDicta.paso(.init(
                accion: accion, parametros: parametros))
            check("acción universal estructurada: \(accion)", paso != nil
                && RecetasPortables.tiposPermitidos.contains(paso!.tipo))
        }
        let externoSinConfirmar = esperarUniversal(.init(
            accion: "homekit", parametros: ["atajo": "BtoDicta QA inexistente"]),
            simular: false)
        check("universal externo exige confirmación", externoSinConfirmar?.ok == false
            && externoSinConfirmar?.evidencia["requiere_confirmacion"] == "true")
        let atajoDesconocido = esperar {
            AppleAtajos.ejecutarVerificado(nombre: "BtoDicta QA \(UUID().uuidString)",
                                            texto: "", simular: true, completion: $0)
        }
        check("Atajo desconocido no se autoautoriza", atajoDesconocido?.ok == false)

        print(fallos == 0 ? "RECIPETEST TODO OK" : "RECIPETEST ✗ \(fallos) FALLOS")
        fflush(stdout); exit(fallos == 0 ? 0 : 4)
    }
}
