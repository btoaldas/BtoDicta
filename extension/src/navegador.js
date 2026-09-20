// La misma extensión corriendo en dos mundos (spec 006, T16, RF-06/RF-07).
//
// Chrome, Edge y Brave exponen sus API bajo `chrome.*`; Firefox lo hace bajo
// `browser.*` y además devuelve promesas donde Chromium usa retrollamadas en
// versiones antiguas. Las versiones actuales de ambos devuelven promesas, así
// que basta con resolver el espacio de nombres.
//
// Es una línea, y es lo que evita mantener dos extensiones: lo que de verdad
// difiere entre ambos mundos es el manifiesto y la firma, no la lógica (ADR-004).

export const api = globalThis.browser ?? globalThis.chrome;

/** Qué navegador es, tal como lo dirá en su informe. */
export function nombreDelNavegador() {
  const ua = (globalThis.navigator && navigator.userAgent) || "";
  if (globalThis.browser && !globalThis.chrome) return "Firefox";
  if (ua.includes("Edg/")) return "Microsoft Edge";
  if (ua.includes("Brave") || (globalThis.navigator && navigator.brave)) return "Brave Browser";
  if (ua.includes("Firefox")) return "Firefox";
  return "Google Chrome";
}
