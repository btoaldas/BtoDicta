// BetoDicta v0.2 — dictado por voz para macOS
// <tecla>: abre panel y graba · <tecla> otra vez: transcribe y pega
// Streaming en vivo (scribe_v2_realtime) o batch (scribe_v1 / scribe_v2)
//
// Config ~/.betodicta/config.json: {"tecla": "fn", "modelo": "scribe_v2_realtime"}
//   tecla: fn | F1..F12
//   modelo: scribe_v2_realtime (texto en vivo) | scribe_v2 | scribe_v1 (batch)
// ~/.betodicta/keyterms.txt — una palabra por línea (streaming usa las primeras 50)
// ~/.betodicta/reemplazos.json — [{"original":"a, b","replacement":"X"}]
// API keys: en ~/.betodicta/.env — se ponen desde Configuración → Modelos

import AppKit

// Puente para UN Atajo universal de macOS:
//   BetoDicta --universal-input orden.json --universal-output respuesta.json
// Corre antes de crear NSApplication, devuelve evidencia JSON y termina. El
// Atajo puede usar el archivo de entrada/salida sin acceder a claves de la app.
let argumentos = CommandLine.arguments
if let i = argumentos.firstIndex(of: "--universal-input"), i + 1 < argumentos.count,
   let o = argumentos.firstIndex(of: "--universal-output"), o + 1 < argumentos.count {
    let entrada = URL(fileURLWithPath: argumentos[i + 1])
    let salida = URL(fileURLWithPath: argumentos[o + 1])
    let respuesta: RespuestaUniversalBeto
    do {
        let orden = try AtajoUniversalBetoDicta.decodificar(desde: entrada)
        var recibida: RespuestaUniversalBeto?
        AtajoUniversalBetoDicta.ejecutar(orden) { recibida = $0 }
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
        try AtajoUniversalBetoDicta.respuestaJSON(respuesta).write(to: salida, options: .atomic)
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
if let dmg = ProcessInfo.processInfo.environment["BETODICTA_DMGVERIFYTEST"],
   let sig = ProcessInfo.processInfo.environment["BETODICTA_DMGVERIFY_SIG"],
   let firma = try? Data(contentsOf: URL(fileURLWithPath: sig)) {
    let ok = Updater.firmaDMGValida(URL(fileURLWithPath: dmg), firma: firma)
    print("DMGVERIFYTEST \(ok ? "OK" : "FALLA")")
    exit(ok ? 0 : 3)
}
if let appPath = ProcessInfo.processInfo.environment["BETODICTA_VERIFYTEST"] {
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
if ProcessInfo.processInfo.environment["BETODICTA_VOXTRALPAYLOADTEST"] == "1" {
    if let problema = VoxtralServer.problemaPayloadQA() {
        print("VOXTRALPAYLOADTEST FALLA: \(problema)")
        fflush(stdout); exit(1)
    }
    print("VOXTRALPAYLOADTEST TODO OK — texto primero, WAV íntegro después")
    fflush(stdout); exit(0)
}
if ProcessInfo.processInfo.environment["BETODICTA_WAKEWORDTEST"] == "1" {
    let (ok, lineas) = ActivacionVoz.ejecutarQA()
    lineas.forEach { print("WAKETEST \($0)") }
    print("WAKETEST \(ok ? "TODO OK" : "FALLA")")
    fflush(stdout); exit(ok ? 0 : 3)
}
if let ruta = ProcessInfo.processInfo.environment["BETODICTA_WAKEAUDIOTEST"],
   !ruta.isEmpty {
    let frase = ProcessInfo.processInfo.environment["BETODICTA_WAKEPHRASE"]
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
if let consulta = ProcessInfo.processInfo.environment["BETODICTA_CLIMALIVETEST"],
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
    let mensaje = "BetoDicta: no hay sesión gráfica; la interfaz no puede arrancar en este contexto.\n" +
        "Los modos QA (variables BETODICTA_*) sí funcionan aquí.\n"
    FileHandle.standardError.write(Data(mensaje.utf8))
    exit(78) // EX_CONFIG
}

let app = NSApplication.shared
app.setActivationPolicy(Config.showInDock() ? .regular : .accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
