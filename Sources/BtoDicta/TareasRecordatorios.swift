import AppKit
import Foundation
import UserNotifications

/// Reloj local de Tareas y notas. No usa IA ni nube: detecta vencimientos,
/// recupera avisos al despertar/reabrir la Mac y ofrece dos resúmenes diarios.
final class TareasRecordatorios: NSObject, UNUserNotificationCenterDelegate {
    enum EstadoNotificaciones: Equatable {
        case permitidas
        case provisionales
        case denegadas
        case sinSolicitar
        case noDisponibles
        case desconocido

        var texto: String {
            switch self {
            case .permitidas: return "Permitidas"
            case .provisionales: return "Provisionales"
            case .denegadas: return "Denegadas en macOS"
            case .sinSolicitar: return "Sin solicitar todavía"
            case .noDisponibles: return "Disponibles en la app instalada"
            case .desconocido: return "Estado desconocido"
            }
        }

        var concedidas: Bool {
            self == .permitidas || self == .provisionales
        }
    }

    struct Aviso {
        let titulo: String
        let cuerpo: String
        let hablar: Bool
        let id: String
        var sonido: Bool = true   // false en horas quietas (notificación muda)
    }

    struct Conteos {
        let vencidas: Int
        let hoy: Int
        let manana: Int
        let proximas: Int
        let sinFecha: Int

        var total: Int { vencidas + hoy + manana + proximas + sinFecha }
    }

    static let shared = TareasRecordatorios()
    private let centro: UNUserNotificationCenter?
    private var timer: Timer?
    private var observadores: [(NotificationCenter, NSObjectProtocol)] = []
    private var presentar: ((Aviso) -> Void)?
    private var iniciada = false

    private override init() {
        // UserNotifications lanza una excepción Objective-C (no capturable en
        // Swift) si el ejecutable se abre suelto desde build/release. El reloj y
        // el notch sí funcionan allí; el centro del sistema solo existe en .app.
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app",
           Bundle.main.bundleIdentifier != nil {
            centro = UNUserNotificationCenter.current()
        } else { centro = nil }
        super.init()
    }

