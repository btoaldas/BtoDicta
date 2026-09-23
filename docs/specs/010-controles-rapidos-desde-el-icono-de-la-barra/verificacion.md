# Verificación 010 — Controles rápidos desde el icono de la barra

- Fecha: 2026-09-22
- Spec: `spec.md` (Aprobada 2026-09-22, nivel P)
- Estado del QA al verificar: **35 pruebas, 0 fallos** (código de salida 0) · suite Swift **47**, 0 fallos · versión 0.80.0

Todas las pruebas de esta spec se vieron **dar rojo** contra el código saboteado
antes de fiarse de ellas. Las que tocan la bitácora o la configuración corren
contra una carpeta aislada y se niegan a correr sin ella.

## Requerimientos funcionales

| RF | Qué exigía | Cómo se comprobó | Segundo ángulo | Veredicto |
|---|---|---|---|---|
| RF-01 | Modo reunión desde el icono: no corta por silencio ni duración | `BTODICTA_REUNIONTEST`: con el modo, 12 s sin voz y un límite de 4 → sigue abierto. Sin conectar el modo → se corta a los 4 s | `BTODICTA_MENUTEST` pulsa el elemento del menú por su acción, como el usuario, y el modo queda puesto y marcado | Cumple |
| RF-02 | Se puede activar con el dictado ya empezado | Mismo arnés: activado a 2,5 s de un corte de 4, sigue la MISMA grabación (`archivoEnCurso` igual) y entran 403 308 bytes más | El audio previo no se pierde: la grabación no se reabre, solo continúa | Cumple |
| RF-03 | El icono dice el estado sin abrir el menú | `BTODICTA_ICONTEST`: cuatro estados con forma distinta del reposo, plantilla sin tinte y descripción propia | Los iconos se guardaron como imagen y se miraron: micrófono · dos personas · dos personas con ondas · pausa. **Con la barra llena el icono puede quedar oculto** (medido; ver riesgos): el Dock ofrece los mismos controles. Reserva en riesgos | Cumple |
| RF-04 | Pausar la bitácora por un rato | `BTODICTA_PAUSATEST` en carpeta aislada: control 329 244 bytes en 10 s; con pausa, **0 bytes en 12 s** | `BTODICTA_MENUTEST`: pulsar «30 minutos» pausa, y el menú dice «⏸ Bitácora en pausa hasta las 22:11» | Cumple |
| RF-05 | La pausa vuelve sola, con aviso | `BTODICTA_PAUSATEST`: vence y reanuda 0,1 s después (vigía de 3 s), con la línea en el registro, y vuelve a grabar | `qa-modo-rapido.py t13` con el vigía REAL de 15 s: +11,4 s | Cumple |
| RF-06 | La pausa sobrevive a un reinicio | `qa-modo-rapido.py t13`: pausa, la aplicación se cierra 5 s, se abre, y vence a su hora | `testTrasUnReinicioLeQuedaElTiempoDeReloj`: con la alternativa descartada (cuenta atrás), ROJO | Cumple |
| RF-07 | Minutos y tamaño pendientes, en el menú | `BTODICTA_MENUTEST` con un dictado de verdad: «● Grabando 0:08 · 0,3 MB por transcribir» | Los bytes que usa el menú son los del archivo en disco salvo exactamente 44: la cabecera WAV. Sesiones largas sobre el texto puro: 20 h → 2.197,3 MB | Cumple |
| RF-08 | Quitar el modo devuelve lo de siempre, sin tocar los ajustes | `BTODICTA_REUNIONTEST`: en la primera vuelta tras quitarlo NO se cierra de golpe; después cierra por silencio como siempre; el ajuste sigue en 4 s | `qa-modo-rapido.py t08`, desde fuera: 8 claves preexistentes, 0 cambios. Si el modo escribe en el corte de silencio, ROJO | Cumple |

## Requerimientos no funcionales

| RNF | Exigía | Resultado | Veredicto |
|---|---|---|---|
| RNF-01 | 2 interacciones para el modo reunión | Está en el primer nivel del menú: abrir y pulsar | Cumple |
| RNF-02 | La pausa vence con error < 60 s, también tras reiniciar | +11,4 s con el vigía real y un reinicio en medio | Cumple |
| RNF-03 | 3 estados distinguibles sin abrir el menú | Cuatro, mirados en imagen; se distinguen por forma | Cumple |
| RNF-04 | 0 cambios en las claves del usuario | 0 cambios en las claves PREEXISTENTES (medida precisada en el §5 del plan) | Cumple |

