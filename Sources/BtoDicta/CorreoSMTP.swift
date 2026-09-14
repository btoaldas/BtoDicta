import Foundation
import Network

// MARK: - Enviar correo por SMTP, diciendo siempre POR QUÉ falló
//
// Swift no trae cliente de correo, así que aquí va uno mínimo y honesto: se
// conecta por TLS desde el primer byte (puerto 465, «SSL implícito»), saluda,
// se autentica y entrega. No se implementa STARTTLS —que obliga a levantar el
// cifrado a mitad de una conexión ya abierta— porque el 465 hace lo mismo sin
// esa costura y lo sirven todos los proveedores que interesan.
//
// Lo que más importa de este archivo no es que envíe: es que cuando NO envía
// diga cuál fue el problema. Un «no se pudo enviar» obliga a adivinar entre el
// puerto, la clave, el remitente o el servidor. Aquí cada fallo sale con su
// código SMTP y con la frase del servidor, traducida a algo accionable.
enum CorreoSMTP {

    /// Traza del diálogo SMTP. Se enciende con BTODICTA_SMTPDEBUG=1 y nunca
    /// imprime la clave: un problema de correo se diagnostica viendo qué dijo
    /// cada lado, no adivinando.
    static var traza: Bool { ProcessInfo.processInfo.environment["BTODICTA_SMTPDEBUG"] == "1" }
    static func tz(_ s: String) { if traza { print("SMTP » \(s)") } }

    struct Cuenta {
        var host: String
        var puerto: Int
        var usuario: String
        var clave: String
        var remitente: String
    }

    enum Fallo: Error, LocalizedError {
        case sinConfigurar(String)
        case conexion(String)
        case autenticacion(String)
        case rechazo(paso: String, codigo: Int, texto: String)
        case tiempo(String)

        var errorDescription: String? {
            switch self {
            case .sinConfigurar(let q): return "Falta configurar \(q)"
            case .conexion(let q): return "No se pudo conectar: \(q)"
            case .autenticacion(let q): return "El servidor rechazó el usuario o la clave: \(q)"
            case .rechazo(let paso, let codigo, let texto): return "\(paso) — el servidor respondió \(codigo): \(texto)"
            case .tiempo(let q): return "El servidor no contestó a tiempo (\(q))"
            }
        }

        /// Qué mirar para arreglarlo. Es la diferencia entre un error y una
        /// pista: el usuario no tiene por qué saber qué significa un 535.
        var consejo: String {
            switch self {
            case .sinConfigurar: return "Complétalo en Configuración → Correo."
            case .conexion:
                return "Revisa el servidor y el puerto. El habitual es 465. Si tu red bloquea la salida, prueba desde otra conexión."
            case .autenticacion:
                return "Revisa el usuario (suele ser el correo completo) y la clave. Con Gmail hace falta una «contraseña de aplicación», no la del correo."
            case .rechazo(_, let codigo, _):
                switch codigo {
                case 550, 553: return "El servidor no acepta ese remitente o ese destinatario. Comprueba que el remitente sea el mismo usuario con el que te autenticas."
                case 552, 523: return "El mensaje es demasiado grande para ese servidor."
                case 421, 451, 452: return "El servidor está saturado o te está limitando. Inténtalo más tarde."
                default: return "Revisa la dirección de destino y la del remitente."
                }
            case .tiempo:
                return "El servidor tardó demasiado. Puede estar caído o el puerto estar filtrado."
            }
        }
    }

    // MARK: Envío

    static func enviar(_ cuenta: Cuenta, para destinatarios: [String],
                       asunto: String, cuerpo: String,
                       completion: @escaping (Result<String, Fallo>) -> Void) {
        guard !cuenta.host.isEmpty else { completion(.failure(.sinConfigurar("el servidor de correo"))); return }
        guard !cuenta.usuario.isEmpty, !cuenta.clave.isEmpty else {
            completion(.failure(.sinConfigurar("el usuario y la clave"))); return
        }
        let dest = destinatarios.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("@") }
        guard !dest.isEmpty else { completion(.failure(.sinConfigurar("al menos un destinatario válido"))); return }
        let de = cuenta.remitente.isEmpty ? cuenta.usuario : cuenta.remitente

