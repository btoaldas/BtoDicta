# Spec 012 — Red de seguridad del icono y triple fn para el modo reunión

- Estado: Implementada
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-22
- Modifica: ninguna (complementa la 010 y la 011)
- Aprobada por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien y si red de seguridad y funcionalidad»
- Rama: `main`

## 1. Problema y propósito

La spec 011 quita la causa por la que el icono de BtoDicta desaparecía. Pero el
icono puede seguir quedando oculto por motivos ajenos —alguien lo desactiva en
Ajustes, una fila envenenada de antes— y con el modo reunión puesto eso es un
riesgo real: no caduca, y sin icono nadie ve que sigue grabando sin cortes.

Esta spec añade tres cosas que no dependen de ver el icono: un aviso cuando está
oculto, una forma de poner el modo reunión con la tecla del dictado, y un
recordatorio si el modo reunión sigue puesto con el icono oculto.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Usuario de BtoDicta | Quien dicta, a veces en reuniones | Se entera si el icono está oculto, y pone el modo reunión sin buscar ningún menú |

## 3. Alcance

### Incluye

- Detectar que el icono está oculto y avisar una vez, diciendo cómo arreglarlo,
  con «no volver a avisar».
- No avisar en falso: ni con una aplicación a pantalla completa, ni cuando la
  aplicación no registró el icono a propósito (spec 011).
- Triple pulsación de fn para poner o quitar el modo reunión, en el modo toque.
- Recordatorio periódico mientras el modo reunión esté puesto y el icono oculto.

### No incluye (con razón)

- **Arreglar el icono oculto desde la aplicación.** Exige escribir ajustes del
  sistema; la aplicación no lo hace (spec 011, RNF-02). El aviso dice cómo.
- **Triple fn con el dictado ya en marcha, pasada la ventana.** Con el dictado
  grabando, una pulsación de fn lo detiene al instante. Esperar a ver si llegan
  otras dos retrasaría la detección de parada en cada dictado. A mitad de una
  grabación el modo reunión se pone desde el menú del icono o del Dock.
- **Triple fn en el modo «mantener para hablar».** La tercera pulsación no tiene
  sentido si la segunda se mantiene mientras se habla.

## 4. Requerimientos funcionales

### RF-01 — Aviso de icono oculto, una vez

- Actor: usuario de BtoDicta
- Acción: la aplicación está abierta, lanzada por el sistema, y su icono queda oculto
- Resultado: recibe un aviso que dice que el icono no se ve y cómo arreglarlo, con
  la opción de no volver a verlo
- Medida: un aviso por arranque de la aplicación como máximo; ninguno si eligió «no
  volver a avisar»
- Prioridad: P1
- Criterio de aceptación:
  - Dado que el icono lleva oculto el tiempo de gracia con la barra visible
  - Cuando la aplicación lo comprueba
  - Entonces avisa una vez, y no vuelve a avisar en esa sesión

### RF-02 — Sin avisos en falso

- Actor: usuario de BtoDicta
- Acción: usa una aplicación a pantalla completa, o abre BtoDicta desde una terminal
- Resultado: no recibe el aviso de icono oculto
- Medida: 0 avisos con la barra escondida por pantalla completa; 0 avisos si la
  aplicación no registró el icono a propósito
- Prioridad: P1
- Criterio de aceptación:
  - Dado que la barra de menús está escondida
  - Cuando el icono no es visible
  - Entonces no hay aviso

### RF-03 — Triple fn pone o quita el modo reunión

- Actor: usuario de BtoDicta
- Acción: pulsa fn tres veces seguidas
- Resultado: empieza el dictado, y el modo reunión cambia, con confirmación en el
  notch; el dictado sigue
- Medida: la tercera pulsación, si llega dentro de la ventana del doble, cambia el
  modo y no detiene el dictado
- Prioridad: P1
- Criterio de aceptación:
  - Dado que el doble fn acaba de arrancar el dictado
  - Cuando llega una tercera pulsación dentro de la ventana
  - Entonces cambia el modo reunión y el dictado sigue grabando

### RF-04 — El doble fn sigue igual de rápido

