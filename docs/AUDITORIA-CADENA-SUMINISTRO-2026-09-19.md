# Auditoría de cadena de suministro — 2026-09-19

Tercera y última tanda. Las dos anteriores miraron el código propio; esta mira
**lo que la aplicación no escribió pero sí ejecuta**: los motores que viajan
dentro del paquete y los modelos que se descargan de internet.

Es la parte que más suele darse por buena, y la que peor se nota cuando falla:
un motor que no viajó no se ve hasta que alguien intenta dictar sin internet.

## Resumen

| | |
|---|---|
| Áreas revisadas | 4 |
| Hallazgos | **2** (1 alto, 1 medio) |
| Corregidos | 2, con prueba |

## Hallazgo 1 (ALTO) — un modelo se instalaba sin mirar qué era

`Descargas.bajar` movía a su sitio lo que llegara, sin comprobar **nada**: ni el
código de respuesta, ni el tamaño, ni el contenido.

Un 404, un aviso de mantenimiento o una pantalla de inicio de sesión —cualquier
cosa que un servidor devuelve cuando algo va mal— quedaba guardada con el nombre
del modelo. El fallo no aparecía al descargar, sino **después**, al usarlo, con
un mensaje incomprensible sobre un formato inválido.

**Corregido.** Antes de instalar se comprueba, en este orden: el código HTTP, que
pese más de un mega —ningún modelo de verdad pesa menos, una página de error sí—,
que no empiece por `<` (sería HTML), y que su firma corresponda a un formato que
la aplicación sabe cargar: GGUF, ggml, ONNX o un punto de control de PyTorch. Si
algo no cuadra, **no se instala nada** y el registro dice qué llegó.

Además se anota la **huella sha256** de cada modelo instalado en
`~/.btodicta/modelos-huellas.json`. Eso no hace segura la descarga —la primera vez
se confía en el servidor—, pero deja constancia: si un modelo cambia de contenido
sin que nadie lo haya vuelto a descargar, se puede ver.

`BTODICTA_MODELOTEST` lo comprueba con diez casos: cuatro cosas que deben
rechazarse, tres formatos legítimos que deben pasar, y tres sobre la huella.

### Lo que esta corrección rompió, y cómo se supo (añadido el 2026-09-19)

Comprobar la huella al arrancar dejaba una huella de memoria de **4 907 MB**.

El código leía el modelo «por trozos» de 1 MB, que es justamente lo que hay que
hacer y lo que hacía parecer que el asunto estaba resuelto. El problema era otro:
`FileHandle.read` devuelve un `Data` respaldado por un objeto **autoliberado**, y
sin drenar el depósito en cada vuelta los trozos no se sueltan — se acumulan
hasta que termina el bucle. Leer 4,8 GB de modelos de a un mega da exactamente
4,8 GB retenidos. **Leer de a poco no sirve de nada si no se suelta lo leído.**

Corregido envolviendo cada vuelta en `autoreleasepool`. Medido con el mismo
modelo de 2,83 GB: de +2 830 MB a **+1 MB**, y el pico del proceso pasó de
5 425 MB a 24 MB.

Dos cosas que deja esta corrección, más allá del arreglo:

- **`BTODICTA_HUELLAMEMTEST`**, que comprueba la huella de un modelo real ya
  instalado y verifica que la memoria no se mueve. Contra un archivo de juguete
  el fallo no aparece: hacen falta gigas de verdad.
- **Ninguna prueba de las que existían podía ver esto.** Todas medían
  `resident_size` (el RSS de `ps`), que en macOS incluye páginas ya liberadas y
  llegó a marcar 5 564 MB con 56 MB reales. La métrica que decide la presión de
  memoria es `phys_footprint`; ahora se mide esa, y `MemoriaProceso` es el único
  sitio donde se lee. Una prueba con la métrica equivocada no es una prueba.

Se descubrió al montar el dictado largo con micrófono real
(`BTODICTA_MICLARGOTEST`), que era una verificación pendiente de otra cosa: el
salto de memoria aparecía siempre entre el segundo 30 y el 60 de cada arranque,
y el registro de la aplicación puso la hora exacta al lado de la línea «modelos:
los del catálogo coinciden con su huella».

## Hallazgo 2 (MEDIO) — un paquete podía salir sin motores

Los ocho motores locales se copian al paquete desde carpetas de compilación del
desarrollador, con `if [ -x … ]` y **sin `else`**:

```make
@if [ -x $(HOME)/whisper.cpp/build/bin/whisper-cli ]; then \
    cp ... ; fi
```

Si esas carpetas no están —otra máquina, una limpieza, un cambio de nombre— la
copia se salta en silencio, el paquete se firma igual y se publica **sin motor
local**. Nadie se entera hasta que alguien intenta dictar sin internet.

**Corregido.** `scripts/qa-binarios.py` entra en el publicador, antes de firmar:
comprueba que los ocho están, que ninguno es un resto de menos de 10 kB, y que
todos son `arm64` —esta aplicación es solo Apple Silicon, y un binario x86 se
colaría sin más—. Sus huellas quedan en `docs/binarios-huellas.json`, así que un
cambio entre versiones se ve.

Probado en las dos direcciones: el paquete real pasa, y uno al que se le quitan
siete piezas falla nombrándolas una a una.

## Lo que se revisó y estaba bien

| Área | Resultado |
|---|---|
| Origen de las descargas | Todas por HTTPS, a repositorios de Hugging Face |
| Dependencias de Swift | **Ninguna**: la aplicación no trae bibliotecas de terceros |
| Versiones de los motores | whisper.cpp **1.9.1**, llama.cpp **build 10068** — recientes |

## Riesgos residuales, dichos claros

1. ~~**La primera descarga se confía.**~~ **Cerrado el 2026-09-19 (0.66.1).** Las
   huellas de los cuatro modelos del catálogo están fijadas en
   `Resources/modelos-conocidos.json`, tomadas de la cabecera `x-linked-etag`
   que Hugging Face publica para cada archivo LFS y **contrastadas una a una
   contra los archivos ya instalados**: las cuatro coincidían.

   Ahora un modelo del catálogo que no sea exactamente el esperado se rechaza,
   aunque venga del sitio de siempre y tenga el formato correcto. Un modelo que
   NO esté en el catálogo se sigue aceptando: el usuario puede bajar el GGUF que
   quiera, y no es cosa nuestra impedirlo.

   Los ya instalados también se comprueban, una vez al arrancar y en segundo
   plano. Solo avisa: que un modelo cambie puede ser legítimo —su repositorio lo
   actualizó— y esa decisión es de su dueño, no de la aplicación.
2. **Los binarios se compilan a mano** en las carpetas del desarrollador. No hay
   compilación reproducible: dos máquinas darían huellas distintas. Lo que se
   vigila es que no cambien sin motivo, no de dónde vienen.
3. **No se auditan las vulnerabilidades** de whisper.cpp ni de llama.cpp. Son
   proyectos vivos; actualizarlos es una decisión con su propio riesgo, porque
   una versión nueva puede cambiar el comportamiento de los motores.
4. **Los modelos ya instalados** antes de esta versión no tienen huella anotada.
   Se irán anotando según se vuelvan a descargar.
