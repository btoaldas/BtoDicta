# Tareas 006 — Extensión de navegador para la bitácora

- Estado: Aprobado
- Plan: `plan.md` (Aprobado 2026-09-20)
- Aprobado por: Alberto — 2026-09-20 — «aprobado, dale con las tareas, todo es parametrizable no existen excluyentes base aún»
- Rama: `main`

El orden no es el del valor visible, sino el del riesgo: lo que puede filtrar
algo va primero, con su prueba negativa, antes de que exista quien lo envíe.

**Desviación del orden (2026-09-20, a petición de Alberto):** T15 se adelanta a
T13 y T14 para poder cargar la extensión y probarla en un navegador real antes de
seguir. Las cerraduras (fases A y B) ya estaban hechas, así que adelantar el
empaquetado no salta ninguna protección.

**Ampliación (2026-09-20, tras probarla):** nacen RF-08 y RF-09 con sus tareas
T23 y T24. Y la comprobación en vivo se limita a Edge por decisión de Alberto
—«estamos solo probando con Edge por el momento»—, así que T15 y T16 se dan por
hechas con la carga real en Edge y la construcción verificada para el resto.

## Fase A — La puerta, antes de que nadie llame

- [x] T01 (RF-01, RNF-01) Punto de entrada `POST /navegador` en la API local, con el token, el tope de cuerpo y el límite de peticiones que ya existen — `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: `curl` sin token devuelve 401 y con token válido devuelve 200
  - Evidencia (2026-09-20): sin token 401 · token falso 401 · válido `{"audibles":1,"recibido":2}`
- [x] T02 (RNF-01) Batería negativa del punto nuevo: sin token, token equivocado, cuerpo desmedido, JSON mal formado y llamada desde una interfaz que no es loopback — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: las cinco rechazadas, cada una con su motivo en una línea
  - Evidencia (2026-09-20): sin token 401 · token falso 401 · JSON inválido 400 · informe vacío 400 con motivo literal · cuerpo de 1,6 MB **413** · desde la IP de la red, sin respuesta. La primera medida del tope no valía —el generador falló y mandó basura—, se rehízo con 1,6 MB reales
- [x] T03 (RF-01) Modelo de lo que el navegador reporta: pestaña activa, pestañas audibles, y de dónde viene — `Sources/BtoDicta/EstadoNavegador.swift` — Evidencia esperada: prueba que construye el estado desde un JSON de ejemplo y lo lee de vuelta sin pérdida
  - Evidencia (2026-09-20): `BTODICTA_NAVEGADORTEST=1` → 9 comprobaciones verdes, incluidas 3 de rechazo de informes incompletos y 2 de caducidad
- [x] T04 (RF-04) Con el punto de entrada sin usar, nada cambia: `qa-paquete.sh` sigue pasando igual — `scripts/qa-paquete.sh` — Evidencia esperada: 22 pruebas verdes, las mismas que antes de esta spec
  - Evidencia (2026-09-20): `qa-paquete.sh` → **23 pruebas, 0 fallos**. Las 22 anteriores siguen verdes y la nueva es la del informe del navegador; sin extensión instalada nada cambia de comportamiento

## Fase B — Que la extensión no vea de más

- [x] T05 (RNF-03) Extracción de texto que EXCLUYE `input`, `textarea` y `[contenteditable]`, sin opción de desactivarlo — `extension/src/texto.js` — Evidencia esperada: sobre una página con formulario, el texto extraído no contiene ninguno de los valores escritos
  - Evidencia (2026-09-20): se leen «Acceso al sistema», «Usuario» y «Contraseña» (son contenido) y NO aparecen ni el usuario ni la clave tecleados. También quedan fuera las áreas `contenteditable` —un editor de correo es un campo disfrazado— y lo marcado `aria-hidden`
- [x] T06 (RNF-03) Prueba negativa de T05 con un formulario de acceso real (usuario y contraseña de prueba) — `extension/pruebas/formulario.html`, `extension/pruebas/correr.mjs` — Evidencia esperada: 0 coincidencias de los 2 valores en el cuerpo que se enviaría
  - Evidencia (2026-09-20): 0 coincidencias. Y probada EN LAS DOS DIRECCIONES: al retirar la exclusión de campos, la prueba da rojo en las 2 comprobaciones de secreto; al restaurarla, verde
- [x] T07 (RF-05) Lista de dominios excluidos, VACÍA de fábrica y editable desde la propia extensión — `extension/src/exclusiones.js`, `extension/src/opciones.html` — Evidencia esperada: añadir un dominio y comprobar que deja de reportarse en menos de dos clics
  - Evidencia (2026-09-20): lista VACÍA de fábrica. Pantalla propia con un campo y un botón —Enter también añade, un clic menos—. Excluir un dominio alcanza a sus subdominios: enumerarlos uno a uno haría la lista inútil
- [x] T08 (RF-05) Prueba negativa de T07: con el dominio excluido, 0 envíos de texto y 0 de captura — `extension/pruebas/correr.mjs` — Evidencia esperada: el registro de envíos no contiene ni una entrada de ese dominio
  - Evidencia (2026-09-20): 12 comprobaciones sobre la lista: normalización, subdominios sí, dominios que solo se parecen no, lista vacía no excluye nada, sin duplicados y orden estable

## Fase C — Que sirva

- [x] T09 (RF-01) Reporte de pestaña activa y audibles con `chrome.tabs.query` — `extension/src/fondo.js` — Evidencia esperada: con un vídeo sonando y el correo al frente, el estado dice activa=correo y audible=vídeo
  - Evidencia (2026-09-20): así sale en la prueba. De un dominio excluido se calla la dirección y el título pero SÍ se dice que suena: es un dato sin contenido, y es el que evita anotar una película como trabajo
- [x] T10 (RF-01, RNF-04) Envío a la API con el token en cabecera, sin acumular nada si la aplicación no responde — `extension/src/enviar.js` — Evidencia esperada: 10 min con BtoDicta cerrada → ≤ 10 intentos y almacenamiento de la extensión en 0
  - Evidencia (2026-09-20): un fallo espera 60 s antes de reintentar, y no se guarda nada pendiente. La prueba encontró un fallo REAL: `leerToken()` quedaba fuera del `try` y lanzaba sin almacén, o sea que la extensión podía tumbar a quien la aloja. Corregido y verde
- [x] T11 (RF-01) BtoDicta usa el estado del navegador en el filtro de la bitácora, por delante de lo que hoy adivina por foco — `Sources/BtoDicta/FiltroBitacora.swift` — Evidencia esperada: con el vídeo sonando detrás y el correo delante, el trozo se conserva; con el vídeo delante, se aparta
  - Evidencia (2026-09-20): las dos direcciones comprobadas, más tres casos de degradación: sin extensión se juzga por el sistema, un informe de hace una hora no decide, y el informe de OTRO navegador no decide por el que está al frente
- [x] T12 (RF-02) El texto de la página entra al índice con su texto ya puesto — `Sources/BtoDicta/ApiLocal.swift`, `Sources/BtoDicta/ContinuoIndice.swift` — Evidencia esperada: el elemento queda en el índice con texto y el OCR no lo procesa
  - Evidencia (2026-09-20): `{"texto_guardado":true}` y en el índice queda con su texto y `procesado=1`. Pendientes de OCR para esa página: **0**, mientras 5 capturas normales sí esperan. No hizo falta desactivar el OCR (ADR-005)
- [ ] T13 (RF-02) Medida contra el OCR: el texto recibido cubre ≥ 90 % de las palabras que da el OCR de esa misma pantalla — `scripts/qa-texto-vs-ocr.py` — Evidencia esperada: porcentaje medido sobre 3 artículos reales
- [x] T14 (RF-03) Captura de la pestaña con `captureVisibleTab` y su guardado en la bitácora — `extension/src/captura.js`, `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: con otra ventana encima, la imagen muestra la página entera y nada de la ventana superpuesta

