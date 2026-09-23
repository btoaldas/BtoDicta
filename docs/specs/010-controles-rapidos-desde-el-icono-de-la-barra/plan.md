# Plan técnico 010 — Controles rápidos desde el icono de la barra

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Aprobado por: Alberto — 2026-09-22 — «si» (a «¿Apruebo el plan y paso a las tareas?»)

## 1. Lo que hay hoy, mirado antes de planificar

| Pieza | Dónde | Qué aporta |
|---|---|---|
| Icono y sus estados | `AppDelegate.setIcono`, `enum EstadoIcono { reposo, grabando, procesando }` | Ya cambia de símbolo y hace latir el icono al grabar |
| Menú del icono | `AppDelegate`, construido una vez (~línea 4503) | Se refresca en `menuWillOpen` **por etiqueta**, no reconstruyendo |
| Corte por silencio y tope | Temporizador del dictado | Los dos sitios que el modo reunión tiene que desactivar |
| Suspender la bitácora | `ContinuoBitacora.suspender` / `recuperarMicrofono` | Existe, pero para **ceder el micrófono al dictado**, no como pausa del usuario |

Dos consecuencias:

- **El patrón del menú ya está resuelto**: elementos con `tag`, actualizados en
  `menuWillOpen`. Los nuevos siguen ese patrón y no se reconstruye nada.
- **Lo de `ContinuoBitacora.suspender` no sirve tal cual.** Esa suspensión es una
  cesión temporal para que dicte el usuario, y el propio dictado la revierte al
  terminar. Una pausa del usuario tiene otra vida y otra autoridad: si se
  reutilizara la misma bandera, el final de un dictado cancelaría la pausa.

## 2. Comprobación contra la constitución

- [x] **Nivel P.** Prueba por RF, verificación con segundo ángulo.
- [x] **Features parametrizables.** Las duraciones de pausa salen de una lista
      configurable; el modo reunión se puede quitar en cualquier momento.
- [x] **Un valor de fábrica peligroso es un fallo.** De fábrica no hay modo
      reunión ni pausa: el comportamiento es el de siempre.
- [x] **Avisar antes de cambiar.** La pausa avisa al empezar y al volver.
- [x] **Lo que amplía la captura tiene que verse.** RF-03 es P1 por eso.
- [x] **Sin secretos ni datos personales.** Dos marcas de estado y nada más.
- [x] **Tres capas.** El estado es un modelo sin interfaz, el temporizador lo
      hace vencer, y el menú y el icono solo lo muestran.
- [x] **No se reescriben los ajustes del usuario.** El modo los ignora mientras
      está puesto; no los toca.

## 3. Componentes

```
Sources/BtoDicta/
  ModoRapido.swift        estado de reunión y de pausa, sin interfaz   (nuevo)
  AppDelegate.swift       menú, icono y los dos frenos del dictado     (modificado)
  ContinuoBitacora.swift  respetar la pausa del usuario                (modificado)
Tests/BtoDictaTests/
  ModoRapidoTests.swift                                                (nuevo)
scripts/
  qa-modo-rapido.py       el guard de que no se tocan los ajustes      (nuevo)
```

### 3.1 El estado (`ModoRapido`)

Dos claves nuevas, y solo dos:

| Clave | Tipo | Para qué |
|---|---|---|
| `modo_reunion` | Bool | Si está puesto. Sobrevive al reinicio (RF-03, caso límite) |
| `bitacora_pausada_hasta` | Double (época) | **Un instante, no una cuenta atrás** |

**Se guarda el instante de vencimiento, no los minutos que faltan.** Una cuenta
atrás se para con la aplicación cerrada y con el equipo suspendido: una pausa de
media hora duraría media hora *de aplicación abierta*, que no es lo que nadie
entiende por media hora. Con un instante, cerrar, reiniciar o suspender no altera
cuándo vence (RF-06 y el caso límite de la suspensión).

### 3.2 El vencimiento

Un `DispatchSourceTimer` en su propia cola comprueba cada 15 s si la pausa venció.
No un `Timer` en el bucle principal: ese ya falló antes en este proyecto —añadido
desde un hilo de fondo, a veces no quedaba registrado, y el apagado del motor de
embeddings «funcionaba a ratos», que es la peor forma de fallar.

Se comprueba **contra el reloj**, no descontando. Así el despertar tras una
suspensión no necesita ningún tratamiento especial: o ya venció, o no.

### 3.3 Los dos frenos del dictado

