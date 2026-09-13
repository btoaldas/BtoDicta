#!/bin/zsh
# Construye la app PUENTE para quien tenga instalada la versión con el nombre
# anterior. Es el mismo ejecutable dentro de un bundle con el identificador y el
# nombre viejos: al detectarlo, la app no dicta nada, solo abre el asistente que
# instala la nueva.
#
# Existe por una razón concreta: la instalación automática de una versión
# anterior busca dentro del paquete una app con el nombre viejo. Si no la
# encuentra, cancela y el usuario se queda sin camino. Con el puente la
# encuentra, la instala y se abre el asistente.
set -euo pipefail
cd "${0:a:h}/.."
BUILD_DIR="${1:-build}"
ORIGEN="$BUILD_DIR/BtoDicta.app"
PUENTE="$BUILD_DIR/BetoDicta.app"
[ -d "$ORIGEN" ] || { print -u2 "Falta $ORIGEN (haz antes 'make bundle')"; exit 1; }

rm -rf "$PUENTE"
mkdir -p "$PUENTE/Contents/MacOS" "$PUENTE/Contents/Resources"
cp "$ORIGEN/Contents/MacOS/BtoDicta" "$PUENTE/Contents/MacOS/"
cp "$ORIGEN/Contents/Info.plist" "$PUENTE/Contents/"
# El puente NO se lleva los motores locales ni los modelos —no dicta— pero SÍ
# todo lo que hace falta para DESCARGAR Y VERIFICAR la app nueva. Sin la clave
# pública no puede comprobar ninguna firma y toda instalación falla con
# «firma del release no válida»: le pasó a esta misma versión antes de
# publicarse, así que ahora se comprueba aquí y el guion se niega a seguir.
IMPRESCINDIBLES=(update-public-key.der code-signing-cert.der)
OPCIONALES=(AppIcon.icns Assets.car logo-original.png)
for r in "${IMPRESCINDIBLES[@]}"; do
  [ -e "$ORIGEN/Contents/Resources/$r" ] \
    || { print -u2 "Falta $r en la app: el puente no podría verificar nada"; exit 1; }
  cp -R "$ORIGEN/Contents/Resources/$r" "$PUENTE/Contents/Resources/"
done
for r in "${OPCIONALES[@]}"; do
  [ -e "$ORIGEN/Contents/Resources/$r" ] && cp -R "$ORIGEN/Contents/Resources/$r" "$PUENTE/Contents/Resources/" || true
done

P="$PUENTE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ec.bto.betodicta" "$P"
/usr/libexec/PlistBuddy -c "Set :CFBundleName BetoDicta" "$P"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName BetoDicta" "$P" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string BetoDicta" "$P"
# Con ventana propia y en el Dock: el asistente tiene que verse.
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" "$P" 2>/dev/null || true

IDENTITY=$(security find-certificate -c "BetoDicta Self Signed" >/dev/null 2>&1 \
  && echo "BetoDicta Self Signed" || echo "-")
codesign --force --deep --sign "$IDENTITY" "$PUENTE"
codesign --verify --deep "$PUENTE"

ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$P")
[ "$ID" = "ec.bto.betodicta" ] || { print -u2 "El puente no quedó con el identificador anterior"; exit 1; }
for r in "${IMPRESCINDIBLES[@]}"; do
  [ -e "$PUENTE/Contents/Resources/$r" ] || { print -u2 "El puente quedó sin $r"; exit 1; }
done
# Prueba de verdad sobre el bundle ya firmado: identificador correcto y
# recursos de verificación presentes.
BTODICTA_PUENTETEST=1 "$PUENTE/Contents/MacOS/BtoDicta" || { print -u2 "El puente no pasó su propia comprobación"; exit 1; }
print "Puente listo: $PUENTE ($(du -sh "$PUENTE" | cut -f1), identificador $ID)"
