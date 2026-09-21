# ADR 008 — El índice apunta al texto en vez de copiarlo, y la unicidad se vuelve parcial

- Fecha: 2026-09-21
- Estado: Aceptada
- Specs: 008 — El texto que se guarda es el que se está leyendo · 009 — Buscar por
  palabras en la bitácora (**una sola migración, decisión de Alberto**)

## Contexto

Medido el 2026-09-21 sobre la bitácora real de 177,2 MB:

- Los dos índices de búsqueda ocupan **92,1 MB, el 52 % del archivo**, y **ningún
  sitio del código los consulta**: no hay una sola consulta de índice en Swift, ni
  búsqueda por recorrido de texto, ni campo de búsqueda en la pestaña, ni modo de
  consulta en la API local.
- De esos 92,1 MB, **64,6 MB son una segunda copia del mismo texto** ya guardado
  aparte: 40,77 MB indexados frente a 41,05 MB guardados.
- La dirección de una anotación de pantalla es única en toda la tabla. Para un
  archivo de captura eso protege de indexarlo dos veces; para una página web hace
  que el segundo informe **se descarte en silencio**.
- El alta en el índice inserta sin borrar lo anterior, y el texto que aporta la
  extensión de navegador **nunca entra al índice**.

## Decisión

Tres cambios, en una sola migración:

1. Los índices se recrean **de contenido externo**: apuntan al texto ya guardado
   en lugar de copiarlo.
2. Se mantienen al día mediante **disparadores** en las tablas base, en alta,
   cambio y borrado, en vez de a mano desde el código.
3. La unicidad de la dirección deja de aplicarse a toda la tabla y pasa a un
   **índice único parcial** que cubre solo lo que no es una dirección web.

## Alternativas descartadas

**Retirar los índices y no buscar nunca.** Recuperaría 92,1 MB ahora y unos 268 MB
en el estado estacionario de 90 días. Se descarta porque una bitácora de 90 días
existe para consultarla: hoy solo se puede mirar la lista de lo reciente, y la
propia pantalla de ajustes ya promete una búsqueda por palabras que no existe.

**Dejar el índice como está y solo construir la búsqueda.** Funcionaría, y
mantendría los 64,6 MB de copia para siempre por no tocar nada.

**Seguir manteniendo el índice a mano desde el código.** Es lo que hay hoy, y ya
se le escaparon dos caminos: el texto del navegador y la posibilidad de duplicar.
Un mecanismo que la base de datos ejecuta sola no se puede olvidar en una edición.

**Quitar la unicidad de la dirección por completo.** Más simple de escribir, pero
perdería la protección real contra indexar dos veces el mismo archivo de captura.

## Consecuencias

- El archivo pasa de 177,2 MB a 112,6 MB o menos, y unos 188 MB menos en el
  estacionario.
- Hay que quitar el alta y el borrado manuales del índice: con disparadores serían
  dobles.
- **La trampa del contenido externo**: al borrar una anotación, el índice necesita
  el texto anterior para deshacer lo indexado. El disparador de borrado debe
  emitirlo. Se prueba con un borrado real sobre una copia antes de tocar nada.
- **Que quitar la copia no ralentice la búsqueda es un supuesto, no un hecho.** El
  índice invertido de 26,7 MB debería bastar para responder en menos de 300 ms,
  pero eso se mide en la verificación. Un número que no se ha medido no es una
  garantía.
- La migración toca datos reales: exige la aplicación parada, respaldo verificado,
  ensayo sobre copia y un visto bueno propio y separado de Alberto.
