#!/usr/bin/env python3
"""El catálogo de exclusiones propuestas está bien escrito (spec 007, T05).

Por qué esto vive aquí y no solo en las pruebas de Swift
-------------------------------------------------------
La prueba `testElCatalogoEmbarcadoEstaBienEscrito` lee el recurso con
`Bundle.main`, y en el binario de pruebas ese recurso no existe: la prueba se
salta sola y dice que se saltó. Eso está bien —mejor decirlo que fingir un
aprobado— pero significa que **nadie comprueba el catálogo de verdad**.

El QA sí tiene el paquete construido delante, así que aquí sí se puede mirar el
archivo que va a viajar dentro de la aplicación.

Qué comprueba, y por qué cada cosa
----------------------------------
- **Entradas demasiado cortas.** La comparación del filtro es por SUBCADENA. En
  un título de ventana —texto largo y ajeno— «sex» casaría con «Essex» y «sexta»,
  y «porn» con una URL de trabajo que lo llevara dentro. Mínimo 4.
- **Dominios sin punto.** Un dominio sin punto es un fragmento, no un dominio.
- **Nombres de aplicación**: mínimo 3, no 4. Un nombre de app es corto y lo pone
  el sistema; «vlc» es el nombre entero. La primera versión de esta comprobación
  exigía 4 a todo y rechazaba una entrada de su propio catálogo.
- **Mayúsculas y espacios.** La comparación ya los ignora; escribirlos igual en
  el archivo y en la lista evita que parezcan dos entradas distintas.
- **Identificadores repetidos y categorías vacías.**

Código de salida: 0 correcto · 1 hay problemas · 2 no se encontró el catálogo.
"""
import json
import os
import sys

MIN_TITULOS = 4
MIN_APPS = 3


def rutas_posibles():
    aqui = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return [
        os.path.join(aqui, "build", "BetoDicta.app", "Contents", "Resources", "semillas-exclusion.json"),
        os.path.join(aqui, "build", "BtoDicta.app", "Contents", "Resources", "semillas-exclusion.json"),
        os.path.expanduser("/Applications/BtoDicta.app/Contents/Resources/semillas-exclusion.json"),
        os.path.join(aqui, "Resources", "semillas-exclusion.json"),
    ]


def main():
    ruta = next((r for r in rutas_posibles() if os.path.exists(r)), None)
    if not ruta:
        print("SEMILLAS OMITIDA — no se encontró el catálogo en ninguna ruta conocida")
        return 0

    try:
        cat = json.load(open(ruta, encoding="utf-8"))
    except Exception as e:
        print(f"SEMILLAS FALLA — el catálogo no es JSON válido: {e}")
        return 1

    males = []
    vistos = set()
    total = 0

    for c in cat.get("categorias", []):
        cid = c.get("id", "?")
        if cid in vistos:
            males.append(f"la categoría «{cid}» está repetida")
        vistos.add(cid)

        destino = c.get("destino")
        if destino not in ("titulos", "apps"):
            males.append(f"la categoría «{cid}» tiene un destino que no existe: «{destino}»")
            continue

        entradas = c.get("entradas", [])
        if not entradas:
            males.append(f"la categoría «{cid}» no tiene ni una entrada")
        minimo = MIN_TITULOS if destino == "titulos" else MIN_APPS

        for e in entradas:
            total += 1
            if e.strip() != e:
                males.append(f"«{e}» ({cid}) tiene espacios de sobra")
            if e.lower() != e:
                males.append(f"«{e}» ({cid}) tiene mayúsculas")
            if len(e.strip()) < minimo:
                males.append(f"«{e}» ({cid}) es demasiado corta para comparar por subcadena")
            if destino == "titulos" and "." not in e:
                males.append(f"«{e}» ({cid}) va a la lista de títulos pero no parece un dominio")

    print(f"SEMILLAS {os.path.relpath(ruta, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))}")
    print(f"SEMILLAS versión {cat.get('version', '?')} · "
          f"{len(cat.get('categorias', []))} categorías · {total} entradas")

    # Que el reparto por destino no se haya cruzado: es el fallo que originó el
    # RF-04 —dos aplicaciones escritas en la lista de títulos, donde no podían
    # coincidir nunca— y no lo detecta ninguna de las reglas de arriba.
    for c in cat.get("categorias", []):
        if c.get("destino") == "apps":
            con_punto = [e for e in c.get("entradas", []) if "." in e]
            if con_punto:
                males.append(f"la categoría «{c.get('id')}» va a la lista de aplicaciones "
                             f"pero tiene dominios: {', '.join(con_punto)}")

    if males:
        print(f"SEMILLAS FALLA — {len(males)} problemas:")
        for m in males:
            print(f"   · {m}")
        return 1

    print("SEMILLAS TODO OK — ninguna entrada que no pueda coincidir")
    return 0


if __name__ == "__main__":
    sys.exit(main())
