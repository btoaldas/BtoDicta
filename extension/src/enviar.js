// Cómo habla la extensión con BtoDicta (spec 006, T10, RNF-04).
//
// La regla que gobierna este archivo: **la extensión no es un almacén**.
//
// Si BtoDicta no está corriendo, lo que se iba a contar se descarta y ya está.
// La tentación sería guardarlo para enviarlo luego, y es una mala idea por dos
// motivos: un informe del navegador de hace media hora no sirve para decidir qué
// se graba ahora, y una cola que crece en el navegador es exactamente el tipo de
// cosa que acaba guardando en disco lo que nadie quería guardar.

import { api } from "./navegador.js";

const API = "http://127.0.0.1:8787";

/** Con la aplicación caída, no más de un intento por minuto (RNF-04). */
const ESPERA_TRAS_FALLO_MS = 60_000;
let siguienteIntento = 0;

/** El token lo pega el usuario una vez; vive en el almacén del navegador. */
export async function leerToken() {
  // Sin almacén —fuera de un navegador, o con los permisos retirados— esto debe
  // devolver vacío, no reventar. La primera versión no lo hacía y la prueba lo
  // cazó: `leerToken` quedaba FUERA del `try` de `enviar`, así que una extensión
  // sin almacén tumbaba a quien la aloja. Es exactamente lo que este archivo
  // dice que no puede pasar.
  try {
    const got = await api?.storage?.local?.get("token");
    return (got && got.token) || "";
  } catch {
    return "";
  }
}

export async function guardarToken(token) {
  try {
    await api?.storage?.local?.set({ token: String(token || "").trim() });
  } catch {
    // Nada que hacer: el usuario verá que el token no quedó guardado.
  }
}

/**
 * Manda un informe. Devuelve `true` si BtoDicta lo recibió.
 *
 * No lanza nunca: un sensor que rompe el navegador cuando su destino no está
 * es peor que no tener sensor.
 */
export async function enviar(ruta, cuerpo) {
  const ahora = Date.now();
  if (ahora < siguienteIntento) return false;      // todavía en penitencia

  let token = "";
  try { token = await leerToken(); } catch { token = ""; }
  if (!token) return false;                        // sin token no se intenta

  try {
    const r = await fetch(API + ruta, {
      method: "POST",
      headers: {
        // En la cabecera, NUNCA en la dirección: una dirección queda en
        // historiales y registros; una cabecera, no.
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(cuerpo),
    });
    if (!r.ok) {
      // Un 401 no se reintenta en bucle: el token está mal y reintentar solo
      // gasta. Se espera lo mismo que ante una caída.
      siguienteIntento = ahora + ESPERA_TRAS_FALLO_MS;
      return false;
    }
    siguienteIntento = 0;
    return true;
  } catch {
    // BtoDicta cerrada, puerto cambiado, permiso retirado. Se calla y se espera.
    siguienteIntento = ahora + ESPERA_TRAS_FALLO_MS;
    return false;
  }
}

/** Para las pruebas: olvida la penitencia. */
export function reiniciarEspera() { siguienteIntento = 0; }

/** Cuánto falta para volver a intentar, en ms. 0 = se puede intentar ya. */
export function esperaRestante() { return Math.max(0, siguienteIntento - Date.now()); }
