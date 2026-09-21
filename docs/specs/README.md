# Especificaciones

Una carpeta por funcionalidad: `NNN-slug/` con `spec.md` (qué), `plan.md`
(cómo), `tasks.md` (en qué orden, con evidencia) y `verificacion.md`. Flujo y
puertas: skill `sdd`. Formato de RF: sw-requerimientos. Nivel: ROADMAP.

Estados de una spec: Borrador → En revisión → Aprobada → En implementación →
Implementada → Cerrada | Descartada. Una spec Cerrada no se edita; lo nuevo es
otra spec con `Modifica: NNN`.

## Índice

<!-- sdd:indice:inicio -->
| NNN | Título | Estado | Nivel | Tipo | Fecha | Aprobada por | Modifica | Fase |
|---|---|---|---|---|---|---|---|---|
| 001 | Memoria del dictado largo | Implementada (0.63.4 y 0.63.5) | X | funcionalidad | 2026-09-14 | Alberto — 2026-09-14 — «acepto, como te digo, la recomendación de X, pero bajo esos términos y cuidados que te digo» | ninguna | Especificando |
| 002 | Corrección: Cancelar un dictado no puede borrar el audio | Implementada (0.59.1 y 0.59.2) | X | correccion | 2026-09-14 | Alberto — 2026-09-14 — «vamos de los tres [pendientes] el que sea más rápido»; RF-01 era «de ley» | ninguna | Especificando |
| 003 | Resumen de la bitácora por correo | Implementada (0.61.0 y 0.62.0) | X | funcionalidad | 2026-09-14 | Alberto — 2026-09-14 — «hagámoslas todas bajo goal, una por una… puedes utilizar un correo de eztic.ec para probarlo» | ninguna | Especificando |
| 004 | Panel de salud y aviso de saldo | Implementada (0.63.0) | X | funcionalidad | 2026-09-15 | Alberto — 2026-09-15 — «estas ideas me gustan: aviso cuando un proveedor se queda sin saldo… un panel de salud» | ninguna | Especificando |
| 005 | API de transcripción para servicios externos | Implementada (0.65.0) | X | funcionalidad | 2026-09-18 | Alberto — 2026-09-19 — «continúa con todo bajo goal y loop… ya no necesito que vuelvas a pararte hasta que termines absolutamente todo» | ninguna | Especificando |
| 006 | Extensión de navegador para la bitácora | Aprobada | X | funcionalidad | 2026-09-20 | Alberto — 2026-09-20 — «aprobado, dale con el plan» | ninguna | Implementando: T26 de T27 |
| 007 | Asistente de exclusiones con semillas y modo de trabajo | Aprobada | P | funcionalidad | 2026-09-21 | Alberto — 2026-09-21 — «si dale» (a «¿Apruebo la spec y paso al plan?») | ninguna | Lista para tareas |
| 008 | El texto que se guarda es el que se está leyendo | Aprobada | X | cambio | 2026-09-21 | Alberto — 2026-09-21 — «resuelve aprobado te doy» | 006 | Planificando |
| 009 | Buscar por palabras en la bitácora | Aprobada | X | funcionalidad | 2026-09-21 | Alberto — 2026-09-21 — «resuelve aprobado te doy» | ninguna | Planificando |

<!-- sdd:indice:fin -->
