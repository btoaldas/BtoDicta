# Spec 011 — Corrección: El icono de la barra no puede quedar a nombre de otra aplicación

- Estado: Implementada
- Tipo: correccion
- Nivel: P
- Fecha: 2026-09-22
- Modifica: ninguna (corrige una explicación equivocada de la spec 010, ver §9)
- Aprobada por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien» (a «¿Apruebo la spec 011 y paso al plan?»)

## 1. Problema y propósito

Con la app abierta y permitida en la barra, su icono no aparecía. Esta corrección
hace que no pueda volver a quedar oculto por cómo se lanzó, en vez de parchearlo
después.

### Reproducción

- Pasos exactos:
  1. Con BtoDicta cerrada, ejecutar el binario de dentro del paquete directamente
     desde una terminal cuyo programa esté bloqueado en *Ajustes → Barra de menús*
     (en el equipo de desarrollo, Claude Code):
     `/Applications/BtoDicta.app/Contents/MacOS/BtoDicta`
  2. Cerrarla y abrirla de forma normal: Dock, Finder o `open`.
- Comportamiento actual (medido el 2026-09-22):
  - macOS apunta el icono de `ec.bto.btodicta` en la fila de Claude Code
    (`menuItemLocations` de `com.anthropic.claude-code`, que está `BLOQUEADA`).
  - El icono **no se ve**: el sistema lo sitúa en (2, 981), fuera de la barra,
    aunque queden 257 puntos libres y la fila propia de BtoDicta esté permitida.
  - **Persiste**: abierta después de forma normal, sigue oculta.
- Comportamiento esperado: el icono se ve siempre que BtoDicta esté abierta y
  permitida en la barra, se haya lanzado antes como se haya lanzado.

## 2. Actores

| Actor | Quién es | Qué gana con esta corrección |
|---|---|---|
| Usuario de BtoDicta | Quien la usa a diario | El icono está siempre, sin reparar nada a mano |
| Quien desarrolla o prueba BtoDicta | Un agente o una persona con una terminal | Puede probarla sin esconder el icono de nadie |

## 3. Alcance

### Incluye

  - Que BtoDicta no pueda dejar su icono apuntado a nombre de otra aplicación,
    sea cual sea el programa que la lance.
  - Que las pruebas del proyecto no lo provoquen.
  - Que el QA falle si una pasada lo deja así.
  - Corregir por escrito la explicación equivocada que quedó en la spec 010.

### No incluye (con razón)

  - **Limpiar lo que ya está envenenado.** Eso es modificar ajustes del sistema y
    lo decide el usuario: hoy existe `make reparar-icono`, que se corre a mano.
  - Otras aplicaciones del equipo afectadas por lo mismo (BtoStats, Neptunus).
  - Detectar y avisar, el atajo por triple fn y el recordatorio: van en una spec
    aparte, después de esta. Con la causa resuelta, avisar deja de ser la solución
    y pasa a ser una red de seguridad.

### Causa raíz

macOS 26 anota el icono de la barra a nombre del **proceso responsable** de la
aplicación. Si la abre el sistema —Dock, Finder, Spotlight, inicio de sesión,
`open`— la aplicación es responsable de sí misma. Si su binario se ejecuta
directamente desde una terminal, el responsable es **el programa dueño de esa
terminal**. Si ese programa está bloqueado en la barra, el icono desaparece, y el
apunte queda guardado para los arranques siguientes.

Confirmado con una aplicación desechable de identificador propio, para no tocar el
estado de BtoDicta:

| Lanzamiento | Padre del proceso | Fila propia | Colgada de | ¿Se ve? |
|---|---|---|---|---|
| `open` | 1 (`launchd`) | permitida | nadie | — |
| binario directo | la terminal | permitida | **Claude Code** | no |
| `open`, con la fila ya envenenada | 1 (`launchd`) | permitida | Claude Code | **no** |

En este proyecto lo provocaban las **pruebas**: los arneses que necesitan el
paquete real se ejecutaban así, y el 2026-09-21 y 22 se añadieron dos más al QA.
El script de reparación de julio quitaba el apunte, pero la siguiente prueba lo
volvía a crear.

Respaldo externo: informe de Mudlet sobre la atribución al proceso responsable
cuando se lanza desde una terminal, y respuesta de Apple DTS sobre el registro de
los iconos por identificador de paquete.

## 4. Requerimientos funcionales

### RF-01 — Lanzada por otro programa, no registra su icono

- Actor: cualquier programa que ejecute el binario de BtoDicta directamente
- Acción: arranca BtoDicta sin pasar por el sistema
- Resultado: la aplicación funciona, pero no registra su icono en la barra y deja
  escrito por qué
- Medida: tras 20 arranques directos desde una terminal bloqueada, `ec.bto.btodicta`
  no aparece colgada de ninguna fila ajena
- Prioridad: P1
- Criterio de aceptación:
  - Dado que el binario se ejecuta directamente desde una terminal
  - Cuando termina de arrancar
  - Entonces no hay icono de BtoDicta registrado y el registro dice el motivo
- Prueba de regresión que lo cubre: `scripts/qa-icono-a-su-nombre.py` (nueva)

### RF-02 — Lanzada por el sistema, el icono es suyo y se ve

