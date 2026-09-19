# Spec 005 — API de transcripción para servicios externos

- Estado: Implementada (0.65.0)
- Tipo: funcionalidad
- Nivel: X
- Fecha: 2026-09-18
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-19 — «continúa con todo bajo goal y loop… ya no necesito que vuelvas a pararte hasta que termines absolutamente todo»
- Rama: `main` (razón en §9)

Origen: `docs/SOLICITUD-API-TRANSCRIPCION-EXTERNA.md` (2026-09-15), reconfirmado
por Alberto el 2026-09-18: «que alguien que quiera ocupar BtoDicta pueda hacerlo
también de una forma transversal, por medio de API en algún otro sistema».

## 1. Problema y propósito

BtoDicta es hoy el único sitio de la Mac con motores de transcripción instalados
y configurados: `whisper.cpp` con `large-v3-turbo` (1,5 GB) en
`~/.btodicta/models`, más las credenciales de veintitrés proveedores en
`~/.btodicta/.env`.

Cuando otro proyecto necesitó transcribir —las notas de voz de WhatsApp de
**BtoWasap**— había tres salidas: duplicar gigabytes de modelos, pagar otro
servicio, o alcanzar los recursos de BtoDicta desde fuera. Se eligió la tercera y
funciona: hay un comando global `transcribir` en `~/.local/bin`, probado con
audio real.

**Pero ese comando conoce las tripas de BtoDicta**: las rutas de los modelos y del
archivo de configuración. El día que BtoDicta reorganice carpetas, renombre un
modelo o mueva dónde guarda una clave, el consumidor se rompe sin avisar y nadie
se entera hasta que alguien pide una transcripción. Es acoplamiento a los
internals en vez de a un contrato — justo lo que la gobernanza de la oficina
desaconseja.

Cuando esto esté hecho, cualquier proyecto de la oficina pide una transcripción
por un contrato estable, BtoDicta puede moverlo todo por dentro sin romper nada,
y las credenciales dejan de viajar fuera de `~/.btodicta`.

## 2. Actores

| Actor | Quién es | Qué gana |
|---|---|---|
| Otro proyecto de la oficina | Hoy BtoWasap; mañana reuniones, subtitulado, dictado por lotes | Transcribe sin duplicar modelos ni contratar otro servicio |
| Quien mantiene BtoDicta | Alberto | Puede reorganizar modelos, rutas y claves sin romper a los consumidores |
| Quien paga las API | Alberto | Una sola cuenta y una sola cascada, no una por consumidor |

## 3. Alcance

### Incluye

- Un contrato estable para pedir la transcripción de un archivo de audio y
  recibir el texto, con qué motor lo produjo y cuánto tardó.
- Elegir motor: local, nube o la cascada automática que ya existe.
- **Pulir texto con IA por el mismo contrato**, con la cascada y las
  cuarentenas que ya existen (decisión de Alberto, 2026-09-18).
- Pasar vocabulario de contexto, porque está medido que sin él las siglas
  institucionales salen mal («WEA» por UEA, «LEVA» por EVA).
- Autorización por token y escucha solo en loopback.
- Reescribir el comando global `transcribir` para que consuma el contrato y deje
  de conocer rutas internas.

### No incluye (con razón)

- **Servir a otra máquina.** El MANIFIESTO excluye «servidor» y «sincronización
  entre equipos»: esto es una tubería entre procesos del mismo Mac, no un
  servicio de red. Si algún día hace falta a distancia, es otra spec.
- Cuentas de usuario, multiusuario o cuotas por consumidor.
- El TTS y el modo agente. El pulido sí entra (arriba); la voz y el agente no.
- Transcripción en vivo por streaming para terceros. El archivo ya cubre el caso
  conocido.

## 4. Requerimientos funcionales

### RF-01 — Transcribir un archivo desde otro proceso

- Actor: otro proyecto de la oficina
- Acción: entrega la ruta de un archivo de audio y pide su texto
- Resultado: recibe el texto, el motor que lo produjo y el tiempo que tardó
- Medida: el mismo audio que hoy transcribe el comando `transcribir` devuelve el
  mismo texto por el contrato nuevo
- Prioridad: P1
- Criterio de aceptación:
  - Dado un archivo de audio de 121 s que el motor local transcribe en 2,74 s
  - Cuando un proceso externo lo pide por el contrato
  - Entonces recibe el texto completo, el nombre del motor y la duración medida

### RF-02 — Elegir motor o dejar que decida la cascada

- Actor: otro proyecto de la oficina
- Acción: indica `local`, `nube` o `automático` al pedir la transcripción
- Resultado: se usa el motor pedido; con `automático` se aplica la cascada y los
  reintentos que BtoDicta ya tiene
- Medida: el motor devuelto en la respuesta coincide con el pedido, y con
  `automático` el salto a nube queda registrado
