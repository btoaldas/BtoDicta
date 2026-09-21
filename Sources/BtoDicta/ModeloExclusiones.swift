import SwiftUI

/// El estado de la pantalla de exclusiones (spec 007, T09–T12).
///
/// **Todo lo de aquí vive en memoria hasta que se pulsa Aplicar.** Esa es la
/// regla que sostiene el RNF-02, y no es una promesa del comentario: el único
/// sitio de todo el programa que escribe estas listas es
/// `SemillasExclusion.aplicar`, y hay una comprobación en el QA que cuenta los
/// sitios y falla si aparece otro.
///
/// El modo es la excepción y se dice por qué: un `Picker` de SwiftUI necesita un
/// valor que cambie al instante para poder pintarse, así que `modo` sí se mueve
/// al tocarlo — pero **tampoco se guarda** hasta Aplicar.
@MainActor
final class ModeloExclusiones: ObservableObject {

    struct Fila: Identifiable {
        let id: String
        let nombre: String
        let descripcion: String
        let destino: SemillasExclusion.Destino
        let entradas: [String]
    }

    @Published private(set) var categorias: [Fila] = []
    @Published private(set) var desplegadas: Set<String> = []
    @Published private(set) var ultimoResultado: String?

    /// Qué entradas están marcadas, por categoría. En memoria, siempre.
    @Published private var marcadas: [String: Set<String>] = [:]

    @Published var modo: FiltroBitacora.Modo = .permisivo

    private let modoGuardado: FiltroBitacora.Modo
    private let catalogo: SemillasExclusion.Catalogo

    init() {
        catalogo = SemillasExclusion.catalogo()
        modoGuardado = FiltroBitacora.modo()
        modo = modoGuardado

        let rech = SemillasExclusion.rechazadas()
        let yaExcluidoApps = Set(FiltroBitacora.appsExcluidas().map { $0.lowercased() })
        let yaExcluidoTitulos = Set(FiltroBitacora.titulosExcluidos().map { $0.lowercased() })

        categorias = catalogo.categorias.map {
            Fila(id: $0.id, nombre: $0.nombre, descripcion: $0.descripcion,
                 destino: $0.destino, entradas: $0.entradas)
        }

        for c in catalogo.categorias {
            let yaEstan = c.destino == .apps ? yaExcluidoApps : yaExcluidoTitulos
            if rech.contains(c.id) {
                // Rechazada en su día: se sigue ofreciendo —si no, no habría
                // forma de cambiar de opinión— pero desmarcada. Si alguna de sus
                // entradas ya está excluida a mano, esa sí se enseña marcada:
                // lo que se pinta debe ser el estado real, no la propuesta.
                marcadas[c.id] = Set(c.entradas.filter { yaEstan.contains($0.lowercased()) })
            } else {
                // Vienen marcadas. Es el «sí, sí, sí» rápido: desmarcar lo que
                // no se quiera cuesta menos que marcar lo que sí.
                marcadas[c.id] = Set(c.entradas)
            }
        }
    }

    // MARK: Lo que se ve

    func marcadasDe(_ id: String) -> Int { marcadas[id]?.count ?? 0 }

    var todasMarcadas: Bool {
        !categorias.isEmpty && categorias.allSatisfy { marcadasDe($0.id) == $0.entradas.count }
    }

    func alternarDespliegue(_ id: String) {
        if desplegadas.contains(id) { desplegadas.remove(id) } else { desplegadas.insert(id) }
    }

    func alternarTodas() {
        let marcar = !todasMarcadas
        for c in categorias { marcadas[c.id] = marcar ? Set(c.entradas) : [] }
        ultimoResultado = nil
    }

