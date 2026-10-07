# Evidencia — Spec 013

- Fecha: 2026-10-06
- Entorno: perfil temporal aislado, audio sintético y proveedores simulados; código de main.

## Resultado verificado

| Comprobación | Resultado |
|---|---|
| Suite Swift completa | 114 pruebas, 0 fallos; incluye 32 nuevas |
| Extensión | 63 comprobaciones, 0 fallos |
| Reposo de capturadores real | 61 s: 0 solicitudes, 0 muestras, 0 bytes y 0 recursos abiertos en micrófono, sistema y pantalla |
| Oyente de voz | Sin micrófono incluso forzando habilitado y con maestro apagado |
| Historial integrado | Escritor real + SQLite + WAV sintético: conserva bytes/texto y no deja trabajo STT duplicado |
| Migración heredada | Repetida 3 veces; conserva filas, FTS, secuencias y huellas de originales |
| Backlog | Filtro de sesión/canal antes de LIMIT; manual explícito conserva acceso a lo ambiental |
| Reintentos y fragmentos | Cortan nuevos envíos y conservan respuestas/parciales recibidos, con proveedor simulado |
| Compilación debug | Correcta, con advertencias existentes del proyecto |
| Compilación optimizada | Correcta en el estado final (129,71 s); pasada anterior también correcta |
| QA detección de voz y memoria en disco | Correctas |
| Formato y SDD | diff sin errores; 8 RF, 3 RNF, 8 tareas sin errores ni avisos |

## Cómo reproducir

```sh
perfil_pruebas="$(mktemp -d)"
BTODICTA_DIR="$perfil_pruebas" swift test
node extension/pruebas/correr.mjs
swift build -c release
perfil_reposo="$(mktemp -d)"
BTODICTA_DIR="$perfil_reposo" BTODICTA_BITACORAREPOSOTEST=1 .build/debug/BtoDicta
python3 scripts/qa-deteccion-voz.py
python3 scripts/qa-memoria-en-disco.py Sources/BtoDicta
python3 /ruta/al/skill/sdd/scripts/puerta.py docs/specs/013-bitacora-solo-de-grabaciones implementar
```

Los perfiles temporales se conservan para inspección. El arnés de reposo se ejecuta antes del arranque normal, con planificador/procesado desactivados, maestro activo durante el minuto completo, fuentes habilitadas y llamadas repetidas de arranque/rearme. Incluye dos reconfiguraciones; al final prueba además maestro apagado. No llama proveedores ni abre capturadores.

## Revisión de segundo ángulo

Revisión independiente de política, coordinador, HistoryWriter, voz, OCR, lotes y capturadores. Se encontraron y corrigieron: adopción de WAV completo tras pausa, TXT parcial tratado como final, colisiones de nombres dentro del mismo segundo y respuesta truncada que intentaba abrir nuevos fragmentos tras cambiar autorización. Pruebas específicas de regresión cubren esos bordes; nombres nuevos conservan hora de huérfanos.

## Desviaciones respecto a la spec

Si la bitácora se pausa/reconfigura dentro de un dictado, su WAV completo queda íntegro en historial y se excluye de la adopción automática para no incluir el intervalo sin permiso. No se fragmenta el original ni se paga STT parcial adicional. Las capturas autorizadas de otras fuentes mantienen sus sesiones.

Una pantalla iniciada dentro de la ventana se descarta si el API todavía no había devuelto la imagen al cerrar. La captura inicial se solicita inmediatamente, pero no se garantiza resultado para grabaciones más cortas que el tiempo del API. La extensión sondea cada 500 ms.

## Límites y control histórico separado

No se ha instalado una app ni publicado una release. Se compilaron los binarios, sin probar captura positiva de hardware/permisos sobre datos personales. La extensión 0.6.0 requiere recarga: la API nueva bloquea ingreso antiguo, mientras la guarda previa al DOM necesita el guion actualizado.

El script existente de calidad texto frente a OCR leyó únicamente datos históricos y no aprobó su ratio de aporte frente al umbral; encontró 0 páginas con texto esperando OCR. No se usa ese indicador de contenido antiguo como prueba de regresión del nuevo modo. Su script, umbral y datos se conservaron. No se ejecutó la suite de paquete completa, que incluye grabación/permisos y controles con datos reales; sí los controles aislados anteriores.

La auditoría de ElevenLabs y sus cifras de cuenta permanecen privadas; una clave compartida no permite atribuir todo el gasto al proyecto. El modo reduce captura futura y congela STT ambiental automático, sin prometer una cantidad de ahorro aún no observada.
