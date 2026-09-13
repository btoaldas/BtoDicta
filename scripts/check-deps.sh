#!/usr/bin/env bash
#
# Aviso de actualizaciones de COMPONENTES DE TERCEROS (transcribe.cpp,
# whisper.cpp, llama.cpp, mediaremote-adapter). SOLO informa — NO actualiza
# nada. Una actualización de terceros puede romper cosas, así que se revisa
# a mano antes de traerla.
#
# Uso:  scripts/check-deps.sh
#
# (Se puede correr al empezar a trabajar en BtoDicta, o programar con
#  launchd/cron. No toca la app ni instala nada; solo hace `git fetch` y
#  consulta la API pública de GitHub.)
#
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

# --notify: además de imprimir, lanza una notificación de macOS si hay algo
# nuevo (para el LaunchAgent programado).
NOTIFY=0
[ "${1:-}" = "--notify" ] && NOTIFY=1

MAN="scripts/deps.tsv"
[ -f "$MAN" ] || { echo "falta $MAN"; exit 1; }

hay_update=0
con_update=""   # nombres de componentes con novedades (para la notificación)
printf "\n\033[1mComponentes de terceros — ¿hay actualizaciones?\033[0m\n"
printf "%s\n" "------------------------------------------------------------"

# API de GitHub (usa gh si hay auth; si no, curl a la API pública).
gh_json() { # $1 = path
  if command -v gh >/dev/null 2>&1; then gh api "$1" 2>/dev/null
  else curl -s "https://api.github.com/$1"; fi
}
latest_ref() { # $1 = owner/repo → imprime "tag_o_commit fecha"
  local r="$1" tag
  tag=$(gh_json "repos/$r/releases/latest" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('tag_name','') or '', (d.get('published_at','') or '')[:10])" 2>/dev/null)
  if [ -z "${tag// /}" ]; then
    # sin releases: usa el último tag o el HEAD del branch por defecto
    tag=$(gh_json "repos/$r/tags" | python3 -c "import sys,json;a=json.load(sys.stdin);print((a[0]['name'] if a else ''),'')" 2>/dev/null)
  fi
  echo "$tag"
}

while IFS=$'\t' read -r nombre repo local || [ -n "$nombre" ]; do
  case "$nombre" in ''|\#*) continue ;; esac
  local="${local/#\~/$HOME}"
  printf "\n• \033[1m%s\033[0m (%s)\n" "$nombre" "$repo"

  if [ -n "${local:-}" ] && [ -d "$local/.git" ]; then
    cur=$(git -C "$local" rev-parse --short HEAD 2>/dev/null)
    git -C "$local" fetch -q --tags origin 2>/dev/null || true
    # branch por defecto del remoto (main/master u otro)
    def=$(git -C "$local" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
    [ -z "$def" ] && def=$(git -C "$local" rev-parse --abbrev-ref HEAD 2>/dev/null)
    behind=$(git -C "$local" rev-list --count "HEAD..origin/$def" 2>/dev/null || echo "?")
    rel=$(latest_ref "$repo")
    if [ "${behind:-0}" != "0" ] && [ "${behind:-?}" != "?" ]; then
      hay_update=1; con_update="$con_update $nombre"
      printf "  \033[33m⬆ %s commits nuevos\033[0m en origin/%s (tienes @%s)\n" "$behind" "$def" "$cur"
      printf "    último release: %s\n" "${rel:-—}"
      printf "    ver:  git -C %s log --oneline HEAD..origin/%s\n" "$local" "$def"
    else
      printf "  \033[32m✓ al día\033[0m (@%s, origin/%s) · release: %s\n" "$cur" "$def" "${rel:-—}"
    fi
  else
    rel=$(latest_ref "$repo")
    printf "  (sin repo local) último release/tag en GitHub: \033[36m%s\033[0m\n" "${rel:-—}"
    printf "    revisa manualmente si tu versión embarcada quedó atrás.\n"
  fi
done < "$MAN"

printf "\n------------------------------------------------------------\n"
if [ "$hay_update" = 1 ]; then
  printf "\033[33mHay actualizaciones de terceros.\033[0m Revísalas ANTES de traerlas\n"
  printf "(pueden romper la build). Recompila y prueba de punta a punta si actualizas.\n"
  if [ "$NOTIFY" = 1 ]; then
    msg="Motores con novedades:${con_update:- (ver detalle)}. Revisa antes de actualizar."
    # Pasa el mensaje como ARGUMENTO (dato), no interpolado en el código
    # AppleScript → evita inyección si un nombre de dep trae comillas/código.
    osascript - "$msg" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 1 of argv) with title "BtoDicta · dependencias" sound name "Ping"
end run
APPLESCRIPT
  fi
else
  printf "\033[32mTodo al día (o sin cambios detectables).\033[0m\n"
fi
