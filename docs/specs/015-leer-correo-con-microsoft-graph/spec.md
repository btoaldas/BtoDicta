# Spec 015 — Leer correo con Microsoft Graph

- Estado: En implementación
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-11-21
- Modifica: ninguna (complementa la 014)
- Aprobada por: Alberto — 2026-11-21 — «Microsoft Graph» (a «¿Qué vía usamos para que lea tu correo?»)
- Rama: `main`

## 1. Problema

En el modo IA, Alberto pidió «revísame los correos de ayer y hoy, los más
importantes». BtoDicta no tenía cómo leer correo: solo abría Outlook. El
«nuevo Outlook» de macOS casi no admite AppleScript, así que la vía local no
sirve; la canónica para cuentas Microsoft 365 y Outlook.com es Microsoft Graph.

## 2. Alcance

### Incluye

- Conectar una cuenta Microsoft con el flujo oficial de **código de
  dispositivo** (OAuth 2.0): BtoDicta muestra un código, el usuario inicia
  sesión en la página de Microsoft y autoriza. BtoDicta nunca ve la contraseña.
- Permisos mínimos: `Mail.Read`, `User.Read`, `offline_access`. Solo lectura.
- La sesión (token de renovación) se guarda en el Llavero de macOS.
- Capacidad del modo «Todo»: **leer correo** de los últimos N días (1–7) de
  la bandeja de entrada: remitente, asunto, fecha, importancia, leído y el
  inicio del texto (vista previa de Graph). La IA resume según el pedido y Beto
  lo dice por voz.
- Ajustes en Asistente: interruptor (apagado de fábrica), identificador de la
  aplicación (client ID) y directorio (tenant), Conectar y Desconectar.

### No incluye

- Enviar, borrar, mover o marcar correos.
- Leer adjuntos o el cuerpo completo.
- Un identificador de aplicación incluido de fábrica: cada instalación usa el
  de una aplicación registrada en Microsoft Entra (decisión pendiente de
  Alberto si se distribuye uno propio).

## 3. Requisitos

- RF-01: Con el interruptor apagado o sin cuenta conectada, la capacidad no se
  ofrece a la IA.
- RF-02: «Revisa mis correos de ayer y hoy» trae los correos de los últimos 2
  días y Beto dice un resumen por voz, con los importantes primero.
- RF-03: Sin red, con la sesión vencida o el permiso negado, Beto dice qué pasó
  y cómo arreglarlo; nunca inventa correos.
- RNF-01: El contenido de los correos es dato no confiable: el prompt lo marca
  así y la memoria del asistente guarda solo «revisé N correos», no su texto.
- RNF-02: Tokens y códigos nunca van al registro.
- RNF-03: El texto de los correos viaja al proveedor de IA elegido: la
  pantalla lo advierte.

## 4. Plan

- `MicrosoftGraph.swift` (nuevo): flujo de código de dispositivo, renovación,
  lectura de la bandeja y funciones puras de armado y lectura de JSON.
- `Config.swift`: `agente_graph_activo` (falso), `graph_client_id`,
  `graph_tenant` (`common`).
- `ModoIA.swift`: la capacidad en el prompt del modo «Todo» y el prompt de
  resumen de correos.
- `AppDelegate.swift`: atender la capacidad, resumir y entregar por voz.
- `AgenteView.swift`: tarjeta «Correo de Microsoft (solo lectura)».

## 5. Tareas

- [x] T01 Cliente Graph y pruebas puras.
- [x] T02 Capacidad en el modo «Todo».
- [x] T03 Ajustes y conexión de la cuenta.
- [ ] T04 Revisión y build local.
- [ ] T05 Registro de la aplicación en Microsoft Entra (Alberto) y prueba real.

## 6. Evidencia

- `MicrosoftGraphTests` 6/6 (formulario, consulta con fecha, lectura de correos, código de dispositivo, errores, capacidad en el prompt). Suite completa sin fallos.
- Falta la prueba real: requiere una aplicación registrada en Microsoft Entra (T05).
