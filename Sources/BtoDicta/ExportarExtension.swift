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
    static func exportar(a destino: URL, nombreCarpeta: String = "BtoDicta-extension") -> Result<URL, Motivo> {
        guard let origen else { return .failure(Motivo(texto: "Esta copia de BtoDicta no trae la extensión dentro.")) }
        let fm = FileManager.default
        let carpeta = destino.appendingPathComponent(nombreCarpeta, isDirectory: true)

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

        **Cárgala desde esta ruta y no desde otra copia:**

        ```
        ~/.btodicta/extension
        ```

        **Instálala desde esa carpeta y no desde una copia.** BtoDicta la
        mantiene al día ahí: cada vez que la aplicación se actualice, los
        archivos se renuevan y el navegador recoge las mejoras al recargar la
        extensión. Una copia en el Escritorio se queda como esté el día que la
        hiciste, y deja de entenderse con BtoDicta en cuanto algo cambie.

        1. Abre `edge://extensions` (o `chrome://extensions`, `brave://extensions`).
        2. Activa **«Modo de desarrollador»**.
        3. Pulsa **«Cargar descomprimida»** y elige esa carpeta.
        4. Entra en las **opciones** de la extensión y **pega la clave**.

        ### ¿De dónde sale la clave?

        Si llegaste aquí pulsando «Sacarla a una carpeta…» en BtoDicta, **ya la
        tienes copiada**: en el paso 4 basta con pegar (⌘V).

        Si no, o si la perdiste:

        1. En BtoDicta, abre **Ajustes**.
        2. Busca **«Dejar que otros programas de este Mac transcriban»**.
        3. Enciende **«Abrir la puerta local»** si estaba apagada — viene apagada
           de fábrica, y sin ella la extensión no tiene con quién hablar.
        4. Aparece el campo **Token** con un botón **«Copiar»**.

        Es una contraseña: quien la tenga puede pedirle transcripciones a tu
        BtoDicta. No la publiques ni la mandes por chat.

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

        Una extensión cargada a mano **no se actualiza sola**: el navegador lo
        impide a propósito, porque una extensión sin firmar que se reescribiera
        sola sería un agujero. Solo se auto-actualizan las que vienen de una
        tienda.

        Lo que sí ocurre, si la cargaste desde `~/.btodicta/extension`: **los
        archivos se ponen al día solos** en cuanto arranca la versión nueva de
        BtoDicta. Para que el navegador los recoja, una de estas dos:

        - Reiniciar el navegador, o
        - Pulsar **«Actualizar»** en la tarjeta de la extensión.

        La aplicación te avisa cuando toca, en Ajustes y en el menú del icono.

        ## Si algo no va

        En la página de extensiones, la tarjeta de BtoDicta tiene dos enlaces
        útiles: **«Errores»**, si el navegador rechazó algo, y **«Service
        worker»**, que abre la consola donde se vería un fallo de envío.
        """
    }

    /// La ruta FIJA desde la que conviene cargar la extensión (RF-11).
    ///
    /// Cargarla desde aquí y no desde el Escritorio tiene una consecuencia
    /// práctica: la aplicación refresca estos archivos en cada actualización, así
    /// que el navegador recoge las mejoras al recargar la extensión, sin que
    /// nadie vuelva a exportar nada.
    ///
    /// **Lo que NO puede hacer, y conviene decirlo claro:** una extensión
    /// cargada a mano no se actualiza sola. Eso lo impide el navegador a
    /// propósito —una extensión sin firmar que se reescribiera sola sería un
    /// agujero—, y solo lo hacen las que vienen de una tienda. Lo que se
    /// consigue aquí es que los archivos estén al día; recogerlos es cosa del
    /// navegador, al reiniciarse o al pulsar «Actualizar».
    static var rutaFija: URL {
        Config.dir.appendingPathComponent("extension", isDirectory: true)
    }

    /// Qué versión hay ahora mismo en la ruta fija.
    static func versionEnRutaFija() -> String {
        let m = rutaFija.appendingPathComponent("manifest.json")
        guard let d = try? Data(contentsOf: m),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let v = j["version"] as? String else { return "" }
        return v
    }

    /// Pone al día la ruta fija si la versión cambió. Se llama al arrancar.
    ///
    /// Solo copia cuando hay diferencia: reescribir los archivos en cada arranque
    /// haría que el navegador considerase modificada la extensión cada vez, y
    /// eso son avisos que nadie pidió.
    static func refrescarRutaFija() {
        guard disponible else { return }
        let traida = EstadoNavegadores.versionQueTraeLaApp()
        let puesta = versionEnRutaFija()
        guard !traida.isEmpty, traida != puesta else { return }

        switch exportar(a: Config.dir, nombreCarpeta: "extension") {
        case .success:
            if puesta.isEmpty {
                Log.log(.sistema, "extensión del navegador preparada en \(rutaFija.path)")
            } else {
                Log.log(.sistema, "extensión del navegador actualizada de la \(puesta) a la \(traida) — recárgala en el navegador para que la recoja")
            }
        case .failure(let m):
            Log.log(.sistema, "no pude poner al día la extensión: \(m.texto)")
        }
    }

    /// Enseña la carpeta desde la que hay que instalarla, y copia la clave.
    ///
    /// Esto sustituye a «exportar a donde quieras», que era un error de diseño:
    /// una copia en el Escritorio **no se actualiza nunca**, y mantenerla al día
    /// es justo el motivo de que exista la ruta fija. Ofrecer las dos cosas
    /// invitaba a elegir la que no funciona a largo plazo.
    @discardableResult
    static func mostrarParaInstalar() -> URL? {
        refrescarRutaFija()
        guard FileManager.default.fileExists(atPath: rutaFija.path) else {
            let a = NSAlert()
            a.messageText = "No encuentro la extensión"
            a.informativeText = "Esta copia de BtoDicta no la trae dentro."
            a.runModal()
            return nil
        }

        let token = ApiLocal.token()
        if !token.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(token, forType: .string)
        }
        NSWorkspace.shared.activateFileViewerSelecting([rutaFija])

        let a = NSAlert()
        a.messageText = "Instalar la extensión"
        var pasos = """
        Se ha abierto la carpeta. Instálala DESDE AHÍ:

        1. Abre  edge://extensions  (o chrome://, brave://)
        2. Activa «Modo de desarrollador»
        3. «Cargar descomprimida» → elige la carpeta que acaba de abrirse
        4. En las opciones de la extensión, pega la clave

        Instálala desde esa carpeta y no desde una copia: esa es la que BtoDicta
        mantiene al día en cada actualización.
        """
        pasos += token.isEmpty
            ? "\n\nLa puerta local está apagada, así que todavía no hay clave. Enciéndela arriba."
            : "\n\nLa clave ya está copiada: en el paso 4 solo tienes que pegar."
        a.informativeText = pasos
        a.addButton(withTitle: "Entendido")
        a.runModal()
        return rutaFija
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

            // La clave, ya en el portapapeles.
            //
            // Sin esto, instalar la extensión obligaba a una búsqueda del tipo
            // «¿y de dónde saco el token?»: encender la puerta local, encontrar
            // el campo, copiarlo, y recordar dónde pegarlo. Cuatro pasos entre
            // dos aplicaciones distintas, y ninguno evidente. Ahora el que
            // exporta ya lleva la clave encima y solo tiene que pegar.
            let token = ApiLocal.token()
            if !token.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(token, forType: .string)
            }

            NSWorkspace.shared.activateFileViewerSelecting([carpeta])

            let a = NSAlert()
            a.messageText = "Extensión lista en \(carpeta.lastPathComponent)"
            var pasos = """
            1. Abre edge://extensions (o chrome://, brave://)
            2. Activa «Modo de desarrollador»
            3. «Cargar descomprimida» → elige la carpeta que acaba de abrirse
            4. En las opciones de la extensión, pega la clave
            """
            if token.isEmpty {
                pasos += "\n\nLa puerta local está apagada, así que todavía no hay clave. Enciéndela aquí arriba y vuelve a copiarla."
            } else {
                pasos += "\n\nLa clave ya está copiada: en el paso 4 solo tienes que pegar."
            }
            a.informativeText = pasos
            a.addButton(withTitle: "Entendido")
            a.runModal()
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
