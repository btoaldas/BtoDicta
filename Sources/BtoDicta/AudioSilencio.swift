import Foundation

// MARK: - ¿Suena algo aquí?
//
// La bitácora graba de continuo, y buena parte de lo que graba es silencio:
// nadie habla, o se está delante del equipo sin decir nada. Medido en esta
// máquina, el 36 % de los trozos.
//
// Cada uno de esos se mandaba igual a un motor de transcripción. El motor
// contestaba «respuesta sin texto» —con razón, no había nada que transcribir—,
// la cascada lo tomaba por un FALLO y probaba con el siguiente motor, y con el
// siguiente. En un solo día se contaron 312 llamadas gastadas así.
//
// Mirar el audio antes cuesta milisegundos y no sale del equipo.

enum AudioSilencio {

    /// Por debajo de este pico se considera que no hay voz.
    ///
    /// Las muestras van de -32768 a 32767. Una voz normal, aunque sea lejana,
    /// pasa de 2000; el ruido de fondo de una habitación se queda en cientos.
    /// 800 es deliberadamente CONSERVADOR: ante la duda, se manda a transcribir.
    /// Perder una frase por ahorrar una llamada sería un mal negocio.
    static func umbralPico() -> Int {
        max(0, (Config.json0("bitacora_umbral_silencio") as? Int) ?? 800)
    }

    /// Cuánta parte del trozo tiene que sonar para considerarlo con voz.
    ///
    /// Mirar solo el pico no basta: un clic del teclado, una puerta o un crujido
    /// levantan el pico de un trozo por lo demás mudo, y ese trozo acaba en la
    /// nube para que el motor conteste que no hay nada. Hablar, en cambio, llena
    /// una parte apreciable del tiempo.
    ///
    /// Tres por mil de las muestras es deliberadamente POCO: en un trozo de
    /// treinta segundos son **90 milisegundos** de sonido, menos de lo que dura
    /// una sílaba. Cualquier palabra suelta pasa de sobra.
    ///
    /// El valor salió de una prueba que falló: con cinco por mil, un sonido de
    /// 12 ms se descartaba. Doce milisegundos es un clic, no una voz —así que el
    /// detector no estaba equivocado—, pero el margen quedaba corto para dormir
    /// tranquilo. Ante la duda, se manda a transcribir: perder una frase por
    /// ahorrar una llamada sería un mal negocio.
    static func proporcionMinima() -> Double {
        let v = (Config.json0("bitacora_proporcion_voz") as? Double) ?? 0.003
        return min(1, max(0, v))
    }

    /// ¿Este archivo es silencio? Lee por ventanas: un trozo largo no tiene por
    /// qué caber en memoria para mirarlo.
    static func esSilencio(_ archivo: URL) -> Bool {
        let umbral = umbralPico()
        guard umbral > 0 else { return false }   // 0 = desactivado, se manda todo
        guard let h = try? FileHandle(forReadingFrom: archivo) else { return false }
        defer { try? h.close() }

        // El .wav lleva 44 bytes de cabecera; el .pcm crudo, ninguno.
        if archivo.pathExtension.lowercased() == "wav" {
            _ = try? h.read(upToCount: 44)
        }
        var sonoras = 0, total = 0
        while let trozo = try? h.read(upToCount: 262_144), !trozo.isEmpty {
            trozo.withUnsafeBytes { crudo in
                let muestras = crudo.bindMemory(to: Int16.self)
                total += muestras.count
                for m in muestras where Int(m.magnitude) >= umbral { sonoras += 1 }
            }
        }
        guard total > 0 else { return true }
        return Double(sonoras) / Double(total) < proporcionMinima()
    }

    /// El pico de un archivo, para las pruebas y el diagnóstico.
    static func pico(_ archivo: URL) -> Int {
        guard let h = try? FileHandle(forReadingFrom: archivo) else { return 0 }
        defer { try? h.close() }
        if archivo.pathExtension.lowercased() == "wav" { _ = try? h.read(upToCount: 44) }
        var pico = 0
        while let trozo = try? h.read(upToCount: 262_144), !trozo.isEmpty {
            trozo.withUnsafeBytes { crudo in
                for m in crudo.bindMemory(to: Int16.self) {
                    let v = Int(m.magnitude)
                    if v > pico { pico = v }
                }
            }
        }
        return pico
    }
}
