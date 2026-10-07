// El sensor (spec 006, T09, RF-01).
//
// Lo único que este archivo sabe hacer es mirar las pestañas y contarlo. No
// decide nada: quien decide qué entra en la bitácora es BtoDicta.
//
// Y lo que cuenta es justo lo que macOS no deja ver desde fuera. Comprobado el
// 2026-09-20: `audible of active tab` responde error -1700, y las únicas
// propiedades que un navegador expone por AppleScript son URL, name, loading,
// class e id. Saber qué pestaña está SONANDO solo es posible desde aquí dentro.

import { api, nombreDelNavegador } from "./navegador.js";
import { enviar, leerToken } from "./enviar.js";
import { leerExcluidos, estaExcluida } from "./exclusiones.js";

/** Cada cuánto se cuenta el estado, aunque no haya cambiado nada. */
const LATIDO_SEGUNDOS = 30;

const API = "http://127.0.0.1:8787";
const SONDEO_MS = 500;
let consultaEnCurso = null;
let ultimoPermiso = { capturando: false };
let permisoConsultadoEn = -Infinity;
let reintentarPermisoEn = 0;

/** Permiso sin contenido; las pestañas comparten un sondeo de medio segundo. */
export async function consultarCaptura({ forzar = false, ahora = Date.now(),
  peticion = globalThis.fetch, obtenerToken = leerToken } = {}) {
  if (consultaEnCurso) return consultaEnCurso;
  if (ahora < reintentarPermisoEn) return { capturando: false };
  if (!forzar && ahora - permisoConsultadoEn < SONDEO_MS) return ultimoPermiso;
  consultaEnCurso = (async () => {
    try {
      const token = await obtenerToken();
      if (!token) throw new Error("sin autorización");
      const r = await peticion(API + "/navegador/captura", {
        headers: { Authorization: "Bearer " + token }, cache: "no-store",
      });
      if (!r.ok) throw new Error("permiso no disponible");
      const estado = await r.json();
      // API vieja o respuesta incompleta: nunca se deduce un permiso.
      const valido = typeof estado?.capturando === "boolean"
        && typeof estado?.solo_grabaciones === "boolean"
        && (!estado.capturando || (Number.isFinite(estado.generacion)
          && Number.isFinite(estado.inicio)
          && (!estado.solo_grabaciones || typeof estado.sesion === "string")));
      ultimoPermiso = valido ? estado : { capturando: false };
      permisoConsultadoEn = ahora;
      reintentarPermisoEn = 0;
    } catch {
      ultimoPermiso = { capturando: false };
      permisoConsultadoEn = ahora;
      reintentarPermisoEn = ahora + 60_000;
    }
    return ultimoPermiso;
  })();
  try { return await consultaEnCurso; }
  finally { consultaEnCurso = null; }
}

export function mismoPermiso(permiso, material) {
  return permiso?.capturando === true
    && permiso.sesion === material?.sesion
    && permiso.generacion === material?.generacion;
}

/// ¿Mandar también la imagen de la pestaña? Apagado de fábrica: el texto ya
/// cuenta lo que pasó, y las imágenes pesan.
async function quiereCapturas() {
  try {
    const g = await api.storage.local.get("capturas");
    return Boolean(g && g.capturas);
  } catch {
    return false;
  }
}

/**
 * Fotografía de las pestañas.
 *
 * De un dominio excluido se informa que EXISTE una pestaña activa, sin decir
 * cuál: la bitácora necesita saber que el navegador está en primer plano —para
 * no creer que no hay nadie— pero no tiene por qué saber dónde. Lo que se calla
 * es la dirección y el título, que es lo que identifica el sitio.
 */
export async function fotografiar({ pestañas = null, excluidos = null, contenidoPermitido = true } = {}) {
  const fuera_ = excluidos ?? await leerExcluidos();
  const abiertas = pestañas ?? await api.tabs.query({});

  return {
    navegador: nombreDelNavegador(),
    // La versión viaja en cada informe para que BtoDicta pueda avisar cuando la
    // extensión se quede atrás. Una extensión no se actualiza sola fuera de una
    // tienda, así que lo único que evita quedarse con una vieja sin saberlo es
    // que alguien lo diga.
    version: api?.runtime?.getManifest?.()?.version ?? "",
    instante: Date.now() / 1000,
    pestanas: abiertas.map((t) => {
      const fuera = contenidoPermitido && estaExcluida(t.url || "", fuera_);
      return {
        url: !contenidoPermitido || fuera ? "" : (t.url || ""),
        titulo: !contenidoPermitido || fuera ? "" : (t.title || ""),
        // El hecho de que suene NO se oculta aunque el dominio esté excluido:
        // es un dato sin contenido —algo suena— y es justo el que evita que la
        // bitácora anote como trabajo una película de fondo.
        audible: Boolean(t.audible),
        activa: Boolean(t.active),
        excluida: fuera,
      };
    }),
  };
}

let ultimaHuella = "";

/**
 * Cuenta el estado si cambió, o cada tanto aunque no cambie.
 *
 * La huella evita empapelar a BtoDicta con informes idénticos mientras nadie
 * toca nada, que es la mayor parte del tiempo.
 */
