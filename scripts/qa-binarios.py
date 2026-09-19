#!/usr/bin/env python3
"""Comprueba los motores que viajan dentro de la aplicación.

Se copian de carpetas de compilación del desarrollador con `if [ -x … ]` y sin
`else`: si un día esas carpetas no están, el paquete sale SIN motor local y nadie
se entera hasta que alguien intenta dictar sin internet.

Esto lo convierte en un fallo ruidoso, y de paso anota la huella de cada binario
para que se pueda ver si cambia entre versiones sin que nadie lo haya tocado.

Salida: 0 todo en orden · 1 falta algo o cambió · 2 error de uso.
"""
import hashlib
import json
import pathlib
import subprocess
import sys

# Lo que SIEMPRE tiene que viajar. Si se añade un motor, se añade aquí.
OBLIGATORIOS = {
    "whisper-cli": "transcripción local (whisper.cpp)",
    "whisper-server": "servidor de transcripción local",
    "llama-server": "motor de embeddings y de Voxtral",
    "transcribe-cli": "transcripción local alternativa",
    "libwhisper.1.dylib": "biblioteca de whisper.cpp",
    "libggml.0.dylib": "núcleo de ggml",
    "libggml-cpu.0.dylib": "ggml para CPU",
    "libggml-metal.0.dylib": "ggml para la GPU de Apple",
}

MINIMO_BYTES = 10_000  # por debajo de esto no es un binario, es un resto


def huella(ruta: pathlib.Path) -> str:
    sha = hashlib.sha256()
    with ruta.open("rb") as f:
        for trozo in iter(lambda: f.read(1_048_576), b""):
            sha.update(trozo)
    return sha.hexdigest()


def arquitectura(ruta: pathlib.Path) -> str:
    try:
        salida = subprocess.run(["/usr/bin/file", "-b", str(ruta)],
                                capture_output=True, text=True, timeout=10).stdout
        return "arm64" if "arm64" in salida else ("x86_64" if "x86_64" in salida else "?")
    except Exception:
        return "?"


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: qa-binarios.py <ruta del .app> [--escribir-registro]", file=sys.stderr)
        return 2
    bundle = pathlib.Path(sys.argv[1])
    binarios = bundle / "Contents" / "Resources" / "bin"
    if not binarios.is_dir():
        print(f"BINARIOS FALLA — no existe {binarios}")
        return 1

    fallos, tabla = [], {}
    for nombre, para_que in OBLIGATORIOS.items():
        ruta = binarios / nombre
        if not ruta.is_file():
            fallos.append(f"FALTA {nombre} ({para_que})")
            continue
        tam = ruta.stat().st_size
        if tam < MINIMO_BYTES:
            fallos.append(f"{nombre} pesa solo {tam} B — no es un binario")
            continue
        arq = arquitectura(ruta)
        if arq != "arm64":
            fallos.append(f"{nombre} es {arq}, y esta aplicación es solo Apple Silicon")
            continue
        tabla[nombre] = {"sha256": huella(ruta), "bytes": tam, "arq": arq}
        print(f"  ✓ {nombre:<24} {tam / 1_048_576:>7.1f} MB  {arq}  {tabla[nombre]['sha256'][:16]}…")

    registro = pathlib.Path(__file__).resolve().parent.parent / "docs" / "binarios-huellas.json"
    if "--escribir-registro" in sys.argv:
        registro.write_text(json.dumps(tabla, indent=2, sort_keys=True) + "\n")
        print(f"\nRegistro escrito: {registro.name}")
    elif registro.is_file():
        previo = json.loads(registro.read_text())
        for nombre, datos in tabla.items():
            antes = previo.get(nombre)
            if antes and antes["sha256"] != datos["sha256"]:
                print(f"  · {nombre} CAMBIÓ desde el registro "
                      f"({antes['bytes'] / 1_048_576:.1f} → {datos['bytes'] / 1_048_576:.1f} MB)")

    if fallos:
        for f in fallos:
            print(f"  ✗ {f}")
        print(f"\nBINARIOS FALLA — {len(fallos)} problemas. El paquete NO está completo")
        return 1
    print(f"\nBINARIOS TODO OK — los {len(tabla)} motores viajan dentro y son arm64")
    return 0


if __name__ == "__main__":
    sys.exit(main())
