# ADR 007 — El primer informe de una página no gasta todo el presupuesto

- Fecha: 2026-09-21
- Estado: Aceptada
- Spec: 008 — El texto que se guarda es el que se está leyendo

## Contexto

Una página se lee por primera vez 1,2 s después de cargar, cuando lo visible es el
principio. Si ese primer informe llena el máximo de caracteres, el acumulado queda
completo antes del primer desplazamiento y ninguna re-lectura puede aportar nada.

Sería reproducir exactamente el fallo que la spec 008 corrige, esta vez con más
código.

## Decisión

El primer informe llena como mucho el **30 % del máximo** con relleno en orden de
documento (6 000 caracteres con el valor de fábrica), más todo lo que esté a la
vista. El 70 % restante queda reservado para lo que se lea después.

## Alternativa descartada: llenar el tope de entrada, como hoy

Tiene una ventaja real: una página que se abre y se cierra sin desplazarse queda
con 20 000 caracteres en vez de 6 000.

Se descarta porque ese caso —abrir y no leer— es justo en el que menos importa lo
que se guarde, mientras que el caso contrario —abrir y leer a fondo— es el que la
spec existe para arreglar. Además, medido el 2026-09-21: una pantalla sostiene
unos 2 900 caracteres, así que 6 000 cubren la primera pantalla y algo más; y una
página que de verdad cabe entera en el 30 % se envía entera de todas formas,
porque el relleno se agota antes que el presupuesto.

## Consecuencias

- Una página larga abierta y abandonada guarda menos que hoy. Aceptado y escrito.
- El 30 % es un número elegido, no medido: queda como lo primero que revisar si
  la verificación de la spec enseña otra cosa. Se implementa como constante con
  nombre, no esparcido por el código.
