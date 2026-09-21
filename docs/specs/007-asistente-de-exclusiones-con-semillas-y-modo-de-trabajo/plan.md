# Plan técnico 007 — Asistente de exclusiones con semillas y modo de trabajo

- Estado: Borrador
- Fecha: 2026-09-21
- Spec: `spec.md` (Aprobada 2026-09-21, nivel P)
- Aprobado por: PENDIENTE

## 1. Lo que se encontró antes de planificar

Antes de escribir nada se recorrió el código que ya decide qué se graba. Tres
hallazgos cambian el plan:

### 1.1 Hay tres listas de exclusión, no una

| Lista | Claves | Qué apaga | Interfaz hoy |
|---|---|---|---|
| **Ancha** | `bitacora_excluir_apps`, `bitacora_excluir_titulos`, `bitacora_incluir_apps`, `bitacora_incluir_titulos` | Audio del sistema **y** capturas de pantalla | **Ninguna.** Solo editando `config.json` a mano |
| **Solo capturas** | `continuo_pantalla_apps_excluidas`, `continuo_pantalla_titulos_excluidos` | Únicamente la captura; el audio se sigue grabando | Sí: dos campos de texto en Ajustes → Bitácora |
| **Del navegador** | almacén de la extensión (spec 006) | Que la URL y el título salgan del navegador | Sí: pantalla de opciones de la extensión |

Consumidores verificados: `ContinuoAudioSistema` consulta solo la ancha;
`ContinuoPantalla` consulta **las dos** (la suya en la línea 261, la ancha en la
270); la extensión es independiente.

**Consecuencia para el plan:** el asistente escribe en la lista **ancha**, que es
la que de verdad apaga la grabación, y es justamente la única sin interfaz. La de
capturas se queda como está: es un grano más fino y legítimo («esto se graba pero
no se fotografía»), y de fábrica trae los gestores de contraseñas.

**Consecuencia para la interfaz:** tener dos sitios donde escribir «youtube» con
efectos distintos es una trampa. La pantalla debe decir en una línea qué apaga
cada una.

### 1.2 El nombre «Asistente» ya está ocupado

`SettingsWindow` tiene una pestaña `.asistente` que es el agente de IA. El de esta
spec no puede llamarse igual: va **dentro de la pestaña Bitácora**, como sección
propia, y se nombra «Qué no debe mirar la bitácora».

### 1.3 `Config` cachea y reescribe el archivo entero

`Config.json()` guarda la configuración en memoria y `Config.set` vuelca el objeto
completo. Escribir `config.json` desde fuera con la app viva se pierde. El
asistente escribe **siempre** por `Config.set`, nunca tocando el archivo.

## 2. Comprobación contra la constitución

| Regla | Cómo la cumple este plan |
|---|---|
| MANIFIESTO: lo que se graba es del usuario y no sale del equipo | Las semillas viajan embarcadas; cero consultas de red al proponer o aceptar |
| Nivel P (piloto/interno) | Prueba por RF, verificación con segundo ángulo, sin exigir rama propia |
| Features parametrizables | Modo, categorías y cada entrada: todo configurable y reversible |
| Valor de fábrica peligroso = fallo | El modo restrictivo con inclusiones vacías avisa antes de guardar (RF-08) |
| Avisar antes de cambiar | Nada se escribe hasta Aceptar (RNF-02) |
| Datos genéricos en el repo | El catálogo son dominios públicos; ni un dato del usuario |
| Sin secretos | No hay credenciales en juego |

## 3. Componentes

```
Sources/BtoDicta/
  SemillasExclusion.swift      catálogo + estado del asistente   (nuevo)
  FiltroBitacora.swift         gana el modo de trabajo           (modificado)
  ContinuoView.swift           sección «Qué no debe mirar»       (modificado)
Resources/
  semillas-exclusion.json      el catálogo, versionado           (nuevo)
Tests/BtoDictaTests/
  SemillasExclusionTests.swift                                   (nuevo)
  FiltroBitacoraTests.swift    + casos del modo restrictivo      (modificado)
```

### 3.1 El catálogo (`semillas-exclusion.json`)

```json
{
  "version": 1,
  "categorias": [
    { "id": "redes", "nombre": "Redes sociales", "destino": "titulos",
      "entradas": ["facebook.com", "instagram.com", "x.com", "twitter.com", …] }
  ]
}
```

- `destino` es `titulos` o `apps`: decide **en qué lista** aterriza. Esto es el
  RF-04 hecho dato en vez de código — el fallo que originó ese RF fue justamente
  escribir una app en la lista de títulos.
- `version` permite proponer semillas nuevas sin resucitar lo que se rechazó.

### 3.2 Estado del asistente (tres claves nuevas)

| Clave | Para qué |
|---|---|
| `bitacora_modo` | `"permisivo"` (de fábrica) o `"restrictivo"` |
| `bitacora_semillas_rechazadas` | Identificadores que el usuario desmarcó. Sostiene el RF-07 |
| `bitacora_asistente_visto` | Versión del catálogo ya revisada. Sostiene el RF-05 |

### 3.3 El modo en el filtro

