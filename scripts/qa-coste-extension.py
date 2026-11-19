#!/usr/bin/env python3
"""Coste de la extensión en el navegador (spec 006, T18, RNF-02).

Compara Chromium oculto de Playwright con y sin la extensión sobre 10 páginas
locales y mide:
  - carga: mediana de `loadEventEnd` por página (límite: < 50 ms de diferencia);
  - trabajo del hilo principal tras cargar (CDP `ScriptDuration`), que es donde
    corre el guion de contenido (`document_idle`);
  - memoria: `phys_footprint` total de los procesos del navegador con las 10
    pestañas abiertas (límite: < 30 MB de diferencia).

Laboratorio aislado: perfil propio, una copia de la extensión que solo cambia el
puerto de la API, y un servidor simulado que concede permiso de captura y
registra lo recibido. No toca la app real (8787) ni ningún navegador del usuario.
"""
import json, os, shutil, statistics, subprocess, sys, tempfile, threading, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler, SimpleHTTPRequestHandler
from functools import partial
from pathlib import Path
from playwright.sync_api import sync_playwright

RAIZ = Path(__file__).resolve().parent.parent
TOKEN = "lab-token"
RONDAS = 3
recibidos = []


class ApiSimulada(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _json(self, codigo, cuerpo):
        datos = json.dumps(cuerpo).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(datos)))
        self.end_headers()
        self.wfile.write(datos)

    def _autorizado(self):
        return self.headers.get("Authorization") == "Bearer " + TOKEN

    def do_GET(self):
        if self.path == "/navegador/captura" and self._autorizado():
            self._json(200, {"capturando": True, "solo_grabaciones": False,
                             "generacion": 1, "inicio": time.time() - 5, "pantalla_activa": False})
        else:
            self._json(401, {})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        cuerpo = self.rfile.read(n)
        if self.path == "/navegador" and self._autorizado():
            recibidos.append(json.loads(cuerpo or b"{}"))
            self._json(200, {"ok": True})
        else:
            self._json(401, {})


def servir(handler):
    s = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s


def copiar_extension(destino: Path, manifiesto: str, puerto: int):
    (destino / "src").mkdir(parents=True)
    for f in (RAIZ / "extension/src").iterdir():
        if f.suffix in (".js", ".html"):
            (destino / "src" / f.name).write_text(f.read_text().replace("127.0.0.1:8787", f"127.0.0.1:{puerto}"))
    m = (RAIZ / "extension" / manifiesto).read_text().replace("127.0.0.1:8787", f"127.0.0.1:{puerto}")
    (destino / "manifest.json").write_text(m)


