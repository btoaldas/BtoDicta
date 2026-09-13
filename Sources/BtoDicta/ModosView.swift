import AppKit
import SwiftUI

// MARK: - Pestaña Modos: qué hacer con lo dictado + su IA/prompt por modo

private let acentoMo = Color(red: 0.36, green: 0.28, blue: 0.62)

final class ModosModel: ObservableObject {
    @Published var modos: [Modo] = ModosStore.todos()
    @Published var defecto: String = Config.modoDefecto()

    func guardar() { ModosStore.guardar(modos) }
    /// Fija el modo POR DEFECTO (sticky). El cambio al vuelo va por el notch/menú.
    func ponerDefecto(_ id: String) {
        ModosStore.fijarDefecto(id); defecto = id
        // Refleja el cambio en el notch al instante.
        (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
    }
    func binding(_ id: String) -> Binding<Modo>? {
        // Buscar por id EN CADA acceso: un índice capturado queda obsoleto si
        // se borra/reordena un modo con el binding vivo (SIGTRAP del 17 jul).
        guard let inicial = modos.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.modos.first(where: { $0.id == id }) ?? inicial },
            set: { nuevo in
                guard let i = self.modos.firstIndex(where: { $0.id == id }) else { return }
                self.modos[i] = nuevo; self.guardar()
            })
    }
    func crear() -> String {
        let m = ModosStore.crear(nombre: "Mi modo")
        modos = ModosStore.todos()
        return m.id
    }
    func borrar(_ id: String) {
        ModosStore.borrar(id)
        modos = ModosStore.todos(); defecto = Config.modoDefecto()
        (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
    }
}

struct ModosView: View {
    @StateObject private var m = ModosModel()
    @State private var expandido: String?

    /// IAs de pulido conectadas (para el selector por modo).
    private var iasPulido: [ChatIA] { ChatIA.conectadasPulido }

    @State private var porVoz = Config.modoPorVoz()
    @State private var porContexto = Config.modoPorContexto()
    @State private var revertir = Config.modoRevertir()
    @State private var nuevoIdioma = ""
    @State private var idiomasVer = 0   // fuerza refrescar el picker tras añadir uno
    @State private var buscNombre = ""
    @State private var buscURL = ""
    @State private var buscVer = 0
    @State private var usarMacWA = ContactosWA.usarMac()
    @State private var contactosVer = 0
    @State private var resultadoImport = ""
    @State private var modoApps = Config.modoAplicaciones()
    @State private var pegarApps = Config.aplicacionPegarAutomatico()
    @State private var nuevoEnEditor = Config.aplicacionNuevoDocumento()
    @State private var appsVer = 0
    @State private var secretoConexion = ""      // borrador del secreto (jamás persiste aquí)
    @State private var avisoConexion = ""        // resultado de Guardar secreto / Probar
    @State private var conexionVer = 0
    // Export/import de modos (fase 6)
    @State private var avisoPortar = ""
    @State private var importPendiente: [Modo] = []      // parseados, esperando elección
    @State private var importErrores: [String] = []
    @State private var importSeleccion: Set<String> = [] // ids elegidos en el sheet
    @State private var mostrarImport = false

    // MARK: Export / Import de modos (con conexiones, SIN secretos)

