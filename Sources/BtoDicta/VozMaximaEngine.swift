import Foundation

// MARK: - Voz local MÁXIMA (XTTS afinado + Resemble Enhance)
//
// Réplica gestionada del perfil de mayor identidad que se validó con Hermes, pero sin
// invocar Hermes ni scripts de Descargas. El clon (modelo + referencias + persona) vive
// en ~/.btodicta/voces/<id>; este runtime COMÚN vive aislado en voz-engine/maxima/.
//
// Receta reproducida:
//   1. XTTS del paquete con temperature=.55, length_penalty=1, repetition_penalty=5,
//      top_k=30, top_p=.80.
//   2. Resemble Enhance: NFE=128, tau=.15, lambda=.5, solver=midpoint, CPU.
//   3. Normalización -18 LUFS / -2 dBTP cuando ffmpeg está disponible; si no, una
//      normalización local conservadora. Enhance es opcional en ejecución: si falla,
//      se entrega XTTS crudo, nunca se deja al asistente sin voz.

enum VozMaximaEngine {
    static let version = "1"
    static var dir: URL { VozEngine.dir.appendingPathComponent("maxima") }
    static var pythonURL: URL { dir.appendingPathComponent("venv/bin/python") }
    private static var modeloDir: URL { dir.appendingPathComponent("model/enhancer_stage2") }
    private static var scriptURL: URL { dir.appendingPathComponent("enhance_clip.py") }
    private static var normalizarURL: URL { dir.appendingPathComponent("normalizar.py") }
    private static var marcador: URL { dir.appendingPathComponent(".listo-\(version)") }

    enum Estado { case noInstalado, instalando, listo }
    private(set) static var instalando = false

    private static let pins = [
        "torch==2.1.1", "torchaudio==2.1.1", "torchvision==0.16.1",
        "resemble-enhance==0.0.1", "deepspeed==0.12.4",
        "numpy==1.26.2", "scipy==1.11.4", "librosa==0.10.1",
        "soundfile==0.12.1", "omegaconf==2.3.0"
    ]

    private struct Recurso {
        let relativo: String
        let url: String
        let sha256: String
    }

    private static let recursos = [
        Recurso(relativo: "hparams.yaml",
                url: "https://huggingface.co/ResembleAI/resemble-enhance/resolve/main/enhancer_stage2/hparams.yaml",
                sha256: "80c3f15bc5a5b2cacf2c698699a0f6599d62911c0d53e1d6dee895c0d7cbaeac"),
        Recurso(relativo: "ds/G/default/mp_rank_00_model_states.pt",
                url: "https://huggingface.co/ResembleAI/resemble-enhance/resolve/main/enhancer_stage2/ds/G/default/mp_rank_00_model_states.pt",
                sha256: "f9d035f318de3e6d919bc70cf7ad7d32b4fe92ec5cbe0b30029a27f5db07d9d6")
    ]

