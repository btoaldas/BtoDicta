# Tareas 010 — Controles rápidos desde el icono de la barra

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22) · Plan: `plan.md` (Aprobado 2026-09-22)
- Aprobado por: Alberto — 2026-09-22 — «si goal todas las tareas hasta terminar todo una por una»

Cada tarea cita su RF y dice qué evidencia la cierra. Un `[x]` sin `Evidencia:`
es una promesa, no un hecho.

Orden deliberado: **la pausa que vuelve sola va primero**, con sus pruebas, antes
que el menú. Una pausa que no vuelve deja de grabar sin que nadie lo note, y se
descubre buscando material que ya no existe. El menú es lo que se ve; lo que
puede fallar en silencio es lo de debajo.

`[P]` = no depende de la tarea anterior.

## Fase A — El estado y la pausa

- [x] T01 (RF-04, RF-05, RF-06) El estado: reunión y pausa, sin interfaz
  - Archivos: `Sources/BtoDicta/ModoRapido.swift`
  - `enReunion`, `pausadaHasta` como **instante**, `pausar(minutos:)`,
    `reanudar()`, `pausaVigente(ahora:)`. Todo con el reloj como parámetro, para
    poder probarlo sin esperar media hora.
  - Evidencia esperada: compila y el estado se guarda y se recupera de
    `config.json` en las dos claves del plan, y solo en esas.
  - Evidencia (2026-09-22): `ModoRapido.swift` compila. Solo escribe `modo_reunion` y `bitacora_pausada_hasta` (`clavesDeEstado`, fijado por `testSoloDosClavesDeEstado`); la comprobación de que no toca ninguna otra es T08.

- [x] T02 (RF-05, RF-06) Pruebas del vencimiento, vistas en ROJO
  - Archivos: `Tests/BtoDictaTests/ModoRapidoTests.swift`
  - Casos: vence a su hora; no vence antes; tras un «reinicio» simulado sigue
    vigente con el tiempo que le quedaba; tras una «suspensión» de dos horas ya
    venció; pausar estando pausada sustituye el plazo, no lo acumula.
  - Evidencia esperada: sabotaje —guardar minutos restantes en vez del instante—
    con la prueba del reinicio en rojo, y verde tras restaurar.
  - Evidencia (2026-09-22): `swift test --filter ModoRapidoTests` → 8 de 8. Sabotaje con la alternativa descartada (guardar los segundos que faltan y sumarlos al cargar): `testTrasUnReinicioLeQuedaElTiempoDeReloj` y `testTrasUnaSuspensionLargaYaVencio` en ROJO. Restaurado: 8 de 8.

- [x] T03 (RF-04) La pausa llega de verdad a la bitácora
  - Archivos: `Sources/BtoDicta/ContinuoBitacora.swift`, `Sources/BtoDicta/ContinuoPantalla.swift`
  - Bandera **propia**, separada de la cesión del micrófono al dictado (D-2).
    Durante la pausa: ni audio ni capturas.
  - Evidencia esperada: con una pausa activa, 0 anotaciones nuevas en la bitácora
    durante la ventana medida.
  - Evidencia (2026-09-22): Arnés `BTODICTA_PAUSATEST` contra carpeta aislada: control sin pausa 329 244 bytes en 10 s; con pausa, **0 bytes nuevos en 12 s**. La pausa se comprueba en el arranque y en las tres entradas de datos (audio, pantalla, audio del sistema).

- [x] T04 (RF-05) El vencimiento, con su aviso
  - Archivos: `Sources/BtoDicta/ModoRapido.swift`
  - `DispatchSourceTimer` en cola propia (D-3) que comprueba contra el reloj cada
    15 s. Al vencer: reanuda y avisa.
  - Evidencia esperada: arnés con una pausa de un minuto; se reanuda antes de 60 s
    después del vencimiento, con la línea de aviso en el registro.
  - Evidencia (2026-09-22): Mismo arnés: vence y reanuda 0,1 s después del vencimiento (intervalo 3 s); tras volver entran 956 612 bytes. Con el intervalo real de 15 s corre dentro del QA.

- [x] T05 (RF-04) La pausa no toca el dictado en curso [P]
  - Archivos: `Sources/BtoDicta/ContinuoBitacora.swift`
  - Evidencia esperada: prueba de que terminar un dictado durante una pausa no la
    cancela. Es el fallo que evita D-2: con una sola bandera, colgar un dictado
    reanudaría la bitácora que el usuario pausó.
  - Evidencia (2026-09-22): Mismo arnés: se simula un dictado entero —ceder y recuperar el micrófono— en mitad de la pausa, y siguen entrando 0 bytes. Sabotaje: sin las dos cerraduras de `ContinuoAudio`, ese mismo dictado reabre el micrófono y **escribe 399 968 bytes durante la pausa**. Es exactamente el fallo que D-2 evita.

## Fase B — El modo reunión

- [x] T06 (RF-01, RF-08) Los tres frenos consultan el modo
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Aviso periódico, tope de duración y corte por silencio se **saltan** con el
    modo puesto. Los valores del usuario no se tocan (D-4).
  - Evidencia esperada: con el modo puesto, un dictado sin voz sigue abierto pasado
    el límite de silencio; sin él, se cierra como siempre.
  - Evidencia (2026-09-22): Un único punto de corte, justo antes de los tres frenos: con `ModoRapido.enReunion` se salta el recordatorio, el tope y el corte por silencio; los valores del usuario no se tocan. Arnés `BTODICTA_REUNIONTEST`: con el modo, 12 s sin voz y límite 4 → sigue abierto; sin él, el corte vuelve y cierra. Sabotaje (quitar el punto de corte) → se corta a los 4 s, ROJO.

