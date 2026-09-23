# ADR 015 — El icono de la barra solo se registra si a la aplicación la lanzó el sistema

- Fecha: 2026-09-22
- Estado: Aceptada
- Spec: 011 — El icono de la barra no puede quedar a nombre de otra aplicación

## Contexto

macOS 26 anota el icono de la barra a nombre del **proceso responsable** de la
aplicación. Cuando la abre el sistema —Dock, Finder, Spotlight, inicio de sesión,
`open`, el actualizador— la aplicación es responsable de sí misma. Cuando su
binario se ejecuta desde una terminal, el responsable es el programa dueño de esa
terminal, y el icono queda apuntado en su fila. Si ese programa está bloqueado en
la barra, el icono desaparece, y el apunte persiste para los arranques normales.

Medido con una aplicación desechable de identificador propio: `open` → padre 1,
colgada de nadie; binario directo → padre la terminal, colgada de ella; `open` con
la fila ya envenenada → sigue oculta.

## Decisión

`crearStatusItem()` solo registra el icono si `getppid() == 1`. Si no, la
aplicación funciona sin icono y deja escrito por qué, una vez. **No hay
interruptor para saltárselo.** Las pruebas que necesitan el icono se lanzan con
`open -n -W --env`, como lo haría el sistema.

## Alternativas descartadas

**Preguntar por el proceso responsable** con `responsibility_get_pid_responsible_for_pid`.
Es lo que decide macOS, pero es API privada: puede cambiar o desaparecer sin
aviso. El padre del proceso es público y describe la misma condición en los
caminos reales, medidos uno a uno.

**Un interruptor para forzar el icono en pruebas.** Cualquier herramienta lo
activaría para «que funcione» y volvería a envenenar el icono: es exactamente como
nació el problema.

**Reparar después**, reescribiendo la lista de la barra. Es lo que se hizo desde
julio y lo que se deja atrás: exige escribir ajustes del sistema, y la siguiente
prueba lo volvía a romper.

## Consecuencias

- 20 arranques directos del binario del paquete: 0 filas ajenas lo albergan, y los
  20 dejaron escrito el motivo.
- Depurar desde Xcode o con `swift run` no muestra icono. Es lo esperado: esos son
  los lanzamientos que lo envenenarían.
- `open -W` devuelve 0 aunque la aplicación falle, así que las pruebas lanzadas por
  el sistema se juzgan por lo que escriben, no por el código de salida.
- Una fila ya envenenada de antes no se limpia sola. Para eso sigue existiendo
  `make reparar-icono`, que se corre a mano.
