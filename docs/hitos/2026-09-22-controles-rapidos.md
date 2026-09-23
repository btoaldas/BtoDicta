# Hito — Controles rápidos desde el icono: modo reunión y pausa de la bitácora

> **Corrección, 2026-09-22 (spec 011).** Lo que se dice aquí sobre una «barra de
> menús llena» era **falso**: quedaban 257 puntos libres. El icono estaba oculto
> porque macOS 26 lo había apuntado a nombre del programa que ejecutó el binario
> del paquete —las propias pruebas, desde una terminal bloqueada en la barra—, y
> ese apunte persiste para los arranques normales. Causa y corrección en
> `docs/specs/011-el-icono-de-la-barra-no-puede-quedar-a-nombre-de-otra-aplicacion/`.
> El resto de este documento se deja tal como se escribió.


- Fecha: 2026-09-22
- Spec: 010 — Controles rápidos desde el icono de la barra (nivel P)
- Versión: 0.80.0
- RF satisfechos: RF-01 a RF-08 (RF-03 con reserva medida, ver riesgos)
- RNF satisfechos: los cuatro

## Qué se consiguió

Dos controles donde ya se mira, sin pasar por Ajustes:

- **Modo reunión.** Mientras está puesto, el dictado no se cierra por silencio ni
  por duración y no interrumpe. Se puede poner con la grabación ya empezada, y
  sigue en la misma grabación sin perder nada. Quitarlo devuelve lo de siempre sin
  cerrar de golpe, y sin haber tocado un solo ajuste del usuario.
- **«No mirar durante…».** Pausa la bitácora un rato elegido y vuelve sola a su
  hora, aunque la aplicación se cierre o el equipo se reinicie en medio. Un dictado
  en mitad de la pausa no la cancela.

Y el icono dice en qué estado se está, por forma: micrófono, dos personas, dos
personas con ondas, pausa. El menú enseña además cuánto se lleva grabado y cuánto
se va a transcribir al soltar.

Nace de una reunión de una hora, el mismo día, que quedó troceada en once
grabaciones porque evitarlo exigía abrir Ajustes delante de la gente.

## Cómo se comprobó

Cinco pruebas nuevas en el QA, todas vistas en rojo contra el código saboteado, y
todas contra carpeta aislada —se niegan a correr sin ella—:

| Prueba | Qué demuestra | Su rojo |
|---|---|---|
| `pausa_bitacora` | Con pausa entran 0 bytes; un dictado entero en medio no la cancela; vuelve sola | Sin las cerraduras del micrófono, ese dictado escribe 399 968 bytes durante la pausa |
| `reunion_no_corta` | Activado a punto de cortarse, sigue la misma grabación; al quitarlo no cierra de golpe | Sin el punto de corte, se corta a los 4 s; sin reiniciar la ventana, se cierra de golpe |
| `modo_rapido` | Desde FUERA del programa: 0 ajustes cambiados, y la pausa vence a su hora tras un reinicio (+11,4 s) | El modo escribiendo en el corte de silencio; un vigía que no arranca |
| `icono_estados` | Cuatro estados distinguibles, plantilla sin tinte | — (amplía una prueba previa) |
| `menu_rapido` | Pulsa los elementos del menú como el usuario; los bytes del menú son los del disco salvo 44, la cabecera WAV; el Dock enseña el estado real | Sin refresco del menú, 5 fallos; el Dock copiando sin refrescar |

QA de 30 a 35 pruebas; suite Swift de 35 a 47.

## Desviaciones respecto a la spec

- **Prioridad del icono precisada**: dictando manda el dictado, porque la pausa no
  lo toca y ocultar «grabando» sería peor; en reposo, la pausa gana a la reunión.
- **RNF-04 mide claves preexistentes**, declarado en el plan antes de escribir código.
- **T12** prueba el formato de sesiones largas sobre una función pura (10 min,
  3 h, 20 h) en vez de grabar diez minutos en vivo.
- **Menú del Dock**: no estaba en la spec. Se añadió al medir que el icono estaba
  oculto en el equipo de desarrollo (ver riesgos): sin él, en ese equipo, los
  controles no habrían sido alcanzables.

## Riesgos residuales

- **Con la barra de menús llena, macOS esconde el icono de BtoDicta sin avisar.**
  Medido: estaba en (2, 981), fuera de la barra. El Dock ofrece los mismos
  controles con el estado real; el icono en sí puede seguir sin verse.
- **El modo reunión no caduca**, por decisión de Alberto.
- **Una sesión larga se transcribe de golpe al soltar**: veinte horas son unos
  2,2 GB. Lo resuelve la spec de transcripción por tramos (por crear).
- **El modo reunión evita el corte, no mejora lo que capta el micrófono.**
- **La vista del menú real no se capturó**: el clic automático no alcanzó el icono
  oculto. Pendiente de comprobación visual de Alberto.

## Lecciones

- Una prueba que mira a un tiempo fijo puede pasar sin pasar por el código que
  dice probar: el temporizador del dictado late cada 5 s, no cada medio segundo.
- Un sabotaje que no rompe nada no prueba la prueba: un `return` suelto en Swift
  se une a la línea siguiente, y el «sabotaje» dejaba el vigía funcionando.
- Una comprobación que pasa por el estado que dejó el paso anterior no comprueba
  nada: la primera prueba del Dock pasaba sin el arreglo porque se había abierto
  el otro menú justo antes.
