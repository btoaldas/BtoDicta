import AppKit
import AVFoundation
import Combine
import Contacts
import CoreGraphics
import CoreLocation
import EventKit
import MusicKit
import Speech

enum PermisoBetoID: String, CaseIterable, Identifiable {
    case notificaciones
    case reconocimientoVoz
    case pantalla
    case contactos
    case calendario
    case recordatorios
    case ubicacion
    case musica
    case automatizacion
    case archivos

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .notificaciones: return "Notificaciones"
        case .reconocimientoVoz: return "Reconocimiento de voz de Apple"
        case .pantalla: return "Captura y grabación de pantalla"
        case .contactos: return "Contactos"
        case .calendario: return "Calendario"
        case .recordatorios: return "Recordatorios"
        case .ubicacion: return "Ubicación"
        case .musica: return "Apple Music y contenido multimedia"
        case .automatizacion: return "Automatización"
        case .archivos: return "Archivos y carpetas"
        }
    }

    var icono: String {
        switch self {
        case .notificaciones: return "bell.badge.fill"
        case .reconocimientoVoz: return "waveform.and.mic"
        case .pantalla: return "rectangle.inset.filled.and.person.filled"
        case .contactos: return "person.crop.circle"
        case .calendario: return "calendar"
        case .recordatorios: return "checklist"
        case .ubicacion: return "location.fill"
        case .musica: return "music.note"
        case .automatizacion: return "gearshape.2.fill"
        case .archivos: return "folder.fill"
        }
    }

    var detalle: String {
        switch self {
        case .notificaciones:
            return "Avisa cuando vence una tarea y entrega los resúmenes que programes. Recomendado."
        case .reconocimientoVoz:
            return "Permite la vista previa en vivo y las funciones de voz nativas de Apple."
        case .pantalla:
            return "Solo se usa cuando pides una captura o grabación de pantalla."
        case .contactos:
            return "Busca localmente el destinatario que nombras para preparar un WhatsApp."
        case .calendario:
            return "Crea eventos únicamente cuando se lo solicitas al asistente."
        case .recordatorios:
            return "Crea recordatorios de Apple únicamente cuando se lo solicitas."
        case .ubicacion:
            return "Obtiene una zona aproximada solo cuando preguntas el clima sin indicar ciudad."
        case .musica:
            return "Permite usar tu biblioteca musical cuando eliges Apple Music; los otros proveedores siguen funcionando si lo niegas."
        case .automatizacion:
            return "macOS autoriza cada app por separado cuando pides controlar Notas, Word, Música, Atajos u otra app."
        case .archivos:
            return "Se concede únicamente al elegir una carpeta o archivo; BtoDicta no necesita acceso total al disco."
        }
    }
}

struct EstadoPermisoBeto: Equatable {
    enum Tipo { case permitido, pendiente, denegado, contextual, noDisponible }
    let tipo: Tipo
    let texto: String

    var concedido: Bool { tipo == .permitido }
    var requiereAtencion: Bool { tipo == .denegado }
}

enum PermisosSistema {
    static let adicionales = PermisoBetoID.allCases

