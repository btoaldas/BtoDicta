# Plan 013 — Bitácora solo de grabaciones

- Estado: Aprobado
- Fecha: 2026-10-06
- Aprobado por: Alberto, 2026-10-06 — «si dale», autorización para continuar con plan, tareas e implementación de la versión corregida
- Spec: [spec.md](spec.md)

## Enfoque y contexto técnico

Swift, AppKit y SQLite existentes; macOS 14; extensión JavaScript. Sin dependencias nuevas. La preferencia ausente equivale a true; false explícito se conserva. El maestro conserva su valor. Una política central con bloqueo emite ventanas identificadas y generaciones para invalidar trabajo asíncrono. El audio del dictado se incorpora desde el historial con su sesión original, sin una segunda captura de micrófono ni STT cuando existe texto. Si una pausa o reconfiguración interrumpe la ventana, el WAV completo queda solo en historial para no incorporar intervalos no autorizados; no se recorta el original.

## Comprobación contra la constitución

- [x] Se conserva el historial y los originales; migración SQLite aditiva y reversible por commit.
- [x] Sin credenciales ni evidencia privada en el repositorio público.
- [x] Pruebas con carpetas temporales, sin proveedores de pago ni configuración personal.
- [x] Trabajo en main conforme a la excepción específica de bitácora de AGENTS.md; commit y push autorizados.
- [x] La publicación de una versión instalable queda separada de la implementación.

## Componentes y orden

1. Config y vista: opción independiente del maestro, default por ausencia, notificación de cambio.
2. Política y coordinador: apertura tras recorder.start exitoso; cierre antes de stop/cancelar; pausa y reconfiguración invalidan generaciones. Historial conserva sesión de origen aunque termine después.
3. Capturadores: guardas antes y después de awaits/callbacks; captura inicial de pantalla; sistema ligado a identidad del stream; micrófono continuo quieto en modo nuevo.
4. Índice y lote: sesión nullable, filtro antes de LIMIT, congelación automática de backlog ambiental y guardas en cada nuevo fragmento/proveedor/portero; respuestas ya enviadas pueden guardarse.
5. Navegador: permiso autenticado antes de DOM y captura, sesión e instante validados al recibir, denegación cerrada ante API ausente.
6. Oyente de voz: guarda de modo en vigilancia, rearme y despertar, incluso con maestro apagado.

## Datos y contratos

[Modelo aditivo](data-model.md) y [contratos internos/locales](contracts/README.md). El identificador de sesión distingue material autorizado de backlog ambiental. No se reclasifica material antiguo. Las fuentes desmarcadas, permisos y exclusiones siguen gobernando.

## Decisiones

[ADR 017](../../adr/017-bitacora-ventanas-de-grabacion.md): ventanas explícitas y default por ausencia. El lote manual conserva su autoridad para procesar pendientes anteriores; el automático filtra sesiones y revalida antes de cada nueva solicitud. Los resúmenes y sus envíos configurados conservan sus flujos.

## Riesgos y mitigación

Callbacks tardíos y dictados consecutivos: generación y sesión inmutable. Fallos de STT: no marcar como resuelto un texto vacío. Backlog que ocupa LIMIT: filtrar en SQL. Reintentos internos: guardas hasta Failover y PorteroVoz. Extensión antigua: no permite lectura si falta permiso autenticado. Recursos del sistema: validación nativa y pruebas de política; una prueba aislada no establece consumo histórico exacto.

## Verificación

| Requisito | Evidencia prevista |
|---|---|
| RF-01, RF-07 | Fixtures de configuración ausente, true y false, maestro conservado |
| RF-02, RF-03 | Política de ventanas, generaciones, pausa, callbacks y reposo; pruebas de captura |
| RF-04 | Dictado con texto resuelto y fallo pendiente, originales conservados |
| RF-05 | Compilación y regresión de suite existente, índice y búsqueda histórica |
| RF-06 | Selección SQL antes de LIMIT, sesiones cerradas y corte de nuevos envíos |
| RF-08 | Guardas del oyente verificadas en prueba/inspección independiente |

Compilar y ejecutar las suites nativa y extensión; segunda revisión independiente sobre los caminos de captura/reintento. No invocar purgas, APIs de pago ni el perfil real. Documentar límites de pruebas de permisos de hardware.

## Recuperación

Commit de reversión, sin borrar originales ni columnas ni configuración; clientes existentes recibirán default seguro cuando instalen la actualización. No modificar clientes remotos durante este trabajo.
