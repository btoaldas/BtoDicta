# Hito — Red de seguridad del icono y triple fn para el modo reunión

- Fecha: 2026-09-22
- Spec: 012 — Red de seguridad del icono y triple fn para el modo reunión (nivel P)
- Versión: 0.81.0
- RF satisfechos: RF-01 a RF-06
- RNF satisfechos: los tres
- Desviaciones respecto a la spec: gracia mínima de 2 s (el plan decía 5) para el
  arnés; una segunda señal de «barra escondida» (una ventana del tamaño de la
  pantalla), añadida para reconocer la pantalla completa; las pruebas lanzadas con
  `open` van en segundo plano. Detalle en `verificacion.md`.

## Qué se consiguió

La spec 011 quitó la causa por la que el icono desaparecía. Esta añade lo que hace
falta por si macOS lo vuelve a esconder por otro motivo:

- **Si el icono no se ve, BtoDicta lo dice**, una vez, con cómo arreglarlo y un
  botón «No volver a avisar». Se decide por **dónde está** el icono, no por si una
  ventana lo tapa: fuera de la barra o bajo la muesca es escondido; con la barra
  fuera de pantalla no se sabe, y no se avisa. Espera 30 s seguidos y nunca
  interrumpe un dictado.
- **fn fn fn pone o quita el modo reunión.** Las dos primeras arrancan el dictado
  como siempre; la tercera, si llega dentro de la ventana del doble, cambia el modo
  sin cortar la grabación.
- **Recordatorio cada 30 min** si el modo reunión sigue puesto con el icono
  escondido.

Todo parametrizable: `icono_oculto_gracia_seg`, `icono_oculto_recordatorio_min`
(0 lo apaga) e `icono_oculto_no_avisar`.

## Cómo se comprobó

| Prueba | Qué demuestra | Su rojo |
|---|---|---|
| `VisibilidadIconoTests` (9) | Posición → visible, oculto o no se sabe, con la geometría medida del equipo | «Siempre visible» → 9 fallos; muesca ignorada → 2 |
| `VigiaIconoOcultoTests` (8) | Una vez tras la gracia; recordatorio por intervalo; lo que no se sabe ni avisa ni reinicia | Avisar cada vez → 6; «no se sabe» que reinicia → 1 |
| `TriplePulsacionTests` (3) | Se arma solo tras un doble que arrancó; ventana; el doble no espera | Armar siempre → 3 |
| `icono_oculto` (QA, por `open`) | Esconde de verdad el propio icono y el vigía real avisa una vez y recuerda | Sin el vigía: 60 s escondido y ningún aviso |
| `triple_fn` (QA) | Eventos de fn sintéticos por el manejador real: 14 comprobaciones, Carbon y la carrera incluidos | Sin tercera → 6; tercera solo grabando → 1; Carbon → 2 |

**La prueba de RF-02 la dio el uso real.** Durante el QA había un juego a pantalla
completa. macOS subió la ventana del icono por encima de la pantalla, a
(1061, 1026): leída sola, esa posición dice «fuera de toda pantalla». BtoDicta
registró «no se sabe: la barra no está en pantalla» y no avisó. Sin la comprobación
de la barra habría sido un aviso en falso.

QA 36 de 38 —`texto_vs_ocr`, ajena y ya roja antes; `icono_oculto`, sin barra que
medir en esa pasada y pasada aparte—; suite Swift de 50 a 70.

## Riesgos residuales

- **Cancelar con fn en menos de 0,45 s después de arrancar pone el modo reunión.**
  Aceptado al diseñar (ADR 016): el notch lo dice y otra fn detiene.
- **La alerta no se pulsa en una prueba automática**: en carpeta aislada no se
  muestra. Su texto sale de una función pura y el botón escribe una clave.
- **Bajo la muesca**, solo probado con geometría.
- Con la barra que se oculta sola (ajuste del sistema), no se avisa nunca: no hay
  forma de saber si el icono se vería.

## Lecciones

- **Una posición sola no dice si algo se ve.** La misma coordenada «fuera de la
  pantalla» es un icono escondido o una barra apartada por un juego. Hizo falta la
  segunda señal —¿está la barra en pantalla?— para no avisar en falso, y la trajo el
  uso real, no el diseño.
- **Una prueba que depende del entorno tiene que poder decir «no pude medir».**
  Dar FALLA porque el usuario estaba jugando habría enseñado a ignorar la prueba.
- **Una carrera no se espera, se fuerza.** La tercera pulsación rápida llegaba
  siempre después de que la grabación empezara, y la prueba de la carrera pasaba
  también con el arreglo saboteado. Mandar segunda y tercera en el mismo turno, antes
  de que el arranque corra, la hizo fallar como debía.
