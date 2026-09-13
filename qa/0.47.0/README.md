# Paquete QA BtoDicta 0.47.0

Este paquete separa dos preguntas distintas:

1. **Camino feliz:** ¿la función correcta completa su trabajo de punta a punta?
2. **Estrés y degradación:** si la frase, permiso, red o proveedor falla, ¿BtoDicta
   evita hacer algo equivocado y vuelve a una salida segura?

## Preparación segura (3 minutos)

1. Abre **Ajustes → Avanzado** y activa el registro detallado de modos.
2. En el asistente, anota su nombre actual. En los casos que dicen `<AGENTE>`,
   reemplázalo por ese nombre; no tiene que llamarse Bto.
3. Usa autonomía **Asistida** durante el QA.
4. Desactiva **autoenviar WhatsApp**. El resultado seguro debe quedar preparado
   en el campo de texto, no enviado.
5. Deja **Dictado** como modo predeterminado y activa “volver al predeterminado”.
6. Abre un documento de prueba vacío para los casos de dictado.
7. Usa destinatarios, eventos y archivos de prueba; no información real sensible.

## Prueba automática segura

Desde esta carpeta:

```sh
./ejecutar-qa.sh --automatico
```

Ejecuta analizadores locales, matrices positivas y negativas, activación por voz,
agente, clima, volumen, aplicaciones, recetas, tareas, Notas y permisos. **No abre
apps, no envía mensajes, no reproduce música y no llama proveedores de pago.**
La carpeta `evidencia-*` termina con `resultado.txt` y `resumen.tsv`.

Pruebas opcionales que sí consumen servicios configurados, pero no ejecutan la
acción final:

```sh
./ejecutar-qa.sh --audio   # ElevenLabs → Apple Speech → resolvedor
./ejecutar-qa.sh --ia      # árbitro de modos con la IA activa
```

## Prueba manual

- Sigue [`01-camino-feliz.md`](01-camino-feliz.md) en orden.
- Después sigue [`02-estres-y-degradacion.md`](02-estres-y-degradacion.md).
- Registra cada caso en [`RESULTADOS.csv`](RESULTADOS.csv): `PASA`, `FALLA` u
  `OMITIDA`, junto con lo que oyó el STT y lo que realmente hizo la app.
- Al terminar, ejecuta `./ejecutar-qa.sh --evidencia` para guardar las últimas
  800 líneas de `modos.jsonl` y `agente.jsonl`.

## Regla para aprobar

- **PASA:** coincide la intención, el contenido no se pierde y existe evidencia
  visible o en logs.
- **DEGRADA BIEN:** no pudo completar por permiso/red/proveedor, pero explica el
  motivo, conserva texto/archivo y no ejecuta otra acción distinta.
- **FALLA:** hace una acción equivocada, envía sin consentimiento, pierde contenido,
  queda colgada, conserva un modo anterior o no deja evidencia.

Los logs pueden contener dictados privados. El ejecutor usa 0700/0600 y nunca
copia `.env`, claves ni `config.json`; no publiques la evidencia sin revisarla.
