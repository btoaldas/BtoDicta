# Spec 004 — Panel de salud y aviso de saldo

- Estado: Implementada (0.63.0)
- Tipo: funcionalidad
- Nivel: X
- Fecha: 2026-09-15
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-15 — «estas ideas me gustan: aviso cuando un proveedor se queda sin saldo… un panel de salud»
- Rama: `main` (no toca el grabador ni el camino del dictado; la gobernanza de rama corta se reserva para lo que sí)

## 1. Problema y propósito

Todo lo que hace falta para saber si BtoDicta está sano **ya se mide** —tiempos
por motor, cuarentenas, techos aprendidos, cola de la bitácora—, pero solo existe
en el registro. Para enterarse hay que abrir un archivo de texto y saber qué
buscar; en un solo día de trabajo hubo que hacerlo cinco veces. Y el saldo de los
proveedores no se mira nunca: uno se entera de que se acabó cuando falla a mitad
de un dictado.

Cuando esto esté hecho, esas dos cosas se ven de un vistazo y el saldo bajo avisa
antes de estropear un dictado.

## 2. Actores

| Actor | Quién es | Qué gana |
|---|---|---|
| Quien usa BtoDicta | Alberto y cualquier usuario | Ve de un vistazo si algo va mal, sin leer registros |
| Quien paga las API | El mismo | Se entera de que se le acaba el saldo antes de quedarse sin voz o sin transcripción |

## 3. Alcance

### Incluye

- Una sección **Salud** en la ventana de configuración.
- Saldo de los proveedores que lo exponen, con su unidad real.
- Aviso cuando un saldo baja del umbral que fije el usuario.
- Lo ya medido: cuarentenas activas, techos de tamaño aprendidos, cola de la
  bitácora y tiempos recientes por motor.

### No incluye (con razón)

- Estimar el saldo de los que no lo exponen (OpenAI, Groq, Anthropic no publican
  un punto de consulta): se dice que no se puede saber, en vez de inventarlo.
- Gráficas históricas: esto es un tablero de estado, no una herramienta de
  análisis. Para el histórico está el registro.
- Cobrar, recargar o tocar la cuenta del proveedor.

## 4. Requerimientos funcionales

### RF-01 — Ver el estado sin leer el registro

- Actor: quien usa BtoDicta
- Acción: abre la sección Salud
- Resultado: ve cuarentenas activas, techos aprendidos, cola de la bitácora y
  tiempos recientes por motor
- Medida: cada dato visible corresponde a algo que hoy solo está en el registro
- Prioridad: P1
- Criterio de aceptación:
  - Dado un proveedor en cuarentena
  - Cuando se abre la sección Salud
  - Entonces aparece con su motivo y cuánto le queda

### RF-02 — Saldo de los proveedores que lo exponen

- Actor: quien paga las API
- Acción: abre la sección Salud
- Resultado: ve el saldo de cada proveedor consultable, en su unidad
- Medida: al menos ElevenLabs (caracteres), Fish Audio y DeepSeek (dinero); y los demás con prueba de vida
- Prioridad: P1
- Criterio de aceptación:
  - Dada una clave válida de esos proveedores
  - Cuando se abre la sección
  - Entonces cada uno muestra su saldo y cuándo se consultó

### RF-03 — Avisar antes de quedarse sin saldo

- Actor: quien paga las API
- Acción: sigue trabajando con un proveedor que se está agotando
- Resultado: se le avisa una vez, sin interrumpir el dictado
- Medida: el aviso sale al bajar del umbral y no se repite más de una vez al día
  por proveedor
- Prioridad: P1
- Criterio de aceptación:
  - Dado un proveedor por debajo del umbral
  - Cuando se consulta el saldo
  - Entonces se avisa una vez y queda en el registro

### RF-04 — El umbral lo pone el usuario

- Actor: quien usa BtoDicta
- Acción: ajusta desde qué punto quiere que se le avise
- Resultado: el aviso respeta ese valor
- Medida: cambiar el umbral cambia cuándo avisa
- Prioridad: P2
- Criterio de aceptación:
  - Dado un umbral del 20 %
  - Cuando un proveedor baja del 20 % de su capacidad
  - Entonces avisa; por encima, no

