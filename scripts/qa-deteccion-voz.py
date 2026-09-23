#!/usr/bin/env python3
"""¿La detección de voz reconoce una voz de verdad? (incidente 2026-09-22)

Por qué existe
--------------
El 2026-09-21 se corrigió que el corte por silencio no funcionara nunca: comparaba
contra el valor del medidor en vez de contra el nivel real. Se puso un umbral fijo
de 0,02, elegido midiendo el ruido de una sala vacía (0,0036) y poniéndolo cinco
veces por encima. Parecía prudente.

El 2026-09-22, en una reunión real, la voz del usuario medía entre 0,010 y 0,059.
Por DEBAJO del umbral casi todo el tiempo. El dictado se cerraba a los quince
segundos mientras él hablaba, sin aviso previo y sin dejar una línea en el
registro. Tuvo que volver a pulsar una y otra vez durante una hora de reunión.

La lección: **la separación entre voz y ruido depende del micrófono, la distancia
y la sala, y puede ser de apenas el doble.** Ningún número fijo sirve para todos,
y elegirlo midiendo solo el silencio es medir la mitad del problema.

Qué hace esta prueba
--------------------
Reproduce las grabaciones REALES de dictados —las que el usuario ya tiene en
disco— por la misma lógica que corre en la aplicación, y comprueba dos cosas:

1. Que en un dictado con habla se detecta voz, y por tanto NO se cerraría.
2. Que en uno sin habla el suelo de ruido no se confunde con voz.

No usa audio sintético a propósito: el fallo vivía justo en la diferencia entre
una sala de laboratorio y una reunión de verdad.

Código de salida: 0 correcto · 1 no detecta voz donde la hay · 2 sin grabaciones.
"""
import array
import glob
import math
import os
import sys
import wave

FACTOR = 2.0        # mismo valor de fábrica que Config.factorVozSobreRuido()
MINIMO = 0.0015     # mismo mínimo absoluto que umbralDeVozAhora
SUBIDA = 1.0002     # el suelo sube muy despacio


def recorrer(muestras, sr, ventana_ms=100):
    """Replica `umbralDeVozAhora`: suelo que baja rápido y sube despacio."""
    win = max(int(sr * ventana_ms / 1000), 1)
    suelo = 1.0
    detecciones = 0
    total = 0
    for k in range(0, len(muestras) - win, win):
        trozo = muestras[k:k + win]
        rms = math.sqrt(sum(x * x for x in trozo) / win) / 32768
        umbral = max(suelo * FACTOR, MINIMO)
        if rms > umbral:
            detecciones += 1
        if rms < suelo:
            suelo = rms
        else:
            suelo *= SUBIDA
        total += 1
    return detecciones, total, suelo


def mayor_silencio(muestras, sr):
    """El hueco más largo sin detección, en segundos: lo que decide el cierre."""
    win = max(int(sr * 100 / 1000), 1)
    suelo = 1.0
    peor = 0
    corriendo = 0
    for k in range(0, len(muestras) - win, win):
        trozo = muestras[k:k + win]
        rms = math.sqrt(sum(x * x for x in trozo) / win) / 32768
        if rms > max(suelo * FACTOR, MINIMO):
            corriendo = 0
        else:
            corriendo += 1
            peor = max(peor, corriendo)
        if rms < suelo:
            suelo = rms
        else:
            suelo *= SUBIDA
    return peor * 0.1


def main():
    # `--fijo 0.02` reproduce el fallo: así el rojo de esta prueba no es una
    # promesa del comentario, se puede volver a ver cuando se quiera.
    fijo = None
    if "--fijo" in sys.argv:
        fijo = float(sys.argv[sys.argv.index("--fijo") + 1])
        global FACTOR, MINIMO
        FACTOR, MINIMO = 0.0, fijo
        print(f"VOZ modo comparación: umbral FIJO de {fijo}")
    carpeta = os.path.expanduser("~/.btodicta/dictados")
    archivos = sorted(glob.glob(os.path.join(carpeta, "*.wav")), key=os.path.getmtime)[-12:]
    if not archivos:
        print("VOZ OMITIDA — no hay grabaciones de dictado en este equipo")
        return 0

    limite = 15.0   # el ajuste del usuario; el hueco no debe acercarse
    mal = 0
    revisados = 0
    print(f"VOZ {len(archivos)} grabaciones reales · factor {FACTOR}x sobre el suelo de ruido")
    for f in archivos:
        try:
            w = wave.open(f)
            sr = w.getframerate()
            d = w.readframes(w.getnframes())
            w.close()
        except Exception:
            continue
        a = array.array("h")
        a.frombytes(d[: len(d) // 2 * 2])
        if len(a) < sr:      # menos de un segundo: no dice nada
            continue
        dur = len(a) / sr
        det, tot, suelo = recorrer(a, sr)
        hueco = mayor_silencio(a, sr)
        revisados += 1
        # Una grabación con voz no puede tener un hueco tan largo como el límite:
        # eso es exactamente lo que cerraba el dictado a mitad de frase.
        ok = det > 0 and hueco < limite
        if not ok:
            mal += 1
        print(f"VOZ {'✓' if ok else '✗'} {os.path.basename(f)[:18]}… {dur:6.1f}s · "
              f"voz en {det}/{tot} ventanas · suelo {suelo:.4f} · "
              f"hueco mayor {hueco:.1f}s (límite {limite:.0f}s)")

    if revisados == 0:
        print("VOZ OMITIDA — ninguna grabación utilizable")
        return 0
    print("VOZ " + ("TODO OK — se detecta voz y ningún hueco llega al límite de cierre"
                    if mal == 0 else
                    f"FALLA — {mal} grabaciones se habrían cerrado con el usuario hablando"))
    return 0 if mal == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
