import AppKit

// MARK: - Bitácora continua: coordinador y retención
//
// Un único punto de encendido y apagado para audio + pantalla, y la purga.
//
// La purga NUNCA borra a ciegas material sin procesar. Si hay audio sin
// transcribir o capturas sin texto reconocido, `revisarPurga` lo devuelve y
// quien llame decide: eso es información que todavía no se extrajo y, una vez
// borrada, no se recupera.

enum ContinuoBitacora {

    // MARK: Encendido

    /// Arranca lo que el usuario haya dejado activado. Seguro de llamar varias
    /// veces y con el módulo apagado (no hace nada).
    static func arrancar() {
        guard Config.continuoActivo() else { return }
        ContinuoIndice.shared.abrir()
        // Lo que quedó a medias en un cierre brusco entra ahora: el archivo
        // sobrevivía pero nadie volvía a mirarlo.
        DispatchQueue.global(qos: .utility).async { ContinuoIndice.shared.rescatarHuerfanos() }
        ContinuoAudio.shared.arrancar()
        if #available(macOS 14.0, *) { ContinuoPantalla.shared.arrancar() }
        if #available(macOS 13.0, *) { ContinuoAudioSistema.shared.arrancar() }
        ContinuoPlanificador.arrancar()
        ContinuoLote.programarRecompresion()
        Log.log(.sistema, "bitácora: encendida")
    }

    static func detener(esperandoElCierre: Bool = false) {
        if esperandoElCierre { ContinuoAudio.shared.detenerYEsperar() }
        else { ContinuoAudio.shared.detener() }
        if #available(macOS 14.0, *) { ContinuoPantalla.shared.detener() }
        if #available(macOS 13.0, *) { ContinuoAudioSistema.shared.detener() }
        ContinuoPlanificador.detener()
        ContinuoLote.detenerRecompresion()
        Log.log(.sistema, "bitácora: apagada")
    }

    /// Relee los ajustes en caliente tras tocar la pestaña.
    static func reconfigurar() {
        detener()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { arrancar() }
    }

    // MARK: Cesión al dictado
    //
    // Estos dos los llama AppDelegate alrededor del dictado. No son ajustes:
    // el dictado siempre gana.

    static func cederMicrofono(completion: @escaping () -> Void) {
        ContinuoAudio.shared.suspender(completion: completion)
    }

    static func recuperarMicrofono() {
        ContinuoAudio.shared.reanudar()
    }

    // MARK: Carpeta

    /// Abre la bitácora en el Finder. Acceso rápido desde la pestaña.
    static func abrirCarpeta() {
        let carpeta = Config.continuoCarpeta()
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([carpeta])
    }

    /// Documentos generados (.md), más nuevos primero, buscados en toda la
    /// bitácora. Son pocos: un escaneo directo basta.
    /// Los tres diarios puros por día (voz, sistema, pantalla), más nuevos
    /// primero.
    static func transcripcionesRecientes(limite: Int = 60) -> [URL] {
        buscarMd(limite: limite) { $0.hasPrefix("transcripcion-") }
    }

    static func documentosRecientes(limite: Int = 60) -> [URL] {
        buscarMd(limite: limite) { !$0.hasPrefix("transcripcion-") }
    }

