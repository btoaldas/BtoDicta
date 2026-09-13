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
# El puente NO necesita los motores locales ni los modelos: solo enseña el
# asistente y descarga la app nueva. Se lleva el icono y poco más.
for r in AppIcon.icns Assets.car; do
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
print "Puente listo: $PUENTE ($(du -sh "$PUENTE" | cut -f1), identificador $ID)"
