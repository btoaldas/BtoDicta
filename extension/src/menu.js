// El menú del icono (spec 006, T25, RF-10).
//
// Dos cosas, y en este orden de importancia:
//
// 1. **Excluir la página que se está viendo, con un clic.** Ese es el motivo de
//    que exista. La postura elegida es «leer todo salvo lo excluido», y con esa
//    postura la velocidad de excluir ES la protección: si hay que abrir una
//    pantalla de opciones y teclear un dominio, nadie lo hace en el momento en
//    que hace falta — que es justo cuando se tiene delante la página que no
//    quiere uno que se guarde.
//
// 2. **Decir si esto está funcionando.** Un sensor silencioso es
//    indistinguible de un sensor roto. Aquí se ve si BtoDicta responde, sin
//    tener que abrir una terminal.

import { api } from "./navegador.js";
import { leerExcluidos, excluir, dejarDeExcluir, dominioDe, estaExcluida } from "./exclusiones.js";
import { leerToken } from "./enviar.js";

const $ = (id) => document.getElementById(id);
const API = "http://127.0.0.1:8787";

/** ¿Está BtoDicta viva y nos acepta? */
async function comprobar() {
  const token = await leerToken();
  if (!token) {
    return {
      luz: "avisa",
      titulo: "Falta la clave",
      // Decir «falta la clave» sin decir dónde está deja al usuario buscando.
      detalle: "BtoDicta → Ajustes → «Dejar que otros programas transcriban» → Copiar.",
    };
  }
  try {
    const r = await fetch(API + "/navegador", { headers: { Authorization: "Bearer " + token } });
    if (r.status === 401) {
      return { luz: "muerta", titulo: "La clave no vale", detalle: "BtoDicta la rechazó. Cópiala otra vez." };
    }
    if (!r.ok) return { luz: "avisa", titulo: "BtoDicta responde raro", detalle: "Código " + r.status };
    const d = await r.json();
    const informes = d.informes || [];
    const mio = informes.find((i) => i.pestanas > 0);
    return {
      luz: "viva",
      titulo: "Conectada con BtoDicta",
      detalle: mio
        ? `Último aviso hace ${mio.hace_segundos} s · ${mio.suenan.length} sonando`
        : "Aún no ha llegado ningún aviso.",
      decision: d.ahora_mismo,
      aviso: d.aviso_version || "",
    };
  } catch {
    return {
      luz: "muerta",
      titulo: "BtoDicta no responde",
      detalle: "¿Está abierta, y su puerta local encendida?",
    };
  }
}

async function pintar() {
  const [tab] = await api.tabs.query({ active: true, currentWindow: true });
  const url = tab?.url || "";
  const dominio = dominioDe(url);
  const excluidos = await leerExcluidos();
  const fuera = estaExcluida(url, excluidos);

  const estado = await comprobar();
  $("luz").className = "luz " + estado.luz;
  $("titulo").textContent = estado.titulo;
  $("detalle").textContent = estado.detalle;

  if (estado.aviso) {
    $("avisoVersion").textContent = estado.aviso;
    $("avisoVersion").style.display = "block";
  }

  const boton = $("alternar");
  if (!dominio) {
    // Una página interna del navegador no se puede excluir ni hace falta.
    $("pagina").textContent = "Esta pestaña no es una página web.";
    boton.style.display = "none";
    return;
  }

  $("pagina").textContent = fuera
    ? `${dominio} está excluido: la bitácora no lo ve.`
    : `Ahora mismo se anota: ${dominio}`;

  boton.style.display = "block";
  boton.textContent = fuera ? `Volver a mirar ${dominio}` : `No mirar ${dominio}`;
  boton.className = fuera ? "volver" : "excluir";
  boton.onclick = async () => {
    // El mismo botón hace y deshace: quien acaba de excluir por error tiene la
    // vuelta atrás en el mismo sitio, no escondida en otra pantalla.
    if (fuera) await dejarDeExcluir(dominio);
    else await excluir(dominio);
    pintar();
  };
}

$("opciones").addEventListener("click", () => api.runtime.openOptionsPage());
pintar();
