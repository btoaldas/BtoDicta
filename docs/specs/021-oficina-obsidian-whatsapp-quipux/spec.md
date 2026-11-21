# Spec 021 — Oficina: Obsidian, WhatsApp, Quipux y actividades

- Estado: Hecha (pendiente prueba real)
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-21
- Modifica: 019, 020
- Aprobada por: Alberto — 2026-11-21 — «Bloque A»
- Rama: `main`

## Alcance

- **Obsidian** (genérico, cualquier usuario): bóveda configurable o la que Obsidian
  tiene abierta. `obsidian_anotar` escribe solo en `BtoDicta/Notas de voz/AAAA-MM-DD.md`
  (nunca en las notas del usuario). `obsidian_buscar` usa Spotlight y, si no trae
  nada, recorre la bóveda; salta archivos que viven solo en la nube, notas de
  credenciales o con secretos, y quita las líneas con claves antes de pasarlas a
  la IA.
- **WhatsApp**: el modo WhatsApp existente deja el mensaje escrito en la app; lo
  envía el usuario. Sin cambios de código.
- **Quipux y registro de actividades**: dependen de credenciales y reglas del
  usuario, así que van por `delegar_agente` (Claude Code con su habilidad). El
  código de BtoDicta queda genérico.
- Lector del plan tolerante: herramienta en «tipo» con otro dato en «clave».

## Evidencia

- 2026-11-21: 241 pruebas, 0 fallos. Búsqueda en la bóveda real: 15,4 s → 0,3 s con
  Spotlight, mismas 4 notas. Evaluación real (glm-5.3) 45/46.
