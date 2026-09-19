#!/usr/bin/env python3
"""Prueba de punta a punta con voz sintética y texto conocido.

Qué resuelve
------------
Todas las pruebas de audio que existían comprobaban que el audio ENTRA: que
llegan buffers, que el archivo crece, que la memoria no sube. Ninguna comprobaba
que el texto SALE COMPLETO, porque no había un texto de referencia con el que
comparar: el micrófono graba lo que haya en la sala y nadie sabe qué dijo.

Aquí el texto se escribe primero, se convierte en voz con el sintetizador del
sistema (`say`, local y gratuito), se transcribe por la API de BtoDicta y se
compara palabra por palabra contra el original.

Las dos trampas del comparador
------------------------------
1. **Los números.** El texto dice «veintitrés» y el motor escribe «23». No es un
   error de transcripción: es normalización. Un comparador ingenuo lo cuenta como
   fallo y ensucia la medida hasta hacerla inútil.
2. **La puntuación y las mayúsculas.** Un motor que puntúa mejor no transcribe
   peor. Fuera de la comparación.

Por eso se informan DOS tasas: la cruda y la normalizada. La que importa para
juzgar al motor es la normalizada; la cruda sirve para ver cuánto de la
diferencia era solo formato.

Uso
---
    qa-voz-a-texto.py --texto archivo.txt [--motor automatico|local|nube]
                      [--voz Paulina] [--salida DIR] [--repetir N]

Sin `--texto` usa el corpus incorporado (unas 500 palabras).
"""
import argparse, json, os, re, subprocess, sys, unicodedata, urllib.request, wave

# Carpetas que la API acepta. La temporal del sistema está excluida a propósito
# (la comparten todas las aplicaciones), así que el audio va a una carpeta propia.
SALIDA_POR_DEFECTO = os.path.expanduser("~/Downloads/btodicta-prueba-voz")
API = "http://127.0.0.1:8787"

CORPUS = """La unidad de infraestructura presentó el informe trimestral el martes catorce de marzo.
El equipo revisó veintitrés servidores, de los cuales dieciocho pasaron la auditoría sin observaciones.
Los cinco restantes quedaron con hallazgos menores relacionados con la rotación de credenciales.
El presupuesto asignado fue de cuarenta y siete mil doscientos dólares, distribuido en tres partidas.
La primera cubre licencias, la segunda mantenimiento preventivo, y la tercera capacitación del personal.
Se acordó que la siguiente revisión se realizará en noventa días calendario.
La migración del correo institucional avanzó según lo planificado durante el segundo semestre.
Se trasladaron cuatrocientas ochenta cuentas sin pérdida de mensajes ni interrupciones prolongadas.
El tiempo máximo de indisponibilidad registrado fue de once minutos, durante la madrugada del sábado.
Los respaldos se verificaron restaurando una copia completa en un entorno aislado.
La prueba de restauración tardó dos horas con cuarenta minutos y concluyó sin errores.
El comité técnico recomendó ampliar la retención de respaldos de treinta a noventa días.
También sugirió documentar el procedimiento de recuperación en un manual accesible al personal de turno.
Sobre la red, se detectaron intermitencias en el enlace principal durante siete jornadas consecutivas.
El proveedor atribuyó la falla a un empalme deteriorado en el tramo suburbano.
La reparación definitiva quedó programada para la primera quincena del mes siguiente.
Mientras tanto, el tráfico crítico se desvió por el enlace secundario, con capacidad reducida.
En materia de seguridad, se aplicaron ciento doce actualizaciones acumuladas en los equipos de escritorio.
Quedaron pendientes nueve estaciones que permanecían apagadas durante la ventana de mantenimiento.
El informe concluye que el estado general de la plataforma es estable y que los riesgos identificados son manejables."""


def normalizar(texto, con_numeros=True):
    """Deja el texto comparable: sin puntuación, en minúsculas, y opcionalmente
    con los números escritos con letra convertidos a dígitos."""
    t = texto.lower()
    t = "".join(c for c in unicodedata.normalize("NFD", t)
                if unicodedata.category(c) != "Mn")          # fuera las tildes
    # Los separadores de miles van ANTES que la puntuación general: si no,
    # «47.200» se parte en «47» y «200» y se contabilizan dos errores donde el
    # motor no cometió ninguno.
    t = re.sub(r"(?<=\d)[.,](?=\d{3}\b)", "", t)
    t = re.sub(r"[^\w\s]", " ", t)
    if con_numeros:
        t = _numeros_a_digitos(t)
    return t.split()


