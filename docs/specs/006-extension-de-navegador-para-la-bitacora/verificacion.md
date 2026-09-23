# Verificación 006 — Extensión de navegador para la bitácora

- Fecha: 2026-09-20
- Spec: `spec.md` (Aprobada 2026-09-20, nivel X)
- Estado del QA al verificar: **26 pruebas, 0 fallos** (código de salida 0)

## Requerimientos funcionales

| RF | Qué exigía | Cómo se comprobó | Segundo ángulo | Veredicto |
|---|---|---|---|---|
| RF-01 | Saber qué pestaña suena, en < 2 s | Informe con correo activo y vídeo audible: la API devuelve `activa=correo`, `audible=vídeo`. Reporta en cada cambio de pestaña, de audio y de URL, más latido de 30 s | El filtro decide con ese dato: vídeo detrás → se graba; vídeo delante → se aparta. Y degrada en tres casos (informe caducado, sin extensión, otro navegador) | Cumple |
| RF-02 | Texto en vez de OCR, ≥ 90 % de cobertura | **La medida de la spec estaba mal planteada, y la primera corrección TAMBIÉN** (ver §Desviaciones). Comparando cada página contra el OCR de esa misma página: **mediana 1,5×**, de 0,2× a 4,3×. Cumple con menos margen del que se dijo | En el índice queda `procesado=1`: 0 pendientes de OCR para esas páginas, frente a 11 capturas normales que sí esperan | Cumple |
| RF-03 | Captura de la pestaña, sin barras ni ventanas encima | `captureVisibleTab` captura la pestaña, no la pantalla: por construcción no incluye lo que haya delante. `{"captura_guardada":true}` y archivo en `BtoDicta Bitácora/navegador/` | Apagada de fábrica; con un dominio excluido ni se captura | Cumple |
| RF-04 | Sin la extensión, todo igual | `qa-paquete.sh` pasa igual con y sin ella. La prueba de exportación se omite sola cuando no hay paquete | Tres formas de degradar probadas en RF-01 | Cumple |
| RF-05 | Excluir dominios: 0 envíos | 12 comprobaciones: normalización, subdominios incluidos, dominios parecidos excluidos, lista vacía no excluye nada | De un dominio excluido se calla URL y título, pero se mantiene el dato de que suena — sin contenido, y es el que evita anotar una película como trabajo | Cumple |
| RF-06 | Un paquete para Chrome, Edge y Brave | Manifest V3 válido, 10 archivos, cero declarados que falten. **Cargado y funcionando en Edge** | Huella SHA256 del código idéntica en ambos paquetes: `3bcce352fb2824b3`. Chrome y Brave sin cargar, pero comparten motor | Cumple |
| RF-07 | Firefox | Manifiesto propio con `scripts` e identificador de Gecko; capa `chrome.*`/`browser.*` | **Nadie lo ha cargado en Firefox**: decisión de probar solo con Edge | No cumple |
| RF-08 | Avisar si la extensión envejece | Con 0.0.1 frente a 0.1.0: detectada, con ambas versiones. Aviso en Ajustes y en la respuesta al informe | Una al día no avisa; una que no dice su versión tampoco — mejor callar que avisar en falso | Cumple |
| RF-09 | Sacarla de la app con su manual | Botón en Ajustes. Deja `manifest.json`, el código y `COMO-INSTALAR.md` con la versión de la que salió | Exportar dos veces reemplaza sin fallar; lo anterior va a la Papelera por si había algo dentro | Cumple |
| RF-10 | Menú en el icono, excluir con un clic | `default_popup` declarado y presente. Cuatro estados de conexión distinguidos | El mismo botón excluye y devuelve. Comprobado en pantalla el 2026-09-20 sobre Edge | Cumple |
| RF-12 | Autodiagnóstico que diga si funciona | **Comprobado en pantalla el 2026-09-20**: las seis comprobaciones en verde, incluida «Tus avisos llegan — 1 informe vigente». Antes de eso la pantalla nacía muerta (ver §Desviaciones) | Desde el otro lado: `GET /navegador` devuelve el informe con `hace_segundos: 7`, y la bitácora registra páginas de 20 000 letras con `procesado=1` | Cumple |
| RF-11 | Ponerse al día sola | Ruta degradada a 0.0.9 a propósito → al reabrir pasa sola a 0.1.0 con su aviso | Solo copia si hay diferencia: reescribir siempre haría que el navegador la viera modificada en cada arranque | Cumple |

## Requerimientos no funcionales

| RNF | Exigía | Resultado | Veredicto |
|---|---|---|---|
| RNF-01 | Token y solo loopback | Sin token 401 · token falso 401 · JSON inválido 400 · cuerpo de 1,6 MB **413** · desde la IP de la red, sin respuesta | Cumple |
| RNF-02 | < 50 ms y < 30 MB en el navegador | **No medido**: aislarlo exige comparar el navegador con y sin la extensión, y eso pasa por descargarla del que está en uso. Consta: 60 kB en disco, 638 líneas, un trabajo por página | No cumple |
| RNF-03 | 0 envíos de contraseñas o formularios | 0 coincidencias de los 2 valores tecleados. Probado **en las dos direcciones**: al retirar la exclusión de campos, las 2 comprobaciones de secreto dan rojo | Cumple |
| RNF-04 | Con la app cerrada: ≤ 1 intento/min y 0 acumulado | Un fallo impone 60 s de espera; nada se guarda pendiente. La prueba encontró que `leerToken()` lanzaba sin almacén — corregido | Cumple |

