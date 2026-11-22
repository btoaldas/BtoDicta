# Spec 024 — Acta con el sonido del equipo

- Estado: Hecha (pendiente prueba real en una videollamada)
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-22
- Modifica: 022
- Aprobada por: Alberto — 2026-11-22 — «hagamos el cuatro»
- Rama: `main`

## Alcance

- `GrabadorSistemaReunion` (ScreenCaptureKit, permiso de Grabación de pantalla):
  graba lo que suena en el equipo, sin la voz de BtoDicta, a `…equipo.wav`
  (PCM16 mono 16 kHz) junto al audio del micrófono. Independiente de la bitácora.
- Al terminar se transcriben las dos pistas por separado y la IA recibe «YO»
  (micrófono) y «LOS DEMÁS» (equipo); las tareas que asume «YO» son del usuario.
  La transcripción guardada lleva las dos pistas rotuladas.
- `agente_acta_sonido_equipo` (encendido). Sin permiso o con error, el acta sigue
  solo con el micrófono y Beto lo dice.

## Evidencia

- 2026-11-22: 257 pruebas, 0 fallos (cabecera WAV, prompt de dos pistas). La
  captura real no se probó desde las pruebas (pediría permiso al binario de prueba).
