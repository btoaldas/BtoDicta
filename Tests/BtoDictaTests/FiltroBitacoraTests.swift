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
                       salvoApps: [String] = [], salvoTitulos: [String] = []) -> Bool {
        let v = FiltroBitacora.decidir(app: app, ventana: ventana,
                                       excluirApps: apps, excluirTitulos: titulos,
                                       incluirApps: salvoApps, incluirTitulos: salvoTitulos)
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
}
