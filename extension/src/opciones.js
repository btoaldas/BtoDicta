// La pantalla donde se excluye un dominio (spec 006, T07, RF-05).
//
// Existe por una razón concreta: la postura elegida es «leer todo salvo lo que
// se excluya», y con esa postura **la velocidad de excluir es la protección**.
// Si excluir un sitio exigiera abrir un archivo de configuración, nadie lo haría
// en el momento en que hace falta — que es justo cuando se tiene delante la
// página que no quiere uno que se guarde.

import { leerExcluidos, excluir, dejarDeExcluir, normalizarDominio } from "./exclusiones.js";
import { leerToken, guardarToken } from "./enviar.js";
import { revisar } from "./diagnostico.js";

const $ = (id) => document.getElementById(id);

async function pintar() {
  const lista = await leerExcluidos();
  const ul = $("lista");
  // `replaceChildren()` en vez de `innerHTML = ""`: hace lo mismo sin dejar
  // a la vista un patrón que, con contenido ajeno, sí sería peligroso.
  ul.replaceChildren();
  $("vacio").style.display = lista.length ? "none" : "block";

  for (const d of lista) {
    const li = document.createElement("li");
    const nombre = document.createElement("span");
    nombre.textContent = d;
    const quitar = document.createElement("button");
    quitar.textContent = "Volver a mirar";
    quitar.addEventListener("click", async () => {
      await dejarDeExcluir(d);
      async function pintarDiagnostico() {
  const caja = $("diagnostico");
  caja.replaceChildren();
  const cargando = document.createElement("div");
  cargando.className = "chk-d";
  cargando.textContent = "Comprobando…";
  caja.append(cargando);

  const pasos = await revisar();
  caja.replaceChildren();
  for (const p of pasos) {
    const fila = document.createElement("div");
    fila.className = "chk " + (p.ok ? "ok" : "mal");
    const marca = document.createElement("span");
    marca.className = "marca";
    marca.textContent = p.ok ? "✓" : "✗";
    const cuerpo = document.createElement("div");
    const t = document.createElement("div");
    t.className = "chk-t";
    t.textContent = p.titulo;
    const d = document.createElement("div");
    d.className = "chk-d";
    d.textContent = p.detalle;
    cuerpo.append(t, d);
    // La instrucción solo aparece cuando hace falta: un consejo permanente se
    // vuelve invisible el día que importa.
    if (!p.ok && p.arreglo) {
      const a = document.createElement("div");
      a.className = "chk-a";
      a.textContent = "→ " + p.arreglo;
      cuerpo.append(a);
    }
    fila.append(marca, cuerpo);
    caja.append(fila);
  }
}

$("revisar").addEventListener("click", pintarDiagnostico);

async function pintarToken() {
  const t = await leerToken();
  $("estadoToken").textContent = t
    ? "Clave guardada. La extensión ya puede hablar con BtoDicta."
    : "Sin clave: la extensión no envía nada.";
}

$("guardarToken").addEventListener("click", async () => {
  const valor = $("token").value.trim();
  await guardarToken(valor);
  $("token").value = "";
  // Comprobar EN EL ACTO si la clave sirve. Guardarla en silencio fue lo que
  // permitió que la extensión estuviera muda sin que nadie lo supiera.
  await pintarToken();
  await pintarDiagnostico();
});

pintar();
pintarToken();
pintarDiagnostico();
    });
    li.append(nombre, quitar);
    ul.append(li);
  }
}

async function anadir() {
  const campo = $("dominio");
  const d = normalizarDominio(campo.value);
  if (!d) { campo.focus(); return; }
  await excluir(d);
  campo.value = "";
  campo.focus();
  pintar();
}

$("anadir").addEventListener("click", anadir);
// Enter añade: un clic menos en la acción que más se repite.
$("dominio").addEventListener("keydown", (e) => { if (e.key === "Enter") anadir(); });

pintar();
