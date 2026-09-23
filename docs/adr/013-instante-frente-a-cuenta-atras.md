# ADR 013 — La pausa guarda el instante en que vence, no los minutos que faltan

- Fecha: 2026-09-22
- Estado: Aceptada
- Spec: 010 — Controles rápidos desde el icono de la barra

## Contexto

El usuario puede pausar la bitácora «30 minutos», «1 hora» o «hasta mañana». La
pausa tiene que sobrevivir a que la aplicación se cierre, se reinicie o a que el
equipo se suspenda, y tiene que volver sola: una pausa que no vuelve deja de
grabar sin que nadie lo note.

## Decisión

Se guarda en `bitacora_pausada_hasta` el **instante** de vencimiento, en segundos
desde la época. Un vigía (`DispatchSourceTimer` en cola propia) compara ese
instante contra el reloj cada 15 s y reanuda cuando pasa. Al abrir la aplicación
se comprueba igual: si ya venció con la aplicación cerrada, se reanuda y se avisa.

## Alternativa descartada: guardar los minutos que faltan y descontarlos

Guardar «quedan 50 minutos» y restar mientras la aplicación corre.

Se descarta porque una cuenta atrás **se congela** cuando nadie la descuenta. Una
pausa de media hora con la aplicación cerrada veinte minutos duraría cincuenta:
sería media hora de aplicación abierta, no de reloj, que no es lo que nadie
entiende por «media hora». Y la suspensión del equipo necesitaría un tratamiento
aparte que con un instante no hace falta: o ya venció, o no.

## Consecuencias

- Cerrar, reiniciar o suspender no altera cuándo vence la pausa.
- Comprobado con la alternativa como sabotaje: guardar los segundos que faltan y
  sumarlos al cargar pone en rojo las pruebas del reinicio y de la suspensión.
- Medido con el vigía real y un reinicio en medio: la pausa volvió 11,4 s después
  de su hora (límite: 60 s).
- Un cambio de hora del reloj del sistema desplaza el vencimiento con él. Se acepta:
  es el comportamiento que cualquiera espera de «hasta las 22:11».
