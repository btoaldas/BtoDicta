# Modelo de datos y migración — Specs 008 + 009 (una sola migración)

Decisión de Alberto del 2026-09-21: las dos specs reconstruyen lo mismo, así que
se ejecutan en **un solo paso**, con un respaldo, un ensayo sobre copia y una sola
ventana de riesgo.

## 1. Estado actual, medido el 2026-09-21

Archivo: `~/BtoDicta Bitácora/bitacora.sqlite` — 177,2 MB según `dbstat`
(185 778 176 bytes en disco más 749 872 del diario de escritura).

| Objeto | MB | Qué es |
|---|---|---|
| `pantalla` | 63,3 | lo guardado de la pantalla y del navegador |
| `pantalla_texto_content` | 55,9 | **copia literal del texto que ya está en `pantalla.texto`** |
| `pantalla_texto_data` | 23,0 | índice invertido — lo único que serviría para buscar |
| `audio` | 13,0 | lo guardado del micrófono |
| `audio_texto_content` | 8,7 | **copia literal otra vez** |
| `audio_texto_data` | 3,7 | índice invertido |
| `sqlite_autoindex_audio_1` | 3,1 | unicidad de `audio.ruta` (archivo real: **se conserva**) |
| `sqlite_autoindex_pantalla_1` | 2,4 | unicidad de `pantalla.ruta` (**es lo que estorba**) |
| resto | 4,1 | índices por instante y por pendientes, docsize, config |

Recuentos: 29 605 anotaciones de pantalla · 40 697 de audio · 28 549 y 28 753
indexadas respectivamente (**0 duplicadas, 0 huérfanas** — el índice está sano).
Texto guardado: 41,05 MB de pantalla y 7,33 MB de audio; el índice contiene 40,77 MB
de ese mismo texto. Ventana cubierta: 31 días (20-ago a 21-sep), retención 90 días
con purga automática.

## 2. Qué estorba y por qué

1. **`pantalla.ruta` es única en toda la tabla.** Para las capturas, `ruta` es el
   archivo y la unicidad protege de indexar dos veces la misma imagen. Para las
   páginas del navegador, `ruta` es la dirección, y la unicidad hace que el segundo
   informe de una misma página **se descarte en silencio** (`anotarTextoDeNavegador`
   devuelve `false` y nadie lo mira). La spec 008 lo necesita al revés.
2. **El índice guarda una segunda copia del texto.** FTS5 sin `content=` mantiene
   su propia copia en `%_content`: 64,6 MB de los 92,1 MB que ocupan los índices.
3. **El alta en el índice inserta sin borrar lo anterior**
   (`ContinuoIndice.swift:244`). Hoy hay 0 duplicadas, pero un segundo
   reconocimiento de la misma anotación la dejaría dos veces.
4. **El texto del navegador nunca entra al índice**: `anotarTextoDeNavegador`
   escribe en la tabla y no en el índice.

## 3. Estado objetivo

- `pantalla` sin unicidad de columna sobre `ruta`; en su lugar un **índice único
  parcial** `WHERE ruta NOT LIKE 'http%'`, que sigue protegiendo los archivos de
  captura y deja que una dirección web se repita.
- `pantalla_texto` y `audio_texto` recreados como FTS5 **de contenido externo**
  (`content='pantalla'`, `content_rowid='id'`), con una sola columna `texto`. La
  columna `fila` desaparece: el identificador de la anotación **es** el rowid.
- **Disparadores** en las tablas base que mantienen el índice al día por sí solos
  en alta, cambio y borrado. Con ellos:
  - el texto del navegador queda indexado sin tocar `anotarTextoDeNavegador`
    (cierra el RF-04 de la 009 de regalo),
  - el alta duplicada deja de ser posible,
  - la purga deja de necesitar su borrado manual del índice.
- `anotarTexto` deja de insertar a mano en el índice: lo haría dos veces.

Efecto esperado: **177,2 MB → 112,6 MB o menos** (64,6 MB recuperados), y ~188 MB
menos en el estado estacionario de 90 días.

## 4. Orden de la migración

Precondiciones, las tres obligatorias:

1. **BtoDicta parada.** La bitácora está viva: entre dos mediciones separadas por
   minutos aparecieron 101 anotaciones nuevas. Migrar bajo escritura es corromper.
2. **Respaldo verificado** por recuento y suma de longitudes de texto, no por
   tamaño de archivo. Hay precedente en la carpeta:
   `bitacora-respaldo-antes-de-rutas.sqlite`.
3. **Ensayo completo sobre una copia** con los números delante (RF-06 de la 009).
   Solo entonces se pide el visto bueno para la bitácora real.

Pasos, todo dentro de una transacción salvo el último:

1. `PRAGMA foreign_keys=off`, `BEGIN IMMEDIATE`.
2. Crear `pantalla_nueva` con el mismo esquema **sin** `UNIQUE` en `ruta`.
3. Copiar las 29 605 anotaciones.
4. Retirar la anterior, renombrar, recrear los índices por instante y por
   pendientes, y crear el índice único parcial.
5. Retirar los cuatro objetos del índice antiguo de pantalla y audio y crear los
   dos nuevos de contenido externo.
6. Reconstruir el índice desde el texto ya guardado:
   `INSERT INTO pantalla_texto(pantalla_texto) VALUES('rebuild')`, ídem audio.
7. Crear los disparadores de alta, cambio y borrado.
8. `COMMIT`.
9. `VACUUM` fuera de la transacción: sin él el archivo no devuelve el espacio.

## 5. Verificación (antes de darla por buena)

| Qué | Cómo | Valor esperado |
|---|---|---|
| No se perdió nada | recuentos de `pantalla` y `audio` | 29 605 y 40 697, más lo que se anote entre medias |
| El texto está entero | suma de longitudes de `texto` | 41,05 MB y 7,33 MB |
| El índice cubre todo | recuento indexado contra anotaciones con texto | sin huecos |
| La búsqueda encuentra | una palabra conocida de una anotación conocida | la devuelve |
| El navegador entra | una palabra de una de las 22 páginas aportadas | la devuelve (hoy: 0) |
| Se recuperó espacio | `dbstat` y tamaño en disco | ≤ 112,6 MB |
| La protección sigue | intentar anotar dos veces el mismo archivo de captura | se rechaza |
| Una dirección se repite | dos informes de la misma página | dos anotaciones |

## 6. Vuelta atrás

Parar BtoDicta, sustituir el archivo por el respaldo, arrancar. El respaldo se
conserva hasta que pase una semana de uso normal — **no se borra al terminar**, y
borrarlo exige su propio visto bueno.

## 7. Lo que NO hace esta migración

No cambia la retención ni la purga, no toca los archivos de audio ni las imágenes
en disco, no borra ni una anotación, y no altera qué material se guarda.
