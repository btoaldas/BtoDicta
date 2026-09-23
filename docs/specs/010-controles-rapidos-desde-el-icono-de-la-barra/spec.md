# Spec 010 — Controles rápidos desde el icono de la barra

- Estado: Borrador
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-22
- Modifica: ninguna
- Aprobada por: PENDIENTE
- Rama: `main`

## 1. Problema y propósito

Lo que cuesta ir a Ajustes, no se hace. El 2026-09-22, en una reunión de una hora,
el dictado se cerraba solo cada pocos segundos y la única forma de evitarlo era
abrir Ajustes y cambiar un deslizador — en mitad de la reunión, delante de gente.
No se hizo, y la reunión quedó troceada en once grabaciones sueltas.

Lo mismo por el otro lado: hay ratos en que la bitácora no debería mirar nada, y
apagarla exige entrar, buscar el interruptor y acordarse de volver a encenderlo.
Nadie lo hace, así que se graba lo que no se quería.

Esta spec pone dos controles donde ya se mira: **el icono de la barra**. Un modo
reunión que no interrumpe nunca, y una pausa de la bitácora con vuelta automática.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Usuario de BtoDicta | Quien dicta y tiene la bitácora encendida | Cambia el comportamiento en un clic, sin salir de lo que está haciendo, y ve de un vistazo en qué estado está |

## 3. Alcance

### Incluye

- **Modo reunión**: mientras esté puesto, el dictado no se cierra por silencio ni
  por duración, y no interrumpe con avisos.
- Activarlo y quitarlo desde el menú del icono, **también con un dictado en curso**.
- **Estado visible en el icono**, distinto del normal, sin abrir nada.
- **Pausa de la bitácora** por un rato elegido, con vuelta automática y aviso.
- Ver en el menú cuánto audio hay pendiente de transcribir mientras se graba.

### No incluye (con razón)

- **Transcribir por tramos mientras se graba.** Es lo que hace viable una sesión
  de horas sin una factura de golpe al final, y cambia el motor de transcripción:
  orden, costura entre tramos y armado del texto. Va en la spec 011. Aquí solo se
  **enseña** cuánto hay pendiente, para que el coste se vea antes de soltar.
- **Mejorar lo que el micrófono capta.** El modo reunión evita que se corte; no
  hace audible lo inaudible. Para una reunión remota ya existe la grabación del
  audio del sistema; para una presencial, la mejora es un micrófono.
- Programar el modo reunión por calendario o por aplicación al frente.

## 4. Requerimientos funcionales

### RF-01 — Modo reunión desde el icono

- Actor: usuario de BtoDicta
- Acción: abre el menú del icono y activa «Modo reunión»
- Resultado: el dictado deja de cerrarse por silencio y por duración, y deja de
  avisar, hasta que él lo quite
- Medida: con el modo puesto, un dictado sobrevive más de 60 min sin voz
- Prioridad: P1
- Criterio de aceptación:
  - Dado el modo reunión activo y un dictado en curso
  - Cuando pasan más segundos sin voz que el límite configurado
  - Entonces el dictado sigue abierto y no aparece ningún aviso

### RF-02 — Se puede activar con el dictado ya empezado

- Actor: usuario de BtoDicta
- Acción: se acuerda a mitad de la reunión y lo activa entonces
- Resultado: se aplica al dictado en curso, sin cortarlo ni reiniciarlo
- Medida: activar el modo con un dictado abierto no interrumpe la grabación ni
  pierde un solo segundo de audio
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado en curso a punto de cerrarse por silencio
  - Cuando se activa el modo reunión desde el menú
  - Entonces no se cierra, y el audio anterior sigue en la misma grabación

### RF-03 — El icono dice en qué estado está

- Actor: usuario de BtoDicta
- Acción: mira la barra de menús
- Resultado: distingue sin abrir nada si está en modo normal, en modo reunión o
  con la bitácora pausada
- Medida: tres estados con símbolo distinto, legibles a simple vista
- Prioridad: P1
- Criterio de aceptación:
  - Dado el modo reunión activo
  - Cuando el usuario mira la barra
  - Entonces el icono es distinto del normal, sin desplegar el menú
- Nota: sin esto, el modo reunión es el fallo de los ocho minutos al revés — se
  queda puesto y graba horas que nadie quería.

### RF-04 — Pausar la bitácora por un rato

- Actor: usuario de BtoDicta
- Acción: elige en el menú «No mirar durante…» con una duración
- Resultado: la bitácora deja de grabar audio y de capturar pantalla ese rato
- Medida: durante la pausa, 0 anotaciones nuevas en la bitácora
- Prioridad: P1
- Criterio de aceptación:
  - Dado que se activó una pausa de 30 minutos
  - Cuando pasan 10 minutos
  - Entonces no hay ni una anotación nueva de audio ni de pantalla

### RF-05 — La pausa vuelve sola

- Actor: usuario de BtoDicta
- Acción: no hace nada al terminar el rato elegido
- Resultado: la bitácora se reanuda sola y lo dice
- Medida: al vencer el plazo se reanuda en menos de 60 s, con aviso
- Prioridad: P1
- Criterio de aceptación:
  - Dado que la pausa venció
  - Cuando pasa un minuto desde el vencimiento
  - Entonces la bitácora está grabando otra vez y hubo un aviso
- Nota: una pausa que no vuelve no es una pausa, es un apagado disfrazado — y no
  se descubre hasta que se busca material que no existe.

### RF-06 — La pausa sobrevive a un reinicio