## Desviaciones respecto a la spec

**La prioridad del icono (D-5) se precisó al implementar.** El plan decía «pausa,
luego reunión, luego el estado de siempre». Tal cual, un dictado en curso con la
bitácora pausada habría enseñado el icono de pausa en vez del de grabando. Como la
pausa no toca el dictado (D-7), ocultar «estoy grabando» sería peor que ocultar la
pausa. Queda así: **dictando, manda el dictado**; en reposo, la pausa gana a la
reunión.

**El RNF-04 mide claves preexistentes**, no todas. Tal como se escribió era
imposible: el estado tiene que guardarse para sobrevivir a un reinicio. Está
declarado en el §5 del plan desde antes de escribir código.

**T12 no se comprobó con un dictado de diez minutos en vivo.** El formato largo
—horas, miles de MB— se prueba sobre una función pura con 10 min, 3 h y 20 h.
Grabar diez minutos para comprobar un formato no añade nada que la función pura
no diga.

**El temporizador del dictado late cada 5 s**, no cada medio segundo. El corte por
silencio y su aviso previo tienen esa resolución. Con los valores que ofrece
Ajustes (15 s como mínimo) el aviso llega antes que el corte; con un límite por
debajo de 10 s escrito a mano en `config.json`, pueden llegar en la misma vuelta.

## Lo que se aprendió probando

- **Una prueba que mira a un tiempo fijo puede pasar sin pasar por el código.** La
  primera versión de la comprobación «al quitar el modo no se cierra de golpe»
  miraba a los 2 s; con un temporizador de 5 s, aún no había pasado por ahí. Ahora
  espera a la primera vuelta tras la transición.
- **Un sabotaje que no rompe nada no prueba la prueba.** Para comprobar que la
  prueba del reinicio detecta un vigía que no arranca, se insertó un `return` al
  principio de `vigilar()`. Swift lo unió a la línea siguiente —`return
  cola.async { … }`— y el vigía siguió funcionando. La prueba dio verde con el
  «sabotaje» puesto. Solo al ver ese verde imposible se detectó; con `if true {
  return }` dio el rojo esperado.
- **La puerta de implementación estuvo cerrada por un literal.** El comprobador
  espera `Estado: Aprobado` y el archivo decía `Aprobadas`. Afectó también a la spec
  007 mientras se implementaba. La aprobación de Alberto existía; el comprobador no
  la reconocía.

## Riesgos residuales

- **Con la barra de menús llena, macOS esconde el icono de BtoDicta sin avisar.**
  Medido, no supuesto: en el equipo de desarrollo, el 2026-09-22, los iconos
  visibles del Centro de Control estaban en y = 4-5 y los ocultos en (0, 982); el de
  BtoDicta, en **(2, 981)** — fuera de la barra. Con el icono oculto no se ve el
  estado ni se puede pulsar.

  **Mitigación aplicada:** el menú del Dock es una copia del menú del icono, así que
  ofrece los mismos controles. Se corrigió que se copiara sin refrescar —habría
  enseñado el estado de la última vez que se abrió el otro menú— y hay prueba que
  lo ve en rojo sin el arreglo. Además, poner o quitar el modo saca un mensaje en
  el notch, y la pausa avisa con una notificación al empezar y al volver.

  **Pendiente:** el icono en sí puede seguir oculto. Resolverlo de verdad —avisar
  de que está tapado, o un atajo de teclado para el modo reunión— es trabajo nuevo,
  fuera de esta spec. La comprobación visual del menú real queda pendiente de
  Alberto.
- **El modo reunión no caduca**, por decisión de Alberto. Si se olvida puesto, se
  graba sin cortes hasta que se quite. Lo compensa el icono, con la reserva
  anterior.
- **Una sesión larga se transcribe de golpe al soltar.** Veinte horas son unos
  2,2 GB de audio. El menú lo enseña; resolverlo es la spec 011.
- **El modo reunión no mejora lo que el micrófono capta**, solo evita que se corte.