- Prioridad: P1
- Criterio de aceptación:
  - Dado un motor local que falla
  - Cuando se pidió `automático`
  - Entonces responde la nube y la respuesta dice qué motor acabó produciéndola

### RF-03 — Vocabulario de contexto

- Actor: otro proyecto de la oficina
- Acción: envía una lista de términos junto al audio
- Resultado: el motor los recibe como contexto
- Medida: un audio con «UEA» y «EVA» transcrito con y sin vocabulario da
  resultados distintos, y el correcto es el del vocabulario
- Prioridad: P2
- Criterio de aceptación:
  - Dado un audio que sin vocabulario produce «WEA»
  - Cuando se envía el vocabulario con «UEA»
  - Entonces el texto dice «UEA»

### RF-04 — Nadie sin autorización, y nada fuera de este Mac

- Actor: cualquier proceso de la máquina
- Acción: pide una transcripción sin token válido, o desde fuera del loopback
- Resultado: se rechaza sin transcribir nada
- Medida: petición sin token → rechazada; petición a una interfaz que no sea
  `127.0.0.1` → no llega siquiera
- Prioridad: P1
- Criterio de aceptación:
  - Dado el servicio en marcha
  - Cuando llega una petición sin token o con token equivocado
  - Entonces responde rechazo, no transcribe y lo anota una sola vez

### RF-05 — No se leen rutas arbitrarias del disco

- Actor: un proceso externo, por error o por malicia
- Acción: pide transcribir una ruta que no es un audio suyo
- Resultado: se rechaza
- Medida: rutas fuera de las carpetas permitidas → rechazadas; comprobado con al
  menos un intento de recorrido de directorios
- Prioridad: P1
- Criterio de aceptación:
  - Dado un intento de leer un archivo fuera de las carpetas permitidas
  - Cuando se pide por el contrato
  - Entonces se rechaza sin abrir el archivo

### RF-06 — Las credenciales no salen de BtoDicta

- Actor: el proceso consumidor
- Acción: pide una transcripción de nube
- Resultado: recibe el texto sin haber leído `~/.btodicta/.env`
- Medida: el consumidor funciona sin permiso de lectura sobre ese archivo
- Prioridad: P1
- Criterio de aceptación:
  - Dado un consumidor sin acceso a `~/.btodicta/.env`
  - Cuando pide una transcripción de nube
  - Entonces la recibe igual

### RF-07 — Pulir un texto desde otro proceso

- Actor: otro proyecto de la oficina
- Acción: entrega un texto y pide su versión pulida
- Resultado: recibe el texto pulido y qué proveedor lo produjo
- Medida: el mismo texto pulido por el contrato y por la app coinciden en
  proveedor y en no perder más de la mitad de las letras (la guarda de 0.62.1)
- Prioridad: P2
- Criterio de aceptación:
  - Dado un texto crudo de 600 caracteres
  - Cuando un proceso externo pide pulirlo
  - Entonces recibe el texto pulido y el nombre del proveedor que lo hizo, y si
    ninguno responde recibe el texto original en vez de un error

### RF-08 — El comando global deja de conocer las tripas

- Actor: quien mantiene BtoDicta
- Acción: reorganiza modelos, rutas o claves por dentro
- Resultado: el comando `transcribir` sigue funcionando
- Medida: `grep` sobre el comando no encuentra ninguna ruta de
  `~/.btodicta/models` ni de `.env`
- Prioridad: P1
- Criterio de aceptación:
  - Dado el comando reescrito sobre el contrato
  - Cuando se renombra un modelo dentro de `~/.btodicta/models`
  - Entonces el comando transcribe igual

## 5. Requerimientos no funcionales

Un RNF sin cifra es un deseo.

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | rendimiento | El servicio no retrasa el arranque de BtoDicta más de 200 ms ni añade más de 30 MB en reposo | Mismo método de medición que la spec 001: arranque cronometrado y huella de memoria antes y después |
| RNF-02 | disponibilidad | Una petición externa no degrada un dictado en curso: 0 palabras perdidas y 0 cortes de audio | Dictado de 60 s con una petición externa simultánea; se comparan palabras dictadas y transcritas |
| RNF-03 | usabilidad | Todo rechazo dice su motivo en 1 línea: autorización, ruta, formato o motor caído | 4 peticiones inválidas, una por motivo; cada respuesta nombra el suyo |
| RNF-04 | seguridad | 0 peticiones atendidas sin token válido y 0 desde fuera de `127.0.0.1` | Prueba negativa por cada vía, obligatoria por nivel X |

## 6. Casos límite y fallos

- **El que más preocupa:** que la API abra una puerta por la que se cuele algo.
  Un puerto local sin token es alcanzable por cualquier proceso del usuario, y en
  esta Mac hay certificados de firma y credenciales de 23 proveedores. De ahí
  RF-04 y RF-05, ambos P1 y con prueba negativa obligatoria por nivel X.
