#!/usr/bin/env bash
#
# Pipeline de release de BtoDicta — GOBERNANZA (orden obligatorio).
#
#   1. Code review        (workflow de Claude — fuera de este script)
#   2. Security review     (workflow de Claude — fuera de este script)
#   3. Manual + README      al día con TODO lo del release
#   4. Build + verificar firma del bundle
#   5. Publicar release (DMG versionado + estable para brew)
#   6. Verificar: latest, brew (redirect 302), y que las novedades saldrán
#
# Los pasos 1 y 2 los ejecuta Claude (revisión adversarial de código y de
# seguridad) ANTES de correr esto; el script exige confirmarlos con flags para
# que no se salten. El resto se automatiza y se verifica.
#
# Uso:
#   scripts/release.sh --code-review-ok --security-review-ok [--notes "texto"]
#
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

CODE_OK=0; SEC_OK=0; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --code-review-ok) CODE_OK=1 ;;
    --security-review-ok) SEC_OK=1 ;;
    --notes) shift; NOTES="$1" ;;
    *) echo "flag desconocido: $1"; exit 2 ;;
  esac
  shift
done

UPDATE_KEY="${BTODICTA_UPDATE_SIGNING_KEY:-$HOME/.btodicta/release-signing/update-ed25519.pem}"
UPDATE_PUB="Resources/update-public-key.der"

fail() { echo "❌ $1"; exit 1; }
ok()   { echo "✅ $1"; }

# ── Gate 1 y 2: reviews (no automatizables — las hace Claude) ──────────────
[ "$CODE_OK" = 1 ] || fail "Falta code review. Córrela (workflow) y pasa --code-review-ok."
[ "$SEC_OK" = 1 ]  || fail "Falta security review. Córrela (workflow) y pasa --security-review-ok."
ok "Reviews confirmadas (código + seguridad)"

# Recordatorio (no bloquea): ¿los motores de terceros tienen versión nueva?
echo ""; echo "── Recordatorio: motores de terceros ──"
bash scripts/check-deps.sh 2>/dev/null || true
echo ""

# ── Versión coherente (Info.plist usa la base numérica; Swift puede ser beta) ─
VSWIFT=$(sed -n 's/.*static let numero = "\([^"]*\)".*/\1/p' Sources/BtoDicta/Version.swift | head -1)
VBASE=${VSWIFT%%-*}
VPLIST=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
[ "$VBASE" = "$VPLIST" ] || fail "Versión no coincide: Version.swift=$VSWIFT (base $VBASE) vs Info.plist=$VPLIST"
V="$VSWIFT"
IS_PRE=0; [[ "$V" == *-* ]] && IS_PRE=1
ok "Versión $V (base de bundle $VPLIST)"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || fail "Versión no válida: $V"
# Cada release tiene un destino NUEVO: no borrar bundles/DMG anteriores.
BUILD_DIR="${BTODICTA_RELEASE_DIR:-build/releases/v$V}"
[[ "$BUILD_DIR" =~ ^build/releases/[A-Za-z0-9._-]+$ ]] || fail "El destino debe estar bajo build/releases/ y no contener espacios"
[ ! -e "$BUILD_DIR" ] || fail "$BUILD_DIR ya existe; consérvalo y elige otro BTODICTA_RELEASE_DIR"
git diff --quiet && git diff --cached --quiet || fail "Hay cambios sin commit"
RELEASE_COMMIT=$(git rev-parse HEAD)

# ── Gate 3: manual + README tocados en este ciclo (desde el último tag) ─────
git fetch --tags -q 2>/dev/null || true
LASTTAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -n "$LASTTAG" ]; then
  CH=$(git diff --name-only "$LASTTAG"..HEAD -- docs/MANUAL.md README.md | wc -l | tr -d ' ')
  [ "$CH" -eq 2 ] || fail "Deben cambiar AMBOS: Manual y README desde $LASTTAG."
  ok "Manual/README actualizados desde $LASTTAG"
fi
grep -q "$V" Sources/BtoDicta/Version.swift || fail "El historial de Version.swift no menciona $V"
ok "Historial de novedades incluye $V"

# Los instaladores de Atajos son parte del producto. Verificamos firma Apple,
# estructura y puente antes del build para no publicar un paquete vacío o roto.
SHORTCUT_LOG=$(mktemp -t btodicta-shortcuts)
scripts/verify-shortcut-installers.sh >"$SHORTCUT_LOG" 2>&1 \
  || { cat "$SHORTCUT_LOG"; rm -f "$SHORTCUT_LOG"; fail "Instaladores de Atajos inválidos"; }
cat "$SHORTCUT_LOG"
rm -f "$SHORTCUT_LOG"
ok "Instaladores de Atajos firmados e íntegros"

# ── Clave de releases: privada local, pública embebida ─────────────────────
[ -f "$UPDATE_KEY" ] || fail "Falta la clave privada de releases: $UPDATE_KEY"
[ -f "$UPDATE_PUB" ] || fail "Falta la clave pública embebida: $UPDATE_PUB"
PERM=$(stat -f '%OLp' "$UPDATE_KEY")
[ "$PERM" = "600" ] || fail "La clave privada de releases debe estar en 0600 (está en $PERM)"
TMPPUB=$(mktemp)
openssl pkey -in "$UPDATE_KEY" -pubout -outform DER -out "$TMPPUB" \
  || { rm -f "$TMPPUB"; fail "No pude derivar la clave pública de releases"; }