`ModoRapido.enReunion` se consulta en el temporizador del dictado, en los tres
sitios que hoy interrumpen: aviso periódico, tope de duración y corte por
silencio. No se tocan los valores del usuario: se saltan las ramas (RF-08).

### 3.4 El icono

`setIcono` ya elige símbolo según el estado. Se le añade la consulta de las dos
banderas, en este orden de prioridad:

1. **Bitácora pausada** — es lo que apaga la captura, y lo que más urge ver.
2. **Modo reunión** — amplía la captura; tiene que verse, pero no tapa lo anterior.
3. El estado de siempre.

## 4. Decisiones, con la alternativa descartada

| # | Decisión | Alternativa descartada | Por qué |
|---|---|---|---|
| D-1 | Guardar el **instante** de vencimiento | Guardar minutos restantes y descontar | Una cuenta atrás se congela con la app cerrada o el equipo suspendido: «media hora» se convertiría en media hora de uso, no de reloj |
| D-2 | Bandera de pausa **propia**, separada de la cesión del micrófono | Reutilizar `ContinuoBitacora.suspender` | Esa cesión la revierte el final del dictado; con una sola bandera, colgar un dictado cancelaría la pausa del usuario |
| D-3 | `DispatchSourceTimer` en cola propia | `Timer` en el bucle principal | Ya falló en este proyecto: registrado desde un hilo de fondo, a veces no se activaba, y el fallo era intermitente |
| D-4 | El modo **ignora** los ajustes, no los sobrescribe | Escribir 0 en el corte de silencio al activar | Un modo que escribe en los ajustes los pierde el día que se cierra mal. El usuario recupera sus 15 s intactos (RF-08) |
| D-5 | El icono prioriza **pausa** sobre reunión | Un símbolo combinado | Dos estados a la vez en un icono de barra no se leen. Se enseña el que más consecuencias tiene: el que apaga la captura |
| D-6 | Elementos de menú con `tag`, refrescados en `menuWillOpen` | Reconstruir el menú al cambiar | Es el patrón que el proyecto ya usa para la actualización y la grabación de pantalla |
| D-7 | La pausa **no** toca el dictado en curso | Pausar las dos cosas a la vez | Son cosas distintas y el usuario las pidió por separado; mezclarlas sorprende |

A `docs/adr/`: D-1 (instante frente a cuenta atrás) y D-2 (dos banderas y no una).

## 5. Una precisión sobre el RNF-04

El RNF-04 dice «**0** cambios en las claves de configuración del usuario». Tal cual
está escrito sería imposible: el modo reunión y la pausa se guardan en el mismo
`config.json`, y deben sobrevivir a un reinicio.

Lo que el requisito quiere decir —y como se medirá— es que **no cambia ninguna
clave PREEXISTENTE**. Las dos claves nuevas de estado quedan fuera de la medida, y
la comprobación del QA compara todas las demás. Queda anotado aquí porque cambiar
lo que mide un requisito sin escribirlo es lo que convierte una verificación en un
trámite.

## 6. Orden de trabajo, y qué se prueba primero

El riesgo mayor no es el menú: es una **pausa que no vuelve**. Deja de grabarse sin
que nadie lo note, y se descubre buscando material que ya no existe. Va primero.

1. `ModoRapido`: estado, vencimiento por reloj, persistencia + pruebas en rojo.
2. La pausa aplicada de verdad a la bitácora, y su vuelta automática.
3. Los tres frenos del dictado consultando el modo reunión.
4. El icono con sus tres estados.
5. Los elementos del menú.
6. Minutos y tamaño pendiente en el menú (RF-07).
7. Verificación y hito.

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| La pausa no vuelve y nadie se entera | Va primero, con pruebas; vence contra el reloj; el icono lo muestra todo el rato |
| El modo reunión se queda puesto días | RF-03: el icono lo dice sin abrir nada. Decisión consciente de Alberto: sin caducidad |
| Una sesión de horas produce una transcripción enorme y cara | RF-07 lo enseña antes de soltar; la solución real es la spec 011 |
| El modo reunión pisa los ajustes del usuario | D-4: no escribe en ellos, y el QA lo comprueba comparando las claves preexistentes |
| Dos estados a la vez en el icono | D-5: prioridad escrita, no un símbolo mezclado |

## 8. Lo que este plan NO resuelve

- Transcribir por tramos mientras se graba (spec 011).
- Mejorar lo que el micrófono capta.
- Activar el modo reunión solo, por calendario o por aplicación al frente.
