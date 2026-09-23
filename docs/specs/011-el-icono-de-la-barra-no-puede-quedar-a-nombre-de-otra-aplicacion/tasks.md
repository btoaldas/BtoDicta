# Tareas 011 — El icono de la barra no puede quedar a nombre de otra aplicación

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22) · Plan: `plan.md` (Aprobado 2026-09-22)
- Aprobado por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien» (aprobación delegada)

- [x] T01 (RF-01) La decisión pura, con sus pruebas vistas en rojo
  - Archivos: `Sources/BtoDicta/IconoBarra.swift`, `Tests/BtoDictaTests/IconoBarraTests.swift`
  - Evidencia esperada: padre 1 → registra; cualquier otro → no. Rojo al invertirla.
  - Evidencia (2026-09-22): `IconoBarra.debeRegistrar(padre:)` y `IconoBarraTests`: 3 de 3; «registrar siempre» → 5 fallos.

- [x] T02 (RF-01, RF-02) La cerradura en `crearStatusItem()`
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Evidencia esperada: lanzada directamente, no hay icono y el registro dice por qué, una sola vez.
  - Evidencia (2026-09-22): Cerradura en `crearStatusItem()`. Lanzada directa: «ICONTEST FALLA: no hay icono», salida 3, y el motivo en el registro una vez.

- [x] T03 (RF-03) Las pruebas que necesitan el icono, por el sistema
  - Archivos: `scripts/qa-paquete.sh`, `scripts/qa-modo-rapido.py`
  - Evidencia esperada: `icono_estados` pasa lanzada con `open`; `qa-modo-rapido.py` usa el binario suelto.
  - Evidencia (2026-09-22): `icono_estados` por `ejecutar_por_sistema` (`open -W -n --env`, juzgado por lo que escribe: `open -W` devuelve 0 aunque falle); `qa-modo-rapido.py` usa el binario suelto. QA: `icono_estados` PASA.

- [x] T04 (RF-03, RF-04) Comprobar a nombre de quién quedó el icono
  - Archivos: `scripts/qa-icono-a-su-nombre.py`, `scripts/qa-paquete.sh`
  - Evidencia esperada: verde con BtoDicta; rojo nombrando la fila con la app desechable, que está envenenada.
  - Evidencia (2026-09-22): `scripts/qa-icono-a-su-nombre.py`, al final del QA. Verde con BtoDicta; con la desechable envenenada, FALLA nombrando `com.anthropic.claude-code (BLOQUEADA)`.

- [x] T05 (RF-01, RF-02) De punta a punta en BtoDicta real
  - Archivos: `scripts/qa-icono-a-su-nombre.py`
  - Evidencia esperada: 20 arranques directos y ninguna fila ajena la alberga; abierta por el sistema, icono a su nombre y dentro de la barra.
  - Evidencia (2026-09-22): `--directos 1` y `--directos 19`: 20 arranques directos, 0 filas ajenas, motivo 20/20. Abierta con `open`: padre 1, icono en (1154, 4), también tras el QA completo. Primer intento con motivo 0/1: el registro no se vaciaba antes de salir; corregido con `Log.vaciar()`.

- [x] T06 (RNF-01, RNF-02) El actualizador y las escrituras en el sistema
  - Archivos: `scripts/qa-icono-a-su-nombre.py`
  - Evidencia esperada: el actualizador se relanza con `open`; ni la app ni las pruebas escriben en los ajustes de la barra.
  - Evidencia (2026-09-22): Guardia: actualizador con `open`; ningún fuente de la app nombra la lista de la barra; última reescritura, la manual de las 22:38.

- [x] T07 (RF-02) Corregir lo que la spec 010 dijo mal
  - Archivos: `docs/specs/010-controles-rapidos-desde-el-icono-de-la-barra/verificacion.md`, `docs/hitos/2026-09-22-controles-rapidos.md`, `docs/bitacora/2026-09-22.md`, `Sources/BtoDicta/Version.swift`
  - Evidencia esperada: nota fechada en cada uno; ninguna afirmación de «barra llena» sin corregir.
  - Evidencia (2026-09-22): Nota fechada de corrección en la verificación y el hito de la 010 y en la bitácora del 2026-09-22; historial 0.80.1 lo dice. Las 11 citas a una «spec 011» de transcripción renumeradas a «por crear».

- [x] T08 (RF-01) ADR
  - Archivos: `docs/adr/015-el-icono-solo-si-lo-lanza-el-sistema.md`
  - Evidencia esperada: decisión y alternativa descartada.
  - Evidencia (2026-09-22): `docs/adr/015-el-icono-solo-si-lo-lanza-el-sistema.md`, con tres alternativas descartadas.

- [x] T09 (todos) Verificación e hito
  - Archivos: `docs/specs/011-el-icono-de-la-barra-no-puede-quedar-a-nombre-de-otra-aplicacion/verificacion.md`, `docs/hitos/2026-09-22-icono-a-su-nombre.md`
  - Evidencia esperada: QA completo en 0; spec en `Implementada`.
  - Evidencia (2026-09-22): `verificacion.md` con 4 RF y 2 RNF en «Cumple»; hito escrito; QA 35 de 36 (la ajena `texto_vs_ocr`); suite Swift 50 de 50.
