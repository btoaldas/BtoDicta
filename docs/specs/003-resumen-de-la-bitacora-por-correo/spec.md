# Spec 003 — Resumen de la bitácora por correo

- Estado: Implementada (0.61.0 y 0.62.0)
- Tipo: funcionalidad
- Nivel: X
- Fecha: 2026-09-14
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-14 — «hagámoslas todas bajo goal, una por una… puedes utilizar un correo de eztic.ec para probarlo»
- Rama: `spec/003-resumen-bitacora-correo` (gobernanza de rama corta del ROADMAP)

## 1. Problema y propósito

La bitácora transcribe el día entero, pero para saber qué pasó hay que abrirla y
leer trozos sueltos. Lo que falta es que el día llegue **resumido y solo**, al
correo, sin abrir la aplicación: un consolidado hecho con IA —no los archivos
pegados uno tras otro— donde las ideas repetidas aparezcan una vez.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Quien usa BtoDicta | Alberto y cualquier usuario | Recibe el resumen del día en su correo, a la hora que él fije, sin hacer nada |
| Quien configura | El mismo usuario | Pone su propio servidor de correo y comprueba que funciona antes de fiarse |

## 3. Alcance

### Incluye

- Una vista de configuración de correo: servidor SMTP o cuenta del proveedor,
  puerto, usuario, clave, remitente y **destinatarios** que elija el usuario.
- Un **botón de prueba** que dice si funcionó o no y, si no, **por qué**.
- Registro de cada envío y de cada fallo.
- Consolidado del periodo con IA: un solo texto, sin repetir ideas, con formato.
- Envío automático en **uno o varios horarios** elegidos por el usuario, cada uno
  con su **periodo** (el día en curso, el día anterior, la semana).
- Envío manual a demanda.

### No incluye (con razón)

- Un servidor de correo propio: el usuario pone el suyo. BtoDicta no manda nada
  desde infraestructura del proyecto.
- Adjuntar el audio: el correo lleva texto; el audio se queda en el equipo.

## 4. Requerimientos funcionales

### RF-01 — Configurar el correo de salida

- Actor: quien configura
- Acción: introduce servidor, puerto, seguridad, usuario, clave y remitente
- Resultado: BtoDicta guarda esos datos y puede enviar con ellos
- Medida: los datos quedan guardados y la prueba de envío llega
- Prioridad: P1
- Criterio de aceptación:
  - Dado un servidor de correo válido
  - Cuando se guardan los datos y se pulsa la prueba
  - Entonces llega un correo de prueba al destinatario

### RF-02 — La prueba dice qué falló y por qué

- Actor: quien configura
- Acción: pulsa la prueba con algún dato mal
- Resultado: se le dice en claro qué falló — puerto, autenticación, clave,
  dirección, certificado o red
- Medida: el mensaje nombra la causa concreta, no un «error» genérico
- Prioridad: P1
- Criterio de aceptación:
  - Dado un puerto equivocado, una clave mala y un destinatario inválido
  - Cuando se prueba cada caso
  - Entonces cada uno da un mensaje distinto que identifica su causa

### RF-03 — Elegir destinatarios

- Actor: quien configura
- Acción: indica a qué direcciones quiere que llegue
- Resultado: el resumen se envía a todas ellas
- Medida: llega a cada dirección configurada
- Prioridad: P1
- Criterio de aceptación:
  - Dado dos destinatarios configurados
  - Cuando se envía un resumen
  - Entonces llega a los dos

### RF-04 — Consolidar el periodo con IA, sin repetir

- Actor: BtoDicta
- Acción: toma lo ya transcrito de la bitácora en el periodo pedido
- Resultado: produce **un solo** texto consolidado, sin repetir ideas
- Medida: el resumen no contiene la misma idea dos veces y cubre el periodo
- Prioridad: P1
- Criterio de aceptación:
  - Dado un día con varias entradas que hablan de lo mismo
  - Cuando se consolida
  - Entonces la idea aparece una sola vez y no se pierde ninguna otra

### RF-05 — Horarios automáticos, con su periodo

- Actor: quien configura
- Acción: define uno o varios horarios, cada uno con su periodo
- Resultado: a esa hora llega el resumen de ese periodo
- Medida: el correo llega dentro de los cinco minutos siguientes a la hora fijada
- Prioridad: P1
- Criterio de aceptación:
  - Dado un horario a las 20:00 con «el día de hoy» y otro a las 07:00 con «el
    día anterior»
  - Cuando llegan esas horas
  - Entonces llegan dos correos, cada uno con su periodo

### RF-06 — Enviar ahora, a mano

- Actor: quien usa BtoDicta
- Acción: pide el resumen del periodo que elija
- Resultado: se envía en ese momento
- Medida: el correo sale sin esperar a un horario
- Prioridad: P2
- Criterio de aceptación:
  - Dado un periodo elegido a mano
  - Cuando se pulsa enviar
  - Entonces el correo llega y queda registrado

### RF-07 — Queda registrado

