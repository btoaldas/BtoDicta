# Plan técnico 011 — El icono de la barra no puede quedar a nombre de otra aplicación

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Aprobado por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien» (aprobación delegada de plan y tareas, dada junto con la de la spec)

## 1. Lo que hay hoy

| Pieza | Dónde | Estado |
|---|---|---|
| Creación del icono | `AppDelegate.crearStatusItem()`, único sitio; lo llaman el arranque y `recuperarStatusItem` | Crea el icono sin mirar quién lanzó la app |
| Arneses de prueba tempranos | pausa, reunión, modo rápido, carrera del micrófono | Salen antes de crear el icono: no envenenan |
| `BTODICTA_ICONTEST` y `BTODICTA_MENUTEST` | después de crear el icono | El de icono corre en el QA con el binario del paquete: **envenena** |
| `qa-modo-rapido.py` | ejecuta el binario de `/Applications` | Arnés temprano: no envenena, pero conviene no depender de eso |
| Actualizador | `Updater.instalarDMGVerificado` | Se relanza con `open`: padre `launchd` |
| `make reparar-icono` | dentro de `make instalar-local` | Reescribe ajustes del sistema. Se conserva; qué hacer con él lo decide Alberto |

## 2. Comprobación contra la constitución

- [x] **Solucionar y no parchar.** La corrección impide que se produzca; no limpia
      después. La limpieza sigue siendo una herramienta manual, del usuario.
- [x] **Sin escrituras en ajustes del sistema** desde la app ni desde las pruebas.
      El agente instala sin pasar por `reparar-icono`.
- [x] **Toda prueba se ve en rojo.** Donde el rojo en BtoDicta real envenenaría el
      icono del usuario, se muestra con la aplicación desechable y en la decisión
      pura; se dice así, no se finge.
- [x] **Nivel P.** Prueba por RF, segundo ángulo y verificación.
- [x] **Commits neutros.**

## 3. Decisiones

| # | Decisión | Alternativa descartada | Por qué |
|---|---|---|---|
| D-1 | Registrar el icono **solo si el padre del proceso es `launchd`** (pid 1) | Preguntar por el «proceso responsable» con la API privada `responsibility_get_pid_responsible_for_pid` | Es API privada: puede cambiar sin aviso y no pasa revisión. `getppid() == 1` es pública, se midió en los cuatro caminos reales (Dock, Finder, `open`, actualizador) y describe exactamente la condición: lo lanzó el sistema |
| D-2 | Sin interruptor para saltarse la cerradura | Una variable de entorno que fuerce el icono para pruebas | Cualquier herramienta la pondría para «que funcione», y volvería a envenenar. Las pruebas que necesitan el icono lo abren como el sistema: `open -n -W --env` |
| D-3 | Las pruebas que necesitan el icono se lanzan con `open` | Ejecutar el binario y limpiar después | Limpiar después es el parche que se quiere dejar atrás, y exige escribir ajustes del sistema |
| D-4 | La comprobación del QA **lee** la lista de la barra, no la escribe | Reparar al final del QA | Lo mismo: leer no toca nada del usuario |

A `docs/adr/015-el-icono-solo-si-lo-lanza-el-sistema.md`: D-1 y D-2.

## 4. Orden de trabajo

1. La decisión pura y sus pruebas en rojo.
2. La cerradura en `crearStatusItem()`, con su línea en el registro.
3. `icono_estados` por `open`; `qa-modo-rapido.py` con el binario suelto.
4. `scripts/qa-icono-a-su-nombre.py` y la guardia final del QA; rojo con la app desechable.
5. Veinte arranques directos sin envenenar; arranque por el sistema, visible.
6. Corregir por escrito lo que la 010 dijo mal, y las citas a la «spec 011».
7. Verificación e hito.

## 5. Riesgos

| Riesgo | Mitigación |
|---|---|
| Un camino del sistema que no tenga `launchd` como padre deja la app sin icono | Medidos los cuatro reales; RF-02 lo comprueba en vivo; si macOS cambia, la prueba lo detecta |
| Depurar desde Xcode o `swift run` no muestra icono | Es lo esperado y queda escrito en el registro: esos lanzamientos serían los que envenenan |
| Una fila ya envenenada de antes | No la limpia esta corrección; `make reparar-icono`, a mano |