        let cola = DispatchQueue(label: "ec.bto.btodicta.smtp")
        let opciones = NWProtocolTCP.Options()
        opciones.connectionTimeout = 20
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: opciones)
        let conexion = NWConnection(host: .init(cuenta.host),
                                    port: .init(integerLiteral: UInt16(cuenta.puerto)),
                                    using: params)
        let sesion = Sesion(conexion: conexion, cola: cola)

        // Una sola entrega, pase lo que pase. `receive` espera indefinidamente
        // si el servidor no contesta nunca, así que el tope no es un lujo: sin
        // él, un servidor mudo deja la comprobación colgada para siempre.
        var entregado = false
        let candado = NSLock()
        func terminar(_ r: Result<String, Fallo>) {
            candado.lock()
            let primera = !entregado
            entregado = true
            candado.unlock()
            guard primera else { return }
            conexion.cancel()
            DispatchQueue.main.async { completion(r) }
        }
        let tope = Double(max(20, cuerpo.utf8.count / 200_000 + 30))
        cola.asyncAfter(deadline: .now() + tope) {
            terminar(.failure(.tiempo("\(Int(tope)) s sin completar el envío")))
        }

        conexion.stateUpdateHandler = { estado in
            switch estado {
            case .failed(let e): terminar(.failure(.conexion(e.localizedDescription)))
            case .waiting(let e): terminar(.failure(.conexion(e.localizedDescription)))
            case .ready:
                // Diálogo SMTP completo, paso a paso: cada respuesta se
                // comprueba y el primer código inesperado corta con su texto.
                sesion.leer("saludo inicial", esperado: [220]) { r in
                    guard case .success = r else { terminar(r.mapError { $0 }); return }
                    let pasos: [(String, String, [Int])] = [
                        ("EHLO btodicta.local", "presentación (EHLO)", [250]),
                        ("AUTH LOGIN", "inicio de autenticación", [334]),
                        (Data(cuenta.usuario.utf8).base64EncodedString(), "usuario", [334]),
                        (Data(cuenta.clave.utf8).base64EncodedString(), "clave", [235]),
                        ("MAIL FROM:<\(de)>", "remitente", [250]),
                    ]
                    sesion.encadenar(pasos) { r in
                        guard case .success = r else { terminar(r); return }
                        let aDestinos = dest.map { ("RCPT TO:<\($0)>", "destinatario \($0)", [250, 251]) }
                        sesion.encadenar(aDestinos) { r in
                            guard case .success = r else { terminar(r); return }
                            sesion.encadenar([("DATA", "apertura del mensaje", [354])]) { r in
                                guard case .success = r else { terminar(r); return }
                                let mensaje = armar(de: de, para: dest, asunto: asunto, cuerpo: cuerpo)
                                sesion.encadenar([(mensaje + "\r\n.", "entrega del mensaje", [250])]) { r in
                                    if case .success(let ok) = r {
                                        sesion.mandarSinEsperar("QUIT")
                                        terminar(.success(ok))
                                    } else { terminar(r) }
                                }
                            }
                        }
                    }
                }
            default: break
            }
        }
        conexion.start(queue: cola)
    }

    /// Mensaje en formato RFC 5322, con acentos correctos. El cuerpo se manda en
    /// UTF-8 con codificación en base64 para que ningún servidor lo estropee.
    private static func armar(de: String, para: [String], asunto: String, cuerpo: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        let asuntoCodificado = "=?UTF-8?B?\(Data(asunto.utf8).base64EncodedString())?="
        let cuerpo64 = Data(cuerpo.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])
        return """
        From: BtoDicta <\(de)>\r
        To: \(para.joined(separator: ", "))\r
        Subject: \(asuntoCodificado)\r
        Date: \(f.string(from: Date()))\r
        MIME-Version: 1.0\r
        Content-Type: text/plain; charset=UTF-8\r
        Content-Transfer-Encoding: base64\r
        X-Mailer: BtoDicta \(Version.numero)\r
        \r
        \(cuerpo64)
        """
    }

    /// Estado de una conversación SMTP: manda una orden y espera su respuesta.
    private final class Sesion {
        let conexion: NWConnection
        let cola: DispatchQueue
        private var buffer = ""

        init(conexion: NWConnection, cola: DispatchQueue) {
            self.conexion = conexion; self.cola = cola
        }

        func mandarSinEsperar(_ orden: String) {
            conexion.send(content: Data((orden + "\r\n").utf8), completion: .contentProcessed { _ in })
        }

        /// Manda una orden y comprueba que el código de respuesta sea el esperado.
        func paso(_ orden: String, _ nombre: String, _ esperado: [Int],
                  _ cb: @escaping (Result<String, Fallo>) -> Void) {
            CorreoSMTP.tz("→ \(nombre): \(orden.count > 60 ? String(orden.prefix(40)) + "…" : (nombre == "clave" || nombre == "usuario" ? "<oculto>" : orden))")
            // Captura FUERTE a propósito: con `[weak self]` la sesión moría a
            // mitad del diálogo y la respuesta del servidor se perdía en
            // silencio —la conversación se quedaba colgada tras el EHLO—. La
            // sesión vive lo que dure el envío y la suelta `terminar`.
            conexion.send(content: Data((orden + "\r\n").utf8), completion: .contentProcessed { e in
                if let e { cb(.failure(.conexion(e.localizedDescription))); return }
                self.leer(nombre, esperado: esperado, cb)
            })
        }

        func encadenar(_ pasos: [(String, String, [Int])],
                       _ cb: @escaping (Result<String, Fallo>) -> Void) {
            guard let primero = pasos.first else { cb(.success("")); return }
            paso(primero.0, primero.1, primero.2) { [weak self] r in
                switch r {
                case .failure: cb(r)
                case .success: self?.encadenar(Array(pasos.dropFirst()), cb)
                }
            }
        }

        /// Lee hasta tener una respuesta completa. SMTP admite varias líneas:
        /// la última lleva un espacio tras el código, las intermedias un guion.
        func leer(_ nombre: String, esperado: [Int],
                  _ cb: @escaping (Result<String, Fallo>) -> Void) {
            conexion.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { datos, _, fin, error in
                if let error { cb(.failure(.conexion(error.localizedDescription))); return }
                CorreoSMTP.tz("   crudo[\(nombre)] bytes=\(datos?.count ?? -1) fin=\(fin)")
                if let datos, !datos.isEmpty { self.buffer += String(decoding: datos, as: UTF8.self) }
                // Una respuesta SMTP puede venir en varias líneas: las
                // intermedias llevan guion tras el código («250-SIZE») y la
                // ÚLTIMA un espacio («250 HELP»). Se busca esa línea
                // terminadora en cualquier posición en vez de exigir que sea
                // literalmente la última del buffer: un salto de línea suelto,
                // un fragmento a medias o un final sin `\r\n` bastaban antes
                // para que el diálogo se quedara esperando para siempre.
                func esTerminadora(_ l: String) -> Bool {
                    let c = Array(l)
                    return c.count >= 4 && c[0].isNumber && c[1].isNumber && c[2].isNumber && c[3] == " "
                }
                let lineas = self.buffer
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let ultima = lineas.last(where: esTerminadora) else {
                    if fin { cb(.failure(.conexion("el servidor cerró la conexión durante: \(nombre)"))); return }
                    self.leer(nombre, esperado: esperado, cb)   // faltan líneas
                    return
                }
                self.buffer = ""
                let codigo = Int(ultima.prefix(3)) ?? 0
                let texto = String(ultima.dropFirst(4))
                CorreoSMTP.tz("← \(nombre): \(codigo) \(texto.prefix(70))")
                if esperado.contains(codigo) { cb(.success(texto)); return }
                // 535 y 534 son inequívocamente credenciales; el resto se informa
                // con su código para que el usuario pueda buscarlo.
                if [535, 534, 530].contains(codigo) || nombre == "clave" {
                    cb(.failure(.autenticacion("\(codigo) \(texto)")))
                } else {
                    cb(.failure(.rechazo(paso: nombre, codigo: codigo, texto: texto)))
                }
            }
        }
    }
}
