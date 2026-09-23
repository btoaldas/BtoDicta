# Tareas 007 — Asistente de exclusiones con semillas y modo de trabajo

- Estado: Aprobadas
- Fecha: 2026-09-21
- Spec: `spec.md` (Aprobada 2026-09-21) · Plan: `plan.md` (Aprobado 2026-09-21)
- Aprobado por: Alberto — 2026-09-21 — «sigue adelante las tareas y arranca por t01»

Cada tarea cita su RF y dice qué evidencia la cierra. Un `[x]` sin `Evidencia:`
es una promesa, no un hecho.

Orden deliberado: **el modo restrictivo va primero**, con sus pruebas, antes de
que exista una sola línea de interfaz. Es lo único de esta spec que puede apagar
la bitácora entera en silencio, y un fallo ahí no se nota hasta que hace falta
el material que no se grabó.

`[P]` = no depende de la tarea anterior.

## Fase A — El modo, antes que nada

- [x] T01 (RF-03) El modo en la decisión pura
  - Archivos: `Sources/BtoDicta/FiltroBitacora.swift`
  - `Modo` (`.permisivo` / `.restrictivo`) y parámetro nuevo en
    `decidir(app:ventana:excluirApps:…)`. En restrictivo entra **solo** lo que
    esté en alguna lista de inclusión.
  - Evidencia esperada: `swift test --filter FiltroBitacoraTests` en verde, y las
    8 pruebas de hoy intactas — el modo permisivo no cambia de comportamiento.
  - Evidencia (2026-09-21): `swift test --filter FiltroBitacoraTests` → 14 de 14, y las 8 anteriores intactas: el modo permisivo no cambió de comportamiento.

- [x] T02 (RF-03) Pruebas de los dos modos, vistas en ROJO
  - Archivos: `Tests/BtoDictaTests/FiltroBitacoraTests.swift`
  - Casos: restrictivo con una app autorizada deja fuera al resto; restrictivo con
    inclusiones vacías no graba nada; permisivo se comporta como hoy.
  - Evidencia esperada: salida del sabotaje —invertir el modo en el código— con
    las pruebas nuevas en rojo, y en verde tras restaurar.
  - Evidencia (2026-09-21): Tres sabotajes, tres rojos. Caer a restrictivo ante un valor desconocido → **8 fallos**; el restrictivo que no filtra → 4; la lista blanca que deja de ir primero → 3. Restaurado: 14 de 14.

- [x] T03 (RF-03) `bitacora_modo` y la variante que lo lee
  - Archivos: `Sources/BtoDicta/Config.swift`, `Sources/BtoDicta/FiltroBitacora.swift`
  - De fábrica `"permisivo"`. Un valor desconocido cae a permisivo, nunca a
    restrictivo: equivocarse hacia el lado que apaga la bitácora sería peor.
  - Evidencia esperada: prueba con la clave ausente, con valor válido y con valor
    basura.
  - Evidencia (2026-09-21): `FiltroBitacora.modo()` lee por `Config`. `testModoDesconocidoCaeAPermisivo` cubre nil, vacío, espacios, «restricitvo», «strict», «RESTRICTIVE», «1» y «null»; `testLosValoresBuenosSeReconocen` evita que pase con un código que ignore todo.

## Fase B — El catálogo

- [x] T04 (RF-01, RF-04) El archivo de semillas
  - Archivos: `Resources/semillas-exclusion.json`
  - Las siete categorías del §5 del plan, con `destino` (`titulos` o `apps`),
    `id` por entrada y `version`. LinkedIn **fuera** de redes sociales.
  - Evidencia esperada: el JSON valida y ninguna entrada es un fragmento corto
    (comprobación automática de longitud y de punto en el dominio, D-3).
  - Evidencia (2026-09-21): `python3 scripts/qa-semillas.py` → versión 1 · 7 categorías · 70 entradas · ninguna entrada que no pueda coincidir. LinkedIn fuera de «redes sociales», y los buscadores entran como `google.com/search` para no comerse Drive ni Gmail.

