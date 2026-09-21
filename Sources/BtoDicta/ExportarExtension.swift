import AppKit
import Foundation

/// Sacar la extensión de dentro de la aplicación (spec 006, T24, RF-09).
///
/// Una extensión cargada a mano vive en una carpeta del disco, y esa carpeta
/// tiene que existir antes de poder cargarla. Sin esto, la única forma de
/// conseguirla sería tener el repositorio del proyecto — lo cual convierte una
/// función del producto en algo reservado a quien lo desarrolla.
enum ExportarExtension {

    /// Un motivo legible. `Result` exige que el error conforme a `Error`, y una
    /// cadena suelta no lo hace.
    struct Motivo: Error { let texto: String }


    /// Dónde vive la extensión dentro del paquete de la aplicación.
    static var origen: URL? {
        Bundle.main.url(forResource: "extension", withExtension: nil)
    }

    static var disponible: Bool {
        guard let o = origen else { return false }
        return FileManager.default.fileExists(atPath: o.path)
    }

    /// Copia la extensión a `destino/BtoDicta-extension`, con su manual dentro.
    ///
    /// Devuelve la carpeta creada, o el motivo por el que no se pudo.
    static func exportar(a destino: URL) -> Result<URL, Motivo> {
        guard let origen else { return .failure(Motivo(texto: "Esta copia de BtoDicta no trae la extensión dentro.")) }
        let fm = FileManager.default
        let carpeta = destino.appendingPathComponent("BtoDicta-extension", isDirectory: true)

        do {
            // Si ya existe, se reemplaza: lo que se quiere es la versión que
            // trae ESTA aplicación, no una mezcla con lo que hubiera antes.
            // Se retira a la Papelera en vez de borrarse — una carpeta que
            // desaparece sin rastro no se puede recuperar si alguien había
            // dejado algo suyo dentro.
            if fm.fileExists(atPath: carpeta.path) {
                var papelera: NSURL?
                try? fm.trashItem(at: carpeta, resultingItemURL: &papelera)
                if fm.fileExists(atPath: carpeta.path) { try fm.removeItem(at: carpeta) }
            }
            try fm.copyItem(at: origen, to: carpeta)

            // El manifiesto correcto pasa a llamarse `manifest.json`: es lo
            // único que distingue un paquete de Chromium de uno de Firefox.
            let chromium = carpeta.appendingPathComponent("manifest.chromium.json")
            let destinoManifiesto = carpeta.appendingPathComponent("manifest.json")
            if fm.fileExists(atPath: chromium.path) {
                try? fm.removeItem(at: destinoManifiesto)
                try fm.copyItem(at: chromium, to: destinoManifiesto)
            }

            try manual().write(to: carpeta.appendingPathComponent("COMO-INSTALAR.md"),
                               atomically: true, encoding: .utf8)
            return .success(carpeta)
        } catch {
            return .failure(Motivo(texto: error.localizedDescription))
        }
    }

    /// El manual, escrito en el momento para que lleve la ruta y la versión de
    /// ESTA instalación. Un manual con rutas de ejemplo obliga a traducirlas.
    static func manual() -> String {
        let version = EstadoNavegadores.versionQueTraeLaApp()
        return """
        # La extensión de BtoDicta para el navegador

        Versión \(version.isEmpty ? "—" : version) · sale de BtoDicta \(Version.numero)

        Sirve para que la bitácora sepa **qué pestaña estás mirando y cuál está
        sonando**. Eso el sistema no puede verlo desde fuera, y sin ese dato la
        bitácora acaba anotando como trabajo un vídeo que sonaba de fondo.

        La extensión **solo observa**: no cambia páginas, no bloquea nada y no
        lee lo que escribes en ningún formulario.

        ## Instalarla en Edge, Chrome o Brave

        1. Abre `edge://extensions` (o `chrome://extensions`, `brave://extensions`).
        2. Activa **«Modo de desarrollador»**.
        3. Pulsa **«Cargar descomprimida»** y elige **esta misma carpeta**.
        4. Entra en las **opciones** de la extensión y pega la clave de BtoDicta.
           La encuentras en *Ajustes → Dejar que otros programas transcriban*.

        Sin la clave pegada, la extensión no envía absolutamente nada.

        ## Comprobar que funciona

        Abre una pestaña cualquiera y pregúntale a BtoDicta qué está viendo:

        ```
        curl -s http://127.0.0.1:8787/navegador \\
          -H "Authorization: Bearer $(cat ~/.btodicta/api-token)"
        ```

        Te dirá qué pestaña tienes delante, cuáles suenan, y **si ese momento se
        grabaría o no**, con el motivo.

        ## Qué no quieres que mire

        En las opciones de la extensión puedes añadir dominios. Lo que excluyas
        ahí **no sale del navegador**: no es que BtoDicta lo descarte después, es
        que nunca lo recibe.

        De fábrica la lista está vacía. Se mira todo hasta que tú digas lo
        contrario.

        ## Cuando BtoDicta se actualice

        Una extensión cargada a mano **no se actualiza sola**. Cuando la versión
        de BtoDicta traiga una extensión más nueva, la aplicación te avisará. Para
        ponerla al día: vuelve a sacarla desde Ajustes y pulsa **«Actualizar»** en
        `edge://extensions`.

        ## Si algo no va

        En la página de extensiones, la tarjeta de BtoDicta tiene dos enlaces
        útiles: **«Errores»**, si el navegador rechazó algo, y **«Service
        worker»**, que abre la consola donde se vería un fallo de envío.
        """
    }

    /// Pregunta dónde y exporta. Devuelve la carpeta creada.
    @discardableResult
    static func exportarPreguntando() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "¿Dónde quieres la extensión?"
        panel.prompt = "Guardar aquí"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let destino = panel.url else { return nil }

        switch exportar(a: destino) {
        case .success(let carpeta):
            Log.log(.sistema, "extensión exportada a \(carpeta.path)")
            NSWorkspace.shared.activateFileViewerSelecting([carpeta])
            return carpeta
        case .failure(let motivo):
            let a = NSAlert()
            a.messageText = "No pude dejar la extensión ahí"
            a.informativeText = motivo.texto
            a.runModal()
            return nil
        }
    }
}
