# Tareas 001 — Memoria del dictado largo · segunda etapa

- Estado: En curso — fase A cerrada, fase B detenida por el hallazgo de `plan.md` §9
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

## Fase B — Un motor primero, medido, y después los once

- [ ] T04 (RF-01) Migrar el motor local a `uploadTask(with:fromFile:)`: sin coste, sin cuota y sin depender de la red — `Sources/BtoDicta/WhisperServer.swift` — Evidencia esperada: transcripción real idéntica a la del camino viejo
  - Parcial (2026-09-18): el motor ya sube con `uploadTask(with:fromFile:)` y compila, pero sus tres llamadores siguen entregándole el audio en memoria. No se cierra hasta que el camino completo venga del archivo — ver el hallazgo de `plan.md` §9
- [ ] T05 (RF-02) Extender `MEMTEST` para medir al transcribir, no solo al grabar, comparando 5 min contra 6 h en el instante del envío — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: diferencia ≤ 200 MB con el motor de T04
- [ ] T06 [P] (RF-01) Migrar el envío compartido por Groq, OpenAI y Mistral: tres motores de una — `Sources/BtoDicta/TranscribeProviders.swift` — Evidencia esperada: `SUBIDATEST` en verde y una transcripción real por motor
- [ ] T07 [P] (RF-01) Migrar los cuatro envíos restantes del mismo archivo, incluido el que manda los datos sin multipart — `Sources/BtoDicta/TranscribeProviders.swift` — Evidencia esperada: igual que T06
- [ ] T08 [P] (RF-01) Migrar Fish Audio — `Sources/BtoDicta/FishAudio.swift` — Evidencia esperada: transcripción real con la clave configurada
- [ ] T09 [P] (RF-01) Migrar los dos envíos de Scribe por lotes, incluido el que ya recibe una ruta pero la lee entera — `Sources/BtoDicta/ScribeBatchClient.swift` — Evidencia esperada: transcripción real y memoria plana
- [ ] T10 (RF-01) Retirar la firma con datos en memoria donde ya no la use nadie y dejarla solo para los tramos que el troceo ya partió — `Sources/BtoDicta/TranscribeProviders.swift`, `Sources/BtoDicta/ScribeBatchClient.swift`, `Sources/BtoDicta/FishAudio.swift`, `Sources/BtoDicta/WhisperServer.swift` — Evidencia esperada: compilación limpia y baterías en verde

## Fase C — Cierre

- [ ] T11 (RF-01) Dictado sintético de seis horas por la cascada real, transcrito completo — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: el texto contiene el primer y el último minuto
- [ ] T12 (RF-02) Medición final de memoria al transcribir seis horas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `ps -o rss` con diferencia ≤ 200 MB
- [ ] T13 (RF-03) Comprobar que un dictado corto no se volvió más lento — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: 45 s por la cascada real, dentro de los 1 883 ms medidos antes
- [ ] T14 (RF-05) Comprobar que la reparación de tramos sigue funcionando — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `REDTEST2` y `PARTIRTEST` en verde leyendo del archivo
- [ ] T15 (RNF-01) Residente por debajo de 700 MB en el dictado de seis horas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: cifra medida contra el umbral
- [ ] T16 (RNF-02) Leer un tramo de 25 MB en menos de 50 ms — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: medición registrada en la aplicación
- [ ] T17 (RNF-03) Las seis baterías existentes en verde y 0 omitidas — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: `PARTIRTEST`, `TROCEOTEST`, `CRONOTEST`, `FISHTEST`, `REDTEST2`, `ROBUSTEZTEST`
- [ ] T18 (RNF-04) Revisión de interfaz: 0 avisos nuevos, 0 preguntas y 0 pasos añadidos — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: comparación antes y después
- [ ] T19 (todos) Verificación final RF por RF con segundo ángulo y prueba negativa — `docs/specs/001-memoria-del-dictado-largo/verificacion.md` — Evidencia esperada: tabla completa con veredicto Cumple o No cumple
- [ ] T20 (todos) Hito fechado con desviaciones y riesgos residuales, bitácora del día e índice de specs regenerado — `docs/hitos/`, `docs/specs/README.md` — Evidencia esperada: hito escrito y bloque del índice actualizado
