import SwiftUI

/// «Qué no debe mirar la bitácora» (spec 007, T09–T12).
///
/// Por qué existe esta pantalla
/// ---------------------------
/// Las listas que de verdad deciden si algo se graba **no tenían interfaz**: solo
/// se podían editar abriendo `config.json` a mano. El resultado medido fue el
/// esperado: de siete exclusiones pedidas se aplicaron cinco, y las dos que
/// faltaban eran aplicaciones de escritorio escritas en la lista de títulos,
/// donde no podían coincidir nunca. Nadie lo notó durante días, porque una regla
/// que no coincide no produce ningún error.
///
/// Tres cosas que esta pantalla hace a propósito
/// ---------------------------------------------
/// 1. **No escribe nada hasta Aceptar.** Todo lo de aquí vive en memoria hasta
///    que se pulsa el botón; cerrar sin aceptar deja la configuración intacta.
/// 2. **Dice qué apaga cada lista.** Hay tres sitios distintos donde se puede
///    escribir «youtube» con efectos distintos, y eso es una trampa. Cada uno
///    lleva su línea.
/// 3. **Se puede desplegar una categoría** y rescatar una entrada suelta, sin
///    renunciar al resto.
struct VistaExclusiones: View {

    @StateObject private var m = ModeloExclusiones()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            encabezado
            Divider()
            modo
            Divider()
            categorias
            Divider()
            aplicar
        }
    }

    // MARK: Encabezado — qué apaga cada lista

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("De fábrica la bitácora mira todo. Aquí se recorta de una vez, sin escribir dominios uno a uno.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Las tres listas, y qué apaga cada una. Sin esto, escribir «youtube»
            // en el sitio equivocado parece haber funcionado y no hace nada.
            VStack(alignment: .leading, spacing: 3) {
                Text("Hay tres listas distintas, y no hacen lo mismo:")
                    .font(.caption2).foregroundStyle(.secondary)
                etiqueta("Esta", "apaga el audio del sistema Y las capturas. Es la que de verdad decide si algo se graba.")
                etiqueta("«Pantalla» (más arriba)", "apaga solo la captura. El audio se sigue grabando.")
                etiqueta("La de la extensión del navegador", "impide que la dirección salga del navegador: BtoDicta no llega a recibirla.")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func etiqueta(_ cual: String, _ que: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("•").font(.caption2).foregroundStyle(.secondary)
            (Text(cual).font(.caption2).bold() + Text(" — " + que).font(.caption2))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Modo de trabajo

    private var modo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cómo quieres que se porte").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $m.modo) {
                Text("Mirar todo salvo lo que excluya").tag(FiltroBitacora.Modo.permisivo)
                Text("No mirar nada salvo lo que incluya").tag(FiltroBitacora.Modo.restrictivo)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if let aviso = m.avisoDeModo {
                // Un valor de fábrica peligroso es un fallo, y este lo sería: el
                // modo restrictivo con la lista de inclusión vacía no graba NADA,
                // y una bitácora que no registra se ve igual que un día tranquilo.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(aviso).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
            }
        }
    }

    // MARK: Categorías

    private var categorias: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Qué excluir").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(m.todasMarcadas ? "Desmarcar todas" : "Marcar todas") { m.alternarTodas() }
                    .buttonStyle(.link).font(.caption)
            }

            if m.categorias.isEmpty {
                Text("Esta copia de BtoDicta no trae el catálogo de propuestas. Puedes escribir las exclusiones a mano igual que siempre.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(m.categorias) { fila in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(isOn: m.enlaceCategoria(fila.id)) {
                            HStack(spacing: 6) {
                                Text(fila.nombre)
                                Text(fila.destino == .apps ? "aplicaciones" : "sitios")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                Text("\(m.marcadasDe(fila.id))/\(fila.entradas.count)")
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(m.desplegadas.contains(fila.id) ? "Ocultar" : "Ver cuáles") {
                            m.alternarDespliegue(fila.id)
                        }
                        .buttonStyle(.link).font(.caption)
                    }

                    if !fila.descripcion.isEmpty {
                        Text(fila.descripcion).font(.caption2).foregroundStyle(.secondary)
                            .padding(.leading, 20).fixedSize(horizontal: false, vertical: true)
                    }

                    if m.desplegadas.contains(fila.id) {
                        // Rescatar una entrada suelta sin renunciar a la categoría
                        // entera. Sin esto, «redes sociales» sería todo o nada.
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(fila.entradas, id: \.self) { e in
                                Toggle(e, isOn: m.enlaceEntrada(fila.id, e))
                                    .font(.caption).toggleStyle(.checkbox)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    // MARK: Aplicar

    private var aplicar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Aplicar") { m.aplicar() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!m.hayCambios)
                if m.hayCambios {
                    Text(m.resumenDeCambios).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Nada que aplicar todavía.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let hecho = m.ultimoResultado {
                    Text(hecho).font(.caption).foregroundStyle(.green)
                }
            }
            Text("Hasta que pulses Aplicar no se cambia nada de tu configuración.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
