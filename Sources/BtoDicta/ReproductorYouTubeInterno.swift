import AppKit
import SwiftUI
import WebKit

struct ResultadoReproductorYouTube {
    let encontro: Bool
    let reproduciendo: Bool
    let mensaje: String
}

enum SeccionReproductorYouTube: String, CaseIterable, Identifiable {
    case buscar, favoritos, historial, cola, listas
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .buscar: "Buscar"
        case .favoritos: "Favoritos"
        case .historial: "Historial"
        case .cola: "Cola"
        case .listas: "Mis listas"
        }
    }
}

extension Notification.Name {
    static let reproductorYouTubeCambio = Notification.Name("BtoDictaReproductorYouTubeCambio")
}

@MainActor
final class ReproductorYouTubeModel: ObservableObject {
    @Published var consulta = ""
    @Published var resultados: [VideoYouTubeInterno] = []
    @Published var indiceActual: Int?
    @Published var videoID = ""
    @Published var tituloActual = ""
    @Published var estado = "Busca una canción, artista o álbum."
    @Published var cuotaBusquedaTexto = YouTubeCuotaBusqueda.resumen()
    @Published var usandoRespaldoLocal = false
    @Published var cargando = false
    @Published var reproduciendo = false
    @Published var listo = false
    @Published var secuenciaCarga = 0
    @Published var reproducirAlCargar = false
    @Published var seccion: SeccionReproductorYouTube = .buscar
    @Published var tipoBusqueda: TipoBusquedaYouTube = .musica
    @Published var filtroBiblioteca = ""
    @Published var listas: [ListaYouTubeInterna] = []
    @Published var listaActual: ListaYouTubeInterna?
    @Published private(set) var cola: [VideoYouTubeInterno] = YouTubeCola.todos()
    @Published var pantallaCompletaVideo = false
    @Published var compacto = Config.musicaInternaCompacta() {
        didSet { Config.set("musica_interna_compacta", to: compacto) }
    }

    /// YouTube exige que un player que reproduce permanezca visible y mida al
    /// menos 200×200. Compacto quita buscador/cola, pero no oculta ni separa audio.
    nonisolated static let tamanoVideoCompacto = CGSize(width: 356, height: 200)
    nonisolated static func cumpleMinimoYouTube(_ tamano: CGSize) -> Bool {
        tamano.width >= 200 && tamano.height >= 200
    }
    var videoVisible: Bool { true }

    var ejecutarJavaScript: ((String) -> Void)?
    var pedirPantallaCompleta: (() -> Void)?
    var pedirCompacto: ((Bool) -> Void)?
    private var pendienteID: UUID?
    private var pendiente: ((ResultadoReproductorYouTube) -> Void)?
    private var detencionSolicitada = false
    private var resultadosBusqueda: [VideoYouTubeInterno] = []
    private var ultimoHistorialID = ""
    private var noDisponibles = Set<String>()
    private var comandoSecuencia = 0
    private var reintentosAutoplay = 0

    var videoActual: VideoYouTubeInterno? {
        guard let indiceActual, cola.indices.contains(indiceActual) else { return nil }
        return cola[indiceActual]
    }

    var esFavoritoActual: Bool { videoActual.map { YouTubeFavoritos.contiene($0.id) } ?? false }

    var resultadosFiltrados: [VideoYouTubeInterno] {
        Self.filtrar(resultados, por: filtroBiblioteca)
    }

