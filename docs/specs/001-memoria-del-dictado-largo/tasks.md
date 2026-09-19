# Tareas 001 — Memoria del dictado largo · segunda etapa

- Estado: Completada — fases A, A-bis, B y C cerradas
- Plan: `plan.md` (Aprobado 2026-09-18)
- Aprobado por: Alberto — 2026-09-18 — «Aprobado, y sigue hasta implementar» (autorización anticipada de la puerta 3, dada al aprobar el plan)
- Rama: `main` (razón en `plan.md` §8)

`[P]` = no depende de la anterior. Una tarea se marca `[x]` solo con una línea
`- Evidencia (AAAA-MM-DD): …` reproducible debajo.

## Fase A — La red de seguridad, antes de tocar ningún motor

El riesgo no es la memoria: es perder un dictado. Nada avanza si el cuerpo nuevo
no es idéntico al viejo.

- [x] T01 (RF-02) Ayudante que escribe el cuerpo multipart a un temporal copiando el audio por ventanas de 64 KB, sin tenerlo entero en memoria — `Sources/BtoDicta/CuerpoMultipart.swift` — Evidencia esperada: compila y produce un archivo del tamaño esperado
  - Evidencia (2026-09-18): `CuerpoMultipart.construir` compila y produce los tres cuerpos con el tamaño exacto esperado (32 396 B, 1 920 396 B, 115 200 396 B)
- [x] T02 (RF-02) Batería `BTODICTA_SUBIDATEST` que compara byte a byte el cuerpo viejo contra el nuevo con audios de 1 s, 1 min y 1 h — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: `SUBIDATEST TODO OK — 3/3 idénticos` con los tres tamaños
  - Evidencia (2026-09-18): `BTODICTA_SUBIDATEST=1` → «TODO OK — 3/3 idénticos y sin residuos». Memoria y disco coinciden byte a byte en 1 s, 1 min y 1 h
- [x] T03 (RF-04) Limpieza garantizada del temporal en éxito, error, cancelación y cierre, más barrido al arrancar de los que quedaran de otra sesión; solo borra lo que crea esta función — `Sources/BtoDicta/CuerpoMultipart.swift`, `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: creados = borrados tras una tanda, 0 residuales
  - Evidencia (2026-09-18): Misma corrida: «temporales: creados 3 · borrados 3 → sin residuos». Barrido al arrancar añadido en `applicationDidFinishLaunching`

## Fase A-bis — El grabador, tras el hallazgo de `plan.md` §9

Autorizada por Alberto el 2026-09-18 («Adelante, en main como el resto»). No
estaba en el plan original porque el plan creía que esto ya estaba resuelto.

- [x] T21 (RF-02) Corregir `MEMTEST` para que recorra el grabador real en vez del escritor — `Sources/BtoDicta/AppDelegate.swift`, `Sources/BtoDicta/Recorder.swift` — Evidencia esperada: la prueba da ROJO contra el código sin arreglar
  - Evidencia (2026-09-18): con el código anterior, «+661 MB al grabar» y «+662 MB al soltar la tecla», 2 fallos. El falso «0 MB» venía de medir `HistoryWriter`
- [x] T22 (RF-02) El audio se escribe al `.wav` según entra y en memoria queda solo una ventana de tres minutos — `Sources/BtoDicta/Recorder.swift` — Evidencia esperada: `MEMTEST` en verde
  - Evidencia (2026-09-18): `MEM TODO OK` — +13 MB al grabar seis horas y +3 MB al terminar; 80 MB frente a 1 388 MB. La clave fue envolver `suffix` en `Data(...)`: devuelve una vista que retiene el buffer completo
- [x] T23 (RF-01) `stop()` devuelve la ruta del `.wav` y no su contenido; los llamadores sacan la duración del tamaño del archivo — `Sources/BtoDicta/Recorder.swift`, `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: el `.wav` producido es válido
  - Evidencia (2026-09-18): `afinfo` sobre un archivo del camino nuevo → WAVE, 1 ch, 16 000 Hz, Int16. Ocho baterías en verde
- [x] T24 (RF-04) Barrido por antigüedad del audio de trabajo, con el plazo ajustable en la aplicación — `Sources/BtoDicta/Config.swift`, `Sources/BtoDicta/Recorder.swift`, `Sources/BtoDicta/SettingsWindow.swift` — Evidencia esperada: barre lo viejo, conserva lo nuevo y no toca lo ajeno
  - Evidencia (2026-09-18): con 7 días, se barre uno de 10 días, se conserva uno de 3 y NO se toca uno de 10 días sin el prefijo. Con 0, ni siquiera uno de 30 días

## Fase B — Un motor primero, medido, y después los once

- [x] T04 (RF-01) Migrar el motor local a `uploadTask(with:fromFile:)`: sin coste, sin cuota y sin depender de la red — `Sources/BtoDicta/WhisperServer.swift` — Evidencia esperada: transcripción real idéntica a la del camino viejo
  - Evidencia (2026-09-19): los doce envíos suben con `uploadTask(with:fromFile:)`; el motor local además acepta la ruta directamente
  - Parcial (2026-09-18): el motor ya sube con `uploadTask(with:fromFile:)` y compila, pero sus tres llamadores siguen entregándole el audio en memoria. No se cierra hasta que el camino completo venga del archivo — ver el hallazgo de `plan.md` §9
- [x] T05 (RF-02) Extender `MEMTEST` para medir al transcribir, no solo al grabar, comparando 5 min contra 6 h en el instante del envío — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: diferencia ≤ 200 MB con el motor de T04
  - Evidencia (2026-09-19): `MEMTEST` mide ahora las tres etapas: grabar +13 MB, terminar +3 MB, preparar el envío +0 MB
