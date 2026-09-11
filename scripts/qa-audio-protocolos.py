#!/usr/bin/env python3
"""Sonda local y sintética: nunca contacta servicios externos ni usa claves."""
import argparse
import http.server
import json
import pathlib
import shutil
import subprocess
import tempfile
import threading

parser = argparse.ArgumentParser()
parser.add_argument("--app", help="Ejecutable de QA de BetoDicta (opcional)")
parser.add_argument("--extension", choices=["mp3", "m3u8"], default="mp3")
args = parser.parse_args()
peticiones = []


class Servidor(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        peticiones.append(self.path)
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Servidor) as server:
    hilo = threading.Thread(target=server.serve_forever, daemon=True)
    hilo.start()
    try:
        with tempfile.TemporaryDirectory(prefix="betodicta-qa-protocolos-") as carpeta:
            origen = pathlib.Path(carpeta) / f"lista-disfrazada.{args.extension}"
            origen.write_text("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:0\n"
                              "#EXTINF:1,\nhttp://127.0.0.1:"
                              f"{server.server_port}/segmento.ts\n#EXT-X-ENDLIST\n")
            ffmpeg = shutil.which("ffmpeg")
            if not ffmpeg:
                raise SystemExit("Falta ffmpeg para esta prueba opt-in")
            resultados = []
            for nombre, extra in [("anterior", []), ("solo-file", ["-protocol_whitelist", "file"]),
                                  ("control-red", ["-f", "hls", "-protocol_whitelist", "file,http,tcp"])]:
                antes = len(peticiones)
                proceso = subprocess.run([ffmpeg, "-nostdin", "-v", "error", *extra,
                                          "-i", str(origen), "-f", "null", "-"],
                                         capture_output=True, timeout=10)
                resultados.append({"ruta": nombre, "http": len(peticiones) - antes,
                                   "exit": proceso.returncode,
                                   "diagnostico": proceso.stderr.decode(errors="replace")[:600]})
            if args.app:
                import os
                antes = len(peticiones)
                env = dict(os.environ, BETODICTA_ARCHIVOCASCADATEST=str(origen))
                proceso = subprocess.run([args.app], env=env, capture_output=True, timeout=15)
                resultados.append({"ruta": "app", "http": len(peticiones) - antes,
                                   "exit": proceso.returncode})
            print(json.dumps(resultados, indent=2, ensure_ascii=False))
            if any(r["http"] or r["exit"] == 0 for r in resultados if r["ruta"] in ("solo-file", "app")):
                raise SystemExit(1)
            if not any(r["http"] > 0 for r in resultados if r["ruta"] == "control-red"):
                raise SystemExit("La sonda no demostró capacidad de detectar peticiones HTTP")
    finally:
        server.shutdown()
        hilo.join(timeout=2)
