# Verificación 012 — Red de seguridad del icono y triple fn para el modo reunión

- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Estado del QA al verificar: **36 de 38** · suite Swift **70 de 70** · versión 0.81.0.
  - `texto_vs_ocr` (spec 006) falla, como ya fallaba antes de esta spec, y no tiene
    que ver con ella: mediana 0,9× frente al OCR. No se le bajó el listón.
  - `icono_oculto` falló en esa pasada **porque no había barra en la que mirar**:
    había un juego a pantalla completa. Se corrigió la prueba para que lo diga como
    OMITIDA en vez de FALLA. Esa misma pasada es, además, la mejor prueba de RF-02
    (ver abajo). El arnés completo se corrió aparte, lanzado por el sistema y con la
    barra a la vista, y pasó.

## Segunda ronda, 2026-09-23 (00:44-00:50)

- **La gracia absorbió un falso «oculto» real.** Al volver del juego a la barra, la
  copia viva de BtoDicta registró durante un solo latido «oculto: fuera de toda
  pantalla (1128, 1026)»: la barra ya estaba en pantalla y la ventana del icono aún
  no había bajado a su sitio. Dos segundos después, «visible». Sin aviso: la gracia
  de 30 s (D-3) está para esto.
- **El arnés, repetido con la barra a la vista** y el código de la 0.81.0: visible sin
  aviso; escondido en (-1894, 949), aviso a los 7,3 s, uno solo; 2 recordatorios con
  la reunión. La última comprobación («devuelto, vuelve a verse») no se pudo medir:
  se había vuelto al juego y la barra ya no estaba. El arnés ahora espera hasta 30 s
  a que la barra vuelva antes de mirar, y si no vuelve lo dice en vez de fallar.
- **BtoDicta se cerró a las 00:44:41** con un cierre normal —pasó por
  `applicationWillTerminate`, que apaga la bitácora—, no por un fallo ni por el
  actualizador. Fue tres segundos después de que la barra volviera a verse; no hay
  rastro de quién lo pidió. No se volvió a abrir desde aquí.

## Requerimientos funcionales

| RF | Qué exigía | Cómo se comprobó | Segundo ángulo | Veredicto |
|---|---|---|---|---|
| RF-01 | Aviso de icono oculto, una vez | `BTODICTA_ICONOOCULTOTEST` lanzado con `open`: el icono visible en (1086, 949), sin aviso; alargado hasta no caber, macOS lo lleva a (-1896, 949) → «oculto» → un aviso a los 7,3 s (gracia de prueba 4 s), y 8 s más escondido sigue siendo uno solo | `VigiaIconoOcultoTests`: aviso tras la gracia, uno por sesión, «no volver a avisar» lo apaga. Rojo: sin el vigía, «escondido 60 s y ningún aviso»; avisar cada vez → 6 fallos | Cumple |
| RF-02 | Sin avisos en falso | **En vivo**: con un juego a pantalla completa, macOS subió la ventana del icono a (1061, 1026), por encima de la pantalla. Sin la comprobación de la barra, eso se leería «fuera de toda pantalla». La copia real de BtoDicta registró «no se sabe: la barra no está en pantalla» y **0 avisos** | `VisibilidadIconoTests`: con la barra fuera de pantalla o que se oculta sola, «no se sabe» para cualquier posición; `VigiaIconoOcultoTests`: 300 lecturas de «no se sabe», 0 eventos. Sin icono registrado (spec 011) el vigía no arranca | Cumple |
| RF-03 | fn fn fn pone o quita el modo reunión, y el dictado sigue | `BTODICTA_TRIPLEFNTEST` por el manejador real de fn: pone el modo, sigue grabando; otra vez, lo quita y sigue grabando | Camino Carbon, y la carrera en que la tercera baja **antes** de que la grabación empiece («¿grabando ya? no»). Rojo: sin la tercera → 6 fallos; tercera solo grabando → 1 fallo; Carbon sin ella → 2 | Cumple |
| RF-04 | El doble fn igual de rápido | La segunda arranca al bajarla: ~160 ms hasta grabar, lo mismo que con la tercera saboteada (171 ms). El código del doble no cambia; la tercera se arma después, al soltar | `TriplePulsacionTests`: el arranque ocurre en la bajada de la segunda, con la tercera aún sin armar | Cumple |
| RF-05 | Pasada la ventana, fn detiene como siempre | Una pulsación tardía detiene sin tocar el modo; tres pulsaciones lentas son arrancar y detener | `TriplePulsacionTests`: 0,46 s después ya no es triple, y la marca vencida se limpia | Cumple |
| RF-06 | Recordatorio con la reunión puesta y el icono oculto | Arnés: 2 recordatorios en 15 s con el intervalo de prueba (6 s); al quitar la reunión, 0 más | `VigiaIconoOcultoTests`: el primero un intervalo después, no en el acto; sin reunión, con el icono visible o con intervalo 0, ninguno | Cumple |

## Requerimientos no funcionales

| RNF | Exigía | Resultado | Veredicto |
|---|---|---|---|
| RNF-01 | 0 ms añadidos al doble fn | La decisión del doble no cambia; medido ~160 ms de bajada a grabación con y sin la tercera | Cumple |
| RNF-02 | Aviso en < 2 min | 7,3 s con gracia 4 s; con la gracia de fábrica (30 s) y el vigía a 2 s, el peor caso es 32 s | Cumple |
| RNF-03 | 0 avisos con la barra escondida | En vivo con pantalla completa: 0 avisos. En pruebas: «no se sabe» para toda posición | Cumple |

## Desviaciones respecto a la spec

- **Gracia mínima de 2 s y recordatorio mínimo de 0,05 min** (el plan hablaba de 5 s):
  lo necesita el arnés para no tardar minutos. De fábrica siguen siendo 30 s y 30 min.
- **La barra «escondida» se detecta de dos formas**: su ventana fuera de pantalla, o
  una ventana normal del tamaño de una pantalla entera. La segunda no estaba en el
  plan; se añadió porque es lo que distingue una aplicación a pantalla completa.
- Las pruebas del QA que se lanzan con `open` ahora van **en segundo plano** (`-g`):
  sin eso, le quitaban el foco a lo que el usuario tuviera delante. Comprobado con el
  juego a pantalla completa: la aplicación de delante siguió siendo la misma.

## Reservas

- La alerta en sí (botones, «No volver a avisar» que se guarda) no se pulsó en una
  prueba automática: en carpeta aislada no se muestra. Su contenido sale de
  `IconoBarra.textoAviso`, y el botón escribe `icono_oculto_no_avisar`.
- El icono escondido **bajo la muesca** solo se prueba con geometría: no se pudo
  provocar en el equipo sin tocar ajustes del sistema.
