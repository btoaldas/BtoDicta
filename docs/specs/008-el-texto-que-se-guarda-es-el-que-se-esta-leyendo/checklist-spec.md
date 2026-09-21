# Checklist de calidad — Spec 008

Pruebas unitarias del texto: preguntan por la calidad de los requisitos, no
por el comportamiento del sistema. Nivel X: se pasa ANTES de la puerta 1.

- [x] CHK01 ¿Cada RF tiene actor, acción, resultado y medida? [Completitud]
      `verificar-spec.py` sale 0 con 5 RF y 6 RNF, sin errores ni avisos.
- [x] CHK02 ¿Cada criterio de aceptación es ejecutable por alguien que no escribió la spec? [Claridad]
      Los cinco citan una página concreta y medible (178 249 caracteres, leída por
      la mitad) o un recuento comprobable (29 605 anotaciones).
- [x] CHK03 ¿Hay algún adjetivo sin cifra («rápido», «seguro», «fácil») en un RNF? [Medibilidad]
      No: 1 MiB, 100 ms, 10 s, 40 informes, 2 MB/día, 0 apariciones, 1 vez.
- [x] CHK04 ¿El no-alcance dice por qué? [Completitud]
      Las cuatro exclusiones llevan razón; la de «guardar la página entera» lleva
      además la medida que la descarta (9x el tope para el caso medido).
- [x] CHK05 ¿Los casos límite cubren entrada vacía, duplicada, concurrente y sin permiso? [Cobertura]
      Vacía: página sin texto visible. Duplicada: misma dirección dos veces (RF-03).
      Concurrente: la misma dirección en dos pestañas a la vez. Sin permiso: dominio
      excluido, y BtoDicta cerrada o sin token.
- [x] CHK06 ¿Se contradicen dos RF o un RF con un límite del MANIFIESTO? [Consistencia]
      No. El RF-04 (tope ajustable) y el RNF-01 (1 MiB por informe) conviven porque
      el tope del informe lo impone la API y acota al ajuste, no al revés — eso
      pasa al plan como restricción, no como contradicción.
- [x] CHK07 ¿Algún RF describe una solución en vez de un comportamiento? [Separación spec/plan]
      No. Ni «desplazamiento», ni «índice», ni «acumulador» aparecen como
      requisito: el cómo es del plan. `verificar-spec.py` no marca A02.
- [x] CHK08 ¿LOPDP y SRI tienen un aplica / no aplica razonado? [Cumplimiento]
      §7: datos personales sí, con el razonamiento de que esta spec cambia cuánto
      texto se guarda y no de qué clase; SRI no aplica, no cobra.
- [x] CHK09 ¿Queda algún [PENDIENTE DE DECISIÓN]? [Puerta]
      Cero: las cuatro decisiones abiertas se cerraron en la puerta del 2026-09-21
      y están en §9 con su razón.
- [x] CHK10 ¿Cabe en dos páginas y ≤ 12 RF? [Tamaño]
      5 RF, 6 RNF, ~190 líneas.

## Riesgo que el checklist no cubre y hay que decir en voz alta

El RF-05 obliga a cambiar la forma en que la bitácora garantiza que una captura
no se anota dos veces, y eso se ejecuta **sobre la base viva del equipo**
(192 MB, 29 605 anotaciones). Es una mutación de datos reales: exige respaldo
previo verificado y un visto bueno propio y separado de Alberto en el momento de
correrla, distinto de aprobar esta spec.
