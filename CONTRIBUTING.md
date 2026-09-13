# Contribuir a BtoDicta

¡Bienvenido! Este proyecto nació dictando por voz y se mantiene con esa filosofía: simple, directo y útil.

## Cómo contribuir con código

1. Haz fork y crea una rama: `git checkout -b mi-mejora`
2. Compila y prueba en tu Mac: `make install` (necesitas Xcode 26+ / Swift 6)
3. Manda tu Pull Request con una descripción clara de qué mejora y por qué

## Reglas de la casa

- **Español primero**: la app y sus mensajes están en español; el código se comenta en español
- **Código modular**: vive en `Sources/BtoDicta/` (Config, Recorder, HistoryWriter, clientes de transcripción, panel, AppDelegate…). Añade tu cambio en el archivo que corresponda o crea uno nuevo si toca
- **Cero secretos en el repo**: las API keys viven en `~/.btodicta/.env`, jamás en el código (el `.gitignore` lo bloquea)
- **Privacidad**: los dictados del usuario (`historial/`, `uso.jsonl`) nunca salen de su máquina
- **Gobernanza**: antes de cada release van revisión de código + revisión de seguridad, y el DMG se firma y se verifica. Ver `docs/RELEASING.md`
- **GPL-3.0**: toda contribución queda bajo la misma licencia libre

## Ideas y pendientes

Mira la **hoja de ruta** en el [README](README.md#hoja-de-ruta). ¿Se te ocurre algo o encontraste un bug? [Abre un issue](https://github.com/btoaldas/BtoDicta/issues/new).

## Apoyar el proyecto ☕

Contribuir no es solo código. BtoDicta es gratis y libre; si te sirve, apoyarlo económicamente ayuda a seguir programando (y a pagar la IA que ayuda a construirlo):

- ☕ **Invítame un café** (tarjeta · Apple Pay · Google Pay · PayPal): [btodicta.eztic.ec/apoyar](https://btodicta.eztic.ec/apoyar)
- 💜 **GitHub Sponsors**: [github.com/sponsors/btoaldas](https://github.com/sponsors/btoaldas)

Cualquier aporte —código, reportes, ideas o un cafecito— suma. ¡Gracias!