def crear_paginas(carpeta: Path):
    parrafo = ("La bitácora guarda lo que se dijo y lo que se leyó durante el día. "
               "Este párrafo se repite para dar volumen a la página de prueba. ")
    urls = []
    for i in range(10):
        repeticiones = [5, 20, 60, 120, 250, 400, 600, 900, 1200, 1600][i]
        cuerpo = "".join(f"<p>{parrafo * 3}</p>" for _ in range(repeticiones // 3 + 1))
        formulario = "<form><input name=u value=usuario><input type=password value=secreto></form>" if i == 3 else ""
        (carpeta / f"p{i}.html").write_text(
            f"<!doctype html><meta charset=utf-8><title>Página {i}</title><h1>Página {i}</h1>{formulario}{cuerpo}")
        urls.append(f"p{i}.html")
    return urls


def huella_memoria(perfil: str) -> int:
    pids = subprocess.run(["pgrep", "-f", perfil], capture_output=True, text=True).stdout.split()
    if not pids:
        return 0
    with tempfile.NamedTemporaryFile(suffix=".json") as t:
        subprocess.run(["footprint", "-j", t.name, *pids], capture_output=True)
        d = json.load(open(t.name))
    return int(d["total footprint"])


def medir(p, perfil: Path, base: str, urls, extension: Path | None, con_clave=True):
    args = []
    if extension:
        args = [f"--disable-extensions-except={extension}", f"--load-extension={extension}"]
    if extension and con_clave:
        # Sin clave al arrancar, el sondeo de permiso se aplaza 60 s: la clave se
        # guarda en un primer arranque y se mide en el segundo, ya con ella puesta.
        ctx = p.chromium.launch_persistent_context(str(perfil), headless=True, channel="chromium", args=args)
        try:
            sw = ctx.service_workers[0] if ctx.service_workers else ctx.wait_for_event("serviceworker")
            sw.evaluate(f"chrome.storage.local.set({{token: '{TOKEN}'}})")
        finally:
            ctx.close()
    ctx = p.chromium.launch_persistent_context(str(perfil), headless=True, channel="chromium", args=args)
    try:
        ctx.set_default_timeout(15000)
        carga = {u: [] for u in urls}
        guion = {u: [] for u in urls}
        for _ in range(RONDAS):
            for u in urls:
                pg = ctx.new_page()
                cdp = ctx.new_cdp_session(pg)
                cdp.send("Performance.enable")
                pg.goto(f"{base}/{u}", wait_until="load")
                carga[u].append(pg.evaluate("performance.getEntriesByType('navigation')[0].loadEventEnd"))
                pg.wait_for_timeout(1500)   # deja correr el guion de contenido (document_idle + sondeo)
                m = {x["name"]: x["value"] for x in cdp.send("Performance.getMetrics")["metrics"]}
                guion[u].append(m["ScriptDuration"] * 1000)
                pg.close()
        abiertas = [ctx.new_page() for _ in urls]
        for pg, u in zip(abiertas, urls):
            pg.goto(f"{base}/{u}", wait_until="load")
        time.sleep(4)
        memoria = huella_memoria(str(perfil))
        return ({u: statistics.median(v) for u, v in carga.items()},
                {u: statistics.median(v) for u, v in guion.items()}, memoria)
    finally:
        ctx.close()


def main():
    lab = Path(tempfile.mkdtemp(prefix="btodicta-coste-"))
    api = servir(ApiSimulada)
    paginas = lab / "paginas"; paginas.mkdir()
    urls = crear_paginas(paginas)
    class Paginas(SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
    web = servir(partial(Paginas, directory=str(paginas)))
    base = f"http://127.0.0.1:{web.server_port}"
    ext = lab / "extension"
    copiar_extension(ext, "manifest.chromium.json", api.server_port)
    # Suelo de la plataforma: una extensión MV3 vacía con trabajador de fondo y
    # guion de contenido en todas las páginas.
    vacia = lab / "vacia"; vacia.mkdir()
    (vacia / "manifest.json").write_text(json.dumps({
        "manifest_version": 3, "name": "vacia", "version": "1.0",
        "background": {"service_worker": "sw.js"},
        "content_scripts": [{"matches": ["<all_urls>"], "js": ["c.js"], "run_at": "document_idle"}]}))
    (vacia / "sw.js").write_text(""); (vacia / "c.js").write_text("")
    try:
        with sync_playwright() as p:
            sin = medir(p, lab / "perfil-sin", base, urls, None)
            con = medir(p, lab / "perfil-con", base, urls, ext)
            suelo = medir(p, lab / "perfil-vacia", base, urls, vacia, con_clave=False)
        paginas_recibidas = {r.get("url", "").rsplit("/", 1)[-1] for r in recibidos if r.get("texto")}
        print("página   carga sin  carga con   Δ ms   guion sin  guion con   Δ ms")
        deltas_carga, deltas_guion = [], []
        for u in urls:
            dc = con[0][u] - sin[0][u]; dg = con[1][u] - sin[1][u]
            deltas_carga.append(dc); deltas_guion.append(dg)
            print(f"{u:8} {sin[0][u]:9.1f} {con[0][u]:10.1f} {dc:6.1f} {sin[1][u]:10.1f} {con[1][u]:10.1f} {dg:6.1f}")
        dmem = (con[2] - sin[2]) / 1e6
        secreto = any("secreto" in (r.get("texto") or "") for r in recibidos)
        print(f"\nmemoria total: sin {sin[2]/1e6:.1f} MB · con {con[2]/1e6:.1f} MB · Δ {dmem:.1f} MB")
        print(f"suelo (extensión vacía): {suelo[2]/1e6:.1f} MB · Δ {(suelo[2]-sin[2])/1e6:.1f} MB · "
              f"propio de BtoDicta sobre el suelo: {(con[2]-suelo[2])/1e6:.1f} MB")
        print(f"páginas con texto recibido por la API simulada: {len(paginas_recibidas)}/10 · contraseña enviada: {secreto}")
        peor_carga = max(deltas_carga)
        ok = (peor_carga < 50 and dmem < 30 and len(paginas_recibidas) == 10 and not secreto)
        print(f"peor Δ de carga {peor_carga:.1f} ms (< 50) · peor Δ de guion {max(deltas_guion):.1f} ms · Δ memoria {dmem:.1f} MB (< 30)")
        print("COSTE OK" if ok else "COSTE FALLA")
        return 0 if ok else 1
    finally:
        api.shutdown(); web.shutdown()
        shutil.rmtree(lab, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
