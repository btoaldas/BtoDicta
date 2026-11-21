# Spec 020 — Pulido del asistente de oficina

- Estado: Hecha (pendiente prueba real)
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-21
- Modifica: 017, 019
- Aprobada por: Alberto — 2026-11-21 — «Los 4 primeros»
- Rama: `main`

## Alcance

1. **Confirmar por voz.** El cuadro sigue; además Beto pregunta en voz alta y, al
   terminar, escucha «sí» o «no» con el reconocimiento local de Apple. Cualquier
   «no» gana. Ajuste `agente_confirmar_voz` (encendido). Sin permiso o sin modelo,
   solo el cuadro.
2. **Sin cortes al empezar a hablar.** En la conversación seguida, el aviso «tin»
   sonaba antes de que el micrófono grabara y se perdían las primeras palabras.
   Ahora suena cuando llega el primer audio.
3. **Resumen de la mañana.** Calendario y recordatorios del Mac, correo y agenda
   del día de todas las cuentas, contado por la IA. Por voz o a la hora elegida
   (`agente_resumen_manana_activo`, apagado; `agente_resumen_manana_hora`), una vez
   al día y, si el Mac dormía, solo hasta mediodía.
4. **Del correo a la tarea.** `correo_a_tarea` crea una tarea (con aviso si hay
   fecha) desde un correo de la lista o el más reciente. La regla fija de
   recordatorios cede cuando el pedido habla de un correo.

## Evidencia

- 2026-11-21: `swift test` 235 pruebas, 0 fallos. Evaluación real (glm-5.3) 42/43,
  41/43 y 40/43 entre corridas; corregido el plan con la herramienta en «tipo».