- [x] T05 (RF-04) Cargar y validar el catálogo [P]
  - Archivos: `Sources/BtoDicta/SemillasExclusion.swift`,
    `Tests/BtoDictaTests/SemillasExclusionTests.swift`
  - Pruebas: una entrada con `destino: apps` aterriza en `bitacora_excluir_apps` y
    **no** en títulos; y al revés. Es el RF que nació de escribir dos apps en la
    lista de títulos, donde no podían coincidir nunca.
  - Evidencia esperada: prueba en rojo al invertir el destino en el cargador.
  - Evidencia (2026-09-21): `swift test --filter SemillasExclusionTests` → 7 de 7. La prueba encontró un fallo real en el validador: exigía 4 letras a toda entrada y rechazaba «vlc», que estaba en el propio catálogo. El mínimo pasa a depender del destino (4 para títulos, 3 para aplicaciones) con la razón escrita. Sabotaje del catálogo → código 1 con los tres problemas señalados; restaurado → código 0.

- [x] T06 (RF-01) Aplicar la selección, por unión
  - Archivos: `Sources/BtoDicta/SemillasExclusion.swift`
  - Escribe por `Config.set` (D-7). Une con lo que ya hubiera; no concatena ni
    duplica.
  - Evidencia esperada: prueba que acepta dos veces la misma categoría y la lista
    no crece la segunda vez.
  - Evidencia (2026-09-21): `nuevasListas` calcula sin escribir y `aplicar` es el único que escribe. Tres pruebas: une con lo previo, aceptar dos veces no hace crecer la lista, y lo escrito a mano sobrevive y va primero.

- [ ] T07 (RNF-02) Nada se escribe antes de Aceptar
  - Archivos: `Tests/BtoDictaTests/SemillasExclusionTests.swift`
  - Evidencia esperada: `sha256` de la configuración antes de abrir y después de
    cerrar sin aceptar — idéntico. Y distinto tras aceptar.
  - Parcial (2026-09-21): la mitad estructural ya está y se vigila en QA — `qa-semillas.py` cuenta los sitios que escriben las listas y exige que sean dos, ambos en `SemillasExclusion.aplicar`, descontando los 13 del arnés de pruebas por conteo de llaves. Verificado en rojo colando una escritura en `ContinuoView`. La mitad de punta a punta —`sha256` del `config.json` al abrir y cerrar sin aceptar— necesita la pantalla y se cierra con T09.

- [x] T08 (RF-07) Rechazos y versión del catálogo
  - Archivos: `Sources/BtoDicta/SemillasExclusion.swift`, `Sources/BtoDicta/Config.swift`
  - `bitacora_semillas_rechazadas` por identificador y `bitacora_asistente_visto`.
  - Evidencia esperada: prueba que desmarca una semilla, sube la versión del
    catálogo y comprueba que esa semilla no vuelve marcada.
  - Evidencia (2026-09-21): `rechazadas`/`versionVista` y sus escritores. `testLoRechazadoSeSigueOfreciendoPeroDesmarcado`: lo rechazado se sigue viendo —si no, no hay forma de cambiar de opinión— pero desmarcado. `testSoloSeMolestaAlUsuarioConUnCatalogoMasNuevo`: con la misma versión no vuelve a salir solo.

## Fase C — La pantalla

- [ ] T09 (RF-01) Sección «Qué no debe mirar la bitácora»
  - Archivos: `Sources/BtoDicta/ContinuoView.swift`
  - Dentro de la pestaña Bitácora, no una pestaña nueva: `.asistente` ya es el
    agente de IA (D-6). Categorías marcadas de salida; un solo botón Aceptar.
  - Evidencia esperada: captura de la sección con las siete categorías.

- [ ] T10 (RF-02) Desplegable para afinar dentro de una categoría
  - Archivos: `Sources/BtoDicta/ContinuoView.swift`
  - Evidencia esperada: desmarcar una entrada de una categoría de N y comprobar en
    `config.json` que se escribieron N−1.

