# Spec 002 — Corrección: Cancelar un dictado no puede borrar el audio

- Estado: Implementada (0.59.1 y 0.59.2)
- Tipo: correccion
- Nivel: X
- Fecha: 2026-09-14
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-14 — «vamos de los tres [pendientes] el que sea más rápido»; RF-01 era «de ley»

## 1. Reproducción

- Pasos exactos:
  1. Empezar a dictar con BtoDicta.
  2. Sin soltar la tecla de dictado, abrir una vista previa de macOS (Quick Look,
     una carpeta, una ventana cualquiera) y pulsar **Escape** para cerrarla.
  3. BtoDicta se queda con esa pulsación y cancela el dictado.
- Comportamiento actual: el dictado se cancela y el audio **se borra del disco**.
  En `HistoryWriter.discard()`: `FileManager.default.removeItem(at: pcmURL)` y lo
  mismo con el `.txt`. No queda nada que recuperar ni en el historial ni en la
  pestaña de transcribir.
- Comportamiento esperado, en palabras del responsable del producto: «pase lo que
  pase, es decir, cierra BtoDicta, cancela la grabación, pero que la grabación no
  se pierda, que la grabación sí se guarde y podamos recuperarla en base a los
  procedimientos que ya existen».

## 2. Alcance de la corrección

- Incluye: qué ocurre con el audio al cancelar un dictado; que Escape deje de
  robarle la tecla a la aplicación que está delante; y un aviso de confirmación
  opcional antes de cancelar.
- No incluye: cambiar la tecla de dictado ni el resto de atajos globales.

## 3. Causa raíz

Dos defectos encadenados, ambos confirmados leyendo el código:

1. **Escape es un atajo GLOBAL mientras se graba.** `armEsc()` hace
   `RegisterEventHotKey(kVK_Escape, …)`, que lo captura en todo el sistema. Por
   eso «BtoDicta gana» cuando el usuario solo quería cerrar una ventana ajena.
   Existe el ajuste `esc_cancela` para apagarlo del todo, pero viene puesto y no
   distingue si el usuario está mirando otra aplicación.
2. **Cancelar destruye la grabación.** `cancelDictation()` llama a
   `history?.discard()`, que **borra** el `.pcm` y el `.txt` del disco. No los
   abandona: los elimina. Eso contradice dos reglas del MANIFIESTO — «el audio
   grabado no se pierde nunca» y «nada se borra sin visto bueno explícito».

## 4. Requerimiento afectado

### RF-01 — Cancelar conserva el audio y se puede recuperar

- Actor: quien dicta
- Acción: cancela un dictado en curso, por Escape, por clic en el notch o por
  cualquier otra vía
- Resultado: el dictado se detiene, pero el audio grabado queda guardado y
  aparece donde ya se recuperan los dictados (historial y pestaña de transcribir)
- Medida: tras cancelar, el archivo de audio existe y figura en el historial
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado de al menos cinco segundos en curso
  - Cuando se cancela por cualquier vía
  - Entonces el audio sigue en disco, aparece en el historial y se puede
    transcribir después

### RF-02 — Escape no le quita la tecla a la aplicación de delante

- Actor: quien usa el Mac mientras dicta
- Acción: pulsa Escape con otra aplicación en primer plano
- Resultado: esa aplicación recibe su Escape; el dictado no se cancela
- Medida: con otra aplicación al frente, Escape no cancela el dictado
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado en curso y una ventana de otra aplicación en primer plano
  - Cuando se pulsa Escape
  - Entonces se cierra esa ventana y el dictado continúa

### RF-03 — Confirmación opcional antes de cancelar

- Actor: quien dicta
- Acción: cancela un dictado teniendo activado el aviso
- Resultado: se le pregunta «¿Deseas cancelar la grabación?» y decide
- Medida: con el ajuste puesto, cancelar exige un sí; con el ajuste quitado,
  cancela directo
- Prioridad: P2
- Criterio de aceptación:
  - Dado el aviso activado y un dictado en curso
  - Cuando se cancela
  - Entonces se pregunta, y si se responde que no, el dictado sigue grabando sin
    haber perdido nada

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Disponibilidad | 0 audios borrados al cancelar, en 10 cancelaciones seguidas | Prueba propia que cancela y comprueba el archivo |
| RNF-02 | Usabilidad | La confirmación es parametrizable; pendiente de implementar (RF-03, P2) | Ajuste en Configuración |
| RNF-03 | Capacidad | El audio conservado se purga a los 90 días, igual que el resto del historial, ni un día antes | Revisión de la purga |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| Se cancela un dictado de medio segundo, por error al pulsar | Se descarta: por debajo de `cancelar_conserva_desde_s` (2 s por defecto) no hay nada que conservar y ensuciaría el historial | RF-01 |
| Se cancela mientras el motor en vivo ya escribía texto | El texto parcial se conserva junto al audio | RF-01 |
| El usuario cancela a propósito porque se equivocó de dicción | Puede borrarlo a mano desde el historial, como cualquier otro | RF-01 |

## 7. Datos y cumplimiento

- Datos que trata: audio de voz y su texto, del propio usuario, en su equipo.
- Datos personales: sí. El cambio **aumenta** lo que se conserva: audio que antes
  se destruía ahora se guarda. Se hereda la purga del historial.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- El rescate de huérfanos (`HistoryWriter.rescatarHuerfanos`) ya sabe convertir un
  `.pcm` suelto en un `.wav` recuperable al arrancar.
- El historial y la pestaña de transcribir ya muestran dictados anteriores: no
  hace falta una vista nueva.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-14

- P: ¿Qué debe pasar al cancelar? → R: «el primer punto… es así va de ley»: la
  grabación no se pierde y se puede recuperar por lo que ya existe (decisión del
  responsable del producto)
- P: ¿Y la confirmación? → R: idea aparte y parametrizable — «podríamos verle la
  opción de que si yo pongo X y va a cerrar BtoDicta, que me confirme»
  (decisión del responsable del producto)

## 10. Estado de implementación

| RF | Estado | Evidencia |
|---|---|---|
| RF-01 — cancelar conserva el audio | **Hecho** en 0.59.1 | `BTODICTA_CANCELTEST=1`, 8 de 8 |
| RF-02 — Escape no roba la tecla | **Hecho** en 0.59.2 | `BTODICTA_CANCELTEST=1`. Solución adoptada: Escape exige repetirse dentro de 0,8 s. `RegisterEventHotKey` se queda la tecla en todo el sistema y no hay forma de devolvérsela a la otra aplicación sin dejar de vigilarla; con la doble pulsación, un Esc suelto deja de cancelar, que es el daño real |
| RF-03 — confirmación opcional | **Hecho** en 0.59.2 | `cancelar_confirma`, apagado por omisión. Se confirma repitiendo la acción en vez de con un cuadro de diálogo: un modal a mitad de dictado interrumpe más de lo que protege |
