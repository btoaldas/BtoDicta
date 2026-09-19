#!/usr/bin/env python3
"""Guardián del fallo que apareció CUATRO veces: «ya lo hice» guardado en memoria.

El resumen por correo, el aviso de saldo bajo, las rutinas de la bitácora y el
planificador de tandas guardaban en una variable estática la nota de qué habían
hecho ya. Al cerrar la aplicación esa nota desaparecía, y al reabrirla creían que
no habían hecho nada: diecisiete correos repetidos, sesenta y ocho avisos en un
día, tres resúmenes de la misma jornada.

Los cuatro se arreglaron por separado, que es justo lo que garantiza un quinto.
Esto lo busca en el código y falla si aparece uno nuevo.

Qué busca: una variable estática cuyo nombre sugiere que RECUERDA algo entre
ejecuciones, en un archivo que no guarda nada en disco ni usa `MemoriaPersistente`.

No es infalible: se guía por el nombre. Pero los cuatro casos reales lo habrían
disparado.

Salida: 0 sin hallazgos · 1 con hallazgos · 2 error de uso.
"""
import pathlib
import re
import sys

# Nombres que sugieren "recuerdo entre ejecuciones".
SOSPECHOSOS = re.compile(
    r"static var (_?(?:ultimoEnvio|ultimoDia|avisado|enviado|notificado|"
    r"ultimaHoraDisparada|yaHecho|yaAvis|procesado|hechoHoy|disparado)\w*)",
    re.IGNORECASE,
)

# Señales de que ESE archivo sí guarda en disco.
PERSISTE = re.compile(r"MemoriaPersistente|\.write\(to:|JSONSerialization\.data|UserDefaults")

# Estos ya están resueltos y usan el sitio común o su propio archivo.
CONOCIDOS = {"ResumenCorreo.swift", "SaldoAPI.swift", "ContinuoRutinas.swift",
             "ContinuoPlanificador.swift", "MemoriaPersistente.swift"}


def main() -> int:
    raiz = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Sources/BtoDicta")
    if not raiz.is_dir():
        print(f"No encuentro {raiz}", file=sys.stderr)
        return 2

    hallazgos = []
    for archivo in sorted(raiz.glob("*.swift")):
        texto = archivo.read_text(encoding="utf-8")
        persiste = bool(PERSISTE.search(texto))
        for i, linea in enumerate(texto.split("\n"), 1):
            if linea.lstrip().startswith("//"):
                continue
            m = SOSPECHOSOS.search(linea)
            if not m:
                continue
            if persiste or archivo.name in CONOCIDOS:
                continue
            hallazgos.append((archivo.name, i, m.group(1), linea.strip()))

    for nombre, linea, variable, texto in hallazgos:
        print(f"  {nombre}:{linea}  «{variable}» parece recordar algo y ese archivo no guarda nada")
        print(f"      {texto[:90]}")
    if hallazgos:
        print(f"\nMEMORIA FALLA — {len(hallazgos)} posibles «ya lo hice» que se pierden al cerrar.")
        print("Usa MemoriaPersistente, o renombra la variable si de verdad es de sesión.")
        return 1
    print("MEMORIA TODO OK — ningún «ya lo hice» nuevo guardado solo en memoria")
    return 0


if __name__ == "__main__":
    sys.exit(main())