UNIDADES = {"cero":0,"uno":1,"una":1,"dos":2,"tres":3,"cuatro":4,"cinco":5,"seis":6,
            "siete":7,"ocho":8,"nueve":9,"diez":10,"once":11,"doce":12,"trece":13,
            "catorce":14,"quince":15,"dieciseis":16,"diecisiete":17,"dieciocho":18,
            "diecinueve":19,"veinte":20,"veintiuno":21,"veintidos":22,"veintitres":23,
            "veinticuatro":24,"veinticinco":25,"veintiseis":26,"veintisiete":27,
            "veintiocho":28,"veintinueve":29,"treinta":30,"cuarenta":40,"cincuenta":50,
            "sesenta":60,"setenta":70,"ochenta":80,"noventa":90,"cien":100,"ciento":100,
            "doscientos":200,"trescientos":300,"cuatrocientos":400,"quinientos":500,
            "seiscientos":600,"setecientos":700,"ochocientos":800,"novecientos":900,
            # Las formas femeninas no son un adorno: «cuatrocientas cuentas» es
            # lo normal al dictar, y sin ellas el comparador inventa un error.
            "doscientas":200,"trescientas":300,"cuatrocientas":400,"quinientas":500,
            "seiscientas":600,"setecientas":700,"ochocientas":800,"novecientas":900}


def _numeros_a_digitos(t):
    """Convierte secuencias de números escritos con letra a su valor.

    No pretende cubrir el español entero: cubre lo que aparece al dictar cifras
    —decenas, centenas, miles, y el 'y' de 'cuarenta y siete'—. Lo que no
    entiende lo deja como está, que es preferible a inventar un número.
    """
    palabras = t.split()
    fuera, i = [], 0
    while i < len(palabras):
        val, consumidas, acumulado, ultimo = None, 0, 0, None
        j, con_y = i, False
        while j < len(palabras):
            p = palabras[j]
            if p in UNIDADES:
                v = UNIDADES[p]
                # Acumular SOLO si forman un número compuesto de verdad. En
                # español eso ocurre con el «y» explícito («cuarenta y siete») o
                # bajando de escalón («cuatrocientas ochenta», «ciento veinte»).
                # Sin esta condición, «uno dos tres cuatro» se sumaba y daba 10:
                # una lista de cifras dictadas se convertía en un número solo, y
                # el comparador reportaba errores que nadie había cometido.
                escalon = ultimo is not None and v < ultimo and (
                    (ultimo >= 1000 and v < 1000)          # «cuarenta y siete mil doscientos»
                    or (ultimo >= 100 and v < 100)         # «cuatrocientas ochenta»
                    or (ultimo >= 10 and ultimo % 10 == 0 and v < 10))   # «treinta y uno»
                if ultimo is None or con_y or escalon:
                    acumulado += v; ultimo = v; consumidas = j - i + 1; val = acumulado
                    con_y = False; j += 1
                else:
                    break
            elif p == "mil":
                # «mil» también abre número («mil novecientos noventa»), no solo
                # multiplica uno ya empezado («cuarenta y siete mil»).
                acumulado = (acumulado if val is not None else 1) * 1000; ultimo = 1000
                consumidas = j - i + 1; val = acumulado; j += 1
            elif p == "y" and j + 1 < len(palabras) and palabras[j + 1] in UNIDADES and val is not None:
                con_y = True; j += 1
            else:
                break
        if val is not None and consumidas:
            fuera.append(str(val)); i += consumidas
        else:
            fuera.append(palabras[i]); i += 1
    return " ".join(fuera)


