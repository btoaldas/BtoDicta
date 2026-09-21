# ADR 006 — Cada informe de una página lleva solo el trozo nuevo

- Fecha: 2026-09-21
- Estado: Aceptada
- Spec: 008 — El texto que se guarda es el que se está leyendo

## Contexto

La spec 008 hace que una página se lea varias veces: al cargarla y cada vez que la
persona se detiene en un sitio nuevo. Con un tope de 40 informes por página, hay
que decidir qué lleva cada informe.

## Decisión

Cada informe lleva **solo los fragmentos que no se habían enviado todavía**. El
guion de contenido mantiene el acumulado en memoria —vive lo que vive la página— y
resta antes de emitir.

## Alternativa descartada: reenviar el acumulado entero

Es la más simple de escribir y la que menos estado necesita: cada informe se basta
a sí mismo, y quien recibe se queda con el último.

Se descarta por aritmética. Con hasta 40 informes por página y un máximo de 20 000
caracteres, una sola página larga podría dejar 800 000 caracteres en la bitácora,
casi todos repetidos. La spec 009 se está tomando el trabajo de eliminar 64,6 MB
de texto duplicado; introducir aquí una duplicación de hasta 40 veces sería
deshacerlo en la misma tanda.

La variante «actualizar la anotación anterior en vez de crear otra» evita la
duplicación, pero Alberto decidió el 2026-09-21 que cada lectura deje su propia
anotación con su hora, porque es lo que permite decir **qué se leyó y cuándo**.

## Consecuencias

- Cada anotación es un trozo, no el documento: quien lea la bitácora tiene que
  saberlo, y el resumen del día ya agrupa por ventana de tiempo, así que encaja.
- El acumulado vive en el guion de contenido y muere con la página. Si la pestaña
  se recarga, se vuelve a empezar — y es lo correcto: una recarga es otra lectura.
- Obliga a que el desalojo del presupuesto se decida **antes** de emitir, porque
  lo enviado no se puede retirar. De ahí el ADR 007.
