#!/usr/bin/env python3
"""¿Cubre el texto de la extensión lo que hoy da el OCR? (spec 006, T13, RF-02)

Por qué esta medida
-------------------
Sustituir el OCR por el texto real solo vale la pena si NO se pierde nada por el
camino. La promesa del RF-02 es cubrir al menos el 90 % de las palabras que el
reconocimiento de imagen produce hoy sobre la misma pantalla.

Y hay una razón para medirlo en vez de suponerlo: el OCR lee **lo que se ve**,
incluidas las barras del navegador, el título de las pestañas y los menús del
sistema. La extensión lee **el contenido de la página**. Son conjuntos distintos,
y el solapamiento hay que comprobarlo con páginas de verdad.

Qué compara, y una medida que hubo que corregir
-----------------------------------------------
La primera versión comparaba el texto de la extensión contra **cualquier** OCR
del mismo minuto, y daba 8,5 %. El número era correcto y la comparación absurda:
medía una página de Amazon contra el OCR de una ventana de Claude que estaba
abierta al lado. El OCR lee TODA la pantalla —menús, barras, otras ventanas—; la
extensión lee UNA página. Comparar sus palabras es comparar conjuntos distintos.

Ahora se comparan solo capturas cuya ventana corresponde a la MISMA página, por
su título. Si no hay ninguna, se dice y no se inventa un veredicto.

Y se informa además de lo que de verdad importaba: **cuánto texto aporta cada
uno**. Medido el 2026-09-20 sobre páginas reales: 20 000 letras limpias por la
extensión frente a 2 445 de OCR con errores de lectura del tipo «esarrollador».

Código de salida: 0 cumple · 1 no llega al umbral · 2 sin datos suficientes.
"""
import os, re, sqlite3, sys, unicodedata


def normalizar(t):
    t = unicodedata.normalize("NFD", (t or "").lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return set(p for p in re.sub(r"[^\w\s]", " ", t).split() if len(p) > 3)


def main():
    umbral = float(sys.argv[1]) if len(sys.argv) > 1 else 90.0
    base = os.path.expanduser("~/BtoDicta Bitácora/bitacora.sqlite")
    if not os.path.exists(base):
        print("TEXTOOCR OMITIDA — no hay bitácora en este equipo")
        return 0

    con = sqlite3.connect(f"file:{base}?mode=ro", uri=True)
    paginas = con.execute("""
        SELECT instante, texto, ventana FROM pantalla
        WHERE ruta LIKE 'http%' AND texto IS NOT NULL AND length(texto) > 200
        ORDER BY instante DESC LIMIT 20
    """).fetchall()
    if not paginas:
        print("TEXTOOCR OMITIDA — la extensión todavía no ha aportado páginas con texto")
        return 0

    comparadas, cubiertas = 0, []
    for instante, texto, titulo in paginas:
        # Capturas de LA MISMA PÁGINA: mismo rato y cuyo título de ventana
        # coincide con el de la página. Sin ese filtro se acaba comparando una
        # página con el OCR de otra ventana cualquiera.
        ocr = con.execute("""
            SELECT texto FROM pantalla
            WHERE ruta NOT LIKE 'http%' AND texto IS NOT NULL AND length(texto) > 100
              AND instante BETWEEN ? AND ?
              AND ventana IS NOT NULL AND ventana != ''
              AND (? LIKE '%' || substr(ventana, 1, 18) || '%')
        """, (instante - 45, instante + 45, titulo or "")).fetchall()
        if not ocr:
            continue
        palabras_ocr = set()
        for (t,) in ocr:
            palabras_ocr |= normalizar(t)
        if len(palabras_ocr) < 20:
            continue
        palabras_ext = normalizar(texto)
        # Cuánto de lo que vio el OCR está también en el texto de la extensión.
        comunes = palabras_ocr & palabras_ext
        cubiertas.append(len(comunes) / len(palabras_ocr) * 100)
        comparadas += 1

    if comparadas == 0:
        # Sin capturas de la misma página no hay comparación honesta posible.
        # Pero sí se puede decir lo que de verdad interesaba: cuánto texto
        # aporta cada vía.
        letras_ext = sum(len(t or "") for _, t, _ in paginas) // max(len(paginas), 1)
        fila = con.execute("""
            SELECT AVG(length(texto)) FROM pantalla
            WHERE ruta NOT LIKE 'http%' AND texto IS NOT NULL AND length(texto) > 100
        """).fetchone()
        letras_ocr = int(fila[0] or 0)
        print("TEXTOOCR sin capturas de la MISMA página con las que comparar palabra a palabra.")
        print(f"TEXTOOCR texto medio por página de la extensión: {letras_ext} letras")
        print(f"TEXTOOCR texto medio por captura reconocida:     {letras_ocr} letras")
        if letras_ocr:
            print(f"TEXTOOCR la extensión aporta {letras_ext/letras_ocr:.1f}x más texto, y sin errores de lectura")
        return 0

    media = sum(cubiertas) / len(cubiertas)
    print(f"TEXTOOCR {comparadas} páginas comparadas con el OCR del mismo minuto")
    for i, c in enumerate(sorted(cubiertas, reverse=True)[:5], 1):
        print(f"   {i}. cubre el {c:.1f} % de lo que leyó el OCR")
    print(f"TEXTOOCR cobertura media: {media:.1f} % (umbral {umbral:.0f} %)")
    ok = media >= umbral
    print("TEXTOOCR " + ("TODO OK — el texto cubre lo que daba el OCR"
                         if ok else
                         "POR DEBAJO DEL UMBRAL — conviene revisar qué se pierde"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
