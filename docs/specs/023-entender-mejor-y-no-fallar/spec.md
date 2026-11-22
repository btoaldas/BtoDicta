# Spec 023 — Entender mejor y no fallar (bloque C)

- Estado: Hecha (pendiente prueba real de la visión)
- Tipo: mejora
- Nivel: P
- Fecha: 2026-11-21
- Modifica: 017, 019, 020
- Aprobada por: Alberto — 2026-11-21 — «Vamos con el punto cinco total»
- Rama: `main`

## Alcance y resultado

- **Palabras del dictado.** Glosario del usuario ampliado de 75 a 106 términos
  (solo se añadieron; respaldo en `~/.btodicta/backups/`). Es dato del usuario, no
  del repositorio.
- **Ver la pantalla de verdad.** `VisionIA`: la captura reducida (JPEG, 1600 px)
  va a un modelo con visión del proveedor (Z.ai `glm-4.6v`, OpenAI `gpt-4.1-mini`,
  o `agente_vision_modelo`; «-» lo apaga). Si no hay o falla, OCR como antes.
  Probado en real con `glm-4.6v`: 3 s, descripción correcta.
- **Más rápido.** Medido: la decisión del modo «Todo» tarda 1,5–4 s con glm-5.3.
  No se cambia de modelo: la espera que se nota es la voz y la transcripción.
- **Pruebas encadenadas.** `testCadenasConIA`: 10 pedidos que dependen del turno
  anterior. 8/10 → 9/10 tras dos ajustes (modificar el borrador recién hecho;
  «contestarle» cede la regla de recordatorios).

## Evidencia

- 2026-11-21: 255 pruebas, 0 fallos. Evaluación general 47/49; cadenas 9/10.
