import SwiftUI

// MARK: - Panel de salud
//
// Todo lo que se enseña aquí YA se medía; lo único que faltaba era poder verlo
// sin abrir el registro y saber qué buscar. Un día de trabajo normal obligó a
// leerlo cinco veces para responder «¿por qué va lento?» o «¿está caído?».
//
// El saldo es lo único nuevo: tres proveedores lo publican, y enterarse de que
// se acabó a mitad de un dictado es lo peor que puede pasar.
struct SaludView: View {
    @State private var saldos: [SaldoAPI.Saldo] = SaldoAPI.cacheados()
    @State private var consultando = false
    @State private var cuarentenaSTT: [(id: String, codigo: Int, causa: String, quedan: Int)] = []
    @State private var cuarentenaPulido: [(proveedor: String, quedan: Int)] = []
    @State private var techos: [(motor: String, cabe: Int, rechaza: Int)] = []
    @State private var colaAudio = 0
    @State private var colaPantalla = 0
    @State private var vidas: [SaldoAPI.Vida] = SaldoAPI.vidasCacheadas()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                encabezado
                saldosSeccion
                Divider()
                gastoSeccion
                Divider()
                latenciaSeccion
                Divider()
                vidaSeccion
                Divider()
                cuarentenasSeccion
                Divider()
                techosSeccion
                Divider()
                colaSeccion
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { refrescar() }
    }

    // MARK: Piezas

    /// Lo que tarda cada motor, medido.
    ///
    /// El orden de la cascada estaba puesto a mano. Esto no lo cambia solo —esa
    /// decisión es de quien la usa, y la velocidad no es lo único que importa:
    /// también están el coste y la privacidad— pero pone los números delante.
    private var latenciaSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cuánto tarda cada motor").font(.headline)
            let medidas = LatenciaMotores.resumen()
            if medidas.isEmpty {
                Text("Aún no hay medidas. Se toman solas al ir usando los motores.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(medidas, id: \.motor) { m in
                    HStack {
                        Text(m.motor)
                        Spacer()
                        Text("\(m.ms) ms").monospacedDigit()
                            .foregroundStyle(m.ms < 2000 ? .primary : .secondary)
                        Text("(\(m.medidas))").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Es la MEDIANA de las últimas medidas, no la media: un cuelgue aislado arrastra la media de cien llamadas buenas, y aquí interesa lo que tarda normalmente. Entre paréntesis, cuántas medidas hay detrás.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Lo que cuesta cada motor, mes a mes.
    ///
    /// El saldo dice cuánto QUEDA; esto dice en qué se ha ido. Son preguntas
    /// distintas, y la segunda es la que permite decidir si un motor vale lo que
    /// cobra. Estaba calculado desde hace tiempo, pero solo se veía recortado a
    /// tres líneas en el menú de la barra.
    private var gastoSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("En qué se va el dinero").font(.headline)
            let meses = UsageLog.gastoPorMes(ultimos: 6)
            if meses.isEmpty {
                Text("Todavía no hay uso registrado.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(meses) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(m.mes).bold().monospacedDigit()
                            Spacer()
                            Text(String(format: "%.1f h", m.horas)).monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(m.dolares < 0.01 ? "—" : String(format: "$%.2f", m.dolares))
                                .monospacedDigit()
                        }
                        ForEach(m.porMotor.prefix(6), id: \.0) { motor, horas, dolares in
                            HStack {
                                Text("· \(motor)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f h", horas)).font(.caption)
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Text(dolares < 0.01 ? "—" : String(format: "$%.2f", dolares))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("El coste sale de las horas usadas por la tarifa de cada modelo, no de la factura del proveedor: sirve para comparar motores entre sí, no para cuadrar con el banco. Los motores locales y los de capa gratuita aparecen sin importe.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var encabezado: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Salud").font(.title2).bold()
                Text("El estado real, sin abrir el registro.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                consultando = true
                SaldoAPI.consultar(forzar: true) { s in
                    saldos = s
                    SaldoAPI.probarTodo { v in
                        vidas = v; consultando = false; refrescarLocal()
                    }
                }
            } label: {
                consultando ? AnyView(ProgressView().scaleEffect(0.6))
                            : AnyView(Label("Actualizar", systemImage: "arrow.clockwise"))
            }
            .disabled(consultando)
        }
    }

    private var saldosSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saldo de las API").font(.headline)
            if saldos.isEmpty {
                Text(consultando ? "Consultando a cada proveedor…"
                                 : "Aún no se ha consultado. Pulsa Actualizar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(saldos) { s in
                HStack(alignment: .firstTextBaseline) {
                    Circle().fill(color(s)).frame(width: 8, height: 8)
                    Text(s.nombre).frame(width: 110, alignment: .leading)
                    Text(s.texto).foregroundStyle(s.error == nil ? .primary : .secondary)
                    Spacer()
                    if let f = s.fraccion {
                        Text("\(Int(f * 100)) %").monospacedDigit().foregroundStyle(color(s))
                    }
                }
                .font(.callout)
            }
            Text("Los que no publican saldo aparecen abajo con su prueba de vida. No se inventa una estimación: no cuadraría con la factura.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Se avisa al bajar del \(Int(Config.saldoAvisoFraccion() * 100)) % "
                 + "o de \(Int(Config.saldoAvisoMinimoUSD())) USD, una vez al día por proveedor.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func color(_ s: SaldoAPI.Saldo) -> Color {
        if s.error != nil { return .gray }
        if s.restante <= 0 { return .red }
        return SaldoAPI.estaBajo(s) ? .orange : .green
    }

    /// Todos los proveedores con clave puesta, agrupados por para qué sirven.
    /// La pregunta que uno se hace de verdad no es «cuánto saldo me queda» sino
    /// «¿está caído?», y esa tiene respuesta para TODOS.
    private var vidaSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proveedores configurados").font(.headline)
            if vidas.isEmpty {
                Text(consultando ? "Probando uno por uno…" : "Pulsa Actualizar para probarlos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(["IA", "Dictado", "Voz"], id: \.self) { fam in
                let grupo = vidas.filter { $0.familia == fam }
                if !grupo.isEmpty {
                    Text(fam == "IA" ? "Inteligencia artificial (pulido, modos, agente)"
                         : fam == "Dictado" ? "Transcripción" : "Voz")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(grupo) { v in
                        HStack {
                            Circle().fill(v.vivo == true ? Color.green : (v.vivo == false ? .red : .gray))
                                .frame(width: 8, height: 8)
                            Text(v.nombre).frame(width: 150, alignment: .leading)
                            Text(v.detalle).foregroundStyle(.secondary)
                            Spacer()
                            if let s = saldos.first(where: { $0.id == v.id }), s.error == nil {
                                Text(s.texto).monospacedDigit().foregroundStyle(color(s))
                            }
                        }.font(.callout)
                    }
                }
            }
        }
    }

    private var cuarentenasSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proveedores apartados ahora mismo").font(.headline)
            if cuarentenaSTT.isEmpty && cuarentenaPulido.isEmpty {
                Text("Ninguno: toda la cascada está disponible.")
                    .font(.caption).foregroundStyle(.green)
            }
            ForEach(cuarentenaSTT, id: \.id) { c in
                HStack {
                    Text("dictado").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(3)
                    Text(c.id).frame(width: 110, alignment: .leading)
                    Text("HTTP \(c.codigo) · \(c.causa)").foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(reloj(c.quedan)).monospacedDigit().foregroundStyle(.orange)
                }.font(.callout)
            }
            ForEach(cuarentenaPulido, id: \.proveedor) { c in
                HStack {
                    Text("pulido").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15)).cornerRadius(3)
                    Text(c.proveedor).frame(width: 110, alignment: .leading)
                    Spacer()
                    Text(reloj(c.quedan)).monospacedDigit().foregroundStyle(.orange)
                }.font(.callout)
            }
        }
    }

    private var techosSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Techos de tamaño aprendidos").font(.headline)
            if techos.isEmpty {
                Text("Ninguno todavía: no se ha chocado con el límite de ningún motor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(techos, id: \.motor) { t in
                // Un techo de AUDIO se mide en megabytes y minutos; uno de
                // CONTEXTO de una IA, en caracteres. Mezclarlos daba filas sin
                // sentido («ia:groq admite 0 MB») que parecían un error.
                let esTexto = t.motor.hasPrefix("ia:")
                HStack {
                    Text(esTexto ? String(t.motor.dropFirst(3)) : t.motor)
                        .frame(width: 110, alignment: .leading)
                    if esTexto {
                        Text("pulido: admite \(t.cabe.formatted()) · cortó en \(t.rechaza.formatted()) caracteres")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("dictado: admite \(t.cabe / 1_048_576) MB · rechazó \(t.rechaza / 1_048_576) MB")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !esTexto {
                        Text("≈ \(t.cabe / RedSeguridadDictado.bytesPorSegundo / 60) min por envío")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }.font(.callout)
            }
            Text("Se descubren al chocar con ellos, se olvidan si se contradicen y caducan a las dos semanas.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var colaSeccion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cola de la bitácora").font(.headline)
            HStack {
                Text("audio por transcribir").frame(width: 190, alignment: .leading)
                Text("\(colaAudio)").monospacedDigit()
                    .foregroundStyle(colaAudio > 500 ? .orange : .primary)
                Spacer()
            }.font(.callout)
            HStack {
                Text("pantallas por leer").frame(width: 190, alignment: .leading)
                Text("\(colaPantalla)").monospacedDigit()
                    .foregroundStyle(colaPantalla > 500 ? .orange : .primary)
                Spacer()
            }.font(.callout)
            if colaAudio > 500 || colaPantalla > 500 {
                Text("La cola está alta. Suele pasar tras varios días con el equipo a batería: la bitácora pospone las tandas para no gastarla.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func reloj(_ segundos: Int) -> String {
        segundos >= 60 ? "\(segundos / 60) min" : "\(segundos) s"
    }

    private func refrescar() {
        refrescarLocal()
        if saldos.isEmpty || vidas.isEmpty {
            consultando = true
            SaldoAPI.consultar { s in
                saldos = s
                SaldoAPI.probarTodo { v in vidas = v; consultando = false }
            }
        }
    }

    private func refrescarLocal() {
        ContinuoIndice.shared.abrir()   // inocuo si ya está abierto
        cuarentenaSTT = CuarentenaSTT.listado()
        cuarentenaPulido = CuarentenaPulido.compartida.listado()
        techos = Troceo.aprendidos()
        colaAudio = ContinuoIndice.shared.pendientes(material: .audio, limite: 5_000).count
        colaPantalla = ContinuoIndice.shared.pendientes(material: .pantalla, limite: 5_000).count
    }
}