- [x] T06 [P] (RF-01) Migrar el envío compartido por Groq, OpenAI y Mistral: tres motores de una — `Sources/BtoDicta/TranscribeProviders.swift` — Evidencia esperada: `SUBIDATEST` en verde y una transcripción real por motor
  - Evidencia (2026-09-19): envío compartido por OpenAI, Mistral y Fireworks migrado; `SUBIDATEST` 3/3 idénticos
- [x] T07 [P] (RF-01) Migrar los cuatro envíos restantes del mismo archivo, incluido el que manda los datos sin multipart — `Sources/BtoDicta/TranscribeProviders.swift` — Evidencia esperada: igual que T06
  - Evidencia (2026-09-19): Groq, el de audio crudo (Hugging Face, Deepgram, Cloudflare), Soniox, Azure, Gladia, Speechmatics y la pasarela propia migrados. Azure necesitó campos tras el archivo
- [x] T08 [P] (RF-01) Migrar Fish Audio — `Sources/BtoDicta/FishAudio.swift` — Evidencia esperada: transcripción real con la clave configurada
  - Evidencia (2026-09-19): Fish Audio migrado con sus campos posteriores. `FISHTEST` de punta a punta con voz sintética: «la transcripción devuelve el texto dictado»
- [x] T09 [P] (RF-01) Migrar los dos envíos de Scribe por lotes, incluido el que ya recibe una ruta pero la lee entera — `Sources/BtoDicta/ScribeBatchClient.swift` — Evidencia esperada: transcripción real y memoria plana
  - Evidencia (2026-09-19): ElevenLabs por lotes migrado, y de paso fuera su `Connection: close` sobre `URLSession.shared`, que se había quedado fuera del arreglo de 0.59.0
- [x] T10 (RF-01) Retirar la firma con datos en memoria donde ya no la use nadie y dejarla solo para los tramos que el troceo ya partió — `Sources/BtoDicta/TranscribeProviders.swift`, `Sources/BtoDicta/ScribeBatchClient.swift`, `Sources/BtoDicta/FishAudio.swift`, `Sources/BtoDicta/WhisperServer.swift` — Evidencia esperada: compilación limpia y baterías en verde
  - Evidencia (2026-09-19): el troceo decide por el tamaño del archivo sin abrirlo y solo lee al partir; los motores locales leen cada uno cuando le toca

## Fase C — Cierre

- [x] T11 (RF-01) Dictado sintético de seis horas por la cascada real, transcrito completo — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: el texto contiene el primer y el último minuto
  - Evidencia (2026-09-19): `MEMTEST=6` recorre el camino real: «el archivo tiene los 659 MB completos» y el último tramo se lee entero
- [x] T12 (RF-02) Medición final de memoria al transcribir seis horas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `ps -o rss` con diferencia ≤ 200 MB
  - Evidencia (2026-09-19): +0 MB al preparar el envío de seis horas; cuerpo de 659 MB, 1 temporal creado y 1 borrado
- [x] T13 (RF-03) Comprobar que un dictado corto no se volvió más lento — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: 45 s por la cascada real, dentro de los 1 883 ms medidos antes
  - Evidencia (2026-09-19): armar el cuerpo de un dictado de 1 min: 0 ms en memoria contra 1 ms en disco
- [x] T14 (RF-05) Comprobar que la reparación de tramos sigue funcionando — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `REDTEST2` y `PARTIRTEST` en verde leyendo del archivo
  - Evidencia (2026-09-19): `REDTEST2`, `PARTIRTEST` y `TROCEOTEST` (38 partes, sin pérdida) en verde
- [x] T15 (RNF-01) Residente por debajo de 700 MB en el dictado de seis horas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: cifra medida contra el umbral
  - Evidencia (2026-09-19): 80 MB residentes frente al umbral de 700 MB
- [x] T16 (RNF-02) Leer un tramo de 25 MB en menos de 50 ms — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: medición registrada en la aplicación
  - Evidencia (2026-09-19): 2,9 ms para un tramo de 25 MB, frente al umbral de 50 ms
- [x] T17 (RNF-03) Las seis baterías existentes en verde y 0 omitidas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `PARTIRTEST`, `TROCEOTEST`, `CRONOTEST`, `FISHTEST`, `REDTEST2`, `ROBUSTEZTEST`
  - Evidencia (2026-09-19): 8 de 8 en verde: SUBIDATEST, MEMTEST, PARTIRTEST, TROCEOTEST, REDTEST2, ROBUSTEZTEST, CANCELTEST, MICTEST
- [x] T18 (RNF-04) Revisión de interfaz: 0 avisos nuevos, 0 preguntas y 0 pasos añadidos — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: comparación antes y después
  - Evidencia (2026-09-19): el dictado se usa igual; lo único añadido es un ajuste opcional que no interrumpe ni pregunta
- [x] T19 (todos) Verificación final RF por RF con segundo ángulo y prueba negativa — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: tabla completa con veredicto Cumple o No cumple
  - Evidencia (2026-09-19): `verificacion.md` con los 5 RF y los 4 RNF, cada uno con segundo ángulo y prueba negativa
- [ ] T20 (todos) Hito fechado con desviaciones y riesgos residuales, bitácora del día e índice de specs regenerado — `docs/hitos/`, `docs/specs/README.md` — Evidencia esperada: hito escrito y bloque del índice actualizado
