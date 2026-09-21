#!/bin/zsh
# Deja la extensión lista para cargar (spec 006, T17).
#
# El mismo código para los cuatro navegadores; lo único que cambia es el
# manifiesto. Por eso esto no «construye» nada: copia, y el único archivo que
# elige es cuál de los dos manifiestos se llama `manifest.json` (ADR-004).
#
#   ./empaquetar.sh              → construye los dos, en dist/
#   ./empaquetar.sh chromium     → solo Chrome, Edge y Brave
#   ./empaquetar.sh firefox      → solo Firefox
set -u
cd "${0:A:h}"

destinos=("${@:-chromium firefox}")
[[ $# -eq 0 ]] && destinos=(chromium firefox)

for d in $destinos; do
  manifiesto="manifest.$d.json"
  if [[ ! -f "$manifiesto" ]]; then
    print -u2 "No existe $manifiesto — ese navegador todavía no está preparado."
    continue
  fi
  salida="dist/$d"
  /bin/rm -rf "$salida"
  /bin/mkdir -p "$salida/src"
  /bin/cp src/*.js src/*.html "$salida/src/"
  /bin/cp "$manifiesto" "$salida/manifest.json"
  print "  $d → $salida  ($(ls "$salida/src" | wc -l | tr -d ' ') archivos)"
done

print ""
print "Para cargarla en Chrome, Edge o Brave:"
print "  1. Abre  chrome://extensions  (o edge://extensions, brave://extensions)"
print "  2. Activa «Modo de desarrollador»"
print "  3. «Cargar descomprimida» → elige  $(pwd)/dist/chromium"
print "  4. En sus opciones, pega la clave que muestra BtoDicta"
print ""
print "En Firefox:  about:debugging → «Este Firefox» → «Cargar complemento temporal»"
print "             → elige  $(pwd)/dist/firefox/manifest.json"
