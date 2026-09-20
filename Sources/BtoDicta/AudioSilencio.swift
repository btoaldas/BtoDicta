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
    ///
    /// **Se conserva como red de seguridad, no como criterio principal.** Medido
    /// el 2026-09-19 contra una hora de ambiente de oficina real: ese ambiente
    /// tiene un 4,2 % de muestras por encima del umbral —catorce veces el tres
    /// por mil—, así que TODO pasaba el filtro. En un día: 414 llamadas a un
    /// motor de pago que contestaron «sin texto», 764 minutos de audio enviados.
    /// Ningún umbral sobre muestras sueltas arregla eso, porque el ruido de una
    /// oficina tiene muestras fuertes de sobra. Lo que distingue a la voz es
    /// otra cosa: ver `rachasMinimas`.
    static func proporcionMinima() -> Double {
        let v = (Config.json0("bitacora_proporcion_voz") as? Double) ?? 0.003
        return min(1, max(0, v))
    }

    /// Cuánto tiene que durar un sonido SEGUIDO para parecer una palabra.
    ///
    /// Esta es la medida que de verdad separa. Un golpe, un clic de ratón o una
    /// tecla producen ventanas sueltas; una palabra ocupa entre 300 y 500 ms
    /// continuos. Medido sobre audio real de esta máquina:
    ///
    /// | | ambiente de oficina | voz |
    /// |---|---|---|
    /// | rachas de ≥ 500 ms | 1,3 por minuto | 37,4 por minuto |
    /// | racha más larga | 1,0 s | 2,5 s |
    ///
    /// Veintinueve veces de separación, frente a las catorce que el criterio
    /// anterior tenía AL REVÉS.
    static func rachaMinimaMs() -> Int {
        max(100, (Config.json0("bitacora_racha_ms") as? Int) ?? 500)
    }

    /// Cuántas de esas rachas hacen falta para mandar el trozo a transcribir.
    ///
    /// Con dos, en un trozo de treinta segundos: el ambiente produce 0,65 rachas
    /// largas de media —llegar a dos es raro— y la voz produce 18,7, que las
    /// supera siempre y con muchísimo margen.
    ///
    /// Que sean dos y no una es seguro aquí **porque este filtro solo gobierna
    /// la bitácora continua**, que graba sola y sin parar. Los dictados que se
    /// piden a propósito no pasan por aquí y nunca se filtran: ahí sigue valiendo
    /// que perder una frase por ahorrar una llamada sería un mal negocio.
    static func rachasMinimas() -> Int {
        max(1, (Config.json0("bitacora_rachas_minimas") as? Int) ?? 2)
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
        // Se recorre el audio en ventanas de 100 ms y se anota cuáles suenan de
        // forma SOSTENIDA (al menos un tercio de la ventana por encima del
        // umbral). Después se miden las rachas de ventanas contiguas: una
        // palabra ocupa varias seguidas, un golpe ocupa una sola.
        let msVentana = 100
        let muestrasPorVentana = (RedSeguridadDictado.bytesPorSegundo / 2) * msVentana / 1000
        let ventanasPorRacha = max(1, rachaMinimaMs() / msVentana)

        var sonoras = 0, total = 0          // para la red de seguridad de abajo
        var rachaActual = 0, rachasLargas = 0
        var enVentana = 0, sonorasVentana = 0

        func cerrarVentana() {
            guard enVentana > 0 else { return }
            if Double(sonorasVentana) / Double(enVentana) >= 0.30 {
                rachaActual += 1
                if rachaActual == ventanasPorRacha { rachasLargas += 1 }
            } else {
                rachaActual = 0
            }
            enVentana = 0; sonorasVentana = 0
        }

        // El `autoreleasepool` no sobra: `read` devuelve un `Data` autoliberado
        // y sin drenar el depósito los trozos se acumulan hasta acabar el bucle.
        // Con una hora de audio son 112 MB retenidos por mirar si hay silencio.
        // Es el mismo descuido que en la comprobación de huella de los modelos,
        // que llegó a retener 4,9 GB: leer por trozos no sirve de nada si no se
        // suelta cada trozo.
        while true {
            let fin = autoreleasepool { () -> Bool in
                guard let trozo = try? h.read(upToCount: 262_144), !trozo.isEmpty else { return true }
                trozo.withUnsafeBytes { crudo in
                    let muestras = crudo.bindMemory(to: Int16.self)
                    total += muestras.count
                    for m in muestras {
                        let fuerte = Int(m.magnitude) >= umbral
                        if fuerte { sonoras += 1; sonorasVentana += 1 }
                        enVentana += 1
                        if enVentana >= muestrasPorVentana { cerrarVentana() }
                    }
                }
                return false
            }
            if fin { break }
        }
        cerrarVentana()
        guard total > 0 else { return true }

        // Hay voz si aparecen suficientes sonidos SOSTENIDOS.
        if rachasLargas >= rachasMinimas() { return false }

        // Red de seguridad: un trozo muy corto no da para varias rachas, y ahí
        // sigue mandando el criterio antiguo. Vale para el trozo de dos segundos
        // que contiene una sola palabra y poco más.
        let segundos = Double(total) / Double(RedSeguridadDictado.bytesPorSegundo / 2)
        if segundos < 3 { return Double(sonoras) / Double(total) < proporcionMinima() }
        return true
    }

    /// El pico de un archivo, para las pruebas y el diagnóstico.
    static func pico(_ archivo: URL) -> Int {
        guard let h = try? FileHandle(forReadingFrom: archivo) else { return 0 }
        defer { try? h.close() }
        if archivo.pathExtension.lowercased() == "wav" { _ = try? h.read(upToCount: 44) }
        var pico = 0
        while true {                       // mismo motivo que en `esSilencio`
            let fin = autoreleasepool { () -> Bool in
                guard let trozo = try? h.read(upToCount: 262_144), !trozo.isEmpty else { return true }
                trozo.withUnsafeBytes { crudo in
                    for m in crudo.bindMemory(to: Int16.self) {
                        let v = Int(m.magnitude)
                        if v > pico { pico = v }
                    }
                }
                return false
            }
            if fin { break }
        }
        return pico
    }
}
