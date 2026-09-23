# ADR 014 — La pausa del usuario y la cesión del micrófono son dos banderas distintas

- Fecha: 2026-09-22
- Estado: Aceptada
- Spec: 010 — Controles rápidos desde el icono de la barra

## Contexto

La bitácora ya sabía «suspenderse»: `ContinuoBitacora.cederMicrofono` suelta el
micrófono cuando empieza un dictado, y `recuperarMicrofono` lo retoma cuando el
dictado termina. Parecía el mecanismo natural para la pausa que pide el usuario.

## Decisión

La pausa del usuario tiene su **propia** bandera (`bitacora_pausada_hasta`),
independiente de la cesión. Se comprueba en el arranque de la bitácora, en la
apertura del micrófono y en las tres entradas de datos —audio, pantalla y audio
del sistema—, así que ningún camino que relance la captura puede saltársela.

## Alternativa descartada: reutilizar la suspensión de la cesión

Usar `cederMicrofono`/`recuperarMicrofono` también para la pausa.

Se descarta porque las dos cosas tienen **dueños distintos**. La cesión la abre y
la cierra el dictado; la pausa, el usuario. Con una sola bandera, terminar un
dictado en mitad de una pausa llamaría a `recuperarMicrofono` y la bitácora
volvería a grabar sin que nadie lo pidiera — el usuario pausó, dictó una frase, y
ya se estaba mirando otra vez.

## Consecuencias

- Un dictado puede empezar y terminar durante una pausa sin cancelarla.
- Comprobado en las dos direcciones: con las cerraduras, un dictado entero en
  mitad de la pausa deja 0 bytes nuevos en la bitácora; sin ellas, el mismo dictado
  reabre el micrófono y escribe 399 968 bytes durante la pausa.
- Hay dos estados que razonar en lugar de uno. Se acepta: fundirlos es exactamente
  el fallo que esto evita.
