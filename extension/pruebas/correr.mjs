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
import { readFileSync } from "node:fs";
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

const { fotografiar, consultarCaptura, capturarPestaña, contarPagina } = await import("../src/fondo.js");

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

// ---------- Spec 013: permiso antes de recoger contenido ----------

let metadatosLeidos = 0;
const pestañaEnReposo = {
  active: true, audible: true,
  get url() { metadatosLeidos++; return "https://ejemplo.test/privado"; },
  get title() { metadatosLeidos++; return "Título de prueba"; },
};
const minima = await fotografiar({ pestañas: [pestañaEnReposo], excluidos: [], contenidoPermitido: false });
chk(metadatosLeidos === 0 && minima.pestanas[0].url === "" && minima.pestanas[0].titulo === "",
    "en reposo ni se consultan URL ni título de pestañas");
chk(minima.pestanas[0].audible && minima.pestanas[0].activa,
    "los guardias conservan solo las señales activa y audible");

const permisoA = { capturando: true, solo_grabaciones: true, pantalla_activa: true,
  sesion: "sesion-a", generacion: 1, inicio: 1_800_000_000 };
let consultas = 0;
let respuestaPermiso = permisoA;
const peticionPermiso = async () => { consultas++; return { ok: true, json: async () => respuestaPermiso }; };
const consulta = { ahora: 100_000, peticion: peticionPermiso, obtenerToken: async () => "token-simulado" };
await Promise.all([consultarCaptura(consulta), consultarCaptura(consulta)]);
chk(consultas === 1, "las pestañas comparten la consulta simultánea de permiso");
await consultarCaptura({ ...consulta, ahora: 100_250 });
chk(consultas === 1, "el sondeo comparte su estado durante medio segundo");
respuestaPermiso = { capturando: false, solo_grabaciones: true };
const revocado = await consultarCaptura({ ...consulta, ahora: 100_251, forzar: true });
chk(!revocado.capturando && consultas === 2, "revalidar antes de leer ignora el permiso cacheado y ve el cierre");
const incompleto = await consultarCaptura({ ...consulta, ahora: 101_000, forzar: true,
  peticion: async () => ({ ok: true, json: async () => ({ listo: true }) }) });
chk(!incompleto.capturando, "una API sin contrato de captura nunca autoriza contenido");
const sinApi = await consultarCaptura({ ...consulta, ahora: 102_000, forzar: true,
  peticion: async () => { throw new Error("API simulada ausente"); } });
chk(!sinApi.capturando, "una API ausente falla sin conceder permiso");
const previas = consultas;
await consultarCaptura({ ...consulta, ahora: 102_500, forzar: true });
chk(consultas === previas, "la API caída respeta espera sin sondear en bucle");

let imagenes = 0, ventanasConsultadas = 0;
const navegadorSimulado = { tabs: {
  query: async () => { ventanasConsultadas++; return [{ url: "https://ejemplo.test/" }]; },
  captureVisibleTab: async () => { imagenes++; return "data:image/jpeg;base64,simulada"; },
} };
await capturarPestaña(permisoA, { navegador: navegadorSimulado, consultar: async () => ({ capturando: false }) });
chk(imagenes === 0 && ventanasConsultadas === 0, "sin permiso ni siquiera se consulta la pestaña para capturar");
let turnoPermiso = 0;
await capturarPestaña(permisoA, { navegador: navegadorSimulado,
  consultar: async () => (++turnoPermiso === 1 ? permisoA : { capturando: false }) });
chk(imagenes === 0, "si el permiso termina durante las esperas, no se hace captura de pestaña");
await capturarPestaña(permisoA, { navegador: navegadorSimulado,
  consultar: async () => ({ ...permisoA, pantalla_activa: false }) });
chk(imagenes === 0, "la fuente de pantalla desmarcada tampoco permite capturar desde la extensión");
const imagenPermitida = await capturarPestaña(permisoA, { navegador: navegadorSimulado, consultar: async () => permisoA });
chk(imagenes === 1 && Number.isFinite(imagenPermitida?.instante), "la captura autorizada lleva el instante en que empezó");

let fotosDePagina = 0, cuerpoEnviado = null;
const materialA = { ...permisoA, instante: 1_800_000_001, url: "https://ejemplo.test/", texto: "Contenido de prueba" };
const dependenciasPagina = { consultar: async () => ({ ...permisoA, sesion: "sesion-b" }),
  tomarFoto: async () => { fotosDePagina++; return { instante: 9, pestanas: [] }; },
  capturas: async () => false,
  mandar: async (_ruta, cuerpo) => { cuerpoEnviado = cuerpo; return true; } };
