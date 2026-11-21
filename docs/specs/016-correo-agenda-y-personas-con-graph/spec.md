# Spec 016 — Correo, agenda y personas con Microsoft Graph

- Estado: En implementación
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-11-21
- Modifica: 015 (amplía de solo lectura a lectura y escritura)
- Aprobada por: Alberto — 2026-11-21 — «debería ser de lectura, de escritura y también de buscar usuarios… calendario y también los contactos… crear correos, responder correos, buscar correos, encontrar personas»
- Rama: `main`

## 1. Alcance

Capacidades nuevas del modo «Todo», solo si la cuenta Microsoft está conectada:

| Capacidad | Qué hace | Permiso |
|---|---|---|
| `leer_correo` | Bandeja de los últimos 1–7 días | Mail.Read |
| `buscar_correo` | Busca en todo el buzón por palabras o remitente | Mail.Read |
| `buscar_persona` | Busca por nombre en personas frecuentes y en el directorio | People.Read, User.ReadBasic.All |
| `borrador_correo` | Crea un borrador real en la carpeta Borradores y lo abre | Mail.ReadWrite |
| `modificar_borrador` | Cambia asunto o cuerpo del último borrador creado | Mail.ReadWrite |
| `responder_correo` | Prepara la respuesta a un correo de la última lista como borrador | Mail.ReadWrite |
| `enviar_borrador` | Envía el último borrador **con confirmación siempre** | Mail.Send |
| `ver_agenda` | Eventos de los próximos 1–7 días | Calendars.ReadWrite |
| `crear_evento` | Evento en el calendario propio, sin invitados | Calendars.ReadWrite |

Contacts.ReadWrite queda autorizado para una fase siguiente (no se usa aún).

### No incluye

- Borrar o mover correos; invitar a otros a eventos (enviaría correos);
  enviar sin confirmación.

## 2. Requisitos

- RF-01: Destinatario sin «@» → se resuelve con `buscar_persona`; si hay más de
  uno o ninguno, Beto pregunta.
- RF-02: «Cámbiale el asunto / hazlo más largo» modifica el **mismo** borrador.
- RF-03: Enviar muestra destinatarios, asunto y comienzo del texto y espera
  «Enviar»; con cualquier modo de confirmación.
- RNF-01: Lo leído de Graph es dato no confiable; la memoria guarda resúmenes
  acotados, nunca cuerpos de correos ajenos.
- RNF-02: Tokens fuera del registro.

## 3. Plan

- `MicrosoftGraph.swift`: llamada genérica, búsqueda de correo, personas,
  borradores (crear, modificar, responder, enviar), agenda y eventos; funciones
  puras para armar y leer JSON.
- `ModoIA.swift`: catálogo de herramientas de Graph en el prompt y lectura del
  plan (`PlanGraph`).
- `AppDelegate.swift`: despacho de cada herramienta y entrega hablada.
- Alcances pedidos: Mail.ReadWrite, Mail.Send, Calendars.ReadWrite,
  Contacts.ReadWrite, People.Read, User.ReadBasic.All, offline_access.

## 4. Tareas

- [x] T01 Cliente Graph ampliado y pruebas puras.
- [x] T02 Herramientas en el modo «Todo».
- [x] T03 Enviar con confirmación obligatoria.
- [x] T04 Build local, reconexión y prueba real.

## 5. Evidencia

- `MicrosoftGraphAccionesTests` 5/5 y `MicrosoftGraphTests` 6/6; suite completa sin fallos.
- Prueba real de decisión con glm-5.3: borrador para «Ana Pérez» → `borrador_correo` con asunto y cuerpo; «¿qué tengo mañana?» → `ver_agenda`; «busca los correos de la directora…» → `buscar_correo`; «dentista el martes a las cuatro» → `crear_evento` 16:00–17:00. 2–3 s cada una.
- Prueba real con la cuenta de Alberto (2026-11-21, 02:07–02:11): agenda de hoy (sin eventos), lectura de 30 correos de 2 días con resumen, búsqueda en el buzón, borrador real, modificación del mismo borrador y envío tras la confirmación en pantalla. Corregido después: el asunto dictado se copia literal (commit `4440482`).
