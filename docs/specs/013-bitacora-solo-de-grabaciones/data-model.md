# Modelo de datos

Preferencia `continuo_solo_grabaciones`: booleano; ausencia = true. El maestro y los demás ajustes no migran.

Columna `sesion` nullable en audio y pantalla. NULL o vacío representa captura ambiental heredada. UUID no vacío representa ventana autorizada; no se actualizan filas históricas. Pendientes automáticos del modo nuevo seleccionan sesiones antes de LIMIT. Se conservan originales, estados de procesamiento y FTS.

Una ventana en memoria tiene sesión, inicio, fin opcional y generación. El historial conserva la sesión original para incorporar dictados tardíos. Cerrar invalida captura nueva, sin invalidar la adopción de lo capturado.

Las ventanas interrumpidas conservan sus intervalos válidos para capturas ya hechas, pero no autorizan la adopción del WAV entero que atraviesa una pausa. No se pierden originales: permanecen en el historial. La transcripción final vacía no resuelve una fila aunque exista un texto parcial.
