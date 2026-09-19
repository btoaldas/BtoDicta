# Pendientes de BtoDicta — documento vivo

Refunde `PENDIENTES-0.50.1.md`, `PENDIENTES-0.51.1.md` y `PENDIENTES-0.53.0.md`,
que **se conservan** como el registro histórico tal cual se escribió. Este es el
que se mira y se actualiza; aquellos no se tocan.

Estados: **Vivo** · **Corregido** (con versión) · **Por verificar** (el código
cambió alrededor y hay que comprobar si sigue) · **Decisión** (no es un fallo:
hace falta que Alberto decida).

Última revisión: 2026-09-18.

## Resumen

| Estado | Cuántos |
|---|---|
| Vivo | 19 |
| Por verificar | 2 |
| Decisión de Alberto | 5 |
| Corregido, esperando release | 2 |
| Corregido y publicado | 7 |

## Riesgo — lo único con vector externo

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| R1 | Una web abierta en pantalla puede «hablarle» a la IA que redacta el resumen: lo capturado entra en el prompt. Mitigación parcial: el aviso al modelo ya distingue canales | Vivo | 0.50.1 |
| R2 | Secretos visibles en pantalla acaban en el índice y pueden viajar en el prompt. Falta lista de exclusión por defecto (gestores de claves, bancos) | Vivo | 0.50.1 |
| R3 | El registro guarda el texto dictado en claro (`[SYS] crudo/IA`). Es local y rota cada semana, pero hay que decidir si el nivel de fábrica lo incluye | Decisión | 0.53.0 §2.8 |

Los tres juntos son la candidata a **spec 007**.

## Audio y micrófono

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| A1 | `installTap` con formato explícito en la bitácora y en la activación por voz: el mismo fallo de «format mismatch» del grabador | **Corregido, esperando release** | Hallado 2026-09-18 |
| A2 | Carrera de datos benigna en el tap de `ContinuoAudio` (conversor y `buffersVistos` entre el hilo de audio y la cola) | Por verificar — el conversor se movió dentro del tap el 2026-09-18 | 0.50.1 |
| A3 | Con micrófono no disponible y bitácora activa, el vigía de 400 ms fuerza remontajes sin tregua | Por verificar — el reintento con respiro de 0.63.2 puede haberlo cambiado | 0.50.1 |
| A4 | Reconfigurar en ráfaga desde los deslizadores reinicia el motor de grabación decenas de veces por arrastre (falta amortiguación) | Vivo | 0.50.1 |
| A5 | El audio del sistema no se rearma tras `didStopWithError`: muere hasta reconfigurar | Vivo | 0.50.1 |

## Red y motores

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| N1 | `ScribeBatchClient` usa `URLSession.shared` en sus dos envíos, así que el arreglo de `Connection: close` de 0.59.0 **no lo cubre**: puede heredar un socket cerrado y esperar en balde | Vivo | Hallado 2026-09-18 |
| N2 | `pulido: groq falló (HTTP 200)` — respuesta correcta sin contenido extraíble, modelos `openai/gpt-oss-*` con campo `reasoning`. Revisar `extraerContenido` | Vivo | 0.53.0 §2.8 |
| N3 | Etiqueta pendiente de ElevenLabs Scribe sin cuota (el fondo se cubrió en 0.52.0) | Vivo | 0.53.0 §2.4 |

## Bitácora, índice y purga

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| B1 | `applicationWillTerminate` no espera al cierre de la bitácora: cada cierre deja un archivo huérfano (38 arranques en 14 días). El rescate funciona, pero el huérfano se crea igual | Vivo | 0.50.1 · 0.53.0 §2.8 |
| B2 | La purga solo se aplica al arrancar; en sesiones largas no se repite | Vivo | 0.50.1 |
| B3 | Los trozos menores de 16 KB quedan fuera del índice y de la purga | Vivo | 0.50.1 |
| B4 | `rescatarHuerfanos` puede indexar el trozo aún abierto con metadatos provisionales | Vivo | 0.50.1 |
| B5 | La purga no es atómica: si falla un borrado físico, el texto del índice ya se perdió | Vivo | 0.50.1 |
| B6 | `guardar()` de documentos hace comprobar-luego-escribir sin exclusión: dos en el mismo segundo colisionan | Vivo | 0.50.1 |
| B7 | `cargarExplorador` recorre dos veces el árbol completo en cada refresco. Con meses de historial la pestaña tarda | Vivo | 0.51.1 |
| B8 | `huellaPrevia` y `ultimaEscritura` de `ContinuoPantalla` se mutan desde el hilo principal y desde el ejecutor de la captura | Vivo | 0.51.1 |
| B9 | `ContinuoPantalla`: estado compartido entre el hilo principal y el ejecutor del Task | Vivo | 0.50.1 |

## Rutinas, modos y tareas

| # | Qué pasa | Estado | Origen |
|---|---|---|---|
| M1 | Dos rutinas a la vez: la segunda recibe «tanda en curso» y genera su documento sin esperar material fresco | Vivo | 0.50.1 |
| M2 | Rutinas y resumen arman el material del día en el hilo principal | Vivo | 0.50.1 |
| M3 | Modo Tarea: verbos sueltos crean tareas por error (preexistente) | Vivo | 0.50.1 |
| M4 | Recordatorio periódico de tareas encendido de fábrica y sin interruptor visible (preexistente) | Vivo | 0.50.1 |
| M5 | Router global por IA: hasta ~30 s de latencia en manos libres, sin plan determinista | Vivo | 0.50.1 |
| M6 | `dictadoOcupado` lee estado del hilo principal desde la cola del lote sin salto | Vivo | 0.50.1 |
| M7 | `pmset` síncrono en el hilo principal en cada tic con «solo con corriente» | Vivo | 0.50.1 |

## Decisiones de Alberto (no son fallos)

| # | Qué hay que decidir | Origen |
|---|---|---|
| D1 | Notarizar con Apple (99 USD/año) o mantener «Abrir de todos modos» en las notas de release | 0.53.0 §4 |
| D2 | Qué hacer con los 17,5 GB de PCM sin recomprimir (la recompresión automática ya existe) | 0.53.0 §4 |
| D3 | ElevenLabs sin créditos: renovar o bajarlo en la cascada. Hoy AssemblyAI va primero y el TTS ya cae a la voz de macOS | 0.53.0 §4 |
| D4 | Ollama apagado en esta Mac: la capa semántica de modos degrada a exacto y raíz | 0.53.0 §4 |
| D5 | Si el registro debe guardar el texto dictado en claro de fábrica (= R3) | 0.53.0 §2.8 |

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