    private func exportarModos() {
        let propios = m.modos.filter { !$0.esFijo }
        guard !propios.isEmpty else { avisoPortar = "No tienes modos propios para exportar."; return }
        guard let data = ModosPortables.exportar(propios) else {
            avisoPortar = "No pude preparar el paquete."; return
        }
        let p = NSSavePanel(); p.nameFieldStringValue = "modos_btodicta.json"
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let u = p.url {
            do {
                try data.write(to: u, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
                avisoPortar = "✅ Exporté \(propios.count) modo(s). Las claves NO se incluyen — cada quien pone la suya."
            } catch { avisoPortar = "No pude guardar: \(error.localizedDescription)" }
        }
    }

    private func abrirImportarModos() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]; p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url, let data = try? Data(contentsOf: u) else { return }
        let (validos, errores) = ModosPortables.importar(data)
        importPendiente = validos; importErrores = errores
        importSeleccion = Set(validos.map(\.id))   // todos marcados por defecto
        if validos.isEmpty {
            avisoPortar = "⚠️ Nada importable. " + errores.joined(separator: " · ")
        } else {
            mostrarImport = true
        }
    }

    private func confirmarImportModos() {
        let elegidos = importPendiente.filter { importSeleccion.contains($0.id) }
        ModosPortables.fusionar(elegidos)
        m.modos = ModosStore.todos()
        let conClave = elegidos.filter { ModosPortables.necesitaSecreto($0) }.map(\.nombre)
        avisoPortar = "✅ Importé \(elegidos.count) modo(s)."
            + (conClave.isEmpty ? "" : " Pon la clave en: \(conClave.joined(separator: ", ")).")
        if !importErrores.isEmpty { avisoPortar += " (\(importErrores.count) descartado(s))" }
        mostrarImport = false; importPendiente = []; importSeleccion = []
    }

    @ViewBuilder private var sheetImportModos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Elige qué modos importar").font(.headline)
            Text("Marca los que quieras. Los que necesiten clave se importan igual; luego pones TU clave en cada uno.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(importPendiente) { modo in
                        Toggle(isOn: Binding(
                            get: { importSeleccion.contains(modo.id) },
                            set: { on in if on { importSeleccion.insert(modo.id) } else { importSeleccion.remove(modo.id) } }
                        )) {
                            HStack {
                                Image(systemName: modo.icono).frame(width: 18)
                                Text(modo.nombre)
                                if modo.conexion != nil {
                                    Text("conexión API").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.15)).clipShape(Capsule())
                                }
                                if ModosPortables.necesitaSecreto(modo) {
                                    Text("⚠️ falta la clave").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }.toggleStyle(.checkbox)
                    }
                }
            }.frame(maxHeight: 260)
            if !importErrores.isEmpty {
                Text("Descartados: \(importErrores.joined(separator: " · "))")
                    .font(.caption2).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancelar") { mostrarImport = false; importPendiente = [] }
                Spacer()
                Button("Importar \(importSeleccion.count)") { confirmarImportModos() }
                    .buttonStyle(.borderedProminent).tint(acentoMo)
                    .disabled(importSeleccion.isEmpty)
            }
        }.padding(16).frame(width: 420)
    }

    private func importarContactos() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.commaSeparatedText, .json, .plainText, .text, .vCard]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url {
            let r = ContactosWA.importar(u)
            resultadoImport = "✅ \(r.validos) importados (\(r.detalle)) · \(r.invalidos) inválidos · \(r.total) en total"
            contactosVer += 1
        }
    }
    private func exportarContactos(_ formato: String) {
        let p = NSSavePanel(); p.nameFieldStringValue = "contactos_whatsapp.\(formato)"
        if p.runModal() == .OK, let u = p.url {
            let txt = formato == "json" ? ContactosWA.exportarJSON() : ContactosWA.exportarCSV()
            try? txt.write(to: u, atomically: true, encoding: .utf8)
        }
    }

    /// Lista de idiomas para el picker; garantiza que el valor actual sea seleccionable.
    /// Compara EXACTO (no case-insensitive): si el valor guardado difiere en
    /// mayúsculas/acentos de un base, se inserta tal cual para que el tag empareje
    /// y el Picker nunca quede en blanco.
    private func listaIdiomas(_ actual: String) -> [(nombre: String, bandera: String)] {
        var lista = Idiomas.todos()
        if !actual.isEmpty, !lista.contains(where: { $0.nombre == actual }) {
            lista.insert((actual, Idiomas.bandera(actual)), at: 0)
        }
        return lista
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Modos — qué hacer con lo dictado", systemImage: "wand.and.stars")
                    .font(.headline).foregroundStyle(acentoMo)
                Spacer()
                Button { AnalizadorWindow.show() } label: { Image(systemName: "wand.and.stars.inverse") }
                    .help("Mejorar modos: analiza el registro y sugiere mejoras (autónomo o con IA)")
                Button { ModosLog.abrir() } label: { Image(systemName: "doc.text.magnifyingglass") }
                    .help("Ver el registro detallado de modos (para analizar y mejorar)")
                Menu {
                    Button("Exportar mis modos…") { exportarModos() }
                    Button("Importar modos…") { abrirImportarModos() }
                } label: { Image(systemName: "square.and.arrow.up.on.square") }
                    .help("Compartir tus modos (con conexiones, SIN claves) o traer los de alguien más")
                    .frame(width: 34)
                Button { expandido = m.crear() } label: { Image(systemName: "plus") }
                    .help("Crear un modo propio")
            }
            if !avisoPortar.isEmpty {
                Text(avisoPortar).font(.caption)
                    .foregroundStyle(avisoPortar.hasPrefix("✅") ? Color.green : Color.secondary)
                    .textSelection(.enabled)
            }
            Text("El MODO decide qué hacer con tu dictado: pulirlo, formatearlo, traducirlo, responder, poner música, buscar o abrir una aplicación instalada. Marca uno como POR DEFECTO aquí; cámbialo al vuelo desde el notch (arriba-izquierda) o el menú de la barra.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("El modo elegido al vuelo es de UN SOLO USO (vuelve al de por defecto tras dictar)", isOn: $revertir)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: revertir) { _, v in Config.set("modo_revertir", to: v) }
            Text("Encendido: cambiar a Correo/Traducir/… desde el notch aplica solo a ese dictado y luego vuelve al modo por defecto. Apagado: el modo elegido se queda fijo hasta que lo cambies.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Activar un modo POR VOZ", isOn: $porVoz)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: porVoz) { _, v in Config.set("modo_por_voz", to: v) }
            Text("Si lo enciendes y empiezas el dictado con la frase de un modo (ej. \"modo tarea comprar la comida\"), ese modo se aplica solo a ese dictado y la frase se quita. Edita o vacía cada frase abajo.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Activar un modo POR APP / SITIO WEB", isOn: $porContexto)
                .toggleStyle(.switch).controlSize(.mini)
                .onChange(of: porContexto) { _, v in Config.set("modo_por_contexto", to: v) }
            Text("Aplica un modo solo por estar en cierta app o página. Ej.: en Outlook usa Correo; en tu intranet (por URL) usa Oficio. Configura las apps y sitios de cada modo abajo. La voz manda sobre el contexto.")
                .font(.caption2).foregroundStyle(.secondary)

            ForEach(m.modos) { modo in
                tarjetaModo(modo)
            }
        }
        .sheet(isPresented: $mostrarImport) { sheetImportModos }
    }

    @ViewBuilder private func tarjetaModo(_ modo: Modo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: modo.icono).foregroundStyle(acentoMo).frame(width: 20)
                Text(modo.nombre).font(.subheadline).bold()
                Spacer()
                if m.defecto == modo.id {
                    Label("Por defecto", systemImage: "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    Button("Poner por defecto") { m.ponerDefecto(modo.id) }.controlSize(.small)
                }
                Button {
                    expandido = expandido == modo.id ? nil : modo.id
                    nuevoIdioma = ""   // no arrastrar borrador entre tarjetas
                } label: {
                    Image(systemName: expandido == modo.id ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(expandido == modo.id
                          ? "Ocultar la configuración de \(modo.nombre)"
                          : "Mostrar y editar la configuración de \(modo.nombre)")
            }
            if expandido == modo.id, let b = m.binding(modo.id) {
                editor(b)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Puente [String] ⇄ texto "a, b, c" para editar listas en un TextField.
    private func listaTexto(_ b: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { b.wrappedValue.joined(separator: ", ") },
            set: { b.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }

    @ViewBuilder private func editor(_ b: Binding<Modo>) -> some View {
        Divider()
        // Modo PROPIO: nombre + comportamiento base editables.
        if !b.wrappedValue.esFijo {
            HStack {
                Text("Nombre:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("Mi modo", text: b.nombre).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            HStack {
                Text("Comportamiento:").font(.caption).frame(width: 110, alignment: .leading)
                Picker("", selection: b.base) {
                    Text("Pulir / reescribir").tag("pulir")
                    Text("Traducir").tag("traducir")
                    Text("Responder (asistente)").tag("responder")
                    Text("Agente (responde por voz + tus tareas/notas)").tag("agente")
                    Text("Buscar (web / Spotlight)").tag("buscar")
                    Text("Música (servicios con failover)").tag("musica")
                    Text("Acción (abrir app/correo/web)").tag("accion")
                    Text("Aplicación instalada (nombre por voz)").tag("aplicacion")
                }.labelsHidden().frame(width: 200)
            }
        }
        // Color del modo en el notch (letrero + tinte de fondo). Vacío = automático
        // (paleta fija para los modos base; color estable por id para los propios).
        HStack {
            Text("Color:").font(.caption).frame(width: 90, alignment: .leading)
            ColorPicker("", selection: Binding<Color>(
                get: { Color(nsColor: ColorModo.de(b.wrappedValue)) },
                set: {
                    b.wrappedValue.color = ColorModo.aHex(NSColor($0))
                    (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
                }
            )).labelsHidden().frame(width: 44)
            if !b.wrappedValue.color.isEmpty {
                Button("Automático") {
                    b.wrappedValue.color = ""
                    (NSApp.delegate as? AppDelegate)?.refrescarModoNotch()
                }.controlSize(.small)
            }
            Text("se ve en el notch (letrero y fondo)").font(.caption2).foregroundStyle(.secondary)
        }
        // Palabra de voz (para activar por voz)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Frases de voz:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("ej. modo tarea, mudo tarea (vacío = sin voz)", text: b.palabraVoz)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
            }
            Text("Separa VARIAS con coma (failover ante mal-escuchas). Si una frase lleva coma, escríbela entre comillas: \"Oye, Bto\". La puntuación no afecta la coincidencia.")
                .font(.caption2).foregroundStyle(.secondary).padding(.leading, 98)
        }
        // Frases de ejemplo para el reconocimiento INTELIGENTE (embeddings)
        if b.wrappedValue.id != "dictado" {
            HStack(alignment: .top) {
                Text("Ejemplos:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. mándale un whatsapp, escribir por whatsapp", text: listaTexto(b.ejemplosVoz))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Formas NATURALES de pedir este modo (para el reconocimiento inteligente por significado). Tus frases se embeben con TU motor. Sepáralas con coma.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // Triggers por contexto (app / sitio). Dictado no dispara por contexto.
        if b.wrappedValue.id != "dictado" {
            HStack(alignment: .top) {
                Text("En apps:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. Outlook, Mail, com.microsoft.Outlook", text: listaTexto(b.apps))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Nombres o bundle IDs, separados por coma. Coincide por parte del nombre.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Text("En sitios:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("ej. docs.ejemplo.com, mail.google.com", text: listaTexto(b.sitios))
                        .textFieldStyle(.roundedBorder).frame(width: 300)
                    Text("Dominios o trozos de URL (navegador). Requiere permiso de Automatización la 1ª vez.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        // Traducir: idioma destino como LISTA con banderita + agregar propios
        if b.wrappedValue.base == "traducir" {
            HStack(alignment: .top) {
                Text("Traducir a:").font(.caption).frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: b.idiomaDestino) {
                        ForEach(listaIdiomas(b.wrappedValue.idiomaDestino), id: \.nombre) { item in
                            Text("\(item.bandera)  \(item.nombre.capitalized)").tag(item.nombre)
                        }
                    }.labelsHidden().frame(width: 220)
                    HStack {
                        TextField("Agregar otro idioma…", text: $nuevoIdioma)
                            .textFieldStyle(.roundedBorder).frame(width: 150)
                        Button("Añadir") {
                            let n = Idiomas.agregar(nuevoIdioma)
                            if !n.isEmpty { b.idiomaDestino.wrappedValue = n; nuevoIdioma = ""; idiomasVer += 1 }
                        }.controlSize(.small)
                        .disabled(nuevoIdioma.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .id(idiomasVer)
        }
        // Buscar: buscador destino (web o Spotlight) + URL personalizada. Sin IA ni prompt.
        if b.wrappedValue.base == "buscar" {
            let _ = buscVer
            HStack {
                Text("Buscar en:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.buscador) {
                    ForEach(Buscadores.paraPicker(), id: \.id) { item in Text(item.nombre).tag(item.id) }
                }.labelsHidden().frame(width: 240)
            }
            if b.wrappedValue.buscador == "personalizado" {
                HStack {
                    Text("URL:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("https://ejemplo.com/buscar?q={q}", text: b.prompt)
                        .textFieldStyle(.roundedBorder).frame(width: 280)
                }
            }
            // Agregar un buscador PROPIO (queda disponible para todos los modos Buscar)
            HStack(spacing: 6) {
                Text("+ Propio:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("Nombre", text: $buscNombre).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("https://sitio.com/?q={q}", text: $buscURL).textFieldStyle(.roundedBorder).frame(width: 200)
                Button("Guardar") {
                    let n = buscNombre.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty, buscURL.contains("{q}") {
                        var ps = Config.buscadoresPersonales(); ps.append(["nombre": n, "url": buscURL])
                        Config.set("buscadores_personales", to: ps)
                        b.buscador.wrappedValue = "personal:\(n.lowercased())"
                        buscNombre = ""; buscURL = ""; buscVer += 1
                    }
                }.controlSize(.small).disabled(buscNombre.trimmingCharacters(in: .whitespaces).isEmpty || !buscURL.contains("{q}"))
            }
            Text("Dictas y se abre el buscador con tu consulta (usa {q} donde va el texto). Agrega los tuyos (Wikipedia, Gmail, Amazon… ya vienen). Spotlight abre ⌘Espacio. Sin IA.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Música: proveedor fijo para este modo o cascada global del Asistente.
        if b.wrappedValue.base == "musica" {
            HStack {
                Text("Al dictar:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.musicaAccion) {
                    Text("Entender “pon” o “busca”").tag("auto")
                    Text("Siempre reproducir").tag("reproducir")
                    Text("Solo buscar").tag("buscar")
                }.labelsHidden().frame(width: 250)
            }
            HStack {
                Text("Música en:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.musicaProveedor) {
                    Text("Automático (usa la cascada)").tag("auto")
                    ForEach(Musica.catalogo(), id: \.id) { p in Text(p.nombre).tag(p.id) }
                }.labelsHidden().frame(width: 250)
            }
            Text("“Pon/reproduce” intenta sonar; “busca” solo muestra resultados. Con proveedor Automático usa la cascada de Ajustes → Asistente.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Acción: qué abrir con el texto (app/correo/web) — Fase 5. Sin IA ni prompt.
        if b.wrappedValue.base == "accion" {
            HStack {
                Text("Acción:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.accion) {
                    ForEach(Acciones.base, id: \.id) { item in Text(item.nombre).tag(item.id) }
                }.labelsHidden().frame(width: 260)
            }
            if b.wrappedValue.accion == "url" {
                HStack {
                    Text("URL:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("https://docs.ejemplo.com/…?q={q}", text: b.prompt)
                        .textFieldStyle(.roundedBorder).frame(width: 280)
                }
            }
            // WhatsApp: contactos para "enviar a <nombre>"
            if b.wrappedValue.accion == "whatsapp" {
                let _ = contactosVer
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contactos (\(ContactosWA.importados().count) importados) — para \"enviar a <nombre>\"")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Importar CSV/JSON…") { importarContactos() }.controlSize(.small)
                        Button("Exportar CSV") { exportarContactos("csv") }.controlSize(.small)
                        Button("Exportar JSON") { exportarContactos("json") }.controlSize(.small)
                        Toggle("Contactos de Mac", isOn: $usarMacWA).toggleStyle(.switch).controlSize(.mini)
                            .onChange(of: usarMacWA) { _, v in Config.set("wa_usar_contactos_mac", to: v) }
                    }
                    if !resultadoImport.isEmpty {
                        Text(resultadoImport).font(.caption).foregroundStyle(.green)
                    }
                    Text("Di \"modo whatsapp, a Andrés, hola qué tal\" → busca a Andrés y abre su chat. Si hay varios, eliges. Importa CSV/JSON (o export de Google/Gmail: detecta columnas Nombre/Teléfono). Exportar vacío = te da un ejemplo del formato. Si no encuentra el nombre, cae a Contactos de Mac.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if b.wrappedValue.accion == "conexion" {
                seccionConexion(b)
            } else {
                Text("Dictas y se abre eso con tu texto (usa {q} en tu URL). Nota de Apple crea y verifica una nota real; Finder y otras apps sin API dejan el texto respaldado en el portapapeles. Tu intranet/tu web: pon la URL. Sin IA.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        // Aplicación: inventario automático + comportamiento seguro al colocar texto.
        if b.wrappedValue.base == "aplicacion" {
            let _ = appsVer
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Permitir abrir aplicaciones instaladas por voz", isOn: $modoApps)
                    .toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: modoApps) { _, v in
                        Config.set("modo_aplicaciones", to: v)
                        ModoCatalogoCache.invalidar()
                        if v { AplicacionesMac.precalentar() }
                    }
                Toggle("Pegar el texto automáticamente al abrir", isOn: $pegarApps)
                    .toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: pegarApps) { _, v in Config.set("aplicacion_pegar_automatico", to: v) }
                Toggle("Crear documento nuevo en Word/TextEdit/LibreOffice", isOn: $nuevoEnEditor)
                    .toggleStyle(.switch).controlSize(.mini)
                    .onChange(of: nuevoEnEditor) { _, v in Config.set("aplicacion_nuevo_documento", to: v) }
                HStack {
                    Text("\(AplicacionesMac.todas().count) aplicaciones detectadas en esta Mac")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Actualizar lista") { _ = AplicacionesMac.refrescar(); appsVer += 1 }
                        .controlSize(.small)
                }
                Text("Ejemplo: «modo abrir aplicación Word, borrador del informe». En editores compatibles crea un documento; en las demás activa la app y pega donde esté el cursor. Nunca pulsa Enter ni envía. Si no puede pegar, el texto queda en el portapapeles.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        // Guardar en la lista local (Tareas/Notas) — Fase 4. No aplica a Buscar/Acción/Dictado.
        if b.wrappedValue.id != "dictado" && !["buscar", "accion", "aplicacion"].contains(b.wrappedValue.base) {
            HStack {
                Text("Guardar en:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: b.almacen) {
                    Text("No guardar").tag("")
                    Text("Tareas").tag("tarea")
                    Text("Notas").tag("nota")
                }.labelsHidden().frame(width: 160)
            }
        }
        // Prompt (salvo Dictado/Traducir/Buscar/Acción, que no usan prompt libre).
        // Excepción: una Conexión API SÍ usa prompt (instrucciones para la IA
        // sobre cómo usar esa API — el conocimiento del dominio vive AHÍ).
        if b.wrappedValue.id != "dictado" && (!["buscar", "traducir", "accion", "aplicacion"].contains(b.wrappedValue.base) || b.wrappedValue.accion == "conexion" && b.wrappedValue.base == "accion") {
            Text("Instrucción para la IA (prompt):").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: b.prompt)
                .font(.callout).frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
        } else if b.wrappedValue.id == "dictado" {
            Text("El modo Dictado usa la limpieza estándar (puntuación, muletillas, glosario). Su 'estilo' se ajusta en Ajustes → Pulido.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // IA propia del modo (no aplica a Buscar/Acción, que no usan IA).
        // Excepción: la Conexión API elegirá su IA para estructurar el plan.
        if !["buscar", "accion", "aplicacion"].contains(b.wrappedValue.base) || b.wrappedValue.accion == "conexion" && b.wrappedValue.base == "accion" {
            HStack {
                Text("IA de este modo:").font(.caption).frame(width: 110, alignment: .leading)
                Picker("", selection: b.proveedorId) {
                    Text("Global (la de Pulido)").tag("")
                    ForEach(iasPulido, id: \.id) { ia in
                        Text(ia.proveedorCorto).tag(ia.id)
                    }
                }.labelsHidden().frame(width: 220)
            }
            if !b.wrappedValue.proveedorId.isEmpty {
                HStack {
                    Text("Modelo:").font(.caption).frame(width: 110, alignment: .leading)
                    TextField("(default del proveedor)", text: b.modelo).textFieldStyle(.roundedBorder).frame(width: 220)
                }
            }
            Text("Consejo: deja la IA en 'Global' para usar la misma que pules; o elige una específica (ej. una potente para 'Asistente', una gratis para 'Tarea').")
                .font(.caption2).foregroundStyle(.secondary)
        }
        // Borrar (solo modos propios; los base no se borran)
        if !b.wrappedValue.esFijo {
            Button(role: .destructive) {
                expandido = nil; m.borrar(b.wrappedValue.id)
            } label: { Label("Borrar este modo", systemImage: "trash") }
            .controlSize(.small)
        }
    }

    // MARK: Conexión API declarada por el usuario (accion == "conexion")

    /// El campo `conexion` del modo es opcional; este binding materializa una
    /// conexión vacía al primer toque para que la UI edite directo.
    private func conexionBinding(_ b: Binding<Modo>) -> Binding<ConexionAPI> {
        Binding(get: { b.wrappedValue.conexion ?? ConexionAPI() },
                set: { b.wrappedValue.conexion = $0 })
    }

    /// [String:String] ⇄ "Clave=Valor, Otra=Valor2" para encabezados extra.
    private func headersTexto(_ h: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { h.wrappedValue.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") },
            set: { texto in
                var out: [String: String] = [:]
                for par in texto.split(separator: ",") {
                    let kv = par.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2, !kv[0].isEmpty { out[kv[0]] = kv[1] }
                }
                h.wrappedValue = out
            })
    }

    @ViewBuilder private func seccionConexion(_ b: Binding<Modo>) -> some View {
        let conex = conexionBinding(b)
        let modoId = b.wrappedValue.id
        let _ = conexionVer
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Conexión API — este modo llama la API que declares aquí. Nada de esto viene en la app: URL, endpoints y credenciales son tuyos. Solo lectura (GET) por ahora; escritura con confirmación en la siguiente fase.")
                .font(.caption2).foregroundStyle(.secondary)
            let baseActual = b.wrappedValue.conexion?.baseURL ?? ""
            HStack {
                Text("URL base:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("https://api.ejemplo.com", text: conex.baseURL)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
                if !baseActual.isEmpty, !ConexionesMotor.urlSegura(baseActual) {
                    Text("⚠️ https (o http solo localhost)").font(.caption2).foregroundStyle(.red)
                }
            }
            // Autenticación: la forma se guarda en el modo; el SECRETO va al Llavero.
            HStack {
                Text("Autenticación:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: conex.auth.tipo) {
                    Text("Sin autenticación").tag("ninguna")
                    Text("API key en encabezado").tag("apikey")
                    Text("Usuario y clave (login → token)").tag("login")
                }.labelsHidden().frame(width: 220)
            }
            if b.wrappedValue.conexion?.auth.tipo == "login" {
                HStack {
                    Text("Login:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("/login", text: conex.auth.loginRuta)
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                    Picker("", selection: conex.auth.loginFormato) {
                        Text("JSON").tag("json"); Text("Formulario").tag("form")
                    }.labelsHidden().frame(width: 110)
                }
                HStack {
                    Text("Campos:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("email", text: conex.auth.campoUsuario)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .help("Nombre del campo de usuario en el body del login")
                    TextField("password", text: conex.auth.campoClave)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .help("Nombre del campo de la clave")
                    TextField("token (o data.access_token)", text: conex.auth.campoToken)
                        .textFieldStyle(.roundedBorder).frame(width: 170)
                        .help("Dónde viene el token en la respuesta (admite rutas con punto)")
                }
                HStack {
                    Text("Usuario:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("usuario@dominio", text: conex.auth.usuario)
                        .textFieldStyle(.roundedBorder).frame(width: 170)
                    Text("Vence (min):").font(.caption)
                    TextField("45", value: conex.auth.ttlMinutos, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                }
                HStack {
                    Text("Clave:").font(.caption).frame(width: 90, alignment: .leading)
                    SecureField("clave (se guarda en el Llavero)", text: $secretoConexion)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                    Button("Guardar clave") {
                        let r = SecretosKeychain.guardar(secretoConexion, cuenta: modoId)
                        ConexionesAuth.invalidar(modoId)   // clave nueva ⇒ token viejo fuera
                        avisoConexion = r.ok ? "Clave guardada en \(r.donde.rawValue)."
                                             : "No pude guardar la clave."
                        secretoConexion = ""; conexionVer += 1
                    }.controlSize(.small)
                    .disabled(secretoConexion.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let donde = SecretosKeychain.donde(cuenta: modoId) {
                        Text(donde == .keychain ? "✓ en el Llavero" : "⚠️ en \(donde.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(donde == .keychain ? Color.green : Color.orange)
                        Button("Quitar") {
                            SecretosKeychain.borrar(cuenta: modoId)
                            ConexionesAuth.invalidar(modoId)
                            avisoConexion = "Clave eliminada."; conexionVer += 1
                        }.controlSize(.small)
                    }
                }
            }
            if b.wrappedValue.conexion?.auth.tipo == "apikey" {
                HStack {
                    Text("Encabezado:").font(.caption).frame(width: 90, alignment: .leading)
                    TextField("Authorization", text: conex.auth.header)
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                    Text("Prefijo:").font(.caption)
                    TextField("Bearer ", text: conex.auth.prefijo)
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                }
                HStack {
                    Text("Secreto:").font(.caption).frame(width: 90, alignment: .leading)
                    SecureField("API key (se guarda en el Llavero)", text: $secretoConexion)
                        .textFieldStyle(.roundedBorder).frame(width: 200)
                    Button("Guardar secreto") {
                        let r = SecretosKeychain.guardar(secretoConexion, cuenta: modoId)
                        avisoConexion = r.ok
                            ? "Secreto guardado en \(r.donde.rawValue)."
                            : "No pude guardar el secreto."
                        secretoConexion = ""; conexionVer += 1
                    }.controlSize(.small)
                    .disabled(secretoConexion.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let donde = SecretosKeychain.donde(cuenta: modoId) {
                        Text(donde == .keychain ? "✓ en el Llavero" : "⚠️ en \(donde.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(donde == .keychain ? Color.green : Color.orange)
                        Button("Quitar") {
                            SecretosKeychain.borrar(cuenta: modoId)
                            avisoConexion = "Secreto eliminado."; conexionVer += 1
                        }.controlSize(.small)
                    }
                }
            }
            HStack {
                Text("Encabezados:").font(.caption).frame(width: 90, alignment: .leading)
                TextField("Accept=application/json, X-Cliente=beto", text: headersTexto(conex.headers))
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            // Endpoints declarados
            HStack {
                Text("Endpoints:").font(.caption).frame(width: 90, alignment: .leading)
                Button {
                    var c = b.wrappedValue.conexion ?? ConexionAPI()
                    c.endpoints.append(EndpointAPI(clave: "endpoint\(c.endpoints.count + 1)"))
                    b.wrappedValue.conexion = c
                } label: { Label("Añadir endpoint", systemImage: "plus") }.controlSize(.small)
            }
            ForEach(conex.endpoints) { $ep in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("clave", text: $ep.clave)
                            .textFieldStyle(.roundedBorder).frame(width: 110)
                        Picker("", selection: $ep.metodo) {
                            ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 85)
                        TextField("/ruta/{variable}", text: $ep.ruta)
                            .textFieldStyle(.roundedBorder).frame(width: 170)
                        Button {
                            var c = b.wrappedValue.conexion ?? ConexionAPI()
                            c.endpoints.removeAll { $0.id == ep.id }
                            b.wrappedValue.conexion = c
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Descripción (una línea; la verá la IA)", text: $ep.descripcion)
                            .textFieldStyle(.roundedBorder).frame(width: 260)
                        Toggle("Escritura", isOn: $ep.esEscritura)
                            .toggleStyle(.switch).controlSize(.mini)
                            .help("Los endpoints de escritura (y todo método distinto de GET) exigirán confirmación")
                    }
                    HStack {
                        Text("Query:").font(.caption2).frame(width: 45, alignment: .leading)
                        TextField("q={texto}&formato=json", text: $ep.query)
                            .textFieldStyle(.roundedBorder).frame(width: 320)
                    }
                    if ep.metodo != "GET" {
                        Text("Body (JSON con {variables}):").font(.caption2).foregroundStyle(.secondary)
                        TextEditor(text: $ep.bodyPlantilla)
                            .font(.caption.monospaced()).frame(height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))
                    }
                    seccionVariables($ep)
                }
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.25)))
            }
            // Flujo proponer→confirmar: el endpoint de escritura elegido actúa
            // de propuesta y, tras tu OK, corre este segundo endpoint.
            HStack {
                Text("Propuesta:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: conex.previewEndpointId) {
                    Text("Ninguna (cada escritura se confirma localmente)").tag("")
                    ForEach((b.wrappedValue.conexion?.endpoints ?? []).filter { !$0.clave.isEmpty && $0.efectivamenteEscritura }, id: \.clave) { ep in
                        Text("1ª fase (dry-run): \(ep.clave)").tag(ep.clave)
                    }
                }.labelsHidden().frame(width: 300)
                    .help("El endpoint que el servidor trata como PREVIEW: se llama, ves su respuesta y solo tras tu OK se confirma. Cualquier OTRA escritura se confirma localmente antes de enviar.")
            }
            HStack {
                Text("Confirmación:").font(.caption).frame(width: 90, alignment: .leading)
                Picker("", selection: conex.confirmEndpointId) {
                    Text("Sin 2ª fase (confirma y envía el mismo endpoint)").tag("")
                    ForEach((b.wrappedValue.conexion?.endpoints ?? []).filter { !$0.clave.isEmpty }, id: \.clave) { ep in
                        Text("2ª fase: \(ep.clave)").tag(ep.clave)
                    }
                }.labelsHidden().frame(width: 300)
            }
            Text("En ruta y query, {texto} es lo que dictes; las demás {variables} las llena la IA. Escritura (o método ≠ GET) SIEMPRE pide tu visto bueno: función = sí, equis o silencio = no. Si eliges un endpoint de 2ª fase, el de escritura actúa como propuesta (su respuesta se muestra para el OK y sus campos quedan como {variables}, ej. {previewId}).")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Probar conexión") {
                    avisoConexion = "Probando…"
                    ConexionesRunner.probar(b.wrappedValue.conexion ?? ConexionAPI(),
                                            modoId: modoId) { ok, msg in
                        avisoConexion = (ok ? "✓ " : "⚠️ ") + String(msg.prefix(300))
                    }
                }.controlSize(.small)
                .disabled(!ConexionesMotor.urlSegura(b.wrappedValue.conexion?.baseURL ?? ""))
                Toggle("Leer resumen por voz", isOn: conex.vozResumen)
                    .toggleStyle(.switch).controlSize(.mini)
                Toggle("La IA arma el plan", isOn: conex.usarIA)
                    .toggleStyle(.switch).controlSize(.mini)
                    .help("Encendido: la IA de este modo elige el endpoint y llena sus variables desde lo dictado (usa el Prompt de abajo como instrucciones). Apagado: se usa la clave dictada o el primer GET, con {texto} solamente.")
            }
            // Explicación de la PROPUESTA del visto bueno (opcional, con IA).
            Toggle("La IA explica la propuesta antes de confirmar", isOn: conex.propuestaConIA)
                .toggleStyle(.switch).controlSize(.mini)
                .help("Encendido: el modal (y la voz) explican en lenguaje natural qué se va a enviar, leyendo exactamente la propuesta del servidor sin inventar. Los datos exactos se muestran siempre debajo. Apagado: solo el formato legible línea por línea.")
            if b.wrappedValue.conexion?.propuestaConIA == true {
                TextEditor(text: conex.promptPropuesta)
                    .font(.callout).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
                Text("Instrucciones de esa explicación (opcional). Ej.: «di cuántas actividades, estado, minutos y con quién».")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            // PROMPT DE VUELTA: cómo contarte el resultado (vacío = crudo).
            Text("Respuesta (prompt de vuelta) — cómo contarte el resultado:").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: conex.promptRespuesta)
                .font(.callout).frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.3)))
            Text("Ej.: «Dime la ciudad, los grados y un consejo de abrigo según el frío». La IA redacta la respuesta con los datos reales de la API; vacío = se muestra la respuesta cruda.")
                .font(.caption2).foregroundStyle(.secondary)
            if !avisoConexion.isEmpty {
                Text(avisoConexion).font(.caption)
                    .foregroundStyle(avisoConexion.hasPrefix("✓") ? Color.green : Color.secondary)
                    .textSelection(.enabled)
            }
            if !Config.agenteHerramientaConexiones() {
                Text("⚠️ Las conexiones API están APAGADAS. Enciéndelas en Ajustes → Asistente → Conexiones API para que este modo funcione.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func seccionVariables(_ ep: Binding<EndpointAPI>) -> some View {
        HStack(spacing: 6) {
            Text("Variables:").font(.caption2).frame(width: 45, alignment: .leading)
            Button {
                ep.wrappedValue.variables.append(VariableAPI(nombre: "var\(ep.wrappedValue.variables.count + 1)"))
            } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.plain).controlSize(.small)
            Text("({texto} viene gratis)").font(.caption2).foregroundStyle(.secondary)
        }
        ForEach(ep.variables) { $v in
            HStack(spacing: 6) {
                TextField("nombre", text: $v.nombre)
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                Picker("", selection: $v.tipo) {
                    Text("texto").tag("texto"); Text("número").tag("numero")
                    Text("fecha").tag("fecha"); Text("lista").tag("lista")
                }.labelsHidden().frame(width: 90)
                Toggle("req.", isOn: $v.requerida).toggleStyle(.switch).controlSize(.mini)
                TextField("descripción para la IA", text: $v.descripcion)
                    .textFieldStyle(.roundedBorder).frame(width: 160)
                Button {
                    ep.wrappedValue.variables.removeAll { $0.id == v.id }
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.leading, 50)
        }
    }
}