    static func estado(_ permiso: PermisoBetoID) -> EstadoPermisoBeto {
        switch permiso {
        case .notificaciones:
            return .init(tipo: .pendiente, texto: "Consultando…")
        case .reconocimientoVoz:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .init(tipo: .permitido, texto: "Permitido")
            case .denied: return .init(tipo: .denegado, texto: "Denegado en macOS")
            case .restricted: return .init(tipo: .noDisponible, texto: "Restringido")
            case .notDetermined: return .init(tipo: .pendiente, texto: "Sin solicitar todavía")
            @unknown default: return .init(tipo: .noDisponible, texto: "Estado desconocido")
            }
        case .pantalla:
            return CGPreflightScreenCaptureAccess()
                ? .init(tipo: .permitido, texto: "Permitido")
                : .init(tipo: .pendiente, texto: "Sin conceder o requiere reiniciar")
        case .contactos:
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited: return .init(tipo: .permitido, texto: "Permitido")
            case .denied: return .init(tipo: .denegado, texto: "Denegado en macOS")
            case .restricted: return .init(tipo: .noDisponible, texto: "Restringido")
            case .notDetermined: return .init(tipo: .pendiente, texto: "Sin solicitar todavía")
            @unknown default: return .init(tipo: .noDisponible, texto: "Estado desconocido")
            }
        case .calendario:
            return estadoEventKit(AppleAgenda.estadoEventos())
        case .recordatorios:
            return estadoEventKit(AppleAgenda.estadoRecordatorios())
        case .ubicacion:
            switch UbicacionClima.estado() {
            case .authorizedAlways, .authorizedWhenInUse:
                return .init(tipo: .permitido, texto: "Permitida")
            case .denied: return .init(tipo: .denegado, texto: "Denegada en macOS")
            case .restricted: return .init(tipo: .noDisponible, texto: "Restringida")
            case .notDetermined: return .init(tipo: .pendiente, texto: "Sin solicitar todavía")
            @unknown default: return .init(tipo: .noDisponible, texto: "Estado desconocido")
            }
        case .musica:
            switch MusicAuthorization.currentStatus {
            case .authorized: return .init(tipo: .permitido, texto: "Permitido")
            case .denied: return .init(tipo: .denegado, texto: "Denegado en macOS")
            case .restricted: return .init(tipo: .noDisponible, texto: "Restringido")
            case .notDetermined: return .init(tipo: .pendiente, texto: "Sin solicitar todavía")
            @unknown default: return .init(tipo: .noDisponible, texto: "Estado desconocido")
            }
        case .automatizacion:
            return .init(tipo: .contextual, texto: "Se concede por cada aplicación")
        case .archivos:
            return .init(tipo: .contextual, texto: "Se concede al elegir")
        }
    }

    static func estadoNotificaciones(_ estado: TareasRecordatorios.EstadoNotificaciones)
        -> EstadoPermisoBeto {
        switch estado {
        case .permitidas, .provisionales:
            return .init(tipo: .permitido, texto: estado.texto)
        case .denegadas:
            return .init(tipo: .denegado, texto: estado.texto)
        case .sinSolicitar:
            return .init(tipo: .pendiente, texto: estado.texto)
        case .noDisponibles:
            return .init(tipo: .noDisponible, texto: estado.texto)
        case .desconocido:
            return .init(tipo: .noDisponible, texto: estado.texto)
        }
    }

    static func etiquetaBoton(_ permiso: PermisoBetoID, estado: EstadoPermisoBeto) -> String? {
        if permiso == .archivos { return nil }
        if estado.tipo == .noDisponible { return nil }
        if permiso == .automatizacion { return "Revisar Automatización…" }
        if estado.concedido { return "Revisar en Ajustes…" }
        if estado.requiereAtencion { return "Abrir Ajustes…" }
        return "Activar"
    }

    static func actuar(_ permiso: PermisoBetoID, alTerminar: @escaping () -> Void) {
        let actual = estado(permiso)
        if actual.tipo == .noDisponible { alTerminar(); return }
        if actual.concedido || actual.requiereAtencion {
            abrirAjustes(permiso); alTerminar(); return
        }

        switch permiso {
        case .notificaciones:
            TareasRecordatorios.solicitarPermiso { estado in
                if estado == .denegadas { _ = TareasRecordatorios.abrirAjustesNotificaciones() }
                alTerminar()
            }
        case .reconocimientoVoz:
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { alTerminar() }
            }
        case .pantalla:
            let concedido = CGRequestScreenCaptureAccess()
            if !concedido { _ = abrirAjustes(.pantalla) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: alTerminar)
        case .contactos:
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                DispatchQueue.main.async { alTerminar() }
            }
        case .calendario:
            AppleAgenda.solicitarEventos { _ in alTerminar() }
        case .recordatorios:
            AppleAgenda.solicitarRecordatorios { _ in alTerminar() }
        case .ubicacion:
            UbicacionClima.shared.solicitarPermiso()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: alTerminar)
        case .musica:
            Task {
                _ = await MusicAuthorization.request()
                await MainActor.run { alTerminar() }
            }
        case .automatizacion:
            abrirAjustes(.automatizacion); alTerminar()
        case .archivos:
            alTerminar()
        }
    }

    @discardableResult
    static func abrirAjustes(_ permiso: PermisoBetoID) -> Bool {
        if permiso == .notificaciones { return TareasRecordatorios.abrirAjustesNotificaciones() }
        let panel: String
        switch permiso {
        case .reconocimientoVoz: panel = "Privacy_SpeechRecognition"
        case .pantalla: panel = "Privacy_ScreenCapture"
        case .contactos: panel = "Privacy_Contacts"
        case .calendario: panel = "Privacy_Calendars"
        case .recordatorios: panel = "Privacy_Reminders"
        case .ubicacion: panel = "Privacy_LocationServices"
        case .musica: panel = "Privacy_Media"
        case .automatizacion: panel = "Privacy_Automation"
        case .archivos: panel = "Privacy_FilesAndFolders"
        case .notificaciones: return false
        }
        let rutas = [
            "x-apple.systempreferences:com.apple.preference.security?\(panel)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for ruta in rutas {
            if let url = URL(string: ruta), NSWorkspace.shared.open(url) { return true }
        }
        return false
    }

    static func rutasQA() -> [PermisoBetoID: String] {
        Dictionary(uniqueKeysWithValues: adicionales.map { permiso in
            let ruta: String
            switch permiso {
            case .notificaciones: ruta = "Notifications"
            case .reconocimientoVoz: ruta = "Privacy_SpeechRecognition"
            case .pantalla: ruta = "Privacy_ScreenCapture"
            case .contactos: ruta = "Privacy_Contacts"
            case .calendario: ruta = "Privacy_Calendars"
            case .recordatorios: ruta = "Privacy_Reminders"
            case .ubicacion: ruta = "Privacy_LocationServices"
            case .musica: ruta = "Privacy_Media"
            case .automatizacion: ruta = "Privacy_Automation"
            case .archivos: ruta = "Privacy_FilesAndFolders"
            }
            return (permiso, ruta)
        })
    }

    private static func estadoEventKit(_ estado: EKAuthorizationStatus) -> EstadoPermisoBeto {
        switch estado {
        case .fullAccess, .authorized:
            return .init(tipo: .permitido, texto: "Permitido")
        case .writeOnly:
            return .init(tipo: .permitido, texto: "Solo escritura")
        case .denied:
            return .init(tipo: .denegado, texto: "Denegado en macOS")
        case .restricted:
            return .init(tipo: .noDisponible, texto: "Restringido")
        case .notDetermined:
            return .init(tipo: .pendiente, texto: "Sin solicitar todavía")
        @unknown default:
            return .init(tipo: .noDisponible, texto: "Estado desconocido")
        }
    }
}