    static func estado() -> Estado {
        if instalando { return .instalando }
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path),
              FileManager.default.fileExists(atPath: marcador.path),
              recursos.allSatisfy({ FileManager.default.fileExists(
                  atPath: modeloDir.appendingPathComponent($0.relativo).path) })
        else { return .noInstalado }
        return .listo
    }

    /// Instalación explícita desde la GUI. Crea un Python propio y verifica los pesos
    /// oficiales por SHA-256 antes de marcarlos listos.
    static func instalar(onProgreso: @escaping (String) -> Void,
                         completion: @escaping (Bool, String) -> Void) {
        if estado() == .listo { completion(true, "La restauración Máxima ya está instalada."); return }
        guard VozEngine.estado() == .listo else {
            completion(false, "Primero instala el motor XTTS local."); return
        }
        guard !instalando else { completion(false, "Ya se está instalando."); return }
        instalando = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try instalarSincrono(onProgreso: onProgreso)
                instalando = false
                DispatchQueue.main.async { completion(true, "Restauración Máxima instalada y verificada.") }
            } catch {
                instalando = false
                DispatchQueue.main.async {
                    completion(false, "Falló la instalación Máxima: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Misma ruta que usa la GUI, expuesta para QA/migraciones reproducibles.
    static func instalarSincrono(onProgreso: @escaping (String) -> Void) throws {
        Config.asegurarDirSeguro()
        try FileManager.default.createDirectory(at: modeloDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let uv = try VozEngine.uvBin(onProgreso)
        if !FileManager.default.isExecutableFile(atPath: pythonURL.path) {
            onProgreso("Creando Python aislado para la restauración…")
            try VozEngine.correrUv(uv, ["venv", "--python", "3.11",
                                        dir.appendingPathComponent("venv").path], onProgreso)
        }
        onProgreso("Instalando Resemble Enhance con versiones verificadas…")
        try VozEngine.correrUv(uv, ["pip", "install", "--python", pythonURL.path] + pins,
                               onProgreso)
        for recurso in recursos {
            try asegurar(recurso, onProgreso: onProgreso)
        }
        try enhancePy.write(to: scriptURL, atomically: true, encoding: .utf8)
        try normalizarPy.write(to: normalizarURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: normalizarURL.path)
        FileManager.default.createFile(atPath: marcador.path, contents: Data())
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marcador.path)
        guard estado() == .listo else { throw ErrorInstalacion.incompleto }
    }

    private static func asegurar(_ recurso: Recurso,
                                 onProgreso: @escaping (String) -> Void) throws {
        let destino = modeloDir.appendingPathComponent(recurso.relativo)
        if sha256(destino) == recurso.sha256 {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                    ofItemAtPath: destino.path)
            return
        }
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])

        // Migración sin red: se acepta el caché anterior SOLO si el hash oficial coincide.
        let base = URL(fileURLWithPath: (Config.vozClonBase() as NSString).expandingTildeInPath)
        let legado = base.appendingPathComponent(
            ".venv-enh/lib/python3.11/site-packages/resemble_enhance/model_repo/enhancer_stage2")
            .appendingPathComponent(recurso.relativo)
        if sha256(legado) == recurso.sha256 {
            onProgreso("Migrando \(destino.lastPathComponent) al entorno propio de BtoDicta…")
            try FileManager.default.copyItem(at: legado, to: destino)
        } else {
            onProgreso("Descargando \(destino.lastPathComponent) desde ResembleAI…")
            let temporal = destino.appendingPathExtension("download")
            try? FileManager.default.removeItem(at: temporal)
            try VozEngine.correrComando("/usr/bin/curl", ["--fail", "--location", "--retry", "3",
                                                               "--output", temporal.path, recurso.url], onProgreso)
            guard sha256(temporal) == recurso.sha256 else {
                try? FileManager.default.removeItem(at: temporal)
                throw ErrorInstalacion.hash(destino.lastPathComponent)
            }
            try FileManager.default.moveItem(at: temporal, to: destino)
        }
        guard sha256(destino) == recurso.sha256 else {
            throw ErrorInstalacion.hash(destino.lastPathComponent)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destino.path)
    }

    /// Genera y restaura usando únicamente el paquete y runtimes gestionados de BtoDicta.
    static func decir(voz: VozLocal, texto: String, completion: @escaping (URL?) -> Void) {
        guard estado() == .listo, voz.maximaInterna, !voz.paquete.isEmpty else {
            completion(nil); return
        }
        let paquete = URL(fileURLWithPath: voz.paquete)
        generarCrudo(paquete: paquete, texto: texto) { crudo in
            guard let crudo else { completion(nil); return }
            DispatchQueue.global(qos: .userInitiated).async {
                let id = UUID().uuidString
                let restaurado = FileManager.default.temporaryDirectory
                    .appendingPathComponent("btodicta-maxima-\(id)-restaurada.wav")
                let salida = FileManager.default.temporaryDirectory
                    .appendingPathComponent("btodicta-maxima-\(id).wav")
                var fuente = crudo
                do {
                    try VozEngine.correrComando(pythonURL.path,
                        [scriptURL.path, crudo.path, restaurado.path, modeloDir.path]) { _ in }
                    if FileManager.default.fileExists(atPath: restaurado.path) { fuente = restaurado }
                } catch {
                    Log.log(.ia, "Voz Máxima: Enhance falló; continúo con XTTS crudo (\(error.localizedDescription))")
                }
                let normalizada = normalizar(fuente, a: salida)
                if !normalizada {
                    try? FileManager.default.removeItem(at: salida)
                    try? FileManager.default.copyItem(at: fuente, to: salida)
                }
                if crudo != salida { try? FileManager.default.removeItem(at: crudo) }
                try? FileManager.default.removeItem(at: restaurado)
                let ok = FileManager.default.fileExists(atPath: salida.path)
                DispatchQueue.main.async {
                    completion(ok ? salida : nil)
                    if ok {
                        DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                            try? FileManager.default.removeItem(at: salida)
                        }
                    }
                }
            }
        }
    }

    private static func generarCrudo(paquete: URL, texto: String,
                                     completion: @escaping (URL?) -> Void) {
        let desdeServidor = {
            XttsServer.generarWav(texto: texto, completion: completion)
        }
        if XttsServer.corriendo, XttsServer.paqueteActivo == paquete.path {
            desdeServidor(); return
        }
        if Config.ttsXttsPreactivar() {
            XttsServer.asegurar(paquete: paquete) { listo in
                if listo { desdeServidor() }
                else { VozEngine.correrPaquete(carpeta: paquete, texto: texto, completion: completion) }
            }
        } else {
            VozEngine.correrPaquete(carpeta: paquete, texto: texto, completion: completion)
        }
    }

    private static func normalizar(_ origen: URL, a salida: URL) -> Bool {
        let candidatos = [Bundle.main.resourceURL?.appendingPathComponent("bin/ffmpeg").path,
                          "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .compactMap { $0 }
        if let ffmpeg = candidatos.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            do {
                try VozEngine.correrComando(ffmpeg, ["-y", "-v", "error", "-i", origen.path,
                    "-af", "loudnorm=I=-18:TP=-2", "-codec:a", "pcm_s16le", salida.path]) { _ in }
                return FileManager.default.fileExists(atPath: salida.path)
            } catch { Log.log(.ia, "Voz Máxima: ffmpeg no normalizó; uso normalizador interno") }
        }
        do {
            try VozEngine.correrComando(pythonURL.path,
                [normalizarURL.path, origen.path, salida.path]) { _ in }
            return FileManager.default.fileExists(atPath: salida.path)
        } catch { return false }
    }

    static func desinstalar() {
        try? FileManager.default.removeItem(at: dir)
    }

    private static func sha256(_ archivo: URL) -> String? {
        guard FileManager.default.fileExists(atPath: archivo.path) else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        p.arguments = ["-a", "256", archivo.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        guard p.terminationStatus == 0,
              let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else { return nil }
        return s.split(separator: " ").first.map(String.init)
    }

    private enum ErrorInstalacion: Error, LocalizedError {
        case incompleto, hash(String)
        var errorDescription: String? {
            switch self {
            case .incompleto: return "el runtime quedó incompleto"
            case .hash(let f): return "la firma SHA-256 no coincide para \(f)"
            }
        }
    }

    private static let enhancePy = #"""
import sys, warnings, torch, torchaudio
from pathlib import Path
warnings.filterwarnings("ignore")
raw, out, model_root = sys.argv[1], sys.argv[2], Path(sys.argv[3])
import resemble_enhance.enhancer.download as _dl
_dl.download = lambda: model_root
import resemble_enhance.enhancer.inference as _inf
_inf.download = lambda: model_root
from resemble_enhance.enhancer.inference import enhance
dwav, sr = torchaudio.load(raw)
dwav = dwav.mean(0)
wav, new_sr = enhance(dwav, sr, "cpu", nfe=128, solver="midpoint", lambd=0.5, tau=0.15)
torchaudio.save(out, wav.unsqueeze(0).cpu(), new_sr)
print("OK", out)
"""#

    private static let normalizarPy = #"""
import sys, numpy as np, soundfile as sf
x, sr = sf.read(sys.argv[1], always_2d=True, dtype="float32")
rms = float(np.sqrt(np.mean(np.square(x)) + 1e-12))
target = 10.0 ** (-18.0 / 20.0)
if rms > 0: x = x * (target / rms)
peak = float(np.max(np.abs(x)) + 1e-12)
ceiling = 10.0 ** (-2.0 / 20.0)
if peak > ceiling: x = x * (ceiling / peak)
sf.write(sys.argv[2], x, sr, subtype="PCM_16")
print("OK", sys.argv[2])
"""#
}
