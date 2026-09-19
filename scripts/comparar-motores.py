#!/usr/bin/env python3
"""Mide TODOS los motores con la misma vara: mismo audio, misma referencia.

Por qué existe
--------------
La cascada de failover esconde la calidad de cada motor: si el primero falla,
contesta otro y el resultado parece bueno igual. Para elegir con criterio hay
que pedir cada motor POR SU NOMBRE, sin respaldo detrás, y comparar su texto
contra uno conocido.

Dos cosas que aprendí escribiendo la primera versión y que están resueltas aquí:

1. **Guardado incremental.** La primera versión acumulaba todo en memoria y
   escribía al final. Un motor se colgó a los veinte minutos, lo corté, y perdí
   las trece medidas ya hechas. Ahora cada resultado se escribe en cuanto está.
2. **Plazo corto por motor.** Con 600 s por motor, veinte motores son horas en
   el peor caso. Un motor que no contesta en tres minutos a dos minutos de audio
   ya dijo lo que había que saber.

Uso
---
    comparar-motores.py [--audio WAV --referencia TXT] [--plazo 180]
                        [--salida comparativa.json] [--motores a,b,c]
"""
import argparse, importlib.util, json, os, pathlib, sys, time, urllib.error, urllib.request

AQUI = pathlib.Path(__file__).resolve().parent
API = "http://127.0.0.1:8787"


def cargar_comparador():
    spec = importlib.util.spec_from_file_location("q", AQUI / "qa-voz-a-texto.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


def motores_activos(token, wav):
    """La API devuelve la lista de activos al rechazar un identificador que no
    existe. Es su propia fuente de verdad: mejor que una lista escrita aquí que
    se quedaría vieja en cuanto alguien active un motor."""
    cuerpo = json.dumps({"archivo": wav, "motor": "__lista__"}).encode()
    req = urllib.request.Request(API + "/transcribir", data=cuerpo,
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=30)
        return []
    except urllib.error.HTTPError as e:
        msg = json.load(e).get("error", "")
        return [x.strip() for x in msg.split("Activos: ")[1].split(",")] if "Activos: " in msg else []


def main():
    ap = argparse.ArgumentParser()
    base = os.path.expanduser("~/Downloads/btodicta-prueba-voz")
    ap.add_argument("--audio", default=base + "/voz-local.wav")
    ap.add_argument("--referencia", default=base + "/referencia-local.txt")
    ap.add_argument("--salida", default=base + "/comparativa.json")
    ap.add_argument("--plazo", type=int, default=180)
    ap.add_argument("--motores", default="")
    a = ap.parse_args()

    q = cargar_comparador()
    token = open(os.path.expanduser("~/.btodicta/api-token")).read().strip()
    R = q.normalizar(open(a.referencia).read())
    motores = [x.strip() for x in a.motores.split(",") if x.strip()] or motores_activos(token, a.audio)
    if not motores:
        print("No pude obtener la lista de motores activos. ¿Está la API encendida?", file=sys.stderr)
        return 2

    print(f"{len(motores)} motores · {len(R)} palabras de referencia · plazo {a.plazo} s por motor\n")
    print(f"{'motor':<17}{'error':>8}{'tiempo':>9}   detalle")
    res = []
    for m in motores:
        cuerpo = json.dumps({"archivo": a.audio, "motor": m}).encode()
        req = urllib.request.Request(API + "/transcribir", data=cuerpo,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        t0 = time.time()
        fila = {"id": m}
        try:
            with urllib.request.urlopen(req, timeout=a.plazo) as r:
                d = json.load(r)
            wer, difs = q.tasa_error(R, q.normalizar(d.get("texto", "")))
            fila |= {"nombre": d.get("motor", m), "wer": round(wer * 100, 2), "ms": d.get("ms", 0),
                     "palabras": len(q.normalizar(d.get("texto", ""))), "difs": len(difs),
                     "texto": d.get("texto", "")}
            print(f"{m:<17}{wer*100:>7.2f}%{d.get('ms',0):>8} ms   {len(difs)} diferencias")
        except urllib.error.HTTPError as e:
            try: msg = json.load(e).get("error", "?")
            except Exception: msg = f"HTTP {e.code}"
            fila |= {"nombre": "—", "wer": None, "ms": int((time.time()-t0)*1000), "error": msg[:120]}
            print(f"{m:<17}{'—':>8}{'':>9}   {msg[:64]}")
        except Exception as e:
            fila |= {"nombre": "—", "wer": None, "ms": int((time.time()-t0)*1000),
                     "error": f"no contestó en {a.plazo} s" if "timed out" in str(e) else str(e)[:120]}
            print(f"{m:<17}{'—':>8}{'':>9}   {fila['error'][:64]}")
        res.append(fila)
        # En cuanto está, al disco. Un motor colgado no se lleva lo ya medido.
        json.dump(res, open(a.salida, "w"), ensure_ascii=False, indent=1)

    buenos = sorted([r for r in res if r.get("wer") is not None], key=lambda r: (r["wer"], r["ms"]))
    print(f"\n{'':-<52}\nORDEN POR CALIDAD (menos error primero):")
    for i, r in enumerate(buenos, 1):
        print(f"  {i:>2}. {r['nombre']:<34}{r['wer']:>6.2f} %{r['ms']:>8} ms")
    caidos = [r for r in res if r.get("wer") is None]
    if caidos:
        print(f"\nNO MIDIERON ({len(caidos)}):")
        for r in caidos:
            print(f"  {r['id']:<17} {r.get('error','?')[:70]}")
    print(f"\nDetalle completo: {a.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
