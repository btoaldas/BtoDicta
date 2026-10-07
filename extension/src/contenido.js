// Lo que corre DENTRO de cada página (spec 006, RF-02).
//
// Su único trabajo es leer el texto visible y pasárselo al trabajador de fondo.
// No toca la página, no cambia nada, no escucha lo que se teclea.
//
// Por qué `import()` dinámico y no un `import` normal: en Manifest V3 los
// guiones de contenido no admiten módulos declarados en el manifiesto, así que
// el módulo se pide en tiempo de ejecución desde los recursos de la extensión.
// La alternativa sería copiar aquí la lógica de `texto.js`, y una copia del
// código que decide qué NO se lee es exactamente lo que no conviene duplicar.

(async () => {
  try {
    const navegador = globalThis.browser ?? globalThis.chrome;
    let ocupado = false;
    let ultimaLectura = "";
    async function revisar() {
      if (ocupado || document.visibilityState === "hidden") return;
      ocupado = true;
      try {
        const permiso = await navegador.runtime.sendMessage({ tipo: "permiso-captura" });
        if (permiso?.capturando !== true) { ultimaLectura = ""; return; }
        // URL, título y DOM se consultan únicamente tras obtener permiso.
        const url = location.href;
        const clave = JSON.stringify([permiso.sesion, permiso.generacion, url]);
        if (clave === ultimaLectura) return;
        const { estaExcluida, leerExcluidos } = await import(
          navegador.runtime.getURL("src/exclusiones.js")
        );
        if (estaExcluida(url, await leerExcluidos())) return;
        const { extraerTexto, tieneCampoDeContrasena } = await import(
          navegador.runtime.getURL("src/texto.js")
        );
        // Las importaciones y el almacén son asíncronos: revalidar justo antes
        // de tocar contenido, sin confiar en el permiso del sondeo anterior.
        const actual = await navegador.runtime.sendMessage({ tipo: "validar-captura" });
        if (actual?.capturando !== true || actual.sesion !== permiso.sesion
          || actual.generacion !== permiso.generacion) return;
        const instante = Date.now() / 1000;
        const texto = extraerTexto(document);
        if (!texto || texto.length < 40) return;
        await navegador.runtime.sendMessage({
          tipo: "pagina", url, titulo: document.title || "", texto,
          sensible: tieneCampoDeContrasena(document),
          sesion: permiso.sesion, generacion: permiso.generacion, instante,
        });
        ultimaLectura = clave;
      } catch {
        // Sin API, token o permiso, se conserva el estado sin leer la página.
      } finally { ocupado = false; }
    }
    // Despierta también páginas abiertas antes del dictado. El sondeo no lee
    // contenido y el fondo lo comparte entre pestañas (spec 013).
    await revisar();
    setInterval(revisar, 500);
  } catch {
    // Una página que no deja ejecutar guiones, un permiso retirado, una carga a
    // medias. No es un error que merezca molestar a nadie.
  }
})();
