#!/usr/bin/env python3
"""Caza tareas de red que se crean y nunca se arrancan.

El fallo que vigila
-------------------
`URLSession.dataTask(...)` devuelve una tarea PARADA. Sin `.resume()` no sale
ninguna petición, el closure no corre nunca y quien espera la respuesta espera
para siempre — sin error, sin tiempo agotado, sin rastro en ningún registro.

Es de los fallos más difíciles de ver leyendo código, porque lo que está escrito
parece completo: la petición, las cabeceras, el manejo de la respuesta y el de los
errores están todos ahí. Solo falta encenderlo.

Casos reales, los dos el 2026-09-19:

- `STTPoll.sondear`: dejó MUDOS a cuatro motores (AssemblyAI, Gladia, Soniox y
  Speechmatics). Los servicios recibían el audio, lo transcribían en 2-3 s, lo
  cobraban y lo dejaban listo; la aplicación no iba a recogerlo jamás.
- Speechmatics, al bajar el transcript: arreglado el primero, el motor llegó un
  paso más allá y se topó con el segundo.

Que apareciera dos veces el mismo día es lo que justifica este script.

Qué NO marca
------------
- Comentarios y documentación.
- Métodos de delegado (`func urlSession(_:dataTask:…)`), que reciben la tarea.
- `let t = …dataTask{…}` con su `t.resume()` más adelante en la función.

Código de salida: 0 limpio · 1 hallazgos · 2 error de uso.
"""
import re, sys, pathlib

CREA = re.compile(r"\b(dataTask|uploadTask|downloadTask)\s*\(")
ASIGNA = re.compile(r"\b(?:let|var)\s+(\w+)\s*(?::[^=]+)?=\s*[^=]*\b(?:dataTask|uploadTask|downloadTask)\s*\(")


def revisar(raiz):
    fallos = []
    for f in sorted(pathlib.Path(raiz).rglob("*.swift")):
        L = f.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, l in enumerate(L):
            limpia = l.strip()
            if limpia.startswith("//") or limpia.startswith("*") or limpia.startswith("///"):
                continue
            if not CREA.search(l):
                continue
            # Un método de delegado RECIBE la tarea, no la crea.
            if re.search(r"\bfunc\s+urlSession\b", l):
                continue
            if ".resume()" in l:
                continue

            # Forma «let t = …dataTask{…}»: basta con que `t.resume()` aparezca
            # después, en cualquier punto de las siguientes líneas.
            m = ASIGNA.search(l)
            if m:
                nombre = m.group(1)
                resto = "\n".join(L[i:i + 80])
                if re.search(rf"\b{re.escape(nombre)}\s*\.\s*resume\s*\(", resto):
                    continue
                fallos.append((f, i + 1, limpia[:90], f"la tarea «{nombre}» nunca se arranca"))
                continue

            # Forma encadenada «sesion().dataTask{…}.resume()»: se busca el
            # cierre del closure contando llaves, y se mira si allí resume.
            prof, arranca = 0, False
            for j in range(i, min(i + 80, len(L))):
                prof += L[j].count("{") - L[j].count("}")
                if j > i and prof <= 0:
                    cola = L[j] + (L[j + 1] if j + 1 < len(L) else "")
                    arranca = ".resume()" in cola
                    break
            if not arranca:
                fallos.append((f, i + 1, limpia[:90], "el closure se cierra sin .resume()"))
    return fallos


def main():
    raiz = sys.argv[1] if len(sys.argv) > 1 else "Sources"
    if not pathlib.Path(raiz).exists():
        print(f"no existe: {raiz}", file=sys.stderr)
        return 2
    f = revisar(raiz)
    if not f:
        print("TAREAS OK — toda petición de red que se crea, se arranca")
        return 0
    print(f"TAREAS {len(f)} petición(es) de red que se crean y NO se arrancan:")
    for ruta, n, txt, por in f:
        print(f"  {ruta}:{n}  — {por}")
        print(f"      {txt}")
    print()
    print("  Sin `.resume()` no sale ninguna petición: el closure no corre nunca")
    print("  y quien espera la respuesta se cuelga sin error y sin rastro.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
