# Hito — El icono de la barra ya no puede quedar a nombre de otra aplicación

- Fecha: 2026-09-22
- Spec: 011 — corrección (nivel P)
- Versión: 0.80.1
- RF satisfechos: RF-01 a RF-04 · RNF-01 y RNF-02
- Desviaciones respecto a la spec: el rojo de RF-01 se mostró con una aplicación
  desechable, no con BtoDicta real, para no envenenar el icono del usuario; se
  añadió `Log.vaciar()`

## Qué se consiguió

El icono de BtoDicta estaba oculto con la barra medio vacía. No era falta de
espacio —eso fue lo que se dijo en la 0.80.0, y era falso—: macOS 26 lo había
apuntado a nombre de Claude Code, que está bloqueado en la barra, porque las
pruebas ejecutaban el binario del paquete desde esa terminal. El apunte persistía
en los arranques normales, y un script de julio lo reparaba reescribiendo los
ajustes de la barra, para que la siguiente prueba lo volviera a romper.

Ahora la causa no puede darse: BtoDicta solo registra su icono si la abre el
sistema. Si la lanza otro programa, funciona sin icono y dice por qué. Las pruebas
que necesitan el icono la abren como el sistema.

## Cómo se supo

Descartando antes de afirmar: había 257 puntos libres (no era espacio), la fila de
BtoDicta estaba permitida (no era la configuración), Ice estaba apagado. Luego, un
experimento con una aplicación desechable de identificador propio, para no tocar
BtoDicta: con `open`, suya y visible; ejecutada directa, colgada de Claude Code;
otra vez con `open`, sigue oculta.

## Evidencia

- 20 arranques directos del binario: 0 filas ajenas, motivo escrito 20/20.
- Abierta por el sistema: icono en (1154, 4), también tras un QA completo lanzado
  desde la terminal bloqueada.
- El QA falla si el icono queda apuntado a nombre de otro, diciendo de quién.
- Ninguna escritura en ajustes del sistema durante todo el trabajo.

## Riesgos residuales

- BtoStats, BtoStatsTest, siprobe y Neptunus siguen colgadas de Claude Code: otras
  aplicaciones, mismo fallo.
- `make reparar-icono` sigue en el instalador hasta que se decida retirarlo. **Retirado el 2026-09-24** con el sí de Alberto; queda solo a mano.
- La mediana de texto de la extensión frente al OCR bajó a 0,9× (spec 006): ajena a
  esto, se deja en rojo.

## Lecciones

- **Antes de parchear un síntoma que vuelve, buscar qué lo dispara.** El script de
  julio llamaba al problema «bug de Control Center» y lo limpiaba en cada
  instalación. Lo disparaban nuestras propias pruebas.
- **Un registro asíncrono pierde lo último que se escribe antes de un `exit()`.** La
  primera medida dijo que la cerradura no dejaba motivo; sí lo dejaba, pero no
  llegaba al disco.
- **`open -W` no devuelve el código de salida de la aplicación.**
