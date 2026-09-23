# ADR 016 — El icono oculto se detecta por su posición; la tercera fn se arma al soltar la segunda

- Fecha: 2026-09-22
- Estado: Aceptada
- Spec: 012 — Red de seguridad del icono y triple fn para el modo reunión

## Contexto

Aunque la spec 011 quita la causa por la que el icono desaparecía, macOS puede
seguir escondiéndolo: el usuario lo desactiva en Ajustes, no cabe, o queda bajo la
muesca. `NSStatusItem.isVisible` sigue diciendo `true` en todos esos casos. Con el
modo reunión puesto, que no caduca, un icono escondido deja al usuario sin forma de
saber que el dictado no se va a cortar.

Y hace falta un modo de poner el modo reunión sin el icono. El usuario eligió la
triple pulsación de fn, que choca con el doble fn que arranca el dictado.

## Decisión 1 — Escondido es «no está en la franja de la barra»

La ventana del icono, en coordenadas globales, tiene que estar en la franja entre
la parte útil de su pantalla (`visibleFrame.maxY`) y el borde superior, y fuera de
la muesca (`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`). Fuera de toda
pantalla, sin ventana, en mitad de la pantalla o bajo la muesca → oculto.

Si la barra no está dibujada —su ventana no está en pantalla, o una ventana normal
ocupa una pantalla entera— **no se sabe**, y no se avisa. Si la barra se oculta
sola (`visibleFrame` llega al borde), tampoco.

Medido en el equipo: visible en (1086, 949) con la barra de y = 949 a 982; el mismo
icono, alargado hasta no caber, lo lleva macOS a (-1896, 949), fuera de toda
pantalla. El escondido de la spec 011 estaba en el borde inferior.

### Alternativa descartada: la oclusión de la ventana

`occlusionState` dice «no visible» con el icono escondido, pero también con la
pantalla dormida o bloqueada, y con otras ventanas por encima. Avisaría cada noche.
La posición es lo que el usuario ve.

## Decisión 2 — La tercera fn se arma al soltar la segunda

La segunda pulsación sigue arrancando el dictado al bajarla, como siempre. Al
soltarla, si fue la que arrancó (en modo toque y sin usarse como modificador), se
arma una segunda compuerta `DoublePressGate`. La pulsación siguiente, si baja
dentro de la misma ventana del doble, cambia el modo reunión y no detiene.

La compuerta se consulta **antes** de mirar si se está grabando: el arranque es
asíncrono (unos 160 ms), y una tercera rápida puede llegar antes que la grabación.

### Alternativa descartada: esperar la ventana tras la segunda

Retrasaría todos los dictados 0,45 s para distinguir un doble de un triple.

### Consecuencia aceptada

Quien arranque con doble fn y pulse fn otra vez en menos de 0,45 s para parar
pondrá el modo reunión. El notch lo dice en el acto y otra pulsación detiene.

## Consecuencias

- El vigía del icono, que ya latía cada 2 s, además mide y decide. Leer la lista de
  ventanas cuesta poco y no necesita permisos: solo se usan capa y tamaño.
- Nada escribe en ajustes del sistema. El aviso dice cómo arreglarlo; lo arregla el
  usuario.
- La triple fn solo existe con el doble fn activado y en modo toque.