    var listasFiltradas: [ListaYouTubeInterna] {
        let f = PerfilAgente.normalizar(filtroBiblioteca)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return listas }
        return listas.filter { PerfilAgente.normalizar($0.titulo).contains(f) }
    }

    var fuenteAleatoria: [VideoYouTubeInterno] {
        guard !compacto, !pantallaCompletaVideo, !resultadosFiltrados.isEmpty else { return cola }
        return resultadosFiltrados
    }

    var puedeAleatorio: Bool {
        fuenteAleatoria.filter { !noDisponibles.contains($0.id) }.count > 1
    }

    nonisolated static func filtrar(_ videos: [VideoYouTubeInterno],
                                    por texto: String) -> [VideoYouTubeInterno] {
        let f = PerfilAgente.normalizar(texto)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty else { return videos }
        return videos.filter {
            PerfilAgente.normalizar("\($0.titulo) \($0.canal)").contains(f)
        }
    }

    /// Evita repetir lo recién escuchado mientras haya alternativas. Si todo el
    /// conjunto ya es reciente, vuelve a usarlo para no dejar la orden sin salida.
    nonisolated static func candidatosAleatorios(_ videos: [VideoYouTubeInterno],
                                                  evitando recientes: Set<String>) -> [Int] {
        let nuevos = videos.indices.filter { !recientes.contains(videos[$0].id) }
        return nuevos.isEmpty ? Array(videos.indices) : nuevos
    }

    nonisolated static func siguienteDisponible(en videos: [VideoYouTubeInterno],
                                                 despuesDe actual: Int,
                                                 omitiendo bloqueados: Set<String>) -> Int? {
        guard videos.count > 1, videos.indices.contains(actual) else { return nil }
        return (1..<videos.count).map { (actual + $0) % videos.count }
            .first { !bloqueados.contains(videos[$0].id) }
    }

    func ejecutar(_ texto: String, reproducir: Bool,
                  completion: @escaping (ResultadoReproductorYouTube) -> Void) {
        consulta = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        tipoBusqueda = TipoBusquedaYouTube.inferir(consulta)
        cambiarSeccion(.buscar)
        let sinConsulta = consulta.isEmpty && reproducir
        if sinConsulta, Config.musicaSinConsulta() == "reanudar", !videoID.isEmpty {
            iniciarPendiente(completion); reanudar(); return
        }
        if sinConsulta {
            consulta = Config.musicaInternaConsultaPredeterminada()
        }
        buscar(reproducir: reproducir && Config.musicaInternaAutoReproducir(),
               aleatorio: sinConsulta,
               completion: completion)
    }

    func buscar(reproducir: Bool = false,
                aleatorio: Bool = false,
                completion: ((ResultadoReproductorYouTube) -> Void)? = nil) {
        let q = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            estado = "Escribe una canción, artista, álbum o enlace de YouTube."
            completion?(.init(encontro: false, reproduciendo: false, mensaje: estado)); return
        }
        cancelarPendiente(mensaje: "La búsqueda anterior fue reemplazada.")
        cargando = true
        estado = YouTubeCuotaBusqueda.restantes() > 0
            ? "Buscando «\(q)» en YouTube…"
            : "Buscando «\(q)» en tu biblioteca local…"
        YouTubeDataAPI.buscar(q, tipo: tipoBusqueda) { [weak self] resultado in
            guard let self else { return }
            self.cargando = false
            self.cuotaBusquedaTexto = YouTubeCuotaBusqueda.resumen()
            switch resultado {
            case .failure(let error):
                let locales = self.buscarEnBibliotecaLocal(q, permitirTodos: aleatorio)
                guard !locales.isEmpty else {
                    self.resultadosBusqueda = []
                    if self.seccion == .buscar { self.resultados = [] }
                    self.usandoRespaldoLocal = false
                    self.estado = "\(error.localizedDescription) Tampoco encontré coincidencias locales."
                    completion?(.init(encontro: false, reproduciendo: false, mensaje: self.estado))
                    return
                }
                self.aplicarResultados(locales, consulta: q, reproducir: reproducir,
                                       aleatorio: aleatorio, respaldoLocal: true,
                                       completion: completion)
            case .success(let videos):
                self.aplicarResultados(videos, consulta: q, reproducir: reproducir,
                                       aleatorio: aleatorio, respaldoLocal: false,
                                       completion: completion)
            }
        }
    }

    private func buscarEnBibliotecaLocal(_ texto: String,
                                          permitirTodos: Bool) -> [VideoYouTubeInterno] {
        let biblioteca = YouTubeBibliotecaCache.combinar([
            resultadosBusqueda, resultados, cola, YouTubeFavoritos.todos(),
            YouTubeHistorial.videos(), YouTubeBibliotecaCache.todos(),
        ])
        return YouTubeBibliotecaCache.buscar(texto, en: biblioteca,
                                              permitirTodos: permitirTodos)
    }

    private func aplicarResultados(_ videos: [VideoYouTubeInterno], consulta q: String,
                                    reproducir: Bool, aleatorio: Bool,
                                    respaldoLocal: Bool,
                                    completion: ((ResultadoReproductorYouTube) -> Void)?) {
        resultadosBusqueda = videos
        if seccion == .buscar { resultados = videos }
        usandoRespaldoLocal = respaldoLocal
        guard !videos.isEmpty else {
            estado = "YouTube no encontró resultados para «\(q)»."
            completion?(.init(encontro: false, reproduciendo: false, mensaje: estado)); return
        }
        if reproducir {
            iniciarPendiente(completion)
            let candidatos = aleatorio
                ? Self.candidatosAleatorios(videos, evitando: YouTubeHistorial.idsRecientes())
                : Array(videos.indices.prefix(1))
            let indice = aleatorio ? candidatos.randomElement() ?? 0 : 0
            seleccionar(indice, desde: videos, reproducir: true)
        } else {
            // Buscar no interrumpe lo que ya suena; en una ventana nueva prepara
            // el primer resultado sin pulsar Play.
            if videoID.isEmpty { seleccionar(0, reproducir: false) }
            let origen = respaldoLocal ? "en tu biblioteca local" : "en YouTube"
            estado = "Encontré \(videos.count) resultado(s) \(origen) para «\(q)»."
            completion?(.init(encontro: true, reproduciendo: false,
                              mensaje: "Abrí \(videos.count) resultado(s) \(origen)."))
        }
    }

    func seleccionar(_ indice: Int, reproducir: Bool = true) {
        seleccionar(indice, desde: resultados, reproducir: reproducir)
    }

    func seleccionar(_ video: VideoYouTubeInterno,
                     desde candidatos: [VideoYouTubeInterno],
                     reproducir: Bool = true) {
        guard let indice = candidatos.firstIndex(where: { $0.id == video.id }) else { return }
        seleccionar(indice, desde: candidatos, reproducir: reproducir)
    }

    private func seleccionar(_ indice: Int, desde candidatos: [VideoYouTubeInterno],
                             reproducir: Bool) {
        guard candidatos.indices.contains(indice) else { return }
        cola = candidatos; YouTubeCola.reemplazar(cola)
        cargarDesdeCola(indice, reproducir: reproducir)
    }

    private func cargarDesdeCola(_ indice: Int, reproducir: Bool = true) {
        guard cola.indices.contains(indice) else { return }
        indiceActual = indice; detencionSolicitada = false
        let video = cola[indice]
        videoID = video.id; tituloActual = video.titulo
        reproduciendo = false; reproducirAlCargar = reproducir
        reintentosAutoplay = 0
        estado = reproducir ? "Cargando «\(video.titulo)»…" : "Preparé «\(video.titulo)»."
        secuenciaCarga += 1
        notificarCambio()
    }

    func alternar() { enviarComando("toggle") }
    func pausar() {
        enviarComando("pause")
        if !tituloActual.isEmpty { estado = "Pausando «\(tituloActual)»…" }
        notificarCambio()
    }
    func reanudar() {
        guard !videoID.isEmpty else { return }
        enviarComando("play")
        estado = "Reanudando «\(tituloActual)»…"
        notificarCambio()
    }
    func detener() {
        detencionSolicitada = true
        enviarComando("stop")
        estado = "Deteniendo la reproducción…"
        notificarCambio()
    }

    private func enviarComando(_ comando: String) {
        comandoSecuencia &+= 1
        ejecutarJavaScript?("bdCommand('\(comando)', \(comandoSecuencia))")
    }
    func anterior() {
        guard !cola.isEmpty else { return }
        let actual = indiceActual ?? 0
        let orden = (1...cola.count).map { (actual - $0 + cola.count * 2) % cola.count }
        guard let indice = orden.first(where: { !noDisponibles.contains(cola[$0].id) }) else { return }
        cargarDesdeCola(indice)
    }
    func siguiente() {
        guard !cola.isEmpty else { return }
        let actual = indiceActual ?? -1
        let orden = (1...cola.count).map { (actual + $0) % cola.count }
        guard let indice = orden.first(where: { !noDisponibles.contains(cola[$0].id) }) else { return }
        cargarDesdeCola(indice)
    }
    func aleatorio() {
        let fuente = fuenteAleatoria
        guard fuente.filter({ !noDisponibles.contains($0.id) }).count > 1 else { return }
        if fuente.map(\.id) != cola.map(\.id) {
            cola = fuente; YouTubeCola.reemplazar(cola)
        }
        let opciones = cola.indices.filter {
            $0 != indiceActual && !noDisponibles.contains(cola[$0].id)
        }
        guard let indice = opciones.randomElement() else { return }
        cargarDesdeCola(indice)
    }

    func alternarFavoritoActual() {
        guard let actual = videoActual else { return }
        let agregado = YouTubeFavoritos.alternar(actual)
        estado = agregado ? "Añadí «\(actual.titulo)» a tus favoritos de BtoDicta."
            : "Quité «\(actual.titulo)» de tus favoritos."
        if seccion == .favoritos { cargarFavoritos() }
        objectWillChange.send(); notificarCambio()
    }

    func alternarFavorito(_ video: VideoYouTubeInterno) {
        _ = YouTubeFavoritos.alternar(video)
        if seccion == .favoritos { cargarFavoritos() }
        else { objectWillChange.send(); notificarCambio() }
    }

    func cargarFavoritos() {
        cancelarPendiente(mensaje: "Cambiaste de biblioteca.")
        seccion = .favoritos; listaActual = nil
        resultados = YouTubeFavoritos.todos()
        estado = resultados.isEmpty ? "Aún no guardas favoritos en BtoDicta."
            : "Tus \(resultados.count) favorito(s) locales."
        notificarCambio()
    }

    func cargarHistorial() {
        cancelarPendiente(mensaje: "Cambiaste de biblioteca.")
        seccion = .historial; listaActual = nil
        resultados = YouTubeHistorial.videos()
        estado = resultados.isEmpty ? "Aún no has reproducido videos dentro de BtoDicta."
            : "Tus \(resultados.count) reproducción(es) recientes."
        notificarCambio()
    }

    func cargarCola() {
        cancelarPendiente(mensaje: "Cambiaste de biblioteca.")
        seccion = .cola; listaActual = nil; resultados = cola
        estado = resultados.isEmpty ? "La cola está vacía. Añade resultados con el botón +."
            : "Cola de reproducción: \(resultados.count) elemento(s)."
        notificarCambio()
    }

    func agregarACola(_ video: VideoYouTubeInterno) {
        let agregado = YouTubeCola.agregar(video)
        cola = YouTubeCola.todos()
        if seccion == .cola { resultados = cola }
        estado = agregado ? "Añadí «\(video.titulo)» al final de la cola."
            : "«\(video.titulo)» ya estaba en la cola."
        notificarCambio()
    }

    func quitarDeCola(_ video: VideoYouTubeInterno) {
        let eraActual = video.id == videoID
        YouTubeCola.quitar(video.id); cola = YouTubeCola.todos(); resultados = cola
        if eraActual { indiceActual = cola.firstIndex(where: { $0.id == videoID }) }
        estado = cola.isEmpty ? "La cola está vacía."
            : "Quité «\(video.titulo)» de la cola."
        notificarCambio()
    }

    func vaciarCola() {
        YouTubeCola.vaciar(); cola = []; resultados = []; indiceActual = nil
        estado = "Vacié la cola. La pista actual no se interrumpe."
        notificarCambio()
    }

    func reproducirCola() {
        guard !cola.isEmpty else { estado = "La cola está vacía."; return }
        cargarDesdeCola(0, reproducir: true)
    }

    func cargarListas() {
        cancelarPendiente(mensaje: "Cambiaste de biblioteca.")
        seccion = .listas; listaActual = nil; resultados = []; cargando = true
        estado = "Leyendo tus listas de YouTube…"
        YouTubeDataAPI.misListas { [weak self] resultado in
            guard let self else { return }
            self.cargando = false
            switch resultado {
            case .failure(let error): self.listas = []; self.estado = error.localizedDescription
            case .success(let listas):
                self.listas = listas
                self.estado = listas.isEmpty ? "Tu cuenta no tiene listas visibles."
                    : "Encontré \(listas.count) lista(s) en tu cuenta."
            }
            self.notificarCambio()
        }
    }

    func conectarCuentaGoogle() {
        guard YouTubeOAuth.tieneCliente else {
            estado = "Primero importa el JSON OAuth de escritorio en Ajustes → Asistente → Modo Música."
            SettingsWindowController.shared.show(irA: "Asistente")
            return
        }
        cargando = true; estado = "Esperando autorización en tu navegador…"
        YouTubeOAuth.conectar { [weak self] ok, mensaje in
            guard let self else { return }
            self.cargando = false; self.estado = mensaje
            if ok { self.cargarListas() }
            else { self.notificarCambio() }
        }
    }

    func abrirLista(_ lista: ListaYouTubeInterna) {
        listaActual = lista; resultados = []
        cargando = true; estado = "Abriendo «\(lista.titulo)»…"
        YouTubeDataAPI.videos(de: lista) { [weak self] resultado in
            guard let self else { return }
            self.cargando = false
            switch resultado {
            case .failure(let error): self.resultados = []; self.estado = error.localizedDescription
            case .success(let videos):
                self.resultados = videos; self.indiceActual = nil
                self.estado = videos.isEmpty ? "La lista no contiene videos reproducibles."
                    : "«\(lista.titulo)»: \(videos.count) video(s)."
                if self.videoID.isEmpty, !videos.isEmpty { self.seleccionar(0, reproducir: false) }
            }
            self.notificarCambio()
        }
    }

    func cambiarSeccion(_ nueva: SeccionReproductorYouTube) {
        filtroBiblioteca = ""
        switch nueva {
        case .buscar:
            seccion = .buscar; listaActual = nil; resultados = resultadosBusqueda
            estado = resultados.isEmpty ? "Busca una canción, artista, álbum o tutorial."
                : "Última búsqueda: \(resultados.count) resultado(s)."
        case .favoritos: cargarFavoritos()
        case .historial: cargarHistorial()
        case .cola: cargarCola()
        case .listas: cargarListas()
        }
    }

    func mensajeWeb(_ cuerpo: Any) {
        guard let d = cuerpo as? [String: Any], let tipo = d["type"] as? String else { return }
        let id = d["id"] as? String ?? ""
        if ProcessInfo.processInfo.environment["BTODICTA_YTPLAYERTEST"] != nil {
            print("YTPLAYERWEB tipo=\(tipo) valor=\(d["value"] ?? "-") id=\(id)")
            fflush(stdout)
        }
        switch tipo {
        case "ready":
            listo = true
            if videoID.isEmpty {
                estado = "Reproductor listo."
            } else if videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#,
                                    options: .regularExpression) != nil {
                // `updateNSView` puede ocurrir antes de que el documento haya
                // definido bdLoad. Ready es la barrera fiable: repetimos aquí
                // la carga vigente y no dependemos de una carrera WebKit/SwiftUI.
                ejecutarJavaScript?("bdLoad('\(videoID)', \(reproducirAlCargar ? "true" : "false"))")
            }
        case "state":
            guard let valor = (d["value"] as? NSNumber)?.intValue else { return }
            if let titulo = d["title"] as? String, !titulo.isEmpty { tituloActual = titulo }
            if valor == 1 {
                reproduciendo = true; estado = "Reproduciendo «\(tituloActual)»."
                registrarHistorialSiHaceFalta(id: id)
                if id.isEmpty || id == videoID {
                    resolverPendiente(.init(encontro: true, reproduciendo: true,
                        mensaje: "Listo, estoy reproduciendo «\(tituloActual)» en BtoDicta."))
                }
            } else if valor == 2 {
                reproduciendo = false; estado = "En pausa: «\(tituloActual)»."
            } else if valor == -1 || valor == 5 {
                reproduciendo = false
                if detencionSolicitada {
                    estado = "Reproducción detenida."
                } else {
                    estado = reproducirAlCargar
                        ? "Preparando «\(tituloActual)»…"
                        : "Preparado: «\(tituloActual)»."
                }
            } else if valor == 0 {
                reproduciendo = false; estado = "Terminó «\(tituloActual)»."
                if detencionSolicitada {
                    estado = "Reproducción detenida."
                } else if Config.musicaInternaAvanzarSolo() { siguiente() }
            }
            notificarCambio()
        case "error":
            reproduciendo = false
            let codigo = (d["value"] as? NSNumber)?.intValue ?? 0
            saltarNoDisponible(codigo: codigo)
        case "autoplayBlocked":
            reproduciendo = false
            if reproducirAlCargar, reintentosAutoplay == 0, !detencionSolicitada {
                // Tras omitir un video 101/150, el IFrame puede terminar de
                // cargar el siguiente después de la primera orden de Play. Un
                // único reintento ya con el reproductor listo resuelve ese caso
                // sin crear un bucle si el navegador exige un gesto real.
                reintentosAutoplay = 1
                estado = "Reintentando iniciar «\(tituloActual)»…"
                notificarCambio()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.enviarComando("play")
                }
            } else {
                estado = "macOS bloqueó el inicio automático. Pulsa Play una vez en el reproductor."
                resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: estado))
            }
        case "command":
            let comando = d["command"] as? String ?? ""
            let secuencia = (d["sequence"] as? NSNumber)?.intValue ?? -1
            // Una confirmación de Play/Pausa puede llegar después de que el
            // usuario ya pulsó Stop. Solo el comando más reciente puede cambiar
            // el estado visible o resolver una orden hablada.
            guard secuencia == comandoSecuencia else { return }
            let valor = (d["value"] as? NSNumber)?.intValue ?? -99
            if comando == "pause", valor != 2 {
                estado = "YouTube no confirmó la pausa; inténtalo otra vez."
            } else if comando == "play", valor != 1 {
                estado = "YouTube no confirmó la reproducción."
            } else if comando == "stop", ![-1, 0, 5].contains(valor) {
                estado = "YouTube no confirmó que se detuvo."
            } else if comando == "stop" {
                detencionSolicitada = false; estado = "Reproducción detenida."
            }
            notificarCambio()
        default: break
        }
    }

    private func notificarCambio() {
        NotificationCenter.default.post(name: .reproductorYouTubeCambio, object: nil)
    }

    private func iniciarPendiente(_ completion: ((ResultadoReproductorYouTube) -> Void)?) {
        guard let completion else { return }
        let id = UUID(); pendienteID = id; pendiente = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.pendienteID == id else { return }
            self.estado = "YouTube mostró el resultado, pero no confirmó reproducción a tiempo."
            self.resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: self.estado))
        }
    }

    private func resolverPendiente(_ resultado: ResultadoReproductorYouTube) {
        guard let p = pendiente else { return }
        pendiente = nil; pendienteID = nil; p(resultado)
    }

    private func cancelarPendiente(mensaje: String) {
        guard pendiente != nil else { return }
        resolverPendiente(.init(encontro: false, reproduciendo: false, mensaje: mensaje))
    }

    func cerrarSesion() {
        cancelarPendiente(mensaje: "Cerraste el reproductor.")
        ejecutarJavaScript = nil; reproduciendo = false; listo = false
        videoID = ""; tituloActual = ""; indiceActual = nil
        reproducirAlCargar = false; detencionSolicitada = false
        estado = "Reproductor cerrado."
        notificarCambio()
    }

    private func saltarNoDisponible(codigo: Int) {
        let fallido = videoID
        if !fallido.isEmpty { noDisponibles.insert(fallido) }
        guard cola.count > 1, let actual = indiceActual else {
            estado = "YouTube no permite reproducir este video aquí (error \(codigo))."
            resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: estado))
            avisarNoDisponible(estado); notificarCambio(); return
        }
        guard let siguiente = Self.siguienteDisponible(en: cola, despuesDe: actual,
                                                        omitiendo: noDisponibles) else {
            estado = "Ningún elemento restante de esta cola permite reproducción embebida."
            resolverPendiente(.init(encontro: true, reproduciendo: false, mensaje: estado))
            avisarNoDisponible(estado); notificarCambio(); return
        }
        let omitido = tituloActual.isEmpty ? "Este video" : "«\(tituloActual)»"
        let mensaje = "⏭ \(omitido) no se puede reproducir aquí; probando el siguiente."
        estado = mensaje; avisarNoDisponible(mensaje); notificarCambio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.cargarDesdeCola(siguiente)
        }
    }

    private func avisarNoDisponible(_ mensaje: String) {
        Log.write("  🎵 \(mensaje)")
        (NSApp.delegate as? AppDelegate)?.presentarAvisoMusica(mensaje)
    }

    private func registrarHistorialSiHaceFalta(id reportado: String) {
        let id = reportado.isEmpty ? videoID : reportado
        guard !id.isEmpty, id != ultimoHistorialID else { return }
        let video = cola.first(where: { $0.id == id })
            ?? VideoYouTubeInterno(id: id,
                                   titulo: tituloActual.isEmpty ? "Video de YouTube" : tituloActual,
                                   canal: "YouTube", miniatura: nil)
        ultimoHistorialID = id; YouTubeHistorial.registrar(video)
        if seccion == .historial { resultados = YouTubeHistorial.videos() }
    }
}

