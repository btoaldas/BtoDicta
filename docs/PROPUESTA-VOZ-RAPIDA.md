# Propuesta: voz clonada SÚPER RÁPIDA sin perder calidad (carriles MLX nuevos, sin romper nada)

**Fecha:** 2026-07-19 · **Autor:** Claude (investigación 28 agentes web + benchmarks propios) · **Para revisión de:** Codex
**Estado:** EJECUCIÓN CONTROLADA — shootout completado; robustez y calentamiento implementados. Ningún
motor experimental se integró porque todavía no superó la referencia XTTS en identidad.

---

## 1. Contexto y realidad computacional

- **Hardware de referencia:** un Mac Apple Silicon reciente (M-series Pro, 64 GB RAM), macOS 26. Sin GPU NVIDIA local.
- **Regla de aceleración (verificada empíricamente):** PyTorch MPS **no sirve** para TTS en este Mac
  (XTTS con GPT en MPS + vocoder CPU dio RTF 1.23 vs 0.52 en CPU puro; Qwen3/F5/fish-speech en MPS: 2.5-10x
  más lentos que tiempo real según issues de terceros). Las vías sanas son **CPU** y **MLX (Metal nativo)**.
- **Entrenamiento pesado:** solo GPU NVIDIA en nube (RunPod/Vast/Colab, ~5-15 USD por corrida). Aceptado.
- **App:** BtoDicta (Swift, SwiftPM, sin Xcode-proyecto). Motores Python viven aislados en
  `~/.btodicta/voz-engine/` (venvs propios, patrón sidecar HTTP local).

### Lo que YA existe y NO SE TOCA (regla de oro)

| Carril | Motor | Calidad | Velocidad medida (Mac de referencia) | Estado |
|---|---|---|---|---|
| Máxima fidelidad | XTTS v2 fine-tune (voz clonada de referencia, `~/.btodicta/voces/voz-referencia`) | **Excelente — es la referencia** | RTF 0.78 streaming vía server residente; primera palabra ≈ colchón (2 s hoy) | Producción (fix d6654cb) |
| Equilibrio | Qwen3-TTS sobre mlx-audio (`MlxVozEngine`, venv `mlx-venv`) | Buena | TTFB ~0.1 s reportado | Producción |
| Rápida | Piper ONNX (`rapida/voz.onnx`) | Robótica (inaceptable como principal) | RTF ~0.2 | Producción |
| Nube | ElevenLabs WS | Excelente | ~75-130 ms | Producción |

**Principio innegociable:** todo motor nuevo entra como **carril adicional parametrizable (toggle, default OFF)**.
La cascada de failover existente queda intacta. Si el motor nuevo suena mal, entrena mal o se cuelga →
se apaga el toggle y todo queda EXACTAMENTE como estaba. Cero regresiones posibles por diseño.

---

## 2. Objetivo (definición de gol)

1. **Latencia:** primera palabra audible en **≤ 1 segundo** con el motor caliente (1 s ya es el tope exagerado).
2. **Calidad:** igual o mejor que el XTTS fine-tuneado actual (juez final: el oído del dueño del proyecto, apoyado por
   similitud d-vector que el Entrenador ya calcula).
3. **100 % local** (la voz nunca sale del Mac). Crear/entrenar/usar voces nuevas con el mismo estándar.
4. **Calentamiento parametrizable** (sección 6).

---

## 3. Candidatos, uno por uno (todo verificado 2026-07-19)

### 3.1 Chatterbox Multilingual + MLX — ★ PROPUESTO COMO PRIMER EXPERIMENTO

- **Qué es:** TTS con clonación zero-shot (10-15 s de referencia) de Resemble AI. 23 idiomas incl. español.
- **Licencia:** MIT (código y pesos) — la más limpia de todas.
- **Velocidad:** único candidato **medido en ESTE Mac**: RTF **0.41** (14.1 s de audio en 5.75 s) con
  `mlx-community/chatterbox-fp16` vía mlx-audio, ~4 GB RAM. Evidencia: `~/Downloads/tts-research-2026-07-19/es_clone*.wav`.