@MainActor
final class PermisosSistemaModel: ObservableObject {
    @Published private(set) var estados: [PermisoBetoID: EstadoPermisoBeto] = [:]

    init() { refrescar() }

    func refrescar() {
        let nuevos = Dictionary(uniqueKeysWithValues: PermisosSistema.adicionales.map {
            ($0, PermisosSistema.estado($0))
        })
        estados = nuevos
        TareasRecordatorios.consultarPermiso { [weak self] estado in
            self?.estados[.notificaciones] = PermisosSistema.estadoNotificaciones(estado)
        }
    }

    func actuar(_ permiso: PermisoBetoID) {
        PermisosSistema.actuar(permiso) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refrescar() }
        }
    }
}

enum PermisosSistemaQA {
    static func ejecutarSiSePidio() {
        guard ProcessInfo.processInfo.environment["BTODICTA_PERMISSIONSTEST"] == "1" else { return }
        let permisos = PermisosSistema.adicionales
        let rutas = PermisosSistema.rutasQA()
        let unicos = Set(permisos.map(\.rawValue)).count == permisos.count
        let completos = permisos.allSatisfy {
            !$0.titulo.isEmpty && !$0.icono.isEmpty && !$0.detalle.isEmpty && rutas[$0] != nil
        }
        let archivosContextual = PermisosSistema.etiquetaBoton(
            .archivos, estado: .init(tipo: .contextual, texto: "Se concede al elegir")) == nil
        let denegadoAbre = PermisosSistema.etiquetaBoton(
            .notificaciones, estado: .init(tipo: .denegado, texto: "Denegadas")) == "Abrir Ajustes…"
        let noDisponibleNoInsiste = PermisosSistema.etiquetaBoton(
            .reconocimientoVoz, estado: .init(tipo: .noDisponible, texto: "Restringido")) == nil
        let ok = permisos.count == 10 && unicos && completos && archivosContextual
            && denegadoAbre && noDisponibleNoInsiste
        print("PERMISSIONSTEST permisos=\(permisos.count) unicos=\(unicos) completos=\(completos) contextual=\(archivosContextual) denegado=\(denegadoAbre) restringido=\(noDisponibleNoInsiste)")
        print("PERMISSIONSTEST \(ok ? "TODO OK" : "FALLA")")
        fflush(stdout); exit(ok ? 0 : 3)
    }
}
