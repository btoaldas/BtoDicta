# Plan 001 — Memoria del dictado largo · segunda etapa

- Estado: Aprobado
- Fecha: 2026-09-18
- Aprobado por: Alberto — 2026-09-18 — «Aprobado, y sigue hasta implementar»
- Puerta 3 (tareas): **autorizada por anticipado** en la misma respuesta. Se
  escribe `tasks.md` y se implementa tarea por tarea con evidencia, sin
  detenerse en cada una; cualquier desviación respecto al plan sí vuelve a él
- Spec: `spec.md` (Aprobada 2026-09-14, nivel X)
- Cubre: RF-01 (parcial) y RF-02 (parcial); no toca RF-03, RF-04 ni RF-05, ya cumplidos

## 1. Qué queda por hacer

La primera etapa (0.60.0) quitó la copia de audio **al grabar**: el archivo es la
única fuente y seis horas simuladas suben 0 MB. Lo que falta es la copia **al
transcribir**.

Al medirlo con el grafo del código aparece que la copia no es una, son **dos**:

```
Recorder → .wav en disco (691 MB en 6 h)
   ↓ Data(contentsOf:)                    copia 1 — el audio entero en RAM
wav: Data
   ↓ body.append(wav)                     copia 2 — el multipart entero en RAM
body: Data
   ↓ uploadTask(with:from: body)          URLSession retiene el cuerpo
```

Un dictado de seis horas necesita **~1,4 GB** en el instante del envío, no 691 MB
como decía la spec. La spec no se corrige hacia atrás en silencio: se anota aquí y
en §9 de `spec.md` con fecha.

## 2. Los doce sitios, medidos

`uploadTask(with:from:)` con el cuerpo en memoria, según el grafo:

| Archivo | Sitios | Notas |
|---|---|---|
| `TranscribeProviders.swift` | 7 | Incluye uno que envía `from: wav` sin multipart |
| `ScribeBatchClient.swift` | 2 | **Usan `URLSession.shared`, no `RedDictado.sesion()`** |
| `WhisperServer.swift` | 1 | Motor local por HTTP |
| `FishAudio.swift` | 1 | |
| `ScribeBatchClient.transcribeFile(url:)` | — | Ya recibe una `URL`, pero la lee entera con `fileData` |

### Hallazgo fuera del alcance de la spec

Los dos sitios de `ScribeBatchClient` usan `URLSession.shared`. El arreglo de
`Connection: close` de 0.59.0 —que renueva la sesión para que el dictado
siguiente no herede un socket cerrado— se aplicó a `RedDictado.sesion()` y **no
los cubre**. No es un problema de memoria y no entra en esta spec; se anota como
corrección aparte para que no se pierda.

## 3. Cómo se resuelve

Un solo ayudante nuevo, `CuerpoMultipart`, que escribe el cuerpo a un archivo
temporal en vez de construirlo en RAM:

1. Crea un temporal en `~/.btodicta/tmp` con permisos del usuario.
2. Escribe las cabeceras, **copia el audio del origen al temporal por ventanas**
   con `FileHandle` (64 KB), y escribe el cierre. Nunca tiene el audio entero.
3. Devuelve la `URL` y un cierre de limpieza.
4. El llamador usa `uploadTask(with:fromFile:)`, que transmite desde disco.
5. La limpieza corre **siempre**: éxito, error, cancelación y cierre de la app.

Los doce sitios pasan de recibir `wav: Data` a recibir `wav: URL`. La firma
antigua se conserva como envoltura para los llamadores que ya tienen los datos en
memoria (audio corto, tramos de troceo ya partidos), escribiendo a temporal.

### Por qué archivo temporal y no `httpBodyStream`

`URLSession` con `httpBodyStream` **no puede reintentar**: al reintentar necesita
rebobinar el flujo y no puede, así que un reintento manda un cuerpo vacío. Esta
app reintenta en cascada por diseño. `fromFile:` sí rebobina. Es además lo que
recomienda Apple para cuerpos grandes. Sale a `docs/adr/`.

## 4. Comprobación contra la constitución

- [x] **Nunca se entrega menos texto del que se dictó.** El troceo, la cascada y
      la costura no se tocan. Solo cambia por dónde viajan los bytes.
- [x] **La fluidez del usuario no se sacrifica.** La escritura del temporal
      ocurre fuera del hilo principal; RF-03 se vuelve a medir.
- [x] **Sin internet tiene que seguir funcionando.** Los motores locales usan el
      mismo camino; el motor local entra en el cambio y es el primero que se migra.
- [x] **El audio y el texto son del usuario.** El temporal vive en
      `~/.btodicta/tmp`, con los permisos que ya usa la aplicación, y se borra al
      terminar.
- [x] **Ninguna credencial en el repositorio.** No toca credenciales.
- [x] **Nada se borra sin visto bueno.** Lo único que se borra son temporales
      creados por esta función; nunca audio del usuario ni del historial.
- [x] **Tres capas y reglas de API.** No cambia ningún contrato externo: la
      interfaz de los motores es interna.
- [x] **Datos personales.** No se introduce ningún dato personal nuevo; el audio
      ya estaba en la máquina.

Nivel X: cada RF con prueba negativa, rama propia y hito con riesgos residuales.

