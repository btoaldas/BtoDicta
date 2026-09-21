# Checklist de calidad — Spec 009

Pruebas unitarias del texto: preguntan por la calidad de los requisitos, no
por el comportamiento del sistema. Nivel X: se pasa ANTES de la puerta 1.

- [x] CHK01 ¿Cada RF tiene actor, acción, resultado y medida? [Completitud]
      `verificar-spec.py` sale 0 con 6 RF y 5 RNF, sin errores ni avisos.
- [x] CHK02 ¿Cada criterio de aceptación es ejecutable por alguien que no escribió la spec? [Claridad]
      Los seis se apoyan en cifras comprobables contra la bitácora real: 177,2 MB,
      112,6 MB, 57 403 anotaciones, 22 páginas del navegador, 300 ms.
- [x] CHK03 ¿Hay algún adjetivo sin cifra («rápido», «seguro», «fácil») en un RNF? [Medibilidad]
      No: 300 ms, 0 MB duplicados, 0 consultas sin token, 1 ejecución, 1 copia.
- [x] CHK04 ¿El no-alcance dice por qué? [Completitud]
      Las cuatro exclusiones llevan razón; la semántica además explica qué exigiría
      (vectores, modelo cargado, decisión de coste).
- [x] CHK05 ¿Los casos límite cubren entrada vacía, duplicada, concurrente y sin permiso? [Cobertura]
      Vacía: búsqueda vacía o de una letra. Duplicada: la misma anotación
      reconocida dos veces — hoy el alta en el índice no borra lo anterior y el
      mecanismo permite duplicar, aunque se midieron 0 duplicadas. Concurrente:
      búsqueda mientras la bitácora escribe, y el cambio de forma con la aplicación
      abierta, que no se ejecuta. Sin permiso: consulta sin token o con token
      inválido.
- [x] CHK06 ¿Se contradicen dos RF o un RF con un límite del MANIFIESTO? [Consistencia]
      No. El RF-05 (dejar de duplicar) y el RF-01 (buscar en 300 ms) no chocan: lo
      que desaparece es la copia del texto, no el índice que hace rápida la
      búsqueda. Conviene comprobarlo con medida en la fase 5, no darlo por hecho.
- [x] CHK07 ¿Algún RF describe una solución en vez de un comportamiento? [Separación spec/plan]
      No. La forma concreta de dejar de duplicar el texto es del plan y va a ADR.
      `verificar-spec.py` no marca A02.
- [x] CHK08 ¿LOPDP y SRI tienen un aplica / no aplica razonado? [Cumplimiento]
      §7: datos personales sí, con el razonamiento de que esta spec no añade ni un
      dato nuevo —hace consultable lo ya guardado—; SRI no aplica, no cobra.
- [x] CHK09 ¿Queda algún [PENDIENTE DE DECISIÓN]? [Puerta]
      Cero: las cinco decisiones se cerraron en la puerta del 2026-09-21.
- [x] CHK10 ¿Cabe en dos páginas y ≤ 12 RF? [Tamaño]
      6 RF, 5 RNF, ~210 líneas.

## Riesgos que el checklist no cubre y hay que decir en voz alta

1. **La migración es conjunta con la spec 008 y toca la bitácora real**
   (177,2 MB, ~57 400 anotaciones indexadas). Un respaldo, un ensayo sobre copia,
   una ventana de riesgo — y **un visto bueno propio y separado de Alberto** en el
   momento de correrla, distinto de aprobar esta spec.
2. **La bitácora está viva mientras se mide**: entre dos consultas separadas por
   minutos aparecieron 101 anotaciones nuevas. La migración exige BtoDicta parada,
   y eso entra en el plan como precondición, no como recomendación.
3. **El RF-03 (preguntar por voz) es P3 y puede aplazarse** sin tocar el resto.
   Si el plan se alarga, es lo primero que se corta — dejándolo escrito, no en
   silencio.
