# Spec 007 — Asistente de exclusiones con semillas y modo de trabajo

- Estado: Aprobada
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-21
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-21 — «si dale» (a «¿Apruebo la spec y paso al plan?»)
- Rama: `main` (como el resto del trabajo reciente del proyecto)

## 1. Problema y propósito

La lista de lo que la bitácora no debe mirar **nace vacía**, y llenarla a mano son
decenas de decisiones sueltas. Por eso no se hace: el 2026-09-20 se pidieron siete
exclusiones, se aplicaron cinco y dos quedaron fuera durante días sin que nadie lo
notara — las dos eran aplicaciones de escritorio y fueron a la lista equivocada.

Un valor de fábrica vacío no protege a nadie. Esta spec convierte «configurar las
exclusiones» en un puñado de síes: el asistente propone categorías completas ya
marcadas, el usuario desmarca lo que no quiera y acepta una vez. Y añade la forma
contraria de trabajar —no mirar nada salvo lo que se autorice— para quien la
prefiera.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Usuario de BtoDicta | Quien dicta y tiene la bitácora encendida | Deja la bitácora configurada en una pantalla en vez de en veinte decisiones, y puede invertir la postura entera si le conviene |

## 3. Alcance

### Incluye

- Asistente con semillas agrupadas por categoría, **ya marcadas**, que no cambia
  nada hasta que se acepta.
- Desplegar una categoría y afinar dominio por dominio dentro de ella.
- **Modo de trabajo parametrizable**: «mirar todo salvo lo excluido» (de fábrica)
  o «no mirar nada salvo lo incluido».
- Semillas equivalentes para **aplicaciones de escritorio**, no solo dominios.
- Apertura automática la primera vez y reapertura desde Ajustes.
- Semillas actualizables con la app sin pisar lo que el usuario ya decidió.

### No incluye (con razón)

- **Clasificar automáticamente si una página desconocida es de contenido adulto.**
  Exige consultar un servicio o embarcar un clasificador, y son dos discusiones
  distintas (coste, privacidad, falsos positivos). Aquí entra la categoría con su
  lista; la detección de lo que no está en la lista queda para otra spec, por
  decisión expresa de Alberto: «eso sería otro feature adicional; primero
  resolvamos lo que estamos resolviendo».
- **Sincronizar estas listas con las de la extensión del navegador.** Son dos
  listas con significados distintos (una impide grabar, la otra impide que la URL
  salga del navegador). Queda constatado en la verificación de la spec 006 como
  decisión pendiente, no se resuelve aquí.
- Exclusiones por horario, por red o por perfil de trabajo.

## 4. Requerimientos funcionales

### RF-01 — Asistente con semillas marcadas que no aplica nada hasta aceptar

- Actor: usuario de BtoDicta
- Acción: abre el asistente y ve las categorías propuestas, todas marcadas
- Resultado: desmarca lo que no quiera y acepta una sola vez; hasta ese momento su
  configuración no ha cambiado
- Medida: el `config.json` es byte a byte idéntico antes de pulsar Aceptar y
  distinto después
- Prioridad: P1
- Criterio de aceptación:
  - Dado un asistente abierto con categorías marcadas
  - Cuando el usuario cierra la ventana sin aceptar
  - Entonces las listas de exclusión quedan exactamente como estaban

### RF-02 — Afinar dentro de una categoría

- Actor: usuario de BtoDicta
- Acción: despliega una categoría y desmarca entradas sueltas
- Resultado: se aplica el resto de la categoría sin la excepción rescatada
- Medida: aceptar una categoría de N entradas con una desmarcada escribe N−1
- Prioridad: P1
- Criterio de aceptación:
  - Dado el despliegue de la categoría «redes sociales»
  - Cuando se desmarca una sola entrada y se acepta
  - Entonces esa entrada no aparece en la lista y las demás sí

### RF-03 — Modo de trabajo parametrizable

- Actor: usuario de BtoDicta
- Acción: elige entre «mirar todo salvo lo excluido» y «no mirar nada salvo lo
  incluido»
