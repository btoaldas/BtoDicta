# Spec 013 — Bitácora solo de grabaciones

- Estado: Borrador — pendiente de aprobación
- Tipo: funcionalidad
- Nivel: X (heredado del ROADMAP)
- Fecha: 2026-10-06
- Modifica: ninguna; complementa la captura de bitácora existente
- Aprobada por: PENDIENTE
- Rama de implementación propuesta: `codex/013-bitacora-solo-grabaciones`

## 1. Problema y propósito

La bitácora consume proveedores aun sin dictar. «Solo al dictar» no limita todas
las fuentes. La nueva opción recoge material únicamente durante grabaciones
explícitas del notch y conserva los resúmenes habituales.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Usuario | Persona que dicta y utiliza la bitácora | Controla cuándo recoge información y reduce trabajo de IA ambiental |

## 3. Alcance

Incluye ajuste, fuentes habilitadas —también sistema y navegador—, pendientes e
integración con dictado. Conserva proveedores, prompts, horarios, formatos,
historial y pendientes. El oyente independiente de activación por voz queda fuera.

## 4. Requerimientos funcionales

### RF-01 — Opción global en configuración

- Actor: usuario.
- Acción: marca «Activar solo de grabaciones», debajo de «Activar la bitácora».
- Resultado: conserva el modo al reiniciar; el maestro apagado prevalece.
- Medida: 1 preferencia, inicialmente desmarcada; desmarcarla recupera el modo anterior.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el maestro activo y la opción marcada
  - Cuando se reinicia la aplicación
  - Entonces conserva el modo; con el maestro apagado no captura.

### RF-02 — Reposo sin captura ambiental

- Actor: usuario.
- Acción: deja la aplicación abierta sin grabar con la opción marcada.
- Resultado: no escucha micrófono ni sistema, ni recoge pantalla, navegador u OCR ambiental.
- Medida: 0 capturas, segmentos o solicitudes STT ambientales nuevos en 60 s de reposo.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el modo solo de grabaciones y ninguna grabación activa
  - Cuando transcurren 60 s, incluido después de reiniciar
  - Entonces los contadores de captura e ingreso ambiental no aumentan.

### RF-03 — Contexto durante la grabación explícita

- Actor: usuario.
- Acción: graba desde el notch, su atajo o tecla de dictado.
- Resultado: utiliza ese audio y recoge contexto habilitado mientras graba; detener, cancelar o pausar cierra la captura; reanudar la abre.
- Medida: contexto desde el comienzo, incluso en grabaciones cortas; 0 material nuevo capturado fuera de la ventana autorizada, aunque se procese después.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el modo nuevo y fuentes habilitadas
  - Cuando una grabación comienza correctamente y luego se detiene
  - Entonces recoge contexto durante ella y puede procesarlo después de detenerse.

### RF-04 — Reutilizar audio y transcripción del dictado

- Actor: usuario.
- Acción: termina un dictado que obtiene transcripción.
- Resultado: incorpora audio y texto existentes sin transcribirlos otra vez.
- Medida: 0 solicitudes STT de bitácora adicionales para dictados ya transcritos; conserva originales.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado un dictado transcrito correctamente
  - Cuando la bitácora lo incorpora
  - Entonces no repite STT; un fallo no marca pendientes como resueltos.

### RF-05 — Conservar resúmenes y acceso al historial

- Actor: usuario.
- Acción: consulta historial o genera resúmenes manuales y programados.
- Resultado: conserva búsqueda, prompts, formatos, horarios y envíos configurados.
- Medida: 0 registros históricos modificados; mismo flujo con menos captura nueva.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado historial previo y material de nuevas grabaciones
  - Cuando cambia el modo y solicita un resumen
  - Entonces conserva historial y resúmenes, incluso después de detener la grabación.

### RF-06 — Transiciones y pendientes sin gasto ambiental nuevo

- Actor: usuario.
- Acción: cambia de modo, reinicia, pausa, cancela o encuentra un fallo.
- Resultado: conserva pendientes ambientales sin procesarlos automáticamente; ningún reintento reactiva su captura. Los resultados conservan procedencia y ventana de captura.
- Medida: 0 nuevas solicitudes automáticas del backlog ambiental; 0 ingresos tardíos ajenos a una grabación autorizada.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado backlog ambiental y una grabación que termina o falla
  - Cuando vencen pausas/reintentos o llegan resultados tardíos
  - Entonces permanece en reposo; completa grabaciones autorizadas y conserva el backlog. Un pedido ambiental ya enviado puede guardar su respuesta, sin encadenar pedidos nuevos.

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Integridad | 0 audios, textos o pendientes eliminados por cambiar de modo | Inventario y huellas antes/después |
| RNF-02 | Compatibilidad | 0 regresiones en dictado, pausa, reunión y modo continuo | Baterías existentes y pruebas negativas por RF |
| RNF-03 | Privacidad | 0 secretos o datos personales reales en pruebas, commits y evidencia pública | Revisión del diff y ejemplos genéricos |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| Falla el inicio del micrófono | No abre captura de contexto | RF-02, RF-03 |
| Se detiene antes de terminar OCR o pulido | Solo completa el material capturado durante esa grabación | RF-03, RF-06 |
| Comienza otro dictado antes de acabar el anterior | Cada resultado conserva la autorización de su grabación | RF-04, RF-06 |
| Maestro apagado, pausa o modo reunión | Se conservan sus restricciones actuales | RF-01, RF-06 |

## 7. Datos y cumplimiento

Reduce la recogida actual de voz, pantalla y texto. Conserva permisos, exclusiones,
retención y destinatarios. No añade tratamiento externo, cobros ni facturación.
La auditoría de cuentas privadas se documenta fuera del repositorio.

## 8. Supuestos y dependencias

«Grabación» comprende los controles habituales del notch, no importaciones ni API
local. Procesamiento posterior y resúmenes pueden consumir IA. No se promete un
porcentaje fijo de ahorro.

## 9. Decisiones y aclaraciones

### Sesión 2026-10-06

- Pedido: opción «Activar solo de grabaciones»; conservar continuo, contexto durante dictado y resúmenes.
- Propuesta por aprobar: inicialmente desmarcada, atajos equivalentes al botón y pendientes ambientales conservados sin proceso automático.
- Diagnóstico privado separado; no atribuir todo el gasto de la cuenta a esta aplicación.
- Pendientes: aprobación de spec, plan y tareas; implementación y activación en instalación viva.