cmp -s "$TMPPUB" "$UPDATE_PUB" \
  || { rm -f "$TMPPUB"; fail "La clave privada no corresponde a Resources/update-public-key.der"; }
rm -f "$TMPPUB"
ok "Clave Ed25519 de releases presente, 0600 y vinculada a la pública embebida"

# ── Gate 4: build + verificar firma del bundle ─────────────────────────────
# Sin pipe (evita el problema SIGPIPE+pipefail): consulta directa del tag.
git rev-parse -q --verify "refs/tags/v$V" >/dev/null 2>&1 && fail "El tag v$V ya existe (¿versión sin subir?)"
mkdir -p "$(dirname "$BUILD_DIR")"
mkdir "$BUILD_DIR"
make dmg BUILD_DIR="$BUILD_DIR" >"$BUILD_DIR/build.log" 2>&1 || { tail -20 "$BUILD_DIR/build.log"; fail "make dmg falló"; }
DMG="$BUILD_DIR/BtoDicta-$VBASE.dmg"
[ -f "$DMG" ] || fail "No se generó $DMG"
# Capturamos a variable: con pipefail, `codesign … | grep -q` haría que grep
# cierre el pipe temprano → codesign recibe SIGPIPE (141) → falso fallo.
SIG=$(codesign -dvvv "$BUILD_DIR/BtoDicta.app" 2>&1 || true)
echo "$SIG" | grep -q "Signature=adhoc" \
  && fail "El bundle quedó ad-hoc; esperaba el certificado propio"
REQ=$(codesign -d -r- "$BUILD_DIR/BtoDicta.app" 2>&1 || true)
CERT_SHA1=$(security find-certificate -c "BetoDicta Self Signed" -Z 2>/dev/null \
  | sed -n 's/^SHA-1 hash: //p' | head -1 | tr '[:upper:]' '[:lower:]')
[ -n "$CERT_SHA1" ] || fail "No pude leer la huella del certificado propio"
echo "$REQ" | tr '[:upper:]' '[:lower:]' | grep -q "$CERT_SHA1" \
  || fail "El bundle no está firmado por la huella del certificado BtoDicta"
TMPCERT=$(mktemp)
security find-certificate -c "BetoDicta Self Signed" -p 2>/dev/null \
  | openssl x509 -outform DER -out "$TMPCERT" \
  || { rm -f "$TMPCERT"; fail "No pude exportar el certificado público de firma"; }
cmp -s "$TMPCERT" Resources/code-signing-cert.der \
  || { rm -f "$TMPCERT"; fail "El certificado del llavero no coincide con el fijado en Resources"; }
rm -f "$TMPCERT"
ok "Bundle firmado con el certificado propio exacto y fijado ($CERT_SHA1)"
codesign --verify --deep --strict "$BUILD_DIR/BtoDicta.app" || fail "Firma del bundle inválida"
BTODICTA_QA_BIN="$PWD/$BUILD_DIR/BtoDicta.app/Contents/MacOS/BtoDicta" \
  scripts/qa-paquete.sh --automatico --salida "$PWD/$BUILD_DIR/qa" \
  || fail "La suite del paquete release falló"
ok "Suite automática del paquete final aprobada"

# La firma distribuible NO depende de que cada Mac confíe en un certificado
# autofirmado: Ed25519 autentica el DMG completo con una clave privada local.
DIGEST=$(mktemp)
DMG_SIG="$DMG.sig"
openssl dgst -sha256 -binary -out "$DIGEST" "$DMG" \
  || { rm -f "$DIGEST"; fail "No pude calcular SHA-256 del DMG"; }
openssl pkeyutl -sign -rawin -inkey "$UPDATE_KEY" -in "$DIGEST" -out "$DMG_SIG" \
  || { rm -f "$DIGEST"; fail "No pude firmar el DMG con Ed25519"; }
rm -f "$DIGEST"
[ "$(stat -f '%z' "$DMG_SIG")" = "64" ] || fail "La firma Ed25519 no mide 64 bytes"
if BTODICTA_DMGVERIFYTEST="$DMG" BTODICTA_DMGVERIFY_SIG="$DMG_SIG" \
   "$BUILD_DIR/BtoDicta.app/Contents/MacOS/BtoDicta" >/dev/null 2>&1; then
  ok "Firma Ed25519 del DMG verificada por la misma app"
else
  fail "La app no pudo verificar la firma Ed25519 del DMG"
fi

# ── Gate 4b: el DMG pasa la MISMA verificación de firma que el updater ──────
# (así nunca publicamos un DMG que la app instalada rechazaría al actualizar)
VOL=$(hdiutil attach -nobrowse -readonly -plist "$DMG" \
      | plutil -convert json -o - - | python3 -c "import sys,json;print(next(e['mount-point'] for e in json.load(sys.stdin)['system-entities'] if 'mount-point' in e))")
