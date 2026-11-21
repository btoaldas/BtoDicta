# Spec 019 — Acciones de oficina y habilidades externas

- Estado: En implementación
- Tipo: funcionalidad
- Nivel: P
- Fecha: 2026-11-21
- Modifica: 017 (arnés), 018 (cuentas)
- Aprobada por: Alberto — 2026-11-21 — «Sí, las 5 fases»
- Rama: `main`

## 1. Análisis

### Correo (institucional, personal y negocio)

| Acción habitual | Hoy | Propuesta |
|---|---|---|
| Leer, buscar, resumir, «los N últimos» | sí | — |
| Borrador, cambiar, enviar con confirmación | sí | — |
| Responder y reenviar | solo Microsoft | también Gmail (hilo y `In-Reply-To`) |
| Archivar | sí (a6fa38a) | — |
| Marcar leído / no leído, destacar o marcar para seguimiento | no | sí, sin confirmación (reversible) |
| Mover a una carpeta o etiqueta por nombre | no | sí, con confirmación |
| Eliminar (a la papelera, nunca definitivo) | no | sí, siempre con confirmación; vaciar papelera, nunca |
| Adjuntos: bajar a Descargas y abrir | no | sí, a `~/Downloads/BtoDicta/` sin sobrescribir |
| Adjuntar un archivo a un borrador | no | sí (ruta o «el último de Descargas») |
| Buzón compartido o delegado (Microsoft) | no | sí, como cuenta propia: «el buzón de secretaría» (permiso `Mail.ReadWrite.Shared`, `Mail.Send.Shared`) |
| Cuenta delegada de Gmail | no | no lo permite la API para cuentas personales; se conecta como otra cuenta |
| Abrir el correo en la web | sí | — |

### Oficina en general

| Área | Hoy | Propuesta |
|---|---|---|
| Tareas y recordatorios | sí | — |
| Word y Excel con plantilla | sí | leer un Word o Excel existente y resumirlo o editarlo |
| Firmar PDF | no | preparar la solicitud y abrir el flujo oficial; **firmar nunca sin el «sí, firma» del titular** |
| Descargas centralizadas | no | todo lo que baja el asistente va a `~/Downloads/BtoDicta/` |
| Internet | buscar y abrir | leer una página y resumirla |
| Abrir sesiones de IA (Claude, Claude Code, ChatGPT, Gemini) | parcial (abrir apps) | «abre Claude Code en el proyecto X» con su carpeta |
| Otras IA / conectores | conexiones API (spec 014) | — |

### Habilidades externas (lo nuevo grande)

Inventario real de esta Mac: `~/.claude/skills` 108, `~/.agents/skills` 113,
`~/.codex/skills` 61, `~/.zcode/skills` 148, `~/.gemini/skills` 2 (formato
`SKILL.md` con nombre y descripción).

Propuesta:
- **Fuente primera, siempre:** las habilidades de BtoDicta (generadas y propias).
- **Fuentes externas, opcional y apagado de fábrica.** Al activarlo, la carpeta por
  defecto es la del usuario (`~`), buscando en `.claude/skills`, `.agents/skills`,
  `.codex/skills`, `.zcode/skills`, `.gemini/skills`. El usuario puede agregar o
  quitar carpetas.
- Se leen solo **nombre y descripción** de cada `SKILL.md` para elegir; el cuerpo
  entra al prompt únicamente si la habilidad se selecciona para ese pedido (top-4,
  como hoy).
- **Lo externo es dato, no autoridad:** no puede saltarse confirmaciones, envíos,
  firmas, pagos ni borrados; las reglas de BtoDicta mandan.
- Los scripts de esos skills **no se ejecutan solos**: si una habilidad pide correr
  un script, va por el camino de comandos con la confirmación elegida.
- Nada de esas carpetas se copia al repositorio ni a la memoria de BtoDicta.

## 2. Fases propuestas

1. **Habilidades externas** (carpetas, interruptor, lectura de `SKILL.md`, selección, límites).
2. **Correo II:** marcar, mover, papelera con confirmación, adjuntos a Descargas, adjuntar.
3. **Buzón compartido o delegado de Microsoft** como cuenta.
4. **Responder y reenviar en Gmail.**
5. **Oficina:** leer Word/Excel existentes, resumir una página web, abrir sesiones de IA por proyecto, firmar vía flujo oficial con confirmación del titular.

## 3. No incluye

- Vaciar papelera, reglas automáticas o reenvíos automáticos del buzón.
- Ejecutar scripts externos sin confirmación.
- Firmar por cuenta propia.

## 4. Tareas

- [x] T01 Habilidades externas opcionales (3f9ab13).
- [x] T02 Correo II: marcar, mover, papelera, adjuntos y adjuntar (04b9dac, 3dc1eb4).
- [x] T03 Buzón compartido o delegado de Microsoft (0f16cdd).
- [x] T04 Responder y reenviar en Gmail (1f025bb).
- [x] T05 Oficina: leer Word/Excel/PDF, resumir página, sesiones de IA, firma vía app oficial.
- [ ] T06 Prueba real de Alberto (Gmail requiere reconectar por `gmail.modify`; buzón delegado por conectar).

## 5. Evidencia

- 2026-11-21: `swift test` 219 pruebas, 0 fallos. Evaluación real (glm-5.3) 36/38; los dos casos
  restantes: «archiva esos tres» sin lista previa (pregunta, correcto) y «borra todos los de hoy»,
  que ahora va a la papelera con confirmación (expectativa actualizada).
- Revisión automática de seguridad: cuarentena de adjuntos y rutas reales al adjuntar, corregidas (3dc1eb4).
