// BtoDicta v0.2 — dictado por voz para macOS
// <tecla>: abre panel y graba · <tecla> otra vez: transcribe y pega
// Streaming en vivo (scribe_v2_realtime) o batch (scribe_v1 / scribe_v2)
//
// Config ~/.btodicta/config.json: {"tecla": "fn", "modelo": "scribe_v2_realtime"}
//   tecla: fn | F1..F12
//   modelo: scribe_v2_realtime (texto en vivo) | scribe_v2 | scribe_v1 (batch)
// ~/.btodicta/keyterms.txt — una palabra por línea (streaming usa las primeras 50)
// ~/.btodicta/reemplazos.json — [{"original":"a, b","replacement":"X"}]
// API keys: en ~/.btodicta/.env — se ponen desde Configuración → Modelos

import AppKit

// Puente de mudanza: este mismo binario, metido en un bundle con el nombre y el
// identificador ANTERIORES, no dicta nada — solo abre el asistente que instala
// la aplicación nueva. Va lo primero de todo y no toca ni un dato del usuario.
if AsistenteMudanza.esPuente {
    // Comprobación del puente sin abrir ventana: BTODICTA_PUENTETEST=1.
    // Un puente sin la clave pública no puede verificar ninguna descarga y su
    // instalación automática falla al final, cuando el usuario ya confió en
    // ella. Se comprueba aquí, en el propio bundle empaquetado.
    if ProcessInfo.processInfo.environment["BTODICTA_PUENTETEST"] == "1" {
        let id = Bundle.main.bundleIdentifier ?? "?"
        let clave = Bundle.main.url(forResource: "update-public-key", withExtension: "der")
        let cert = Bundle.main.url(forResource: "code-signing-cert", withExtension: "der")
        print("PUENTETEST identificador=\(id)")
        print("PUENTETEST clave de verificación: \(clave != nil ? "presente" : "AUSENTE")")
        print("PUENTETEST certificado de identidad: \(cert != nil ? "presente" : "AUSENTE")")
        let ok = id == AsistenteMudanza.identificadorAnterior && clave != nil && cert != nil
        print("PUENTETEST \(ok ? "TODO OK" : "FALLA")")
        exit(ok ? 0 : 1)
    }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let asistente = AsistenteMudanza()
        // El delegado lo retiene la propia aplicación mientras corre.
        objc_setAssociatedObject(app, "asistenteMudanza", asistente, .OBJC_ASSOCIATION_RETAIN)
        app.delegate = asistente
        app.run()
    }
    exit(0)
}

// La app se llamaba BetoDicta: lo PRIMERO es poner sus carpetas a nombre del
// nuevo, antes de que nadie lea configuración ni abra un índice. Ver Rebautizo.
Rebautizo.aplicar()

