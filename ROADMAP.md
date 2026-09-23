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
| 001 | Memoria del dictado largo | Implementada (0.63.4 y 0.63.5) | X | funcionalidad | 2026-09-14 | Alberto — 2026-09-14 — «acepto, como te digo, la recomendación de X, pero bajo esos términos y cuidados que te digo» | ninguna | Especificando |
| 002 | Corrección: Cancelar un dictado no puede borrar el audio | Implementada (0.59.1 y 0.59.2) | X | correccion | 2026-09-14 | Alberto — 2026-09-14 — «vamos de los tres [pendientes] el que sea más rápido»; RF-01 era «de ley» | ninguna | Especificando |
| 003 | Resumen de la bitácora por correo | Implementada (0.61.0 y 0.62.0) | X | funcionalidad | 2026-09-14 | Alberto — 2026-09-14 — «hagámoslas todas bajo goal, una por una… puedes utilizar un correo de eztic.ec para probarlo» | ninguna | Especificando |
| 004 | Panel de salud y aviso de saldo | Implementada (0.63.0) | X | funcionalidad | 2026-09-15 | Alberto — 2026-09-15 — «estas ideas me gustan: aviso cuando un proveedor se queda sin saldo… un panel de salud» | ninguna | Especificando |
| 005 | API de transcripción para servicios externos | Implementada (0.65.0) | X | funcionalidad | 2026-09-18 | Alberto — 2026-09-19 — «continúa con todo bajo goal y loop… ya no necesito que vuelvas a pararte hasta que termines absolutamente todo» | ninguna | Especificando |
| 006 | Extensión de navegador para la bitácora | Aprobada | X | funcionalidad | 2026-09-20 | Alberto — 2026-09-20 — «aprobado, dale con el plan» | ninguna | Implementando: T26 de T27 |
| 007 | Asistente de exclusiones con semillas y modo de trabajo | Aprobada | P | funcionalidad | 2026-09-21 | Alberto — 2026-09-21 — «si dale» (a «¿Apruebo la spec y paso al plan?») | ninguna | Implementando: T07 de T20 |
| 008 | El texto que se guarda es el que se está leyendo | Aprobada | X | cambio | 2026-09-21 | Alberto — 2026-09-21 — «resuelve aprobado te doy» | 006 | Lista para tareas |
| 009 | Buscar por palabras en la bitácora | Aprobada | X | funcionalidad | 2026-09-21 | Alberto — 2026-09-21 — «resuelve aprobado te doy» | ninguna | Lista para tareas |
| 010 | Controles rápidos desde el icono de la barra | Implementada | P | funcionalidad | 2026-09-22 | Alberto — 2026-09-22 — «si» (a «¿Apruebo la spec y paso al plan?») | ninguna | Especificando |

<!-- sdd:indice:fin -->

## Próximo

1. **Spec 001, segunda etapa.** Los motores reciben el audio como datos y no
   como archivo, así que al transcribir se sigue haciendo una copia completa.
   Pasarlos a transmitir desde disco toca la interfaz de los doce.
2. **Correo en HTML con logotipo.** La primera versión va en texto plano, que es
   lo que no cae en spam; queda para cuando el canal esté rodado.
3. Pendientes heredados: `docs/PENDIENTES-0.50.1.md`, `-0.51.1.md`, `-0.53.0.md`.

## Hecho recientemente

- **0.61.0** — El resumen de la bitácora llega por correo, consolidado con IA,
  desde la cuenta del propio usuario. La prueba de envío dice por qué falla.
- **0.60.0** — El dictado deja de vivir en la memoria: seis horas simuladas, 0 MB
  de subida.
- **0.59.1-0.59.3** — Cancelar un dictado ya no lo borra, un Escape suelto ya no
  lo corta, y sus ajustes salen en la interfaz.
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
