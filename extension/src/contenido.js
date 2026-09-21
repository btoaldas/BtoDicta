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
    const { extraerTexto, tieneCampoDeContrasena } = await import(
      chrome.runtime.getURL("src/texto.js")
    );
    const { estaExcluida, leerExcluidos } = await import(
      chrome.runtime.getURL("src/exclusiones.js")
    );

    const excluidos = await leerExcluidos();
    if (estaExcluida(location.href, excluidos)) return;   // ni se lee

    // Se espera un momento: muchas páginas cargan su contenido después del
    // primer pintado, y leerlas de inmediato devuelve un esqueleto vacío.
    await new Promise((r) => setTimeout(r, 1200));

    const texto = extraerTexto(document);
    if (!texto || texto.length < 40) return;   // una página sin contenido no aporta

    chrome.runtime.sendMessage({
      tipo: "pagina",
      url: location.href,
      titulo: document.title || "",
      texto,
      // Que la página tenga un campo de contraseña no la excluye —eso lo decide
      // la lista del usuario— pero viaja como aviso: sirve para que la propia
      // extensión pueda sugerir excluir el sitio.
      sensible: tieneCampoDeContrasena(document),
    });
  } catch {
    // Una página que no deja ejecutar guiones, un permiso retirado, una carga a
    // medias. No es un error que merezca molestar a nadie.
  }
})();
