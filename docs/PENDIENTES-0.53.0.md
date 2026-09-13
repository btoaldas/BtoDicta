# Diagnóstico 2026-09-01 y pendientes para 0.53.0

Fuentes: informes de fallo de macOS (`~/Library/Logs/DiagnosticReports`),
registros semanales W33–W35 más el actual (`~/.btodicta/logs`, 2026-08-17 →
2026-09-01), y el código de `main` en `a7a15b0` (0.52.0). Cada punto trae
evidencia, causa localizada y propuesta; nada de aquí se ha corregido todavía
salvo lo marcado como cerrado en 0.52.0.

## 1. Cierres inesperados

| Fecha | Versión | Pila | Estado |
|---|---|---|---|
| 08-25 20:08 · 08-26 20:03 · 08-27 20:13 · 08-28 20:04 | 0.51.0 | `presentarAvisoPendiente → Voz.decir → ElevenLabsStreamTTS.stream → [AVAudioPlayerNode play]` → `NSException` → `SIGABRT` | **Cerrado en 0.52.0** (`AudioSeguro` + puente ObjC) |

No hay más informes de BtoDicta en el histórico completo, ni informes de
cuelgue (`.hang`/`.spin`), ni de procesos hijos (llama-server, XTTS, Piper).

## 2. Errores recurrentes con causa localizada (por impacto)

### 2.1 La compresión de audio de la bitácora lleva rota desde el 08-17 — 17,5 GB en crudo

- **Evidencia.** `bitácora: el m4a de HH-MM-SS.pcm no valida — conservo el crudo`:
  entre 622 y 1 973 veces **cada día** desde 2026-08-17 (≈22 000 en total).
  En disco: 22 515 `.pcm` = 17 501 MB frente a 130 `.m4a` = 13 MB (los únicos
  m4a válidos son del 08-16 y la mañana del 08-17).
- **Causa** (`ContinuoLote.comprimir`, introducido en `378d355`). Se escribe el
  m4a con `AVAudioFile`, se hace `archivo = nil` para finalizar el contenedor y
  se valida abriéndolo en lectura. Pero `guard let salida = archivo` dejó una
  **segunda referencia viva** al escritor, así que el contenedor MPEG-4 no se
  finaliza al validar: la lectura falla, el m4a (que sí es válido cuando por fin
  se libera) se borra y se conserva el PCM.
- **Prueba reproducible** (`/tmp/m4atest.swift`, mismo PCM de 30 s):
  patrón actual → `valida=false length=-1`; con la referencia liberada antes de
  validar → `valida=true length=480064`. El archivo «inválido» abre bien con
  `afinfo` en cuanto el proceso lo suelta (30,004 s, 471 paquetes).
- **Impacto.** ≈1,1 GB/día de crudo; con la purga a 90 días el régimen sería
  ~100 GB. Relación m4a/pcm ≈ 1:8,5. Hoy hay 730 GB libres: no es urgente,
  pero crece solo.
- **Propuesta.** (a) Encerrar la escritura en su propio ámbito (función o
  `do {}`) para que el escritor muera antes de validar; (b) hook de prueba
  «pcm → m4a → leer» en ROBUSTEZTEST; (c) **decisión de Alberto**: recomprimir
  en segundo plano los 22 515 PCM existentes (misma rutina, acotada, con
  pausa si hay dictado) o dejarlos hasta la purga.

### 2.2 El streaming Scribe de ElevenLabs manda audio a un socket muerto: 19 539 líneas en 3 días

- **Evidencia.** `stream: ERROR The operation couldn't be completed. Socket is
  not connected` ×19 539 (08-22 2 105 · 08-23 2 589 · 08-29 14 847) a 600 por
  minuto exactos = 10/s = un buffer de micrófono cada 100 ms. Siempre precedido
  de `stream: ERROR quota_exceeded` (×44) al arrancar el dictado.
- **Causa** (`ScribeStreamClient`). El servidor responde `quota_exceeded` y
  cierra; `receiveLoop` marca `conectado = false` pero `send(chunk:)` no lo
  consulta y nadie avisa a `AppDelegate`, así que cada chunk del dictado se
  envía al socket cerrado y cada envío fallido escribe una línea. El texto llegó
  al final por la ruta de rescate (batch), pero sin vista previa en vivo y con
  el registro inundado. Además `registrarFallo()` pone al proveedor «en
  cuarentena (red caída)» 2 min cuando la causa real es cuota.
- **Propuesta.** (a) `send` con `guard conectado`; (b) callback de cierre para
  que `AppDelegate` pase a plan B a mitad de dictado; (c) `quota_exceeded` /
  `auth_error` → `CuarentenaSTT.registrar` (30 min) con causa real, y la ruta
  WS debe respetar `CuarentenaSTT.activa("elevenlabs")` además de
  `StreamClient.enCuarentena`; (d) etiqueta de cuarentena con el motivo real.

### 2.3 AssemblyAI `speech_model` deprecado — **cerrado en 0.52.0**

3 816 fallos (08-30 → 09-01) en cada dictado y cada tap de la bitácora. Ya se
envía `speech_models`; la cuarentena evita repetirlo. Verificado con
transcripción real y con el modelo guardado (`universal-3-pro` mapeado).

### 2.4 ElevenLabs Scribe por lotes sin cuota — cubierto en 0.52.0, etiqueta pendiente

2 805 × `HTTP 401 quota_exceeded` (08-22 → 08-29): un fallo por cada trozo de
la bitácora. Con `CuarentenaSTT` el 401 aparta al proveedor 30 min. Queda la
etiqueta engañosa del punto 2.2 (d).

### 2.5 Capturas de pantalla «colgadas» ×12 (08-31, 09-01)