- Resultado: el filtro se comporta según el modo elegido
- Medida: en modo restrictivo, una app que no está en la lista de incluidas no se
  graba; en modo permisivo, sí
- Prioridad: P1
- Criterio de aceptación:
  - Dado el modo «no mirar nada salvo lo incluido» con una sola app autorizada
  - Cuando está al frente cualquier otra aplicación
  - Entonces la bitácora no registra
- Nota: de fábrica queda el modo permisivo, el de hoy. Cambiarlo al restrictivo
  apagaría la bitácora de quien actualice sin avisar.

### RF-04 — Semillas para aplicaciones de escritorio

- Actor: usuario de BtoDicta
- Acción: acepta las categorías de aplicaciones propuestas
- Resultado: quedan escritas en la lista de aplicaciones, no en la de títulos
- Medida: aceptar la categoría de reproductores escribe en `bitacora_excluir_apps`
  y deja `bitacora_excluir_titulos` intacta
- Prioridad: P1
- Criterio de aceptación:
  - Dado que se aceptó una semilla de aplicación
  - Cuando esa aplicación está al frente
  - Entonces el veredicto es «fuera» citando la aplicación, no el título
- Nota: este RF nace de un fallo real — dos exclusiones pedidas fueron a la lista
  de títulos, donde nunca podían coincidir.

### RF-05 — Cuándo aparece

- Actor: usuario de BtoDicta
- Acción: abre la app por primera vez con la bitácora encendida, o entra a Ajustes
- Resultado: la primera vez el asistente se ofrece solo; después está siempre
  disponible en Ajustes
- Medida: en un perfil nuevo el asistente aparece una vez; tras aceptarlo o
  descartarlo, no vuelve a aparecer solo
- Prioridad: P2
- Criterio de aceptación:
  - Dado un perfil que ya pasó por el asistente
  - Cuando se reinicia la app
  - Entonces el asistente no se abre solo, y sigue accesible desde Ajustes

### RF-06 — Nada de lo que ponga el asistente queda bloqueado

- Actor: usuario de BtoDicta
- Acción: edita a mano cualquier entrada que haya puesto el asistente
- Resultado: la edición manda; el asistente no la revierte
- Medida: una entrada borrada a mano no reaparece al reabrir el asistente ni al
  reiniciar
- Prioridad: P1
- Criterio de aceptación:
  - Dado que una entrada escrita por el asistente se borró a mano
  - Cuando se reinicia la app
  - Entonces esa entrada sigue sin estar

### RF-07 — Semillas nuevas en versiones posteriores

- Actor: usuario de BtoDicta
- Acción: actualiza la app, que trae semillas nuevas
- Resultado: se le **proponen**; no se aplican solas ni resucitan lo que él quitó
- Medida: tras actualizar, `config.json` no cambia hasta que el usuario acepte
- Prioridad: P2
- Criterio de aceptación:
  - Dado que el usuario desmarcó una semilla en su día
  - Cuando la app se actualiza y esa semilla sigue en el catálogo
  - Entonces no se le vuelve a proponer marcada

### RF-08 — Aviso antes de dejar la bitácora ciega

- Actor: usuario de BtoDicta
- Acción: cambia a «no mirar nada salvo lo incluido» con la lista de incluidos
  vacía
- Resultado: se le advierte de que con eso la bitácora no registrará nada, y ha de
  confirmarlo
