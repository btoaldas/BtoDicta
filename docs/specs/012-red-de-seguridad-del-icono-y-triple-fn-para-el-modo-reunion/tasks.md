# Tareas 012 — Red de seguridad del icono y triple fn para el modo reunión

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22) · Plan: `plan.md` (Aprobado 2026-09-22)
- Aprobado por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien y si red de seguridad y funcionalidad» (aprobación delegada)

- [x] T01 (RF-01, RF-02, RNF-03) Clasificar el icono por su posición, con pruebas vistas en rojo
  - Archivos: `Sources/BtoDicta/IconoBarra.swift`, `Tests/BtoDictaTests/IconoBarraTests.swift`
  - Evidencia esperada: en la barra → visible; abajo, fuera de pantalla, sin ventana o bajo la muesca → oculto; barra escondida → no se sabe. Con la geometría medida del equipo.
  - Evidencia (2026-09-22): `IconoBarra.visibilidad(ventana:pantallas:barraEnPantalla:)` y `VisibilidadIconoTests`: 9 de 9, con la geometría medida (barra de y = 949 a 982, muesca de x = 663 a 848). Rojo: «siempre visible» → 9 fallos; muesca ignorada → 2 fallos.

- [x] T02 (RF-01, RF-02, RF-06) El vigía: avisar una vez, recordar con la reunión puesta
  - Archivos: `Sources/BtoDicta/IconoBarra.swift`, `Tests/BtoDictaTests/IconoBarraTests.swift`
  - Evidencia esperada: aviso solo tras la gracia y una vez; «no volver a avisar» lo apaga; lo que no se sabe no avanza; recordatorio cada intervalo solo con reunión y oculto; intervalo 0 lo apaga.
  - Evidencia (2026-09-22): `VigiaIconoOculto` y `VigiaIconoOcultoTests`: 8 de 8. Rojo: avisar cada vez → 6 fallos; «no se sabe» que reinicia → 1 fallo.

- [x] T03 (RF-03, RF-04, RF-05) La tercera pulsación, pura
  - Archivos: `Sources/BtoDicta/DoublePressGate.swift`, `Tests/BtoDictaTests/TriplePulsacionTests.swift`
  - Evidencia esperada: se arma solo tras un doble que arrancó, en modo toque y sin tecla; dentro de la ventana es triple; fuera, no; el doble no la consulta.
  - Evidencia (2026-09-22): `TriplePulsacionPolicy` + `DoublePressGate` reutilizado; `TriplePulsacionTests`: 3 de 3. Rojo: armar siempre → 3 fallos. Suite Swift: 70 de 70.

- [x] T04 (RF-01, RF-02, RF-06) Cablear el vigía, el aviso y el recordatorio
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`, `Sources/BtoDicta/Config.swift`
  - Evidencia esperada: claves nuevas con sus límites; el aviso espera a que no se dicte; líneas en el registro.
  - Evidencia (2026-09-22): `vigilarVisibilidadIcono()` en el vigía de 2 s; claves `icono_oculto_no_avisar`, `icono_oculto_gracia_seg` (30; 2-600), `icono_oculto_recordatorio_min` (30; 0 apaga). La barra se da por escondida si su ventana no está en pantalla o una ventana normal ocupa una pantalla entera. Aviso aplazado mientras se dicta; se rearma si el icono vuelve a verse antes de mostrarlo.

- [x] T05 (RF-03, RF-04, RF-05) Cablear la triple fn en los dos caminos
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`
  - Evidencia esperada: monitor de modificadores y Carbon; la segunda sigue arrancando al bajar.
  - Evidencia (2026-09-22): monitor de fn (armar al soltar la segunda que arrancó; consumir al bajar, antes de mirar si se graba) y Carbon (armar al reconocer el doble). El código del doble no cambia.

- [x] T06 (RF-01, RNF-02) Arnés del icono oculto, lanzado por el sistema
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`, `scripts/qa-paquete.sh`
  - Evidencia esperada: visible → no avisa; escondido de verdad → avisa en menos de 2 min, una vez; con la reunión, recuerda; devuelto → visible. Rojo con el vigía saboteado.
  - Evidencia (2026-09-22): `BTODICTA_ICONOOCULTOTEST` por `open`: visible en (1086, 949) → 0 avisos; alargado hasta no caber, macOS lo lleva a (-1896, 949) → «oculto», aviso a los 7,3 s (gracia 4 s), uno solo; con la reunión, 2 recordatorios en 15 s (cada 6 s); devuelto → visible, 0 recordatorios más. Rojo sin el vigía: «escondido 60 s y ningún aviso». Lista de la barra sin escribir (misma hora de modificación antes y después) y `qa-icono-a-su-nombre.py` en verde.

- [x] T07 (RF-03, RF-04, RF-05) Arnés de la triple fn
  - Archivos: `Sources/BtoDicta/AppDelegate.swift`, `scripts/qa-paquete.sh`
  - Evidencia esperada: fn fn arranca; fn fn fn cambia el modo y sigue grabando; tardía detiene. Rojo sin la tercera.
  - Evidencia (2026-09-22): `BTODICTA_TRIPLEFNTEST`, 14 comprobaciones en verde: fn fn fn pone y quita el modo con el dictado grabando; una tardía detiene sin tocar el modo; tres lentas son arrancar y detener; fn fn solo arranca; tercera antes de grabar (carrera forzada: «¿grabando ya? no») también pone el modo; camino Carbon. Doble: ~160 ms de la bajada de la segunda a grabar, igual que sin la tercera. Rojo: sin la tercera → 6 fallos; tercera solo grabando → 1 fallo (D-7); Carbon sin la tercera → 2 fallos.

- [x] T08 (RF-01, RF-02, RF-03) Instalar, QA completo, y el icono sigue a su nombre
  - Archivos: `Sources/BtoDicta/Version.swift`, `Info.plist`
  - Evidencia esperada: `make install` + `open`; QA completo; `qa-icono-a-su-nombre.py` verde, icono dentro de la barra.
  - Evidencia (2026-09-22): 0.81.0 con `make install` (sin `reparar-icono`) y abierta con `open -a`: padre 1, icono en (1131, 4), registro «icono barra: visible». QA completo 36 de 38: `texto_vs_ocr` (ajena, ya roja) e `icono_oculto` sin barra que medir por un juego a pantalla completa; corregida para decirlo como OMITIDA. `icono_a_su_nombre` y `config_del_usuario_intacta` en verde. Suite Swift 70 de 70.

- [x] T09 (RF-01, RF-02, RF-03, RF-04, RF-05, RF-06) Verificación, ADR e hito
  - Archivos: `docs/specs/012-red-de-seguridad-del-icono-y-triple-fn-para-el-modo-reunion/verificacion.md`, `docs/adr/016-icono-oculto-por-posicion-y-triple-fn.md`, `docs/hitos/2026-09-22-red-de-seguridad-del-icono.md`
  - Evidencia esperada: cada RF Cumple con segundo ángulo.
  - Evidencia (2026-09-22): `verificacion.md` con los seis RF en Cumple y segundo ángulo; `docs/adr/016-icono-oculto-por-posicion-y-triple-fn.md`; `docs/hitos/2026-09-22-red-de-seguridad-del-icono.md`.
