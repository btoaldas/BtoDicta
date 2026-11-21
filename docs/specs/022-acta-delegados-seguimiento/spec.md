# Spec 022 — Acta de reunión, aviso de encargos y seguimiento de correos

- Estado: Hecha (pendiente prueba real)
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-21
- Modifica: 019, 020
- Aprobada por: Alberto — 2026-11-21 — «Sí, bloque B»
- Rama: `main`

## Alcance

- **Acta de reunión.** «Graba esta reunión» graba el micrófono en
  `Documentos/BtoDicta/Reuniones/` (tope 3 h). «Terminó la reunión» transcribe,
  la IA devuelve solo datos (JSON: resumen, acuerdos, tareas con responsable y
  fecha, pendientes), BtoDicta arma el Word con su plantilla, guarda la
  transcripción junto al audio y anota las tareas del usuario. La memoria
  conserva el resumen para el correo de seguimiento. El audio del sistema
  (videollamadas) queda para después.
- **Aviso de encargos delegados.** Claude Code recibe `--settings` con un gancho
  `Stop` y Codex `-c notify=…` que tocan `~/.btodicta/delegados/<id>.fin`;
  BtoDicta lo vigila y dice «ya respondió… te espera en la Terminal». Sin tocar la
  configuración global del usuario. Probado en real con Claude Code; Codex sin
  probar en real.
- **Seguimiento de correos.** `seguir_correo` («avísame si X no me responde hasta
  el viernes», «avísame cuando me escriba X») en `~/.btodicta/seguimientos.json`;
  revisión cada 15 min con la búsqueda de la cuenta; sin plazo, 7 días.

## Evidencia

- 2026-11-21: 249 pruebas, 0 fallos. Evaluación real (glm-5.3) 48/49. Acta con IA
  real sobre una transcripción de ejemplo: título, 2 acuerdos, 2 tareas con su
  responsable. Gancho Stop de Claude Code: crea la señal.
