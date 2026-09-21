import XCTest
@testable import BtoDicta

/// Qué NO debe grabar la bitácora.
///
/// Por qué existe este archivo
/// ---------------------------
/// La exclusión por aplicación se pidió, se escribió y estuvo meses sin una sola
/// prueba. Cuando se comprobó, la lista `bitacora_excluir_apps` llevaba vacía
/// desde el principio: se habían configurado los cinco títulos web y ninguna de
/// las dos aplicaciones. El mecanismo era correcto y el resultado, no.
///
/// Todas las pruebas usan listas pasadas a mano. La otra variante de `decidir`
/// lee el `config.json` del usuario, y una prueba escrita contra ella mediría su
/// configuración real: pasaría o fallaría según lo que él tuviera puesto ese día,
/// que es lo contrario de una prueba.
final class FiltroBitacoraTests: XCTestCase {

    private func graba(app: String?, ventana: String?,
                       apps: [String] = [], titulos: [String] = [],
                       salvoApps: [String] = [], salvoTitulos: [String] = [],
                       modo: FiltroBitacora.Modo = .permisivo) -> Bool {
        let v = FiltroBitacora.decidir(app: app, ventana: ventana,
                                       excluirApps: apps, excluirTitulos: titulos,
                                       incluirApps: salvoApps, incluirTitulos: salvoTitulos,
                                       modo: modo)
        if case .entra = v { return true }
        return false
    }

    /// Sin reglas escritas no se filtra nada. Es el estado de fábrica y tiene que
    /// dejar pasar todo: un filtro que se activa solo sería una sorpresa.
    func testSinReglasEntraTodo() {
        XCTAssertTrue(graba(app: "VLC media player", ventana: "una película"))
    }

    /// El caso que originó las pruebas: dos aplicaciones de escritorio que el
    /// usuario pidió excluir por nombre.
    func testExcluyePorAplicacion() {
        XCTAssertFalse(graba(app: "VLC media player", ventana: "peli.mkv", apps: ["vlc"]))
        XCTAssertFalse(graba(app: "Dota 2", ventana: "", apps: ["dota"]))
    }

    /// Se compara por subcadena, en minúsculas y sin tildes: quien escribe una
    /// regla no debería tener que acertar cómo se escribe a sí misma cada app.
    func testCoincideSinImportarMayusculasNiTildes() {
        XCTAssertFalse(graba(app: "Música", ventana: "", apps: ["musica"]))
        XCTAssertFalse(graba(app: "vlc", ventana: "", apps: ["VLC"]))
    }

    /// Y no de más: una regla ancha que se coma aplicaciones ajenas sería peor
    /// que no tenerla, porque se pierde trabajo sin que nadie lo note.
    func testNoExcluyeLoQueNoCoincide() {
        XCTAssertTrue(graba(app: "Xcode", ventana: "FiltroBitacora.swift", apps: ["vlc", "dota"]))
    }

    func testExcluyePorTituloDeVentana() {
        XCTAssertFalse(graba(app: "Brave Browser", ventana: "Vídeo — YouTube", titulos: ["youtube"]))
        XCTAssertTrue(graba(app: "Brave Browser", ventana: "Correo — Gmail", titulos: ["youtube"]))
    }

    /// La lista blanca se mira ANTES que la negra, y por eso puede rescatar.
    /// Sin ese orden, «no grabes el navegador, salvo las reuniones» no se puede
    /// expresar: la regla ancha se comería la excepción.
    func testLaListaBlancaGana() {
        XCTAssertTrue(graba(app: "Brave Browser", ventana: "Reunión — meet.google.com",
                            titulos: ["meet"], salvoTitulos: ["meet.google"]))
        XCTAssertTrue(graba(app: "VLC media player", ventana: "clase grabada",
                            apps: ["vlc"], salvoApps: ["vlc media"]))
    }

    /// Una regla de aplicación no debe dispararse por el título, ni al revés:
    /// son dos campos distintos y confundirlos excluiría de más.
    func testLasReglasNoSeCruzanDeCampo() {
        XCTAssertTrue(graba(app: "Notas", ventana: "vlc: cómo se usa", apps: ["vlc"]))
        XCTAssertTrue(graba(app: "VLC media player", ventana: "peli.mkv", titulos: ["vlc"]))
    }