- **Encaje:** corre sobre **mlx-audio, la MISMA librería que BtoDicta ya embarca** para Qwen3
  (`MlxVozEngine`/`MlxVozServer`). Integración = añadir modelo permitido + parámetro `ref_audio`. Mínima cirugía.
- **Ruta de entrenamiento si el zero-shot no clava el timbre:** LoRA con `gokhaneraslan/chatterbox-finetuning`
  (GPU nube; con 30-60 min curados sobra) → convertir a MLX con el tooling de mlx-community.
- **Riesgos:** (a) primera corrida con referencia nueva paga compilación Metal (RTF 2.6) → se resuelve
  precalentando con frase dummy al levantar; (b) conversión LoRA→MLX plausible pero sin confirmación publicada
  → **verificar con un LoRA trivial ANTES de pagar GPU**; (c) el pack dedicado
  `ResembleAI/Chatterbox-Multilingual-es-mx-latam` es solo PyTorch (habría que convertirlo).
- **Nota de acento:** issue #268 reporta seseo latinoamericano en español — para voz ecuatoriana es ventaja.

### 3.2 Qwen3-TTS 1.7B Base fine-tuneado — ★ MEJOR RUTA DE ENTRENAMIENTO FORMAL

- **Qué es:** el modelo que BtoDicta ya usa en el carril equilibrio, pero en variante **Base** fine-tuneada
  con las horas de audio de la voz objetivo. Fine-tune **oficial del vendor** (Apache 2.0 código y pesos).
- **Velocidad:** TTFB 57-111 ms, RTF ~0.59 con 1.7B-4bit en MLX (gist oficial de Blaizzy, mantenedor de
  mlx-audio). En el Mac de referencia será mejor (sin cifra publicada).
- **Encaje:** infra 100 % existente (mismo venv, mismo server, mismo carril). Solo cambia el checkpoint.
- **Ruta de entrenamiento:** LoRA sobre `Qwen3-TTS-1.7B-Base` en GPU nube con
  `instavar/qwen3-tts-lora-finetuning` (parchea el bug de doble label-shift del script oficial;
  10-30 min de audio limpio 24 kHz bastan) → convertir a MLX.