## Fase D — Los cuatro navegadores

- [x] T15 (RF-06) Manifest V3 para Chromium y carga sin errores en Chrome, Edge y Brave — `extension/manifest.chromium.json` — Evidencia esperada: los tres cargan el mismo paquete y reportan estado
  - Evidencia (2026-09-20): `empaquetar.sh chromium` produce `dist/chromium` con 8 archivos; manifest_version 3, permisos `tabs, storage, alarms, scripting`, y cero archivos declarados que falten. Envío simulado de extremo a extremo: `{"recibido":2,"audibles":1,"texto_guardado":true}`. **Falta la carga real en los tres navegadores, que la hace Alberto**
- [x] T16 (RF-07) Capa de compatibilidad `chrome.*` / `browser.*` y manifiesto de Firefox — `extension/src/navegador.js`, `extension/manifest.firefox.json` — Evidencia esperada: Firefox reporta pestaña activa y audibles igual que Chrome
  - Evidencia (2026-09-20): `navegador.js` resuelve `browser.*` o `chrome.*`, y el manifiesto de Firefox declara el fondo como `scripts` y lleva identificador propio. **Sin comprobar en vivo**: Alberto decidió probar solo con Edge por ahora
- [x] T17 (RF-06, RF-07) Empaquetado reproducible de los dos paquetes desde un solo código — `extension/empaquetar.sh` — Evidencia esperada: el script produce los dos archivos y `unzip -l` muestra el mismo código en ambos
  - Evidencia (2026-09-20): huella SHA256 del código (excluyendo el manifiesto) **idéntica** en los dos paquetes: `3bcce352fb2824b3`. Y los manifiestos sí difieren donde deben — `service_worker` frente a `scripts`, más el identificador de Firefox

