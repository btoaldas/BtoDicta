import XCTest
@testable import BtoDicta

/// El catálogo de exclusiones propuestas (spec 007, T05 y T06).
///
/// Estas pruebas no tocan la configuración real: construyen sus propias
/// categorías. La única que lee el archivo embarcado lo hace para comprobar que
/// ese archivo está bien escrito, que es lo que nadie revisa después de la
/// primera vez.
final class SemillasExclusionTests: XCTestCase {

    private func cat(_ id: String, _ destino: SemillasExclusion.Destino,
                     _ entradas: [String]) -> SemillasExclusion.Categoria {
        .init(id: id, nombre: id, destino: destino, descripcion: "", entradas: entradas)
    }

    // MARK: El destino — el RF que nació de un fallo real

    /// Dos exclusiones pedidas se escribieron en la lista de títulos siendo
    /// aplicaciones de escritorio. Ahí no podían coincidir nunca, y el fallo fue
    /// silencioso: la configuración parecía puesta.
    func testCadaEntradaVaASuLista() {
        let (apps, titulos) = SemillasExclusion.repartir([
            cat("reproductores", .apps, ["vlc", "dota"]),
            cat("redes", .titulos, ["facebook.com"]),
        ])
        XCTAssertEqual(apps, ["vlc", "dota"])
        XCTAssertEqual(titulos, ["facebook.com"])
        // Y lo que de verdad importa: NO se cruzan.
        XCTAssertFalse(apps.contains("facebook.com"))
        XCTAssertFalse(titulos.contains("vlc"))
    }

    /// Una entrada de aplicación escrita en la lista de títulos es exactamente el
    /// fallo original. Se comprueba de punta a punta: repartida a su lista, el
    /// filtro la aplica; en la otra, no coincide con nada.
    func testUnaAppSoloExcluyeDesdeLaListaDeApps() {
        let (apps, titulos) = SemillasExclusion.repartir([cat("r", .apps, ["vlc"])])
        func entra(_ excApps: [String], _ excTitulos: [String]) -> Bool {
            if case .entra = FiltroBitacora.decidir(app: "VLC media player", ventana: "peli.mkv",
                                                    excluirApps: excApps, excluirTitulos: excTitulos,
                                                    incluirApps: [], incluirTitulos: []) { return true }
            return false
        }
        XCTAssertFalse(entra(apps, titulos), "en su lista, excluye")
        XCTAssertTrue(entra([], apps), "en la lista equivocada, no coincide con nada")
    }

    // MARK: Unir sin duplicar

    func testAceptarDosVecesNoDuplica() {
        let una = SemillasExclusion.unir([], con: ["facebook.com", "x.com"])
        let otra = SemillasExclusion.unir(una, con: ["facebook.com", "x.com"])
        XCTAssertEqual(una.count, 2)
        XCTAssertEqual(otra.count, 2, "aceptar la misma categoría dos veces no puede hacer crecer la lista")
    }

    func testUnirRespetaLoQueYaHabiaYIgnoraLaCaja() {
        let r = SemillasExclusion.unir(["mibanco.com"], con: ["  X.com  ", "x.com", "mibanco.com", ""])
        XCTAssertEqual(r, ["mibanco.com", "X.com"],
                       "conserva lo previo, recorta espacios y no repite por diferencia de mayúsculas")
    }

    // MARK: El catálogo embarcado

    /// El catálogo viaja dentro de la aplicación: un error aquí lo heredan todos
    /// los usuarios y nadie lo revisa después. Entre otras cosas comprueba que no
    /// haya entradas cortas —la comparación es por subcadena, y «sex» casaría con
    /// «Essex»— ni dominios sin punto.
    func testElCatalogoEmbarcadoEstaBienEscrito() {
        let c = SemillasExclusion.catalogo()
        guard !c.categorias.isEmpty else {
            // En la suite de pruebas no hay paquete de aplicación, así que el
            // recurso puede no estar. Se dice y no se inventa un aprobado.
            print("SEMILLAS OMITIDA — el recurso no está disponible en este contexto")
            return
        }
        XCTAssertEqual(SemillasExclusion.problemas(c), [],
                       "el catálogo embarcado tiene entradas que no sirven")
        XCTAssertGreaterThan(c.version, 0)
    }

