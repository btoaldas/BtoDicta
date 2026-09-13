import AppKit
import SwiftUI

// MARK: - Editor de IAs personalizadas (gateways propios)
//
// Base URL + API key + esquema de auth (Bearer / X-API-Key / encabezado
// propio) + encabezados extra + modelo (manual o descubierto) + para qué
// sirve (pulir / reconocer voz). Prueba de conexión y descubrimiento.

private let acentoIA = Color(red: 0.36, green: 0.28, blue: 0.62)

final class IAPersonalizadasStore: ObservableObject {
    @Published var items: [IAPersonalizada] = PersonalizadaStore.cargar()
    func guardar() { PersonalizadaStore.guardar(items) }
    func add() { items.append(IAPersonalizada(nombre: "Mi gateway")); guardar() }
    /// Agrega una plantilla PRECONFIGURADA (id fresco) — el usuario solo termina
    /// de llenar (ej. Cloudflare: reemplazar el account-id y poner la key).
    func addPlantilla(_ tpl: IAPersonalizada) {
        var p = tpl; p.id = UUID().uuidString
        items.append(p); guardar()
    }
    func remove(_ id: String) { items.removeAll { $0.id == id }; guardar() }

    /// Plantillas de gateways que necesitan un dato del usuario en la URL base.
    static let plantillas: [(nombre: String, tpl: IAPersonalizada, ayuda: String)] = [
        ("Cloudflare Workers AI",
         IAPersonalizada(nombre: "Cloudflare Workers AI",
                         base: "https://api.cloudflare.com/client/v4/accounts/TU-ACCOUNT-ID/ai/v1",
                         modelo: "@cf/meta/llama-3.3-70b-instruct-fp8-fast"),
         "Reemplaza TU-ACCOUNT-ID en la URL base por tu Account ID de Cloudflare y pon tu API token. 10.000 llamadas/día gratis."),
    ]
}

struct IAPersonalizadaEditor: View {
    @StateObject private var store = IAPersonalizadasStore()
    @State private var seleccion: String?
    @State private var descubriendo = false
    @State private var msgDescubrir: String?
    @State private var rutaManual = ""
    @State private var estadoPrueba: String?
    @State private var probando = false
    @State private var nuevoHeaderN = ""
    @State private var nuevoHeaderV = ""

    private var idx: Int? { store.items.firstIndex { $0.id == seleccion } }

