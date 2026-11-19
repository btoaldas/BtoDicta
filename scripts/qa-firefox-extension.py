#!/usr/bin/env python3
"""La extensión en Firefox (spec 006, T16, RF-07).

Firefox oculto con perfil temporal; la extensión se instala como complemento
temporal por el protocolo de depuración remota (lo mismo que hace `web-ext`).
Comprueba que reporta pestaña activa y audible, y que envía el texto de la
página sin la contraseña, igual que en Chromium.

Laboratorio aislado: la copia de la extensión solo cambia el puerto de la API, y
una API simulada concede permiso y registra lo que recibe. No toca la app real
(8787) ni el perfil de Firefox del usuario.
"""
import importlib.util, json, math, shutil, socket, struct, subprocess, sys, tempfile, time, wave
from functools import partial
from http.server import SimpleHTTPRequestHandler
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
FIREFOX = "/Applications/Firefox.app/Contents/MacOS/firefox"
_spec = importlib.util.spec_from_file_location("coste", RAIZ / "scripts/qa-coste-extension.py")
coste = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(coste)


class Rdp:
    """Cliente mínimo del protocolo de depuración remota de Firefox."""

    def __init__(self, puerto):
        for _ in range(100):
            try:
                self.s = socket.create_connection(("127.0.0.1", puerto), timeout=10); break
            except OSError:
                time.sleep(0.3)
        else:
            raise RuntimeError("Firefox no abrió el puerto de depuración")
        self.buf = b""
        self.leer()   # saludo del actor raíz

    def leer(self):
        while b":" not in self.buf:
            self.buf += self.s.recv(65536)
        largo, resto = self.buf.split(b":", 1)
        n = int(largo)
        while len(resto) < n:
            resto += self.s.recv(65536)
        self.buf = resto[n:]
        return json.loads(resto[:n])

    def pedir(self, to, tipo, **kw):
        datos = json.dumps({"to": to, "type": tipo, **kw}).encode()
        self.s.sendall(str(len(datos)).encode() + b":" + datos)
        while True:
            m = self.leer()
            if m.get("from") == to and ("type" not in m or m.get("type") == tipo or "error" in m):
                return m

    def consola_de_fondo(self, descriptor):
        """Consola de la página de fondo, vía el watcher de destinos."""
        watcher = self.pedir(descriptor, "getWatcher")["actor"]
        datos = json.dumps({"to": watcher, "type": "watchTargets", "targetType": "frame"}).encode()
        self.s.sendall(str(len(datos)).encode() + b":" + datos)
        consola = None
        while True:
            m = self.leer()
            if m.get("type") == "target-available-form" and "_generated_background_page" in m["target"].get("url", ""):
                consola = m["target"]["consoleActor"]
            if m.get("from") == watcher and "type" not in m:
                break
        if not consola:
            raise RuntimeError("no apareció la página de fondo de la extensión")
        return consola

    def evaluar(self, consola, codigo, espera=10):
        """Evalúa en el fondo de la extensión. Las promesas se resuelven vía global."""
        envoltorio = (f"globalThis.__qa = undefined; Promise.resolve((async () => {{ {codigo} }})())"
                      ".then(v => globalThis.__qa = JSON.stringify({ok: v}), e => globalThis.__qa = JSON.stringify({error: String(e)}))")
        self._eval(consola, envoltorio)
        fin = time.time() + espera
        while time.time() < fin:
            r = self._eval(consola, "globalThis.__qa")
            if isinstance(r, str):
                return json.loads(r)
            time.sleep(0.2)
        raise RuntimeError("la evaluación no terminó: " + codigo[:60])

    def _eval(self, consola, texto):
        datos = json.dumps({"to": consola, "type": "evaluateJSAsync", "text": texto}).encode()
        self.s.sendall(str(len(datos)).encode() + b":" + datos)
        rid = None
        while True:
            m = self.leer()
            if m.get("from") != consola:
                continue
            if "resultID" in m and m.get("type") != "evaluationResult":
                rid = m["resultID"]; continue
            if m.get("type") == "evaluationResult" and (rid is None or m.get("resultID") == rid):
                r = m.get("result")
                return r if not isinstance(r, dict) else None


def wav_con_tono(ruta: Path):
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050)
        w.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / 22050)))
                               for i in range(22050 * 20)))


