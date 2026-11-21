# Spec 014 — Modo IA por gesto de teclado

- Estado: Implementada (pendiente de prueba real de Alberto)
- Tipo: funcionalidad
- Nivel: P (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-11-20
- Modifica: ninguna (la triple fn sigue siendo el modo reunión)
- Aprobada por: Alberto — 2026-11-20 — «Creo que es tecla propia… todo lo que acabamos de hablar, parametrizable… esas tres formas, por favor»
- Rama: `main`

## 1. Problema y propósito

Alberto quiere un gesto de teclado que abra un «modo IA»: habla y el agente actúa
sobre BtoDicta y la Mac (tachar una tarea, callar el aviso que suena, cambiar un
ajuste…), con el proveedor de IA que elija. Hoy el agente existe, pero se entra
por voz («Beto, …») o dejando el modo activo en «agente»; no hay un gesto propio.

## 2. Qué existe ya (verificado en el código, 2026-11-20)

### 2.1 Gestos de la tecla del dictado

- Tecla configurable `tecla` (por defecto fn). Dos maneras excluyentes, por ajuste
  global:
  - **Modo toque** (`doble_pulsacion_activar`): la segunda fn arranca al BAJAR, sin
    esperas; una fn posterior detiene. Ventana `doble_pulsacion_ventana`.
  - **Mantener para hablar** (`hold_para_hablar`): con doble activo, se mantiene la
    segunda fn y al soltar termina.
- **Triple fn = modo reunión** (spec 012, `DoublePressGate.swift`
  `TriplePulsacionPolicy`; manejador en `AppDelegate.installFlagsMonitor` y
  `pulsarAtajoCarbon`). La tercera se arma al soltar la segunda —que ya arrancó el
  dictado— y se consume al bajar la siguiente dentro de la ventana. Por diseño el
  doble no espera a la tercera: **0 ms añadidos**. Solo en modo toque.
- Con una confirmación en pantalla, **una** fn acepta (`ConfirmacionFnPolicy`).
- Prueba sintética del manejador: `BTODICTA_TRIPLEFNTEST=1` y
  `Tests/BtoDictaTests/TriplePulsacionTests.swift`.

**Conclusión:** la triple fn ya está ocupada. Lo que propuso Alberto («triple fn =
IA») choca con el modo reunión.

### 2.2 Modo Agente

- Es un modo más (`ModosStore.modo("agente")`). Se entra por la frase activadora
  (`PerfilAgente.invocacion`, `agente_activadores`), por la activación manos libres
  (`ActivacionVoz.swift`) o con «agente» como modo activo. En
  `AppDelegate` (~7867) el dictado se resuelve con `modoSnapshot ?? ModosStore.activo()`:
  **forzar el agente para un dictado concreto es solo pasar ese modo**.
- Cadena de decisión (de más determinista a menos):
  1. `AgenteNucleo.planificar`: rutinas (`RutinasAgente.swift`), clima, volumen,
     `ModoPlanificador.detectarNatural` (correo, WhatsApp, apps, búsquedas…),
     con interruptores por herramienta (`agente_tool_*`).
  2. `RouterGlobalIA.decidir` (`router_global_activo`, por defecto encendido): una
     IA elige UNA capacidad de un catálogo cerrado (JSON), con freno de confianza
     0,45, y se ejecuta por el despacho de modos con su política.
  3. Cerebro conversacional: local → Codex / Hermes / IA de BtoDicta (`agente_motor`,
     `agente_ia_proveedor`, `agente_ia_modelo`), con failover.
- Política: `NivelAutonomiaAgente` (consultivo / asistido / autónomo) y
  `RiesgoAgente` (lectura, reversible, cambio local, externo, destructivo).
  `PoliticaAgente.autoEjecutar` decide; si no, `presentarConfirmacion`. Externo y
  destructivo nunca se autoejecutan.

### 2.3 Proveedores

- `ChatIA` (`LLMPostProcess.swift`): proveedores por API compatibles con OpenAI,
  incluido **Z.ai (GLM)** (`zai`, `glm-4.5-flash`) y la cuenta de ChatGPT vía Codex.
- `AgenteCodex.swift`: usa el binario oficial `codex exec --ephemeral --sandbox
  read-only --ignore-user-config`; **solo devuelve texto**, no toca la Mac.
- `AgenteHermes.swift`: igual, cerebro conversacional sin herramientas.
- La CLI de ZCode está instalada (`~/.local/bin/zcode`) pero **no está integrada**.

### 2.4 Herramientas sobre tareas y avisos

- `TareasComando.interpretar` (determinista, sin IA): crear, **completar (tachar)**,
  modificar, resumen. `NotasStore.completarPorTexto` tacha la más parecida.
- Hoy se llega a «tachar» si el modo es Tarea, o si el router IA elige el modo Tarea.
  El agente no tiene una regla determinista propia para «marca X como hecha».
- Callar la notificación que suena: lo está construyendo la sesión origen en
  `TareasRecordatorios.swift` / `NotasView.swift` (no tocar). El agente solo
  necesitará llamar a esa función cuando exista.
- `TTS.detener()` / `VozTTS.detener()` ya cortan la voz propia de BtoDicta.

## 3. Opciones de gesto

| Opción | Cómo | Latencia | Conflictos |
|---|---|---|---|
| **A. Triple fn configurable** (reunión ↔ IA) | Igual que la 012: la doble arranca el dictado al instante; la tercera, dentro de la ventana, **reorienta ese mismo dictado al agente** | 0 ms; no se pierde audio (la grabación ya empezó) | Si se elige IA, el modo reunión pierde su gesto (queda en el menú del icono y del Dock). Solo en modo toque |
| B. Mantener fn = conversar, doble fn = IA | Mezclar «mantener» y «doble» en el mismo modo | Para distinguir «mantener» de «toque» hay que esperar un umbral (~250–400 ms) en cada primera pulsación | fn+flecha, confirmaciones de una fn y la detención con una fn: toca el manejador más delicado. Riesgo alto de regresión |
| C. Tecla o combinación propia para IA (p. ej. ⌥ derecha, F-tecla, ctrl+fn) | Segundo monitor de atajo, independiente | 0 ms | Ninguno con fn; hay que elegir una tecla libre y añadir un segundo combo (hoy `comboMods` es uno) |
| D. Frase de voz (ya existe) | «Beto, …» | — | Ninguno; no es gesto |

Triple fn «desde reposo sin arrancar el dictado» exigiría retrasar la doble hasta
que pase la ventana (≈450 ms en cada dictado). Se descarta, como ya decidió la 012.

## 4. Agente externo frente a herramientas propias

| | Cerebro externo con manos propias (recomendado) | Agente externo con manos propias del agente (ZCode/Codex con shell) |
|---|---|---|
| Qué hace la IA | Elige una acción de un **catálogo cerrado** y devuelve JSON (como `RouterGlobalIA`) | Ejecuta comandos en la Mac por su cuenta |
| Quién ejecuta | BtoDicta, con `PoliticaAgente` y confirmación | La CLI externa |
| Riesgos | Acotados al catálogo; lo externo y destructivo siempre se confirma | Shell sin límites, inyección de instrucciones desde notas/pantalla/correo, acciones irreversibles sin pasar por la política |
| Estado | Patrón ya probado en el router global | Hoy Codex corre en `--sandbox read-only` a propósito |

Permisos: lectura y cambios reversibles según el nivel de autonomía; envíos,
borrados, publicaciones y pagos **siempre** con confirmación (ya lo impone
`RiesgoAgente`). Cambiar ajustes: solo una lista blanca de claves con valor anterior
→ nuevo a la vista y deshacer; nunca `Config.set` libre.

### Regla de IA de pago (ALTO vigente)

La oficina tiene en pausa la IA de pago en la ruta de decisión. El router global ya
existente usa IA para decidir; el modo IA no debe ampliar eso sin decisión de
Alberto. Para cumplir la regla sin decisión nueva:

- lo determinista va primero y funciona solo (sin clave ni red el gesto sigue
  sirviendo para las órdenes que el núcleo local entiende);
- cuando la acción la eligió una IA, **se confirma siempre**, sea cual sea el nivel
  de autonomía (sugerencia con confirmación humana);
- nada normativo (permisos, borrados, envíos) lo decide la IA.

## 5. Recomendación — alcance mínimo de la versión 1

1. **Gesto**: ajuste `gesto_triple_fn` = `reunion` (por defecto, nada cambia) |
   `agente`. Con `agente`, la tercera fn marca el dictado en curso para el agente y
   el notch lo indica («Modo IA»). Reutiliza la mecánica de la 012: 0 ms.
2. **Proveedor**: el que ya tiene el agente (`agente_motor` + `agente_ia_proveedor`,
   donde ya están GLM por API, Codex y Hermes). No se integra la CLI de ZCode en v1.
3. **Herramientas nuevas mínimas**:
   - regla determinista «marca / tacha X como hecha» en `AgenteNucleo.planificar`
     → `TareasComando` completar (cambio local, confirmable);
   - «calla / silencia» → `TTS.detener` + la función de callar el aviso de la sesión
     origen cuando esté publicada.
4. **Seguridad**: confirmación siempre que decidió una IA (§4).
5. **Fuera de v1 (al backlog)**: tecla propia para IA (opción C), ZCode como motor
   (como cerebro de catálogo cerrado, nunca con shell), ajustes por voz con lista
   blanca, opción B.

Archivos que tocaría v1: `DoublePressGate.swift` (política), `AppDelegate.swift`
(manejador y resolución), `Config.swift` (clave), `AgenteView.swift` (selector),
`AgenteNucleo.swift` (regla de tachar), pruebas en `TriplePulsacionTests.swift`.
No toca `TareasRecordatorios.swift` ni `NotasView.swift`.

## 6. Decisiones de Alberto (2026-11-20)

1. **Tecla propia**, no triple fn. Sugirió doble Control. En esta Mac no hay
   Karabiner, Raycast, Alfred ni BetterTouchTool, y Siri no tiene atajo de teclado
   configurado: doble Control está libre. Tecla y ventana, parametrizables.
2. **Proveedor elegible**: IA de BtoDicta, Hermes, Codex o ZCode (nuevo).
3. **Qué decide la IA, parametrizable**: solo reglas fijas · catálogo cerrado ·
   terminal (la IA propone comandos, sudo incluido).
4. **Confirmación de lo que decide la IA, tres modos**: aprobación · auto · omitir
   permisos. Esto es la decisión de Alberto sobre la regla de IA de pago para esta
   función: lo determinista sigue primero y funciona solo.
5. Respuesta hablada con la voz configurada (Beto, ElevenLabs) y **conversación**:
   tras responder vuelve a escuchar.
6. Órdenes «tacha X» y «calla», y **callar con un clic en el icono**.

## 7. Plan

- `ModoIA.swift` (nuevo): `GestoTeclaIA` (detector puro de toque y doble toque de
  una modificadora), `AgenteOrdenes` (calla, tachar), `AgenteTerminal` (plan JSON,
  lista de solo lectura, ejecución con sudo por `sudo -n` o el diálogo de macOS),
  `AgenteZCode` (`zcode -p --mode guarded` sin herramientas) y `CerebroTexto`.
- `Config.swift`: claves `agente_gesto_activo` (apagado de fábrica),
  `agente_gesto_tecla` (ctrl), `agente_gesto_ventana` (0,4 s),
  `agente_gesto_conversacion`, `agente_ia_decision` (catalogo),
  `agente_ia_confirmacion` (auto), `agente_terminal_timeout` (60 s),
  `agente_zcode_bin`, `agente_clic_calla`.
- `AppDelegate.swift`: el gesto entra por el mismo monitor de modificadores; el
  turno usa `modoPendienteVoz = agente`. Órdenes directas antes del planificador;
  modo de decisión antes del router; confirmación del router en aprobación;
  conversación tras `entregarRespuestaAgente`; clic en el icono calla.
- `AgenteView.swift`: tarjeta «Modo IA con tecla propia» y ZCode en el cerebro.
- `TareasComando.swift`: el verbo más largo gana («marca como hecha» antes que
  «marca»); antes dejaba «como hecha…» dentro del nombre buscado.
- `RouterGlobalIA.llamarIA` deja de ser privado para reutilizarlo.
- Callar el aviso de tareas: BtoDicta publica `betoCallarAvisos`; la sesión que
  trabaja los avisos puede escucharla. No se tocan `TareasRecordatorios.swift` ni
  `NotasView.swift`.

## 8. Tareas

- [x] T01 Detector del gesto y pruebas.
- [x] T02 Órdenes calla y tachar, y pruebas.
- [x] T03 Modos de decisión y confirmación.
- [x] T04 Terminal con autorización y sudo; pruebas de lectura y ejecución.
- [x] T05 ZCode como cerebro.
- [x] T06 Conversación hablada y clic que calla.
- [x] T07 Ajustes en la pantalla del Asistente.
- [ ] T08 Prueba real de Alberto con la app instalada.

## 9. Evidencia

- `swift build` limpio; `ModoIATests` 13/13, `TriplePulsacionTests` 3/3; suite
  completa 132 pruebas, 0 fallos (3 omitidas de siempre).
- ZCode responde en modo de una pregunta (`zcode -p … --mode guarded`), ~13 s.
- Revisión única de código y seguridad (Codex, auditor, solo lectura,
  2026-11-20): 9 hallazgos, todos corregidos y con prueba donde es puro:
  ZCode sin ninguna herramienta conocida; `ps e`/`-E`, `sysctl -f` y rutas ocultas
  relativas fuera de la lectura automática; Esc y el tiempo agotado matan el árbol
  del comando y de ZCode; cancelar tras el gesto suelta el modo Agente; callar
  cierra el turno; «tacha» sigue la conversación; Control-clic no cuenta como
  toque; Hermes se respeta en terminal; «marca como hecho» se reconoce.
- Revisión automática del arnés: comillas, comodines, tabuladores, `$`, `=`,
  `open`, `sed`, `awk`, `sort`, `printenv`, `file` y rutas sensibles fuera de la
  lectura automática. «Omitir permisos» se mantiene por decisión de Alberto.
- Límite conocido: un comando con clave de administrador corre como root; Esc no
  puede matarlo desde la app.

## 10. Cambio tras la prueba real (2026-11-20)

Alberto probó el gesto: funcionaba, pero el asistente solo conversaba. Causas
vistas en `logs/agente.jsonl`: el router devolvía siempre confianza 0 (el ejemplo
del prompt decía `0.0` y el modelo lo copiaba), así que el freno de 0,45
descartaba incluso decisiones correctas; además el router usaba la cascada de
pulido (Groq) y no la IA del asistente.

- Nuevo modo de decisión **«Todo: acción, terminal o respuesta»** (`mixto`): una
  sola consulta al cerebro elegido devuelve una capacidad del catálogo, comandos
  o solo la respuesta. Genérico: funciona con IA por API, Codex, Hermes o ZCode;
  si falta la CLI elegida, cae a la IA configurada.
- El router usa la IA del asistente si está configurada.
- Borrador de correo canónico: `open "mailto:…"` (no envía).
- Prueba real contra ZCode (`BTODICTA_ZCODE_REAL=1`): borrador por comando,
  búsqueda web por capacidad. Suite 133, 0 fallos. Commit `2d5db69`.