    /// Las dos listas en UN solo recorrido.
    ///
    /// La pestaña las pedía por separado y cada llamada recorría el árbol
    /// entero de la bitácora. Con meses de historial son decenas de miles de
    /// archivos, recorridos dos veces en cada refresco para repartirlos luego
    /// por el prefijo del nombre — que es algo que se puede decidir sobre la
    /// marcha.
    static func documentosYTranscripciones(limite: Int = 60) -> (documentos: [URL], transcripciones: [URL]) {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz,
                                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return ([], []) }
        var docs: [(URL, Date)] = []
        var trans: [(URL, Date)] = []
        for caso in e {
            guard let url = caso as? URL, url.pathExtension == "md" else { continue }
            let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if url.lastPathComponent.hasPrefix("transcripcion-") { trans.append((url, fecha)) }
            else { docs.append((url, fecha)) }
        }
        func ordenar(_ l: [(URL, Date)]) -> [URL] {
            l.sorted { $0.1 > $1.1 }.prefix(limite).map(\.0)
        }
        return (ordenar(docs), ordenar(trans))
    }

    private static func buscarMd(limite: Int, filtro: (String) -> Bool) -> [URL] {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var docs: [(URL, Date)] = []
        for caso in e {
            guard let url = caso as? URL, url.pathExtension == "md",
                  filtro(url.lastPathComponent) else { continue }
            let fecha = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            docs.append((url, fecha))
        }
        return docs.sorted { $0.1 > $1.1 }.prefix(limite).map(\.0)
    }

    /// Abre en el Finder la subcarpeta del día (audio, pantalla, sistema) o la
    /// del mes para los documentos. Se crea si aún no existe, para que el botón
    /// nunca caiga en el vacío.
    static func abrirCarpetaHoy(_ sub: String) {
        let destino: URL
        if sub == "transcripciones" {
            destino = ContinuoAudio.carpetaDelDia(Date(), sub: "audio").deletingLastPathComponent()
        } else if sub == "documentos" {
            let f = DateFormatter(); f.dateFormat = "yyyy/MM"
            destino = Config.continuoCarpeta().appendingPathComponent(f.string(from: Date()))
        } else {
            destino = ContinuoAudio.carpetaDelDia(Date(), sub: sub)
        }
        try? FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([destino])
    }

    /// Revela un archivo en el Finder, o lo abre con su app predeterminada.
    static func revelar(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    static func abrir(_ url: URL) { NSWorkspace.shared.open(url) }

    // MARK: Retención

    /// Fecha límite según el ajuste de días. `nil` = conservar para siempre.
    static func limiteRetencion() -> Date? {
        let dias = Config.continuoRetencionDias()
        guard dias > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -dias, to: Date())
    }

    /// Qué se llevaría la purga. Se consulta ANTES de borrar para poder avisar.
    static func revisarPurga(limite: Date? = nil) -> BalancePurga? {
        guard let corte = limite ?? limiteRetencion() else { return nil }
        ContinuoIndice.shared.abrir()
        return ContinuoIndice.shared.balanceAnteriorA(corte)
    }

    /// Ejecuta la purga. `forzar` es obligatorio cuando hay material sin
    /// procesar y el aviso está activado: sin él, no se borra nada.
    @discardableResult
    static func purgar(limite: Date? = nil, forzar: Bool = false) -> (borradas: Int, bloqueada: Bool) {
        guard let corte = limite ?? limiteRetencion() else { return (0, false) }
        ContinuoIndice.shared.abrir()
        let balance = ContinuoIndice.shared.balanceAnteriorA(corte)
        if balance.hayMaterialSinProcesar, Config.continuoRetencionAvisarSinProcesar(), !forzar {
            Log.log(.sistema, "bitácora: purga detenida — \(balance.sinProcesar) elementos sin transcribir ni reconocer")
            return (0, true)
        }
        let n = ContinuoIndice.shared.purgarAnteriorA(corte)
        Log.log(.sistema, "bitácora: purgados \(n) elementos anteriores a \(corte)")
        borrarDiariosAnterioresA(corte)
        limpiarCarpetasVacias()
        return (n, false)
    }

    /// Borra los diarios puros (transcripcion-*.md) de los días que quedaron
    /// enteros fuera de la retención. Viven fuera del índice, así que la purga
    /// de filas no los alcanza — y dejarlos sería el mismo agujero que el .txt
    /// hermano: purgar el sonido y conservar el texto en claro burla la
    /// retención. El día de la frontera se conserva: aún tiene material vivo y
    /// los diarios de días pasados no se regeneran.
    private static func borrarDiariosAnterioresA(_ corte: Date) {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        for caso in e {
            guard let url = caso as? URL, url.pathExtension == "md",
                  url.lastPathComponent.hasPrefix("transcripcion-") else { continue }
            // La fecha va al final del nombre: transcripcion-<canal>-yyyy-MM-dd.md
            let base = url.deletingPathExtension().lastPathComponent
            guard base.count > 10, let dia = f.date(from: String(base.suffix(10))),
                  let fin = Calendar.current.date(byAdding: .day, value: 1,
                                                  to: Calendar.current.startOfDay(for: dia)),
                  fin <= corte else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// La purga automática solo corre si el usuario la pidió Y no hay nada
    /// pendiente de procesar: en cuanto lo hay, exige decisión humana.
    static func purgaAutomaticaSiCorresponde() {
        guard Config.continuoActivo(), Config.continuoRetencionAutomatica() else { return }
        DispatchQueue.global(qos: .utility).async {
            let r = purgar()
            if r.bloqueada {
                Log.log(.sistema, "bitácora: la purga automática quedó a la espera de tu visto bueno")
            }
        }
    }

    /// Quita los directorios de día que quedaron sin archivos tras purgar.
    private static func limpiarCarpetasVacias() {
        let raiz = Config.continuoCarpeta()
        guard let e = FileManager.default.enumerator(at: raiz,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        var carpetas: [URL] = []
        for caso in e {
            guard let url = caso as? URL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            carpetas.append(url)
        }
        // De más profundo a menos, para que al vaciar un día se pueda vaciar el mes.
        for url in carpetas.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            let hijos = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            if hijos.isEmpty { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Presentación

    static func tamanoLegible(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
