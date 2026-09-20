#!/usr/bin/env python3
"""Vigila qué consume BtoDicta cuando NADIE la está usando.

Para qué
--------
Una aplicación que vive todo el día en la barra de menús se juzga por lo que
gasta en reposo, no por lo que gasta trabajando. Y eso no se puede estimar
leyendo el código: hay procesos hijos que se encienden y se apagan solos,
temporizadores que despiertan cada tanto y modelos que se cargan bajo demanda.

Qué mide, y por qué así
-----------------------
- **Huella real** (`phys_footprint`), no el RSS que informa `ps`. En macOS el
  RSS cuenta páginas que el asignador ya liberó: medido el 2026-09-19 en esta
  misma aplicación, 5 564 MB de RSS con 56 MB reales. Un vigilante que mire el
  número equivocado da conclusiones equivocadas.
- **El árbol entero**, no solo el proceso principal. Los motores locales son
  procesos hijos y son los que pesan: el de embeddings retiene unos 400 MB.
- **CPU acumulada entre muestras**, que es lo que dice si algo trabaja de fondo.
  El porcentaje instantáneo de `ps` es ruido a esta escala.

Uso
---
    vigilar-reposo.py [--minutos 30] [--cada 30] [--salida informe.json]
"""
import argparse, json, os, re, subprocess, sys, time
from datetime import datetime

APP = "BtoDicta.app/Contents/MacOS/BtoDicta"


def arbol():
    """Los procesos de BtoDicta: el principal y sus hijos."""
    out = subprocess.run(["ps", "-axo", "pid=,ppid=,etime=,time=,rss=,comm="],
                         capture_output=True, text=True).stdout
    procesos = {}
    for l in out.splitlines():
        partes = l.split(None, 5)
        if len(partes) < 6:
            continue
        pid, ppid, etime, cpu, rss, comm = partes
        procesos[int(pid)] = {"ppid": int(ppid), "etime": etime, "cpu": cpu,
                              "rss": int(rss), "comm": comm}
    principal = [p for p, d in procesos.items() if d["comm"].endswith(APP.split("/")[-1])
                 and "BtoDicta.app" in d["comm"]]
    if not principal:
        return None, []
    raiz = principal[0]
    hijos = [p for p, d in procesos.items() if d["ppid"] == raiz]
    return (raiz, procesos[raiz]), [(h, procesos[h]) for h in hijos]


def huella(pid):
    """phys_footprint en MB, y el pico histórico del proceso."""
    try:
        out = subprocess.run(["footprint", "-p", str(pid)], capture_output=True,
                             text=True, timeout=20).stdout
    except Exception:
        return None, None
    def busca(campo):
        m = re.search(rf"{campo}:\s+([\d.]+)\s*(\w+)", out)
        if not m:
            return None
        v, u = float(m.group(1)), m.group(2).upper()
        return v * 1024 if u.startswith("G") else (v if u.startswith("M") else v / 1024)
    return busca("phys_footprint"), busca("phys_footprint_peak")


def seg_cpu(t):
    """`ps` da el tiempo de CPU como [dd-]hh:mm:ss[.ss]; aquí en segundos."""
    t = t.strip()
    dias = 0
    if "-" in t:
        d, t = t.split("-", 1); dias = int(d)
    p = t.split(":")
    try:
        p = [float(x) for x in p]
    except ValueError:
        return 0.0
    s = 0.0
    for x in p:
        s = s * 60 + x
    return s + dias * 86400


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--minutos", type=float, default=30)
    ap.add_argument("--cada", type=float, default=30)
    ap.add_argument("--salida", default=os.path.expanduser("~/Downloads/btodicta-reposo.json"))
    a = ap.parse_args()

    print(f"Vigilando {a.minutos:.0f} min, una muestra cada {a.cada:.0f} s.")
    print("Mide la HUELLA real (phys_footprint), no el RSS.\n")
    print(f"{'hora':<9}{'huella app':>12}{'hijos':>26}{'CPU/min':>10}")

    muestras = []
    cpu_previa, t_previo = None, None
    fin = time.time() + a.minutos * 60
    while time.time() < fin:
        raiz, hijos = arbol()
        ahora = datetime.now().strftime("%H:%M:%S")
        if raiz is None:
            print(f"{ahora:<9}  la aplicación no está corriendo")
            muestras.append({"hora": ahora, "viva": False})
            time.sleep(a.cada)
            continue
        pid, d = raiz
        h_app, pico_app = huella(pid)
        cpu_total = seg_cpu(d["cpu"])
        detalle_hijos = []
        for hp, hd in hijos:
            hh, _ = huella(hp)
            cpu_total += seg_cpu(hd["cpu"])
            detalle_hijos.append({"pid": hp, "nombre": os.path.basename(hd["comm"]).split()[0],
                                  "huellaMB": round(hh or 0, 1), "cpu_s": seg_cpu(hd["cpu"])})
        # CPU consumida DESDE la muestra anterior, normalizada a por minuto.
        cpu_min = None
        t = time.time()
        if cpu_previa is not None and t_previo is not None and t > t_previo:
            cpu_min = (cpu_total - cpu_previa) / (t - t_previo) * 60
        cpu_previa, t_previo = cpu_total, t

        total = (h_app or 0) + sum(x["huellaMB"] for x in detalle_hijos)
        resumen_hijos = ", ".join(f"{x['nombre']} {x['huellaMB']:.0f}MB" for x in detalle_hijos) or "—"
        print(f"{ahora:<9}{(h_app or 0):>9.0f} MB  {resumen_hijos:>24}  "
              f"{(f'{cpu_min:.1f} s' if cpu_min is not None else '—'):>9}")
        muestras.append({"hora": ahora, "viva": True, "huella_appMB": round(h_app or 0, 1),
                         "pico_appMB": round(pico_app or 0, 1), "hijos": detalle_hijos,
                         "totalMB": round(total, 1),
                         "cpu_s_por_min": round(cpu_min, 2) if cpu_min is not None else None})
        json.dump(muestras, open(a.salida, "w"), ensure_ascii=False, indent=1)
        time.sleep(a.cada)

    vivas = [m for m in muestras if m.get("viva")]
    if vivas:
        tot = [m["totalMB"] for m in vivas]
        cpus = [m["cpu_s_por_min"] for m in vivas if m["cpu_s_por_min"] is not None]
        print(f"\n{'':-<60}")
        print(f"RESUMEN de {len(vivas)} muestras en reposo")
        print(f"  huella del árbol : mínimo {min(tot):.0f} MB · mediana {sorted(tot)[len(tot)//2]:.0f} MB · máximo {max(tot):.0f} MB")
        if cpus:
            cpus_o = sorted(cpus)
            print(f"  CPU por minuto   : mediana {cpus_o[len(cpus_o)//2]:.2f} s · máximo {max(cpus):.2f} s")
            print(f"  (1 s de CPU por minuto ≈ 1,7 % de un núcleo)")
        nombres = {}
        for m in vivas:
            for h in m["hijos"]:
                nombres.setdefault(h["nombre"], []).append(h["huellaMB"])
        if nombres:
            print("  procesos hijos vistos:")
            for n, vs in nombres.items():
                print(f"    {n:<22} en {len(vs)}/{len(vivas)} muestras · hasta {max(vs):.0f} MB")
        else:
            print("  sin procesos hijos en ninguna muestra")
    print(f"\nDetalle: {a.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
