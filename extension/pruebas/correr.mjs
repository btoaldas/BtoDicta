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

console.log(mal === 0
  ? "EXTENSION TODO OK — no se lee lo que el usuario escribe, y lo excluido no se reporta"
  : `EXTENSION FALLA (${mal})`);
process.exit(mal === 0 ? 0 : 1);
