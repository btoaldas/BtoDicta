#!/usr/bin/env python3
"""¿A nombre de quién está el icono de BtoDicta en la barra? (spec 011)

Por qué existe
--------------
macOS 26 anota el icono de la barra a nombre del proceso responsable de la
aplicación. Ejecutar el binario del paquete desde una terminal lo deja apuntado
en la fila del programa dueño de esa terminal; si ese programa está bloqueado en
la barra, el icono desaparece, y el apunte se queda para los arranques normales.

Las pruebas de este proyecto lo provocaban, y un script lo reparaba reescribiendo
los ajustes de la barra. La corrección impide que ocurra. Esto comprueba que no
ocurre — **solo leyendo** la lista del sistema, sin escribir en ella.

Qué comprueba
-------------
- **RF-03/RF-04**: ninguna fila ajena alberga el icono. Si alguna lo hace, falla
  diciendo cuál. Siempre.
- **RF-02** (si BtoDicta está abierta): la lanzó el sistema —padre `launchd`— y su
  icono está dentro de la barra.
- **RNF-01**: el actualizador se relanza con `open`, no ejecutándose a sí mismo.
- **RNF-02**: el código de la aplicación no escribe en los ajustes de la barra.
- **RF-01**, solo con `--directos N`: ejecuta el binario del paquete N veces
  directamente y comprueba que, aun así, ninguna fila ajena alberga el icono. No
  va en cada pasada del QA a propósito: si la cerradura se rompiera, esa misma
  prueba envenenaría el icono del usuario, y limpiarlo exige tocar ajustes del
  sistema.

Uso
---
    qa-icono-a-su-nombre.py                         # BtoDicta, comprobación de siempre
    qa-icono-a-su-nombre.py --paquete ec.bto.otra   # otro identificador (para verla en rojo)
    qa-icono-a-su-nombre.py --directos 20           # RF-01 de punta a punta

Código de salida: 0 correcto · 1 falla.
"""
import os
import plistlib
import re
import subprocess
import sys
import tempfile

LISTA = os.path.expanduser(
    "~/Library/Group Containers/group.com.apple.controlcenter/"
    "Library/Preferences/group.com.apple.controlcenter.plist")
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def filas():
    try:
        d = plistlib.load(open(LISTA, "rb"))
        return plistlib.loads(d["trackedApplications"])
    except Exception as e:
        print(f"ICONOSUYO OMITIDA — no se pudo leer la lista de la barra ({e})")
        return None


def dueno(loc):
    if not isinstance(loc, dict):
        return str(loc)
    if "bundle" in loc:
        return loc["bundle"]["_0"]
    if "adhocBinary" in loc:
        return "(binario) " + loc["adhocBinary"]["_0"]["relative"]
    return str(loc)[:60]


def colgada_de(paquete, t):
    """Filas AJENAS que albergan el icono de `paquete`."""
    out = []
    for e in t:
        if not isinstance(e, dict) or "isAllowed" not in e:
            continue
        d = dueno(e.get("location"))
        if d == paquete:
            continue
        alberga = [dueno(u) for u in e.get("menuItemLocations", [])]
        if paquete in alberga:
            out.append(f"{d} ({'permitida' if e['isAllowed'] else 'BLOQUEADA'})")
    return out


def fila_propia(paquete, t):
    for e in t:
        if isinstance(e, dict) and "isAllowed" in e and dueno(e.get("location")) == paquete:
            return e["isAllowed"]
    return None


def comprobar_nombre(paquete):
    t = filas()
    if t is None:
        return True
    colg = colgada_de(paquete, t)
    propia = fila_propia(paquete, t)
    print(f"ICONOSUYO {paquete}: fila propia "
          f"{'no existe' if propia is None else ('permitida' if propia else 'BLOQUEADA')}")
    if colg:
        print(f"ICONOSUYO FALLA — el icono de {paquete} está apuntado a nombre de: {', '.join(colg)}")
        print("ICONOSUYO   algo ejecutó el binario del paquete desde una terminal. Se limpia a mano: make reparar-icono")
        return False
    print(f"ICONOSUYO ✓ ninguna fila ajena alberga el icono de {paquete}")
    return True


