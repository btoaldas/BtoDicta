// Qué dominios no debe mirar la extensión (spec 006, T07, RF-05).
//
// La lista nace VACÍA. Decisión de Alberto del 2026-09-20: «todo es
// parametrizable, no existen excluyentes base aún». No se traen exclusiones
// escritas de antemano — ni banca, ni salud, ni gestores de contraseñas.
//
// Esa postura es la que más superficie deja, y por eso importa que excluir algo
// cueste dos clics desde la propia extensión y no una visita a un archivo de
// configuración: con «leer todo salvo lo excluido», la velocidad de excluir ES
// la protección.
//
// Lo que NO depende de esta lista: el contenido de los campos que el usuario
// escribe no se lee nunca, esté el dominio donde esté (ver `texto.js`).

const CLAVE = "dominios_excluidos";

/** Deja un dominio en su forma comparable: sin protocolo, sin www, minúsculas. */
export function normalizarDominio(entrada) {
  let d = String(entrada || "").trim().toLowerCase();
  if (!d) return "";
  d = d.replace(/^[a-z]+:\/\//, "");   // fuera el protocolo
  d = d.split("/")[0];                  // fuera la ruta
  d = d.split("?")[0].split("#")[0];
  d = d.replace(/^www\./, "");
  return d;
}

/** El dominio de una dirección, o cadena vacía si no se puede saber. */
export function dominioDe(url) {
  try {
    return normalizarDominio(new URL(String(url)).hostname);
  } catch {
    return "";
  }
}

/**
 * ¿Está excluida esta dirección?
 *
 * Un dominio excluido se lleva consigo sus subdominios: quien escribe
 * `banco.test` espera que valga también para `claves.banco.test`. Lo contrario
 * —tener que enumerar cada subdominio— haría la lista inútil en la práctica.
 */
export function estaExcluida(url, dominios) {
  const d = dominioDe(url);
  if (!d) return false;
  return (dominios || []).some((raw) => {
    const e = normalizarDominio(raw);
    return e && (d === e || d.endsWith("." + e));
  });
}

/** Lee la lista guardada. Vacía mientras el usuario no escriba nada. */
export async function leerExcluidos(almacen) {
  const store = almacen || (typeof chrome !== "undefined" ? chrome.storage?.local : null);
  if (!store) return [];
  const got = await store.get(CLAVE);
  const lista = got && got[CLAVE];
  return Array.isArray(lista) ? lista : [];
}

/** Guarda la lista, ya normalizada y sin repetidos. */
export async function guardarExcluidos(lista, almacen) {
  const store = almacen || (typeof chrome !== "undefined" ? chrome.storage?.local : null);
  if (!store) return [];
  const limpia = [...new Set((lista || []).map(normalizarDominio).filter(Boolean))].sort();
  await store.set({ [CLAVE]: limpia });
  return limpia;
}

/** Añade un dominio. Devuelve la lista resultante. */
export async function excluir(dominio, almacen) {
  const actuales = await leerExcluidos(almacen);
  return guardarExcluidos([...actuales, dominio], almacen);
}

/** Quita un dominio de la lista. */
export async function dejarDeExcluir(dominio, almacen) {
  const d = normalizarDominio(dominio);
  const actuales = await leerExcluidos(almacen);
  return guardarExcluidos(actuales.filter((x) => normalizarDominio(x) !== d), almacen);
}
