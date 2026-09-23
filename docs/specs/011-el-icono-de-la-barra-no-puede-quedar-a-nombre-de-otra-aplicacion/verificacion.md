# Verificación 011 — El icono de la barra no puede quedar a nombre de otra aplicación

- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Estado del QA al verificar: **35 de 36** · suite Swift **50 de 50** · versión 0.80.1.
  La que falla es `texto_vs_ocr` (spec 006), ajena a esta corrección y dependiente
  de las páginas navegadas: mediana de texto 0,9× frente al OCR. No se bajó su
  listón para ponerla en verde.

## Requerimientos funcionales

| RF | Qué exigía | Cómo se comprobó | Segundo ángulo | Veredicto |
|---|---|---|---|---|
| RF-01 | Lanzada por otro programa, no registra su icono | `qa-icono-a-su-nombre.py --directos 20`: 20 arranques directos del binario del paquete, 0 filas ajenas lo albergan, 20/20 dejan escrito el motivo | `IconoBarraTests`: registrar siempre da 5 fallos. El rojo de punta a punta, con la aplicación desechable: ejecutada directa, queda colgada de Claude Code | Cumple |
| RF-02 | Lanzada por el sistema, el icono es suyo y se ve | Abierta con `open`: padre 1, fila propia permitida, icono en (1154, 4) | Mismo resultado tras una pasada completa del QA | Cumple |
| RF-03 | Las pruebas no envenenan el icono | Tras un QA completo lanzado desde la terminal bloqueada, ninguna fila ajena lo alberga | El icono sigue visible en (1154, 4) después de ese QA | Cumple |
| RF-04 | El QA falla si queda envenenado | `qa-icono-a-su-nombre.py --paquete ec.bto.pruebaicono` sobre la desechable, envenenada adrede: FALLA nombrando `com.anthropic.claude-code (BLOQUEADA)` | Con BtoDicta, verde; la guardia corre al final del QA, después de todas las pruebas | Cumple |

## Requerimientos no funcionales

| RNF | Exigía | Resultado | Veredicto |
|---|---|---|---|
| RNF-01 | 0 casos sin icono tras actualizarse | El actualizador se relanza con `open /Applications/BtoDicta.app` (padre 1); lo comprueba la guardia del QA | Cumple |
| RNF-02 | 0 escrituras en ajustes del sistema desde la app o las pruebas | Ningún fuente de la app nombra la lista de la barra; la última reescritura de esa lista es la que corrió Alberto a mano a las 22:38, anterior a todo el trabajo de esta spec | Cumple |

## Desviaciones respecto a la spec

- **El rojo de RF-01 no se corrió sobre BtoDicta real.** Hacerlo envenenaría el
  icono del usuario, y limpiarlo exige reescribir ajustes del sistema. Se mostró
  con la aplicación desechable —misma causa, identificador propio— y con la
  decisión pura saboteada.
- **Se añadió `Log.vaciar()`.** El registro se escribe en una cola en segundo plano
  y un `exit()` inmediato perdía las últimas líneas: la primera medida de RF-01 dio
  «motivo 0/1» con la cerradura funcionando. Afectaba a todos los arneses.
- **`open -W` devuelve 0 aunque la aplicación falle.** Las pruebas lanzadas por el
  sistema se juzgan por lo que escriben.

## Riesgos residuales

- **Filas ya envenenadas de antes** no se limpian solas: BtoStats, BtoStatsTest,
  siprobe y Neptunus siguen colgadas de Claude Code. Son otras aplicaciones.
- **Tres filas de prueba** del agente en la lista del sistema (`spike`, `largo` y
  `ec.bto.pruebaicono`); se quitan en Ajustes → Barra de menús.
- **`make reparar-icono` sigue dentro de `make instalar-local`.** Retirarlo necesita
  un sí explícito y separado; hasta entonces, el agente instala con `make install`.
- **Si macOS cambiara** cómo lanza las aplicaciones y dejara de ser `launchd` el
  padre, la app se quedaría sin icono: la guardia en vivo del QA lo detectaría.