def comprobar_en_vivo():
    """RF-02: si BtoDicta está abierta, la lanzó el sistema y su icono se ve."""
    r = subprocess.run(["pgrep", "-f", "BtoDicta.app/Contents/MacOS/BtoDicta"],
                       capture_output=True, text=True)
    pids = [p for p in r.stdout.split() if p]
    if not pids:
        print("ICONOSUYO en vivo: BtoDicta no está abierta — se omite")
        return True
    ok = True
    for pid in pids:
        padre = subprocess.run(["ps", "-o", "ppid=", "-p", pid],
                               capture_output=True, text=True).stdout.strip()
        if padre != "1":
            # Una copia lanzada por otro programa (una prueba en curso) no cuenta:
            # esa, por diseño, no registra icono.
            print(f"ICONOSUYO en vivo: copia {pid} con padre {padre} — no la lanzó el sistema, no se exige icono")
            continue
        pos = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to tell (first process whose unix id is '
             f'{pid}) to get position of menu bar item 1 of menu bar 2'],
            capture_output=True, text=True).stdout.strip()
        nums = [int(n) for n in re.findall(r"-?\d+", pos)]
        if len(nums) < 2:
            print(f"ICONOSUYO en vivo: no se pudo leer la posición del icono ({pos!r}) — sin permiso de accesibilidad")
            continue
        dentro = nums[1] < 40
        print(f"ICONOSUYO {'✓' if dentro else 'FALLA —'} en vivo: la lanzó el sistema y su icono está en "
              f"{tuple(nums)}{'' if dentro else ' — FUERA de la barra'}")
        ok &= dentro
    return ok


def comprobar_actualizador():
    """RNF-01: el actualizador se relanza a través del sistema."""
    fuente = open(os.path.join(RAIZ, "Sources", "BtoDicta", "Updater.swift"), encoding="utf-8").read()
    ok = re.search(r"^\s*open /Applications/BtoDicta\.app\s*$", fuente, re.M) is not None
    print(f"ICONOSUYO {'✓' if ok else 'FALLA —'} el actualizador se relanza con `open`"
          f"{'' if ok else ': si se ejecutara a sí mismo, se quedaría sin icono tras actualizarse'}")
    return ok


def comprobar_sin_escrituras():
    """RNF-02: la aplicación no escribe en los ajustes de la barra."""
    malos = []
    carpeta = os.path.join(RAIZ, "Sources", "BtoDicta")
    for n in sorted(os.listdir(carpeta)):
        if not n.endswith(".swift"):
            continue
        texto = open(os.path.join(carpeta, n), encoding="utf-8").read()
        if "group.com.apple.controlcenter" in texto or "trackedApplications" in texto:
            malos.append(n)
    ok = not malos
    print(f"ICONOSUYO {'✓ la aplicación no toca los ajustes de la barra' if ok else 'FALLA — la aplicación toca los ajustes de la barra en: ' + ', '.join(malos)}")
    return ok


def directos(n, paquete="ec.bto.btodicta"):
    """RF-01: N arranques directos del binario del paquete no envenenan el icono."""
    binario = "/Applications/BtoDicta.app/Contents/MacOS/BtoDicta"
    if not os.path.exists(binario):
        print("ICONOSUYO RF-01 omitida — no está instalada")
        return True
    antes = colgada_de(paquete, filas() or [])
    if antes:
        print(f"ICONOSUYO RF-01 no se puede medir: ya está envenenada de antes ({antes})")
        return False
    motivo = 0
    for i in range(n):
        d = tempfile.mkdtemp(prefix="icono-directo-")
        # El arnés del icono llega justo al punto donde se crearía el icono y sale.
        r = subprocess.run([binario], env=dict(os.environ, BTODICTA_DIR=d, BTODICTA_ICONTEST="1"),
                           capture_output=True, text=True, timeout=60)
        registro = os.path.join(d, "btodicta.log")
        if os.path.exists(registro) and "icono barra: NO se registra" in open(registro, encoding="utf-8").read():
            motivo += 1
    despues = colgada_de(paquete, filas() or [])
    ok = not despues and motivo == n
    print(f"ICONOSUYO RF-01: {n} arranques directos · dejaron escrito el motivo {motivo}/{n} · "
          f"filas ajenas que la albergan: {despues or 'ninguna'}")
    print(f"ICONOSUYO {'✓' if ok else 'FALLA —'} RF-01: lanzada por otro programa, no registra su icono")
    return ok


def main():
    args = sys.argv[1:]
    paquete = args[args.index("--paquete") + 1] if "--paquete" in args else "ec.bto.btodicta"
    if "--directos" in args:
        n = int(args[args.index("--directos") + 1])
        ok = directos(n, paquete)
        print("ICONOSUYO " + ("TODO OK" if ok else "FALLA"))
        return 0 if ok else 1
    ok = comprobar_nombre(paquete)
    if paquete == "ec.bto.btodicta":
        ok &= comprobar_en_vivo()
        ok &= comprobar_actualizador()
        ok &= comprobar_sin_escrituras()
    print("ICONOSUYO " + ("TODO OK — el icono está a su nombre" if ok else "FALLA"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
