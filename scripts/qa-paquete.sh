#!/bin/zsh
# Paquete QA reproducible de BtoDicta. Por defecto solo ejecuta pruebas locales
# que no abren aplicaciones, no envían mensajes y no llaman proveedores de pago.
set -u
umask 077

VERSION_PAQUETE="0.47.0"
SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:h}"
if [[ -f "$SCRIPT_DIR/matriz-camino-feliz.tsv" ]]; then
  QA_DIR="$SCRIPT_DIR"
  REPO=""
else
  QA_DIR="$REPO/qa/$VERSION_PAQUETE"
fi

modo="automatico"
salida=""
while (( $# )); do
  case "$1" in
    --automatico) modo="automatico" ;;
    --audio) modo="audio" ;;
    --ia) modo="ia" ;;
    --evidencia) modo="evidencia" ;;
    --salida)
      shift
      (( $# )) || { print -u2 "Falta la ruta después de --salida"; exit 2; }
      salida="$1"
      ;;
    --ayuda|-h|--help)
      print "Uso: $0 [--automatico|--audio|--ia|--evidencia] [--salida RUTA]"
      print "  --automatico  QA local seguro (predeterminado)."
      print "  --audio       ElevenLabs → Apple Speech → modos; puede consumir API."
      print "  --ia          Árbitro de modos con la IA activa; puede consumir API."
      print "  --evidencia   Copia solo los últimos logs locales para analizar pruebas manuales."
      exit 0
      ;;
    *) print -u2 "Opción desconocida: $1"; exit 2 ;;
  esac
  shift
done

[[ -d "$QA_DIR" ]] || { print -u2 "No encuentro las matrices QA en $QA_DIR"; exit 2; }

if [[ -n "${BTODICTA_QA_BIN:-}" ]]; then
  BIN="$BTODICTA_QA_BIN"
elif [[ -n "$REPO" && -x "$REPO/build/release/BtoDicta" ]]; then
  BIN="$REPO/build/release/BtoDicta"
else
  BIN="/Applications/BtoDicta.app/Contents/MacOS/BtoDicta"
fi
[[ -x "$BIN" ]] || {
  print -u2 "No encuentro el binario de BtoDicta. Instala la app o define BTODICTA_QA_BIN."
  exit 2
}

marca="$(/bin/date '+%Y%m%d-%H%M%S')"
[[ -n "$salida" ]] || salida="$QA_DIR/evidencia-$marca"
/bin/mkdir -p "$salida/logs-automaticos" "$salida/logs-app"
/bin/chmod 700 "$salida" "$salida/logs-automaticos" "$salida/logs-app"

version_app="desconocida"
plist="${BIN:h:h}/Info.plist"
if [[ -f "$plist" ]]; then
  version_app="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || print desconocida)"
elif [[ -f /Applications/BtoDicta.app/Contents/Info.plist ]]; then
  version_app="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/BtoDicta.app/Contents/Info.plist 2>/dev/null || print desconocida)"
fi

{
  print "Paquete QA BtoDicta $VERSION_PAQUETE"
  print "Fecha: $(/bin/date '+%Y-%m-%d %H:%M:%S %Z')"
  print "macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || print desconocido)"
  print "Arquitectura: $(/usr/bin/uname -m)"
  print "Binario: $BIN"
  print "Versión detectada: $version_app"
  print "Modo: $modo"
  print "Privacidad: evidencia local; no se copiaron .env, claves ni config.json."
} > "$salida/metadatos.txt"

copiar_evidencia() {
  local fuente destino
  for fuente in "$HOME/.btodicta/logs/modos.jsonl" "$HOME/.btodicta/logs/agente.jsonl"; do
    [[ -f "$fuente" ]] || continue
    destino="$salida/logs-app/${fuente:t}"
    /usr/bin/tail -n 800 "$fuente" > "$destino"
    /bin/chmod 600 "$destino"
  done
  print "Los logs pueden contener texto dictado. No los publiques sin revisarlos." \
    > "$salida/logs-app/PRIVACIDAD.txt"
  /bin/chmod 600 "$salida/logs-app/PRIVACIDAD.txt"
}

if [[ "$modo" == "evidencia" ]]; then
  copiar_evidencia
  print "Evidencia local preparada en: $salida"
  exit 0
fi

print "prueba\testado\tcodigo\tsegundos\tarchivo" > "$salida/resumen.tsv"
total=0
fallos=0
omitidas=0