- [x] T07 (RF-02) Activarlo con el dictado en curso no lo corta
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Arnés `BTODICTA_REUNIONTEST`: abre un dictado, espera hasta rozar el límite de
    silencio, activa el modo, y comprueba que no se cierra y que el audio previo
    sigue en la misma grabación.
  - Evidencia esperada: el arnés en verde, y en rojo con el modo sin conectar.
  - Evidencia (2026-09-22): Mismo arnés: activado a 2,5 s de un corte de 4, el dictado sigue en la MISMA grabación (`archivoEnCurso` igual) y entran 403 308 bytes más. Al quitarlo, en la primera vuelta del temporizador (4,8 s) NO se cierra de golpe. Sabotaje (no reiniciar la ventana de silencio al quitarlo) → se cierra de golpe, ROJO. Hallazgo: el temporizador del dictado late cada 5 s, no cada 0,5; la primera versión de la prueba miraba a un tiempo fijo y pasaba por casualidad.

- [x] T08 (RNF-04, RF-08) Ninguna clave preexistente cambia [P]
  - Archivos: `scripts/qa-modo-rapido.py`, `scripts/qa-paquete.sh`
  - Compara todas las claves del `config.json` menos las dos de estado, antes y
    después de activar y quitar el modo. Es la medida precisada en el §5 del plan.
  - Evidencia esperada: verde en uso normal; rojo si el modo escribe en
    `silencio_max_seg`.
  - Evidencia (2026-09-22): `scripts/qa-modo-rapido.py t08`, desde fuera: fotos del `config.json` justo antes y después de poner y quitar el modo, pausar dos veces y reanudar. 8 claves preexistentes comparadas, 0 cambios. Exige además que `modo_reunion` sí quede escrito, para que «no tocó nada» no signifique «no hizo nada». Sabotaje (el modo pone el corte a 0) → `silencio_max_seg: 15.0 → 0`, ROJO.

## Fase C — El icono y el menú

- [ ] T09 (RF-03, RNF-03) El icono con sus tres estados
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Normal, reunión y bitácora pausada, con la prioridad del plan (D-5).
  - Evidencia esperada: captura de la barra en los tres estados.

- [ ] T10 (RF-01, RNF-01) Menú: activar y quitar el modo reunión
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Elemento con `tag`, refrescado en `menuWillOpen` (D-6), con la marca de
    activado.
  - Evidencia esperada: dos interacciones desde cualquier aplicación.

- [ ] T11 (RF-04) Menú: pausar la bitácora
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - «No mirar durante…» con 15 min, 30 min, 1 h, hasta mañana y «Reanudar ya».
    Mientras está pausada, el propio menú dice hasta qué hora.
  - Evidencia esperada: captura del submenú con la hora de vuelta visible.

- [ ] T12 (RF-07) Minutos y tamaño pendiente, en el menú
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`, `Sources/BtoDicta/Recorder.swift`
  - Con un dictado largo en curso, el menú enseña minutos grabados y megabytes
    que se transcribirán al soltar.
  - Evidencia esperada: con un dictado de más de diez minutos, el menú muestra
    ambas cifras y coinciden con el archivo en disco.

## Fase D — Medidas y cierre

- [x] T13 (RNF-02) La pausa vence con error menor de 60 s, también tras reiniciar
  - Archivos: `scripts/qa-modo-rapido.py`
  - Evidencia esperada: pausa de dos minutos con un reinicio en medio; se reanuda
    dentro de los 60 s siguientes al vencimiento.
  - Evidencia (2026-09-22): `scripts/qa-modo-rapido.py t13` con el vigía REAL de 15 s: pausa de 40 s, la aplicación se cierra 5 s y se vuelve a abrir; vuelve **+11,4 s** después del vencimiento (límite 60). Sabotaje (vigía que no arranca) → la pausa no vuelve nunca, ROJO. El primer intento de este sabotaje NO rompió nada: un `return` suelto en Swift se une a la línea siguiente y el vigía seguía ejecutándose. Un sabotaje que no rompe nada no prueba la prueba.

- [ ] T14 (RF-05, RF-04) Los dos ADR
  - Archivos: `docs/adr/013-instante-frente-a-cuenta-atras.md`,
    `docs/adr/014-pausa-y-cesion-dos-banderas.md`
  - Numerados a partir de 013: del 006 al 009 los tomó la spec 008/009, y del 010
    al 012 quedan reservados para la spec 007.
  - Evidencia esperada: los dos archivos con su alternativa descartada.

- [ ] T15 (todos) Verificación RF por RF
  - Archivos: `docs/specs/010-controles-rapidos-desde-el-icono-de-la-barra/verificacion.md`
  - Evidencia esperada: cada RF con segundo ángulo; `qa-paquete.sh` en 0.

- [ ] T16 (todos) Hito
  - Archivos: `docs/hitos/2026-09-22-controles-rapidos.md`, `ROADMAP.md`
  - Evidencia esperada: spec a `Implementada` e índice regenerado.