    func iniciar(presentar: @escaping (Aviso) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.iniciar(presentar: presentar) }
            return
        }
        self.presentar = presentar
        guard !iniciada else { revisarAhora(); return }
        iniciada = true
        centro?.delegate = self
        let centroLocal = NotificationCenter.default
        let cambios = centroLocal.addObserver(
            forName: .betoPendientesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.solicitarPermisoSiHaceFalta()
            self?.revisarAhora()
        }
        observadores.append((centroLocal, cambios))
        let activa = centroLocal.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.revisarAhora() }
        observadores.append((centroLocal, activa))
        let centroWorkspace = NSWorkspace.shared.notificationCenter
        let despierta = centroWorkspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.revisarAhora() }
        observadores.append((centroWorkspace, despierta))
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.revisarAhora()
        }
        RunLoop.main.add(t, forMode: .common); timer = t
        solicitarPermisoSiHaceFalta()
        // Deja terminar el arranque visual antes de mostrar un aviso recuperado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.revisarAhora() }
    }

    func detener() {
        timer?.invalidate(); timer = nil
        for (centro, token) in observadores { centro.removeObserver(token) }
        observadores.removeAll(); iniciada = false; presentar = nil
    }

    func solicitarPermisoSiHaceFalta() {
        let necesitaAvisos = Config.tareasAvisos() && NotasStore.todos().contains {
            $0.fechaObjetivo != nil && !$0.hecho && $0.avisar
                && ($0.tipo == "tarea" || Config.tareasAvisarNotas())
        }
        let necesita = necesitaAvisos
            || Config.tareasResumenManana() || Config.tareasResumenTarde()
            || Config.tareasResumenMediodia() || Config.tareasResumenPeriodico()
        guard necesita, let centro else { return }
        centro.getNotificationSettings { [weak self] ajustes in
            guard ajustes.authorizationStatus == .notDetermined else { return }
            self?.centro?.requestAuthorization(options: [.alert, .sound]) { permitido, error in
                if let error { Log.write("⚠️ avisos de tareas: \(error.localizedDescription)") }
                else { Log.write("avisos de tareas: permiso \(permitido ? "concedido" : "denegado")") }
            }
        }
    }

    static func consultarPermiso(completion: @escaping (EstadoNotificaciones) -> Void) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app",
              Bundle.main.bundleIdentifier != nil else {
            completion(.noDisponibles); return
        }
        UNUserNotificationCenter.current().getNotificationSettings { ajustes in
            let estado: EstadoNotificaciones
            switch ajustes.authorizationStatus {
            case .authorized: estado = .permitidas
            case .provisional, .ephemeral: estado = .provisionales
            case .denied: estado = .denegadas
            case .notDetermined: estado = .sinSolicitar
            @unknown default: estado = .desconocido
            }
            DispatchQueue.main.async { completion(estado) }
        }
    }

    static func estadoPermiso(completion: @escaping (String) -> Void) {
        consultarPermiso { completion($0.texto) }
    }

    /// Solicitud explícita para el asistente inicial y la pantalla de Tareas.
    /// No exige que ya exista una tarea: el clic del usuario aporta el contexto.
    static func solicitarPermiso(completion: @escaping (EstadoNotificaciones) -> Void) {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app",
              Bundle.main.bundleIdentifier != nil else {
            completion(.noDisponibles); return
        }
        let centro = UNUserNotificationCenter.current()
        centro.getNotificationSettings { ajustes in
            guard ajustes.authorizationStatus == .notDetermined else {
                consultarPermiso(completion: completion); return
            }
            centro.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error {
                    Log.write("⚠️ permiso de notificaciones: \(error.localizedDescription)")
                }
                consultarPermiso(completion: completion)
            }
        }
    }

    @discardableResult
    static func abrirAjustesNotificaciones() -> Bool {
        let id = Bundle.main.bundleIdentifier ?? "ec.bto.btodicta"
        let rutas = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]
        for ruta in rutas {
            if let url = URL(string: ruta), NSWorkspace.shared.open(url) { return true }
        }
        return false
    }

    func probarAviso(completion: (() -> Void)? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.probarAviso(completion: completion) }
            return
        }
        let emitir: (Bool) -> Void = { [weak self] sistemaPermitido in
            guard let self else { return }
            self.publicar(.init(titulo: "Prueba de Tareas y notas",
                                cuerpo: sistemaPermitido
                                    ? "Este es el aviso de prueba de BtoDicta."
                                    : "El notch funciona, pero macOS tiene las notificaciones desactivadas. Ábrelas en Ajustes.",
                                hablar: Config.tareasAvisosVoz(),
                                id: "prueba.\(Int(Date().timeIntervalSince1970))"))
            completion?()
        }
        guard let centro else { emitir(false); return }
        centro.getNotificationSettings { ajustes in
            if ajustes.authorizationStatus == .notDetermined {
                centro.requestAuthorization(options: [.alert, .sound]) { permitido, _ in
                    DispatchQueue.main.async { emitir(permitido) }
                }
            } else {
                let permitido = [.authorized, .provisional]
                    .contains(ajustes.authorizationStatus)
                DispatchQueue.main.async { emitir(permitido) }
            }
        }
    }

    static func conteos(items: [Pendiente], ahora: Date = Date()) -> Conteos {
        let cal = Calendar.current
        let inicioManana = cal.date(byAdding: .day, value: 1,
                                    to: cal.startOfDay(for: ahora))!
        let finManana = cal.date(byAdding: .day, value: 1, to: inicioManana)!
        var vencidas = 0, hoy = 0, manana = 0, proximas = 0, sinFecha = 0
        for t in items where t.tipo == "tarea" && !t.hecho {
            guard let e = t.fechaObjetivo else { sinFecha += 1; continue }
            let f = Date(timeIntervalSince1970: e)
            if f < ahora { vencidas += 1 }
            else if f < inicioManana { hoy += 1 }
            else if f < finManana { manana += 1 }
            else { proximas += 1 }
        }
        return .init(vencidas: vencidas, hoy: hoy, manana: manana,
                     proximas: proximas, sinFecha: sinFecha)
    }

    static func siguiente(items: [Pendiente], ahora: Date = Date()) -> Pendiente? {
        items.filter {
            $0.tipo == "tarea" && !$0.hecho
                && ($0.fechaObjetivo ?? -Double.greatestFiniteMagnitude) >= ahora.timeIntervalSince1970
        }.min { ($0.fechaObjetivo ?? .greatestFiniteMagnitude)
            < ($1.fechaObjetivo ?? .greatestFiniteMagnitude) }
    }

    /// La IA solo puede cambiar la redacción. Si altera una cantidad, fecha u
    /// hora escrita con dígitos, o devuelve rastros del prompt, se descarta.
    static func resumenIACoherente(_ candidato: String, con local: String) -> Bool {
        let c = candidato.trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count >= 8, c.count <= max(240, local.count * 2),
              !c.localizedCaseInsensitiveContains("INSTRUCCIONES_INTERNAS"),
              !c.localizedCaseInsensitiveContains("RESUMEN_LOCAL") else { return false }
        func numeros(_ texto: String) -> [String] {
            guard let re = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
            let ns = texto as NSString
            return re.matches(in: texto, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }.sorted()
        }
        return numeros(c) == numeros(local)
    }

    /// Tareas que el resumen debe nombrar: vencidas, sin fecha y las que vencen
    /// dentro de `horas` (0 = todas). Una tarea de dentro de meses no se repite a diario.
    static func cercanas(_ items: [Pendiente], ahora: Date, horas: Int) -> [Pendiente] {
        guard horas > 0 else { return items }
        let limite = ahora.timeIntervalSince1970 + Double(horas) * 3_600
        return items.filter { ($0.fechaObjetivo ?? -.greatestFiniteMagnitude) <= limite }
    }

    /// Título corto para leer y mostrar: primera línea y como mucho `palabras`.
    static func breve(_ texto: String, palabras: Int = 12) -> String {
        let linea = texto.split(whereSeparator: \.isNewline).first.map(String.init) ?? texto
        let p = linea.split(separator: " ")
        return p.count <= palabras ? linea : p.prefix(palabras).joined(separator: " ") + "…"
    }

    /// Visible para QA. Resume sin IA y sin enviar datos fuera de la Mac.
    static func resumenTexto(items: [Pendiente], ahora: Date,
                             incluirSinFecha: Bool = true, titulos: Int = 5) -> String {
        let tareas = items.filter { $0.tipo == "tarea" && !$0.hecho }
        guard !tareas.isEmpty else { return "No tienes tareas pendientes." }
        let c = conteos(items: items, ahora: ahora)
        func n(_ k: Int, _ uno: String, _ varios: String) -> String { "\(k) \(k == 1 ? uno : varios)" }
        var bloques: [String] = []
        if c.vencidas > 0 { bloques.append(n(c.vencidas, "vencida", "vencidas")) }
        if c.hoy > 0 { bloques.append("\(c.hoy) para hoy") }
        if c.manana > 0 { bloques.append("\(c.manana) para mañana") }
        if c.proximas > 0 { bloques.append(n(c.proximas, "próxima", "próximas")) }
        if incluirSinFecha, c.sinFecha > 0 { bloques.append("\(c.sinFecha) sin fecha") }

        let relevantes = tareas.filter { incluirSinFecha || $0.fechaObjetivo != nil }
            .sorted {
                ($0.fechaObjetivo ?? Double.greatestFiniteMagnitude)
                    < ($1.fechaObjetivo ?? Double.greatestFiniteMagnitude)
            }
        // Una frase por tarea, con ordinal y pausa: leído de corrido no se entiende.
        let ordinales = ["La primera", "La segunda", "La tercera", "La cuarta", "La quinta"]
        let frases = zip(ordinales.prefix(titulos), relevantes).map { orden, item -> String in
            guard let e = item.fechaObjetivo else { return "\(orden): \(breve(item.texto))." }
            let f = Date(timeIntervalSince1970: e)
            let cuando: String
            if Calendar.current.isDate(f, inSameDayAs: ahora) {
                cuando = f < ahora ? "vencida a las \(f.formatted(date: .omitted, time: .shortened))"
                    : "hoy a las \(f.formatted(date: .omitted, time: .shortened))"
            } else if let diaSiguiente = Calendar.current.date(byAdding: .day, value: 1, to: ahora),
                      Calendar.current.isDate(f, inSameDayAs: diaSiguiente) {
                cuando = "mañana a las \(f.formatted(date: .omitted, time: .shortened))"
            } else {
                cuando = f.formatted(date: .abbreviated, time: .shortened)
            }
            return "\(orden): \(breve(item.texto)), \(cuando)."
        }
        let total = relevantes.count
        guard total > 0 else { return "No tienes tareas pendientes." }
        var texto = "Tienes \(n(total, "tarea pendiente", "tareas pendientes"))"
        texto += bloques.isEmpty ? "." : ": \(bloques.joined(separator: ", "))."
        if !frases.isEmpty { texto += " " + frases.joined(separator: " ") }
        if total > frases.count { texto += " Y \(total - frases.count) más." }
        return texto
    }

    /// Resumen hablado/escrito filtrado por alcance (hoy / semana / pendientes).
    /// "hoy" = pendientes vencidas o que vencen hoy (+ sin fecha si se incluye);
    /// "semana" = las de los próximos 7 días (+ vencidas); "pendientes" = todas.
    static func resumenAlcance(_ alcance: AlcanceResumen, items: [Pendiente],
                               ahora: Date, incluirSinFecha: Bool) -> String {
        let cal = Calendar.current
        let finSemana = cal.date(byAdding: .day, value: 7, to: ahora)?.timeIntervalSince1970
            ?? ahora.timeIntervalSince1970 + 7 * 86_400
        func enAlcance(_ p: Pendiente) -> Bool {
            guard let e = p.fechaObjetivo else { return incluirSinFecha && alcance == .pendientes }
            switch alcance {
            case .pendientes: return true
            case .hoy: return e <= ahora.timeIntervalSince1970
                || cal.isDateInToday(Date(timeIntervalSince1970: e))
            case .semana: return e <= finSemana
            }
        }
        let filtradas = items.filter { $0.tipo == "tarea" && !$0.hecho && enAlcance($0) }
        guard !filtradas.isEmpty else {
            switch alcance {
            case .hoy: return "No tienes tareas para hoy."
            case .semana: return "No tienes tareas para esta semana."
            case .pendientes: return "No tienes tareas pendientes."
            }
        }
        return resumenTexto(items: filtradas, ahora: ahora, incluirSinFecha: incluirSinFecha)
    }

    static func vencidos(items: [Pendiente], ahora: Date, incluirNotas: Bool,
                         repetir: [Int] = []) -> [Pendiente] {
        items.filter { item in
            guard !item.hecho, item.avisar, let e = item.fechaObjetivo,
                  tocaAviso(fecha: e, ultimo: item.avisadoEn,
                            ahora: ahora.timeIntervalSince1970, repetir: repetir)
            else { return false }
            return item.tipo == "tarea" || incluirNotas
        }.sorted { ($0.fechaObjetivo ?? 0) < ($1.fechaObjetivo ?? 0) }
    }

    /// Primer aviso al vencer; luego uno por cada minuto de `repetir` ya alcanzado
    /// y aún no cubierto por el último aviso. Pasados 5 minutos del último plazo
    /// no se repite más (una Mac que despierta tarde no recupera repeticiones viejas):
    /// desde ahí la tarea solo sale en los resúmenes.
    static func tocaAviso(fecha: Double, ultimo: Double?, ahora: Double, repetir: [Int]) -> Bool {
        guard fecha <= ahora else { return false }
        guard let ultimo else { return true }
        guard let tope = repetir.max(), ahora <= fecha + Double(tope) * 60 + 300 else { return false }
        return repetir.contains { m in
            let t = fecha + Double(m) * 60
            return t > ultimo && t <= ahora
        }
    }

    private func publicarVencidos(_ items: [Pendiente], repetidos: Bool, ahora: Date,
                                  callar: Bool = false) {
        guard let p = items.first else { return }
        let marca = "\(repetidos ? "r" : "n").\(Int(ahora.timeIntervalSince1970))"
        if items.count == 1 {
            let titulo = repetidos ? "Sigue pendiente"
                : (p.tipo == "nota" ? "Nota programada" : "Tarea pendiente")
            publicar(.init(titulo: titulo, cuerpo: Self.breve(p.texto),
                           hablar: !callar && Config.tareasAvisosVoz(),
                           id: "pendiente.\(p.id).\(marca)", sonido: !callar))
        } else {
            let muestra = items.prefix(3).map { Self.breve($0.texto) }.joined(separator: "; ")
            publicar(.init(titulo: "\(items.count) pendientes \(repetidos ? "siguen sin hacer" : "vencidos")",
                           cuerpo: muestra, hablar: !callar && Config.tareasAvisosVoz(),
                           id: "pendientes.\(marca)", sonido: !callar))
        }
    }

    private func enHorasQuietasAhora(_ ahora: Date) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: ahora)
        return Config.tareasQuietasActivo()
            && Self.enHorasQuietas(minutosAhora: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                                   desde: Config.tareasQuietasDesde(),
                                   hasta: Config.tareasQuietasHasta())
    }

    func revisarAhora(ahora: Date = Date()) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.revisarAhora(ahora: ahora) }
            return
        }
        let vencidos = Config.tareasAvisos()
            ? Self.vencidos(items: NotasStore.todos(), ahora: ahora,
                            incluirNotas: Config.tareasAvisarNotas(),
                            repetir: Config.tareasVencidasRepetirMinutos()) : []

        let marcados = vencidos.compactMap { v in
            NotasStore.marcarAvisado(v.id, previo: v.avisadoEn, fecha: v.fechaObjetivo, ahora: ahora)
                .map { ($0, v.avisadoEn != nil) }
        }
        publicarVencidos(marcados.filter { !$0.1 }.map { $0.0 }, repetidos: false, ahora: ahora)
        // Las repeticiones respetan las horas quietas: de noche llegan sin sonido ni voz.
        publicarVencidos(marcados.filter { $0.1 }.map { $0.0 }, repetidos: true, ahora: ahora,
                         callar: enHorasQuietasAhora(ahora))
        revisarResumen(ahora: ahora)
        revisarResumenPeriodico(ahora: ahora)
    }

    /// ¿`ahora` cae dentro de la ventana de silencio? La ventana puede cruzar
    /// medianoche (ej. 22:00→07:00). Puro y testeable.
    static func enHorasQuietas(minutosAhora: Int, desde: Int, hasta: Int) -> Bool {
        if desde == hasta { return false }
        return desde < hasta
            ? (minutosAhora >= desde && minutosAhora < hasta)          // ventana normal
            : (minutosAhora >= desde || minutosAhora < hasta)          // cruza medianoche
    }

    /// ¿Toca el resumen periódico? Puro: separa la política del reloj real.
    static func tocaResumenPeriodico(activo: Bool, horas: Int,
                                     ultimo: Double, ahora: Date) -> Bool {
        guard activo, horas >= 1 else { return false }
        let transcurrido = ahora.timeIntervalSince1970 - ultimo
        return transcurrido >= Double(horas) * 3_600 - 30   // -30s: tolerancia del reloj
    }

    /// Recordatorio cada N horas de lo que falta. En horas quietas entrega la
    /// notificación escrita pero SIN sonido ni voz. Nunca dispara si no hay
    /// pendientes. Avanza el marcador aunque calle, para no acumular al amanecer.
    private func revisarResumenPeriodico(ahora: Date) {
        guard Config.tareasResumenPeriodico() else { return }
        // Primera vez (o tras encenderlo): fija la línea base sin disparar, para
        // que el primer recordatorio llegue tras un intervalo completo y no en
        // cada arranque o cambio de ajuste.
        if Config.tareasResumenPeriodicoUltimo() <= 0 {
            Config.set("tareas_resumen_periodico_ultimo", to: ahora.timeIntervalSince1970)
            return
        }
        guard Self.tocaResumenPeriodico(activo: true,
                                        horas: Config.tareasResumenPeriodicoHoras(),
                                        ultimo: Config.tareasResumenPeriodicoUltimo(),
                                        ahora: ahora) else { return }
        Config.set("tareas_resumen_periodico_ultimo", to: ahora.timeIntervalSince1970)
        let items = Self.cercanas(NotasStore.todos(), ahora: ahora, horas: Config.tareasResumenHorasAntes())
        let sinFecha = Config.tareasResumenIncluirSinFecha()
        guard items.contains(where: { $0.tipo == "tarea" && !$0.hecho && (sinFecha || $0.fechaObjetivo != nil) })
        else { return }  // nada que recordar
        let quietas = enHorasQuietasAhora(ahora)
        let texto = Self.resumenTexto(items: items, ahora: ahora,
                                      incluirSinFecha: Config.tareasResumenIncluirSinFecha())
        publicar(.init(titulo: "Tareas pendientes", cuerpo: texto,
                       hablar: !quietas && Config.tareasResumenPeriodicoVoz(),
                       id: "periodico.\(Int(ahora.timeIntervalSince1970))",
                       sonido: !quietas))
    }

    private func revisarResumen(ahora: Date) {
        let clave = Self.claveDia(ahora)
        var periodos: [(nombre: String, minuto: Int, hecho: Bool)] = []
        if Config.tareasResumenManana() { periodos.append(("manana", Config.tareasResumenMananaMinutos(), false)) }
        if Config.tareasResumenMediodia() { periodos.append(("mediodia", Config.tareasResumenMediodiaMinutos(), false)) }
        if Config.tareasResumenTarde() { periodos.append(("tarde", Config.tareasResumenTardeMinutos(), false)) }
        periodos = periodos.map { ($0.nombre, $0.minuto, Config.tareasResumenUltimo($0.nombre) == clave) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: ahora)
        guard let (periodo, cubrir) = Self.elegirPeriodo(minutos: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                                                         periodos: periodos) else { return }
        // Si la Mac se abre tarde, entrega solo el resumen más reciente y marca los
        // anteriores ya pasados como cubiertos: nunca dispara dos discursos seguidos.
        for p in cubrir { Config.set("tareas_resumen_ultimo_\(p)", to: clave) }
        let titulos = ["manana": "Resumen del día", "mediodia": "Resumen del mediodía",
                       "tarde": "Resumen de la tarde"]
        publicarResumen(titulo: titulos[periodo] ?? "Resumen", ahora: ahora, periodo: periodo)
    }

    static func periodoResumenPendiente(ahora: Date,
                                        mananaActivo: Bool, tardeActivo: Bool,
                                        minutoManana: Int, minutoTarde: Int,
                                        ultimoManana: String,
                                        ultimoTarde: String,
                                        mediodiaActivo: Bool = false, minutoMediodia: Int = 750,
                                        ultimoMediodia: String = "") -> String? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: ahora)
        let clave = claveDia(ahora)
        var periodos: [(nombre: String, minuto: Int, hecho: Bool)] = []
        if mananaActivo { periodos.append(("manana", minutoManana, ultimoManana == clave)) }
        if mediodiaActivo { periodos.append(("mediodia", minutoMediodia, ultimoMediodia == clave)) }
        if tardeActivo { periodos.append(("tarde", minutoTarde, ultimoTarde == clave)) }
        return elegirPeriodo(minutos: (c.hour ?? 0) * 60 + (c.minute ?? 0), periodos: periodos)?.0
    }

    /// El periodo pendiente más tardío ya alcanzado (por su hora, no por su nombre)
    /// y los que quedan cubiertos con él: todos los ya alcanzados hasta esa hora.
    static func elegirPeriodo(minutos: Int, periodos: [(nombre: String, minuto: Int, hecho: Bool)])
        -> (String, [String])? {
        let alcanzados = periodos.filter { $0.minuto <= minutos }
        guard let e = alcanzados.filter({ !$0.hecho }).max(by: { $0.minuto < $1.minuto }) else { return nil }
        return (e.nombre, alcanzados.filter { $0.minuto <= e.minuto }.map { $0.nombre })
    }

    private func publicarResumen(titulo: String, ahora: Date, periodo: String) {
        // Con IA activa el texto puede salir de la Mac: como mucho tres títulos,
        // lo que promete el consentimiento de ese ajuste.
        let local = Self.resumenTexto(items: Self.cercanas(NotasStore.todos(), ahora: ahora,
                                                           horas: Config.tareasResumenHorasAntes()),
                                      ahora: ahora,
                                      incluirSinFecha: Config.tareasResumenIncluirSinFecha(),
                                      titulos: Config.tareasResumenIA() ? 3 : 5)
        let id = "resumen.\(periodo).\(Self.claveDia(ahora))"
        let aviso: (String) -> Void = { [weak self] cuerpo in
            self?.publicar(.init(titulo: titulo, cuerpo: cuerpo,
                                 hablar: Config.tareasAvisosVoz(), id: id))
        }
        guard Config.tareasResumenIA(), ChatIA.seleccionada() != nil else {
            aviso(local); return
        }
        // La IA es cosmética y opt-in: nunca bloquea el recordatorio. Si en seis
        // segundos no respondió, se entrega el cálculo local y la respuesta tardía
        // queda descartada para evitar avisos duplicados.
        var entregado = false
        let entregarUnaVez: (String) -> Void = { texto in
            guard !entregado else { return }
            entregado = true; aviso(texto)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { entregarUnaVez(local) }
        LLMPostProcess.resumirPendientes(local) { texto in
            DispatchQueue.main.async {
                entregarUnaVez(Self.resumenIACoherente(texto, con: local) ? texto : local)
            }
        }
    }

    static func claveDia(_ fecha: Date) -> String {
        let f = DateFormatter(); f.calendar = .current; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: fecha)
    }

    private func publicar(_ aviso: Aviso) {
        Log.log(.config, "aviso local: \(aviso.titulo) — \(aviso.cuerpo.prefix(120))")
        AgenteLog.registrar("aviso_pendiente", ["id": aviso.id, "titulo": aviso.titulo,
                                                 "texto": aviso.cuerpo, "voz": aviso.hablar])
        presentar?(aviso)

        guard let centro else { return }
        centro.getNotificationSettings { [weak self] ajustes in
            guard [.authorized, .provisional].contains(ajustes.authorizationStatus) else { return }
            let c = UNMutableNotificationContent(); c.title = aviso.titulo; c.body = aviso.cuerpo
            if Config.tareasAvisosSonido(), aviso.sonido { c.sound = .default }
            let req = UNNotificationRequest(identifier: "ec.bto.btodicta.\(aviso.id)",
                                            content: c, trigger: nil)
            self?.centro?.add(req) { error in
                if let error { Log.write("⚠️ notificación de tarea: \(error.localizedDescription)") }
                else {
                    Log.write("notificación de tarea aceptada por macOS: \(aviso.id)")
                    AgenteLog.registrar("notificacion_local_aceptada", ["id": aviso.id])
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Config.tareasAvisosSonido() ? [.banner, .list, .sound] : [.banner, .list])
    }
}

/// Hooks puros y net-zero. Viven antes de `NSApplication` en main.swift para
/// poder correr en CI, SSH o el sandbox de un agente sin una sesión Aqua.
enum TareasNotasQA {
    static func ejecutarSiSePidio() {
        let env = ProcessInfo.processInfo.environment
        if env["BTODICTA_TASKREMINDERTEST"] == "1" { probarRecordatorios() }
        if env["BTODICTA_NOTATEST"] == "1" { probarAlmacen() }
    }

    private static func probarRecordatorios() -> Never {
        let cal = Calendar(identifier: .gregorian)
        let ahora = cal.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                   hour: 10, minute: 0))!
        let fecha = cal.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                   hour: 20, minute: 0))!
        let p = NotasStore.agregar(tipo: "tarea", texto: "QA llamar a Rafael",
                                   fechaObjetivo: fecha, avisar: true)
        let agregado = NotasStore.todos().contains {
            $0.id == p.id && $0.fechaObjetivo == fecha.timeIntervalSince1970 && $0.avisar
        }
        let ayer = cal.date(byAdding: .hour, value: -26, to: ahora)!
        let vencidaHoy = cal.date(byAdding: .hour, value: -1, to: ahora)!
        let manana = cal.date(byAdding: .day, value: 1, to: fecha)!
        let futura = cal.date(byAdding: .day, value: 4, to: fecha)!
        let pruebas = [
            Pendiente(tipo: "tarea", texto: "de ayer", fechaObjetivo: ayer),
            Pendiente(tipo: "tarea", texto: "de esta mañana", fechaObjetivo: vencidaHoy),
            Pendiente(tipo: "tarea", texto: "de esta tarde", fechaObjetivo: fecha),
            Pendiente(tipo: "tarea", texto: "de mañana", fechaObjetivo: manana),
            Pendiente(tipo: "tarea", texto: "futura", fechaObjetivo: futura),
            Pendiente(tipo: "tarea", texto: "sin fecha"),
            Pendiente(tipo: "nota", texto: "nota vencida", fechaObjetivo: vencidaHoy)
        ]
        let resumen = TareasRecordatorios.resumenTexto(items: pruebas, ahora: ahora)
        let conteos = TareasRecordatorios.conteos(items: pruebas, ahora: ahora)
        let larga = Pendiente(tipo: "tarea", texto: "uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce")
        let lejana = Pendiente(tipo: "tarea", texto: "lejana",
                               fechaObjetivo: cal.date(byAdding: .day, value: 90, to: ahora)!)
        let resumenOK = resumen.hasPrefix("Tienes 6 tareas pendientes: 2 vencidas, 1 para hoy")
            && resumen.contains("1 para mañana") && resumen.contains("1 próxima")
            && resumen.contains("1 sin fecha") && resumen.contains("La primera: de ayer")
            && resumen.contains("La quinta:") && resumen.contains("Y 1 más.")
            && resumen.contains("vencida a las")
            && !TareasRecordatorios.resumenTexto(items: pruebas, ahora: ahora, titulos: 3).contains("La cuarta")
            && TareasRecordatorios.resumenTexto(items: [Pendiente(tipo: "tarea", texto: "x")], ahora: ahora,
                                                incluirSinFecha: false) == "No tienes tareas pendientes."
            && TareasRecordatorios.resumenTexto(items: [pruebas[0], pruebas[1]], ahora: ahora)
                .hasPrefix("Tienes 2 tareas pendientes: 2 vencidas.")
            && TareasRecordatorios.breve(larga.texto).hasSuffix("doce…")
            && TareasRecordatorios.cercanas(pruebas + [lejana], ahora: ahora, horas: 72).count == pruebas.count - 1
            && TareasRecordatorios.cercanas(pruebas + [lejana], ahora: ahora, horas: 0).count == pruebas.count + 1
            && conteos.total == 6 && conteos.vencidas == 2
        let notaOptIn = TareasRecordatorios.vencidos(items: pruebas, ahora: ahora,
                                                     incluirNotas: true).count == 3
            && TareasRecordatorios.vencidos(items: pruebas, ahora: ahora,
                                             incluirNotas: false).count == 2
        let siguienteOK = TareasRecordatorios.siguiente(items: pruebas, ahora: ahora)?.texto
            == "de esta tarde"
        let recuperacionOK = TareasRecordatorios.periodoResumenPendiente(
            ahora: cal.date(bySettingHour: 21, minute: 0, second: 0, of: ahora)!,
            mananaActivo: true, tardeActivo: true,
            minutoManana: 510, minutoTarde: 1200,
            ultimoManana: "", ultimoTarde: "") == "tarde"
            && TareasRecordatorios.periodoResumenPendiente(
                ahora: ahora, mananaActivo: true, tardeActivo: true,
                minutoManana: 510, minutoTarde: 1200,
                ultimoManana: "", ultimoTarde: "") == "manana"
            && TareasRecordatorios.periodoResumenPendiente(
                ahora: ahora, mananaActivo: true, tardeActivo: true,
                minutoManana: 510, minutoTarde: 1200,
                ultimoManana: "2026-07-19", ultimoTarde: "") == nil
        let coherenciaIA = TareasRecordatorios.resumenIACoherente(
            "Tienes vencidas: 2 · hoy: 1. Revisa a las 8:00.",
            con: "Tienes vencidas: 2 · hoy: 1. Revisa a las 8:00.")
            && !TareasRecordatorios.resumenIACoherente(
                "Tienes vencidas: 2 · hoy: 1. Revisa a las 9:00.",
                con: "Tienes vencidas: 2 · hoy: 1. Revisa a las 8:00.")
        let primero = NotasStore.marcarAvisado(p.id, ahora: ahora)
        let segundo = NotasStore.marcarAvisado(p.id, ahora: ahora)
        let tercero = NotasStore.marcarAvisado(p.id, previo: primero?.avisadoEn,
                                               fecha: fecha.timeIntervalSince1970,
                                               ahora: ahora.addingTimeInterval(900))
        let otraFecha = NotasStore.marcarAvisado(p.id, previo: tercero?.avisadoEn,
                                                 fecha: fecha.timeIntervalSince1970 + 60, ahora: ahora)
        // Vence a las 0: avisa en 0, 15, 30 y 60 minutos y nunca más.
        let r = [15, 30, 60], f = 1_000_000.0
        func toca(_ ultimo: Double?, _ min: Double) -> Bool {
            TareasRecordatorios.tocaAviso(fecha: f, ultimo: ultimo, ahora: f + min * 60, repetir: r)
        }
        let cadencia = !toca(nil, -1) && toca(nil, 0) && !toca(f, 14) && toca(f, 15)
            && !toca(f + 900, 29) && toca(f + 900, 30) && toca(f + 1_800, 60)
            && !toca(f + 3_600, 61) && !toca(f + 3_600, 600)
            && toca(f, 40) && !toca(f + 2_400, 59)          // despierta a los 40: uno, no dos
            && !toca(f, 120)                                // despierta tarde: nada viejo
            && !TareasRecordatorios.tocaAviso(fecha: f, ultimo: f, ahora: f + 900, repetir: [])
            && TareasRecordatorios.periodoResumenPendiente(
                ahora: cal.date(bySettingHour: 13, minute: 0, second: 0, of: ahora)!,
                mananaActivo: true, tardeActivo: true, minutoManana: 510, minutoTarde: 1200,
                ultimoManana: "", ultimoTarde: "", mediodiaActivo: true, minutoMediodia: 750,
                ultimoMediodia: "") == "mediodia"
            && TareasRecordatorios.elegirPeriodo(minutos: 1205, periodos: [
                ("tarde", 1200, false), ("mediodia", 1230, false)])! == ("tarde", ["tarde"])
            && TareasRecordatorios.elegirPeriodo(minutos: 1300, periodos: [
                ("manana", 510, false), ("mediodia", 750, true), ("tarde", 1200, false)])!.1.count == 3
        let unaVez = primero?.avisadoEn != nil && segundo == nil && tercero != nil && otraFecha == nil && cadencia
        let parseada = AppleAgenda.previsualizar("Llamar a Rafael mañana a las 8:00 p.m.",
                                                 ahora: ahora).fecha
        let fechaOK = parseada.map {
            let c = cal.dateComponents([.day, .hour, .minute], from: $0)
            return c.day == 20 && c.hour == 20 && c.minute == 0
        } ?? false
        NotasStore.borrar(p.id)
        let netoCero = !NotasStore.todos().contains { $0.id == p.id }
        let permisos = (try? FileManager.default.attributesOfItem(
            atPath: Config.dir.appendingPathComponent("pendientes.json").path)[.posixPermissions]
            as? NSNumber)?.intValue == 0o600
        let ok = agregado && resumenOK && notaOptIn && siguienteOK && recuperacionOK && coherenciaIA
            && unaVez && fechaOK && netoCero && permisos
        print("TASKREMINDERTEST agregado=\(agregado) fecha=\(fechaOK) resumen=\(resumenOK) notas=\(notaOptIn) siguiente=\(siguienteOK) recupera=\(recuperacionOK) ia=\(coherenciaIA) unaVez=\(unaVez) neto=\(netoCero) 0600=\(permisos)")
        print("TASKREMINDERTEST \(ok ? "TODO OK" : "FALLA")")
        exit(ok ? 0 : 3)
    }

    private static func probarAlmacen() -> Never {
        let p = NotasStore.agregar(tipo: "tarea", texto: "  prueba xyz  ")
        let addOk = NotasStore.todos().contains { $0.id == p.id && $0.texto == "prueba xyz" }
            && p.hecho == false
        NotasStore.alternar(p.id)
        let togOk = NotasStore.todos().first { $0.id == p.id }?.hecho == true
        NotasStore.borrar(p.id)
        let delOk = !NotasStore.todos().contains { $0.id == p.id }
        let ok = addOk && togOk && delOk
        print("NOTATEST add=\(addOk) toggle=\(togOk) delete=\(delOk) → \(ok ? "TODO OK" : "✗ FALLA")")
        exit(ok ? 0 : 3)
    }
}