def main():
    lab = Path(tempfile.mkdtemp(prefix="btodicta-firefox-"))
    api = coste.servir(coste.ApiSimulada)
    paginas = lab / "paginas"; paginas.mkdir()
    coste.crear_paginas(paginas)
    wav_con_tono(paginas / "tono.wav")
    (paginas / "audio.html").write_text("<!doctype html><title>Audio</title><audio src=tono.wav autoplay loop></audio>")

    class Paginas(SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
    web = coste.servir(partial(Paginas, directory=str(paginas)))
    base = f"http://127.0.0.1:{web.server_port}"
    ext = lab / "extension"
    coste.copiar_extension(ext, "manifest.firefox.json", api.server_port)
    perfil = lab / "perfil"; perfil.mkdir()
    (perfil / "user.js").write_text("\n".join(f'user_pref("{k}", {json.dumps(v)});' for k, v in {
        "devtools.debugger.remote-enabled": True, "devtools.chrome.enabled": True,
        "devtools.debugger.prompt-connection": False, "media.autoplay.default": 0,
        "media.autoplay.blocking_policy": 0, "media.block-autoplay-until-in-foreground": False, "browser.shell.checkDefaultBrowser": False,
        "datareporting.policy.dataSubmissionEnabled": False, "toolkit.telemetry.reportingpolicy.firstRun": False,
        "browser.aboutwelcome.enabled": False, "app.update.enabled": False,
    }.items()))
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); puerto = s.getsockname()[1]
    ff = subprocess.Popen([FIREFOX, "-headless", "-no-remote", "-profile", str(perfil),
                           "--start-debugger-server", str(puerto), "about:blank"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    comprobaciones = []
    def chk(ok, texto):
        comprobaciones.append(ok); print(("FIREFOX ✓ " if ok else "FIREFOX ✗ ") + texto)
    try:
        rdp = Rdp(puerto)
        raiz = rdp.pedir("root", "getRoot")
        inst = rdp.pedir(raiz["addonsActor"], "installTemporaryAddon", addonPath=str(ext), openDevTools=False)
        id_ext = inst.get("addon", {}).get("id")
        chk(id_ext == "extension@btodicta.bto.ec", f"se instala como complemento temporal ({id_ext or inst})")
        ext_actor = next(a for a in rdp.pedir("root", "listAddons")["addons"] if a.get("id") == id_ext)
        consola = rdp.consola_de_fondo(ext_actor["actor"])
        version = rdp.evaluar(consola, "return browser.runtime.getManifest().version")
        chk(version.get("ok") == json.loads((RAIZ / "extension/manifest.firefox.json").read_text())["version"],
            f"su fondo corre en Firefox (versión {version.get('ok')})")
        permiso = rdp.evaluar(consola, "return await browser.permissions.contains({origins: ['<all_urls>']})")
        chk(permiso.get("ok") is True, "tiene permiso sobre las páginas (<all_urls>)")
        rdp.evaluar(consola, f"await browser.storage.local.set({{token: '{coste.TOKEN}'}}); return true")
        # Sin clave al arrancar, el sondeo de permiso se aplaza 60 s (igual en Chromium).
        time.sleep(62)
        rdp.evaluar(consola, f"await browser.tabs.create({{url: '{base}/audio.html', active: false}}); return true")
        # En Firefox oculto una pestaña nueva no pasa a ser la activa (queda oculta y
        # la extensión no lee páginas ocultas): la página se carga en la activa.
        rdp.evaluar(consola, "const [t] = await browser.tabs.query({active: true, currentWindow: true}); "
                             f"await browser.tabs.update(t.id, {{url: '{base}/p3.html'}}); return true")
        fin = time.time() + 30
        while time.time() < fin:
            ultimo = next((r for r in reversed(coste.recibidos) if r.get("pestanas")), {})
            p = ultimo.get("pestanas", [])
            if any(t["activa"] and t["url"].endswith("/p3.html") for t in p) and any(t["audible"] for t in p) \
                    and any(r.get("texto") for r in coste.recibidos):
                break
            time.sleep(1)
        ultimo = next((r for r in reversed(coste.recibidos) if r.get("pestanas")), {})
        p = ultimo.get("pestanas", [])
        chk(ultimo.get("navegador") == "Firefox", f"se presenta como Firefox ({ultimo.get('navegador')})")
        chk(any(t["activa"] and t["url"].endswith("/p3.html") for t in p), "reporta la pestaña activa")
        chk(any(t["audible"] and t["url"].endswith("/audio.html") and not t["activa"] for t in p),
            "reporta la pestaña que suena, aunque no sea la activa")
        textos = [r for r in coste.recibidos if r.get("texto")]
        chk(any(r.get("url", "").endswith("/p3.html") for r in textos), "envía el texto de la página")
        chk(not any("secreto" in r["texto"] or "usuario" in r["texto"] for r in textos),
            "sin la contraseña ni el valor de los campos")
    finally:
        ff.terminate()
        try: ff.wait(10)
        except subprocess.TimeoutExpired: ff.kill()
        api.shutdown(); web.shutdown()
        shutil.rmtree(lab, ignore_errors=True)
    ok = comprobaciones and all(comprobaciones)
    print("FIREFOX TODO OK" if ok else f"FIREFOX FALLA ({comprobaciones.count(False)})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
