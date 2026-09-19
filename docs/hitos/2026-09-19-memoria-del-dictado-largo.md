# Hito — Memoria del dictado largo

- Fecha: 2026-09-19
- Spec: 001 — Memoria del dictado largo (nivel X)
- Versiones: 0.63.4 (grabador y audio de trabajo) · 0.63.5 (los doce envíos)
- RF satisfechos: RF-01, RF-02, RF-03, RF-04, RF-05 — los cinco
- RNF satisfechos: RNF-01, RNF-02, RNF-03, RNF-04 — los cuatro

## Qué se consiguió

Un dictado de seis horas ocupaba cerca de **2 GB** de memoria repartidos en tres
etapas. Ahora ocupa **80 MB**.

| Etapa | Antes | Ahora |
|---|---|---|
| Grabar 6 h | +661 MB | +13 MB |
| Soltar la tecla | +662 MB | +3 MB |
| Preparar el envío | +659 MB | +0 MB |

El audio se escribe al archivo según entra y viaja como ruta hasta el motor, que
lo sube desde disco. Solo se lee entero para guardarlo en el historial, ya con la
transcripción hecha.

## Desviaciones respecto a la spec

**Una, y de fondo.** El plan aprobado suponía que la primera etapa (0.60.0) había
resuelto la memoria al grabar, porque así lo decía la spec con una medición de
0 MB en seis horas. Al migrar el primer motor se descubrió que esa medición
**probaba otro componente**: construía un `HistoryWriter` y le pasaba los trozos
directamente, sin recorrer nunca el grabador del dictado, que sí retenía todo lo
hablado.

Corregir eso exigía tocar el grabador, que estaba fuera de lo aprobado. Se detuvo
el trabajo, se anotó el hallazgo con fecha en `plan.md` §9 y se pidió decisión;
autorizada, se hizo en `main` y quedó como fase A-bis.

Segunda desviación, menor: el barrido del audio de trabajo no estaba en el plan.
Apareció porque el propio cambio lo hizo necesario —el dictado pasa a ocupar
disco—, y se resolvió con un ajuste configurable en vez de un valor fijo.

## La lección

Una prueba que no recorre el camino del usuario no dice nada sobre el camino del
usuario. El «0 MB en seis horas» era una cifra correcta sobre algo que a nadie le
importaba, y sostuvo durante tres versiones la creencia de que el problema estaba
resuelto. La prueba corregida **da rojo** contra el código anterior, que es la
única forma de saber que mide algo.

Por eso la fase A fue la red de seguridad y no el cambio: antes de tocar un solo
motor se comprobó byte a byte que el cuerpo nuevo era idéntico al viejo.

## Riesgos residuales — los cuatro cerrados el 2026-09-19 (0.63.7)

1. ~~El historial lee el audio entero al guardarlo.~~ **Resuelto**: lo adopta
   moviéndolo. 0 MB medidos.
2. ~~Los motores locales reciben el audio en memoria.~~ **Resuelto**: lo reciben
   por enlace duro, comprobado por número de nodo del sistema de archivos.
3. ~~El audio de trabajo se acumula.~~ **Resuelto por el punto 1**: deja de
   existir donde estaba en cuanto pasa al historial. El barrido por antigüedad
   queda como red para lo que no llegue a moverse, no como única defensa.
4. ~~Sin auditar el resto de la aplicación.~~ **Auditada**: el patrón había
   vuelto en trece sitios. Retirado en todos, y vigilado desde el QA por
   `scripts/qa-conexion-compartida.py`.

Al cerrarlos apareció **un fallo que podía perder un dictado**: dos dictados en
el mismo segundo compartían archivo y el segundo pisaba al primero. Estaba
anotado como pendiente menor; con la adopción por movimiento dejaba de serlo.
Corregido y con prueba.

## Evidencia

- `BTODICTA_MEMTEST=6` — las tres etapas medidas, y en rojo contra el código anterior
- `BTODICTA_SUBIDATEST=1` — cuerpo idéntico byte a byte en 1 s, 1 min y 1 h
- `BTODICTA_FISHTEST=1` — recorrido completo con voz sintética
- `PARTIRTEST`, `TROCEOTEST`, `REDTEST2`, `ROBUSTEZTEST`, `CANCELTEST`, `MICTEST`
- Uso real: dos dictados del usuario el 2026-09-18, entregados completos
- Detalle RF por RF en `verificacion.md`