// Puente para UN Atajo universal de macOS:
//   BtoDicta --universal-input orden.json --universal-output respuesta.json
// Corre antes de crear NSApplication, devuelve evidencia JSON y termina. El
// Atajo puede usar el archivo de entrada/salida sin acceder a claves de la app.
let argumentos = CommandLine.arguments
if let i = argumentos.firstIndex(of: "--universal-input"), i + 1 < argumentos.count,
   let o = argumentos.firstIndex(of: "--universal-output"), o + 1 < argumentos.count {
    let entrada = URL(fileURLWithPath: argumentos[i + 1])
    let salida = URL(fileURLWithPath: argumentos[o + 1])
    let respuesta: RespuestaUniversalBeto
    do {
        let orden = try AtajoUniversalBtoDicta.decodificar(desde: entrada)
        var recibida: RespuestaUniversalBeto?
        AtajoUniversalBtoDicta.ejecutar(orden) { recibida = $0 }
        let limite = Date().addingTimeInterval(120)
        while recibida == nil, Date() < limite {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        respuesta = recibida ?? .init(ok: false,
            mensaje: "La acción universal excedió 120 segundos.",
            evidencia: ["timeout": "true"])
    } catch {
        respuesta = .init(ok: false, mensaje: error.localizedDescription,
                          evidencia: ["entrada_valida": "false"])
    }
    do {
        try AtajoUniversalBtoDicta.respuestaJSON(respuesta).write(to: salida, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: salida.path)
    } catch {
        FileHandle.standardError.write(Data("No pude escribir la evidencia: \(error.localizedDescription)\n".utf8))
        exit(3)
    }
    print(respuesta.mensaje); exit(respuesta.ok ? 0 : 2)
}

// Hooks puros del pipeline de release. Corren antes de crear NSApplication para
// que también funcionen con la app instalada cerrada y en una sesión sin GUI.
if let dmg = ProcessInfo.processInfo.environment["BTODICTA_DMGVERIFYTEST"],
   let sig = ProcessInfo.processInfo.environment["BTODICTA_DMGVERIFY_SIG"],
   let firma = try? Data(contentsOf: URL(fileURLWithPath: sig)) {
    let ok = Updater.firmaDMGValida(URL(fileURLWithPath: dmg), firma: firma)
    print("DMGVERIFYTEST \(ok ? "OK" : "FALLA")")
    exit(ok ? 0 : 3)
}
if let appPath = ProcessInfo.processInfo.environment["BTODICTA_VERIFYTEST"] {
    // El hook del pipeline se ejecuta después de verificar la firma Ed25519
    // del DMG, igual que el actualizador real.
    let ok = Updater.firmaConfiable(URL(fileURLWithPath: appPath), contenidoAutenticado: true)
    print("VERIFYTEST \(appPath) -> identidadConfiable=\(ok)")
    exit(ok ? 0 : 3)
}

AutoAyudaQA.ejecutarSiSePidio()
PermisosSistemaQA.ejecutarSiSePidio()
ModoPlanQA.ejecutarSiSePidio()
ModoRegressionQA.ejecutarSiSePidio()
MatrizModosQA.ejecutarSiSePidio()
ModoAudioQA.ejecutarSiSePidio()
ModoIAQA.ejecutarSiSePidio()
AplicacionesMacQA.ejecutarSiSePidio()
AgenteCoreQA.ejecutarSiSePidio()
CascadaArchivoQA.ejecutarSiSePidio()
RecetasQA.ejecutarSiSePidio()
ConexionesQA.ejecutarSiSePidio()
TareasQA.ejecutarSiSePidio()
CatalogoQA.ejecutarSiSePidio()
ClimaQA.ejecutarSiSePidio()
VolumenMacQA.ejecutarSiSePidio()
AgenteCodex.ejecutarPruebaSiSePidio()
DocumentosMac.ejecutarPruebaSiSePidio()
NotasApple.ejecutarPruebaSiSePidio()
VozLocalQA.ejecutarSiSePidio()
TareasNotasQA.ejecutarSiSePidio()
if ProcessInfo.processInfo.environment["BTODICTA_VOXTRALPAYLOADTEST"] == "1" {
    if let problema = VoxtralServer.problemaPayloadQA() {
        print("VOXTRALPAYLOADTEST FALLA: \(problema)")
        fflush(stdout); exit(1)
    }
    print("VOXTRALPAYLOADTEST TODO OK — texto primero, WAV íntegro después")
    fflush(stdout); exit(0)
}
if ProcessInfo.processInfo.environment["BTODICTA_WAKEWORDTEST"] == "1" {
    let (ok, lineas) = ActivacionVoz.ejecutarQA()
    lineas.forEach { print("WAKETEST \($0)") }
    print("WAKETEST \(ok ? "TODO OK" : "FALLA")")
    fflush(stdout); exit(ok ? 0 : 3)
}
if let ruta = ProcessInfo.processInfo.environment["BTODICTA_WAKEAUDIOTEST"],
   !ruta.isEmpty {
    let frase = ProcessInfo.processInfo.environment["BTODICTA_WAKEPHRASE"]
        ?? Config.agenteActivadores().first
        ?? "oye \(Config.agenteNombre())"
    guard let wav = try? Data(contentsOf: URL(fileURLWithPath: ruta)) else {
        print("WAKEAUDIOTEST FALLA no pude leer \(ruta)"); exit(4)
    }
    var recibido: Result<String, Swift.Error>?
    AppleSpeechSTT.run(wav: wav) { recibido = $0 }
    let limite = Date().addingTimeInterval(90)
    while recibido == nil, Date() < limite {
        _ = RunLoop.current.run(mode: .default,
                                before: Date().addingTimeInterval(0.05))
    }
    guard let recibido else { print("WAKEAUDIOTEST FALLA timeout"); exit(5) }
    switch recibido {
    case .success(let texto):
        let inv = PerfilAgente.invocacionTolerante(en: texto, activadores: [frase])
        let ok = inv != nil
        print("WAKEAUDIOTEST \(ok ? "OK" : "FALLA") frase=\(frase) texto=\(texto) contenido=\(inv?.contenido ?? "")")
        exit(ok ? 0 : 3)
    case .failure(let error):
        print("WAKEAUDIOTEST FALLA \(error.localizedDescription)"); exit(6)
    }
}

// Consulta meteorológica real de integración, sin abrir la interfaz. Requiere
// una ciudad explícita para no solicitar ubicación desde un proceso de QA.
if let consulta = ProcessInfo.processInfo.environment["BTODICTA_CLIMALIVETEST"],
   !consulta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    var recibido: ResultadoHerramientaApple?
    ClimaServicio.consultar(consulta) { recibido = $0 }
    let limite = Date().addingTimeInterval(25)
    while recibido == nil, Date() < limite {
        _ = RunLoop.current.run(mode: .default,
                                before: Date().addingTimeInterval(0.05))
    }
    let r = recibido ?? .init(ok: false, mensaje: "La consulta meteorológica excedió 25 segundos.")
    print("CLIMALIVETEST \(r.ok ? "OK" : "FALLA") | \(r.mensaje)")
    fflush(stdout); exit(r.ok ? 0 : 13)
}

// Sin sesión gráfica (SSH, sandbox de un agente, launchd de fondo) AppKit
// aborta en _RegisterApplication al crear NSApplication. Los modos QA de
// arriba ya corrieron; aquí toca avisar y salir limpio en vez de crashear.
guard SesionGUI.disponible else {
    let mensaje = "BtoDicta: no hay sesión gráfica; la interfaz no puede arrancar en este contexto.\n" +
        "Los modos QA (variables BTODICTA_*) sí funcionan aquí.\n"
    FileHandle.standardError.write(Data(mensaje.utf8))
    exit(78) // EX_CONFIG
}

let app = NSApplication.shared
app.setActivationPolicy(Config.showInDock() ? .regular : .accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
