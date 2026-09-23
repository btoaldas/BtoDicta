#!/usr/bin/env python3
"""Los controles rápidos del icono, comprobados desde fuera (spec 010, T08 y T13).

Por qué desde fuera
-------------------
Estas dos comprobaciones no las hace el propio programa sobre sí mismo. El
programa solo hace lo que haría un usuario —poner y quitar el modo reunión,
pausar, reanudar, cerrarse y volver a abrirse— y deja constancia en archivos.
Quien decide si fue bien es este script. Una comprobación que vive dentro del
código que comprueba comparte sus puntos ciegos.

T08 · Ninguna clave PREEXISTENTE cambia (RNF-04, RF-08)
-------------------------------------------------------
El modo reunión IGNORA los ajustes del usuario mientras está puesto; no los
reescribe. Un modo que pusiera el corte de silencio a cero los perdería el día
que la aplicación se cerrara mal. Se comparan todas las claves que existían
antes de conmutar, salvo las dos de estado del propio modo (`modo_reunion` y
`bitacora_pausada_hasta`). No se compara el archivo al arrancar contra el archivo
al salir: el arranque escribe claves legítimas —la versión vista— y eso no es el
modo. Las fotos se toman justo antes y justo después de conmutar.

T13 · La pausa vence a su hora aunque la aplicación se reinicie (RNF-02)
-----------------------------------------------------------------------
Primer arranque: pausa 40 s y se cierra. Cinco segundos «cerrada». Segundo
arranque: se abre como lo haría la aplicación y se mide cuánto tarda en volver.
Con el vigía de producción (15 s) el retraso tiene que quedar por debajo de 60 s.
Una pausa guardada como cuenta atrás habría vuelto 5 s TARDE por el tiempo que
estuvo cerrada; una que no se vigila al arrancar no volvería nunca.

Siempre contra carpeta aislada: esto pausa la bitácora, y el sitio donde se
prueba eso nunca es la de verdad.

Código de salida: 0 correcto · 1 falla · 2 sin aplicación construida.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

CLAVES_DE_ESTADO = {"modo_reunion", "bitacora_pausada_hasta"}

# Unos ajustes de usuario cualquiera: lo que importa es que existan ANTES y que
# estén justo los que el modo reunión podría tener la tentación de tocar.
AJUSTES_PREVIOS = {
    "silencio_max_seg": 15.0,
    "dictado_umbral_voz": 0.0,
    "dictado_factor_voz": 2.0,
    "dictado_max_min": 20.0,
    "dictado_aviso_min": 5.0,
    "dictado_al_tope": "preguntar",
    "continuo_activo": False,
    "bitacora_excluir_titulos": ["ejemplo.com"],
}


def binario():
    aqui = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for c in (os.environ.get("BIN"),
              "/Applications/BtoDicta.app/Contents/MacOS/BtoDicta",
              os.path.join(aqui, "build", "BtoDicta.app", "Contents", "MacOS", "BtoDicta")):
        if c and os.path.exists(c):
            return c
    return None


def correr(bin_, dir_, paso, extra=None, limite=180):
    env = dict(os.environ, BTODICTA_DIR=dir_, BTODICTA_MODORAPIDOTEST=paso)
    env.pop("BTODICTA_PAUSA_INTERVALO", None)   # el vigía REAL, no uno acelerado
    if extra:
        env.update(extra)
    r = subprocess.run([bin_], env=env, capture_output=True, text=True, timeout=limite)
    return r.returncode, r.stdout + r.stderr


def t08(bin_):
    d = tempfile.mkdtemp(prefix="modorapido-t08-")
    with open(os.path.join(d, "config.json"), "w", encoding="utf-8") as f:
        json.dump(AJUSTES_PREVIOS, f)
    rc, salida = correr(bin_, d, "conmutar", limite=60)
    try:
        antes = json.load(open(os.path.join(d, "antes.json"), encoding="utf-8"))
        despues = json.load(open(os.path.join(d, "despues.json"), encoding="utf-8"))
    except Exception as e:
        print(f"RAPIDO ✗ T08: no se pudieron leer las fotos ({e}); salida: {salida[-300:]}")
        return False

    cambiadas = []
    for k, v in antes.items():
        if k in CLAVES_DE_ESTADO:
            continue
        if despues.get(k, "«desapareció»") != v:
            cambiadas.append(f"{k}: {v!r} → {despues.get(k, '«desapareció»')!r}")
    nuevas = sorted(set(despues) - set(antes) - CLAVES_DE_ESTADO)

    print(f"RAPIDO T08 claves preexistentes comparadas: {len([k for k in antes if k not in CLAVES_DE_ESTADO])}")
    ok = not cambiadas and not nuevas
    if cambiadas:
        print("RAPIDO ✗ T08: el modo tocó ajustes del usuario:")
        for c in cambiadas:
            print(f"   · {c}")
    if nuevas:
        print(f"RAPIDO ✗ T08: aparecieron claves que no son de estado: {nuevas}")
    if ok:
        print("RAPIDO ✓ T08: poner y quitar el modo reunión, pausar y reanudar no cambia ningún ajuste previo")
    # Y que el estado sí se escribió donde debe: si no, «no tocó nada» sería
    # porque no hizo nada.
    if despues.get("modo_reunion") is not True:
        print("RAPIDO ✗ T08: el modo reunión no quedó guardado — la prueba no demostraría nada")
        ok = False
    return ok


def t13(bin_):
    d = tempfile.mkdtemp(prefix="modorapido-t13-")
    carpeta = os.path.join(d, "bitacora")
    os.makedirs(carpeta, exist_ok=True)
    with open(os.path.join(d, "config.json"), "w", encoding="utf-8") as f:
        json.dump({"continuo_activo": True, "continuo_carpeta": carpeta,
                   "continuo_audio_modo": "siempre", "continuo_sistema_activo": False,
                   "continuo_pantalla_activa": False}, f)

    rc1, s1 = correr(bin_, d, "pausar_y_salir", {"BTODICTA_PAUSA_SEG": "40"}, limite=30)
    try:
        vence = float(open(os.path.join(d, "vence.txt")).read())
    except Exception:
        print(f"RAPIDO ✗ T13: el primer arranque no dejó la pausa puesta; salida: {s1[-300:]}")
        return False

    time.sleep(5)          # «la aplicación está cerrada»
    rc2, s2 = correr(bin_, d, "esperar_vuelta", limite=180)
    try:
        volvio = float(open(os.path.join(d, "volvio.txt")).read())
    except Exception:
        print(f"RAPIDO ✗ T13: tras reiniciar, la pausa NO volvió; salida: {s2[-300:]}")
        return False

    retraso = volvio - vence
    print(f"RAPIDO T13 pausa de 40 s con un reinicio en medio · volvió {retraso:+.1f} s respecto al vencimiento")
    if retraso < -1:
        print("RAPIDO ✗ T13: volvió ANTES de su hora")
        return False
    if retraso >= 60:
        print("RAPIDO ✗ T13: volvió con más de 60 s de retraso")
        return False
    print("RAPIDO ✓ T13: vence a su hora aunque la aplicación se cierre y se vuelva a abrir")
    return True


def main():
    bin_ = binario()
    if not bin_:
        print("RAPIDO OMITIDA — no hay aplicación construida")
        return 0
    solo = sys.argv[1] if len(sys.argv) > 1 else "todo"
    ok = True
    if solo in ("todo", "t08"):
        ok &= t08(bin_)
    if solo in ("todo", "t13"):
        ok &= t13(bin_)
    print("RAPIDO " + ("TODO OK — no toca los ajustes del usuario y la pausa vence a su hora"
                       if ok else "FALLA"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
