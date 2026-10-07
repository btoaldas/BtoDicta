# Investigación 013 — alcance real de la captura

Fecha: 2026-10-06. Solo inspección; no demuestra una implementación de la spec.

## Comportamiento actual comprobado

«Solo al dictar» pertenece al selector de audio del micrófono. No es una política
global: el coordinador inicia pantalla y audio del sistema por caminos separados.
La API de navegador comprueba que la bitácora esté activa, sin exigir grabación.

El dictado ya tiene una vía útil para ahorrar: `HistoryWriter.finish()` entrega
el audio a `ContinuoAudio.adoptar()`, que reutiliza su texto y lo marca procesado.
El modo nuevo debe conservar esa propiedad, no crear otro transcriptor de dictados.

| Responsabilidad | Fuente actual | Observación para el futuro plan |
|---|---|---|
| Preferencias e interfaz | `Config.swift`, `ContinuoView.swift` | El maestro gobierna captura de bitácora; el modo sigue editable y suspende el oyente incluso con maestro apagado |
| Coordinación | `ContinuoBitacora.swift` | Separar preparación/planificación de captura autorizada |
| Inicio y fin del dictado | `AppDelegate.swift` | Abrir ventana solo tras iniciar realmente; cerrarla al detener, cancelar, pausar o fallar |
| Audio del notch | `HistoryWriter.swift`, `ContinuoAudio.swift` | Conservar autorización de cada grabación hasta su entrega tardía |
| Micrófono continuo | `ContinuoAudio.swift` | Revisar entradas profundas, reanudaciones y reintentos |
| Pantalla | `ContinuoPantalla.swift` | Proteger capturas en vuelo; atender grabaciones cortas |
| Audio del sistema | `ContinuoAudioSistema.swift` | Aplicar la misma ventana y proteger montajes tardíos |
| Navegador | `ApiLocal.swift`, `extension/src/contenido.js`, `extension/src/fondo.js` | Evitar captura/lectura de bitácora en reposo, no solo su persistencia |
| Pendientes y resúmenes | `ContinuoIndice.swift`, `ContinuoLote.swift`, `ContinuoRutinas.swift`, `ContinuoResumen.swift` | Conservar material previo, sin drenar audio ambiental automáticamente en el modo nuevo |

Las rutas de la aplicación de esta lista se resuelven bajo `Sources/BtoDicta/`.

## Riesgos que debe resolver el plan aprobado

- Una captura iniciada dentro de una grabación puede terminar después: su
  autorización depende del instante y procedencia de captura, no de la hora de
  llegada del OCR. Una captura iniciada fuera no se autoriza por llegar durante
  otro dictado.
- La pantalla no tiene procedencia de sesión persistente como tal; el audio
  distingue `continuo`, `dictado` y `sistema`. El plan debe justificar cómo
  distinguir material autorizado de backlog ambiental tras reiniciar sin borrar
  ni reclasificar los originales de forma incorrecta.
- Una respuesta ambiental ya solicitada antes del cambio puede conservarse. El
  cambio no recupera créditos gastados ni debe encadenar solicitudes nuevas.
- La cesión del micrófono nunca puede añadir una espera indefinida al dictado.
- Pausa, exclusiones y modo reunión mantienen sus frenos actuales. Aunque el
  oyente de activación por voz sea independiente, la corrección del requerimiento
  lo incluye expresamente: debe quedar suspendido mientras esté marcado solo de
  grabaciones, conservando su preferencia para el modo continuo. Esto también
  aplica con maestro de bitácora apagado: el dictado manual sigue disponible.

## Verificación propuesta, todavía no ejecutada

Usar configuración y base aisladas, proveedores simulados y contadores de
capturas/solicitudes; no generar gasto real ni grabar información personal en QA.

Cubrir reposo de 60 s con todas las fuentes habilitadas, inicio fallido, dictado
corto, parada/cancelación, pausa/reanudación, maestro apagado durante dictado,
captura en vuelo, dos dictados con entregas cruzadas y reinicio con backlog
ambiental. Verificar por separado la captura y el procesamiento posterior.

Añadir fixtures de configuración nueva, anterior con maestro ON/OFF, preferencia
nueva explícita true/false y dos actualizaciones/reinicios después de elegir
continuo. Comprobar suspensión/reintentos del oyente de voz y recuperación de su
preferencia al desmarcar. Estas pruebas están propuestas, todavía no ejecutadas.

Reutilizar las baterías de `scripts/qa-paquete.sh` y
`extension/pruebas/correr.mjs`. Antes de ejecutar QA, ampliar o comprobar su
aislamiento: la huella de configuración actual de `qa-paquete.sh` cubre claves
`bitacora_`, pero no todas las `continuo_` implicadas en esta spec.

## Diagnóstico de proveedores

El saldo de cuenta, los créditos por producto y las métricas locales son medidas
distintas. Un registro de gasto del dictado no contabiliza por sí solo toda la
bitácora. Si varias aplicaciones comparten clave, el desglose por clave tampoco
las distingue. La auditoría debe separar ciclo de facturación y mes natural,
anotar la zona horaria y declarar las limitaciones de atribución.

Las cifras y credenciales de una cuenta concreta no forman parte del repositorio.

## Corrección de valor predeterminado y actualización

La opción debe estar activa tanto en instalación nueva como al actualizar una
instalación anterior que no tenga la preferencia. No debe activar el maestro ni
forzar true en cada actualización después de que el usuario haya elegido false.

Patrón existente comprobado: `Config.json()` lee/cachea el diccionario sin
inyectar defaults (`Config.swift:45–52`); los getters aportan sus valores por
ausencia. `Config.set()` conserva booleanos explícitos y escribe atómicamente
bajo candado (`Config.swift:879–901`). El maestro conserva default false
(`Config.swift:1047`). Por tanto basta un getter nuevo con default true por
ausencia; una elección explícita false permanece false en futuras actualizaciones.

Se descarta un migrador que reescriba configuración o fuerce true por versión:
no aporta valor a este cambio, añade fallos de persistencia y podría deshacer una
elección posterior. La prueba debe comprobar también huellas de configuración:
leer el nuevo default no debe modificar el archivo.

Los selectores actuales siguen definiendo qué fuentes se usan; la política nueva
define cuándo. Audio del sistema es opcional de fábrica, mientras pantalla/OCR
están habilitados de fábrica: no confundir default del modo con habilitar todos
los canales ni solicitar permisos silenciosamente.

La grabación de vídeo de `CapturaMac` es una acción manual independiente y no
alimenta actualmente la bitácora. Integrarla como origen nuevo no forma parte de
esta spec de dictado; se conserva su funcionamiento actual.