- Actor: usuario de BtoDicta
- Acción: la abre desde el Dock, el Finder, Spotlight, el inicio de sesión o tras
  actualizarse sola
- Resultado: el icono queda a nombre de BtoDicta y se ve
- Medida: fila propia permitida, colgada de nadie, e icono visible según el sistema
- Prioridad: P1
- Criterio de aceptación:
  - Dado que la abre el sistema
  - Cuando termina de arrancar
  - Entonces el icono está a su nombre y visible
- Prueba de regresión que lo cubre: `scripts/qa-icono-a-su-nombre.py` (nueva)

### RF-03 — Las pruebas no envenenan el icono

- Actor: el QA del proyecto
- Acción: corre la pasada completa, incluidas las pruebas que necesitan el icono
- Resultado: ninguna deja el icono de BtoDicta a nombre de otro programa
- Medida: 0 filas ajenas que alberguen `ec.bto.btodicta` tras la pasada
- Prioridad: P1
- Criterio de aceptación:
  - Dado un QA completo lanzado desde una terminal bloqueada en la barra
  - Cuando termina
  - Entonces ninguna fila ajena alberga el icono de BtoDicta
- Prueba de regresión que lo cubre: guardia final de `scripts/qa-paquete.sh`

### RF-04 — El QA falla si lo deja envenenado

- Actor: el QA del proyecto
- Acción: comprueba, al terminar, a nombre de quién quedó el icono
- Resultado: falla si alguna fila ajena lo alberga, diciendo cuál
- Medida: una prueba saboteada para ejecutar el binario directamente pone el QA en
  rojo
- Prioridad: P1
- Criterio de aceptación:
  - Dado que una prueba ejecuta el binario del paquete directamente
  - Cuando termina el QA
  - Entonces el QA falla y nombra la fila que lo alberga
- Prueba de regresión que lo cubre: guardia final de `scripts/qa-paquete.sh`

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Compatibilidad | Actualizarse sola no deja la aplicación sin icono: **0** casos | El actualizador se relanza con `open`; se comprueba que el camino sigue siendo ese |
| RNF-02 | Seguridad | **0** escrituras en ajustes del sistema desde la aplicación o desde las pruebas | Huella del archivo de ajustes de la barra antes y después del QA, descontando lo que macOS añade por sí solo |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| La lanza el inicio de sesión | Icono a su nombre y visible | RF-02 |
| Se actualiza sola y se relanza | Icono a su nombre y visible: el actualizador usa `open` | RF-02, RNF-01 |
| Se ejecuta con `swift run` o el binario suelto de `build/` | Funciona sin icono, y el registro dice por qué | RF-01 |
| Una prueba necesita el icono de verdad | Abre el paquete a través del sistema, no el binario | RF-03 |
| La fila ya estaba envenenada de antes | Esta corrección no la limpia: lo decide el usuario con `make reparar-icono` | — |

## 7. Datos y cumplimiento

- Ningún dato nuevo, ni personal ni de configuración.
- La aplicación no escribe en ajustes del sistema, ni para arreglar esto (RNF-02).
- Lo que macOS anota por sí solo al abrirse una aplicación con icono no lo hace
  la aplicación, y no se cuenta como escritura suya.

## 8. Supuestos y dependencias

- **Supone** que el sistema abre las aplicaciones como hijas de `launchd` cuando
  las lanza él: medido con `open` en macOS 26.6.2. Si una versión futura lo
  cambiara, la prueba de RF-02 lo detectaría.
- **Depende** del actualizador, que hoy se relanza con `open`.
- **No depende** de la spec 010: corrige una explicación suya, no su código.

## 9. Lo que la spec 010 dejó dicho y era falso

La verificación, el hito, la bitácora y el historial de versiones de la spec 010
atribuyeron el icono oculto a **una barra de menús llena**. Era falso: quedaban
257 puntos libres. La causa es la de §3. Se corrige por escrito y con fecha, sin
reescribir lo que se publicó.

## 10. Decisiones y aclaraciones

### Sesión 2026-09-22

- P: ¿Qué vías resuelve esto? → R: «no debería haber este problema; siempre
  debería haber el icono… lo primordial es que se vea y siempre esté vigente». Las
  tres vías de aviso se quieren, pero **después** (decisión de Alberto).
- P: ¿Qué hacemos con el script que reescribe los ajustes de la barra? → R:
  «Debemos solucionar y no parchar… ningún sistema lo parcha» (decisión de
  Alberto). Esta spec ataca la causa; qué hacer con el script queda en §8.
- P: ¿Entra que el flujo de desarrollo no provoque el problema? → R: «Sí, es lo
  primero» (decisión de Alberto).
- Constatado y comunicado: el script de reparación reescribió los ajustes de la
  barra 8 veces el 2026-09-22 dentro de `make instalar-local`, y el agente dejó
  dos filas de prueba (`/tmp/spike-icono/spike` y `largo`) y una aplicación
  desechable (`ec.bto.pruebaicono`) en la lista del sistema. Ninguna se quita desde
  aquí: es un ajuste del sistema.

## 11. Pendiente de decisión en la puerta

- Qué hacer con `make reparar-icono` dentro de `make instalar-local` una vez la
  causa esté corregida. Quitarlo del instalador es retirar un paso: necesita un sí
  explícito.
