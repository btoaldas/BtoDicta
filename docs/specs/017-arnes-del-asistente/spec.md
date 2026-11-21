# Spec 017 — Arnés del asistente: gobernanza, habilidades, memoria y evaluación

- Estado: En implementación (fase 1 hecha; fases 2–4 pendientes)
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-11-21
- Modifica: 014, 016 (el modo «Todo» pasa a trabajar sobre el arnés)
- Pedido: Alberto — 2026-11-21 — «funciona un 30 %… toca hacer un arnés… que tenga memoria, skills, gobernanza… que sepa todas las funciones de BtoDicta… la forma de contestar es distinta de lo que hace»
- Rama: `main`

## 1. Diagnóstico (prueba real del 2026-11-21, 02:25–02:36)

| Causa | Evidencia en `logs/agente.jsonl` |
|---|---|
| La conversación se corta | Tras cada acción vuelve a escuchar, pero el corte por silencio la cierra si el usuario piensa; sin señal de escucha. El usuario repite y se **duplican** recordatorio, tarea y evento. |
| Tono técnico | Resúmenes de terminal tipo registro («se ejecutó… código 0»). |
| Promete sin hacer | «Reviso tu agenda de esta semana» sin herramienta. |
| Caminos que chocan | La regla vieja de calendario (Apple) creó un evento con toda la frase como título; luego Graph creó otro. |
| No conoce BtoDicta | «¿Qué tareas hay?» abrió Recordatorios; «crea un Word» usó el modo oficio (pega texto). |
| Inventa lo normativo | Numeró un oficio («N.° 001-2026-…»). La numeración nunca sale de la IA. |
| Fallos sueltos | «Silencia la computadora» → «no obtuve respuesta del cerebro»; Gmail personal no se puede leer. |

## 2. Qué es el arnés

Una carpeta que viaja con la instalación y que el usuario puede ampliar. El
asistente arma su contexto desde ahí en cada turno; lo que ejecuta sigue siendo
código determinista de BtoDicta.

```
~/.btodicta/arnes/
  gobernanza.md        reglas duras (nada se envía, borra ni firma sin OK; sin numeración inventada)
  persona.md           cómo HABLA Beto (colega, breve, alegre…) — distinto del tono de los documentos
  habilidades/         una ficha por capacidad de BtoDicta, GENERADA del código en cada arranque
  habilidades-propias/ fichas del usuario (recetas, rutinas, procedimientos de su trabajo)
  memoria.md           datos duraderos del usuario (institución, dominios, preferencias); se amplía con «recuerda que…», con confirmación
  evaluacion/          casos de prueba con la herramienta esperada
```

- **Arnés de BtoDicta** (fijo, se regenera): gobernanza base y fichas generadas
  del catálogo real (modos, acciones, rutinas y recetas, atajos, música,
  herramientas de Microsoft, tareas, bitácora, historial, transcripción).
- **Arnés del usuario** (editable, nunca se pisa): persona, memoria, fichas
  propias y reglas extra. Se edita desde Ajustes → Asistente o como archivos.

## 3. Cómo cambia el turno

1. Reglas fijas primero (como hoy), pero en el modo IA **un solo camino**: si hay
   cuenta Microsoft, calendario y correo van por Graph; no se ejecutan dos.
2. Se eligen las 3–6 fichas relevantes (palabras clave y embeddings locales) y
   entran al prompt con la gobernanza, la persona y la memoria.
3. La IA elige UNA herramienta con sus datos; el código la ejecuta.
4. **Voz de Beto**: el resultado se dice con la persona (frase corta y
   natural, con etiquetas de emoción de ElevenLabs v4 si están activas). El
   documento conserva su propio tono (formal, oficio…).
5. Conversación: señal sonora al volver a escuchar y margen de silencio mayor
   en turnos de conversación; un pedido repetido dentro de 30 s no se ejecuta dos
   veces sin preguntar.

## 4. Herramientas deterministas nuevas (scripts de BtoDicta)

- Documento Word con plantilla (memo, oficio, informe) sin numeración inventada;
  Excel desde tabla; listar tareas de BtoDicta; leer historial y bitácora;
  transcribir un archivo; silenciar y volumen (ya existen, se exponen como fichas).

## 5. Evaluación (el arnés de pruebas)

- `evaluacion/casos.json`: pedido → herramienta esperada (los 37 casos de esta
  sesión como base). Un comando corre todos contra el modelo elegido **sin
  ejecutar nada** y da el porcentaje. Cada cambio se mide antes de instalarlo.

## 6. Fases propuestas

1. **Conversación y voz**: corte por silencio, señal de escucha, anti-duplicados,
   un solo camino de calendario, persona hablada editable. Mide la evaluación
   inicial.
2. **Arnés y habilidades**: carpeta, gobernanza, fichas generadas del código,
   selección de fichas por turno, memoria duradera.
3. **Herramientas deterministas**: Word/Excel con plantilla, tareas de BtoDicta,
   historial, bitácora, transcribir.
4. **Habilidades propias y recetas**: el usuario crea fichas; las rutinas
   portables se exponen como fichas.

## 7. Tareas y evidencia

Fase 1 aprobada por Alberto el 2026-11-21 («Sí, fase 1»).

- [x] Señal «Tink» y «Te escucho» al volver a escuchar; cierre hablado corto («¿Algo más?»).
- [x] Anti-duplicados: la misma acción en menos de 90 s se consulta antes de repetirla.
- [x] Promesa sin acción: un reintento exigiendo la herramienta.
- [x] En el modo «Todo», las reglas fijas solo para lo preciso (volumen, clima, capturas, recordatorios, rutinas); el resto lo decide la IA con el catálogo. Con Microsoft, el calendario va solo por Graph.
- [x] Persona hablada editable (`agente_persona_voz`), distinta del tono de los documentos; regla de no inventar numeración; una sola acción por turno.
- [x] Plazo del cerebro 40 s (antes 15: «silencia la computadora» caducó); «silencia la computadora/el equipo/la Mac» por regla fija.
- [x] Herramienta `tareas_resumen` (tareas de BtoDicta).
- [x] Evaluación automática `EvaluacionAsistenteTests` (25 casos genéricos, reglas + IA, sin ejecutar).

Medición con glm-5.3 y la configuración de Alberto: **68 %** al cerrar los arreglos de conversación; **96 %**, 96 % y **100 %** tras limitar las reglas fijas y agregar la herramienta de tareas (el caso variable es «abre la calculadora», cubierto en la app por el reintento).


Se detallan al aprobar las fases. Línea base: 30 % estimado por Alberto en la
prueba real; la evaluación automática dará la cifra medida.
