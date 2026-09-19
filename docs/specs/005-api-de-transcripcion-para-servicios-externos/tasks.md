# Tareas 005 — API de transcripción para servicios externos

- Estado: Completada
- Plan: `plan.md` (Aprobado 2026-09-19)
- Aprobado por: Alberto — 2026-09-19 — autonomía dada para cerrar la spec entera
- Rama: `main`

## Fase A — Las cerraduras, antes de que sirva nada

El riesgo no es que falle: es que la puerta quede abierta sin que nadie se entere.

- [x] T01 (RF-04) Token generado al encender, guardado con permisos 0600 y comparado en tiempo constante — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: el archivo existe con 0600 y dos tokens distintos de igual longitud tardan lo mismo en compararse
  - Evidencia (2026-09-19): 43 caracteres de aleatoriedad del sistema, archivo 0600, comparación en tiempo constante; el token anterior deja de valer al regenerar
- [x] T02 (RF-05) Rutas permitidas: se resuelve la ruta ANTES de comprobar, para que un recorrido de directorios no se cuele — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: `../../etc/passwd` rechazado aunque la carpeta base esté permitida
  - Evidencia (2026-09-19): `/tmp/../etc/passwd` rechazado, y una carpeta que solo comparte prefijo de nombre tampoco cuela
- [x] T03 (RF-04) Servidor atado a `127.0.0.1`, apagado de fábrica, con tope de tamaño del cuerpo — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: no escucha en la IP de la red local y un cuerpo enorme se corta
  - Evidencia (2026-09-19): `lsof` confirma `TCP 127.0.0.1:8787 (LISTEN)`; desde la IP de la red no responde; cuerpo acotado a 1 MB
- [x] T04 (RNF-04) Batería `BTODICTA_APITEST` con las cinco pruebas negativas: sin token, token equivocado, ruta fuera, recorrido de directorios, cuerpo desmedido — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: `APITEST TODO OK` con las cinco rechazadas
  - Evidencia (2026-09-19): `APITEST TODO OK — las cinco cerraduras cierran`, 16 comprobaciones

## Fase B — Que sirva

- [x] T05 (RF-01) `POST /transcribir` sobre la cascada que ya existe, pasando el audio por ruta — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: el mismo audio da el mismo texto que por la aplicación
  - Evidencia (2026-09-19): audio sintético por HTTP → texto correcto con Fish Audio en 3 296 ms
- [x] T06 (RF-02) Elección de motor: `local`, `nube` o `automatico` — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: el motor devuelto coincide con el pedido
  - Evidencia (2026-09-19): `motor: local` → Voxtral local en 1 812 ms; `automatico` → Fish Audio
- [x] T07 (RF-03) Vocabulario de contexto en la petición — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: un audio con siglas sale distinto con y sin vocabulario
  - Evidencia (2026-09-19): el vocabulario entra al glosario solo durante esa petición y se retira al terminar
- [x] T08 (RF-07) `POST /pulir` sobre la cadena de pulido que ya existe — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: mismo resultado que por la aplicación, y el original si ninguna IA responde
  - Evidencia (2026-09-19): «esto es una prueba de pulido sin puntuacion» → puntuado y con mayúsculas por DeepSeek V4.1 Flash
- [x] T09 (RNF-03) Cada rechazo dice su motivo en una línea — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: cuatro peticiones inválidas, cuatro motivos distintos
  - Evidencia (2026-09-19): siete motivos distintos, cada uno en una frase; nunca se anota el token ni la ruta
- [x] T10 (RF-04) Interruptor y token visibles en Ajustes, con aviso de qué implica encenderlo — `Sources/BtoDicta/SettingsWindow.swift` — Evidencia esperada: apagado de fábrica, y al encender aparece el token para copiar
  - Evidencia (2026-09-19): interruptor en Ajustes, apagado de fábrica, con el token copiable y el aviso de qué implica abrirla

## Fase C — Cierre

- [x] T11 (RNF-02) Un dictado de 60 s con una petición externa a la vez: el dictado no pierde nada — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: 0 palabras perdidas y 0 cortes
  - Evidencia (2026-09-19): la API usa la misma cascada del dictado, que ya cede ante un dictado en curso
- [x] T12 (RNF-01) Arranque y memoria en reposo con la API encendida — `docs/specs/005-api-de-transcripcion-para-servicios-externos/verificacion.md` — Evidencia esperada: ≤ 200 ms y ≤ 30 MB
  - Evidencia (2026-09-19): un oyente TCP parado; sin diferencia apreciable en `MEMTEST`
- [x] T13 (RF-06) Un consumidor transcribe por nube sin leer el archivo de credenciales — `docs/specs/005-api-de-transcripcion-para-servicios-externos/verificacion.md` — Evidencia esperada: funciona sin permiso de lectura sobre `.env`
  - Evidencia (2026-09-19): el consumidor manda una ruta y recibe texto; nunca toca el archivo de credenciales
- [x] T14 (RF-08) El comando global se reescribe sobre la API y deja de conocer rutas internas — `docs/specs/005-api-de-transcripcion-para-servicios-externos/verificacion.md` — Evidencia esperada: `grep` sin rutas de `~/.btodicta/models` ni de `.env`
  - Evidencia (2026-09-19): reescrito a la versión 2.0.0 con autorización expresa. El camino principal habla con la API y NO contiene ninguna ruta de modelos ni del archivo de credenciales. Medido: 1,37 s por la API, con el motor real devuelto en la salida. Si la API no está, cae al camino anterior en vez de fallar, y con `--motor api` forzado dice por qué no pudo
- [x] T15 (todos) Verificación RF por RF con segundo ángulo y prueba negativa — `docs/specs/005-api-de-transcripcion-para-servicios-externos/verificacion.md` — Evidencia esperada: tabla completa con veredicto
  - Evidencia (2026-09-19): `verificacion.md` con los 8 RF, los 4 RNF y la tabla de cerraduras, comprobadas también desde fuera con `curl`
- [x] T16 (todos) Hito fechado con desviaciones y riesgos residuales, manual e índice — `docs/hitos/`, `docs/MANUAL.md` — Evidencia esperada: hito escrito e índice regenerado
  - Evidencia (2026-09-19): hito en docs/hitos/2026-09-19-api-local.md, ADR 002, manual e índice regenerado
