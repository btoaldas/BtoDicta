// Extraer el texto de una página para la bitácora (spec 006, T05, RNF-03).
//
// Lo que NUNCA sale de aquí
// -------------------------
// Nada que el usuario haya escrito: campos de texto, contraseñas, áreas de
// edición. Esto **no es configurable**, y esa es la decisión: no existe un caso
// de uso legítimo en el que la bitácora necesite la contraseña que alguien acaba
// de teclear, así que tampoco existe un interruptor que pueda quedarse mal
// puesto.
//
// La diferencia importa más de lo que parece: el texto VISIBLE de una página de
// banca dice «Saldo disponible», y eso es inocuo; el VALOR de sus campos dice la
// cifra y el número de cuenta. Se guarda lo primero y nunca lo segundo.
//
// Por qué recibe el documento en vez de usar el global
// ----------------------------------------------------
// Para poder probarlo sin navegador. Una función que lee `document` por su
// cuenta solo se puede comprobar arrancando Chrome, y una prueba que cuesta
// arrancar Chrome es una prueba que no se corre.

/** Etiquetas cuyo contenido no aporta texto legible. */
const INVISIBLES = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "SVG", "CANVAS"]);

/** Lo que el usuario escribe. De aquí no se lee NADA, ni el valor ni el texto. */
const ESCRITO_POR_EL_USUARIO = new Set(["INPUT", "TEXTAREA", "SELECT", "OPTION"]);

/**
 * Texto visible de un documento, sin nada que el usuario haya escrito.
 *
 * @param {Document|Element} raiz  documento o nodo desde el que leer
 * @param {number} tope  máximo de caracteres a devolver
 * @returns {string}
 */
export function extraerTexto(raiz, tope = 20000) {
  const cuerpo = raiz && raiz.body ? raiz.body : raiz;
  if (!cuerpo) return "";

  const partes = [];
  let total = 0;

  const recorrer = (nodo) => {
    if (!nodo || total >= tope) return;

    const etiqueta = (nodo.tagName || "").toUpperCase();
    if (INVISIBLES.has(etiqueta) || ESCRITO_POR_EL_USUARIO.has(etiqueta)) return;

    // `contenteditable` es un campo de texto disfrazado de página: un editor de
    // correo, un comentario a medio escribir. Se trata como tal.
    if (typeof nodo.getAttribute === "function") {
      const editable = nodo.getAttribute("contenteditable");
      if (editable !== null && editable !== "false") return;
      // Marcar algo como oculto para lectores es una forma explícita de decir
      // «esto no es contenido».
      if (nodo.getAttribute("aria-hidden") === "true") return;
    }

    // Nodo de texto (nodeType 3): esto es lo único que se recoge.
    if (nodo.nodeType === 3) {
      const t = (nodo.nodeValue || "").replace(/\s+/g, " ").trim();
      if (t) {
        partes.push(t);
        total += t.length + 1;
      }
      return;
    }

    const hijos = nodo.childNodes || [];
    for (let i = 0; i < hijos.length && total < tope; i++) recorrer(hijos[i]);
  };

  recorrer(cuerpo);
  return partes.join(" ").slice(0, tope).trim();
}

/**
 * ¿Hay algún campo de contraseña en esta página?
 *
 * No decide por sí solo —el usuario pidió «leer todo salvo lo que excluya»—,
 * pero acompaña al informe para que la bitácora pueda decidir con ese dato, y
 * para que el aviso de la extensión pueda decir por qué una página es sensible.
 */
export function tieneCampoDeContrasena(raiz) {
  const doc = raiz && raiz.querySelectorAll ? raiz : (raiz && raiz.body ? raiz : null);
  if (!doc || typeof doc.querySelectorAll !== "function") return false;
  return doc.querySelectorAll('input[type="password"]').length > 0;
}
