#!/usr/bin/env python3
"""Recupera de forma aditiva dictados reemplazados por puntajes 0..1.

Lee el texto anterior al pulido desde btodicta.log y crea, solo con --apply,
un archivo hermano `*.recuperado.txt`. Nunca reemplaza el `.txt` original.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


PUNTAJE = re.compile(r"^[+-]?[01][.,][0-9]{8,}$")
LINEA_LOG = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[[^]]+\] (.*)$")
CAMPO_CRUDO = re.compile(r"^\s*1·crudo:\s*(.*)$")
CAMPO_REGLAS = re.compile(r"^\s*2·reglas:\s*(.*)$")
CAMPO_ENTREGADO = re.compile(r"^\s*✓ entregado:\s*(.*)$")
MARCADORES_SILENCIO = {
    "(empty)", "[empty]", "<empty>", "[blank_audio]",
    "<|nospeech|>", "<|no_speech|>", "(silence)", "[silence]",
}


@dataclass
class Bloque:
    fecha: datetime
    crudo: str = ""
    reglas: str = ""
    entregado: str = ""


def sha256(datos: bytes) -> str:
    return hashlib.sha256(datos).hexdigest()


def normalizar(texto: str) -> str:
    return texto.strip()


def es_silencio(texto: str) -> bool:
    return normalizar(texto).casefold() in MARCADORES_SILENCIO


def bloques_del_log(ruta: Path) -> list[Bloque]:
    bloques: list[Bloque] = []
    actual: Bloque | None = None
    campo: str | None = None

    with ruta.open("r", encoding="utf-8", errors="replace") as archivo:
        for linea in archivo:
            limpia = linea.rstrip("\n")
            entrada = LINEA_LOG.match(limpia)
            if not entrada:
                if actual is not None and campo in {"crudo", "reglas"}:
                    previo = getattr(actual, campo)
                    setattr(actual, campo, previo + "\n" + limpia)
                continue

            fecha = datetime.strptime(entrada.group(1), "%Y-%m-%d %H:%M:%S")
            mensaje = entrada.group(2)
            campo = None
            if "──── dictado " in mensaje:
                actual = Bloque(fecha=fecha)
                continue
            if actual is None:
                continue
            if coincidencia := CAMPO_CRUDO.match(mensaje):
                actual.crudo = coincidencia.group(1)
                campo = "crudo"
            elif coincidencia := CAMPO_REGLAS.match(mensaje):
                actual.reglas = coincidencia.group(1)
                campo = "reglas"
            elif coincidencia := CAMPO_ENTREGADO.match(mensaje):
                actual.entregado = coincidencia.group(1).strip()
                actual.fecha = fecha
                bloques.append(actual)
                actual = None
    return bloques


def ruta_normalizada(ruta: Path) -> Path:
    return ruta.expanduser().resolve()


def ejecutar() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", required=True, type=Path,
                        help="raíz del historial que se inspeccionará")
    parser.add_argument("--log", required=True, type=Path,
                        help="btodicta.log que conserva el texto anterior al pulido")
    parser.add_argument("--silence-wav", action="append", default=[], type=Path,
                        help="WAV verificado acústicamente como silencio; puede repetirse")
    parser.add_argument("--apply", action="store_true",
                        help="crea los sidecars; sin esta opción solo audita")
    args = parser.parse_args()

    raiz = ruta_normalizada(args.history)
    log = ruta_normalizada(args.log)
    silencios = {ruta_normalizada(ruta) for ruta in args.silence_wav}
    if not raiz.is_dir() or not log.is_file():
        parser.error("la raíz de historial o el log no existen")

    bloques = bloques_del_log(log)
    candidatos = [ruta for ruta in raiz.rglob("*.txt")
                  if not ruta.name.endswith(".recuperado.txt")
                  and PUNTAJE.fullmatch(normalizar(ruta.read_text(encoding="utf-8", errors="replace")))]
    plan: list[dict[str, object]] = []
    pendientes: list[str] = []

    for txt in sorted(candidatos):
        puntaje = normalizar(txt.read_text(encoding="utf-8", errors="replace"))
        wav = txt.with_suffix(".wav")
        relativo = str(txt.relative_to(raiz))
        if not wav.is_file():
            pendientes.append(f"{relativo}: falta el WAV")
            continue
        fecha_wav = datetime.fromtimestamp(wav.stat().st_mtime)
        compatibles = [bloque for bloque in bloques if bloque.entregado == puntaje]
        if not compatibles:
            pendientes.append(f"{relativo}: no aparece el puntaje en el log")
            continue
        bloque = min(compatibles, key=lambda item: abs((item.fecha - fecha_wav).total_seconds()))
        distancia = abs((bloque.fecha - fecha_wav).total_seconds())
        if distancia > 5:
            pendientes.append(f"{relativo}: el bloque más cercano está a {distancia:.0f} s")
            continue

        recuperado = normalizar(bloque.reglas or bloque.crudo)
        fuente = "reglas" if bloque.reglas else "crudo"
        if es_silencio(recuperado):
            if ruta_normalizada(wav) not in silencios:
                pendientes.append(f"{relativo}: el log contiene marcador de silencio sin verificar")
                continue
            recuperado = ""
            fuente = "silencio_verificado"
        if recuperado and PUNTAJE.fullmatch(recuperado):
            pendientes.append(f"{relativo}: la fuente recuperada también es un puntaje")
            continue

        salida = txt.with_suffix(".recuperado.txt")
        datos_originales = txt.read_bytes()
        datos_salida = (recuperado + ("\n" if recuperado else "")).encode("utf-8")
        plan.append({
            "txt": txt,
            "wav": wav,
            "salida": salida,
            "datos": datos_salida,
            "fuente": fuente,
            "original_sha256": sha256(datos_originales),
            "wav_sha256": sha256(wav.read_bytes()),
        })

    if pendientes:
        print(json.dumps({"ok": False, "listos": len(plan), "pendientes": pendientes},
                         ensure_ascii=False, indent=2))
        return 2

    # Preflight global: si algo difiere, no se crea ni un solo archivo.
    for item in plan:
        salida = item["salida"]
        assert isinstance(salida, Path)
        if salida.exists() and salida.read_bytes() != item["datos"]:
            print(json.dumps({"ok": False, "error": f"me niego a sobrescribir {salida.relative_to(raiz)}"},
                             ensure_ascii=False, indent=2))
            return 3

    if args.apply:
        for item in plan:
            salida = item["salida"]
            datos = item["datos"]
            txt = item["txt"]
            assert isinstance(salida, Path) and isinstance(datos, bytes) and isinstance(txt, Path)
            if not salida.exists():
                with salida.open("xb") as archivo:
                    archivo.write(datos)
                    archivo.flush()
                    os.fsync(archivo.fileno())
                os.chmod(salida, stat.S_IMODE(txt.stat().st_mode))

    informe = []
    for item in plan:
        txt = item["txt"]
        salida = item["salida"]
        datos = item["datos"]
        assert isinstance(txt, Path) and isinstance(salida, Path) and isinstance(datos, bytes)
        original_intacto = sha256(txt.read_bytes()) == item["original_sha256"]
        sidecar_ok = (not args.apply) or (salida.is_file() and salida.read_bytes() == datos)
        informe.append({
            "archivo": str(txt.relative_to(raiz)),
            "salida": str(salida.relative_to(raiz)),
            "fuente": item["fuente"],
            "caracteres": len(datos.decode("utf-8").rstrip("\n")),
            "sha256": sha256(datos),
            "original_intacto": original_intacto,
            "sidecar_verificado": sidecar_ok,
        })

    ok = len(plan) == len(candidatos) and all(
        item["original_intacto"] and item["sidecar_verificado"] for item in informe)
    print(json.dumps({
        "ok": ok,
        "modo": "apply" if args.apply else "dry-run",
        "detectados": len(candidatos),
        "recuperables": len(plan),
        "archivos": informe,
    }, ensure_ascii=False, indent=2))
    return 0 if ok else 4


if __name__ == "__main__":
    sys.exit(ejecutar())