## Desviaciones respecto a la spec

**El RF-02 tenía una medida mal elegida, y la escribí yo.** Decía «al menos el
90 % de las palabras que hoy produce el OCR de esa misma pantalla». Pero el OCR
lee **toda la pantalla** —menús, barras, otras ventanas— y la extensión lee **una
página**: son conjuntos distintos. La primera medición dio 8,5 % y el número era
correcto; lo absurdo era la comparación, que enfrentaba una página de Amazon con
el OCR de una ventana de Claude abierta al lado.

Medido de la forma que el requisito quería decir —cuánto texto aporta cada vía—
el primer resultado fue **11,3×**. **Ese número también estaba mal medido**, y se
corrige aquí el 2026-09-22: salía de dividir la media de unas páginas de Amazon
enormes entre la media de TODAS las capturas del equipo, que son dos poblaciones
distintas.

Comparando cada página contra el OCR de **esa misma página**, la cifra honesta es
una **mediana de 1,5×**, con un reparto ancho: 0,2× en la peor y 4,3× en la mejor.
El requisito se cumple —la mitad de las páginas aporta al menos tanto texto como
el OCR, y sin errores de lectura— pero con mucho menos margen del que se dijo. La
cola baja tiene causa conocida: el tope de 20 000 caracteres desde el principio
del documento.

**Orden de tareas alterado** a petición de Alberto: T15 (empaquetado) se adelantó
a T13 y T14 para poder cargar la extensión y probarla antes de seguir. Las
cerraduras ya estaban hechas, así que no se saltó ninguna protección.

**Cuatro requisitos nacieron después de aprobar la spec** (RF-08 a RF-11), todos
de usar la extensión de verdad. Cada uno con su entrada fechada en §9 de la spec.

**La pantalla de opciones estuvo muerta y las pruebas decían que no.** Una
edición dejó dos funciones y los dos `addEventListener` de los botones dentro
del callback de otro botón: el archivo parseaba, `node --check` lo aprobaba, y
el botón de guardar la clave no tenía listener. El guardián escrito para esto
buscaba una cadena de texto en el fuente —que estaba, intacta— y daba verde
contra una pantalla muerta. Sustituido por una carga real del módulo contra un
DOM simulado. Detalle en `docs/bitacora/2026-09-20.md`.

## Dos listas de exclusión que no se hablan

Constatado el 2026-09-20, sin decidir todavía:

- La lista de **la extensión** (almacén del navegador) impide que la URL y el
  título salgan siquiera del navegador. Hoy está vacía.
- La lista de **BtoDicta** (`bitacora_excluir_titulos`) impide grabar cuando eso
  está al frente. Hoy tiene cinco entradas.

Ambas son legítimas y significan cosas distintas, pero nada las sincroniza: quien
excluya un dominio desde el menú del icono no lo verá reflejado en BtoDicta, ni al
revés. Queda como decisión pendiente de Alberto, no como defecto.

## Riesgos residuales

- **Firefox sin probar.** El código está; nadie lo ha cargado.
- **Chrome y Brave sin cargar.** El paquete es el mismo que funciona en Edge, y
  comparten motor, pero «debería funcionar» no es «funciona».
- **El coste en el navegador no está medido** (RNF-02).
- **«Leer todo salvo lo excluido»** es la postura con más superficie. Se compensa
  con que nunca se leen campos de contraseña y con que excluir cuesta un clic,
  pero el riesgo de capturar algo sensible **antes** de excluirlo es real y fue
  una decisión consciente de Alberto.
- **La extensión no se auto-actualiza** y no puede: lo impide el navegador. Se
  mitiga con la ruta fija, pero recargarla sigue siendo un acto humano.
- **El texto de la página se corta a 20 000 caracteres, empezando por arriba.**
  Descubierto el 2026-09-21 midiendo por qué el solapamiento con el OCR daba
  44,6 %. `extraerTexto` recorre el documento desde el principio: en una página
  larga leída por la mitad se envía el principio mientras el usuario mira el
  centro. Varias páginas quedaron registradas con exactamente 20 000 letras, que
  es la firma del tope. No resuelto; hay tres vías (priorizar lo visible, subir el
  tope midiendo el coste, o trocear) y la decisión no es de esta spec.
- **Un trozo de audio que empieza en una página y termina en otra se conserva**
  entero. Ante la duda se guarda, pero en cada transición pueden colarse hasta
  30 s de lo que no se quería.


## Por qué este hito NO se puede cerrar todavía

Dos requisitos quedan en **No cumple**, y no por estar mal hechos sino por no
estar comprobados:

- **RF-07 (Firefox)**: el código está escrito y el paquete se construye, pero
  nadie lo ha cargado en Firefox. Decisión de Alberto: probar solo con Edge por
  ahora.
- **RNF-02 (coste en el navegador)**: medirlo exige comparar el navegador con y
  sin la extensión, y eso pasa por descargarla del que está en uso.

Marcarlos «Cumple» sería exactamente la clase de afirmación sin prueba que este
documento existe para evitar. Un requisito no verificado no es un requisito
cumplido, por mucho que el código esté escrito.

Hay dos salidas legítimas, y la elección es de Alberto:

1. **Verificarlos**: cargar la extensión en Firefox y medir el coste.
2. **Diferirlos** a otra spec, con lo ya hecho cerrado como está.
