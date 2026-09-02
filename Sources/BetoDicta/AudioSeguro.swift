import AVFoundation
import BDObjC

// MARK: - Audio a prueba de caídas (AVAudioEngine + AVAudioPlayerNode)
//
// AVFoundation señala varios fallos como NSException, NO como Error de Swift:
// "player started when engine not running", "player started when in a disconnected
// state"… Pasan cuando el dispositivo de salida cambió o desapareció (pantalla con
// parlantes apagada, AirPlay caído) entre el connect y el play. Swift no puede
// atraparlas → la app ABORTA entera. Así murió BetoDicta cuatro días seguidos a las
// 20:00 (ago-2026) al hablar el resumen vespertino con ElevenLabs.
//
// Aquí todo pasa por un @try/@catch de ObjC (BDAtraparExcepcion) y cualquier fallo se
// convierte en `false` → el llamador hace failover al siguiente motor de voz. Nunca cae.

enum AudioSeguro {
    /// Atrapa NSException de cualquier bloque (nil = sin excepción). Expuesto para tests.
    static func atrapar(_ bloque: () -> Void) -> String? { BDAtraparExcepcion(bloque) }

    /// Arranca motor + reproductor. `false` = no se pudo (ya quedó en el log) → failover.
    @discardableResult
    static func arrancar(_ engine: AVAudioEngine, _ player: AVAudioPlayerNode, contexto: String) -> Bool {
        guard arrancarMotor(engine, player, contexto: contexto) else { return false }
        return reproducir(player, contexto: contexto)
    }

    /// Solo el motor (el play va después, cuando haya audio encolado).
    static func arrancarMotor(_ engine: AVAudioEngine, _ player: AVAudioPlayerNode, contexto: String) -> Bool {
        var canales: UInt32 = 0
        if let ex = BDAtraparExcepcion({ canales = engine.outputNode.outputFormat(forBus: 0).channelCount }) {
            Log.log(.ia, "audio [\(contexto)]: sin salida de audio (\(ex)) → failover"); return false
        }
        guard canales > 0 else {
            Log.log(.ia, "audio [\(contexto)]: no hay dispositivo de salida → failover"); return false
        }
        var fallo: String?
        if let ex = BDAtraparExcepcion({
            do { try engine.start() } catch { fallo = error.localizedDescription }
        }) { fallo = ex }
        if let fallo {
            Log.log(.ia, "audio [\(contexto)]: el motor no arrancó (\(fallo)) → failover"); return false
        }
        guard engine.isRunning, player.engine != nil else {
            Log.log(.ia, "audio [\(contexto)]: motor detenido o nodo desconectado → failover"); return false
        }
        return true
    }

    /// play() sin poder tumbar la app.
    static func reproducir(_ player: AVAudioPlayerNode, contexto: String) -> Bool {
        guard let engine = player.engine, engine.isRunning else {
            Log.log(.ia, "audio [\(contexto)]: play con el motor detenido → failover"); return false
        }
        if let ex = BDAtraparExcepcion({ player.play() }) {
            Log.log(.ia, "audio [\(contexto)]: play lanzó \(ex) → failover"); return false
        }
        return true
    }
}
