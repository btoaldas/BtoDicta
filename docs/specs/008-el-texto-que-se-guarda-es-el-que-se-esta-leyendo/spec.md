# Spec 008 — El texto que se guarda es el que se está leyendo

- Estado: Aprobada
- Tipo: cambio
- Nivel: X (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-21
- Modifica: 006
- Aprobada por: Alberto — 2026-09-21 — «resuelve aprobado te doy»
- Rama: main

## 1. Problema y propósito

La extensión lee la página **una sola vez**, 1,2 s después de cargarla, recorre el
documento desde el principio y corta a 20 000 caracteres. En una página larga eso
guarda la cabecera y el menú mientras la persona está leyendo el centro, media
hora más tarde y varias pantallas más abajo.

Medido el 2026-09-21: de las 22 páginas que la extensión lleva aportadas, **12
quedaron cortadas exactamente en el tope**. Sobre un artículo real de 178 249
caracteres, el tope guarda el 11 % del texto; leyéndolo por la mitad, **42 de los
81 fragmentos que estaban en pantalla caen fuera de lo que se envía**.

El propósito es que lo que la bitácora guarde de una página sea lo que se estuvo
mirando, y que una misma página leída dos veces deje constancia de las dos.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Persona que dicta | El dueño del equipo | El resumen del día cita lo que de verdad leyó, no el menú de la página |
| La extensión | El sensor dentro del navegador | Deja de mandar el principio del documento como si fuera lo consultado |
| BtoDicta | La aplicación de escritorio | Recibe varias lecturas de una misma página y puede situarlas en el tiempo |

## 3. Alcance

### Incluye

- Volver a leer la página cuando cambia lo que la persona tiene delante.
- Que lo que estuvo en pantalla tenga preferencia sobre lo que nunca se vio,
  cuando no cabe todo.
- Que cada lectura de una página deje su propia anotación con su hora.
- Que el máximo de texto por página se pueda cambiar, con 20 000 de fábrica.
- Conservar íntegra la bitácora ya grabada al cambiar la forma en que se guarda.

### No incluye (con razón)

- **Páginas que cambian de dirección sin recargarse** (aplicaciones de una sola
  página). El guion de contenido no vuelve a arrancar y detectarlo pide vigilar el
  historial del navegador; queda para otra spec y se anota como límite conocido.
- **Guardar la página entera.** Subir el tope hasta cubrir cualquier documento
  (9x el actual para el caso medido) hace crecer la bitácora sin arreglar la causa:
  seguiría cortando desde arriba. Se descarta como vía principal; quien la quiera
  la tiene en el ajuste del RF-04.
- **Tocar el OCR ni la captura periódica de pantalla.** Siguen exactamente igual.
- **Cambiar qué NO se lee.** La regla de la spec 006 —nada de lo que el usuario
  escribe— no se toca, ni se hace configurable.

## 4. Requerimientos funcionales

Formato de sw-requerimientos: actor, acción, resultado, medida. Máximo 12.

### RF-01 — Se vuelve a leer lo que la persona tiene delante

- Actor: la extensión
- Acción: vuelve a informar del texto de la página cuando la persona deja de
  desplazarse en un sitio distinto del que ya se informó
- Resultado: la bitácora guarda el texto de la parte que se estuvo leyendo, y no
  solo el principio del documento
- Medida: en una página de 178 249 caracteres leída por la mitad, el texto
  guardado contiene al menos el 80 % de las palabras que estuvieron en pantalla;
  hoy son 0 % de las que caen más allá del tope
- Prioridad: P1
- Criterio de aceptación:
  - Dado un artículo largo abierto en el navegador
  - Cuando la persona baja hasta la mitad y se detiene a leer
  - Entonces lo que la bitácora guarda de esa página incluye lo que tuvo delante

### RF-02 — Lo que estuvo en pantalla no se desaloja

- Actor: la extensión
- Acción: cuando el texto acumulado llega al máximo, descarta antes lo que nunca
  estuvo a la vista que lo que sí se miró
- Resultado: en una página que no cabe entera, lo guardado es lo leído
- Medida: con el máximo alcanzado, cero fragmentos vistos en pantalla descartados
  mientras queden fragmentos no vistos por descartar
- Prioridad: P1
- Criterio de aceptación:
  - Dado un documento cuyo texto supera el máximo configurado
  - Cuando se ha leído una parte que está más allá del corte
  - Entonces esa parte aparece en lo guardado y el relleno no mirado es lo que falta

### RF-03 — Cada lectura deja su propia anotación

- Actor: BtoDicta
- Acción: anota cada informe de una misma dirección como una entrada propia, con
  la hora en que llegó
- Resultado: el resumen del día puede decir qué se leyó y cuándo, aunque sea la
  misma página dos veces en momentos distintos
- Medida: dos informes de la misma dirección separados en el tiempo producen dos
  entradas; hoy el segundo se descarta en silencio
- Prioridad: P1
- Criterio de aceptación:
  - Dado que la página ya quedó anotada esta mañana
  - Cuando se vuelve a leer por la tarde
  - Entonces quedan dos anotaciones, cada una con su hora y su texto

### RF-04 — Cuánto texto se guarda por página es ajustable

- Actor: la persona que dicta
- Acción: cambia el máximo de caracteres por página desde la pantalla de opciones
  de la extensión
- Resultado: quien quiera guardar artículos enteros puede hacerlo sin tocar código,
  y de fábrica no cambia nada respecto a hoy
- Medida: valor de fábrica 20 000; un valor nuevo surte efecto en la siguiente
  página leída, sin volver a instalar la extensión
- Prioridad: P2
- Criterio de aceptación:
  - Dado el ajuste puesto en 60 000
  - Cuando se lee un artículo de 178 249 caracteres
  - Entonces lo guardado de esa página llega a 60 000 y no a 20 000

### RF-05 — Ninguna anotación anterior se pierde

- Actor: BtoDicta
- Acción: al cambiar la forma en que la bitácora guarda las páginas, conserva
  todas las anotaciones ya grabadas
- Resultado: la bitácora anterior sigue completa y consultable, y el resumen del
  día de fechas pasadas no cambia
- Medida: recuento de anotaciones y suma de longitudes de texto idénticos antes y
  después; el equipo tiene hoy 29 605 anotaciones y 40,95 MB de texto
- Prioridad: P1
- Criterio de aceptación:
  - Dado un archivo de bitácora con anotaciones de meses anteriores
  - Cuando BtoDicta arranca con esta versión
  - Entonces el recuento y el texto son los mismos que antes de arrancar

## 5. Requerimientos no funcionales

Un RNF sin cifra es un deseo.

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Capacidad | El informe enviado no supera 1 MiB ni con la captura de pestaña activa (tope de la API local, que responde 413) | Informe de la página más larga medida, con capturas activadas, contra `/navegador` |
| RNF-02 | Rendimiento | Una re-lectura cuesta menos de 100 ms sobre un documento de 178 249 caracteres y 6 653 fragmentos | Medición en el propio navegador sobre esa página |
| RNF-03 | Rendimiento | Como mucho una re-lectura cada 10 s por pestaña, y como mucho 40 informes por página cargada | Contador en las pruebas de la extensión con desplazamientos simulados |
| RNF-04 | Capacidad | Con el valor de fábrica, la bitácora no crece más de 2 MB al día por páginas del navegador | Suma de texto de las páginas de un día real, antes y después |
| RNF-05 | Seguridad | 0 apariciones de lo que el usuario escribe en cualquiera de las re-lecturas: campos, áreas editables y contraseñas | Las pruebas de la spec 006 (T06) corridas contra el nuevo recorrido |
| RNF-06 | Disponibilidad | El cambio de forma de la bitácora se ejecuta 1 vez, con respaldo previo verificado y vuelta atrás probada | Respaldo comparado por recuento y suma de texto; ensayo de reversión |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| Página de desplazamiento infinito (una cronología de red social) | El límite de informes por página corta el goteo; lo guardado es lo primero que se leyó, no un envío por cada rueda de ratón | RNF-03 |
| Pestaña en segundo plano o ventana minimizada | No hay nada en pantalla que priorizar, y no se vuelve a leer. Medido hoy: con el panel oculto el navegador informa alto de ventana 0 y ningún fragmento resulta visible | RF-01 |
| Dominio excluido por el usuario | Sigue sin leerse, también en las re-lecturas: la comprobación va antes que todo lo demás | RF-01 |
| BtoDicta cerrada mientras se lee | El informe se descarta, no se encola: la extensión no es un almacén (regla de la spec 006) | RF-01 |
| Extensión nueva contra una versión vieja de BtoDicta | Las re-lecturas se descartan como hoy, sin error visible y sin romper nada | RF-03 |
| Página sin texto visible (un visor de vídeo, un lienzo) | No se informa nada, como hoy: por debajo de 40 caracteres no hay contenido que anotar | RF-01 |
| La misma dirección abierta en dos pestañas a la vez | Cada pestaña acumula lo suyo y deja su anotación; ninguna pisa a la otra ni se mezclan los textos | RF-03 |
| El cambio de forma de la bitácora se interrumpe a medias | La bitácora anterior queda intacta y el respaldo permite volver; nunca un estado a medio camino | RF-05 |
| Página que cambia de dirección sin recargar | Queda con la lectura de la primera dirección. Límite conocido y declarado fuera de alcance | — |

## 7. Datos y cumplimiento

- Datos que trata: los mismos que la spec 006 — direcciones de páginas visitadas y
  texto visible de esas páginas, en el equipo y sin salir de él.
- Datos personales: sí, los que aparezcan en lo que se lee. No cambia respecto a
  006: mismo almacenamiento local, misma retención configurable de la bitácora,
  mismos dominios excluibles. Esta spec aumenta **cuánto** texto de una página se
  guarda, no **qué clase** de texto.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- La spec 006 está implementada y en uso: extensión, API local en `127.0.0.1:8787`
  y filtro de la bitácora funcionando.
- El navegador informa de la posición y el tamaño de lo que está en pantalla. En
  una pestaña sin pintar eso vale cero, y el comportamiento en ese caso está en
  los casos límite.
- El cambio de la forma de la bitácora se ejecuta sobre la base viva del equipo
  (192 MB, 29 605 anotaciones). **Requiere visto bueno propio y separado de
  Alberto antes de correr**, con respaldo previo verificado, según la regla dura
  de la oficina.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-21

- P: De las tres vías (priorizar lo visible, subir el tope, trocear), ¿cuál se
  implementa? → R: re-leer al desplazarse y priorizar lo visible —vías 1 y 3
  combinadas—, porque priorizar lo visible por sí solo no arregla nada: el guion
  de contenido lee una sola vez, 1,2 s tras cargar, cuando lo visible todavía es
  el principio (decisión de Alberto).
- P: Cuando la misma dirección vuelve a informar, ¿se actualiza la anotación o se
  crea otra? → R: **una anotación por lectura** (decisión de Alberto). La
  recomendación del agente era actualizar la existente por ser más barata y no
  exigir cambiar la forma de la bitácora; Alberto elige la fiel a la línea de
  tiempo. Consecuencia asumida: hay que cambiar la forma en que la bitácora
  garantiza que no se anota dos veces la misma captura, sobre la base viva, y eso
  pasa por el RF-05 y su respaldo.
- P: ¿El tope de 20 000 se queda? → R: **parametrizable**, con 20 000 de fábrica
  (decisión de Alberto), coherente con la regla de la oficina de que toda
  funcionalidad nueva se pueda activar, desactivar o configurar.
- P: ¿Rama propia o main? → R: main, como en las specs 006 y 007 (decisión de
  Alberto).
