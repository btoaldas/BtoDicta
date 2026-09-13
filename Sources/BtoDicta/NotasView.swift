import AppKit
import SwiftUI

// MARK: - Tareas y notas locales con calendario/avisos

private let acentoNo = Color(red: 0.36, green: 0.28, blue: 0.62)

struct NotasView: View {
    @State private var items: [Pendiente] = NotasStore.todos()
    @State private var nuevo = ""
    @State private var tipoNuevo = "tarea"
    @State private var programarNuevo = false
    @State private var fechaNueva = Self.mananaNueve()
    @State private var diaCalendario = Date()
    @State private var editorCalendario = false
    @State private var textoCalendario = ""
    @State private var tipoCalendario = "tarea"
    @State private var horaCalendario = Self.hoy(minutos: 9 * 60)
    @State private var permisoNotificaciones: TareasRecordatorios.EstadoNotificaciones = .desconocido
    @State private var avisosExpandidos = true
    @State private var calendarioExpandido = true

    @State private var avisos = Config.tareasAvisos()
    @State private var sonido = Config.tareasAvisosSonido()
    @State private var voz = Config.tareasAvisosVoz()
    @State private var avisarNotas = Config.tareasAvisarNotas()
    @State private var resumenManana = Config.tareasResumenManana()
    @State private var resumenTarde = Config.tareasResumenTarde()
    @State private var incluirSinFecha = Config.tareasResumenIncluirSinFecha()
    @State private var resumenIA = Config.tareasResumenIA()
    @State private var horaManana = Self.hoy(minutos: Config.tareasResumenMananaMinutos())
    @State private var horaTarde = Self.hoy(minutos: Config.tareasResumenTardeMinutos())
    @State private var recordatorioPeriodico = Config.tareasResumenPeriodico()
    @State private var periodicoHoras = Config.tareasResumenPeriodicoHoras()
    @State private var periodicoVoz = Config.tareasResumenPeriodicoVoz()
    @State private var quietasActivo = Config.tareasQuietasActivo()
    @State private var horaQuietaDesde = Self.hoy(minutos: Config.tareasQuietasDesde())
    @State private var horaQuietaHasta = Self.hoy(minutos: Config.tareasQuietasHasta())