    var body: some View {
        HStack(spacing: 0) {
            // Lista
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("IAs personalizadas").font(.headline)
                    Spacer()
                    Menu {
                        Button("Gateway en blanco") { store.add(); seleccion = store.items.last?.id }
                        Divider()
                        Text("Plantillas (solo termina de llenar)")
                        ForEach(IAPersonalizadasStore.plantillas, id: \.nombre) { pl in
                            Button(pl.nombre) { store.addPlantilla(pl.tpl); seleccion = store.items.last?.id }
                        }
                    } label: { Image(systemName: "plus") }
                }
                List(selection: $seleccion) {
                    ForEach(store.items) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.nombre.isEmpty ? "(sin nombre)" : p.nombre).font(.subheadline)
                                Text(p.modelo.isEmpty ? "sin modelo" : p.modelo).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.paraPulido { Text("pulir").font(.system(size: 8)).padding(.horizontal, 4).background(acentoIA.opacity(0.3)).clipShape(Capsule()) }
                            if p.paraVoz { Text("voz").font(.system(size: 8)).padding(.horizontal, 4).background(.green.opacity(0.3)).clipShape(Capsule()) }
                        }.tag(p.id)
                    }
                }.frame(width: 220)
            }.padding(12)
            Divider()
            // Detalle
            if let i = idx {
                formulario(i).padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                VStack { Spacer(); Text("Elige o crea un gateway →").foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 700, height: 560)
    }

    @ViewBuilder private func formulario(_ i: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                campo("Nombre") { TextField("Mi gateway", text: $store.items[i].nombre, onCommit: store.guardar).textFieldStyle(.roundedBorder) }
                campo("URL base") { TextField("https://gateway.tuempresa.com/v1", text: $store.items[i].base, onCommit: store.guardar).textFieldStyle(.roundedBorder) }
                if store.items[i].base.contains("TU-ACCOUNT-ID") {
                    Text("⚠️ Reemplaza TU-ACCOUNT-ID en la URL por tu Account ID de Cloudflare (Dashboard → Workers AI) y pon tu API token abajo. 10.000 llamadas/día gratis.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                campo("API key") { SecureField("clave del gateway", text: $store.items[i].apiKey, onCommit: store.guardar).textFieldStyle(.roundedBorder) }
                // Esquema de auth
                campo("Autenticación") {
                    Picker("", selection: Binding(
                        get: { esquemaActual(store.items[i]) },
                        set: { aplicarEsquema($0, a: i) })) {
                        Text("Bearer (Authorization)").tag("bearer")
                        Text("X-API-Key").tag("xapikey")
                        Text("Encabezado propio").tag("custom")
                    }.labelsHidden().frame(width: 220)
                }
                if esquemaActual(store.items[i]) == "custom" {
                    campo("Nombre del encabezado") { TextField("X-Mi-Auth", text: $store.items[i].authHeader, onCommit: store.guardar).textFieldStyle(.roundedBorder).frame(width: 220) }
                    campo("Prefijo (opcional)") { TextField("ej: Bearer ", text: $store.items[i].authPrefix, onCommit: store.guardar).textFieldStyle(.roundedBorder).frame(width: 120) }
                }
                // Encabezados extra
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encabezados extra").font(.subheadline).bold()
                    ForEach(Array(store.items[i].headers.keys.sorted()), id: \.self) { k in
                        HStack {
                            Text(k).font(.caption).frame(width: 140, alignment: .leading)
                            Text(store.items[i].headers[k] ?? "").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.items[i].headers[k] = nil; store.guardar() } label: { Image(systemName: "minus.circle").foregroundStyle(.red) }
                                .buttonStyle(.borderless).help("Quitar este encabezado adicional")
                        }
                    }
                    HStack {
                        TextField("X-Nombre", text: $nuevoHeaderN).textFieldStyle(.roundedBorder).frame(width: 140)
                        TextField("valor", text: $nuevoHeaderV).textFieldStyle(.roundedBorder)
                        Button("Agregar") {
                            let n = nuevoHeaderN.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            store.items[i].headers[n] = nuevoHeaderV; nuevoHeaderN = ""; nuevoHeaderV = ""; store.guardar()
                        }.controlSize(.small)
                    }
                }
                Divider()
                // Modelo (manual o descubierto)
                campo("Modelo (ID)") { TextField("gpt-4o-mini · llama-3.3-70b · …", text: $store.items[i].modelo, onCommit: store.guardar).textFieldStyle(.roundedBorder) }
                HStack(spacing: 8) {
                    Button(descubriendo ? "Buscando…" : "Descubrir modelos") {
                        descubriendo = true; msgDescubrir = nil
                        PersonalizadaStore.descubrirModelos(store.items[i], rutaManual: rutaManual.isEmpty ? nil : rutaManual) { ids, msg in
                            descubriendo = false; msgDescubrir = msg
                            if !ids.isEmpty {
                                // Guarda TODO el catálogo; el usuario elige cualquiera
                                // luego, incluso desde Ajustes → Pulido (sin volver aquí).
                                store.items[i].modelos = ids
                                if store.items[i].modelo.isEmpty { store.items[i].modelo = ids[0] }
                                store.guardar()
                            }
                        }
                    }.controlSize(.small).disabled(descubriendo || store.items[i].base.isEmpty)
                    if let m = msgDescubrir {
                        Text(m).font(.caption).foregroundStyle(store.items[i].modelos.isEmpty ? .orange : .green)
                    }
                    if !store.items[i].modelos.isEmpty {
                        Menu("Elegir (\(store.items[i].modelos.count))") {
                            ForEach(store.items[i].modelos, id: \.self) { m in
                                Button(m) { store.items[i].modelo = m; store.guardar() }
                            }
                        }.frame(width: 150)
                    }
                }
                // Ruta manual del endpoint de modelos (opcional): se prueba
                // PRIMERO. Para gateways que sirven la lista en una ruta rara.
                campo("Ruta de modelos (opcional)") {
                    TextField("auto (prueba /models, /v1/models…) o ej: /v1/models", text: $rutaManual)
                        .textFieldStyle(.roundedBorder)
                }
                if !store.items[i].modelos.isEmpty {
                    Text("Se guardaron \(store.items[i].modelos.count) modelos. Puedes cambiar el activo aquí o en Ajustes → Pulido, cuando quieras.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                // Para qué sirve
                Toggle("Usar para PULIR / traducir el texto", isOn: $store.items[i].paraPulido).onChange(of: store.items[i].paraPulido) { _, _ in store.guardar() }
                Toggle("Usar para RECONOCER voz (transcripción)", isOn: $store.items[i].paraVoz)
                    .onChange(of: store.items[i].paraVoz) { _, _ in store.guardar() }
                if store.items[i].paraVoz {
                    Text("Aparecerá en la cascada de Modelos (apagado). El gateway debe exponer /audio/transcriptions estilo OpenAI. Actívalo y ordénalo ahí.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                // Probar / borrar
                HStack(spacing: 10) {
                    Button {
                        probando = true; estadoPrueba = nil
                        PersonalizadaStore.probar(store.items[i]) { ok, msg in
                            probando = false; estadoPrueba = ok ? "✅ Conecta (\(msg))" : "❌ \(msg)"
                        }
                    } label: { Label(probando ? "Probando…" : "Probar conexión", systemImage: "bolt.horizontal") }
                    if let e = estadoPrueba { Text(e).font(.caption).foregroundStyle(e.hasPrefix("✅") ? .green : .orange) }
                    Spacer()
                    Button(role: .destructive) { let id = store.items[i].id; seleccion = nil; store.remove(id) } label: { Label("Borrar", systemImage: "trash") }
                }
            }
        }
    }

    private func campo<V: View>(_ t: String, @ViewBuilder _ c: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).font(.subheadline).frame(width: 160, alignment: .leading)
            c()
        }
    }
    private func esquemaActual(_ p: IAPersonalizada) -> String {
        let h = p.authHeader.lowercased()
        if h == "authorization" { return "bearer" }
        if h == "x-api-key" { return "xapikey" }
        return "custom"
    }
    private func aplicarEsquema(_ e: String, a i: Int) {
        switch e {
        case "bearer":  store.items[i].authHeader = "Authorization"; store.items[i].authPrefix = "Bearer "
        case "xapikey": store.items[i].authHeader = "x-api-key";     store.items[i].authPrefix = ""
        default:        if esquemaActual(store.items[i]) != "custom" { store.items[i].authHeader = "X-Mi-Auth"; store.items[i].authPrefix = "" }
        }
        store.guardar()
    }
}

enum IAPersonalizadaWindow {
    private static var win: NSWindow?
    static func show() {
        if win == nil {
            let h = NSHostingController(rootView: IAPersonalizadaEditor())
            let w = NSWindow(contentViewController: h)
            w.title = "IAs personalizadas · BtoDicta"
            w.styleMask = [.titled, .closable]
            w.setContentSize(NSSize(width: 700, height: 560))
            w.isReleasedWhenClosed = false
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.center(); win?.makeKeyAndOrderFront(nil)
    }
}
