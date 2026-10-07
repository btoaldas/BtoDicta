# Tareas 013 — Bitácora solo de grabaciones

- Estado: Aprobado
- Fecha: 2026-10-06
- Aprobado por: Alberto, 2026-10-06 — «si dale», delegación de plan, tareas e implementación de la spec corregida
- Spec: [spec.md](spec.md)
- Plan: [plan.md](plan.md)

- [x] T01 [P] (RF-01, RF-07) Preferencia por ausencia, UI editable y notificación — `Sources/BtoDicta/Config.swift`, `Sources/BtoDicta/ContinuoView.swift` — Evidencia esperada: pruebas de configuración nueva, existente y elección false conservada.
  - Evidencia (2026-10-06): Suite BitacoraGrabacionesConfigTests: 4 pruebas; getter ausente true, maestro preservado y false explícito sobre dos ciclos; revisión de UI editable. Ver evidencia.md.
- [x] T02 (RF-02, RF-03, RF-04) Política de sesiones y enlace al grabador e historial — `Sources/BtoDicta/ContinuoCapturaSesion.swift`, `Sources/BtoDicta/ContinuoBitacora.swift`, `Sources/BtoDicta/AppDelegate.swift`, `Sources/BtoDicta/HistoryWriter.swift` — Evidencia esperada: ventanas, cierre, pausa, reconfiguración y finalización tardía aisladas.
  - Evidencia (2026-10-06): Suite SesionTests: 7 pruebas; HistorialTests: escritor real y WAV sintético conservados, sin STT pendiente; apertura/stop/cancel revisados independientemente. Ver evidencia.md.
- [x] T03 [P] (RF-02, RF-03, RF-04) Guardar micrófono, pantalla y sistema con sesión — `Sources/BtoDicta/ContinuoAudio.swift`, `Sources/BtoDicta/ContinuoPantalla.swift`, `Sources/BtoDicta/ContinuoAudioSistema.swift` — Evidencia esperada: guardas asíncronas y prueba sin captura personal.
  - Evidencia (2026-10-06): CapturaTests: 8 pruebas aisladas; arnés real de reposo 61 s con 0 solicitudes/muestras/bytes/recursos en tres fuentes y revisiones de generaciones. Ver evidencia.md.
- [x] T04 [P] (RF-04, RF-05, RF-06, RNF-01) Índice aditivo, filtro de pendientes y corte de nuevas solicitudes — `Sources/BtoDicta/ContinuoIndice.swift`, `Sources/BtoDicta/ContinuoLote.swift`, `Sources/BtoDicta/ContinuoOCR.swift`, `Sources/BtoDicta/TranscribeProviders.swift`, `Sources/BtoDicta/PorteroVoz.swift` — Evidencia esperada: migración idempotente, históricos/FTS íntegros y filtro antes de LIMIT.
  - Evidencia (2026-10-06): IndiceTests: 6 pruebas (migración 3x/FTS/huellas/filtro previo LIMIT); TroceoTests: 6 pruebas sin red, conserva parciales y corta reintentos. Ver evidencia.md.
- [x] T05 [P] (RF-02, RF-03, RNF-03) Permiso autenticado de navegador previo a lectura y captura — `Sources/BtoDicta/ApiLocal.swift`, `extension/src/contenido.js`, `extension/src/fondo.js`, `extension/pruebas/correr.mjs` — Evidencia esperada: reposo denegado, ventana autorizada, fallo cerrado y suite de extensión.
  - Evidencia (2026-10-06): Extensión: 63 comprobaciones aprobadas; permiso autenticado con cuota propia; revisión de guardas previas DOM/captura y revalidación de sesión/instante. Ver evidencia.md.
- [x] T06 (RF-08) Pausar activación por voz en todas las entradas y reintentos — `Sources/BtoDicta/AppDelegate.swift` — Evidencia esperada: guards de vigilancia/rearme/despertar y maestro apagado.
  - Evidencia (2026-10-06): Arnés reposo fuerza listener habilitado: no ocupa micrófono; también con maestro apagado. Revisión de vigilancia, montaje, PCM y entrega tardía. Ver evidencia.md.
- [x] T07 (RF-02, RF-03, RF-05, RNF-02) QA aislada y regresión nativa/paquete — `Tests/BtoDictaTests/BitacoraGrabacionesSesionTests.swift`, `scripts/qa-paquete.sh` — Evidencia esperada: compilación, suites y revisión de segundo ángulo sin llamadas de pago.
  - Evidencia (2026-10-06): 114 pruebas Swift/63 JavaScript sin fallos, reposo real 61 s con maestro activo, build debug y release correctos; revisión independiente de segundo ángulo. Límites y control histórico separado en evidencia.md.

- [x] T08 (RF-01, RF-07, RNF-03) Registrar evidencia y cierre, commit y push — `docs/specs/013-bitacora-solo-de-grabaciones/evidencia.md`, `docs/bitacora/2026-10-06.md`, `ROADMAP.md` — Evidencia esperada: verificadores SDD, árbol y remoto alineados, hito en Obsidian.
  - Evidencia (2026-10-06): Commit 476a469 publicado en origin/main; HEAD, ls-remote y API GitHub coinciden. Hito de Obsidian creado con autor Codex, releído y verificado. Documentación pública neutral y manifestada; cierre documental posterior separado.