trap 'hdiutil detach "$VOL" >/dev/null 2>&1 || true' EXIT
VERIFY_OK=0
VERIFY_OUT=""
# El volumen puede estar montado pero sus recursos tardar una fracción en quedar
# visibles para Bundle/Security. Reintentamos de forma breve y acotada: una
# identidad realmente incorrecta seguirá fallando en todos los intentos.
for intento in 1 2 3 4 5 6; do
  if VERIFY_OUT=$(BTODICTA_VERIFYTEST="$VOL/BtoDicta.app" \
      "$BUILD_DIR/BtoDicta.app/Contents/MacOS/BtoDicta" 2>&1); then
    VERIFY_OK=1
    break
  fi
  [ "$intento" -lt 6 ] && sleep 2
done
if [ "$VERIFY_OK" -eq 1 ]; then
  ok "El bundle del DMG conserva bundle id y certificado de BtoDicta"

# El puente es el único camino de vuelta para quien tenga instalada la versión
# con el nombre anterior: si falta o pierde su identificador, esa gente se queda
# sin actualización automática y con un error en pantalla.
PUENTE_DMG="$VOL/BetoDicta.app"
[ -d "$PUENTE_DMG" ] || fail "El DMG no lleva el puente BetoDicta.app"
PID_PUENTE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PUENTE_DMG/Contents/Info.plist" 2>/dev/null || echo "")
[ "$PID_PUENTE" = "ec.bto.betodicta" ] || fail "El puente no conserva el identificador anterior (tiene: $PID_PUENTE)"
codesign --verify --deep "$PUENTE_DMG" 2>/dev/null || fail "El puente del DMG no está firmado"
ok "El puente para instalaciones anteriores viaja firmado y con su identificador"
else
  echo "$VERIFY_OUT" >&2
  fail "El .app del DMG NO conserva la identidad esperada"
fi
hdiutil detach "$VOL" >/dev/null 2>&1 || true; trap - EXIT

# ── Gate 5: publicar (DMG versionado + estable para brew) ──────────────────
cp "$DMG" "$BUILD_DIR/BtoDicta.dmg"
cp "$DMG_SIG" "$BUILD_DIR/BtoDicta.dmg.sig"
NOTES="${NOTES:-Ver historial en Créditos.}"
PRE_FLAG=()
[ "$IS_PRE" = 1 ] && PRE_FLAG=(--prerelease)
gh release create "v$V" --target "$RELEASE_COMMIT" --title "BtoDicta $V" --notes "$NOTES" "${PRE_FLAG[@]}" \
  "$DMG" "$DMG_SIG" "$BUILD_DIR/BtoDicta.dmg" "$BUILD_DIR/BtoDicta.dmg.sig" \
  || fail "gh release create falló"
ok "Release v$V publicado"

# ── Gate 6: estable verifica latest+brew; beta verifica su tag+asset ───────
sleep 2
if [ "$IS_PRE" = 1 ]; then
  PRE=$(gh api "repos/btoaldas/BtoDicta/releases/tags/v$V" --jq '(.tag_name == "v'"$V"'" and .prerelease == true)')
  [ "$PRE" = "true" ] || fail "v$V no quedó marcado como prerelease"
  RED=$(curl -sI -o /dev/null -w "%{http_code} %{redirect_url}" "https://github.com/btoaldas/BtoDicta/releases/download/v$V/BtoDicta.dmg")
  echo "$RED" | grep -Eq '^200|^302' || fail "asset beta v$V no responde ($RED)"
  REDSIG=$(curl -sI -o /dev/null -w "%{http_code} %{redirect_url}" "https://github.com/btoaldas/BtoDicta/releases/download/v$V/BtoDicta.dmg.sig")
  echo "$REDSIG" | grep -Eq '^200|^302' || fail "firma beta v$V no responde ($REDSIG)"
  ok "prerelease v$V · DMG y firma accesibles (latest estable no se altera)"
else
  LATEST=$(gh api "repos/btoaldas/BtoDicta/releases/latest" --jq '.tag_name')
  [ "$LATEST" = "v$V" ] || fail "latest=$LATEST (esperaba v$V)"
  RED=$(curl -sI -o /dev/null -w "%{http_code} %{redirect_url}" https://github.com/btoaldas/BtoDicta/releases/latest/download/BtoDicta.dmg)
  echo "$RED" | grep -q "v$V/BtoDicta.dmg" || fail "brew estable no apunta a v$V ($RED)"
  REDSIG=$(curl -sI -o /dev/null -w "%{http_code} %{redirect_url}" https://github.com/btoaldas/BtoDicta/releases/latest/download/BtoDicta.dmg.sig)
  echo "$REDSIG" | grep -q "v$V/BtoDicta.dmg.sig" || fail "firma estable no apunta a v$V ($REDSIG)"
  ok "latest=v$V · brew estable y firma → v$V"
fi

echo ""
echo "🥅 Release v$V COMPLETO. La app instalada (versión anterior) verá 'Actualizar a v$V'"
echo "   y las novedades al actualizar. NO se instaló nada localmente."