await contarPagina(materialA, dependenciasPagina);
chk(fotosDePagina === 0 && cuerpoEnviado?.sesion === "sesion-a" && cuerpoEnviado?.pestanas.length === 0,
    "material ya leído de otra sesión conserva su identidad sin recoger contexto de la nueva");
await contarPagina(materialA, { ...dependenciasPagina, consultar: async () => permisoA });
chk(cuerpoEnviado?.sesion === "sesion-a" && cuerpoEnviado?.instante === materialA.instante,
    "el envío conserva sesión e instante de lectura, aunque la foto termine después");

// Se ejecuta el guion real con DOM y temporizador simulados. Los contadores
// miden accesos; buscar una cadena de código no demostraría ausencia de lectura.
let numeroGuion = 0;
const contenidoFuente = readFileSync(new URL("../src/contenido.js", import.meta.url), "utf8");
async function abrirContenido(estadoInicial, { validacion = null } = {}) {
  const intervaloOriginal = globalThis.setInterval;
  let tick, estado = estadoInicial, lecturas = 0, titulos = 0, urls = 0;
  const mensajes = [];
  let avisarListo;
  const listo = new Promise((r) => { avisarListo = r; });
  globalThis.document = {
    visibilityState: "visible",
    get body() { lecturas++; return el("P", [texto("Contenido visible neutro para la prueba de autorización de grabaciones.")]); },
    get title() { titulos++; return "Página neutra"; },
    querySelectorAll: () => [],
  };
  globalThis.location = { get href() { urls++; return "https://ejemplo.test/pagina"; } };
  globalThis.chrome = { runtime: {
    getURL: (ruta) => new URL("../" + ruta, import.meta.url).href,
    sendMessage: async (msg) => {
      if (msg.tipo === "permiso-captura") return estado;
      if (msg.tipo === "validar-captura") return validacion ? validacion() : estado;
      mensajes.push(msg); return {};
    },
  } };
  globalThis.setInterval = (fn) => { tick = fn; avisarListo(); return 1; };
  try {
    // El guion clásico no tiene imports estáticos: Node lo cachearía como
    // CommonJS por ruta ignorando la query. Un módulo de datos ejecuta sus
    // mismos bytes de nuevo, sin modificar ni copiar el archivo de producción.
    await import("data:text/javascript;base64," + Buffer.from(contenidoFuente).toString("base64")
      + "#prueba=" + (++numeroGuion));
    await listo;
  } finally { globalThis.setInterval = intervaloOriginal; }
  return { tick: () => tick(), estado: (nuevo) => { estado = nuevo; }, mensajes,
    contadores: () => ({ lecturas, titulos, urls }) };
}

const reposo = await abrirContenido({ capturando: false });
for (let n = 0; n < 120; n++) await reposo.tick();
chk(Object.values(reposo.contadores()).every((n) => n === 0) && reposo.mensajes.length === 0,
    "60 segundos de reposo simulados: cero DOM, URL, título y páginas enviadas");
reposo.estado(permisoA);
await reposo.tick();
chk(reposo.contadores().lecturas > 0 && reposo.mensajes[0]?.sesion === "sesion-a"
  && Number.isFinite(reposo.mensajes[0]?.instante), "una pestaña ya abierta recoge texto al comenzar la grabación");
const lecturasTrasInicio = reposo.contadores().lecturas;
await reposo.tick();
chk(reposo.contadores().lecturas === lecturasTrasInicio, "el sondeo no vuelve a leer la misma página dentro de la ventana");
reposo.estado({ capturando: false });
for (let n = 0; n < 120; n++) await reposo.tick();
chk(reposo.contadores().lecturas === lecturasTrasInicio, "detener o pausar cierra las lecturas posteriores de la página");
const cierreDuranteEspera = await abrirContenido(permisoA, { validacion: () => ({ capturando: false }) });
chk(cierreDuranteEspera.contadores().lecturas === 0 && cierreDuranteEspera.contadores().titulos === 0,
    "si se cierra la ventana mientras cargan módulos, no se llega a leer DOM ni título");
const sesionCruzada = await abrirContenido(permisoA, { validacion: () => ({ ...permisoA, sesion: "sesion-b" }) });
chk(sesionCruzada.contadores().lecturas === 0 && sesionCruzada.mensajes.length === 0,
    "un permiso de otra sesión no valida una lectura pendiente");
const continuo = await abrirContenido({ ...permisoA, solo_grabaciones: false, sesion: null });
chk(continuo.contadores().lecturas > 0 && continuo.mensajes.length === 1,
    "el modo continuo explícito sigue leyendo páginas autorizadas");
globalThis.chrome = undefined;
globalThis.location = undefined;

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