- Actor: usuario de BtoDicta
- Acción: pulsa fn dos veces para dictar
- Resultado: el dictado empieza en la segunda pulsación, como hoy
- Medida: 0 ms añadidos al arranque por doble fn
- Prioridad: P1
- Criterio de aceptación:
  - Dado el doble fn de siempre
  - Cuando llega la segunda pulsación
  - Entonces el dictado empieza en ese momento, sin esperar a una tercera

### RF-05 — Pasada la ventana, fn detiene como siempre

- Actor: usuario de BtoDicta
- Acción: pulsa fn con el dictado grabando, pasada la ventana del doble
- Resultado: el dictado se detiene como hoy
- Medida: una pulsación tras la ventana detiene; ninguna se interpreta como triple
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado que empezó hace más que la ventana
  - Cuando llega una pulsación
  - Entonces el dictado se detiene

### RF-06 — Recordatorio si el modo reunión sigue puesto con el icono oculto

- Actor: usuario de BtoDicta
- Acción: deja el modo reunión puesto con el icono oculto
- Resultado: cada 30 minutos recibe un recordatorio de que el modo sigue puesto
- Medida: un recordatorio cada 30 min, parametrizable; ninguno si el icono se ve o
  si el modo reunión está quitado
- Prioridad: P2
- Criterio de aceptación:
  - Dado el modo reunión puesto y el icono oculto
  - Cuando pasan 30 minutos
  - Entonces hay un recordatorio

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Rendimiento | **0 ms** añadidos al arranque del dictado por doble fn | La decisión del doble no cambia; se prueba sobre la decisión pura |
| RNF-02 | Detección | Aviso en menos de **2 min** desde que el icono queda oculto con la barra visible | Arnés que oculta su propio icono |
| RNF-03 | Fiabilidad | **0** avisos con la barra escondida | Prueba sobre la decisión con la barra escondida |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| El icono se oculta un instante y vuelve | No hay aviso: hace falta que siga oculto el tiempo de gracia | RF-01 |
| El usuario elige «no volver a avisar» | No vuelve a avisar, ni tras reiniciar | RF-01 |
| La aplicación no registró el icono a propósito (spec 011) | No hay aviso | RF-02 |
| Una aplicación a pantalla completa esconde la barra | No hay aviso | RF-02 |
| Triple fn con una confirmación en pantalla | Manda la confirmación, como hoy | RF-03 |
| Tres pulsaciones lentas, fuera de ventana | Doble arranca, la tercera detiene: lo de siempre | RF-05 |

## 7. Datos y cumplimiento

- Una clave nueva de preferencia: «no volver a avisar del icono oculto». Otra para
  el intervalo del recordatorio.
- Nada sale del equipo. La aplicación no escribe en ajustes del sistema.

## 8. Supuestos y dependencias

- **Supone** que el sistema informa de que la ventana del icono no es visible
  cuando está oculto: medido con una aplicación de prueba cuyo icono no cabía y con
  otra envenenada, ambas «no visible».
- **Depende** de la spec 011: si la aplicación no registró el icono a propósito, no
  se avisa.
- **Depende** del modo reunión de la spec 010.

## 9. Criterios de aceptación de la spec

- Cada RF con prueba, vista en rojo antes de fiarse de ella.
- El arranque del dictado por doble fn no cambia en nada.

## 10. Decisiones y aclaraciones

### Sesión 2026-09-22

- P: ¿Qué vías? → R: detectar y avisar, atajo y recordatorio, las tres, **después**
  de resolver la causa (decisión de Alberto).
- P: ¿Qué atajo? → R: **triple pulsación de fn** (decisión de Alberto). Se advirtió
  de que choca con el doble; se resuelve interpretando la tercera solo dentro de la
  ventana del doble que acaba de arrancar el dictado, sin retrasar el doble.
- P: ¿Cada cuánto el aviso? → R: **una vez, con «no volver a avisar»** (decisión de
  Alberto).
- Aprobación: «todo si bajo goal y loop hasta resolver y que funcione todo bien y si
  red de seguridad y funcionalidad».

## 11. Historial de cambios sobre la spec aprobada

(ninguno todavía)