- **BtoDicta cerrada cuando llega la petición: se rechaza**, con un mensaje que
  diga exactamente eso y cómo arreglarlo. Decidido en §9.
- Dos peticiones a la vez mientras el usuario dicta: ver RNF-02.
- Audio de seis horas por el contrato: aplica el troceo que ya existe.
- El motor local **omitió una frase entera** en un audio real de dos minutos que
  el de nube sí capturó. La cascada no es solo para fallos: es segunda opinión.

## 7. Datos y cumplimiento

- **Ningún dato personal nuevo.** El audio y el texto ya están en la máquina; el
  contrato los mueve entre procesos del mismo usuario, no los saca de ahí.
- **Las credenciales no viajan** (RF-06): siguen en `~/.btodicta/.env`, que solo
  lee BtoDicta.
- **El token del contrato es una credencial**: se registra en Obsidian con ficha
  completa el día que se genere, según la regla dura de la oficina, y nunca en el
  repositorio ni en el registro.
- El audio que pida un consumidor **no entra en la bitácora del usuario** salvo
  que se decida lo contrario: es trabajo de otro proyecto, no dictado propio.
- LOPDP: si un consumidor manda audio de terceros (notas de voz de WhatsApp), la
  responsabilidad del tratamiento es de ese proyecto, no de BtoDicta. Se deja
  dicho, no se controla desde aquí.

## 8. Supuestos y dependencias

- Se apoya en lo que ya existe y está probado: cascada de motores, troceo por
  techo aprendido, cuarentenas y reintentos. **No se duplica nada de eso.**
- Depende de que la spec 001 (memoria del dictado largo) resuelva su segunda
  etapa: hoy transcribir un archivo de seis horas hace una copia de 691 MB en
  memoria. Por el contrato, esa copia la pagaría BtoDicta por cuenta de otro
  proceso. **Conviene cerrar 001 antes o a la vez.**
- El consumidor conocido es BtoWasap, que ya funciona con el comando global; la
  migración es reescribir ese comando (RF-07), no tocar BtoWasap.
- Supone que BtoDicta está corriendo cuando llega la petición (ver §6).

## 9. Decisiones y aclaraciones

### Sesión 2026-09-18

P: ¿el contrato se abre solo a transcripción o se diseña para crecer? → R:
**«transcripción y pulido desde el principio»** (decisión de Alberto). *Objeción
registrada:* se recomendó implementar solo transcripción dejando sitio para
crecer, porque el pulido duplica la superficie que hay que asegurar y probar en
nivel X sin un consumidor que lo pida todavía. Alberto decide abrirlo; se acata y
entra como RF-07 con prioridad P2, para que no bloquee a los P1.

P: ¿qué forma tiene el contrato? → R: **HTTP en loopback con token** (decisión de
Alberto). La forma es solución, así que su detalle vive en `plan.md`; aquí consta
solo la decisión y su fecha.

P: ¿de dónde sale este pedido? → R: de necesitar transcribir notas de voz de
WhatsApp en BtoWasap sin duplicar modelos; Alberto lo reconfirma como pedido
transversal para «alguien que quiera ocupar BtoDicta… por medio de API en algún
otro sistema» (decisión de Alberto).

P: ¿el comando `transcribir` se mueve a este repositorio? → R: no, se queda
fuera hasta que exista la API; entonces se reescribe para consumirla (decisión de
Alberto registrada el 2026-09-15 en la solicitud).

P: ¿qué pasa si la aplicación está cerrada cuando llega una petición? → R: **se
rechaza con un mensaje claro**, no se levanta sola. Decidido por criterio técnico
bajo la autonomía dada el 2026-09-19, y se anota para que conste:

Levantar una aplicación de interfaz desde una petición HTTP es intrusivo —
aparecería en pantalla mientras su dueño está en otra cosa—, tarda lo que tarde
el arranque, y con el motor local aún frío la primera transcripción llegaría
tardísimo. El consumidor sabe mejor que nosotros si quiere esperar: se le dice
que no está en marcha y decide. Si algún día hace falta un servicio que viva sin
la aplicación, eso es otra spec, no un atajo dentro de esta.

P: ¿en qué rama? → R: **`main`**. La misma razón que en la spec 001: cada pieza es
un añadido independiente que no deja la aplicación inservible entre commits, y
Alberto pidió en su día no mantener dos ramas a la vez.

## 8. Datos medidos que sirven al plan

- Motor local, audio de 121 s: **2,74 s** (~43× tiempo real).
- Fish Audio: **$0,006 por minuto**; saldo verificado el 2026-09-15: $46,18.
- **Voxtral Realtime** (2,6 GB, descargado) **no sirve para archivos**: es
  streaming por micrófono. Para archivos haría falta Voxtral Mini 3B con su
  `mmproj` y `llama-server`.