### RF-05 — Consultar el saldo no puede estorbar

- Actor: BtoDicta
- Acción: consulta saldos
- Resultado: lo hace de fondo, sin bloquear ni retrasar un dictado
- Medida: 0 ms añadidos al camino del dictado
- Prioridad: P1
- Criterio de aceptación:
  - Dado un proveedor de saldo que no responde
  - Cuando se está dictando
  - Entonces el dictado no se entera: se muestra «no se pudo consultar»

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Rendimiento | Consultar los saldos tarda menos de 15 s en total y no se repite más de 1 vez cada 30 min | Medición registrada |
| RNF-02 | Seguridad | 0 claves visibles en el panel, en el registro o en la ventana | Revisión |
| RNF-03 | Disponibilidad | Un proveedor que no responde muestra «no se pudo consultar» y los demás se ven igual | Prueba con clave inválida |
| RNF-04 | Usabilidad | Todo el estado cabe en una pantalla sin desplegar nada | Captura |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| El proveedor no expone saldo | Se dice «no publica saldo», no se inventa una estimación | RF-02 |
| La clave del proveedor está mal | Se muestra el motivo, y el resto del panel sigue visible | RNF-03 |
| Sin internet | El panel muestra lo local (cuarentenas, techos, cola) y marca los saldos como no consultables | RF-05 |
| El saldo baja del umbral cinco veces en un día | Se avisa una sola vez ese día por proveedor | RF-03 |
| ElevenLabs agotado (100 % consumido) | Aparece en rojo y avisa | RF-03 |

## 7. Datos y cumplimiento

- Datos que trata: saldos y estado de las API del propio usuario. Ningún dato
  personal nuevo; ninguna clave se muestra ni se registra.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- Ya existen y se miden: `CuarentenaSTT`, `CuarentenaPulido`, los techos de
  `Troceo`, la cola de `ContinuoIndice` y los tiempos que cada motor registra.
- Puntos de consulta verificados el 2026-09-15 con claves reales:
  ElevenLabs `/v1/user/subscription` (caracteres), Fish Audio
  `/wallet/self/api-credit` y DeepSeek `/user/balance` (dinero).
- OpenAI, Groq y Anthropic no publican un punto de consulta de saldo utilizable.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-15

- P: ¿Qué debe salir en el panel? → R: «tiempos por motor, cuarentenas activas,
  techos aprendidos, cola de la bitácora, saldo de API» (decisión del responsable
  del producto, recogiendo la propuesta)
- P: ¿Y el aviso? → R: «aviso cuando un proveedor se queda sin saldo; hoy te
  enteras cuando falla» (decisión del responsable del producto)
- P: ¿Y los proveedores que no exponen saldo? → R: se dice que no lo publican.
  Inventar una estimación sería peor que no decir nada (decisión tomada al
  especificar; reversible)

## 10. Estado de implementación

| RF | Estado | Evidencia |
|---|---|---|
| RF-01 — ver el estado sin leer el registro | **Hecho** | Sección Salud: cuarentenas, techos y cola |
| RF-02 — saldo de los que lo exponen | **Hecho, y ampliado dos veces** | Tras «sería de todas las API, no solo de las tres» y «necesito que te esfuerces en todos»: se probaron uno por uno con claves reales y salieron **seis** con saldo — ElevenLabs (caracteres), Fish, DeepSeek, OpenRouter, Novita (dinero) y Speechmatics (horas) — más **prueba de vida de los 23**. Deepgram y Anthropic tienen consulta pero piden clave de administrador |
| RF-03 — avisar antes de quedarse sin saldo | **Hecho** | Aviso del sistema + registro, una vez al día por proveedor |
| RF-04 — el umbral lo pone el usuario | **Hecho** | `saldo_aviso_fraccion` (15 %) y `saldo_aviso_minimo_usd` (5) |
| RF-05 — consultar no estorba | **Hecho** | Reloj de fondo, caché de 30 min, 0 ms en el camino del dictado |

Medido al implementar: **20 proveedores** probados —15 de IA, 3 de dictado, 2 de
voz—, de los cuales uno estaba caído. Eso no se sabía sin abrir el registro.