private struct ReproductorWebYouTube: NSViewRepresentable {
    @ObservedObject var model: ReproductorYouTubeModel

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        weak var model: ReproductorYouTubeModel?
        var ultimaCarga = -1

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "beto" else { return }
            DispatchQueue.main.async { [weak self] in self?.model?.mensajeWeb(message.body) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "beto")
        let web = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = web; context.coordinator.model = model
        model.ejecutarJavaScript = { [weak web] js in
            DispatchQueue.main.async { web?.evaluateJavaScript(js, completionHandler: nil) }
        }
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://btodicta.app/"))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.model = model
        guard context.coordinator.ultimaCarga != model.secuenciaCarga, !model.videoID.isEmpty else { return }
        context.coordinator.ultimaCarga = model.secuenciaCarga
        let id = Self.literalJS(model.videoID)
        web.evaluateJavaScript("bdLoad(\(id), \(model.reproducirAlCargar ? "true" : "false"))",
                               completionHandler: nil)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "beto")
        if coordinator.model?.ejecutarJavaScript != nil { coordinator.model?.ejecutarJavaScript = nil }
    }

    private static func literalJS(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8), json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    private static let html = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>html,body,#player{width:100%;height:100%;margin:0;background:#0d0b12;overflow:hidden}</style>
    </head><body><div id="player"></div><script>
    var player=null, pending=null;
    function info(type,value){
      var d={type:type,value:value||0,id:'',title:''};
      try{var v=player&&player.getVideoData?player.getVideoData():{};d.id=v.video_id||'';d.title=v.title||'';}catch(e){}
      window.webkit.messageHandlers.beto.postMessage(d);
    }
    function onYouTubeIframeAPIReady(){
      player=new YT.Player('player',{width:'100%',height:'100%',playerVars:{playsinline:1,rel:0,origin:'https://btodicta.app'},events:{
        onReady:function(){pending=null;info('ready',1);},
        onStateChange:function(e){info('state',e.data);},
        onError:function(e){info('error',e.data);},
        onAutoplayBlocked:function(){info('autoplayBlocked',1);}
      }});
    }
    function bdLoad(id,play){
      if(!player||!player.loadVideoById){pending={id:id,play:play};return;}
      if(play){player.loadVideoById(id);}else{player.cueVideoById(id);}
    }
    function bdCommand(cmd,sequence){
      if(!player){window.webkit.messageHandlers.beto.postMessage({type:'command',value:-99,command:cmd,sequence:sequence});return;}
      if(cmd==='toggle'){if(player.getPlayerState()===1)player.pauseVideo();else player.playVideo();}
      else if(cmd==='play')player.playVideo();else if(cmd==='pause')player.pauseVideo();
      else if(cmd==='stop')player.stopVideo();
      setTimeout(function(){
        var s=-99;try{s=player.getPlayerState();}catch(e){}
        window.webkit.messageHandlers.beto.postMessage({type:'command',value:s,command:cmd,sequence:sequence});
      },350);
    }
    var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';
    document.head.appendChild(tag);
    </script></body></html>
    """
}

private struct ReproductorYouTubeView: View {
    @ObservedObject var model: ReproductorYouTubeModel
    private let violeta = Color(red: 0.36, green: 0.28, blue: 0.62)

    var body: some View {
        VStack(spacing: model.pantallaCompletaVideo ? 0 : 12) {
            if !model.pantallaCompletaVideo {
            if !model.compacto {
            VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("Biblioteca", selection: $model.seccion) {
                    ForEach(SeccionReproductorYouTube.allCases) { s in Text(s.nombre).tag(s) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .onChange(of: model.seccion) { _, nueva in model.cambiarSeccion(nueva) }
                Spacer()
                if model.seccion == .buscar {
                    Picker("Tipo", selection: $model.tipoBusqueda) {
                        ForEach(TipoBusquedaYouTube.allCases) { t in Text(t.nombre).tag(t) }
                    }.frame(width: 170)
                        .help("Música usa la categoría musical de YouTube; Videos y tutoriales busca contenido general")
                }
            }

            if model.seccion == .buscar {
            HStack(spacing: 8) {
                Image(systemName: "music.note.house.fill").foregroundStyle(violeta)
                TextField(model.tipoBusqueda == .musica
                          ? "Canción, artista, álbum o enlace de YouTube"
                          : "Video, tutorial o tema", text: $model.consulta)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.buscar() }
                Button("Buscar") { model.buscar() }
                    .keyboardShortcut(.return, modifiers: [])
                    .help("Buscar música sin iniciar la reproducción")
                Button {
                    model.buscar(reproducir: true)
                } label: { Label("Buscar y reproducir", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).tint(violeta)
                    .help("Buscar y reproducir el primer resultado")
            }
            Text(model.tipoBusqueda == .musica
                 ? "Música filtra la categoría musical de YouTube. No existe una API pública separada de YouTube Music."
                 : "Videos y tutoriales quita el filtro musical y busca contenido general reproducible.")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: model.usandoRespaldoLocal ? "internaldrive" : "network")
                Text(model.usandoRespaldoLocal
                     ? "Respaldo local activo · favoritos, cola, historial y listas ya abiertas"
                     : model.cuotaBusquedaTexto)
                Spacer()
            }.font(.caption2).foregroundStyle(model.usandoRespaldoLocal ? .orange : .secondary)
            } else if model.seccion == .listas, let lista = model.listaActual {
                HStack {
                    Button { model.cargarListas() } label: {
                        Label("Mis listas", systemImage: "chevron.left")
                    }.buttonStyle(.plain).help("Volver al listado de tu cuenta")
                    Text(lista.titulo).font(.headline).lineLimit(1)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(violeta)
                        TextField(model.seccion == .listas ? "Filtrar listas" : "Filtrar por título o canal",
                                  text: $model.filtroBiblioteca)
                            .textFieldStyle(.roundedBorder)
                        if model.seccion == .cola {
                            Button { model.reproducirCola() } label: {
                                Label("Reproducir", systemImage: "play.fill")
                            }.disabled(model.cola.isEmpty).help("Reproducir la cola desde el primer elemento")
                            Button("Vaciar") { model.vaciarCola() }
                                .disabled(model.cola.isEmpty).help("Vaciar la cola sin cortar la pista actual")
                        }
                    }
                    if model.seccion == .listas, !YouTubeOAuth.conectada {
                        HStack {
                            Text("La API key sirve para buscar. Mis listas requiere autorizar tu cuenta con OAuth de escritorio.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button(YouTubeOAuth.tieneCliente ? "Conectar Google…" : "Configurar OAuth…") {
                                model.conectarCuentaGoogle()
                            }.controlSize(.small)
                                .help("Importar las credenciales OAuth de escritorio y autorizar Google en el navegador")
                        }
                    }
                }
            }
            }
            .frame(minHeight: 72, alignment: .top)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: model.reproduciendo
                          ? "speaker.wave.2.circle.fill" : "music.note.house.fill")
                        .font(.title2).foregroundStyle(model.reproduciendo ? Color.green : violeta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.tituloActual.isEmpty ? "Reproductor interno" : model.tituloActual)
                            .font(.headline).lineLimit(1)
                        Text(model.reproduciendo ? "Reproduciendo solo audio" : model.estado)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("VISTA COMPACTA")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            }

            // SIEMPRE es la misma instancia de WKWebView para no cortar el audio.
            // En compacto se conserva visible en 356×200: cumple el mínimo oficial
            // de YouTube y evita convertirlo en un reproductor de fondo prohibido.
            ReproductorWebYouTube(model: model)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: model.compacto && !model.pantallaCompletaVideo
                       ? Self.anchoVideoCompacto : nil,
                       height: model.compacto && !model.pantallaCompletaVideo
                       ? Self.altoVideoCompacto : nil)
                .frame(maxWidth: .infinity,
                       maxHeight: model.pantallaCompletaVideo ? .infinity
                       : (model.compacto ? Self.altoVideoCompacto : 386))
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: model.pantallaCompletaVideo ? 0 : 10))

            if !model.pantallaCompletaVideo {
            HStack(spacing: 18) {
                Button(action: model.anterior) { Image(systemName: "backward.end.fill") }
                    .disabled(model.cola.count < 2).help("Resultado anterior")
                Button(action: model.alternar) {
                    Image(systemName: model.reproduciendo ? "pause.fill" : "play.fill")
                        .font(.title2)
                }.disabled(model.videoID.isEmpty || !model.listo)
                    .help(model.reproduciendo ? "Pausar" : "Reproducir")
                Button(action: model.detener) { Image(systemName: "stop.fill") }
                    .disabled(!model.reproduciendo || !model.listo).help("Detener la reproducción")
                Button(action: model.siguiente) { Image(systemName: "forward.end.fill") }
                    .disabled(model.cola.count < 2).help("Resultado siguiente")
                Button(action: model.aleatorio) { Image(systemName: "shuffle") }
                    .disabled(!model.puedeAleatorio)
                    .help("Mezclar y reproducir desde la pestaña activa")
                Button(action: model.alternarFavoritoActual) {
                    Image(systemName: model.esFavoritoActual ? "star.fill" : "star")
                }.disabled(model.videoActual == nil)
                    .help(model.esFavoritoActual ? "Quitar de favoritos locales" : "Guardar como favorito local")
                Spacer()
                Button {
                    model.compacto.toggle(); model.pedirCompacto?(model.compacto)
                } label: {
                    Label(model.compacto ? "Vista amplia" : "Compacto",
                          systemImage: model.compacto ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                }.controlSize(.small)
                    .help(model.compacto
                          ? "Volver a mostrar el buscador y los resultados"
                          : "Reducir la interfaz conservando visible el reproductor oficial de YouTube")
                Button { model.pedirPantallaCompleta?() } label: {
                    if model.compacto {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    } else {
                        Label("Pantalla", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }.controlSize(.small).help("Mostrar el video y los controles a pantalla completa")
                if !model.compacto, !model.videoID.isEmpty {
                    Button {
                        if let u = URL(string: "https://music.youtube.com/watch?v=\(model.videoID)") {
                            NSWorkspace.shared.open(u)
                        }
                    } label: { Label("YouTube", systemImage: "arrow.up.right.square") }
                        .controlSize(.small).help("Abrir esta pista en el navegador")
                }
            }.buttonStyle(.bordered)

            HStack(spacing: 7) {
                if model.cargando { ProgressView().controlSize(.small) }
                Circle().fill(model.reproduciendo ? Color.green : (model.listo ? Color.secondary : Color.orange))
                    .frame(width: 7, height: 7)
                Text(model.estado).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Configurar cuenta o clave…") {
                    SettingsWindowController.shared.show(irA: "Asistente")
                }.controlSize(.small).help("Abrir la configuración del reproductor interno")
            }

            if !model.compacto, model.seccion == .listas,
               model.listaActual == nil, !model.listasFiltradas.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.listasFiltradas) { lista in
                            Button { model.abrirLista(lista) } label: {
                                HStack(spacing: 9) {
                                    AsyncImage(url: lista.miniatura) { fase in
                                        if let imagen = fase.image { imagen.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.18).overlay(Image(systemName: "music.note.list")) }
                                    }.frame(width: 84, height: 47).clipped().cornerRadius(5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lista.titulo).font(.subheadline).lineLimit(2)
                                        Text("\(lista.cantidad) elemento(s)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(6).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .help("Abrir la lista \(lista.titulo)")
                        }
                    }
                }.frame(height: 205)
            } else if !model.compacto,
                      (model.seccion != .listas || model.listaActual != nil),
                      !model.resultadosFiltrados.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.resultadosFiltrados) { video in
                            HStack(spacing: 9) {
                                Button {
                                    model.seleccionar(video, desde: model.resultadosFiltrados)
                                } label: {
                                    HStack(spacing: 9) {
                                    AsyncImage(url: video.miniatura) { fase in
                                        if let imagen = fase.image { imagen.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.18).overlay(Image(systemName: "music.note")) }
                                    }.frame(width: 84, height: 47).clipped().cornerRadius(5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(video.titulo).font(.subheadline).lineLimit(2)
                                        Text(video.canal).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if model.videoID == video.id {
                                        Image(systemName: model.reproduciendo ? "speaker.wave.2.fill" : "play.circle")
                                            .foregroundStyle(violeta)
                                    }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { model.alternarFavorito(video) } label: {
                                    Image(systemName: YouTubeFavoritos.contiene(video.id) ? "star.fill" : "star")
                                }.buttonStyle(.plain).help("Añadir o quitar de favoritos locales")
                                if model.seccion == .cola {
                                    Button { model.quitarDeCola(video) } label: {
                                        Image(systemName: "minus.circle")
                                    }.buttonStyle(.plain).help("Quitar de la cola")
                                } else {
                                    Button { model.agregarACola(video) } label: {
                                        Image(systemName: "text.badge.plus")
                                    }.buttonStyle(.plain).help("Añadir al final de la cola de reproducción")
                                }
                            }.padding(6)
                                .background(model.videoID == video.id ? violeta.opacity(0.10) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .help("Reproducir \(video.titulo), de \(video.canal)")
                        }
                    }
                }.frame(height: 205)
            } else if !model.compacto {
                VStack(spacing: 8) {
                    Image(systemName: model.seccion == .listas ? "music.note.list" : "tray")
                        .font(.title2).foregroundStyle(.secondary)
                    Text(model.estado).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 120, maxHeight: 205)
            }
            }
        }
        .padding(model.pantallaCompletaVideo ? 0 : 16)
        .background(model.pantallaCompletaVideo ? Color.black : Color.clear)
        .frame(minWidth: model.compacto ? 500 : 660,
               idealWidth: model.compacto ? 560 : 720,
               minHeight: model.compacto ? 350 : 600,
               idealHeight: model.compacto ? 390 : 690)
    }

    private static let anchoVideoCompacto = ReproductorYouTubeModel.tamanoVideoCompacto.width
    private static let altoVideoCompacto = ReproductorYouTubeModel.tamanoVideoCompacto.height
}

@MainActor
final class ReproductorYouTubeInterno: NSObject, NSWindowDelegate {
    static let shared = ReproductorYouTubeInterno()
    let model = ReproductorYouTubeModel()
    private var window: NSWindow?
    var tieneContenido: Bool { !model.videoID.isEmpty }
    var tieneCola: Bool { !model.cola.isEmpty }
    var estadoControl: EstadoControlMusica {
        EstadoControlMusica(reproduciendo: model.reproduciendo,
                            tieneContenido: tieneContenido,
                            tieneCola: tieneContenido && model.cola.count > 1,
                            interfazVisible: window?.isVisible == true,
                            puedeAleatorio: model.puedeAleatorio)
    }

    override private init() { super.init() }

    func mostrar() {
        crearSiHaceFalta()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func ejecutar(_ consulta: String, reproducir: Bool,
                  completion: @escaping (ResultadoReproductorYouTube) -> Void) {
        mostrar()
        model.ejecutar(consulta, reproducir: reproducir, completion: completion)
    }

    func pausar() { model.pausar() }
    func reanudar() { mostrar(); model.reanudar() }
    func detener() { model.detener() }
    func anterior() { mostrar(); model.anterior() }
    func siguiente() { mostrar(); model.siguiente() }
    func aleatorio() { mostrar(); model.aleatorio() }

    /// Ejecuta un control y no responde “listo” hasta que el IFrame confirme el
    /// estado esperado. La espera es breve y acotada; nunca bloquea AppKit.
    func controlarVerificado(_ comando: ComandoMusica,
                             completion: @escaping (Bool) -> Void) {
        let idAnterior = model.videoID
        switch comando {
        case .pausar: model.pausar()
        case .reanudar: mostrar(); model.reanudar()
        case .detener: model.detener()
        case .siguiente: mostrar(); model.siguiente()
        case .anterior: mostrar(); model.anterior()
        case .aleatorio: mostrar(); model.aleatorio()
        default: completion(false); return
        }
        esperarControl(comando, idAnterior: idAnterior,
                       limite: Date().addingTimeInterval(5), completion: completion)
    }

    private func esperarControl(_ comando: ComandoMusica, idAnterior: String,
                                limite: Date, completion: @escaping (Bool) -> Void) {
        let confirmado: Bool
        switch comando {
        case .pausar:
            confirmado = !model.reproduciendo && model.estado.hasPrefix("En pausa:")
        case .reanudar:
            confirmado = model.reproduciendo
        case .detener:
            confirmado = !model.reproduciendo && model.estado == "Reproducción detenida."
        case .siguiente, .anterior, .aleatorio:
            confirmado = model.videoID != idAnterior && model.reproduciendo
        default:
            completion(false); return
        }
        if confirmado { completion(true); return }
        if model.estado.contains("no confirmó") || model.estado.contains("bloqueó")
            || Date() >= limite {
            completion(false); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.esperarControl(comando, idAnterior: idAnterior,
                                 limite: limite, completion: completion)
        }
    }

    func cerrar() {
        model.detener()
        // Desmontar WebKit garantiza silencio aunque YouTube no confirme Stop;
        // nunca dejamos un reproductor oculto sonando en segundo plano.
        desmontarVentana()
    }
    func alternarPantallaCompleta() {
        crearSiHaceFalta()
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            model.pantallaCompletaVideo = false
            window.toggleFullScreen(nil)
            return
        }
        if model.compacto {
            model.compacto = false
            model.pedirCompacto?(false)
        }
        model.pantallaCompletaVideo = true
        DispatchQueue.main.async { window.toggleFullScreen(nil) }
    }
    func alternarCompacto() {
        mostrar(); model.compacto.toggle(); model.pedirCompacto?(model.compacto)
    }
    func configurarCompacto(_ valor: Bool) {
        guard model.compacto != valor else { return }
        model.compacto = valor
        if window != nil { model.pedirCompacto?(valor) }
    }

    func windowWillClose(_ notification: Notification) {
        model.detener()
        DispatchQueue.main.async { [weak self] in self?.desmontarVentana() }
    }
    func windowWillMiniaturize(_ notification: Notification) {
        model.pausar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.model.reproduciendo else { return }
            // Si Pausa no fue confirmada, desmontar es el fail-closed seguro.
            self.desmontarVentana()
        }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        model.pantallaCompletaVideo = false
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        model.pantallaCompletaVideo = false
    }

    private func desmontarVentana() {
        guard let w = window else { model.cerrarSesion(); return }
        w.delegate = nil; w.orderOut(nil); w.contentViewController = nil
        window = nil; model.cerrarSesion()
    }

    private func crearSiHaceFalta() {
        guard window == nil else { return }
        let hosting = NSHostingController(rootView: ReproductorYouTubeView(model: model))
        let w = NSWindow(contentViewController: hosting)
        w.title = "Música · BtoDicta"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(model.compacto ? .init(width: 560, height: 390)
                                       : .init(width: 720, height: 690))
        w.minSize = model.compacto ? .init(width: 500, height: 350)
                                  : .init(width: 660, height: 600)
        w.level = model.compacto ? .floating : .normal
        w.isReleasedWhenClosed = false; w.delegate = self
        model.pedirPantallaCompleta = { [weak self] in self?.alternarPantallaCompleta() }
        model.pedirCompacto = { [weak w] compacto in
            guard let w, !w.styleMask.contains(.fullScreen) else { return }
            w.level = compacto ? .floating : .normal
            w.minSize = compacto ? .init(width: 500, height: 350)
                                  : .init(width: 660, height: 600)
            w.setContentSize(compacto ? .init(width: 560, height: 390)
                                      : .init(width: 720, height: 690))
        }
        w.center(); window = w
    }
}
