#!/usr/bin/env bash
#
# Instala (o quita) DOS LaunchAgents automáticos (al iniciar sesión y los lunes):
#   1) Revisar actualizaciones de motores de TERCEROS → notifica (no actualiza).
#   2) Actualizar los PRECIOS de los modelos de IA desde LiteLLM (sin gastar IA)
#      → ~/.btodicta/precios_ia.json, para que TODO modelo tenga precio real.
#
# Uso:
#   scripts/install-checkdeps-agent.sh            # instalar/activar ambos
#   scripts/install-checkdeps-agent.sh uninstall  # quitar ambos
#
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/Library/LaunchAgents"

# $1=label  $2=script  $3=extra-arg
crear_agente() {
  local label="$1" script="$2" arg="${3:-}"
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  local log="$HOME/Library/Logs/$label.log"
  local argxml=""
  [ -n "$arg" ] && argxml="    <string>$arg</string>"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO/scripts/$script</string>
$argxml
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log</string>
  <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
}

quitar_agente() {
  local plist="$HOME/Library/LaunchAgents/$1.plist"
  launchctl unload "$plist" 2>/dev/null || true
  rm -f "$plist"
}

if [ "${1:-install}" = "uninstall" ]; then
  quitar_agente "ec.bto.btodicta.checkdeps"
  quitar_agente "ec.bto.btodicta.precios"
  echo "✅ LaunchAgents desinstalados (dependencias + precios)."
  exit 0
fi

crear_agente "ec.bto.btodicta.checkdeps" "check-deps.sh" "--notify"
crear_agente "ec.bto.btodicta.precios" "update-prices.sh" ""
echo "✅ LaunchAgents activos (al iniciar sesión y los LUNES 10:00):"
echo "   • dependencias de terceros → avisa si hay versión nueva (no actualiza)."
echo "   • precios de IA → baja precios reales de LiteLLM a ~/.btodicta/precios_ia.json (sin gastar IA)."
echo "   Logs en ~/Library/Logs/ec.bto.btodicta.*.log"
echo "   Desinstalar: scripts/install-checkdeps-agent.sh uninstall"
