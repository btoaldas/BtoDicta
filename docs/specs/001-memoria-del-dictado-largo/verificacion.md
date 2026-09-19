# Verificación 001 — Memoria del dictado largo

- Fecha: 2026-09-19
- Versiones: 0.63.4 (grabador) y 0.63.5 (los doce envíos)
- Nivel X: cada RF con segundo ángulo y prueba negativa

## Resumen

Un dictado de seis horas ocupaba cerca de **2 GB** entre las tres etapas —el
buffer del grabador, el `.wav` que se armaba al terminar y el cuerpo del envío
que lo copiaba otra vez dentro—. Ahora ocupa **80 MB**.

| Etapa | Antes | Ahora |
|---|---|---|
| Grabar 6 h | +661 MB | **+13 MB** |
| Soltar la tecla | +662 MB | **+3 MB** |
| Preparar el envío | +659 MB | **+0 MB** |
| Residente total | ~1 990 MB | **80 MB** |

## RF-01 — Dictar seis horas y recibirlo transcrito completo

**Cumple.**

- Criterio: el texto entregado contiene el habla del primer y del último minuto.
- Ejecutado: `BTODICTA_MEMTEST=6` recorre el camino real del grabador con seis
  horas de audio y comprueba que el archivo queda completo —«el archivo tiene los
  659 MB completos»— y que se puede leer cualquier tramo, incluido el último.
- Segundo ángulo: `BTODICTA_FISHTEST=1` hace el recorrido entero con voz
  sintética —genera el audio, lo transcribe por la cascada real y compara el
  texto—: «la transcripción devuelve el texto dictado».
- Prueba negativa: pedir un tramo más allá del final devuelve vacío, no un error
  ni datos inventados.
- En uso real: dos dictados del usuario el 2026-09-18 (13,9 s y 8,3 s), ambos
  entregados completos por Fish Audio.

## RF-02 — La memoria no crece con la duración

**Cumple.** Medida: la diferencia entre un dictado de seis horas y uno corto no
pasa de 200 MB. Medido **13 MB al grabar, 3 MB al terminar y 0 MB al preparar el
envío**.

- Segundo ángulo: además del residente, se cuentan los temporales creados y
  borrados — «1 creados, 1 borrados», sin huérfanos. La memoria puede salir bien
  y la limpieza mal; se comprueban las dos.
- Prueba negativa: el mismo `MEMTEST` **daba rojo** contra el código anterior
  (+661 MB y +662 MB, 2 fallos). Una prueba que nunca falla no prueba nada.

### La medición anterior era un falso positivo

La spec daba RF-02 por cumplido «al grabar» desde 0.60.0, con 0 MB en seis horas.
La cifra era real pero **medía otro componente**: `MEMTEST` construía un
`HistoryWriter` y le metía los trozos directamente, sin pasar nunca por el
grabador. El grabador retenía el dictado entero.

La prueba corregida recorre el grabador real. Queda anotado aquí porque es la
lección que más vale de esta spec: una prueba que no recorre el camino del
usuario no dice nada sobre el camino del usuario.

## RF-03 — Un dictado corto no se vuelve más lento

**Cumple.** Armar el cuerpo de un envío, camino viejo contra camino nuevo:

| Audio | En memoria | En disco | Diferencia |
|---|---|---|---|
| 1 s | 0 ms | 1 ms | +1 ms |
| 1 min | 0 ms | 1 ms | +1 ms |
| 1 h | 7 ms | 54 ms | +47 ms |

Escribir a disco **sí es más lento en términos relativos** —siete veces para una
hora de audio— y se dice sin adornos. En términos absolutos son 47 ms frente a
los segundos que tarda cualquier transcripción, y a cambio se ahorran 115 MB. En
un dictado corto, que es lo que mide este RF, la diferencia es de 1 ms.

## RF-04 — El audio sigue a salvo ante un cierre inesperado

**Cumple.**

- El `.wav` se escribe según entra el audio, así que un cierre inesperado deja en
  disco todo lo hablado hasta ese instante en vez de perderlo con el proceso.
- La cabecera se completa al cerrar; un archivo interrumpido conserva el audio
  aunque declare un tamaño menor.
- Segundo ángulo: al arrancar se barren los cuerpos de envío huérfanos de una
  sesión anterior, y el barrido del audio de trabajo comprobado en las dos
  direcciones — con el plazo de fábrica borra uno de diez días, conserva uno de
  tres y **no toca** uno de diez días que no lleve su prefijo; con el plazo en 0
  no borra ni uno de treinta días.
- Prueba negativa: `CANCELTEST` en verde — cancelar sigue sin borrar nada.

## RF-05 — La reparación de tramos sigue funcionando

**Cumple.** `REDTEST2` y `PARTIRTEST` en verde leyendo del archivo, y
`TROCEOTEST` parte en 38 tramos sin pérdida y con las líneas correctas.

El troceo solo carga el audio en memoria **cuando de verdad parte**, que es lo
excepcional; para decidir si hace falta le basta el tamaño del archivo, que se
consulta sin abrirlo.

## Requerimientos no funcionales

| ID | Umbral | Medido | Veredicto |
|---|---|---|---|
| RNF-01 | Residente ≤ 700 MB en 6 h | **80 MB** | Cumple |
| RNF-02 | Leer un tramo de 25 MB < 50 ms | **2,9 ms** | Cumple |
| RNF-03 | 6 de 6 baterías en verde, 0 omitidas | `SUBIDATEST`, `MEMTEST`, `PARTIRTEST`, `TROCEOTEST`, `REDTEST2`, `ROBUSTEZTEST`, `CANCELTEST`, `MICTEST` — 8 de 8 | Cumple |
| RNF-04 | 0 avisos nuevos, 0 pasos añadidos | El dictado se usa igual. Lo único añadido es un ajuste **opcional** (los días que se conserva el audio de trabajo), que no interrumpe ni pregunta | Cumple |

## Comprobación previa a todo: el cuerpo no cambió

Antes de migrar ningún motor se comprobó que el cuerpo escrito a disco es
**byte a byte** el que se armaba en memoria, con audios de 1 s, 1 min y 1 h:
32 396 B, 1 920 396 B y 115 200 396 B, los tres idénticos. Si hubiera diferido un
solo byte, el servidor habría recibido basura y el dictado se habría perdido —
que es lo que el MANIFIESTO pone por encima de la memoria.

Queda como prueba permanente: `BTODICTA_SUBIDATEST=1`.

## Riesgos residuales

1. **El historial sigue leyendo el audio entero** al guardarlo, ya con la
   transcripción hecha. No afecta a RF-02, que mide el momento de transcribir,
   pero es la última copia que queda en el camino.
2. **Los motores locales** que procesan el audio ellos mismos lo siguen
   recibiendo en memoria. Son locales: no hay envío que ahorrar, pero sí una
   lectura.
3. **El audio de trabajo ocupa disco**: ~115 MB por hora dictada, barrido a los
   días que fije el usuario. Con el ajuste en 0 no se barre nada y crece sin
   límite, que es justo lo que ese valor significa.
4. **`ScribeBatchClient` usaba `URLSession.shared`** y se corrigió de paso; no se
   ha auditado si queda algún otro punto de la aplicación fuera de la sesión
   compartida del dictado.
