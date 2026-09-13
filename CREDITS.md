# Créditos y licencias de terceros

BtoDicta se apoya en tecnología de código abierto de otras personas y equipos. Aquí
va el reconocimiento y la licencia de cada una — con gratitud. Si algo falta o está
mal atribuido, es un error nuestro: avísanos y lo corregimos.

BtoDicta descarga estas herramientas **bajo demanda y con tu permiso** (no las
incluye en el instalador ni en el repositorio por peso). Ver "Descargas bajo demanda".

## Texto → voz (TTS)

- **Coqui TTS / XTTS v2** — clonación de voz de alta calidad. Código: [coqui-tts](https://github.com/idiap/coqui-ai-TTS) (fork mantenido por Idiap), licencia **MPL-2.0**. Modelo XTTS v2: **Coqui Public Model License (CPML), uso NO comercial**. Gracias a Coqui y a la comunidad.
- **Resemble Enhance** — restauración local de detalle para la variante ✨ Máxima. Código y modelo: [ResembleAI/resemble-enhance](https://github.com/resemble-ai/resemble-enhance), licencia **MIT**. BtoDicta verifica el peso oficial por SHA‑256 antes de usarlo.
- **Piper** — TTS rápido (VITS/ONNX), voz fija. [OHF-Voice/piper1-gpl](https://github.com/OHF-Voice/piper1-gpl) y el original [rhasspy/piper](https://github.com/rhasspy/piper), licencia **GPL-3.0**. Autor: Michael Hansen (rhasspy). Gracias.
- **Qwen3‑TTS** — TTS multilingüe y clonación por referencia para el carril local equilibrado. [QwenLM/Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS), licencia **Apache-2.0**; modelos según su ficha en Hugging Face.
- **MLX-Audio / Apple MLX** — inferencia y streaming optimizados para Apple Silicon. [Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio) y [ml-explore/mlx](https://github.com/ml-explore/mlx), licencias open source indicadas por cada proyecto.
- **VITS / monotonic_align** — arquitectura base de Piper. Jaehyeon Kim et al., licencia **MIT**.
- **Voces Piper de prueba** — de [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices): `es_ES-davefx-medium` y `es_MX-claude-high`. Licencias por voz (CC/MIT) según cada dataset. Gracias a quienes donaron su voz y a los entrenadores.
- **ElevenLabs** — TTS en la nube (opcional, con tu propia API key). Servicio comercial de ElevenLabs; se usa su API bajo tus términos.
- **Voz de macOS (AVSpeechSynthesizer) y Apple Speech** — de Apple, parte del sistema.

## Voz → texto (STT)

- **OpenAI Whisper** — reconocimiento de voz. Licencia **MIT**. Y **mlx-whisper** (Apple MLX), MIT.
- **Apple Speech (SpeechAnalyzer)** — nativo de macOS 26, de Apple.
- Proveedores de nube opcionales (con tu key): ElevenLabs Scribe, Groq, OpenAI, Mistral/Voxtral, Deepgram, etc. — cada uno bajo sus términos.

## Entrenamiento y utilidades

- **PyTorch** — Meta AI, licencia **BSD-3-Clause**.
- **Resemblyzer** — verificación de locutor (d-vector) para elegir el mejor checkpoint. Licencia **Apache-2.0** (Corentin Jemine).
- **PyTorch Lightning** — entrenamiento de Piper. Licencia **Apache-2.0** (Lightning AI).
- **librosa / soundfile / matplotlib / numpy** — audio y gráficas. Licencias ISC/BSD/otras open source.
- **uv** — gestor de entornos Python. [Astral](https://github.com/astral-sh/uv), **Apache-2.0/MIT**. Con **python-build-standalone**.
- **ffmpeg** — audio/video. LGPL/GPL.

## Descargas bajo demanda (qué se baja y cuándo)

Para no inflar el repositorio ni el instalador, lo PESADO se descarga **solo cuando lo
usas y con aviso explícito** ("voy a descargar X para hacer Y"):

- **Motor de voz** (Python propio + PyTorch + Coqui) — al pulsar "Instalar motor de voz".
- **Herramientas de entrenamiento** (Whisper, Resemblyzer, Piper training) — al preparar un entrenamiento.
- **Modelos y voces** (XTTS base, voces Piper `.onnx`, modelos de tu clon) — al usarlos.

Lo **liviano** (los scripts del pipeline) sí vive en el repositorio. Nada pesado se sube
al Git.
