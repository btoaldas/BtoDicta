#!/usr/bin/env node
// Pruebas de la extensión (spec 006, T06 y T08).
//
// Sin dependencias y sin navegador. Una prueba que exige arrancar Chrome es una
// prueba que no se corre, y lo que aquí se comprueba —que no se lea lo que el
// usuario escribe— es justo lo que no puede quedar sin comprobar.
//
// El DOM de abajo es mínimo a propósito: solo lo que `extraerTexto` recorre.
// Construirlo a mano cuesta veinte líneas y evita arrastrar una dependencia
// entera para leer un formulario de mentira.

import { extraerTexto, tieneCampoDeContrasena } from "../src/texto.js";
import {
  normalizarDominio, dominioDe, estaExcluida,
  leerExcluidos, guardarExcluidos, excluir, dejarDeExcluir,
} from "../src/exclusiones.js";

let mal = 0;
const chk = (ok, q) => { console.log(`EXTENSION ${ok ? "✓" : "✗"} ${q}`); if (!ok) mal++; };

// ---------- DOM mínimo ----------

const texto = (valor) => ({ nodeType: 3, nodeValue: valor, childNodes: [] });
const el = (tagName, hijos = [], atributos = {}) => ({
  nodeType: 1,
  tagName,
  childNodes: hijos,
  getAttribute: (n) => (n in atributos ? atributos[n] : null),
});
const documento = (cuerpo, campos = []) => ({
  body: cuerpo,
  querySelectorAll: (sel) =>
    sel === 'input[type="password"]' ? campos.filter((c) => c === "password") : [],
});

// ---------- T06: nada de lo que el usuario escribe ----------
//
// El caso REAL que preocupa: una página de acceso. El texto visible («Usuario»,
// «Contraseña», «Entrar») es inocuo y debe guardarse; lo tecleado, jamás.

const USUARIO = "alberto.prueba";
const CLAVE_SECRETA = "ClaveDePrueba-NoReal-98765";

const login = documento(
  el("DIV", [
    el("H1", [texto("Acceso al sistema")]),
    el("LABEL", [texto("Usuario")]),
    el("INPUT", [texto(USUARIO)], { type: "text", value: USUARIO }),
    el("LABEL", [texto("Contraseña")]),
    el("INPUT", [texto(CLAVE_SECRETA)], { type: "password", value: CLAVE_SECRETA }),
    el("BUTTON", [texto("Entrar")]),
  ]),
  ["password"],
);

const extraido = extraerTexto(login);
chk(extraido.includes("Acceso al sistema"), "el texto visible de la página sí se lee");
chk(extraido.includes("Usuario") && extraido.includes("Contraseña"),
    "las etiquetas de los campos también: son contenido, no datos");
chk(!extraido.includes(CLAVE_SECRETA), "la CONTRASEÑA escrita NO aparece por ninguna parte");
chk(!extraido.includes(USUARIO), "ni el usuario escrito");
chk(tieneCampoDeContrasena(login), "y la página queda marcada como sensible");

// Un editor de correo a medio escribir es un campo de texto disfrazado.
const borrador = documento(el("DIV", [
  el("H2", [texto("Redactar")]),
  el("DIV", [texto("querido cliente, le adjunto la factura secreta")], { contenteditable: "true" }),
]));
const textoBorrador = extraerTexto(borrador);
chk(textoBorrador.includes("Redactar"), "el título de la página se lee");
chk(!textoBorrador.includes("factura secreta"),
    "lo escrito en un área editable NO se lee: es un campo disfrazado de página");

// Y lo que está marcado como oculto para lectores no es contenido.
const conOculto = documento(el("DIV", [
  el("P", [texto("visible")]),
  el("P", [texto("tecnicismo invisible")], { "aria-hidden": "true" }),
]));
chk(extraerTexto(conOculto).includes("visible"), "se lee lo visible");
chk(!extraerTexto(conOculto).includes("tecnicismo invisible"), "y no lo marcado como oculto");

// El tope corta, para que una página enorme no dispare el envío.
const largo = documento(el("DIV", [texto("palabra ".repeat(9000))]));
chk(extraerTexto(largo, 500).length <= 500, "el texto se corta en el tope pedido");

// ---------- T08: la lista de dominios ----------

chk(normalizarDominio("HTTPS://WWW.Ejemplo.TEST/algo?x=1") === "ejemplo.test",
    "un dominio se normaliza: sin protocolo, sin www, sin ruta");