    /// El interruptor de una categoría entera.
    func enlaceCategoria(_ id: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in (self?.marcadasDe(id) ?? 0) > 0 },
            set: { [weak self] nuevo in
                guard let self, let fila = self.categorias.first(where: { $0.id == id }) else { return }
                self.marcadas[id] = nuevo ? Set(fila.entradas) : []
                self.ultimoResultado = nil
            })
    }

    /// El interruptor de una entrada suelta.
    func enlaceEntrada(_ id: String, _ entrada: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.marcadas[id]?.contains(entrada) ?? false },
            set: { [weak self] nuevo in
                guard let self else { return }
                var s = self.marcadas[id] ?? []
                if nuevo { s.insert(entrada) } else { s.remove(entrada) }
                self.marcadas[id] = s
                self.ultimoResultado = nil
            })
    }

    // MARK: El aviso de bitácora ciega (RF-08)

    /// El modo restrictivo sin nada incluido no graba absolutamente nada.
    ///
    /// Es coherente —«nada salvo lo incluido», y no hay nada incluido— y por eso
    /// mismo es peligroso: no da ningún error, y la bitácora vacía se ve igual
    /// que un día tranquilo. Se avisa antes de poder aplicarlo.
    var avisoDeModo: String? {
        guard modo == .restrictivo else { return nil }
        let incluye = FiltroBitacora.appsIncluidas().count + FiltroBitacora.titulosIncluidos().count
        if incluye == 0 {
            return "Con este modo y la lista de incluidos vacía, la bitácora no registrará NADA. "
                 + "No dará ningún error: simplemente no habrá nada grabado. "
                 + "Escribe primero qué sí quieres que se mire."
        }
        return "Solo se grabará lo que esté en tus \(incluye) reglas de inclusión. Todo lo demás queda fuera."
    }

    /// Si el aviso es el de la lista vacía, no se deja aplicar.
    private var modoBloqueado: Bool {
        modo == .restrictivo
            && FiltroBitacora.appsIncluidas().isEmpty
            && FiltroBitacora.titulosIncluidos().isEmpty
    }

    // MARK: Aplicar

    /// Qué categorías quedarían, con solo las entradas marcadas.
    private var elegidas: [SemillasExclusion.Categoria] {
        catalogo.categorias.compactMap { c in
            let m = marcadas[c.id] ?? []
            guard !m.isEmpty else { return nil }
            return .init(id: c.id, nombre: c.nombre, destino: c.destino,
                         descripcion: c.descripcion, entradas: c.entradas.filter { m.contains($0) })
        }
    }

    /// Cuántas entradas se añadirían de verdad. Lo que ya está no cuenta: decir
    /// «70 exclusiones» cuando 68 ya estaban sería mentir sobre el efecto.
    private var porAnadir: (apps: Int, titulos: Int) {
        let antesApps = FiltroBitacora.appsExcluidas()
        let antesTitulos = FiltroBitacora.titulosExcluidos()
        let despues = SemillasExclusion.nuevasListas(apps: antesApps, titulos: antesTitulos,
                                                     elegidas: elegidas)
        return (despues.apps.count - antesApps.count, despues.titulos.count - antesTitulos.count)
    }

    var hayCambios: Bool {
        if modoBloqueado { return false }
        let n = porAnadir
        return n.apps > 0 || n.titulos > 0 || modo != modoGuardado
    }

    var resumenDeCambios: String {
        let n = porAnadir
        var partes: [String] = []
        if n.titulos > 0 { partes.append("\(n.titulos) sitio(s)") }
        if n.apps > 0 { partes.append("\(n.apps) aplicación(es)") }
        if modo != modoGuardado { partes.append("y el modo de trabajo") }
        return partes.isEmpty ? "" : "Se añadirá: " + partes.joined(separator: ", ")
    }

    func aplicar() {
        guard !modoBloqueado else { return }
        let n = porAnadir
        SemillasExclusion.aplicar(elegidas)
        Config.set("bitacora_modo", to: modo.rawValue)

        // Lo desmarcado se recuerda como rechazado: sin esto, la próxima versión
        // se lo vuelve a proponer marcado y decide por él (RF-07).
        let rechazadas = Set(categorias.filter { marcadasDe($0.id) == 0 }.map(\.id))
        SemillasExclusion.guardarRechazadas(rechazadas)
        SemillasExclusion.guardarVersionVista(catalogo.version)

        var dicho: [String] = []
        if n.titulos > 0 { dicho.append("\(n.titulos) sitio(s)") }
        if n.apps > 0 { dicho.append("\(n.apps) aplicación(es)") }
        ultimoResultado = dicho.isEmpty ? "Guardado." : "Añadido: " + dicho.joined(separator: ", ")
        objectWillChange.send()
    }
}
