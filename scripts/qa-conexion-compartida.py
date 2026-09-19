#!/usr/bin/env python3
"""Guardián del fallo de 0.59.0: «Connection: close» sobre la sesión compartida.

Pedir el cierre de la conexión está bien si la sesión es propia y muere con la
petición. Sobre `URLSession.shared` —que comparte toda la aplicación— el socket
cerrado se queda en el banco del cliente y la petición SIGUIENTE espera a un
socket que ya no existe, hasta agotar su plazo. Medido en su día: seis de ocho
dictados tardaban 18,7 s en vez de 1,8.

Se corrigió en los motores de transcripción, volvió a aparecer en trece sitios
más, y por eso existe esta comprobación: es estática, corre en el QA y no depende
de que alguien se acuerde.

Salida: 0 sin hallazgos · 1 con hallazgos · 2 error de uso.
"""
import pathlib
import re
import sys

VENTANA = 40  # líneas hacia delante en las que buscar quién ejecuta la petición
EXCLUIDOS = {"VozEngine.swift"}  # servidor Python embebido: sus cabeceras son de otro protocolo

CIERRE = re.compile(r'forHTTPHeaderField:\s*"Connection"')
PROPIA = re.compile(r"URLSession\(configuration|sesionNueva\(\)|RedDictado\.sesion\(\)|sesionPropia")


def revisar(raiz: pathlib.Path) -> list[tuple[str, int, str]]:
    hallazgos = []
    for archivo in sorted(raiz.glob("*.swift")):
        if archivo.name in EXCLUIDOS:
            continue
        lineas = archivo.read_text(encoding="utf-8").split("\n")
        for i, linea in enumerate(lineas):
            if not CIERRE.search(linea) or linea.lstrip().startswith("//"):
                continue
            ventana = "\n".join(lineas[i : i + VENTANA])
            if "URLSession.shared" in ventana and not PROPIA.search(ventana):
                hallazgos.append((archivo.name, i + 1, linea.strip()))
    return hallazgos


def main() -> int:
    raiz = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Sources/BtoDicta")
    if not raiz.is_dir():
        print(f"No encuentro {raiz}", file=sys.stderr)
        return 2
    hallazgos = revisar(raiz)
    for nombre, linea, texto in hallazgos:
        print(f"  {nombre}:{linea}  {texto}")
    if hallazgos:
        print(f"\nCONEXIONES FALLA — {len(hallazgos)} peticiones piden cerrar la conexión")
        print("sobre la sesión compartida. Usa una sesión propia o quita la cabecera.")
        return 1
    print("CONEXIONES TODO OK — ninguna petición pide cerrar la sesión compartida")
    return 0


if __name__ == "__main__":
    sys.exit(main())