ejecutar() {
  local id="$1" variable="$2" valor="$3" limite="${4:-90}"
  local log="$salida/logs-automaticos/$id.log"
  local inicio fin codigo estado
  inicio="$(/bin/date +%s)"
  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$limite" \
    /usr/bin/env "$variable=$valor" "$BIN" > "$log" 2>&1
  codigo=$?
  fin="$(/bin/date +%s)"
  total=$((total + 1))
  if (( codigo == 0 )); then
    estado="PASA"
  elif (( codigo == 4 )) && [[ "$id" == audio_* || "$id" == ia_* ]]; then
    estado="OMITIDA"; omitidas=$((omitidas + 1))
  else
    estado="FALLA"; fallos=$((fallos + 1))
  fi
  print "$id\t$estado\t$codigo\t$((fin - inicio))\t${log:t}" >> "$salida/resumen.tsv"
  print "[$estado] $id"
}

# Comprobación ESTÁTICA: no necesita arrancar la aplicación, lee el código. Vigila
# el fallo de 0.59.0 —pedir el cierre de la conexión sobre la sesión compartida—,
# que ya volvió una vez en trece sitios distintos.
estatica() {
  local id="$1"; shift
  local log="$salida/logs-automaticos/$id.log"
  local inicio fin codigo estado
  inicio="$(/bin/date +%s)"
  "$@" > "$log" 2>&1
  codigo=$?
  fin="$(/bin/date +%s)"
  total=$((total + 1))
  if (( codigo == 0 )); then estado="PASA"; else estado="FALLA"; fallos=$((fallos + 1)); fi
  print "$id\t$estado\t$codigo\t$((fin - inicio))\t${log:t}" >> "$salida/resumen.tsv"
  print "[$estado] $id"
}

if [[ "$modo" == "audio" ]]; then
  ejecutar "audio_elevenlabs_apple" "BTODICTA_MODOAUDIOQA" "1" 900
elif [[ "$modo" == "ia" ]]; then
  ejecutar "ia_arbitro_modos" "BTODICTA_MODOIATEST" "1" 240
else
  ejecutar "nucleo_agente" "BTODICTA_AGENTCORETEST" "1" 120
  ejecutar "planificador_natural" "BTODICTA_MODOPLANTEST" "1" 120
  ejecutar "regresiones_modos" "BTODICTA_MODEREGRESSION" "1" 90
  ejecutar "matriz_camino_feliz" "BTODICTA_MATRIZTEST" "$QA_DIR/matriz-camino-feliz.tsv" 120
  ejecutar "matriz_estres" "BTODICTA_MATRIZTEST" "$QA_DIR/matriz-estres.tsv" 120
  ejecutar "activacion_voz" "BTODICTA_WAKEWORDTEST" "1" 90
  ejecutar "aplicaciones" "BTODICTA_APPTEST" "1" 120
  ejecutar "recetas_y_atajos" "BTODICTA_RECIPETEST" "1" 120
  ejecutar "clima_parser" "BTODICTA_CLIMATEST" "1" 90
  ejecutar "volumen_parser" "BTODICTA_VOLUMETEST" "1" 90
  ejecutar "notas_apple_parser" "BTODICTA_NOTASAPPLETEST" "1" 90
  ejecutar "tareas_recordatorios" "BTODICTA_TASKREMINDERTEST" "1" 90
  ejecutar "almacen_tareas_notas" "BTODICTA_NOTATEST" "1" 90
  ejecutar "autoayuda" "BTODICTA_HELPTEST" "1" 90
  ejecutar "permisos" "BTODICTA_PERMISSIONSTEST" "1" 90
  estatica "memoria_en_disco" /usr/bin/python3 "${REPO:-$QA_DIR/../..}/scripts/qa-memoria-en-disco.py" "${REPO:-$QA_DIR/../..}/Sources/BtoDicta"
  estatica "conexion_compartida" /usr/bin/python3 "${REPO:-$QA_DIR/../..}/scripts/qa-conexion-compartida.py" "${REPO:-$QA_DIR/../..}/Sources/BtoDicta"
fi

copiar_evidencia
{
  print "Total: $total"
  print "Fallos: $fallos"
  print "Omitidas: $omitidas"
  print "Resultado: $([[ $fallos -eq 0 ]] && print APROBADO || print REVISAR)"
} > "$salida/resultado.txt"
/bin/chmod -R go-rwx "$salida"

print ""
if (( fallos == 0 )); then
  print "QA APROBADO: $total pruebas, $omitidas omitidas."
  print "Evidencia: $salida"
  exit 0
fi
print "QA CON FALLOS: $fallos de $total. Revisa $salida/resumen.tsv"
print "Evidencia: $salida"
exit 1
