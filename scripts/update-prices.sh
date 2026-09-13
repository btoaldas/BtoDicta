#!/usr/bin/env bash
#
# Actualiza los precios de los modelos de IA desde una FUENTE MANTENIDA
# (LiteLLM model_prices_and_context_window.json) — SIN usar IA/tokens.
# Escribe DOS archivos en ~/.btodicta/:
#   precios_ia.json  = { "modelo": [entrada_por_1M, salida_por_1M] }  (CHAT/pulido)
#   precios_stt.json = { "modelo": usd_por_hora_de_audio }            (TRANSCRIPCIÓN)
# La app los lee y así CUALQUIER modelo tiene precio real (estadísticas de gasto
# de chat y de voz). Correr de vez en cuando (o por el LaunchAgent).
#
# Uso: scripts/update-prices.sh
#
set -uo pipefail
DEST="$HOME/.btodicta/precios_ia.json"
DEST_STT="$HOME/.btodicta/precios_stt.json"
URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
TMP="$(mktemp)"

# Descarga completa (el archivo es grande, ~1.6MB) con reintentos.
ok=0
for i in 1 2 3; do
  curl -s --max-time 60 --retry 2 "$URL" -o "$TMP" 2>/dev/null
  if python3 -c "import json;json.load(open('$TMP'))" 2>/dev/null; then ok=1; break; fi
  sleep 2
done
[ "$ok" = 1 ] || { echo "❌ no pude bajar/parsear la fuente de precios"; rm -f "$TMP"; exit 1; }

mkdir -p "$HOME/.btodicta" && chmod 700 "$HOME/.btodicta" 2>/dev/null || true
python3 - "$TMP" "$DEST" <<'PY'
import json, sys, os
src = json.load(open(sys.argv[1]))
out = {}
for key, v in src.items():
    if not isinstance(v, dict): continue
    inp = v.get("input_cost_per_token"); o = v.get("output_cost_per_token")
    if inp is None or o is None: continue
    prov = v.get("litellm_provider", "")
    # id "desnudo" (quita SOLO el prefijo del proveedor: "groq/openai/gpt-oss-120b" → "openai/gpt-oss-120b")
    bare = key[len(prov) + 1:] if prov and key.startswith(prov + "/") else key
    # $ por 1M tokens (LiteLLM da $ por token)
    par = [round(inp * 1_000_000, 4), round(o * 1_000_000, 4)]
    # Colisión de nombre "desnudo" entre proveedores (p.ej. openai/gpt-4o-mini vs
    # azure/gpt-4o-mini): quedarse con el de MENOR (entrada+salida) — determinista,
    # conservador — en vez del último iterado (que elegía un proveedor al azar).
    if bare not in out or sum(par) < sum(out[bare]): out[bare] = par
    if bare != key and (key not in out or sum(par) < sum(out[key])): out[key] = par
json.dump(out, open(sys.argv[2], "w"))
os.chmod(sys.argv[2], 0o600)
print(f"✅ {len(out)} precios de modelos → {sys.argv[2]}")
PY

# Precios de TRANSCRIPCIÓN (STT): modelos con mode=audio_transcription. El precio
# vive en input_cost_per_second (USD/segundo de audio) → USD/hora = x3600. Caso
# borde Soniox: el costo va en output_cost_per_second. Se saltan los de solo
# per-token (gpt-4o-transcribe: no se puede convertir a $/hora sin # de tokens).
python3 - "$TMP" "$DEST_STT" <<'PY'
import json, sys, os
src = json.load(open(sys.argv[1]))
out = {}
for key, v in src.items():
    if key == "sample_spec" or not isinstance(v, dict): continue
    if v.get("mode") != "audio_transcription": continue
    ips = v.get("input_cost_per_second")
    ops = v.get("output_cost_per_second")
    per_sec = ips if (ips is not None and ips > 0) else (ops if (ops is not None and ops > 0) else None)
    if per_sec is None: continue          # sin precio por segundo utilizable → saltar
    usd_hora = round(per_sec * 3600, 4)
    prov = v.get("litellm_provider", "")
    bare = key[len(prov) + 1:] if prov and key.startswith(prov + "/") else key
    # Colisión de nombre "desnudo" entre proveedores (p.ej. whisper-large-v3-turbo
    # groq $0.04 vs watsonx $0.36): quedarse con el MENOR (estimación conservadora).
    # De todos modos, la app antepone el curado VERIFICADO a este archivo para sus
    # modelos conocidos; esto solo afecta el long-tail no curado.
    if bare not in out or usd_hora < out[bare]: out[bare] = usd_hora
    if bare != key and (key not in out or usd_hora < out[key]): out[key] = usd_hora
json.dump(out, open(sys.argv[2], "w"))
os.chmod(sys.argv[2], 0o600)
print(f"✅ {len(out)} precios de STT (audio) → {sys.argv[2]}")
PY
rm -f "$TMP"

if [ "${1:-}" = "--notify" ]; then
  n=$(python3 -c "import json;print(len(json.load(open('$DEST'))))" 2>/dev/null || echo "?")
  osascript - "Precios de IA actualizados ($n modelos)." >/dev/null 2>&1 <<'A' || true
on run argv
  display notification (item 1 of argv) with title "BtoDicta · precios"
end run
A
fi