def tasa_error(ref, hip):
    """Tasa de error por palabra (WER) y las operaciones concretas.

    Distancia de edición clásica a nivel palabra. Se devuelven también las
    diferencias porque un número suelto no dice QUÉ falló, y lo que se arregla
    es lo concreto.
    """
    n, m = len(ref), len(hip)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): d[i][0] = i
    for j in range(m + 1): d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = d[i-1][j-1] if ref[i-1] == hip[j-1] else 1 + min(d[i-1][j-1], d[i-1][j], d[i][j-1])
    # Reconstruir el camino para saber qué pasó exactamente.
    difs, i, j = [], n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and ref[i-1] == hip[j-1]: i, j = i-1, j-1
        elif i > 0 and j > 0 and d[i][j] == d[i-1][j-1] + 1:
            difs.append(("cambió", ref[i-1], hip[j-1])); i, j = i-1, j-1
        elif i > 0 and d[i][j] == d[i-1][j] + 1:
            difs.append(("faltó", ref[i-1], "")); i -= 1
        else:
            difs.append(("sobró", "", hip[j-1])); j -= 1
    return (d[n][m] / n if n else 0), list(reversed(difs))


def sintetizar(texto, voz, destino):
    """Texto → voz con el sintetizador de macOS, y a WAV de 16 kHz mono."""
    txt, aiff = destino + ".txt", destino + ".aiff"
    open(txt, "w").write(texto)
    for v in ([voz] if voz else []) + ["Paulina", "Mónica", "Jorge", "Juan"]:
        if subprocess.run(["say", "-v", v, "-f", txt, "-o", aiff],
                          capture_output=True).returncode == 0:
            break
    else:
        subprocess.run(["say", "-f", txt, "-o", aiff], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                    aiff, destino], check=True)
    os.remove(aiff)
    w = wave.open(destino)
    return w.getnframes() / w.getframerate()


def transcribir(wav, motor, token, timeout):
    cuerpo = json.dumps({"archivo": wav, "motor": motor}).encode()
    req = urllib.request.Request(API + "/transcribir", data=cuerpo,
                                 headers={"Authorization": "Bearer " + token,
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--texto"); ap.add_argument("--motor", default="automatico")
    ap.add_argument("--voz", default="Paulina"); ap.add_argument("--repetir", type=int, default=1)
    ap.add_argument("--salida", default=SALIDA_POR_DEFECTO)
    ap.add_argument("--umbral", type=float, default=5.0, help="%% de error tolerado")
    a = ap.parse_args()

    texto = open(a.texto).read() if a.texto else CORPUS
    if a.repetir > 1:
        texto = "\n".join(texto for _ in range(a.repetir))
    os.makedirs(a.salida, exist_ok=True)
    wav = os.path.join(a.salida, f"voz-{a.motor}.wav")

    print(f"VOZTEXTO referencia: {len(texto.split())} palabras · voz «{a.voz}»")
    dur = sintetizar(texto, a.voz, wav)
    print(f"VOZTEXTO audio generado: {dur/60:.1f} min ({dur:.0f} s) · {os.path.getsize(wav)/2**20:.1f} MB")

    token = open(os.path.expanduser("~/.btodicta/api-token")).read().strip()
    print(f"VOZTEXTO transcribiendo por la API (motor pedido: {a.motor})…")
    r = transcribir(wav, a.motor, token, timeout=max(600, dur * 3))
    dicho = r.get("texto", "")
    open(os.path.join(a.salida, f"transcrito-{a.motor}.txt"), "w").write(dicho)
    open(os.path.join(a.salida, f"referencia-{a.motor}.txt"), "w").write(texto)
    print(f"VOZTEXTO motor real: {r.get('motor')} · {r.get('ms')} ms")

    cruda, _ = tasa_error(normalizar(texto, False), normalizar(dicho, False))
    wer, difs = tasa_error(normalizar(texto), normalizar(dicho))
    ref_n = len(normalizar(texto))
    print(f"VOZTEXTO palabras: {ref_n} dichas → {len(normalizar(dicho))} transcritas")
    print(f"VOZTEXTO error crudo (con números escritos distinto): {cruda*100:.2f} %")
    print(f"VOZTEXTO ERROR REAL (normalizado): {wer*100:.2f} %  ·  {len(difs)} diferencias")

    if difs:
        print("VOZTEXTO las primeras diferencias:")
        for tipo, r_, h_ in difs[:15]:
            print(f"VOZTEXTO   {tipo:>7}: «{r_}» → «{h_}»" if tipo == "cambió"
                  else f"VOZTEXTO   {tipo:>7}: «{r_ or h_}»")

    ok = wer * 100 <= a.umbral
    print(f"VOZTEXTO {'TODO OK' if ok else 'FALLA'} — error {wer*100:.2f} % (tolerado {a.umbral} %)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
