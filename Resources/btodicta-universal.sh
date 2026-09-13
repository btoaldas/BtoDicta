#!/bin/zsh
# Puente para una acción “Ejecutar script de shell” de Atajos de macOS.
# Entrada: JSON por stdin. Salida: RespuestaUniversalBeto JSON por stdout.
set -eu
umask 077

BIN="/Applications/BtoDicta.app/Contents/MacOS/BtoDicta"
if [[ ! -x "$BIN" ]]; then
  print -u2 "BtoDicta no está instalado en /Applications."
  exit 127
fi

TMPDIR_BD="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/btodicta-universal.XXXXXX")"
IN="$TMPDIR_BD/orden-$$.json"
OUT="$TMPDIR_BD/respuesta-$$.json"
trap '/bin/rm -f "$IN" "$OUT"; /bin/rmdir "$TMPDIR_BD" 2>/dev/null || true' EXIT INT TERM

# El binario vuelve a validar el contrato, pero cortar aquí impide que una
# entrada defectuosa/ilimitada llene el disco antes de llegar a Swift.
/usr/bin/head -c 64001 > "$IN"
/bin/chmod 600 "$IN"
set +e
"$BIN" --universal-input "$IN" --universal-output "$OUT" >/dev/null
STATUS=$?
set -e
[[ -f "$OUT" ]] && /bin/cat "$OUT"
exit "$STATUS"