    /// Un campo vacío no puede hacer de comodín. `"".contains("vlc")` es falso,
    /// pero el guard de vacío se comprueba explícitamente porque el día que
    /// alguien invierta esa condición, todo dejaría de grabarse en silencio.
    func testUnCampoVacioNoExcluye() {
        XCTAssertTrue(graba(app: nil, ventana: nil, apps: ["vlc"], titulos: ["youtube"]))
        XCTAssertTrue(graba(app: "", ventana: "", apps: ["vlc"], titulos: ["youtube"]))
    }

    // MARK: Modo de trabajo (spec 007, T02, RF-03)

    /// El modo permisivo es el de siempre. Las ocho pruebas de arriba no pasan
    /// `modo`, así que ya lo comprueban por omisión; esta lo dice explícito para
    /// que se vea que el valor de fábrica no cambia de comportamiento.
    func testPermisivoSeComportaComoSiempre() {
        XCTAssertTrue(graba(app: "Xcode", ventana: "", apps: ["vlc"], modo: .permisivo))
        XCTAssertFalse(graba(app: "VLC media player", ventana: "", apps: ["vlc"], modo: .permisivo))
    }

    /// El caso que justifica el modo: solo entra lo autorizado.
    func testRestrictivoDejaFueraLoNoAutorizado() {
        XCTAssertTrue(graba(app: "Xcode", ventana: "", salvoApps: ["xcode"], modo: .restrictivo))
        XCTAssertFalse(graba(app: "Safari", ventana: "", salvoApps: ["xcode"], modo: .restrictivo))
    }

    /// Restrictivo con las listas de inclusión vacías **no graba nada**. Es
    /// coherente —«nada salvo lo incluido», y no hay nada incluido— y es justo
    /// el estado que la interfaz tiene que avisar antes de guardar (RF-08).
    /// Aquí se fija el comportamiento para que nadie lo «arregle» sin querer.
    func testRestrictivoSinInclusionesNoGrabaNada() {
        XCTAssertFalse(graba(app: "Xcode", ventana: "trabajo", modo: .restrictivo))
        XCTAssertFalse(graba(app: nil, ventana: nil, modo: .restrictivo))
    }

    /// En restrictivo, una lista de exclusión llena no autoriza nada por sí sola:
    /// lo que manda es la de inclusión. Sin esto, alguien podría creer que
    /// vaciar las exclusiones «abre» el modo restrictivo.
    func testEnRestrictivoLasExclusionesNoAutorizan() {
        XCTAssertFalse(graba(app: "Xcode", ventana: "", apps: ["vlc"], titulos: ["youtube"],
                             modo: .restrictivo))
    }

    /// Un valor que el código no reconoce cae SIEMPRE a permisivo.
    ///
    /// Los dos errores no cuestan lo mismo: caer a permisivo graba de más y se
    /// corrige borrando; caer a restrictivo no graba nada, sin aviso, y el pasado
    /// no se puede grabar después. Se elige el error reversible.
    func testModoDesconocidoCaeAPermisivo() {
        for crudo in [nil, "", "   ", "restricitvo", "strict", "RESTRICTIVE", "1", "null"] {
            XCTAssertEqual(FiltroBitacora.Modo.desde(crudo), .permisivo,
                           "«\(crudo ?? "nil")» debería caer a permisivo")
        }
    }

    /// Y los valores buenos sí se reconocen, con espacios y mayúsculas de por
    /// medio: si no, la prueba anterior pasaría con un código que ignora todo.
    func testLosValoresBuenosSeReconocen() {
        XCTAssertEqual(FiltroBitacora.Modo.desde("permisivo"), .permisivo)
        XCTAssertEqual(FiltroBitacora.Modo.desde("restrictivo"), .restrictivo)
        XCTAssertEqual(FiltroBitacora.Modo.desde("  Restrictivo  "), .restrictivo)
    }
}
