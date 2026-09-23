# Plan técnico 012 — Red de seguridad del icono y triple fn para el modo reunión

- Estado: Aprobado
- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Aprobado por: Alberto — 2026-09-22 — «todo si bajo goal y loop hasta resolver y que funcione todo bien y si red de seguridad y funcionalidad» (aprobación delegada de plan y tareas, dada junto con la de la spec)

## 1. Lo que hay hoy

| Pieza | Dónde | Estado |
|---|---|---|
| Vigía del icono | `AppDelegate.iniciarVigilanciaIcono()`, cada 2 s | Repara imagen, visibilidad y ventana ausente. **No sabe si el icono se ve**: `isVisible` dice `true` con el icono escondido |
| Arranque del vigía | solo si hay icono (`statusItem != nil`) | Con la cerradura de la spec 011, una copia no lanzada por el sistema no lo arranca |
| Atajo fn, modo toque | monitor de modificadores (`installFlagsMonitor`) | Doble fn arranca al BAJAR la segunda; con el dictado grabando, una pulsación detiene al SOLTAR |
| Atajo Carbon (F1-F12, combinaciones) | `pulsarAtajoCarbon()` | Solo recibe la bajada; misma regla |
| Ventana del doble | `Config.doblePulsacionVentana()`, 0,45 s por defecto | Se mide de soltar la primera a bajar la segunda (`DoublePressGate`) |
| Modo reunión | `alternarModoReunion()` (spec 010) | Pone o quita y lo confirma en el notch sin tapar el dictado |

**Geometría medida en el equipo** (2026-09-22, sin crear ningún icono): pantalla
1512 × 982; la barra ocupa de y = 949 a 982; la muesca va de x = 663 a 848
(`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`). El icono visible está en
x = 1154 dentro de la barra; el escondido que se midió en la spec 011, en (2, 981)
contado desde arriba: **fuera de la barra, en el borde inferior**.

## 2. Comprobación contra la constitución

- [x] **Sin escrituras en ajustes del sistema.** La aplicación solo mira dónde está
      su propia ventana y lo dice; no toca la lista de la barra.
- [x] **Sin avisos en falso.** Si no se puede saber —barra escondida por pantalla
      completa u ocultación automática—, no se avisa: se espera.
- [x] **El doble fn no cambia.** La tercera pulsación se decide en la pulsación
      siguiente, nunca esperando a ver si llega.
- [x] **Parametrizable.** Tiempo de gracia, intervalo del recordatorio (0 = apagado)
      y «no volver a avisar» en `config.json`.
- [x] **Toda prueba se ve en rojo.** Pruebas puras en la suite Swift y un arnés
      lanzado con `open` (spec 011) que esconde su propio icono.
- [x] **Nivel P.** Prueba por RF, segundo ángulo, verificación.
- [x] **Commits neutros.**

## 3. Decisiones

| # | Decisión | Alternativa descartada | Por qué |
|---|---|---|---|
| D-1 | «Oculto» = la ventana del icono **no está en la franja de la barra** de su pantalla, **está bajo la muesca**, no está en ninguna pantalla o no existe | La oclusión de la ventana (`occlusionState`) | La oclusión también da «no visible» con la pantalla dormida o bloqueada: avisaría en falso cada noche. La posición es lo que el usuario ve, y es lo que se midió en el icono escondido |
| D-2 | Si la barra no ocupa sitio (`visibleFrame` llega al borde superior) **no se sabe**, y no se avisa | Avisar igual | Es pantalla completa u ocultación automática: el icono tampoco se ve, pero no por un fallo |
| D-3 | Tiempo de gracia de **30 s** oculto sin interrupción antes de avisar | Avisar a la primera lectura | Al arrancar, al cambiar de pantalla o de espacio, la barra se reconstruye un instante. Con 30 s y el vigía a 2 s, el aviso llega en < 2 min (RNF-02) |
| D-4 | El aviso es una **alerta** con «Entendido» y «No volver a avisar», y **espera a que no se esté dictando** | Una notificación del sistema | Con el icono escondido, la notificación puede estar silenciada y es el único canal que queda. La alerta no se puede pasar por alto, y en mitad de un dictado robaría el foco: por eso espera |
| D-5 | El recordatorio es una **notificación del sistema** cada 30 min, más una línea en el registro | Otra alerta | Se repite: una alerta cada media hora en una reunión sería peor que el problema |
| D-6 | La tercera pulsación **se arma al soltar la segunda** (la que arrancó el dictado) y se consume al bajar la siguiente, con la misma ventana del doble. Se reutiliza `DoublePressGate` | Esperar la ventana tras la segunda antes de arrancar | Esperar retrasaría todos los dictados 0,45 s (RF-04). Así, la segunda arranca al instante igual que hoy |
| D-7 | La tercera se comprueba **antes** de mirar si se está grabando | Solo con el dictado ya grabando | El arranque del dictado es asíncrono: una tercera muy rápida puede llegar antes de que la grabación empiece, y entonces se tomaría por una primera pulsación suelta |
| D-8 | Solo en **modo toque con doble fn**. En «mantener para hablar» y con el doble apagado no hay triple | Triple en todos los modos | Con el doble apagado, fn fn fn es arrancar-parar-arrancar; en «mantener», soltar la segunda termina el dictado |