- **Evidencia.** Las doce ocurren **durante la tanda** de la bitácora
  (transcripción local Voxtral de 42 archivos + OCR de 29 capturas, 16:24 →
  16:50 del 09-01): `SCShareableContent` tarda > 30 s bajo esa carga.
- **Causa.** Contención de CPU/GPU, no permiso. El mensaje culpa al permiso de
  grabación de pantalla y confunde el diagnóstico.
- **Propuesta.** Pausar la captura mientras corre una tanda (o bajarle la
  prioridad), mensaje neutro con la duración real, y contar el evento.

### 2.6 Rutinas de resumen que «fallan» en silencio

- `rutina «cada 3 h · Resumen del día» falló — no hay nada transcrito ni leído`
  ×17 en 7 días: es la rutina de madrugada sin material. No es un fallo;
  debería registrarse como «omitida» y no despertar la IA.
- `… falló — la IA no devolvió texto` ×7 en 6 días: `ContinuoResumen.llamar`
  devuelve `nil` ante cualquier error o código ≠ 2xx **sin registrar cuál**, y
  usa un único proveedor (`ChatIA.seleccionada()`), sin la cascada de pulido.
- **Propuesta.** `sinMaterial` → omitida; registrar HTTP/motivo; llamar por
  `cadenaPulido` con failover como el resto de la app.

### 2.7 Sin internet, la cascada de pulido recorre los 16 proveedores

4 episodios (08-18, 08-19, 08-30, 08-31), 60 líneas de reintento y 16 saltos
cada vez, más el TTS reintentando. **Propuesta.** Cortocircuito por
`NSURLErrorNotConnectedToInternet` (-1009): texto original y voz local de
inmediato, una sola línea en el registro.

### 2.8 Menores

- `pulido: groq falló (HTTP 200: …chat.completion…)` ×4: respuesta 200 sin
  contenido extraíble (modelo `openai/gpt-oss-*`, campo `reasoning`). Revisar
  `extraerContenido`. Baja.
- 38 arranques de la bitácora en 14 días; cada cierre deja 1 archivo huérfano
  (ya en PENDIENTES-0.50.1: `applicationWillTerminate` no cierra la bitácora).
  El rescate funciona. Baja.
- `assemblyai-stream: cancelled` ×3: cancelación normal. Nada que hacer.
- El registro guarda el texto dictado en claro (`[SYS] crudo/IA`); es local y
  rota semanal, pero conviene decidir si el nivel por defecto lo incluye.

## 3. Pendientes heredados de revisiones anteriores

Siguen vigentes los de `PENDIENTES-0.50.1.md` (20) y `PENDIENTES-0.51.1.md`
(2), salvo los que tocaron `5d32952` (fallo de una pantalla no aborta las
demás) y `378d355` (purga sin bloquear, privacidad por defecto). Los de
ContinuoPantalla (estado compartido main/Task) se relacionan con 2.5.

## 4. Decisiones de producto pendientes (de Alberto)

- Notarizar con Apple Developer (99 USD/año) o mantener «Abrir de todos modos»
  en las notas de release.
- Recompresión de los 17,5 GB de PCM (2.1 c).
- ElevenLabs sin créditos: renovar o bajarlo en la cascada (hoy AssemblyAI va
  primero; el TTS ya cae a la voz de macOS).
- Ollama apagado en esta Mac: la capa semántica de modos degrada a exacto/raíz.

## 5. Estado en 0.53.0

| Punto | Estado | Cómo se verifica |
|---|---|---|
| 2.1 compresión m4a | **Corregido**: escritor en su propio ámbito; validación por marcos (≥ crudo − 0,5 s); sin índice actualizado no se suelta el crudo. **Recompresión** en segundo plano (`continuo_recomprimir_pendientes`, pasadas de 1 500 archivos cada 15 min y una por minuto mientras quede cola, se detiene al dictar) + botón «Recomprimir ahora» | `ROBUSTEZTEST` (pcm sintético → m4a 48 000/48 000 marcos) y `BTODICTA_RECOMPTEST=<n>` sobre archivos reales |
| 2.2 streaming Scribe | **Corregido**: `send`/`commit` exigen sesión viva; `quota_exceeded`/`auth_error` → `CuarentenaSTT` 30 min (429 → 5); `onCierre` una sola vez → `planBVivo` a mitad de dictado con todo el audio; las dos puertas al WS consultan también `CuarentenaSTT` | `ROBUSTEZTEST` (inyección de `quota_exceeded`: cuarentena real + cierre avisado una vez) |
| 2.2 (d) etiquetas | **Corregido**: «cuarentena breve (su streaming cayó hace menos de 1 min)» | lectura del log |
| 2.5 capturas en tanda | **Corregido**: rescate a 90 s, mensaje con la causa real (tanda en curso / permiso), aviso único de «captura lenta», ajuste `continuo_pantalla_pausar_en_tanda` (apagado de fábrica) | log durante la próxima tanda |
| 2.6 rutinas | **Corregido**: `sinMaterial` → «omitida»; `llamarUna` devuelve motivo (HTTP/red/sin contenido) y `llamar` prueba hasta dos respaldos de `cadenaPulido` | log de la próxima rutina |
| 2.7 sin internet | **Corregido**: `SinConexion.es` (-1009/-1020); pulido salta directo al primer motor local o al texto original; TTS cae 1 min a la voz local | `ROBUSTEZTEST` (clasificador) |
| 2.8 menores | Pendientes (Groq 200 sin contenido, huérfanos por cierre, nivel del log) | — |
| 3 heredados | Pendientes | — |

Entrenador Piper, destilador y voces sin tocar. Release solo bajo pedido.