async function contar({ forzar = false } = {}) {
  try {
    // Los guardias de audio conservan solo activa/audible en reposo. Ni siquiera
    // se accede a URL/título de las pestañas sin una ventana autorizada.
    const permiso = await consultarCaptura({ forzar: true });
    const foto = await fotografiar({ contenidoPermitido: permiso.capturando === true });
    if (permiso.capturando) {
      foto.sesion = permiso.sesion;
      foto.generacion = permiso.generacion;
    }
    const huella = JSON.stringify(
      foto.pestanas.map((p) => [p.url, p.audible, p.activa]),
    );
    if (!forzar && huella === ultimaHuella) return;
    const ok = await enviar("/navegador", foto);
    if (ok) ultimaHuella = huella;
  } catch {
    // Un sensor no puede tumbar el navegador. Si algo falla, calla.
  }
}

/// Una captura de la PESTAÑA, no de la pantalla (spec 006, RF-03).
///
/// La diferencia con lo que ya hace BtoDicta por su cuenta: una captura de
/// pantalla recoge la barra del sistema, el Dock y cualquier ventana que esté
/// encima. Esto recoge la página y nada más, aunque haya algo delante tapándola.
///
/// Se pide con moderación: capturar cuesta, y la bitácora ya tiene el texto, que
/// es lo que de verdad se consulta después.
export async function capturarPestaña(material, { consultar = consultarCaptura, navegador = api } = {}) {
  try {
    let permiso = await consultar({ forzar: true });
    if (!mismoPermiso(permiso, material) || permiso.pantalla_activa !== true) return null;
    const [tab] = await navegador.tabs.query({ active: true, currentWindow: true });
    if (!tab) return null;
    const excluidos = await leerExcluidos();
    if (estaExcluida(tab.url || "", excluidos)) return null;   // ni se captura
    permiso = await consultar({ forzar: true });
    if (!mismoPermiso(permiso, material) || permiso.pantalla_activa !== true) return null;
    // `captureVisibleTab` devuelve la imagen ya codificada; no hay que tocar
    // los píxeles ni pedir permisos adicionales.
    const instante = Date.now() / 1000;
    const imagen = await navegador.tabs.captureVisibleTab(undefined, { format: "jpeg", quality: 60 });
    return { imagen, instante };
  } catch {
    // Páginas internas del navegador, o una pestaña que dejó de estar visible.
    return null;
  }
}

/// Una página leída por el guion de contenido, camino de BtoDicta.
export async function contarPagina(msg, { consultar = consultarCaptura, tomarFoto = fotografiar,
  capturas = quiereCapturas, capturar = capturarPestaña, mandar = enviar } = {}) {
  if (!Number.isFinite(msg?.instante)) return false;
  const permiso = await consultar({ forzar: true });
  const ventanaActual = mismoPermiso(permiso, msg);
  // Un texto ya leído puede llegar después del cierre. No recoge nada nuevo:
  // la API decide con la sesión y el instante originales si puede conservarlo.
  const foto = ventanaActual ? await tomarFoto({ contenidoPermitido: true }) : {
    navegador: nombreDelNavegador(), version: api?.runtime?.getManifest?.()?.version ?? "", pestanas: [],
  };
  const cuerpo = {
    ...foto,
    instante: msg.instante,
    sesion: msg.sesion,
    generacion: msg.generacion,
    url: msg.url,
    titulo: msg.titulo,
    texto: msg.texto,
  };
  // La imagen solo si se pide: el texto es lo que se consulta después, y una
  // captura por página multiplicaría por cien lo que viaja y lo que ocupa.
  if (ventanaActual && await capturas()) {
    const captura = await capturar(msg);
    if (captura) {
      cuerpo.captura = captura.imagen;
      cuerpo.captura_instante = captura.instante;
    }
  }
  return await mandar("/navegador", cuerpo);
}

// Las escuchas solo se enganchan si hay un navegador de verdad detrás.
//
// Sin este guardián, importar este archivo en una prueba intentaría registrar
// escuchas contra un `api` que no existe y reventaría. Y la alternativa —no
// probarlo— es peor: `fotografiar()` es donde se decide qué se cuenta de cada
// pestaña, justo lo que no puede quedar sin comprobar.
if (api?.tabs?.onActivated) {
  // Lo que hace cambiar el estado: cambiar de pestaña, que una empiece o deje de
  // sonar, abrir, cerrar o cambiar de ventana.
  api.tabs.onActivated.addListener(() => contar());
  api.tabs.onUpdated.addListener((_id, cambios) => {
    // `audible` y `url` son los dos que importan; el resto de cambios (favicon,
    // progreso de carga) no alteran lo que la bitácora necesita saber.
    if ("audible" in cambios || "url" in cambios || "status" in cambios) contar();
  });
  api.tabs.onRemoved.addListener(() => contar());
  api.runtime?.onMessage?.addListener((msg, _emisor, responder) => {
    if (msg?.tipo === "permiso-captura" || msg?.tipo === "validar-captura") {
      consultarCaptura({ forzar: msg.tipo === "validar-captura" })
        .then(responder).catch(() => responder({ capturando: false }));
      return true;
    }
    if (msg?.tipo === "pagina") {
      contarPagina(msg).then((recibido) => responder({ recibido }))
        .catch(() => responder({ recibido: false }));
      return true;
    }
  });
  api.windows?.onFocusChanged?.addListener(() => contar());

  // Latido: en Manifest V3 el trabajador de fondo se duerme, así que el temporizador
  // va por alarma del navegador y no por `setInterval`, que no sobrevive al sueño.
  api.alarms?.create?.("latido", { periodInMinutes: LATIDO_SEGUNDOS / 60 });
  api.alarms?.onAlarm?.addListener((a) => { if (a.name === "latido") contar({ forzar: true }); });

  contar({ forzar: true });
}
