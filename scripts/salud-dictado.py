#!/usr/bin/env python3
"""¿Está fallando el dictado? Salud del dictado día a día, desde los registros.

Por qué existe
--------------
El dictado es lo que no puede fallar. El 24 de septiembre de 2026 hubo que
reconstruir a mano, cruzando dos registros, cuántas veces se pulsó fn fn y no se
grabó nada: hasta el 12 de septiembre, el 100 %; desde el 21, fallos sueltos que
solo un reinicio arreglaba. Esto lo deja en una llamada.

Qué cruza
---------
- El registro de texto (`btodicta.log` y los semanales comprimidos de `logs/`):
  pedidos de dictado (doble fn), fallos del micrófono, errores -10868.
- `logs/modos.jsonl`: dictados que de verdad empezaron a grabar, y entregas.

Un pedido sin arranque en los 4 s siguientes es un dictado perdido: la tecla
respondió y no se grabó nada. Se listan con lo que dijo el registro justo después.

Uso
---
    salud-dictado.py                 # desde hace 30 días
    salud-dictado.py --desde 2026-09-01
    salud-dictado.py --dir /otra/carpeta

Solo lee. Código de salida: 0 sin dictados perdidos en el periodo · 1 con alguno.
"""
import collections
import datetime
import glob
import gzip
import json
import os
import re
import sys

args = sys.argv[1:]
DIR = os.path.expanduser(args[args.index("--dir") + 1] if "--dir" in args else "~/.btodicta")
DESDE = (args[args.index("--desde") + 1] if "--desde" in args
         else (datetime.date.today() - datetime.timedelta(days=30)).isoformat())

PEDIDO = "doble pulsación reconocida — iniciar"
PATRONES = {
    "mic_fallo": r"micrófono: el dictado NO arrancó|micrófono: no pude instalar|micrófono: el motor de audio no arrancó|micrófono no disponible|dictado: el micrófono no entrega audio",
    "respaldo": r"micrófono: el dictado arrancó con el micrófono del sistema",
    "sin_ceder": r"dictado: la bitácora o el oyente no soltaron el micrófono",
    "e10868": r"-10868",
}


def lineas_texto():
    fuentes = sorted(glob.glob(os.path.join(DIR, "logs", "*.log.gz"))) + [os.path.join(DIR, "btodicta.log")]
    for f in fuentes:
        if not os.path.exists(f):
            continue
        abrir = gzip.open if f.endswith(".gz") else open
        with abrir(f, "rt", encoding="utf-8", errors="replace") as fh:
            for l in fh:
                yield l.rstrip("\n")


def cuando(l):
    m = re.match(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\]", l)
    return datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S") if m else None


dia = collections.defaultdict(collections.Counter)
inicios = []
jsonl = os.path.join(DIR, "logs", "modos.jsonl")
if os.path.exists(jsonl):
    for l in open(jsonl, encoding="utf-8", errors="replace"):
        try:
            e = json.loads(l)
        except ValueError:
            continue
        d = (e.get("fecha") or "")[:10]
        if d < DESDE:
            continue
        if e.get("ev") == "dictado_inicio":
            dia[d]["grabó"] += 1
            inicios.append(e.get("t", 0))
        elif e.get("ev") == "despacho":
            dia[d]["entregó"] += 1

todas = list(lineas_texto())
perdidos = []
for i, l in enumerate(todas):
    t = cuando(l)
    if not t or t.strftime("%Y-%m-%d") < DESDE:
        continue
    d = t.strftime("%Y-%m-%d")
    if PEDIDO in l:
        dia[d]["pedidos"] += 1
        ts = t.timestamp()
        if not any(0 <= x - ts <= 4 for x in inicios):
            dia[d]["perdidos"] += 1
            despues = [x for x in todas[i + 1:i + 40]
                       if "tap #" not in x and "reintento" not in x and "sigue ocupado" not in x][:5]
            perdidos.append((l[:21], despues))
    for k, p in PATRONES.items():
        if re.search(p, l):
            dia[d][k] += 1

cols = ["pedidos", "grabó", "perdidos", "entregó", "mic_fallo", "respaldo", "sin_ceder", "e10868"]
print("Salud del dictado desde", DESDE, "·", DIR)
print("Sin «pedidos» un día = ese día no hay registro de texto (no quiere decir que no se dictara).")
print("fecha       " + " ".join(c.rjust(9) for c in cols))
for d in sorted(dia):
    print(d + "  " + " ".join(str(dia[d][c]).rjust(9) for c in cols))

total_p = sum(v["pedidos"] for v in dia.values())
total_x = sum(v["perdidos"] for v in dia.values())
print(f"\nPedidos con registro: {total_p} · perdidos (fn fn sin grabar): {total_x}")
for cuando_, despues in perdidos[-15:]:
    print(f"\n  PERDIDO {cuando_}")
    for x in despues:
        print("    " + x[:160])
sys.exit(1 if total_x else 0)