    private static func hoy(minutos: Int) -> Date {
        Calendar.current.date(bySettingHour: minutos / 60, minute: minutos % 60,
                              second: 0, of: Date()) ?? Date()
    }
    private static func mananaNueve() -> Date {
        let m = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: m) ?? m
    }
    private static func minutos(_ fecha: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: fecha)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func recargar() {
        items = NotasStore.todos()
        TareasRecordatorios.consultarPermiso { permisoNotificaciones = $0 }
    }

    private func agregar(tipo: String, texto: String, fecha: Date?) {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        NotasStore.agregar(tipo: tipo, texto: t, fechaObjetivo: fecha,
                           avisar: fecha == nil ? nil : true)
        nuevo = ""; textoCalendario = ""; recargar()
        TareasRecordatorios.shared.solicitarPermisoSiHaceFalta()
    }

    private func fechaCalendarioElegida() -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: diaCalendario)
        let h = cal.dateComponents([.hour, .minute], from: horaCalendario)
        var c = DateComponents(); c.year = d.year; c.month = d.month; c.day = d.day
        c.hour = h.hour; c.minute = h.minute
        return cal.date(from: c) ?? diaCalendario
    }

    private func guardarConfiguracion() {
        Config.set("tareas_avisos", to: avisos)
        Config.set("tareas_avisos_sonido", to: sonido)
        Config.set("tareas_avisos_voz", to: voz)
        Config.set("tareas_avisar_notas", to: avisarNotas)
        Config.set("tareas_resumen_manana", to: resumenManana)
        Config.set("tareas_resumen_tarde", to: resumenTarde)
        Config.set("tareas_resumen_sin_fecha", to: incluirSinFecha)
        Config.set("tareas_resumen_ia", to: resumenIA)
        Config.set("tareas_resumen_manana_min", to: Self.minutos(horaManana))
        Config.set("tareas_resumen_tarde_min", to: Self.minutos(horaTarde))
        Config.set("tareas_resumen_periodico", to: recordatorioPeriodico)
        Config.set("tareas_resumen_periodico_horas", to: periodicoHoras)
        Config.set("tareas_resumen_periodico_voz", to: periodicoVoz)
        Config.set("tareas_quietas_activo", to: quietasActivo)
        Config.set("tareas_quietas_desde", to: Self.minutos(horaQuietaDesde))
        Config.set("tareas_quietas_hasta", to: Self.minutos(horaQuietaHasta))
        TareasRecordatorios.shared.solicitarPermisoSiHaceFalta()
        TareasRecordatorios.shared.revisarAhora()
        recargar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Tareas y notas", systemImage: "checklist")
                .font(.headline).foregroundStyle(acentoNo)
            Text("Se llenan solas al dictar con Tarea o Nota. Las fechas se detectan en frases como “mañana a las 8:00 p. m.”; todo queda local en tu Mac.")
                .font(.caption).foregroundStyle(.secondary)

            tablero

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("", selection: $tipoNuevo) {
                            Text("Tarea").tag("tarea"); Text("Nota").tag("nota")
                        }.labelsHidden().frame(width: 100)
                        TextField("Agregar a mano…", text: $nuevo).textFieldStyle(.roundedBorder)
                        Button("Agregar") {
                            agregar(tipo: tipoNuevo, texto: nuevo,
                                    fecha: programarNuevo ? fechaNueva : nil)
                        }.disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Toggle("Programar fecha y hora", isOn: $programarNuevo)
                            .toggleStyle(.checkbox)
                        if programarNuevo {
                            DatePicker("", selection: $fechaNueva,
                                       displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().controlSize(.small)
                        } else {
                            Text("También la detecto dentro del texto.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(4)
            }

            DisclosureGroup(isExpanded: $avisosExpandidos) {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Avisarme al llegar la fecha", isOn: $avisos)
                    HStack(spacing: 18) {
                        Toggle("Sonido", isOn: $sonido)
                        Toggle("También hablarlo", isOn: $voz)
                            .disabled(!Config.ttsActivo())
                        Toggle("También notas con fecha", isOn: $avisarNotas)
                    }.toggleStyle(.checkbox)
                    Text("Notificaciones de macOS: \(permisoNotificaciones.texto). La voz usa el motor TTS elegido en Ajustes y nunca habla durante una grabación de pantalla.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        Toggle("Resumen de la mañana", isOn: $resumenManana)
                        DatePicker("", selection: $horaManana, displayedComponents: .hourAndMinute)
                            .labelsHidden().controlSize(.small).disabled(!resumenManana)
                    }
                    HStack {
                        Toggle("Resumen de la tarde", isOn: $resumenTarde)
                        DatePicker("", selection: $horaTarde, displayedComponents: .hourAndMinute)
                            .labelsHidden().controlSize(.small).disabled(!resumenTarde)
                    }
                    Divider()
                    Toggle("Recordarme las tareas pendientes cada cierto tiempo", isOn: $recordatorioPeriodico)
                        .toggleStyle(.checkbox)
                    if recordatorioPeriodico {
                        HStack {
                            Text("Cada").font(.caption)
                            Picker("", selection: $periodicoHoras) {
                                Text("1 hora").tag(1); Text("2 horas").tag(2)
                                Text("3 horas").tag(3); Text("8 horas").tag(8)
                            }.labelsHidden().frame(width: 110)
                            Toggle("Leerlo en voz alta", isOn: $periodicoVoz).toggleStyle(.checkbox)
                        }
                        Text("Te resume solo lo que falta (con su hora); las tareas tachadas no aparecen.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Toggle("No molestar de noche (sin sonido ni voz)", isOn: $quietasActivo)
                            .toggleStyle(.checkbox)
                        if quietasActivo {
                            HStack {
                                Text("Desde").font(.caption)
                                DatePicker("", selection: $horaQuietaDesde, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                Text("hasta").font(.caption)
                                DatePicker("", selection: $horaQuietaHasta, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                        }
                    }
                    Divider()
                    Toggle("Incluir tareas sin fecha en los resúmenes", isOn: $incluirSinFecha)
                        .toggleStyle(.checkbox)
                    Toggle("Dar forma al resumen con IA (opcional)", isOn: $resumenIA)
                        .toggleStyle(.checkbox)
                    Text(resumenIA
                         ? "La IA solo reescribe el resumen ya calculado y puede recibir hasta tres títulos. Si no responde en 6 segundos, BtoDicta usa el resumen local."
                         : "El resumen es local y determinista: no gasta IA ni sale de tu Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Probar aviso ahora") {
                            TareasRecordatorios.shared.probarAviso { recargar() }
                        }
                        if !permisoNotificaciones.concedidas {
                            Button(permisoNotificaciones == .denegadas
                                   ? "Activar en Ajustes…" : "Activar notificaciones") {
                                TareasRecordatorios.solicitarPermiso { estado in
                                    permisoNotificaciones = estado
                                    if estado == .denegadas {
                                        _ = TareasRecordatorios.abrirAjustesNotificaciones()
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent).tint(acentoNo)
                            .help("Solicita a macOS permiso para mostrar avisos de tareas y resúmenes.")
                        }
                        Button {
                            _ = TareasRecordatorios.abrirAjustesNotificaciones()
                        } label: {
                            Label("Permisos de BtoDicta…", systemImage: "gear")
                        }
                        .buttonStyle(.link)
                        .help("Abre directamente Notificaciones en Ajustes del Sistema para revisar el permiso de BtoDicta.")
                    }.controlSize(.small)
                    Text("Si la Mac estaba apagada o dormida, el resumen vigente y los avisos vencidos se recuperan al volver a abrir o activar BtoDicta.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .onChange(of: avisos) { _, _ in guardarConfiguracion() }
                .onChange(of: sonido) { _, _ in guardarConfiguracion() }
                .onChange(of: voz) { _, _ in guardarConfiguracion() }
                .onChange(of: avisarNotas) { _, _ in guardarConfiguracion() }
                .onChange(of: resumenManana) { _, _ in guardarConfiguracion() }
                .onChange(of: resumenTarde) { _, _ in guardarConfiguracion() }
                .onChange(of: incluirSinFecha) { _, _ in guardarConfiguracion() }
                .onChange(of: resumenIA) { _, _ in guardarConfiguracion() }
                .onChange(of: horaManana) { _, _ in guardarConfiguracion() }
                .onChange(of: horaTarde) { _, _ in guardarConfiguracion() }
                .onChange(of: recordatorioPeriodico) { _, _ in guardarConfiguracion() }
                .onChange(of: periodicoHoras) { _, _ in guardarConfiguracion() }
                .onChange(of: periodicoVoz) { _, _ in guardarConfiguracion() }
                .onChange(of: quietasActivo) { _, _ in guardarConfiguracion() }
                .onChange(of: horaQuietaDesde) { _, _ in guardarConfiguracion() }
                .onChange(of: horaQuietaHasta) { _, _ in guardarConfiguracion() }
            } label: {
                Label("Avisos y resúmenes", systemImage: "bell.badge")
                    .font(.subheadline).bold().foregroundStyle(acentoNo)
            }

            DisclosureGroup(isExpanded: $calendarioExpandido) {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("", selection: $diaCalendario, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().frame(maxWidth: 390)
                    let delDia = items.filter {
                        guard let e = $0.fechaObjetivo else { return false }
                        return Calendar.current.isDate(Date(timeIntervalSince1970: e),
                                                       inSameDayAs: diaCalendario)
                    }.sorted { ($0.fechaObjetivo ?? 0) < ($1.fechaObjetivo ?? 0) }
                    if delDia.isEmpty {
                        Text("No hay tareas ni notas programadas ese día.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(delDia) { p in
                            HStack {
                                Label(p.texto, systemImage: p.tipo == "tarea"
                                      ? (p.hecho ? "checkmark.circle.fill" : "checkmark.circle")
                                      : "note.text")
                                Spacer()
                                if let e = p.fechaObjetivo {
                                    Text(Date(timeIntervalSince1970: e)
                                        .formatted(date: .omitted, time: .shortened))
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                            }.font(.caption)
                        }
                    }
                    Button("Agregar en este día…") { editorCalendario = true }
                }.padding(.top, 8)
            } label: {
                Label("Calendario local", systemImage: "calendar")
                    .font(.subheadline).bold().foregroundStyle(acentoNo)
            }

            listaTareas
            Divider()
            listaNotas
        }
        .onAppear(perform: recargar)
        .onReceive(NotificationCenter.default.publisher(for: .betoPendientesChanged)) { _ in recargar() }
        .sheet(isPresented: $editorCalendario) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Nuevo pendiente").font(.headline)
                Picker("Tipo", selection: $tipoCalendario) {
                    Text("Tarea").tag("tarea"); Text("Nota").tag("nota")
                }.pickerStyle(.segmented)
                TextField("¿Qué quieres recordar?", text: $textoCalendario)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Hora", selection: $horaCalendario, displayedComponents: .hourAndMinute)
                HStack {
                    Spacer(); Button("Cancelar") { editorCalendario = false }
                    Button("Agregar") {
                        agregar(tipo: tipoCalendario, texto: textoCalendario,
                                fecha: fechaCalendarioElegida())
                        editorCalendario = false
                    }.keyboardShortcut(.defaultAction)
                        .disabled(textoCalendario.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.padding(22).frame(width: 420)
        }
    }

    @ViewBuilder private var tablero: some View {
        let c = TareasRecordatorios.conteos(items: items)
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    indicador("Vencidas", c.vencidas, color: c.vencidas > 0 ? .red : .secondary)
                    indicador("Hoy", c.hoy, color: acentoNo)
                    indicador("Mañana", c.manana, color: .blue)
                    indicador("Sin fecha", c.sinFecha, color: .secondary)
                }
                if let siguiente = TareasRecordatorios.siguiente(items: items),
                   let e = siguiente.fechaObjetivo {
                    Label("Siguiente: \(siguiente.texto) · \(Date(timeIntervalSince1970: e).formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "clock")
                        .font(.caption).lineLimit(2)
                } else if c.total == 0 {
                    Label("Todo al día", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }.padding(3)
        }
    }

    private func indicador(_ titulo: String, _ valor: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(valor)").font(.title3).bold().monospacedDigit().foregroundStyle(color)
            Text(titulo).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 5)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(titulo): \(valor)")
    }

    @ViewBuilder private var listaTareas: some View {
        let tareas = items.filter { $0.tipo == "tarea" }
        HStack {
            Text("Tareas (\(tareas.count))").font(.subheadline).bold()
            Spacer()
            if tareas.contains(where: { $0.hecho }) {
                Button("Limpiar hechas") { NotasStore.limpiarHechas(); recargar() }.controlSize(.small)
            }
            Button { recargar() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refrescar")
        }
        if tareas.isEmpty { Text("Sin tareas.").font(.caption).foregroundStyle(.tertiary) }
        ForEach(tareas) { tarea in fila(tarea, permiteHecho: true) }
    }

    @ViewBuilder private var listaNotas: some View {
        let notas = items.filter { $0.tipo == "nota" }
        Text("Notas (\(notas.count))").font(.subheadline).bold()
        if notas.isEmpty { Text("Sin notas.").font(.caption).foregroundStyle(.tertiary) }
        ForEach(notas) { nota in fila(nota, permiteHecho: false) }
    }

    @ViewBuilder private func fila(_ p: Pendiente, permiteHecho: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if permiteHecho {
                Button { NotasStore.alternar(p.id) } label: {
                    Image(systemName: p.hecho ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(p.hecho ? .green : .secondary)
                }.buttonStyle(.plain)
                    .help(p.hecho ? "Marcar esta tarea como pendiente" : "Marcar esta tarea como completada")
            } else { Image(systemName: "note.text").foregroundStyle(acentoNo) }
            VStack(alignment: .leading, spacing: 4) {
                Text(p.texto).font(.callout).strikethrough(p.hecho)
                    .foregroundStyle(p.hecho ? .secondary : .primary)
                    .textSelection(.enabled)
                if let e = p.fechaObjetivo {
                    let f = Date(timeIntervalSince1970: e)
                    HStack(spacing: 6) {
                        DatePicker("", selection: Binding(
                            get: { f },
                            set: { NotasStore.programar(p.id, fecha: $0, avisar: true) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().controlSize(.small)
                        Button { NotasStore.programar(p.id, fecha: f, avisar: !p.avisar) } label: {
                            Image(systemName: p.avisar ? "bell.fill" : "bell.slash")
                        }.buttonStyle(.plain).help(p.avisar ? "No avisar" : "Avisarme")
                        Button { NotasStore.programar(p.id, fecha: nil, avisar: false) } label: {
                            Image(systemName: "calendar.badge.minus")
                        }.buttonStyle(.plain).help("Quitar fecha")
                    }.foregroundStyle(f < Date() && !p.hecho ? .red : .secondary)
                } else {
                    Button("Programar…") {
                        NotasStore.programar(p.id, fecha: Self.mananaNueve(), avisar: true)
                    }.buttonStyle(.link).controlSize(.small)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { NotasStore.borrar(p.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Eliminar esta tarea o nota local")
        }
    }
}