- [ ] T11 (RF-01) Decir qué apaga cada lista
  - Archivos: `Sources/BtoDicta/ContinuoView.swift`
  - Una línea junto a cada lista: la ancha apaga audio y capturas; la de capturas
    solo la foto; la de la extensión impide que la URL salga del navegador. Tener
    tres sitios donde escribir «youtube» con efectos distintos es una trampa.
  - Evidencia esperada: captura de las tres leyendas.

- [ ] T12 (RF-08) Selector de modo y aviso de bitácora ciega
  - Archivos: `Sources/BtoDicta/ContinuoView.swift`
  - Pasar a restrictivo con la lista de inclusiones vacía avisa y exige confirmar.
  - Evidencia esperada: prueba de que el cambio no se guarda sin confirmación, y
    captura del aviso.

- [ ] T13 (RF-05) Aparecer solo la primera vez
  - Archivos: `Sources/BtoDicta/ContinuoView.swift`, `Sources/BtoDicta/AppDelegate.swift`
  - Evidencia esperada: con `bitacora_asistente_visto` ausente se ofrece; tras
    aceptar o descartar, reiniciar la app y comprobar que no vuelve.

- [ ] T14 (RF-06) La edición manual manda
  - Archivos: `Sources/BtoDicta/SemillasExclusion.swift`
  - Evidencia esperada: prueba que borra a mano una entrada puesta por el
    asistente, recarga y comprueba que sigue sin estar.

## Fase D — La lista ampliada

- [ ] T15 (RF-09) Descarga explícita, apagada de fábrica
  - Archivos: `Sources/BtoDicta/SemillasExclusion.swift`, `Sources/BtoDicta/ContinuoView.swift`
  - Enseña la dirección antes de descargar. Guarda en disco para funcionar sin
    conexión. Si falla, lo dice y sigue con la lista corta.
  - Evidencia esperada: con la ampliación apagada, **0 peticiones de red** al
    abrir la sección y al aceptar (comprobado con el registro de red).

- [ ] T16 (RF-09) Coincidencia por anfitrión sobre un conjunto
  - Archivos: `Sources/BtoDicta/FiltroBitacora.swift`
  - Extrae el anfitrión de la URL y busca ese y sus dominios padre. Nunca por
    subcadena (D-8). Sin URL real no se aplica: la lista corta es la red de
    seguridad, y eso se dice en la pantalla.
  - Evidencia esperada: prueba con un anfitrión de la lista, uno de un subdominio
    suyo, y uno que solo la contiene como subcadena y **no** debe excluirse.

## Fase E — Medidas, ADR y cierre

- [ ] T17 (RNF-01, RNF-03, RNF-04, RNF-05) Las cuatro medidas
  - Archivos: `scripts/qa-asistente-exclusiones.py`
  - RNF-01 aceptar todo < 2 s · RNF-03 diez idas y vueltas de modo dejan las
    cuatro listas idénticas · RNF-04 dos interacciones para la configuración
    recomendada · RNF-05 decisión < 5 ms con más de 10 000 dominios cargados.
  - Evidencia esperada: salida del script con los cuatro números medidos, no
    estimados.

- [ ] T18 (RF-03, RF-09) Los tres ADR
  - Archivos: `docs/adr/010-comparacion-por-subcadena.md`,
    `docs/adr/011-alcance-lista-contenido-adulto.md`,
    `docs/adr/012-dos-formas-de-comparar.md`
  - Evidencia esperada: los tres archivos con su alternativa descartada.

- [ ] T19 (todos) Verificación RF por RF
  - Archivos: `docs/specs/007-asistente-de-exclusiones-con-semillas-y-modo-de-trabajo/verificacion.md`
  - Cada RF con criterio ejecutado de punta a punta, segundo ángulo distinto y
    prueba negativa donde aplique.
  - Evidencia esperada: `verificar-tasks.py` y `qa-paquete.sh` en 0.

- [ ] T20 (todos) Hito
  - Archivos: `docs/hitos/2026-MM-DD-asistente-exclusiones.md`, `ROADMAP.md`
  - Con «Desviaciones respecto a la spec» aunque diga ninguna, y riesgos
    residuales.
  - Evidencia esperada: `indice-specs.py --escribir` regenera el índice; spec a
    `Implementada`.