## Fase E — Que no estorbe

- [ ] T18 (RNF-02) Medición del coste en el navegador: 10 páginas con y sin extensión — `scripts/qa-coste-extension.py` — Evidencia esperada: < 50 ms de diferencia al cargar y < 30 MB de memoria
- [ ] T19 (RF-04) Instalador: la extensión viaja con la aplicación, no se instala sola, y se explica cómo cargarla — `Makefile`, `docs/MANUAL.md` — Evidencia esperada: el paquete de la aplicación contiene la extensión y el manual explica los pasos
- [ ] T20 (RF-05, RNF-03) Las pruebas de la extensión entran en el paquete de QA — `scripts/qa-paquete.sh` — Evidencia esperada: el QA pasa de 22 a 23 pruebas, con las negativas incluidas

## Fase G — Lo que pidió Alberto tras probarla (RF-08, RF-09)

- [x] T23 (RF-08) La extensión reporta su versión y BtoDicta avisa si es vieja — `extension/src/fondo.js`, `Sources/BtoDicta/EstadoNavegador.swift`, `Sources/BtoDicta/ApiLocal.swift` — Evidencia esperada: con una versión anterior, la respuesta lo dice y queda un aviso en el registro
  - Evidencia (2026-09-20): la extensión manda su versión en cada informe; con 0.0.1 frente a la 0.1.0 que trae la app, se detecta con ambas versiones. Una al día no avisa, y una que no dice su versión tampoco — mejor callar que avisar en falso. El aviso sale una vez por versión, no en cada informe
- [x] T24 (RF-09) Sacar la extensión desde la aplicación al sitio que se elija, con su manual — `Sources/BtoDicta/ExportarExtension.swift`, `Sources/BtoDicta/SettingsWindow.swift` — Evidencia esperada: una acción deja la carpeta con la extensión y un manual en español
  - Evidencia (2026-09-20): botón «Sacarla a una carpeta…» en Ajustes. Deja `manifest.json` con el nombre que el navegador espera, el código y `COMO-INSTALAR.md` con los pasos reales y la versión de la que salió. Exportar dos veces reemplaza sin fallar, y lo anterior va a la Papelera por si alguien dejó algo dentro

- [x] T25 (RF-10) Menú en el icono: estado de la conexión y excluir o volver a mirar la página actual con un clic — `extension/src/menu.html`, `extension/src/menu.js`, `extension/manifest.chromium.json` — Evidencia esperada: el menú dice si BtoDicta responde y el botón alterna según el dominio esté o no excluido
  - Evidencia (2026-09-20): `default_popup` declarado y presente en el paquete (10 archivos). Cuatro estados de conexión distinguidos: sin clave, clave rechazada (401), sin respuesta y conectada con el tiempo del último aviso. El mismo botón excluye y devuelve — quien se equivoca tiene la vuelta atrás donde la usó, no en otra pantalla. **Falta la comprobación visual, que la hace Alberto en Edge**

- [x] T26 (RF-11) Ruta fija que la aplicación refresca al arrancar si la versión cambió — `Sources/BtoDicta/ExportarExtension.swift`, `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: tras instalar una versión nueva, los archivos de la ruta fija son los nuevos sin que nadie exporte
  - Evidencia (2026-09-20): degradada la ruta a 0.0.9 a propósito y reabierta la app → pasa sola a 0.1.0 con el aviso «recárgala en el navegador para que la recoja». Solo copia cuando hay diferencia: reescribir en cada arranque haría que el navegador la viera modificada siempre

## Fase F — Cierre

- [ ] T21 (todos) Verificación RF por RF con segundo ángulo y prueba negativa — `docs/specs/006-extension-de-navegador-para-la-bitacora/verificacion.md` — Evidencia esperada: tabla con los 7 RF y los 4 RNF, cada uno con veredicto
- [ ] T22 (todos) Hito fechado con desviaciones y riesgos residuales, manual e índice — `docs/hitos/`, `docs/MANUAL.md` — Evidencia esperada: hito escrito, spec en Implementada e índice regenerado
