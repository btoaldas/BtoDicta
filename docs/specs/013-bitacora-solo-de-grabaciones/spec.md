# Spec 013 — Bitácora solo de grabaciones

- Estado: Implementada
- Tipo: funcionalidad
- Nivel: X (heredado del ROADMAP)
- Fecha: 2026-10-06
- Modifica: ninguna; complementa la captura de bitácora existente
- Aprobada por: Alberto, 2026-10-06 — «si dale», en respuesta a continuar con plan, tareas e implementación
- Rama de implementación: `main`, excepción del módulo bitácora en AGENTS.md

## 1. Problema y propósito

La bitácora consume proveedores aun sin dictar. «Solo al dictar» no limita todas
las fuentes. La nueva opción recoge material únicamente durante grabaciones
explícitas del notch y conserva los resúmenes habituales.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Usuario | Persona que dicta y utiliza la bitácora | Controla cuándo recoge información y reduce trabajo de IA ambiental |

## 3. Alcance

Incluye ajuste, fuentes habilitadas —micrófono/ambiente, sistema, pantallas, OCR
y navegador—, pendientes, dictado y suspensión del oyente de activación por voz.
Conserva permisos, exclusiones, proveedores, prompts, horarios, formatos e historial.

## 4. Requerimientos funcionales

### RF-01 — Opción global en configuración

- Actor: usuario.
- Acción: encuentra «Activar solo de grabaciones» marcada, debajo de «Activar la bitácora», y puede desmarcarla.
- Resultado: conserva el modo al reiniciar; el maestro apagado impide generar bitácora. La opción sigue editable y explica que también suspende activación por voz.
- Medida: 1 preferencia, activada por defecto; desmarcarla recupera el modo continuo.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el maestro activo y la opción marcada
  - Cuando se reinicia la aplicación
  - Entonces conserva el modo; con el maestro apagado no captura.

### RF-02 — Reposo sin captura ambiental

- Actor: usuario.
- Acción: deja la aplicación abierta sin grabar con la opción marcada.
- Resultado: no mantiene captura de micrófono/ambiente, sistema, pantalla, navegador ni OCR ambiental, ni oyentes pasivos de voz.
- Medida: 0 capturas, segmentos o solicitudes STT ambientales nuevos en 60 s de reposo.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el modo solo de grabaciones y ninguna grabación activa
  - Cuando transcurren 60 s, incluido después de reiniciar
  - Entonces los contadores de captura e ingreso ambiental no aumentan.

### RF-03 — Contexto durante la grabación explícita

- Actor: usuario.
- Acción: graba desde el notch, su atajo o tecla de dictado.
- Resultado: utiliza ese audio —voz propia y ambiente— y las fuentes habilitadas de sistema, pantalla, OCR y navegador mientras graba. Detener, cancelar o pausar cierra la captura; reanudar la abre.
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

### RF-07 — Aplicación automática al actualizar

- Actor: usuario nuevo o existente.
- Acción: instala o actualiza sin tener la nueva preferencia.
- Resultado: adopta automáticamente solo de grabaciones antes de iniciar capturadores; conserva el maestro y los demás ajustes.
- Medida: valor predeterminado true; 0 activaciones del maestro apagado y 0 cambios forzados de elecciones posteriores.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado una instalación antigua, incluso con bitácora apagada
  - Cuando actualiza y después elige continuo
  - Entonces primero obtiene solo de grabaciones y conserva el maestro; tras elegir continuo, reinicios y actualizaciones respetan su elección.

### RF-08 — Activación por voz suspendida en este modo

- Actor: usuario con activación del asistente por voz configurada.
- Acción: utiliza solo de grabaciones.
- Resultado: el oyente permanece suspendido; inicia dictados desde notch o teclado, sin perder la preferencia de voz.
- Medida: 0 oyentes pasivos en reposo, incluso con maestro de bitácora apagado.
- Prioridad: P1.
- Criterio de aceptación:
  - Dado el oyente configurado y solo de grabaciones marcado
  - Cuando permanece en reposo o vuelve al modo continuo
  - Entonces primero no escucha; al volver a continuo recupera la activación por voz según su preferencia conservada.

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
| Actualización sin preferencia nueva | Solo de grabaciones activo; maestro conservado | RF-07 |
| Usuario desmarca la opción y vuelve a actualizar | Se conserva continuo | RF-07 |
| Oyente de voz configurado, bitácora apagada y modo nuevo marcado | No escucha en reposo; dictado manual disponible | RF-08 |

## 7. Datos y cumplimiento

Reduce la recogida actual de voz, pantalla y texto. Conserva permisos, exclusiones,
retención y destinatarios. No añade tratamiento externo, cobros ni facturación.
La auditoría de cuentas privadas se documenta fuera del repositorio.

## 8. Supuestos y dependencias

«Grabación» comprende dictado desde notch o teclado, no importaciones ni API local.
Los selectores existentes determinan qué fuentes se recogen; no se encienden
fuentes desmarcadas ni se eluden permisos/exclusiones. Procesamiento posterior y
resúmenes pueden consumir IA; no se promete un ahorro porcentual fijo.

## 9. Decisiones y aclaraciones

### Sesión 2026-10-06

- Pedido: opción «Activar solo de grabaciones»; conservar continuo, contexto durante dictado y resúmenes.
- Corrección confirmada: activada por defecto para instalaciones nuevas y existentes al actualizar; maestro apagado conservado. Sustituye la propuesta inicial de valor desmarcado.
- Confirmación sobre el oyente independiente: «Sí: también pausar la activación por voz; usar notch o teclado».
- Propuesta técnica: valor true por ausencia de preferencia; la elección explícita posterior false se conserva. Sin reescritura de configuración ni imposición repetida.
- Diagnóstico privado separado; no atribuir todo el gasto de la cuenta a esta aplicación.
- Cierre: plan, tareas e implementación autorizados por «si dale»; código publicado en 476a469, verificación y hito registrados. Instalación y distribución quedan fuera de este hito.

## 10. Cierre de implementación

[Verificación por requisito](verificacion.md), [evidencia y límites](evidencia.md) y [hito](../../hitos/2026-10-06-bitacora-solo-de-grabaciones.md). Puerta de hito abierta antes de registrar este estado Implementada; 8 tareas con evidencia.