chk(dominioDe("https://sub.ejemplo.test/x") === "sub.ejemplo.test", "se extrae el dominio de una dirección");
chk(dominioDe("no es una url") === "", "y una dirección inválida no da dominio");

chk(estaExcluida("https://banco.test/cuenta", ["banco.test"]), "un dominio excluido queda fuera");
chk(estaExcluida("https://claves.banco.test/x", ["banco.test"]),
    "y sus subdominios también: enumerarlos uno a uno haría la lista inútil");
chk(!estaExcluida("https://otrobanco.test/x", ["banco.test"]),
    "pero no un dominio que solo se le parece");
chk(!estaExcluida("https://ejemplo.test/x", []), "con la lista VACÍA no se excluye nada");

// Almacén de mentira, con la misma forma que el del navegador.
const almacen = (() => {
  let datos = {};
  return {
    get: async (k) => ({ [k]: datos[k] }),
    set: async (o) => { datos = { ...datos, ...o }; },
    _ver: () => datos,
  };
})();

const vacio = await leerExcluidos(almacen);
chk(Array.isArray(vacio) && vacio.length === 0, "de fábrica la lista está VACÍA");

await excluir("https://www.Ejemplo.TEST/ruta", almacen);
const trasUno = await leerExcluidos(almacen);
chk(trasUno.length === 1 && trasUno[0] === "ejemplo.test", "añadir un dominio lo guarda normalizado");
chk(estaExcluida("https://ejemplo.test/lo-que-sea", trasUno),
    "y a partir de ahí ese dominio deja de reportarse");

await excluir("ejemplo.test", almacen);
chk((await leerExcluidos(almacen)).length === 1, "añadirlo dos veces no lo duplica");

await dejarDeExcluir("ejemplo.test", almacen);
chk((await leerExcluidos(almacen)).length === 0, "y se puede quitar");

await guardarExcluidos(["  ", "", "b.test", "a.test"], almacen);
const orden = await leerExcluidos(almacen);
chk(orden.join(",") === "a.test,b.test", "las entradas vacías se descartan y la lista queda ordenada");

// ---------- T09: qué se cuenta de cada pestaña ----------
//
// El caso que da sentido a toda la extensión: un vídeo sonando en una pestaña
// mientras se trabaja en otra. Eso es lo que macOS no puede ver.

const { fotografiar } = await import("../src/fondo.js");

const abiertas = [
  { url: "https://correo.test/bandeja", title: "Bandeja", active: true,  audible: false },
  { url: "https://videos.test/watch?v=1", title: "Un vídeo", active: false, audible: true },
  { url: "https://banco.test/cuenta",    title: "Mi cuenta", active: false, audible: false },
];

const foto = await fotografiar({ pestañas: abiertas, excluidos: [] });
chk(foto.pestanas.length === 3, "se cuentan las tres pestañas");
chk(foto.pestanas.find((p) => p.activa)?.url.includes("correo"), "la activa es la del correo");
chk(foto.pestanas.find((p) => p.audible)?.url.includes("videos"),
    "y la que suena es la del vídeo, con el correo delante");

// Con un dominio excluido: se sigue sabiendo que ALGO suena, pero no qué es.
const conExcluido = await fotografiar({ pestañas: abiertas, excluidos: ["banco.test", "videos.test"] });
const vid = conExcluido.pestanas[1];
chk(vid.url === "" && vid.titulo === "", "de un dominio excluido no se dice ni la dirección ni el título");
chk(vid.audible === true,
    "pero SÍ que suena: es un dato sin contenido, y es el que evita anotar una película como trabajo");
chk(conExcluido.pestanas[2].url === "", "y la pestaña del banco queda muda del todo");
chk(conExcluido.pestanas[0].url.includes("correo"), "mientras lo no excluido se sigue contando entero");

// ---------- T10: el envío no acumula ----------

const { reiniciarEspera, esperaRestante, enviar: enviarDeVerdad } = await import("../src/enviar.js");

// Sin navegador no hay almacén ni token: el envío no debe lanzar, solo fallar.
reiniciarEspera();
let lanzo = false;
try { await enviarDeVerdad("/navegador", { x: 1 }); } catch { lanzo = true; }
chk(!lanzo, "un envío imposible no lanza: un sensor no puede tumbar el navegador");
chk(esperaRestante() >= 0, "y queda un tiempo de espera medible antes del siguiente intento");