- Actor: usuario de BtoDicta
- Acción: pausa una hora y la aplicación se reinicia por cualquier motivo
- Resultado: la pausa sigue vigente hasta su hora, y luego se reanuda
- Medida: tras reiniciar durante una pausa, sigue pausada y vence a su hora
- Prioridad: P2
- Criterio de aceptación:
  - Dado que se activó una pausa de una hora hace diez minutos
  - Cuando la aplicación se reinicia
  - Entonces sigue pausada y le quedan unos cincuenta minutos

### RF-07 — Cuánto audio hay pendiente de transcribir

- Actor: usuario de BtoDicta
- Acción: abre el menú durante un dictado largo
- Resultado: ve los minutos grabados y el tamaño pendiente de transcribir
- Medida: el menú muestra duración y megabytes acumulados, actualizados al abrirlo
- Prioridad: P2
- Criterio de aceptación:
  - Dado un dictado de más de diez minutos en curso
  - Cuando se abre el menú del icono
  - Entonces se ven los minutos y el tamaño que se transcribirá al soltar
- Nota: sustituye provisionalmente a la transcripción por tramos (spec 011). Hasta
  que exista, esto es lo único que hace visible el coste antes de pagarlo.

### RF-08 — Quitar el modo reunión devuelve el comportamiento de siempre

- Actor: usuario de BtoDicta
- Acción: desactiva el modo reunión
- Resultado: vuelven el corte por silencio, el tope y los avisos, con los valores
  que el usuario tenía configurados
- Medida: los ajustes previos se recuperan intactos; el modo no los sobrescribe
- Prioridad: P1
- Criterio de aceptación:
  - Dado un usuario con corte de silencio en 15 s
  - Cuando activa el modo reunión y luego lo quita
  - Entonces su ajuste sigue siendo 15 s
- Nota: el modo **no toca la configuración**; la ignora mientras está puesto. Un
  modo que escribe en los ajustes del usuario los pierde el día que falla.

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Usabilidad | Activar el modo reunión cuesta **2** interacciones desde cualquier aplicación: abrir el menú y pulsar | Contado sobre la interfaz |
| RNF-02 | Fiabilidad | La pausa vence y se reanuda con un error menor de **60 s**, incluso tras reiniciar | Cronometrado |
| RNF-03 | Visibilidad | Los **3** estados se distinguen en el icono sin abrir el menú | Captura de los tres |
| RNF-04 | Seguridad de datos | Activar o quitar el modo reunión produce **0** cambios en las claves de configuración del usuario | Huella de `config.json` antes y después |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| Se activa el modo reunión sin dictado en curso | Queda armado para el siguiente | RF-01 |
| El dictado termina con el modo puesto | El modo sigue puesto y el icono lo sigue diciendo | RF-03 |
| Se pausa la bitácora con un dictado en curso | El dictado no se toca: son cosas distintas | RF-04 |
| La aplicación se cierra con el modo reunión puesto | Al abrir sigue puesto, y el icono lo dice | RF-03 |
| Se pausa la bitácora estando ya pausada | Se sustituye el plazo, no se acumulan | RF-04 |
| El equipo se suspende durante una pausa | Al despertar se comprueba la hora real: si venció, se reanuda | RF-05 |

## 7. Datos y cumplimiento

- Ningún dato nuevo. Se guardan dos marcas de estado en la configuración local:
  si el modo reunión está puesto, y hasta qué hora está pausada la bitácora.
- El efecto de la pausa es **reducir** lo que se registra, nunca ampliarlo.
- El modo reunión hace lo contrario —graba más tiempo— y por eso el RF-03 es P1:
  lo que amplía la captura tiene que verse.

## 8. Supuestos y dependencias

- **Supone** que el corte por silencio y el tope de duración siguen viviendo en el
  temporizador del dictado, donde se les puede pedir que no actúen.
- **Depende** de `ContinuoBitacora` para suspender y reanudar la captura; la
  cesión del micrófono al dictado ya existe y no se toca.
- **Depende** del icono de la barra, que ya tiene estados (reposo, grabando).
- **No depende** de la spec 011: si nunca se hiciera, el modo reunión funciona
  igual, solo que la transcripción sigue siendo una sola al final.

## 9. Criterios de aceptación de la spec

- Ningún camino de esta spec escribe en los ajustes del usuario (RNF-04).
- Cada RF tiene prueba, y cada prueba se ha visto **dar rojo** sin la funcionalidad.
- Con el modo reunión quitado, el comportamiento es byte a byte el de antes.

## 10. Decisiones y aclaraciones

### Sesión 2026-09-22

- P: ¿Cuándo se apaga solo el modo reunión? → R: **hasta que yo lo apague, con el
  icono gritando** (decisión de Alberto). Sin límite de horas.
- P: ¿Cómo se transcriben veinte horas? → R: **a trozos mientras se graba**
  (decisión de Alberto). Por tamaño, va a la spec 011; aquí queda el RF-07 que
  hace visible lo pendiente mientras tanto.
- Petición literal recogida: «podría hacer clic ahí mismo y podría decir no
  bitácora por media hora, no bitácora por todo el día, por el tiempo que yo
  quiera».
- Petición literal recogida: «así sea que estén hablando a dos kilómetros y se
  escucha apenas, pues que siga grabando».
- Advertido y aceptado: el modo reunión evita el corte, **no** mejora lo que el
  micrófono capta.

## 11. Historial de cambios sobre la spec aprobada

(ninguno todavía)