- **Riesgos:** (a) **la conversión checkpoint fine-tuneado → MLX NO está confirmada end-to-end públicamente**
  — verificación barata obligatoria antes de pagar GPU; (b) en zero-shot se cuela acento inglés en español
  (Discussion #230) — irrelevante tras fine-tune nativo, que es exactamente este plan.

### 3.3 F5-TTS español fine-tuneado — plan C (flujo más parecido al actual)

- **Qué es:** flow matching; base española comunitaria de 218 h (`jpgallegoar/F5-Spanish`) + fine-tune oficial
  (`SWivid/F5-TTS`) + inferencia `lucasnewman/f5-tts-mlx`.
- **Velocidad:** RTF ~0.6 medido por el autor del port en M3 Max. (El RTF 0.15 que circula no está verificado.)
- **A favor:** la conversión fine-tune→MLX está PROBADA (`Juanfa/F5-Spanish-MLX-Compat` es exactamente eso;
  `convert_weights` integrado). Flujo idéntico al actual: entrenar → convertir → inferir.
- **Riesgos:** pesos CC-BY-NC (uso personal OK, comercial NO); port MLX sin release desde mar-2025;
  gotcha issue #1292 (quitar prefijo `ema_model.` y usar el `vocab.txt` correcto).

### 3.4 Descartados (con evidencia, para no reabrir)

| Opción | Por qué NO |
|---|---|
| RVC (Retrieval-based VC) | No es TTS; conversor de timbre que PRESERVA la prosodia de la fuente → Piper robótico entra, clon robótico sale. Repo oficial abandonó Mac (main reinicializado solo-Windows 19-jul-2026). Única excepción futura: refinador de timbre opcional (port MLX Acelogic, RTF 0.09 en M3 Max, sin licencia declarada). |
| CorentinJ/Real-Time-Voice-Cloning | 2019, solo inglés, 16 kHz; el propio autor lo declara superado y redirige a Chatterbox. |
| PyTorch MPS (cualquier modelo) | Medido/verificado: siempre peor que CPU o inestable. MLX es la única aceleración sana. |
| Piper con más entrenamiento | Lo robótico es techo arquitectural (VITS chico), no falta de steps. |
| chatterbox-turbo | Solo inglés. |
| fish-speech/OpenAudio en Mac | 5-10x más lento que tiempo real (PR #461). |
| Orpheus | Sin soporte Apple Silicon (issue #178 sin respuesta desde 2025). |
| Kokoro / Kyutai pocket-tts | Rapidísimos pero no clonan voz arbitraria (Kokoro) o calidad de modelo diminuto (Kyutai). |

---

## 4. Presupuesto de latencia para el gol de ≤ 1 s

Con motor caliente (server residente, modelo en RAM, kernels compilados):

| Motor | Primera palabra estimada | Cómo |
|---|---|---|
| Qwen3-TTS MLX | ~0.1-0.3 s | TTFB nativo 57-111 ms + colchón mínimo |
| Chatterbox MLX | ~0.5-1.0 s | RTF 0.41: frase corta inicial (~2 s de audio) lista en ~0.8 s; mejor aún si mlx-audio permite streaming por chunks (VERIFICAR — pregunta a Codex #2) |
| XTTS actual | ~1.0-1.2 s | Bajar `tts_xtts_colchon_seg` de 2.0 → 1.0-1.2 (ya parametrizable HOY; con RTF 0.78 hay riesgo leve de microcortes en frases largas — mitigable partiendo por frases) |

Táctica común a todos los carriles: **partir el texto por frases y generar primero una frase corta** —
la reproducción de la frase 1 cubre la generación de la 2 en adelante (pipeline).

---

## 5. Plan por fases con criterios GO/NO-GO (nada se rompe en ninguna fase)

### Fase 1 — Shootout a oído, CERO cambios en la app (1-2 h, gratis)
Con 10-15 s limpios de la voz clonada de referencia, generar el MISMO párrafo con:
Chatterbox-MLX (venv de prueba ya existe en `/tmp/cbx-venv`), Qwen3-TTS CustomVoice, F5-Spanish-MLX,
y compararlo contra el XTTS actual. Medir RTF y tiempo-a-primer-audio reales en el Mac de referencia + escuchar.
- **GO a Fase 2** si algún candidato suena ≥ XTTS (oído + d-vector) y da RTF < 0.5.
- **NO-GO:** quedarse con XTTS + bajar colchón a 1 s. Nada cambió.

### Fase 2 — Carril experimental en BtoDicta (solo si Fase 1 da GO)
- Integrar el ganador como carril nuevo **default OFF** (toggle en Ajustes, como todo en BtoDicta).
- Chatterbox: extender `MlxVozEngine.modelosPermitidos` + pasar `ref_audio` de la voz activa.
- Precalentamiento según spec (sección 6), incluida frase dummy anti-compilación.
- Botón A/B en la biblioteca: misma frase por XTTS y por el candidato, escuchar lado a lado.
- **GO a Fase 3** solo si el timbre zero-shot NO iguala al XTTS afinado pero la velocidad/naturalidad convencen.

### Fase 3 — Fine-tune en nube (solo si hace falta timbre exacto)
- **ANTES de pagar GPU:** verificar la conversión checkpoint→MLX con un LoRA trivial de 10 pasos.
- Entrenar LoRA (Chatterbox o Qwen3 según ganador; 30-60 min de audio curado del dataset existente).
- Validar con el pipeline del Entrenador ya construido (d-vector coseno vs voz real + escuchar y elegir).
- El paquete resultante entra por el mismo carril experimental. XTTS sigue intacto como respaldo.

### Fase 4 — Solo si todo convence tras semanas de uso real
Recién ahí discutir si el carril nuevo pasa a ser default. XTTS NUNCA se elimina (respaldo de máxima fidelidad
y motor del Entrenador actual).

---

## 6. Política de calentamiento (spec del dueño del proyecto — TODO parametrizable)

| Parámetro (por motor) | Default propuesto | Comportamiento |
|---|---|---|
| `voz_warmup_arranque` | ON | Al abrir BtoDicta: levantar el motor de voz activo y dejarlo caliente. |
| `voz_warmup_arranque_min` | **60** | Ventana caliente inicial: 1 hora desde el arranque. Si en esa hora no se usó, se apaga (libera RAM). |
| `voz_caliente_tras_uso_min` | **15** | Tras CADA uso, mantener caliente 15 min más; luego dormir hasta el próximo uso. |
| `voz_warmup_dummy` | ON | Al levantar, generar una frase corta muda (compila kernels Metal / llena cachés) para que la primera frase real ya sea rápida. |

Implementado: XTTS y Qwen3‑MLX tienen su propia ventana inicial, su tiempo post-uso, calentamiento silencioso
y controles en la interfaz. Solo permanece caliente la variante activa; cambiar de carril descarga la anterior.
El ahorro global respeta la ventana inicial y, al primer uso real, pasa a contar el tiempo post-uso.

---

## 7. Preguntas concretas para Codex

1. **Arquitectura:** ¿carril Chatterbox DENTRO de `MlxVozServer` existente (mismo proceso/puerto, modelos
   intercambiables) o server mlx-audio separado en otro puerto? Trade-off: RAM/simplicidad vs aislamiento de fallos.
2. **Streaming:** ¿`mlx_audio` expone generación por chunks (streaming) para Chatterbox/Qwen3, o solo WAV
   completo? Si solo completo: ¿partir por frases en Swift (como hoy) basta para ≤ 1 s?
3. **Convivencia de motores calientes:** ¿política cuando el usuario alterna voces (XTTS clon ↔ Chatterbox
   clon)? ¿Dormir el no-activo de inmediato o respetar los 15 min de cada uno?
4. **Verificación LoRA→MLX barata:** ¿mejor camino para confirmar la conversión Qwen3/Chatterbox fine-tuneado
   → MLX sin gastar en GPU (¿checkpoint dummy en CPU? ¿Colab gratis?)?
5. **Riesgo del colchón 1 s en XTTS** (RTF 0.78): ¿colchón adaptativo (arrancar al tener frase 1 completa
   en vez de N segundos fijos) es mejor que bajar el número a ciegas?
6. ¿Algo del plan viola el principio "no romper nada"? ¿Falta algún rollback?

---

## 8. Resumen ejecutivo

- **Mantener TODO lo actual tal cual** (XTTS = referencia de calidad, intocable).
- **Evaluar Chatterbox-MLX sin integrarlo primero** — fue rápido, pero el shootout posterior no superó la
  identidad XTTS; por el propio gate de este documento quedó fuera de la app.
- **Qwen3-TTS Base fine-tune como ruta de entrenamiento formal** (Apache, oficial) y **F5-Spanish como plan C**
  (conversión a MLX ya probada por terceros).
- **Gol:** primera palabra ≤ 1 s con motor caliente, calidad ≥ XTTS actual, todo local, todo parametrizable,
  warm-up 60 min al abrir + 15 min tras cada uso.
- **Si algo se comporta o entrena mal: toggle OFF y quedamos exactamente como hoy.**

---

## 9. Resultado de la ejecución (2026-07-19)

### 9.1 Fallo real encontrado y corregido en XTTS

El problema de que la voz empezaba bien y luego se cortaba no era una pérdida del checkpoint. Para textos
largos, Coqui intentaba dividir el texto con `enable_text_splitting=True`, pero el runtime aislado de BtoDicta
no incluye spaCy. El servidor ya había respondido HTTP 200 cuando Python lanzaba la excepción; por eso el
cliente podía confundir audio vacío/truncado con una respuesta correcta.

Corrección aplicada:

- segmentación española liviana y local, dentro del límite real del tokenizer;
- inferencia por segmentos sin spaCy, con 80 ms de separación natural;
- transferencia HTTP `chunked`: solo un final completo se acepta como éxito;
- cierre explícito de cada conexión: un keep-alive ocioso ya no puede monopolizar el
  servidor serial y bloquear al reproductor de streaming;
- la ruta residente y la ruta de respaldo usan la misma regla;
- hook QA con dos respuestas consecutivas, texto largo, duración de audio, RTF y error real.

Pruebas sobre la voz instalada `voz-referencia`:

| Prueba | Resultado |
|---|---|
| Texto largo, pedido 1 | 30,17 s de audio; RTF 0,921; HTTP 200; completo |
| Texto largo, pedido 2 | 31,52 s de audio; RTF 0,897; HTTP 200; completo |
| Streaming detallado | primer PCM 0,443 s; RTF 0,740; sin vaciados del colchón desde 0,5 s |
| Seis respuestas calientes | RTF 0,625–0,753; memoria estable; cero degradación progresiva |
| Ruta de respaldo sin servidor | WAV válido de 300.332 bytes |

El colchón configurado permanece en 2 s: la medición demuestra que puede bajarse, pero no se reduce a
ciegas porque la estabilidad tiene prioridad.

### 9.2 Shootout Chatterbox-MLX

Se generó el mismo texto con la misma referencia real de 12 s. Resultados:

- audio: 16,40 s;
- RTF en proceso nuevo: 0,37; RTF caliente repetido: 0,28–0,30;
- inteligibilidad Whisper: 0,9592;
- similitud de voz: **0,8178**, menor que XTTS (**0,8753** en la comparativa existente);
- la versión actual de `mlx-audio` genera Chatterbox completo: no ofrece chunks reales para este motor.

**Decisión: NO-GO a integración.** Es rápido y estable, pero no iguala la identidad de XTTS; por tanto no
se añadió un toggle decorativo ni otro servidor pesado. Las muestras quedaron en
`~/Downloads/Comparativa_Voz_Rapida_BtoDicta_2026-07-19/` para escucharlas.

### 9.3 Qwen3-MLX, F5 y respuestas arquitectónicas

- **Qwen3-MLX:** sigue como carril equilibrado separado. El calentamiento real cargó el servidor en 2,23 s,
  precompiló silenciosamente y completó dos generaciones. Un fine-tune formal queda bloqueado por el gate
  correcto: demostrar primero, con un checkpoint trivial, que la conversión hacia MLX conserva los pesos.
- **F5-Spanish:** no entra en BtoDicta por ahora. Sus pesos compatibles tienen licencia no comercial; no es
  una base adecuada para un producto que debe poder usarse libremente. No se descargó ni se alteró el Mac.
- **Arquitectura futura:** un motor experimental iría en proceso/puerto separado, pero solo el activo puede
  permanecer caliente. Así un crash no contamina Qwen y nunca conviven varios modelos de 4 GB.
- **Streaming:** Qwen sí tiene entrega progresiva; Chatterbox no en la versión evaluada. Partir frases ayuda
  a la latencia, pero no debe venderse como WebSocket/streaming verdadero.
- **Rollback:** cualquier candidato futuro necesita toggle OFF por defecto, manifiesto tolerante, watchdog,
  verificación de audio completo y prueba A/B antes de poder activarse.

### 9.4 Política térmica aplicada

- al abrir: solo el motor local activo queda protegido **60 min**;
- tras el primer uso: cambia a **15 min** de inactividad;
- frase silenciosa configurable para calentar el camino real (y Metal en MLX);
- XTTS y Qwen3‑MLX tienen controles independientes; 0 min desactiva la protección inicial;
- si el calentamiento falla, se registra y la cascada continúa: nunca detiene al asistente.

Fuentes primarias consultadas: [MLX Audio](https://github.com/Blaizzy/mlx-audio),
[releases de MLX Audio](https://github.com/Blaizzy/mlx-audio/releases),
[Chatterbox MLX](https://huggingface.co/mlx-community/chatterbox-fp16),
[Qwen3-TTS oficial](https://github.com/QwenLM/Qwen3-TTS),
[F5-TTS oficial](https://github.com/SWivid/F5-TTS) y
[F5-Spanish MLX Compat](https://huggingface.co/Juanfa/F5-Spanish-MLX-Compat).
