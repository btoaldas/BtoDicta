# Pendientes de BtoDicta — documento vivo

Refunde `PENDIENTES-0.50.1.md`, `PENDIENTES-0.51.1.md` y `PENDIENTES-0.53.0.md`,
que **se conservan** como el registro histórico tal cual se escribió. Este es el
que se mira y se actualiza; aquellos no se tocan.

Estados: **Vivo** · **Corregido** (con versión) · **Por verificar** (el código
cambió alrededor y hay que comprobar si sigue) · **Decisión** (no es un fallo:
hace falta que Alberto decida).

Última revisión: 2026-09-19 (segunda pasada: se cierran todos los vivos).

## Resumen

| Estado | Cuántos |
|---|---|
| Vivo | 0 |
| Decisión de Alberto | 4 |
| Corregido y publicado | 24 |
| No reproducible con el código actual | 4 |

Los veinticuatro arreglos van en 0.63.2 → 0.64.3. Cuatro pendientes resultaron
**obsoletos**: el código había cambiado alrededor y el fallo ya no se daba. Se
comprobó uno a uno en vez de darlos por buenos.

## Riesgo — lo único con vector externo

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| R1 | Inyección de instrucciones por lo leído en pantalla | **Corregido** en 0.64.0: valla impredecible por llamada y regla que manda sobre el encargo | 0.50.1 |
| R2 | Secretos fotografiados: la lista de exclusión venía VACÍA de fábrica | **Corregido** en 0.64.0: trae los gestores de contraseñas y el llavero, más una capa por título de ventana | 0.50.1 |
| R3 | El registro guarda el texto dictado en claro | **Resuelto** en 0.64.0 como ajuste, encendido de fábrica con su razón escrita | 0.53.0 §2.8 |

Los tres juntos son la candidata a **spec 007**.

## Audio y micrófono

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| A1 | `installTap` con formato explícito en la bitácora y en la activación por voz | **Corregido** en 0.63.3 | Hallado 2026-09-18 |
| A2 | Carrera del contador de buffers | **Corregido** en 0.64.1: bajo candado, que es el número con el que se decide si el micrófono está mudo | 0.50.1 |
| A3 | El vigía de 400 ms forzaba remontajes sin tregua | **No reproducible**: ese vigía ya no existe en el código | 0.50.1 |
| A4 | Los deslizadores reiniciaban el planificador en cada paso del arrastre | **Corregido** en 0.64.2: se espera a que la mano se quede quieta | 0.50.1 |
| A5 | El audio del sistema no se rearmaba tras un error | **Corregido** en 0.64.1: reintenta con espera creciente, tope de cinco | 0.50.1 |

## Red y motores

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| N1 | `Connection: close` sobre la sesión compartida: el fallo de 0.59.0 había vuelto en **trece sitios**, no solo en ElevenLabs | **Corregido** en 0.63.7, con guardián estático en el QA | Hallado 2026-09-18 |
| N2 | Un 200 con el texto en `reasoning` se contaba como fallo | **Corregido** en 0.64.1, con `BTODICTA_EXTRAERTEST` | 0.53.0 §2.8 |
| N3 | El registro decía «HTTP 402» donde debía decir qué hacer | **Corregido** en 0.64.3: el motivo va en una frase, y el código detrás | 0.53.0 §2.4 |

## Bitácora, índice y purga

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| B1 | Un archivo huérfano por cada cierre | **Corregido** en 0.64.1. Medido: de 2–4 por arranque a cero | 0.50.1 · 0.53.0 §2.8 |
| B2 | La purga solo corría al arrancar | **Corregido** en 0.64.1: se repasa cada seis horas | 0.50.1 |
| B3 | Migajas de audio que la limpieza nunca alcanzaba | **Corregido** en 0.64.2: se retiran donde se descubren. Había ocho | 0.50.1 |
| B4 | El trozo en escritura entraba al índice a medias | **Corregido** en 0.64.2: se salta lo tocado en el último minuto | 0.50.1 |
| B5 | Se des-indexaba lo que no se había conseguido borrar | **Corregido** en 0.64.1: fila a fila, solo las de los archivos que de verdad se fueron | 0.50.1 |
| B6 | Dos dictados —y dos documentos— en el mismo segundo compartían archivo | **Corregido** en 0.63.7 (dictados) y 0.64.3 (documentos) | 0.50.1 |
| B7 | La pestaña recorría el árbol entero dos veces por refresco | **Corregido** en 0.64.1: un solo recorrido | 0.51.1 |
| B8 | Carrera en los diccionarios de la captura | **No reproducible**: todos los accesos viven ya dentro de su cola | 0.51.1 |
| B9 | Estado compartido en la captura de pantalla | **No reproducible**: igual que B8 | 0.50.1 |

## Rutinas, modos y tareas

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| M1 | Una rutina generaba su documento con el día a medio transcribir | **Corregido** en 0.64.2: se aplaza cinco minutos | 0.50.1 |
| M2 | El resumen armaba el material en el hilo principal y congelaba la ventana | **Corregido** en 0.64.2 | 0.50.1 |
| M3 | Verbos sueltos creaban tareas por error | **No reproducible**: «comprar», «revisar», «llamar» y «hacer» no disparan ningún modo | 0.50.1 |
| M4 | Aviso periódico sin interruptor visible | **No reproducible**: el interruptor está en la pestaña de Notas | 0.50.1 |
| M5 | Router por IA sin plan determinista delante | **Resuelto**: el determinista decide primero y la IA es el último recurso | 0.50.1 |
| M6 | El estado de «hay alguien dictando» se leía desde otra cola | **Corregido** en 0.64.2: el hilo principal lo publica en una bandera atómica | 0.50.1 |
| M7 | Lanzaba un proceso para saber si el equipo está enchufado, en cada tic | **Corregido** en 0.64.1: se guarda la respuesta 30 s | 0.50.1 |

## Decisiones de Alberto (no son fallos)

| # | Qué hay que decidir | Origen |
|---|---|---|
| D1 | Notarizar con Apple (99 USD/año) o mantener «Abrir de todos modos» en las notas de release | 0.53.0 §4 |
| D2 | Qué hacer con los 17,5 GB de PCM sin recomprimir (la recompresión automática ya existe) | 0.53.0 §4 |
| D3 | ElevenLabs sin créditos: renovar o bajarlo en la cascada. Hoy AssemblyAI va primero y el TTS ya cae a la voz de macOS | 0.53.0 §4 |
| D4 | Ollama apagado en esta Mac: la capa semántica de modos degrada a exacto y raíz | 0.53.0 §4 |


## Corregido y publicado

Se listan para que nadie los reabra. Detalle en los documentos históricos.

| # | Qué era | Dónde se cerró |
|---|---|---|
| C1 | La compresión de audio de la bitácora llevaba rota desde el 08-17: 17,5 GB en crudo | 0.53.0 §2.1 |
| C2 | El streaming Scribe mandaba audio a un socket muerto: 19 539 líneas en 3 días | 0.53.0 §2.2 |
| C3 | `speech_model` obsoleto en AssemblyAI | 0.52.0 §2.3 |
| C4 | Capturas de pantalla «colgadas» bajo la carga de una tanda | 0.53.0 §2.5 |
| C5 | Rutinas de resumen que fallaban en silencio sin material | 0.53.0 §2.6 |
| C6 | Sin internet, la cascada recorría los 16 proveedores | 0.53.0 §2.7 |
| C7 | Un fallo de una pantalla abortaba las demás; purga sin bloquear | `5d32952`, `378d355` |