A `docs/adr/016-icono-oculto-por-posicion-y-triple-fn.md`: D-1, D-2 y D-6.

**Consecuencia aceptada de D-6** (se dice en el hito): quien arranque un dictado
con doble fn y pulse fn otra vez **en menos de 0,45 s** para cancelarlo pondrá el
modo reunión en vez de detener. El notch lo dice en el acto, y otra pulsación
detiene como siempre.

## 4. Diseño

**Decisiones puras** (`IconoBarra.swift`, `DoublePressGate.swift`), con pruebas:

- `IconoBarra.estado(ventana:pantallas:) -> EstadoIcono` → `.visible`,
  `.oculto(motivo)` o `.noSeSabe`. Recibe rectángulos, no objetos de AppKit.
- `VigiaIconoOculto` (struct): recibe cada lectura con la hora, el modo reunión y
  «no volver a avisar»; devuelve `.avisar` una sola vez tras la gracia y
  `.recordar` cada intervalo mientras siga oculto con la reunión puesta. Lo que no
  se sabe no avanza ni reinicia; lo visible reinicia.
- `TriplePulsacionPolicy.armarAlSoltar(activoPorDoble:usadoConTecla:pushToTalk:)`.

**Cableado** (`AppDelegate`):

- En el vigía de 2 s: leer la ventana del icono y las pantallas, clasificar, pasar
  a `VigiaIconoOculto` y actuar. El aviso se aplaza mientras se dicte.
- Monitor de modificadores: al soltar la segunda que arrancó, armar la tercera; al
  bajar, antes que nada salvo grabación de pantalla y confirmación, consumirla y
  marcar la pulsación como triple; al soltarla, alternar el modo reunión.
- Carbon: armar al reconocer el doble; consumir al principio de la siguiente.
- Claves nuevas: `icono_oculto_no_avisar` (bool), `icono_oculto_gracia_seg`
  (30, entre 5 y 600), `icono_oculto_recordatorio_min` (30; 0 = apagado).

**Arnés** `BTODICTA_ICONOOCULTOTEST=1`, lanzado con `open` y carpeta aislada:
mide el icono visible, lo esconde alargándolo hasta que no cabe, deja trabajar al
vigía real con gracia corta, pone la reunión y espera el recordatorio, y lo
devuelve a su tamaño. En vez de la alerta y la notificación, escribe líneas en el
registro, que el QA lee.

**Arnés** `BTODICTA_TRIPLEFNTEST=1`: alimenta el mismo manejador del monitor con
eventos sintéticos de fn y comprueba: el doble arranca en la segunda; la tercera
dentro de la ventana cambia el modo sin parar el dictado; una pulsación tardía
detiene. Para no transcribir con un motor de pago, la detención de la prueba
descarta el audio (solo con la carpeta aislada).

## 5. Orden de trabajo

1. Decisiones puras y sus pruebas, vistas en rojo.
2. Vigía: clasificar, avisar y recordar, con las claves nuevas.
3. Triple fn en los dos caminos.
4. Arneses y su registro en el QA.
5. Instalar con `make install`, abrir con `open`, QA completo.
6. Verificación, ADR, hito.

## 6. Riesgos

| Riesgo | Mitigación |
|---|---|
| macOS esconda el icono de una forma que la posición no delate | Se mide en el arnés con el icono escondido de verdad; si no lo delata, la prueba falla |
| Esconder el icono del arnés deje algo apuntado en la lista del sistema | Es la misma aplicación, lanzada por el sistema; se comprueba después, **solo leyendo**, con `qa-icono-a-su-nombre.py` |
| Cancelar con fn en < 0,45 s pone el modo reunión | Aceptado (D-6); el notch lo dice y otra pulsación detiene |
| La alerta aparezca con la pantalla bloqueada | La alerta espera en el escritorio; no bloquea el dictado porque no aparece mientras se dicta |
