# Cascada de archivos y pulido adaptativo

## Cambios

- Importar/retranscribir usa siempre `AudioArchivo` → WAV PCM16 mono 16 kHz
  → `Failover`. Se conserva el orden de proveedores STT habilitados y su
  cuarentena; no existe un atajo de MP3/M4A/MP4/MOV hacia ElevenLabs.
- Decodificación nativa macOS. Para códecs no compatibles (por ejemplo Ogg),
  puede usar ffmpeg si ya está instalado; nunca lo descarga. Sin decodificador
  da un error local antes de subir contenido. El original permanece intacto.
- Límite local: 512 MB de PCM (~4,6 horas) y 180 s de conversión por motor.
  Un archivo vacío, sin pista o dañado no debe enviarse a un proveedor.
- DeepSeek predeterminado: `deepseek-flash` (V4.1 Flash), con
  `thinking.type=disabled`. Groq: `openai/gpt-oss-20b`, esfuerzo bajo.
- Plazo por proveedor: base 8 s + `(caracteresTexto-500)/90` +
  `(caracteresPrompt-3000)/400`, sumando solo excesos positivos, máximo 120 s.
  El prompt incluye instrucciones/glosario. Configuración manual base: 5–60 s.
- Deadline de pared con cancelación y callback único, sin repetir un timeout
  contra el mismo proveedor. Respuestas truncadas/inválidas pasan al siguiente.
- Cuarentena efímera: sin conexión/timeout 15 s; cuota/auth/modelo no disponible
  30 min; rate limit 60 s; 5xx 30 s. Sin internet se omite la nube y se conservan
  los locales. Modelo/clave diferente obtiene otra identidad; no se guardan claves
  en la tabla. Cambiar el orden no modifica la selección persistente.
- Agotada la cascada de pulido, se entrega la transcripción original.

## Verificación reproducible

```sh
swift test --build-path build-agent --filter CascadaTests
swift build -c release --build-path build-agent
BETODICTA_QA_BIN="$PWD/build-agent/release/BetoDicta" scripts/qa-paquete.sh --automatico
```

Los tests de formatos requieren ffmpeg existente para generar fixtures: WAV
estéreo/48 kHz, MP3, M4A, MP4/MOV con vídeo y Ogg. Se comprueban bytes originales
intactos, WAV mono/16 kHz, entrega a la cascada, y archivo corrupto sin upload.
Pruebas HTTP simuladas: cuota y siguiente dictado, timeout sin reintento, respuesta
de clasificador, original conservado, límite real con callback único, texto largo
sin recorte del plazo, expiración/aislamiento de cuarentena.

Integración opt-in (consume los proveedores configurados; no guarda ni pega):

```sh
BETODICTA_ARCHIVOCASCADATEST=/ruta/prueba.mp3 /ruta/BetoDicta.app/Contents/MacOS/BetoDicta
BETODICTA_PULIDOADAPTATIVOTEST=deepseek /ruta/BetoDicta.app/Contents/MacOS/BetoDicta
BETODICTA_PULIDOADAPTATIVOTEST=groq /ruta/BetoDicta.app/Contents/MacOS/BetoDicta
```

## Fuentes y precios (consulta 2026-09-10)

- [DeepSeek pricing](https://api-docs.deepseek.com/quick_start/pricing/):
  `deepseek-flash` = V4.1 Flash. Entrada/salida sin caché por millón: fuera de
  pico USD 0,15/0,60; pico USD 0,30/1,20. El precio curado usa pico como estimación
  conservadora; no sustituye una tarifa manual ni representa la factura real.
- [Thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/): habilitado
  con esfuerzo alto por defecto; se desactiva explícitamente para este flujo.
- [Groq modelos](https://console.groq.com/docs/models): GPT OSS 20B es el
  generativo de producción con menor tarifa pública, USD 0,075/0,30 por millón.
  Los Prompt Guard baratos son clasificadores, no editores de texto.

Instalar requiere respaldo previo del bundle y configuración, firma verificada
y aprobación específica. No fusionar esta rama a main sin aprobación separada.

## Resultado de esta validación

- Tests nuevos: 7/7, repetidos con MP4/MOV que contienen vídeo.
- Suite general: 15/15 en debug y 15/15 en el paquete release firmado.
- MP3 sintético: conversión + Voxtral local + frase completa, 9,39 s en frío.
  Mismo hash del original antes/después. Repetido desde la interfaz instalada:
  resultado completo visible, 67 caracteres.
- Pulido desde el paquete real: DeepSeek Flash 1,43 s; Groq GPT OSS 20B 0,38 s.
  Son mediciones de una frase breve, no SLA. Peticiones de prueba sin guardado
  ni pegado automático.
- Instalación local aprobada y completada: identidad/firma conservadas,
  selección DeepSeek Flash, Groq GPT OSS 20B y base 8 s. Orden STT sin cambios.
- SHA-256 del ejecutable firmado instalado y staged:
  `7ed1e62a294bdbb85a69fc5cda698abbf5af37be7f25978ef4989d5a4b8b90b5`.
- Evidencia bajo `build-agent/qa-cascada-adaptativa-*` (no versionada).
  App anterior, config y proveedores respaldados fuera del repositorio.
