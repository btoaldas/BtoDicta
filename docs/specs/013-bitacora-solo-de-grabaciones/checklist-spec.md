# Revisión de calidad — Spec 013

Fecha: 2026-10-06. Revisión del requerimiento; no verificación de la funcionalidad.

- [x] CHK01 Los 8 RF tienen actor, acción, resultado y medida.
- [x] CHK02 Los criterios distinguen captura, autorización y procesamiento posterior.
- [x] CHK03 Los 3 RNF tienen cifras observables.
- [x] CHK04 Se conservan resumen/proveedores; el oyente de voz se suspende por confirmación expresa, sin perder su preferencia.
- [x] CHK05 Se contemplan fallo de inicio, grabación corta, cancelación, pausa, concurrencia, maestro apagado, entregas tardías, actualizaciones y elecciones posteriores.
- [x] CHK06 Se contrastó con MANIFIESTO: originales conservados, continuidad del dictado y sin dependencias nuevas para grabar.
- [x] CHK07 Los RF describen comportamiento; las observaciones sobre componentes están en research.md.
- [x] CHK08 Hay datos personales como antes; se reduce recogida y se conservan permisos/exclusiones/destinatarios. No se incorporan cobros o facturación.
- [x] CHK09 No quedan marcadores de decisión dentro de los RF; la aprobación se registró expresamente después de la revisión.
- [x] CHK10 Spec de 8 RF; investigación y revisión separadas.

Evidencia: `verificar-spec.py spec.md` → 8 RF, 3 RNF, 0 pendientes de decisión,
0 errores y 0 avisos. Revisión independiente de requisitos: corregidas las
ambigüedades de pausa, ventana de captura y respuesta ambiental ya solicitada.
Corrección posterior: default activado al instalar/actualizar y suspensión del
oyente de voz; aplicación automática por ausencia sin reescritura de ajustes.

Al terminar la revisión, la puerta de plan estaba cerrada. Alberto aprobó después continuar con plan, tareas e implementación («si dale»); al cierre se verificó la puerta de hito abierta con 8 tareas respaldadas. Ver evidencia.md y verificacion.md.
