# Spec 025 — Acta completa: personas, agenda, seguimiento y gestión documental

- Estado: Hecha (pendiente prueba real en una reunión)
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-22
- Modifica: 022, 024
- Aprobada por: Alberto — 2026-11-22 (lista de mejoras del acta y release 0.90.0)
- Rama: `main`

## Alcance

- **Quién habla**: cada pista se transcribe con ElevenLabs Scribe y `diarize`
  («Persona 1: …»); sin clave de ElevenLabs, la cascada de siempre. La IA usa el
  nombre si alguien se presenta.
- **Agenda**: el evento que más se solapa con la grabación da el título y los
  invitados (Microsoft `attendees`, Google `attendees` sin el propio).
- **Correo de seguimiento**: con invitados, queda como BORRADOR (resumen, acuerdos,
  tareas) y Beto pregunta si lo envía; el envío sigue exigiendo «confirmo».
- **Gestión documental**: `acta_a_documental` encarga a Claude Code un memorando
  BORRADOR (por defecto Quipux, con la habilidad del usuario), confirmado antes.

## Evidencia

- 2026-11-22: 263 pruebas, 0 fallos. Diarización real con ElevenLabs sobre un
  audio de dos voces: «Persona 1 / Persona 2» correctas.
