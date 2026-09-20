// La pantalla donde se excluye un dominio (spec 006, T07, RF-05).
//
// Existe por una razón concreta: la postura elegida es «leer todo salvo lo que
// se excluya», y con esa postura **la velocidad de excluir es la protección**.
// Si excluir un sitio exigiera abrir un archivo de configuración, nadie lo haría
// en el momento en que hace falta — que es justo cuando se tiene delante la
// página que no quiere uno que se guarde.

import { leerExcluidos, excluir, dejarDeExcluir, normalizarDominio } from "./exclusiones.js";

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
      pintar();
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
