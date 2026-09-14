# ROADMAP — BtoDicta

Documento **vivo**. El propósito y lo no negociable están en `MANIFIESTO.md`.

## Estado

| | |
|---|---|
| Versión publicada | 0.59.0 (2026-09-14) |
| Estado | En uso diario · publicado en GitHub y por Homebrew |
| **Nivel** | **X — producción** |
| Repositorio | `github.com/btoaldas/BtoDicta` |

**Por qué nivel X.** Está publicado y hay instalaciones fuera de esta máquina;
maneja la voz del usuario y sus claves de API, que cuestan dinero; y su fallo
característico —perder un dictado— no tiene deshacer. Eso obliga, por cada
funcionalidad: prueba negativa por requisito, rama propia, revisión antes de la
puerta y riesgos residuales anotados al cerrar.

## Módulos del ciclo que aplican

Pase de lista de `sw-ciclo`, con lo descartado y su razón.

| Módulo | Aplica | Razón |
|---|---|---|
| Requerimientos | Sí | Por funcionalidad, vía `docs/specs/` |
| Arquitectura | Sí | Cascada de motores, red de seguridad, troceo |
| Datos | Sí | Índice SQLite de la bitácora, historial en disco |
| Seguridad de aplicación | Sí | Claves de terceros, audio y texto del usuario |
| Infraestructura | **No** | No hay servidor: todo corre en el Mac del usuario |
| Entornos y CI/CD | Parcial | Sin CI; el publicador (`scripts/release.sh`) hace de puerta con control de calidad y firma |
| Observabilidad | Sí | Registro semanal rotado y baterías de prueba propias |
| Pagos | **No** | No cobra nada |
| Correo | **No** | No envía correo |
| Móvil | **No** | Es una aplicación de escritorio |
| Mantenimiento | Sí | Dependencias de terceros y costos de API |

## Gobernanza de ramas — rama corta y cierre obligatorio

Regla de Alberto, 2026-09-14: *«se me hace muy difícil a mí estar manteniendo dos
ramas… cuando se termine una rama se cierre completamente»*. El riesgo es real:
en este repositorio trabajan varias sesiones y a veces más de un agente, así que
una rama que sobrevive a la sesión diverge y acaba perdiendo trabajo.

- Una rama de spec **nace y muere en la misma sesión de trabajo**. Si no se
  termina, se decide explícitamente: se fusiona lo que esté probado (detrás de un
  ajuste apagado por defecto si hace falta) o se descarta con su razón escrita.
  No se deja abierta «para mañana».
- **Lo instalado siempre sale de `main`.** Mientras una rama está viva, el uso
  diario no depende de ella.
- Antes de fusionar: las seis baterías en verde sobre el paquete construido desde
  la rama, y la spec con su `verificacion.md` al día.
- Al fusionar: se borra la rama en local y en remoto, y el hito lo deja escrito.

## Especificaciones

<!-- sdd:indice:inicio -->
| NNN | Título | Estado | Nivel | Tipo | Fecha | Aprobada por | Modifica | Fase |
|---|---|---|---|---|---|---|---|---|
| 001 | Memoria del dictado largo | Aprobada | X | funcionalidad | 2026-09-14 | Alberto — 2026-09-14 — «acepto, como te digo, la recomendación de X, pero bajo esos términos y cuidados que te digo» | ninguna | Lista para plan |
| 002 | Corrección: Cancelar un dictado no puede borrar el audio | Borrador | X | correccion | 2026-09-14 | PENDIENTE | ninguna | Especificando |
| 003 | Resumen de la bitácora por correo | Borrador | X | funcionalidad | 2026-09-14 | PENDIENTE | ninguna | Especificando |

<!-- sdd:indice:fin -->

## Próximo

1. **Spec 001 — Memoria del dictado largo.** Aprobada; toca el grabador, así que
   va con la gobernanza de rama corta. Objetivo: seis horas de dictado sin que la
   memoria dependa de la duración.
2. **Spec 002 — Cancelar un dictado no puede borrar el audio.** Defecto
   confirmado: Escape es un atajo global y `discard()` elimina el archivo. En
   especificación.
3. **Spec 003 — Resumen de la bitácora por correo.** En especificación.

## Hecho recientemente

- **0.59.0** — Troceo adaptativo: se descubre el techo de cada motor al chocar
  con él, se parte con solape y se cose; se aprende, y se olvida cuando la
  medida se contradice. Corregido un cuelgue de conexión que afectaba a los doce
  motores de nube.
- **0.58.0** — Cronómetro de grabación y banco de pruebas con dictados
  sintéticos.
- **0.57.x** — Fish Audio como proveedor de voz y transcripción.
- **0.56.x** — Rebautizo a BtoDicta con asistente de mudanza.
- **0.54.0** — Red de seguridad del dictado: detección y reparación quirúrgica de
  los tramos que el motor en vivo se salta o se deja.

## Pendientes conocidos

- `docs/PENDIENTES-0.50.1.md`, `-0.51.1.md`, `-0.53.0.md`.
- Los Atajos de macOS apuntan al nombre anterior; hay que regenerarlos a mano.
- Notarización de Apple: decisión pendiente.
