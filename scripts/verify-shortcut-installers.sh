#!/bin/zsh
# Verifica sin importar nada que los `.shortcut` incluidos estén firmados,
# íntegros y apunten al puente correcto. Requiere las herramientas de macOS.
set -eu
cd "${0:A:h}/.."

TMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/btodicta-shortcuts.XXXXXX")"
trap '/bin/rm -rf "$TMP"' EXIT INT TERM
OPENSSL="/opt/homebrew/bin/openssl"
[[ -x "$OPENSSL" ]] || OPENSSL="/usr/bin/openssl"

verificar() {
  local archivo="$1"
  local esperado="$2"
  local exige_entrada="${3:-0}"
  local base="${archivo:t:r}"
  local dir="$TMP/$base"
  /bin/mkdir -p "$dir"

  [[ -f "$archivo" ]] || { print -u2 "Falta $archivo"; return 1; }
  [[ "$(/usr/bin/xxd -p -l 4 "$archivo")" == "41454131" ]] || {
    print -u2 "$archivo no usa el contenedor firmado AEA1"; return 1
  }

  local largo
  largo="$(/usr/bin/od -An -tu4 -j 8 -N 4 "$archivo" | /usr/bin/tr -d ' ')"
  [[ "$largo" == <-> ]] || { print -u2 "Cabecera inválida en $archivo"; return 1; }
  /bin/dd if="$archivo" of="$dir/header.plist" bs=1 skip=12 count="$largo" 2>/dev/null
  /usr/bin/plutil -extract SigningCertificateChain.0 raw \
    -o "$dir/cert.b64" "$dir/header.plist"
  /usr/bin/base64 -D -i "$dir/cert.b64" -o "$dir/cert.der"
  "$OPENSSL" x509 -inform DER -in "$dir/cert.der" -pubkey -noout > "$dir/pub.pem"
  "$OPENSSL" pkey -pubin -in "$dir/pub.pem" -outform DER > "$dir/pub.der"
  /usr/bin/tail -c 65 "$dir/pub.der" > "$dir/pub-x963.bin"
  local pub
  pub="$(/usr/bin/xxd -p -c 200 "$dir/pub-x963.bin" | /usr/bin/tr -d '\n')"
  /usr/bin/aea decrypt -i "$archivo" -o "$dir/workflow.aa" \
    -sign-pub-value "hex:$pub"
  /bin/mkdir -p "$dir/unpacked"
  /usr/bin/aa extract -i "$dir/workflow.aa" -d "$dir/unpacked"
  /usr/bin/plutil -lint "$dir/unpacked/Shortcut.wflow" >/dev/null
  /usr/bin/plutil -convert xml1 -o "$dir/workflow.xml" \
    "$dir/unpacked/Shortcut.wflow"
  # Los instaladores los firma Apple y guardan la ruta ABSOLUTA de la app. Tras
  # el cambio de nombre siguen apuntando al nombre anterior y no se pueden
  # regenerar sin la app Atajos: eso se AVISA, no se oculta, y se publica solo
  # porque el atajo sigue funcionando mientras la app anterior esté instalada.
  local anterior="${esperado//BtoDicta/BetoDicta}"
  anterior="${anterior//btodicta-/betodicta-}"
  if ! /usr/bin/grep -Fq "$esperado" "$dir/workflow.xml"; then
    if [ "$anterior" != "$esperado" ] && /usr/bin/grep -Fq "$anterior" "$dir/workflow.xml"; then
      print "SHORTCUTTEST AVISO · $base apunta al nombre anterior de la app — hay que volver a generarlo desde Atajos"
    else
      print -u2 "$archivo no contiene $esperado"; return 1
    fi
  fi
  # Los paquetes son portables: jamás deben capturar una ruta personal, una
  # credencial ni la capacidad privada generada por una instalación concreta.
  if /usr/bin/grep -Eq '/Users/|agente_pasarela_siri_token|sk-[A-Za-z0-9_-]{12,}|api[_-]?key' \
      "$dir/workflow.xml"; then
    print -u2 "$archivo contiene una ruta personal o un posible secreto"; return 1
  fi
  if [[ "$exige_entrada" == "1" ]]; then
    [[ "$(/usr/bin/plutil -extract WFWorkflowHasShortcutInputVariables raw \
        "$dir/unpacked/Shortcut.wflow")" == "true" ]] || {
      print -u2 "$archivo no conecta la Entrada del atajo"; return 1
    }
  fi
  print "SHORTCUTTEST OK · $base"
}

verificar "Resources/BtoDicta · Escuchar asistente.shortcut" \
  "/Applications/BtoDicta.app/Contents/Resources/btodicta-siri.sh"
verificar "Resources/BtoDicta Universal.shortcut" \
  "/Applications/BtoDicta.app/Contents/Resources/btodicta-universal.sh" 1
verificar "Resources/BtoDicta-Reproducir-musica.shortcut" \
  "is.workflow.actions.playmusic"

print "SHORTCUTTEST TODO OK"
