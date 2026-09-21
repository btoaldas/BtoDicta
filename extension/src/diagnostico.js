// ¿Esto está funcionando? (spec 006, T27, RF-12)
//
// Por qué existe
// --------------
// La extensión dejó de enviar y nada lo dijo: ni un aviso, ni un error, ni una
// señal. Se descubrió días después mirando si habían llegado informes. Un sensor
// silencioso es indistinguible de un sensor roto, y el usuario no tiene por qué
// leer registros para saber cuál de los dos tiene.
//
// Cada comprobación responde tres cosas: qué se miró, cómo salió, y —si salió
// mal— QUÉ HACER. Un diagnóstico que dice «error» sin decir el siguiente paso
// deja al usuario donde estaba.

import { api } from "./navegador.js";
import { leerToken } from "./enviar.js";
import { leerExcluidos } from "./exclusiones.js";

const API = "http://127.0.0.1:8787";

/**
 * Revisa la cadena entera, en el orden en que las cosas dependen unas de otras.
 *
 * El orden importa: sin permisos no hay pestañas, sin clave no se intenta
 * enviar, y sin BtoDicta viva da igual todo lo demás. Comprobarlo al revés
 * produce tres errores donde hay una sola causa.
 */
export async function revisar() {
  const pasos = [];
  const paso = (titulo, ok, detalle, arreglo) =>
    pasos.push({ titulo, ok, detalle, arreglo: ok ? "" : (arreglo || "") });

  // 1. ¿Puede ver las pestañas? Sin esto no hay extensión que valga.
  let pestañas = null;
  try {
    pestañas = await api.tabs.query({});
    paso("Permiso para ver las pestañas", true, `${pestañas.length} pestañas abiertas`);
  } catch {
    paso("Permiso para ver las pestañas", false,
         "El navegador no deja consultarlas",
         "Quita la extensión y vuelve a cargarla desde ~/.btodicta/extension");
  }

  // 2. ¿Hay clave? Sin ella ni se intenta enviar — que es exactamente lo que
  //    pasó sin que nadie se enterara.
  const token = await leerToken();
  paso("Clave de BtoDicta", Boolean(token),
       token ? `Guardada (${token.length} caracteres)` : "No hay ninguna clave guardada",
       "Cópiala en BtoDicta → Ajustes → «Dejar que otros programas transcriban» → Copiar, y pégala aquí arriba");

  // 3. ¿Está BtoDicta viva? Se pregunta a la puerta que no exige clave, para
  //    poder distinguir «no está» de «no me acepta».
  let viva = false;
  try {
    const r = await fetch(API + "/estado");
    if (r.ok) {
      const d = await r.json();
      viva = true;
      paso("BtoDicta responde", true, `Versión ${d.version || "?"} · ${d.motores || 0} motores`);
    } else {
      paso("BtoDicta responde", false, `Contestó con el código ${r.status}`,
           "Reinicia BtoDicta");
    }
  } catch {
    paso("BtoDicta responde", false, "No contesta en 127.0.0.1:8787",
         "Abre BtoDicta y enciende «Abrir la puerta local» en Ajustes. Viene apagada de fábrica");
  }

  // 4. ¿Acepta la clave? Solo tiene sentido si hay clave y está viva.
  if (token && viva) {
    try {
      const r = await fetch(API + "/navegador", { headers: { Authorization: "Bearer " + token } });
      if (r.status === 401) {
        paso("La clave sirve", false, "BtoDicta la rechazó",
             "La clave cambió. Cópiala otra vez desde Ajustes y pégala aquí");
      } else if (r.ok) {
        const d = await r.json();
        const mios = (d.informes || []).length;
        paso("La clave sirve", true, "Aceptada");
        // 5. ¿Están llegando informes? Es lo único que demuestra que la cadena
        //    entera funciona de punta a punta.
        paso("Tus avisos llegan", mios > 0,
             mios > 0 ? `${mios} informe(s) vigente(s) en BtoDicta`
                      : "BtoDicta no tiene ningún informe reciente tuyo",
             "Cambia de pestaña o recarga una página: se envía al momento. Si sigue vacío, recarga la extensión");
        if (d.aviso_version) {
          paso("Versión", false, d.aviso_version,
               "Recarga la extensión en la página de extensiones del navegador");
        }
      } else {
        paso("La clave sirve", false, `Código ${r.status}`, "Mira el registro de BtoDicta");
      }
    } catch {
      paso("La clave sirve", false, "No se pudo preguntar",
           "Comprueba que BtoDicta sigue abierta");
    }
  }

  // 6. Informativo, no un fallo: cuántos sitios se están dejando fuera.
  const excluidos = await leerExcluidos();
  paso("Dominios que no se miran", true,
       excluidos.length ? `${excluidos.length}: ${excluidos.slice(0, 3).join(", ")}${excluidos.length > 3 ? "…" : ""}`
                        : "Ninguno — se mira todo");

  return pasos;
}

/** Un resumen de una línea, para el menú del icono. */
export function resumir(pasos) {
  const fallos = pasos.filter((p) => !p.ok);
  if (!fallos.length) return { ok: true, texto: "Todo funcionando" };
  return { ok: false, texto: fallos[0].titulo + ": " + fallos[0].detalle };
}
