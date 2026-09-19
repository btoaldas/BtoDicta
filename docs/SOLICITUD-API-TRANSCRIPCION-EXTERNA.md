# Solicitud: API de transcripción para servicios externos

**Fecha:** 2026-09-15
**Pedido por:** Alberto
**Estado:** IMPLEMENTADO en 0.65.0. Este documento se conserva como el origen
citado por la spec 005; lo vigente está en `docs/specs/005-api-de-transcripcion-para-servicios-externos/`.

## Qué se pide

Que BtoDicta exponga una **API de transcripción utilizable desde fuera de la
app**, para que otros servicios y proyectos de la oficina puedan convertir audio
en texto reutilizando los motores y modelos que BtoDicta ya tiene instalados,
sin duplicarlos y sin depender de rutas internas.

## Por qué surge

BtoDicta es hoy el único lugar de la Mac con motores de transcripción
instalados, configurados y funcionando: `whisper.cpp` con `large-v3-turbo`
(1,5 GB) en `~/.btodicta/models`, además de la credencial de Fish Audio en
`~/.btodicta/.env`.

Cuando otro proyecto necesitó transcribir —notas de voz de WhatsApp para
**BtoWasap**— las opciones eran duplicar modelos de varios gigabytes, contratar
otro servicio, o alcanzar los recursos de BtoDicta desde fuera. Se eligió lo
tercero, y funciona: hay un comando global `transcribir` en `~/.local/bin` que
usa esos recursos y está probado con audio real.

**Pero ese comando depende de la estructura interna de BtoDicta**: conoce las
rutas de los modelos y del archivo de configuración. Si BtoDicta reorganiza sus
carpetas, renombra un modelo o cambia dónde guarda la clave, el consumidor se
rompe sin aviso y sin que nadie lo note hasta que alguien pida una
transcripción.

Eso es acoplamiento a los internals en vez de a un contrato — exactamente lo que
la gobernanza de la oficina desaconseja.

## Lo que resolvería una API propia

1. **Un contrato estable.** BtoDicta podría mover, renombrar o cambiar sus
   modelos sin romper a nadie, mientras respete la interfaz.
2. **Un solo lugar donde vive la decisión de qué motor usar**, con su cascada y
   sus reintentos, en vez de repetirla en cada consumidor.
3. **Reutilización real.** Hoy el consumidor es BtoWasap; mañana puede ser un
   flujo de reuniones, de dictado por lotes o de subtitulado.
4. **Las credenciales dejan de viajar.** El consumidor no necesitaría leer
   `~/.btodicta/.env`: pediría la transcripción y recibiría el texto.

## Forma sugerida — a criterio de quien lo implemente

Lo mínimo útil sería una operación que reciba la ruta de un archivo de audio y
devuelva el texto, junto con qué motor lo produjo y cuánto tardó. Conviene poder
elegir motor (local, nube, o cascada automática) y pasar vocabulario de
contexto, porque está medido que las siglas institucionales se transcriben mal
sin él ("WEA" por UEA, "LEVA" por EVA).

Si es HTTP local, valen las mismas cautelas que se aplicaron en BtoWasap:
escuchar solo en loopback, token de autorización, y nunca exponer rutas
arbitrarias del disco.

## Mientras tanto

**El comando global `transcribir` se mantiene fuera de BtoDicta**, por decisión
expresa de Alberto. No se mueve a este repositorio hasta que exista la API.
Documentado en el skill global `transcribir`
(`~/.claude/skills/transcribir/SKILL.md`), que también recoge las trampas
medidas de ambos motores.

Cuando esta API exista, ese comando se reescribe para consumirla y deja de
conocer rutas internas de BtoDicta.

## Datos medidos que pueden servir a quien implemente

- Motor local, audio de 121 s: transcrito en **2,74 s** (~43x tiempo real).
- Fish Audio: **$0,006 por minuto**; saldo verificado el 2026-09-15: $46,18.
- **Voxtral Realtime** (descargado, 2,6 GB) **no sirve para archivos**: es
  streaming por micrófono. Transcribir un archivo con Voxtral exigiría descargar
  Voxtral Mini 3B con su `mmproj` y levantar `llama-server`.
- El motor local **omitió una frase completa** en un audio real de dos minutos
  que el de nube sí capturó. La cascada a nube no es solo para fallos: también
  sirve como segunda opinión.
