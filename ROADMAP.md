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

## Especificaciones

<!-- sdd:indice:inicio -->
<!-- sdd:indice:fin -->

## Próximo

- **Memoria del dictado largo** — que un dictado de hasta seis horas no dependa
  de tener el audio completo en memoria. En especificación.

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
