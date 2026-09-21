# ADR 009 — Una sola función de búsqueda, tres maneras de llamarla

- Fecha: 2026-09-21
- Estado: Aceptada
- Spec: 009 — Buscar por palabras en la bitácora

## Contexto

Alberto decidió el 2026-09-21 que la búsqueda se pueda usar desde tres sitios: la
pestaña de la bitácora, la API local y el agente por voz. Tres entradas invitan a
escribir tres consultas, y entonces cada fallo hay que arreglarlo tres veces.

## Decisión

Una única función de búsqueda sobre el índice. Las tres entradas la llaman y solo
se diferencian en cómo presentan el resultado. La búsqueda se hace **sobre el
índice**, no recorriendo el texto guardado.

## Alternativa descartada: recorrer el texto guardado

No necesitaría el índice en absoluto, y tiene el atractivo de eliminar una pieza.

Se descarta por tres razones medidas: son 48,4 MB de texto que recorrer en cada
consulta; no hay forma de ordenar por relevancia; y se perdería la normalización
de acentos y mayúsculas que el índice ya hace. Teniendo el índice construido, al
día y sano —0 duplicadas, 0 huérfanas—, recorrer el texto a mano sería tirar algo
que ya funciona.

## Consecuencias

- El agente de voz queda como prioridad P3: si el plan se alarga, es lo primero
  que se corta, y se corta **por escrito**, no en silencio.
- La entrada por la API amplía la superficie que hay que proteger. Va tras el
  mismo token que el resto, con prueba negativa de token ausente e inválido.
- La frase de la pantalla de ajustes que ya promete buscar por palabras sueltas
  deja de ser una promesa incumplida.
