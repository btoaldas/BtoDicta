# Spec 018 — Varias cuentas de Microsoft y Google

- Estado: En implementación
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-11-21
- Modifica: 015, 016 (de una cuenta Microsoft a varias cuentas de dos proveedores)
- Aprobada por: Alberto — 2026-11-21 — «conectar las cuentas que desee el usuario, tanto de Microsoft como de Google, puede conectar más de una… siempre y cuando tenga las autorizaciones»; «Sigue con fase 5»
- Rama: `main`

## 1. Alcance

- Registro de cuentas en `~/.btodicta/cuentas.json` (0600): proveedor, nombre corto,
  correo, identificadores de la aplicación y una predeterminada. Las sesiones, en
  el Llavero (una entrada por cuenta). La cuenta Microsoft actual se migra sola.
- Microsoft: varias cuentas, mismo flujo de código de dispositivo.
- Google: OAuth oficial de aplicación de escritorio con PKCE y redirección local
  (`127.0.0.1`), porque el flujo de dispositivo de Google no admite Gmail.
  Permisos: `gmail.readonly`, `gmail.compose`, `calendar.events`,
  `contacts.readonly`, `openid`, `email`.
- Interfaz común de proveedor: leer y buscar correo, borradores (crear, cambiar),
  enviar (siempre con confirmación), agenda (ver, crear) y personas.
- Asistente: campo «cuenta» por nombre corto o correo; sin él, la predeterminada.

## 2. No incluye (siguiente paso)

- Responder y reenviar en Gmail (sí en Microsoft).
- Publicar la aplicación de Google para terceros (queda en modo prueba).

## 3. Requisitos

- RF-01: Con dos cuentas, «revisa mi correo personal» usa la cuenta «Personal».
- RF-02: Quitar una cuenta pide confirmación y borra solo su sesión del Llavero.
- RF-03: Enviar desde cualquier cuenta muestra destinatarios y texto y espera OK.
- RNF-01: Tokens y secretos nunca en el registro ni en el repositorio.

## 4. Tareas

- [x] T01 Registro de cuentas y migración.
- [x] T02 Microsoft multi-cuenta.
- [x] T03 Google OAuth de escritorio con PKCE.
- [x] T04 Gmail, Calendar y Contactos.
- [x] T05 Asistente con cuenta por nombre.
- [x] T06 Ajustes de cuentas.
- [ ] T07 Aplicación en Google Cloud (con Alberto) y prueba real.

## 5. Evidencia

- 2026-11-21: `swift test` 186 pruebas, 0 fallos (nuevas: `CuentasNubeTests`, `GoogleCuentaTests`,
  incluido el vector PKCE del RFC 7636 y el bloqueo de cabeceras inyectadas en destinatarios).
- Evaluación real del asistente (glm-5.3, 33 casos): 33/33.
- Migración probada en copia temporal: la cuenta Microsoft anterior pasa al registro sin reconectar.
- Pendiente T07: aplicación de Google Cloud (con OK de Alberto) y prueba real con Gmail.