- Medida: el cambio no se guarda sin una confirmación explícita
- Prioridad: P1
- Criterio de aceptación:
  - Dado el modo restrictivo elegido y ninguna inclusión escrita
  - Cuando el usuario intenta guardar
  - Entonces se le advierte y el cambio solo se aplica si confirma

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Rendimiento | Aceptar el asistente completo (todas las categorías) tarda menos de 2 s y no bloquea la interfaz | Cronometrado sobre el catálogo entero |
| RNF-02 | Seguridad de datos | **0 escrituras** en `config.json` entre abrir el asistente y pulsar Aceptar | `sha256` del `config.json` antes y después de abrir y cerrar sin aceptar |
| RNF-03 | Reversibilidad | Tras **10** cambios de modo de ida y vuelta, las **4** listas siguen idénticas | Ida y vuelta entre modos: las cuatro listas sobreviven idénticas |
| RNF-04 | Usabilidad | Dejar la configuración recomendada completa cuesta 2 interacciones: abrir y aceptar | Contado sobre la pantalla |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| El usuario cierra el asistente a medias | Nada cambia | RF-01 |
| Modo restrictivo con lista de incluidos vacía | Se advierte de que la bitácora quedará ciega y se exige confirmación | RF-08 |
| Una semilla ya estaba en la lista del usuario | No se duplica | RF-01 |
| El usuario borró a mano una semilla y actualiza la app | No reaparece | RF-07 |
| Una semilla de aplicación coincide por subcadena con otra app legítima | Se propone la cadena más específica posible, y el desplegable deja verla antes de aceptar | RF-02, RF-04 |
| `config.json` no se puede escribir | Se dice, y no se deja la configuración a medias | RNF-02 |

## 7. Datos y cumplimiento

- **No se guarda ningún dato personal nuevo.** El asistente escribe cadenas de
  texto —nombres de dominio y de aplicación— en el `config.json` local del
  usuario, el mismo archivo que ya edita a mano hoy.
- **Nada sale del equipo.** Las semillas viajan embarcadas en la app; no hay
  consulta a ningún servicio, ni en la propuesta ni al aceptar.
- **Las semillas son un catálogo público de dominios**, no información sobre el
  usuario. Qué categorías acepte cada quien queda solo en su equipo.
- El efecto de esta spec es **reducir** lo que la bitácora registra, nunca
  ampliarlo: ningún camino aquí hace que se grabe algo que hoy no se grabe.

## 8. Supuestos y dependencias

- **Supone** que las cuatro listas del filtro (`bitacora_excluir_apps`,
  `bitacora_excluir_titulos`, `bitacora_incluir_apps`, `bitacora_incluir_titulos`)
  siguen siendo la única fuente de verdad, y que la comparación sigue siendo por
  subcadena sin mayúsculas ni tildes.
- **Depende** de `FiltroBitacora.decidir(app:ventana:excluirApps:…)`, la variante
  sin lectura de disco extraída el 2026-09-20, que es la que permite probar los
  modos sin tocar la configuración real de nadie.
- **Depende** de `Config`, que mantiene la configuración en caché en memoria y
  reescribe el archivo entero: editar `config.json` desde fuera con la app viva se
  pierde. El asistente escribe por `Config.set`, nunca tocando el archivo directo.
- **No depende** de la extensión del navegador (spec 006) ni la modifica.

## 9. Criterios de aceptación de la spec

- Las cuatro listas (`excluir_apps`, `excluir_titulos`, `incluir_apps`,
  `incluir_titulos`) siguen siendo la única fuente de verdad del filtro.
- Existe una prueba por cada RF, y cada una se ha visto **dar rojo** contra el
  código sin la funcionalidad.
- El camino de producción del filtro no cambia de comportamiento con el modo de
  fábrica: quien no abra el asistente queda exactamente como hoy.

## 10. Decisiones y aclaraciones

### Sesión 2026-09-21

- P: Con los dos modos disponibles, ¿cuál es el de fábrica? → R: **mirar todo
  salvo lo excluido**, el de hoy (decisión de Alberto).
- P: ¿Las semillas llegan marcadas o desmarcadas? → R: **marcadas, y nada surte
  efecto hasta aceptar** (decisión de Alberto).
- P: ¿Con qué grano se eligen? → R: **por categoría, con desplegable para afinar**
  (decisión de Alberto).
- Petición literal recogida: «que te dé ya una semilla de algunos en los que
  nosotros solo pongamos sí, sí, sí […] que no esté ejecutada, pero que sea fácil».
- Petición literal recogida sobre aplicaciones: «uno lo va a poder poner de forma
  manual; sin embargo, por defecto deberían sumarse las más comunes excluidas
  también, como ayuda».
- La detección automática de contenido adulto queda **fuera** por decisión expresa
  de Alberto, para otra spec.

## 11. Historial de cambios sobre la spec aprobada

(ninguno todavía)