// ---------- Que las pantallas ARRANQUEN DE VERDAD ----------
//
// Este guardián nace de un fallo que no dio ningún error, y de un primer intento
// de guardián que tampoco lo vio.
//
// Qué pasó: una edición dejó `pintarToken`, `pintarDiagnostico` y los dos
// `addEventListener` de los botones metidos DENTRO del callback de otro botón,
// dentro de un bucle. El archivo seguía siendo JavaScript válido —`node --check`
// lo aprobaba— pero al abrir la pantalla el botón de guardar la clave no tenía
// listener: pulsarlo no hacía absolutamente nada, sin un solo error a la vista.
//
// El primer guardián buscaba el TEXTO `pintarDiagnostico();` en el archivo. Ese
// texto estaba —en la última línea, intacto— así que daba verde mientras el
// usuario miraba una pantalla muerta. **Comprobar una cadena no es comprobar un
// comportamiento.** Ahora se carga la pantalla contra un DOM de mentira y se
// mira lo único que importa: que los botones queden enganchados y que lo que se
// pinta al abrir, se pinte.

function pantallaDeMentira() {
  const nodos = new Map();
  const nuevo = (id) => ({
    id,
    oyentes: [],
    hijos: [],
    textContent: "",
    value: "",
    className: "",
    style: {},
    addEventListener(ev, fn) { this.oyentes.push([ev, fn]); },
    append(...h) { this.hijos.push(...h); },
    replaceChildren(...h) { this.hijos = h; },
    focus() {},
  });
  return {
    nodos,
    doc: {
      getElementById(id) {
        if (!nodos.has(id)) nodos.set(id, nuevo(id));
        return nodos.get(id);
      },
      createElement: (tag) => nuevo("<" + tag + ">"),
    },
  };
}

/** Carga un módulo de pantalla con DOM falso y devuelve sus nodos. */
async function abrirPantalla(ruta) {
  const { nodos, doc } = pantallaDeMentira();
  globalThis.document = doc;
  // `fetch` se anula para que la prueba no dependa de que BtoDicta esté abierta:
  // una prueba que pasa o falla según qué haya corriendo en la Mac no prueba nada.
  globalThis.fetch = async () => { throw new Error("sin red en la prueba"); };
  let fallo = null;
  try {
    // El sufijo hace que cada carga sea un módulo nuevo: sin él, la segunda
    // pantalla reutilizaría la primera y el DOM falso no se volvería a usar.
    await import(new URL(ruta, import.meta.url).href + "?prueba=" + ruta.length);
    // Las funciones de arranque son asíncronas: hay que dejarlas terminar.
    await new Promise((r) => setTimeout(r, 30));
  } catch (e) {
    fallo = e;
  }
  return { nodos, fallo };
}

const op = await abrirPantalla("../src/opciones.js");
chk(!op.fallo, `la pantalla de opciones se abre sin reventar${op.fallo ? " — " + op.fallo.message : ""}`);
for (const [id, ev] of [["guardarToken", "click"], ["revisar", "click"],
                        ["anadir", "click"], ["dominio", "keydown"]]) {
  const n = op.nodos.get(id);
  chk(Boolean(n && n.oyentes.some(([e]) => e === ev)),
      `el control «${id}» de opciones responde a ${ev}`);
}
// Que se haya PINTADO, no solo que la función exista.
chk(Boolean(op.nodos.get("estadoToken")?.textContent),
    "al abrir opciones se dice en qué estado está la clave");
chk((op.nodos.get("diagnostico")?.hijos.length || 0) > 0,
    "al abrir opciones el diagnóstico pinta algo (ni vacío ni mudo)");

const mn = await abrirPantalla("../src/menu.js");
chk(!mn.fallo, `el menú del icono se abre sin reventar${mn.fallo ? " — " + mn.fallo.message : ""}`);
chk(Boolean(mn.nodos.get("opciones")?.oyentes.some(([e]) => e === "click")),
    "el botón de opciones del menú responde a click");
// Sin navegador de verdad el menú no puede consultar pestañas. Lo que se exige
// no es que funcione, sino que NO se quede en blanco: un popup mudo parece una
// extensión desinstalada y no deja nada que diagnosticar.
chk(Boolean(mn.nodos.get("titulo")?.textContent),
    "el menú nunca se queda en blanco: si falla, lo dice");

console.log(mal === 0
  ? "EXTENSION TODO OK — no se lee lo que el usuario escribe, y lo excluido no se reporta"
  : `EXTENSION FALLA (${mal})`);
process.exit(mal === 0 ? 0 : 1);
