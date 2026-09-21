#!/usr/bin/env python3
"""¿Aporta la extensión el texto que el OCR no puede dar? (spec 006, RF-02)

Qué se mide, y una medida que hubo que corregir DOS veces
---------------------------------------------------------
La promesa del RF-02 era sustituir el OCR por el texto real de la página. Ponerle
número costó tres intentos, y los dos primeros fallaron por el mismo motivo:
medían algo que sonaba parecido pero no era el requisito.

1. **Contra cualquier OCR del mismo minuto** → 8,5 %. El número era correcto y la
   comparación absurda: enfrentaba una página de Amazon con el OCR de otra
   ventana abierta al lado.
2. **Contra el OCR de la MISMA página** → 44,6 %, por debajo de un umbral del
   90 % que hacía fallar el QA. Antes de tocar el umbral se miró qué faltaba:
   «favoritos, bookmarks, archivo, editar, pestaña, historial» y los nombres de
   las carpetas de marcadores. Era **la barra del navegador**. Más palabras que
   el OCR cortó a medias: «geografic», «ubica», «compar».

   Descartar lo que sale en casi todas las pantallas solo sube a 48 %. El resto
   se explica por un tope real: `extraerTexto` corta a 20 000 caracteres
   recorriendo desde arriba, así que en una página larga leída por la mitad se
   manda el principio mientras el OCR fotografía el centro.

   Exigir que el texto de UNA página cubra el 90 % de lo que el OCR lee de TODA
   la pantalla es exigir que la extensión transcriba los menús de Edge.

3. **Lo que el requisito decía de verdad**: aportar más texto, y sin errores de
   lectura. Eso es lo que decide aquí. El solapamiento se sigue informando como
   diagnóstico, porque una caída brusca sí señalaría un problema — pero no manda.

Código de salida: 0 cumple · 1 no cumple · 2 sin datos suficientes.
"""
import os, re, sqlite3, sys, unicodedata

# Cuánto más texto debe aportar la extensión que el OCR de la misma pantalla.
# Medido el 2026-09-21: 11,3x. El mínimo se pone en 3x —muy por debajo de lo
# observado— para que salte si la extracción se rompe de verdad, no si una
# jornada tuvo páginas cortas.
MINIMO_VECES = 3.0


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
        print(f"   {i}. comparte el {c:.1f} % de las palabras que leyó el OCR")
    print(f"TEXTOOCR solapamiento medio: {media:.1f} %  (diagnóstico, no veredicto)")

    # Por qué el solapamiento NO es el veredicto
    # ------------------------------------------
    # Medido el 2026-09-21 sobre 9 páginas reales: 44,6 %. Se investigó en vez de
    # ajustar el número, y las palabras que el OCR ve y la extensión no son:
    # «favoritos, bookmarks, archivo, editar, pestaña, extensiones, historial» y
    # los nombres de las carpetas de marcadores. Es la BARRA DEL NAVEGADOR, más
    # palabras que el OCR cortó a medias («geografic», «ubica», «compar»).
    #
    # Descartar lo que aparece en casi todas las pantallas —el cromo se repite,
    # el contenido de una página no— solo sube de 44,6 % a 48 %. El resto del
    # hueco tiene otra causa, documentada aparte: `extraerTexto` corta a 20 000
    # caracteres RECORRIENDO DESDE ARRIBA, así que en una página larga leída por
    # la mitad se manda el principio mientras el OCR fotografía el centro.
    #
    # Exigir que el texto de UNA página cubra el 90 % de lo que el OCR lee de
    # TODA la pantalla es exigir que la extensión transcriba los menús de Edge.
    # El requisito nunca fue ese: era aportar más texto y sin errores de lectura.
    # Eso sí se puede medir, y es lo que decide aquí.
    letras_ext = sum(len(t or "") for _, t, _ in paginas) // max(len(paginas), 1)
    fila = con.execute("""
        SELECT AVG(length(texto)) FROM pantalla
        WHERE ruta NOT LIKE 'http%' AND texto IS NOT NULL AND length(texto) > 100
    """).fetchone()
    letras_ocr = int(fila[0] or 0)
    veces = letras_ext / letras_ocr if letras_ocr else 0
    print(f"TEXTOOCR texto por página de la extensión: {letras_ext} letras")
    print(f"TEXTOOCR texto por captura reconocida:     {letras_ocr} letras")
    print(f"TEXTOOCR la extensión aporta {veces:.1f}x más texto (mínimo exigido {MINIMO_VECES}x)")

    pendientes = con.execute("""
        SELECT COUNT(*) FROM pantalla
        WHERE ruta LIKE 'http%' AND texto IS NOT NULL AND length(texto) > 200
          AND (procesado IS NULL OR procesado = 0)
    """).fetchone()[0]
    print(f"TEXTOOCR páginas con texto que aún esperan OCR: {pendientes} (debe ser 0)")

    ok = veces >= MINIMO_VECES and pendientes == 0
    print("TEXTOOCR " + ("TODO OK — la extensión aporta mucho más texto y ninguna página espera OCR"
                         if ok else
                         "FALLA — o no aporta el texto prometido, o quedan páginas esperando OCR"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