## 5. Riesgo mayor y cómo se prueba primero

**El riesgo no es la memoria: es perder un dictado.** Un temporal mal escrito, un
corte a mitad de copia o una limpieza que borre de más convierten una mejora de
memoria en pérdida de audio — exactamente lo que el MANIFIESTO pone primero.

Por eso el orden de trabajo empieza por la prueba, no por el cambio:

1. Una batería `BTODICTA_SUBIDATEST` que compare **byte a byte** el cuerpo que
   produce el camino nuevo contra el que producía el viejo, con audio de 1 s,
   1 min y 1 h. Si no son idénticos, nada más avanza.
2. Un solo motor migrado (`WhisperServer`, local, sin coste ni cuota) y medido.
3. Los once restantes, con la batería corriendo en cada uno.
4. `MEMTEST` extendido para medir **al transcribir**, no solo al grabar.

## 6. Cómo se mide que quedó hecho

| RF / RNF | Medida | Cómo |
|---|---|---|
| RF-01 | Seis horas transcritas completas | Dictado sintético de 6 h por la cascada real |
| RF-02 | Diferencia ≤ 200 MB entre 5 min y 6 h **al transcribir** | `MEMTEST` extendido con `ps -o rss` en el instante del envío |
| RNF-01 | Residente no pasa de 700 MB | Igual |
| RNF-02 | Leer un tramo de 25 MB < 50 ms | Medición en la app, registrada |
| RNF-03 | 6 de 6 baterías en verde | `PARTIRTEST`, `TROCEOTEST`, `CRONOTEST`, `FISHTEST`, `REDTEST2`, `ROBUSTEZTEST` |
| RNF-04 | 0 avisos nuevos, 0 pasos añadidos | Revisión de interfaz antes y después |

Segundo ángulo para RF-02, porque un `ps` es una foto: además de la medición,
contar los temporales creados y borrados en una tanda completa. Si queda uno, la
limpieza falla aunque la memoria salga bien.

## 7. Lo que este plan NO hace

- No toca el troceo, la costura ni los techos aprendidos.
- No cambia la cascada ni el orden de los motores.
- No arregla lo de `URLSession.shared` (§2): se anota, se hace aparte.
- No toca el pulido con IA, que tiene su propio camino de datos.

## 8. Decisiones pendientes para la puerta 2

Resueltas el 2026-09-18. Queda una de detalle, que se decide aquí por criterio
técnico y se anota para que conste:

**Rama: `main`.** La spec pedía rama corta propia. Las specs 002, 003 y 004
fueron por `main` y el ROADMAP reserva la rama corta para lo que pueda dejar la
aplicación inservible entre commits. Aquí no ocurre: cada motor migrado es un
cambio independiente que se prueba solo y que, si falla, se revierte solo. Además
el propio Alberto pidió en su día no mantener dos ramas a la vez. Si al migrar
aparece un cambio que rompa el dictado entre commits, se abre rama entonces.


## 9. Hallazgo del 2026-09-18 — la primera etapa no midió lo que dice

Al migrar el primer motor aparece que **el supuesto de partida de este plan es
falso**. La spec da por cumplido RF-02 «al grabar», con la medición de 0 MB en
seis horas. Esa medición es real, pero **mide otro componente**:

- `BTODICTA_MEMTEST` construye un `HistoryWriter` y le mete los trozos
  directamente. `HistoryWriter` sí escribe a disco sin acumular, y por eso da 0 MB.
- El grabador del dictado, `Recorder`, **nunca entra en esa prueba**. Y su tap
  hace `samples.append(chunk)` en cada trozo: retiene el dictado entero en
  memoria. `stop()` construye después el `.wav` completo **desde ese buffer**,
  así que en el instante de terminar hay **dos copias** en RAM.

Es el mismo tipo de falso positivo que ya apareció dos veces esta semana: la
prueba pasa porque mide el componente que funciona.

### Lo que sí está bien, y hace la solución más limpia

El archivo en disco **ya existe**: `recorder.onChunk` se lo pasa a
`history.append(chunk:)` mientras se dicta. Lo que falta no es escribirlo, es
**usarlo**: hoy se transcribe desde el `.wav` que `stop()` arma en memoria, no
desde el archivo que ya está escrito.

### Qué cambia en el plan

El trabajo no es solo migrar los doce envíos. Antes hay que:

1. Que `Recorder` deje de retener el dictado entero. El buffer solo hace falta
   acotado, para la vista previa en vivo, que ya solo mira los últimos dos minutos.
2. Que `stop()` devuelva **la ruta del archivo** que `HistoryWriter` ya escribió,
   en vez de un `.wav` armado en memoria.
3. Solo entonces, los doce envíos con `uploadTask(with:fromFile:)`.

Sin los dos primeros, migrar los envíos quita una copia de dos y deja la otra:
la mejora sería la mitad de la anunciada, y RF-02 seguiría sin cumplirse.

**Pendiente de decisión de Alberto**, porque toca el grabador —el camino por el
que pasa cada dictado— y eso excede lo que aprobó: aprobó los envíos, no el
grabador. Las tareas T04 a T10 quedan detenidas hasta esa decisión. La fase A
(red de seguridad) está cerrada y no depende de esto.
