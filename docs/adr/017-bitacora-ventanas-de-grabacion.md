# ADR 017 — Ventanas de captura explícita de bitácora

- Estado: aceptada
- Fecha: 2026-10-06
- Referencia: spec 013, aprobada por Alberto

## Contexto

La captura ambiental y su backlog pueden seguir generando solicitudes mientras no se dicta. El oyente de activación por voz es independiente del maestro.

## Decisión

Usar preferencia true por ausencia, respetar false explícito y emitir ventanas con UUID y generación tras comenzar el grabador. Reutilizar el dictado y su texto. Conservar sesión en el índice mediante columnas aditivas y filtrar backlog automático antes del límite. Revalidar antes de cada nuevo envío interno. Suspender oyente cuando la preferencia sea true aunque el maestro esté apagado. Preservar el modo continuo seleccionable y el procesamiento manual explícito.

## Consecuencias

No hay migración destructiva ni pérdida del historial. Respuestas ya enviadas pueden guardarse; capturas tardías solo se aceptan con sesión e instante originales. El ahorro futuro depende del tiempo grabado y fuentes habilitadas; la auditoría de una clave compartida no atribuye todo el consumo a esta app.

## Bordes verificados

Una pausa o reconfiguración durante el dictado invalida la adopción de su WAV completo, que queda íntegro en historial. Así no se incorpora el tramo pausado ni se genera STT parcial adicional. Los contextos de pantalla/sistema ya autorizados mantienen sus sesiones. Si la imagen todavía no había vuelto del API al detenerse, se descarta de forma conservadora.