    /// Y el validador tiene que encontrar de verdad lo que dice buscar: si nunca
    /// falla, la prueba de arriba no vale nada.
    func testElValidadorDetectaLoQueBusca() {
        let malo = SemillasExclusion.Catalogo(version: 1, categorias: [
            cat("a", .titulos, ["sex"]),            // corta Y sin punto: dos males
            cat("a", .titulos, ["facebook.com"]),   // identificador repetido
            cat("b", .titulos, ["Facebook.com"]),   // mayúsculas
            cat("c", .titulos, ["reproductor"]),    // sin punto: no es un dominio
            cat("d", .apps, []),                    // vacía
            cat("e", .apps, ["vs"]),                // corta incluso para una app
        ])
        let males = SemillasExclusion.problemas(malo)
        // «sex» dispara dos: corta y sin punto. Se afirma el conjunto entero y no
        // solo el número, porque un recuento acierta por casualidad.
        XCTAssertTrue(males.contains { $0.contains("«sex»") && $0.contains("corta") })
        XCTAssertTrue(males.contains { $0.contains("«sex»") && $0.contains("dominio") })
        XCTAssertTrue(males.contains { $0.contains("«a» está repetida") })
        XCTAssertTrue(males.contains { $0.contains("«Facebook.com»") && $0.contains("mayúsculas") })
        XCTAssertTrue(males.contains { $0.contains("«reproductor»") && $0.contains("dominio") })
        XCTAssertTrue(males.contains { $0.contains("«d» no tiene ni una entrada") })
        XCTAssertTrue(males.contains { $0.contains("«vs»") && $0.contains("corta") })
        XCTAssertEqual(males.count, 7, "no debería encontrar nada más: \(males)")
    }

    // MARK: Calcular lo que quedaría (T06)

    func testLoQueQuedariaUneConLoQueYaHabia() {
        let r = SemillasExclusion.nuevasListas(
            apps: ["mibanco"], titulos: ["intranet.ejemplo"],
            elegidas: [cat("r", .apps, ["vlc"]), cat("v", .titulos, ["youtube.com"])])
        XCTAssertEqual(r.apps, ["mibanco", "vlc"])
        XCTAssertEqual(r.titulos, ["intranet.ejemplo", "youtube.com"])
    }

    /// Aceptar dos veces no puede hacer crecer nada. Se comprueba encadenando,
    /// que es lo que pasa de verdad cuando alguien vuelve a abrir el asistente.
    func testAceptarDosVecesDejaLoMismo() {
        let cats = [cat("r", .apps, ["vlc"]), cat("v", .titulos, ["youtube.com"])]
        let una = SemillasExclusion.nuevasListas(apps: [], titulos: [], elegidas: cats)
        let dos = SemillasExclusion.nuevasListas(apps: una.apps, titulos: una.titulos, elegidas: cats)
        XCTAssertEqual(una.apps, dos.apps)
        XCTAssertEqual(una.titulos, dos.titulos)
    }

    /// Lo que el usuario tenía escrito a mano sobrevive intacto y va primero.
    func testNoPisaLoQueElUsuarioEscribio() {
        let r = SemillasExclusion.nuevasListas(
            apps: [], titulos: ["mi-banco-privado.ejemplo"],
            elegidas: [cat("v", .titulos, ["youtube.com", "netflix.com"])])
        XCTAssertEqual(r.titulos.first, "mi-banco-privado.ejemplo")
        XCTAssertEqual(r.titulos.count, 3)
    }

    // MARK: Lo rechazado no vuelve marcado (T08, RF-07)

    func testLoRechazadoSeSigueOfreciendoPeroDesmarcado() {
        let c = SemillasExclusion.Catalogo(version: 2, categorias: [
            cat("redes", .titulos, ["facebook.com"]),
            cat("video", .titulos, ["youtube.com"]),
        ])
        let p = SemillasExclusion.propuesta(c, rechazadas: ["video"])
        XCTAssertEqual(p.count, 2, "lo rechazado se sigue viendo: si no, no hay forma de cambiar de opinión")
        XCTAssertTrue(p.first { $0.categoria.id == "redes" }!.marcada)
        XCTAssertFalse(p.first { $0.categoria.id == "video" }!.marcada,
                       "una propuesta que reaparece marcada tras rechazarla decide por el usuario")
    }

    func testSoloSeMolestaAlUsuarioConUnCatalogoMasNuevo() {
        let c = SemillasExclusion.Catalogo(version: 2, categorias: [])
        XCTAssertTrue(SemillasExclusion.hayNovedades(c, vista: 1))
        XCTAssertFalse(SemillasExclusion.hayNovedades(c, vista: 2), "la misma versión no vuelve a salir sola")
        XCTAssertFalse(SemillasExclusion.hayNovedades(c, vista: 3))
    }

    /// Una entrada legítima no debe dar falso positivo, o el validador acabaría
    /// ignorándose.
    ///
    /// `vlc` está aquí por un motivo concreto: la primera versión del validador
    /// exigía cuatro letras a TODO y rechazaba «vlc», que es el nombre entero de
    /// una aplicación y estaba en el propio catálogo embarcado. El riesgo de una
    /// cadena corta es real en un título de ventana —texto largo y ajeno— y no en
    /// un nombre de aplicación, que es corto y lo pone el sistema.
    func testElValidadorNoSeQuejaDeLoBueno() {
        let bueno = SemillasExclusion.Catalogo(version: 1, categorias: [
            cat("redes", .titulos, ["facebook.com", "google.com/search"]),
            cat("apps", .apps, ["quicktime player", "vlc", "iina"]),
        ])
        XCTAssertEqual(SemillasExclusion.problemas(bueno), [])
    }
}