`decidir(app:ventana:excluirApps:…)` gana un parámetro `modo`. En restrictivo la
lógica se invierte: entra solo lo que esté en alguna lista de inclusión. La
variante que lee de `Config` saca el modo de `bitacora_modo`.

## 4. Decisiones, con la alternativa descartada

| # | Decisión | Alternativa descartada | Por qué |
|---|---|---|---|
| D-1 | Catálogo en un JSON de recursos | Literal Swift | Revisable y diffeable sin leer código; se actualiza sin tocar lógica |
| D-2 | El asistente escribe en la lista **ancha** | Escribir en las tres | Cada lista significa algo distinto; unificarlas sería decidir por el usuario. La sincronización quedó fuera de alcance en la spec |
| D-3 | **Entradas de dominio completo**, nunca fragmentos | Palabras sueltas («sex», «porn») | La comparación es por subcadena: «sex» casa con «Essex» y «sexta». Un fragmento corto deja sin bitácora media jornada sin que nadie entienda por qué |
| D-4 | Lista de contenido adulto **corta y embarcada** (~25 dominios de más tráfico) | Blocklist pública de decenas de miles | Una lista enorme engorda el paquete, envejece sola y obliga a mantener algo ajeno. La cobertura completa exige clasificación, que la spec dejó fuera |
| D-5 | Rechazos guardados **por identificador de entrada** | Guardar solo lo aceptado | Sin registrar el rechazo no se distingue «nunca se lo propusimos» de «dijo que no», y cada versión se lo volvería a proponer |
| D-6 | Sección dentro de la pestaña Bitácora | Pestaña nueva | `.asistente` ya existe y es otra cosa; y esto pertenece al sitio donde se configura la bitácora |
| D-7 | Escribir por `Config.set` | Escribir `config.json` | `Config` cachea y reescribe entero: una edición externa se pierde |

Salen a `docs/adr/`: D-3 (comparación por subcadena y su trampa) y D-4 (alcance
de la lista de contenido adulto).

## 5. Catálogo propuesto — **a revisar antes de escribir código**

Esto es lo que quedó abierto en la puerta de la spec. Las categorías y su destino:

| Categoría | Destino | Entradas propuestas |
|---|---|---|
| Redes sociales | títulos | facebook.com · instagram.com · x.com · twitter.com · tiktok.com · snapchat.com · reddit.com · threads.net · bsky.app · mastodon.social · pinterest.com · tumblr.com |
| Vídeo y música | títulos | youtube.com · netflix.com · primevideo.com · disneyplus.com · max.com · twitch.tv · spotify.com · vimeo.com · dailymotion.com |
| Buscadores | títulos | google.com/search · bing.com/search · duckduckgo.com · search.yahoo.com · ecosia.org |
| Contenido adulto | títulos | ~25 dominios de mayor tráfico, dominio completo (ver D-3 y D-4) |
| Mensajería personal | títulos | web.whatsapp.com · messenger.com · telegram.org |
| Reproductores y juegos | **apps** | vlc · dota · steam · iina · quicktime player · epic games |
| Banca y claves | **apps** | 1password · bitwarden · keychain access · dashlane |

Tres cosas que conviene mirar antes de aceptarlas:

1. **LinkedIn no está en redes sociales**, a propósito: para ti es trabajo. Si lo
   quieres fuera, se añade.
2. **Buscadores**: excluir `google.com` entero se comería Drive, Gmail y Meet. Por
   eso la entrada es `google.com/search`, que solo casa con la página de
   resultados. Con Gmail y Meet ya en tu lista de inclusión, están doblemente a
   salvo.
3. **Banca y claves** duplica en parte lo que la lista de capturas ya trae de
   fábrica, pero con más alcance: ahí apaga la foto, aquí apaga también el audio.

## 6. Orden de trabajo, y qué se prueba primero

El riesgo mayor no es la pantalla: es **el modo restrictivo**, porque un fallo ahí
apaga la bitácora entera en silencio. Va primero, con sus pruebas, antes de que
exista interfaz alguna.

1. Modo en `FiltroBitacora` + pruebas de los dos modos, vistas en rojo.
2. `SemillasExclusion`: catálogo, rechazos, versión + pruebas.
3. Sección de interfaz con las categorías desplegables.
4. Aviso de bitácora ciega (RF-08).
5. Apertura automática la primera vez (RF-05).
6. Verificación RF por RF.

## 7. Riesgos

| Riesgo | Mitigación |
|---|---|
| El modo restrictivo deja la bitácora ciega sin que se note | RF-08 avisa; y las pruebas del punto 1 van antes que la interfaz |
| Una entrada corta excluye de más | D-3: dominios completos, y el desplegable los enseña antes de aceptar |
| El usuario cree que configuró todo y solo tocó una de las tres listas | La pantalla dice en una línea qué apaga cada lista |
| La lista de contenido adulto envejece | D-4 asume cobertura parcial y lo dice; la completa exige la spec de clasificación |
| Aceptar el catálogo entero duplica entradas que ya tenía | Unión, no concatenación (caso límite de la spec) |

## 8. Lo que este plan NO resuelve

- Clasificar páginas adultas desconocidas (fuera de alcance por la spec).
- Sincronizar las tres listas entre sí (decisión pendiente de la spec 006).
- Dar interfaz a la lista de capturas más allá de la que ya tiene.
