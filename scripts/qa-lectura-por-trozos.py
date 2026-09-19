#!/usr/bin/env python3
"""Caza bucles que leen un archivo por trozos sin soltar lo leído.

El fallo que vigila
-------------------
`FileHandle.read(upToCount:)` devuelve un `Data` respaldado por un objeto
autoliberado. Dentro de un bucle, sin drenar el depósito en cada vuelta, los
trozos NO se sueltan: se acumulan hasta que el bucle termina. Leer un archivo
de 5 GB de a un mega retiene 5 GB.

Esto es traicionero porque el código se ve correcto. Leer por trozos es
exactamente lo que hay que hacer, y quien lo escribe cree haber resuelto el
problema de memoria. **Leer de a poco no sirve de nada si no se suelta cada
trozo.**

Casos reales encontrados el 2026-09-19:

- Comprobar la huella sha256 de los modelos al arrancar: **4 907 MB** retenidos
  en cada arranque de la aplicación.
- Detector de silencio (`esSilencio` y `pico`): 112 MB por mirar si una hora de
  audio tiene voz.

Qué acepta y qué no
-------------------
Solo mira bucles (`while` / `for`). Una lectura suelta —los 44 bytes de cabecera
de un WAV, los 8 de una firma de formato— no acumula nada y se deja pasar.

Código de salida: 0 limpio · 1 hallazgos · 2 error de uso.
"""
import re, sys, pathlib

# Cuánto contexto hacia atrás se mira buscando el `autoreleasepool` que protege.
VENTANA = 8


def revisar(raiz):
    hallazgos = []
    for f in sorted(pathlib.Path(raiz).rglob("*.swift")):
        lineas = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, l in enumerate(lineas):
            if "read(upToCount:" not in l:
                continue
            # ¿Está dentro de un bucle? Se mira hacia atrás, pero SIN cruzar el
            # comienzo de la función: si no, el `while` de la función de arriba
            # se atribuye a una lectura suelta de la siguiente y se denuncia un
            # bucle que no existe (pasó con los 44 bytes de cabecera de un WAV).
            ventana = []
            for x in reversed(lineas[max(0, i - VENTANA):i + 1]):
                ventana.append(x)
                if re.search(r"^\s*(static\s+)?func\b", x):
                    break
            en_bucle = any(re.search(r"\b(while|for)\b", x) for x in ventana)
            if not en_bucle:
                continue
            if any("autoreleasepool" in x for x in ventana):
                continue
            hallazgos.append((f, i + 1, l.strip()))
    return hallazgos


def main():
    raiz = sys.argv[1] if len(sys.argv) > 1 else "Sources"
    if not pathlib.Path(raiz).exists():
        print(f"no existe: {raiz}", file=sys.stderr)
        return 2
    h = revisar(raiz)
    if not h:
        print("LECTURAS OK — todo bucle que lee por trozos suelta lo leído")
        return 0
    print(f"LECTURAS {len(h)} bucle(s) que leen por trozos SIN soltar lo leído:")
    for f, n, txt in h:
        print(f"  {f}:{n}")
        print(f"      {txt[:100]}")
    print()
    print("  Envolver el cuerpo del bucle en `autoreleasepool { ... }`.")
    print("  Sin eso, leer un archivo grande lo retiene ENTERO en memoria,")
    print("  aunque se lea de a un mega.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