- Actor: quien diagnostica un problema
- Acción: revisa el registro tras un envío o un fallo
- Resultado: encuentra cuándo se envió, a quién, con qué periodo y, si falló, por qué
- Medida: una línea por intento, con resultado y causa
- Prioridad: P1
- Criterio de aceptación:
  - Dado un envío correcto y otro fallido
  - Cuando se mira el registro
  - Entonces ambos aparecen, distinguibles y con su causa

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Seguridad | La clave del correo se guarda con permisos 0600 y **0 apariciones** en el repositorio, el registro o la interfaz | Revisión del archivo y del registro |
| RNF-02 | Disponibilidad | Un fallo de envío reintenta hasta 3 veces y nunca bloquea el dictado | Prueba con servidor caído |
| RNF-03 | Rendimiento | Consolidar un día completo tarda menos de 120 s | Medición registrada |
| RNF-04 | Usabilidad | La prueba de envío devuelve veredicto en menos de 30 s | Medición |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| No hay nada transcrito en el periodo | No se envía un correo vacío; se registra como omitido | RF-04 |
| La IA no responde o devuelve el texto cortado | Se envía el material sin consolidar: el correo es para enterarse, y un resumen crudo informa más que un correo que nunca llegó | RF-04 |
| El servidor de correo rechaza la autenticación a las 07:00 | Se reintenta y se registra la causa; no se pierde el resumen | RF-07 |
| El equipo está dormido a la hora fijada | Se envía al despertar: el reloj dispara en la hora fijada **o después**, una sola vez por horario y día | RF-05 |
| Hay varios destinatarios y uno rebota | Los demás reciben igual; el rebote se registra | RF-03 |

## 7. Datos y cumplimiento

- Datos que trata: el texto ya transcrito de la bitácora del usuario, su
  dirección de correo y la de sus destinatarios.
- Datos personales: sí, y de terceros si envía a otras personas. **El correo saca
  del equipo contenido que hoy no sale.** Debe quedar claro en la interfaz qué se
  envía y a quién, y el envío automático no puede quedar activado sin que el
  usuario lo haya puesto.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- La bitácora ya transcribe y guarda el texto por día; esta spec lo **consume**,
  no lo produce.
- `ContinuoResumen` ya sabe trocear texto largo y resumir con la cascada de IA.
- El envío por SMTP no depende de ningún servicio del proyecto.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-14

- P: ¿Qué se envía? → R: el consolidado del periodo hecho con IA, «no es
  solamente unir los archivos resultantes de la bitácora, sino… que no se repitan
  las ideas… bien pulidito, bien con formato» (decisión del responsable del
  producto)
- P: ¿Quién pone el correo? → R: el usuario, «tanto el SMTP o la conexión con
  Gmail o con su proveedor», y elige destinatarios (decisión del responsable del
  producto)
- P: ¿Hace falta comprobación? → R: sí, con causa concreta — «si no valió el
  puerto, si no valió la llamada, si no valió el correo, si no valió la clave»
  (decisión del responsable del producto)
- P: ¿Cuándo se envía? → R: parametrizable, varios horarios y varios periodos —
  «quiero que me llegue tanto a las ocho de la noche como… a las siete de la
  mañana, y de qué día» (decisión del responsable del producto)
- P: ¿Lleva imagen o logotipo? → R: se envía en **texto plano** en esta primera
  versión. Un correo en HTML con imágenes incrustadas es bastante más propenso a
  acabar en spam y a verse roto según el cliente, y aquí lo que importa es que el
  resumen llegue y se lea. Queda anotado para una segunda versión, cuando el
  canal esté rodado (objeción registrable: no se consultó por ser reversible)

## 10. Estado de implementación

| RF | Estado | Evidencia |
|---|---|---|
| RF-01 — configurar el correo | **Hecho** | Configuración → Ajustes, sección «Resumen de la bitácora por correo» |
| RF-02 — la prueba dice por qué falló | **Hecho** | `BTODICTA_CORREOTEST=1`: clave mala → «535 Incorrect authentication data»; puerto mal → error de conexión; destinatario inválido → lo nombra. Cada uno con su consejo |
| RF-03 — destinatarios | **Hecho** | Campo separado por comas |
| RF-04 — consolidar con IA sin repetir | **Hecho** | Envío real de 23 204 caracteres de bitácora consolidados |
| RF-05 — horarios con su periodo | **Hecho del todo en 0.62.0** | Primera versión tenía UN periodo común para todos los horarios, que no expresaba el requisito. Ahora son reglas independientes: cada una con su hora, su periodo y sus días (incluido «los sábados» y «entre semana»), se añaden y se quitan desde la interfaz |
| RF-06 — enviar a mano | **Hecho** | Menú de la barra → «Enviar resumen por correo» |
| RF-07 — queda registrado | **Hecho** | Una línea por intento con causa; traza del diálogo con `BTODICTA_SMTPDEBUG=1` |

Cuenta de pruebas creada para esto: `btodicta@eztic.ec` (Hestia de EZTIC),
registrada en la bóveda personal. La clave vive solo en `~/.btodicta/.env`.
