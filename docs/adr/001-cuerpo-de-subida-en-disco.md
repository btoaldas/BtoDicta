# ADR 001 — El cuerpo de la subida se escribe en disco, no en memoria

- Fecha: 2026-09-18
- Estado: Aceptada
- Spec: 001 — Memoria del dictado largo

## Contexto

Los doce motores de transcripción arman su `multipart/form-data` en una `Data`:
cabeceras, el audio entero, cierre. Con el audio ya cargado en otra `Data`, un
dictado de seis horas necesita ~1,4 GB en el instante del envío.

## Decisión

El cuerpo se escribe a un archivo temporal copiando el audio del origen por
ventanas de 64 KB, y se transmite con `uploadTask(with:fromFile:)`.

## Alternativa descartada: `httpBodyStream`

Es la opción evidente —un flujo no necesita archivo— y se descarta por una razón
concreta: **un flujo no se rebobina**. `URLSession` no puede reenviarlo, así que
el primer reintento manda un cuerpo vacío.

Esta aplicación reintenta por diseño, y no en un caso raro: el motor local
reintenta cada segundo mientras precalienta, con un plazo de cuarenta segundos.
Con un flujo, ese segundo intento subiría cero bytes y el dictado se perdería en
silencio — exactamente el fallo que el MANIFIESTO pone por encima de todo.

`fromFile:` sí rebobina, y es lo que Apple recomienda para cuerpos grandes.

## Consecuencias

- Hace falta gestionar temporales: limpieza en éxito, error, cancelación y
  cierre, más un barrido al arrancar por si un cierre inesperado dejó alguno.
  Se cuenta cuántos se crean y cuántos se borran para poder comprobarlo.
- Se escribe en disco un archivo del tamaño del dictado. En seis horas son
  691 MB temporales — aceptable frente a 1,4 GB de memoria, y en un disco donde
  el audio del dictado ya vive.
- El cuerpo tiene que ser **byte a byte** el que se armaba antes. Lo comprueba
  `BTODICTA_SUBIDATEST` con audios de 1 s, 1 min y 1 h antes de migrar nada.
