# Hito — Bitácora solo de grabaciones

- Fecha: 2026-10-06
- Spec: [013](../specs/013-bitacora-solo-de-grabaciones/spec.md)
- Autorización: Alberto — «si dale» para plan, tareas e implementación; commit y push solicitados expresamente.
- Implementación publicada: [476a469](https://github.com/btoaldas/BtoDicta/commit/476a4696257db50ef04bebf18977337ab5857486)

## Resultado

Opción activada por defecto cuando falta la preferencia; conserva maestro y elecciones posteriores. Captura de bitácora ligada a grabaciones explícitas, audio/texto reutilizados, backlog ambiental automático congelado y oyente de activación por voz suspendido incluso con maestro apagado. Modo continuo y acceso manual al historial conservados. Extensión 0.6.0 condiciona DOM e imagen a permiso autenticado.

## Evidencia

114 pruebas Swift (32 nuevas), 63 comprobaciones JavaScript, reposo real 61 s con maestro activo y cero solicitudes/muestras/bytes/recursos en tres fuentes; voz también quieta con maestro apagado. Compilaciones debug/release correctas, revisión independiente y migración aditiva idempotente. [Matriz y límites](../specs/013-bitacora-solo-de-grabaciones/verificacion.md), [reproducción](../specs/013-bitacora-solo-de-grabaciones/evidencia.md).

HEAD, origin/main y API de GitHub reconciliados para 476a469. Hito registrado en Obsidian con autor Codex, releído y verificado. La auditoría de cuenta queda privada.

## Desviaciones respecto a la spec

Un dictado que atraviesa pausa/reconfiguración conserva su WAV completo en historial y se excluye de adopción completa a bitácora. No se recortan originales ni se manda STT parcial adicional. La pantalla descarta imágenes que no hubieran vuelto del API al cerrar; la extensión sondea cada 500 ms.

## Riesgos residuales y continuidad

Sin prueba positiva de hardware/permisos sobre datos personales; los tests usan audio sintético y perfiles aislados. La extensión necesita recarga para que su guarda previa al DOM esté activa; API nueva ya impide ingreso antiguo no autorizado. El indicador histórico de aporte texto/OCR no aprobó el ratio de sus datos previos y permanece documentado por separado; no hubo cambios de umbral o históricos. El control Semillas informó recurso no disponible en el contexto SPM.

No se instaló ni publicó una release. Los clientes aplicarán el default al instalar una versión que incluya este cambio; conservarán una elección false explícita posterior. Recuperación mediante commit revisado, sin eliminar historial ni columnas.
