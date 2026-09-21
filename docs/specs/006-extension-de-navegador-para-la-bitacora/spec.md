# Spec 006 — Extensión de navegador para la bitácora

- Estado: Aprobada
- Tipo: funcionalidad
- Nivel: X (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-20
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-20 — «aprobado, dale con el plan»
- Rama: main

## 1. Problema y propósito

La bitácora anota como trabajo cosas que no lo son: un resumen diario llegó a
empezar con «una partida de Dota 2». El filtro que se acaba de añadir (0.74-0.75)
se apoya en lo único que el sistema deja ver desde fuera —qué aplicación tiene el
foco y la dirección de la pestaña activa— y eso deja dos huecos que **no se pueden
cerrar sin ayuda del propio navegador**: no se sabe qué pestaña está sonando, y lo
que se guarda de una página es un OCR de píxeles, no su texto.

Una extensión instalada en el navegador sí ve ambas cosas. El propósito es que la
bitácora entienda mejor lo que ocurre dentro del navegador —dónde pasa la mayor
parte del día— sin degradar nada de lo que ya funciona.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Persona que dicta | El dueño del equipo, que usa Edge, Brave, Chrome y Firefox | Su resumen diario deja de mezclar ocio con trabajo, y lo que se guarda de una página es texto legible en vez de OCR |
| BtoDicta | La aplicación de escritorio | Recibe del navegador una señal que hoy no existe y que no puede deducir |

## 3. Alcance

### Incluye

- Extensión que informa a BtoDicta de **qué pestaña está activa y cuáles emiten
  sonido**.
- Envío del **texto de la página** visitada, para que la bitácora guarde texto en
  lugar de OCR.
- **Captura de la pestaña** sin barras del sistema ni ventanas superpuestas.
- **Instalación opcional**: se entrega con BtoDicta, no se instala sola y la
  aplicación funciona igual sin ella.
- Exclusiones: lee todo salvo los dominios que el usuario excluya, y las listas ya
  existentes de la bitácora siguen mandando.

### No incluye (con razón)

- Publicación en la Chrome Web Store: es una decisión aparte, con cuenta de
  desarrollador y revisión de terceros. Aquí se entrega para carga manual.
- Modificar páginas, bloquear contenido o automatizar navegación. La extensión
  **solo observa**.
- Sincronización entre equipos: el MANIFIESTO la deja fuera del producto.
- Safari, que no usa el mismo formato de extensión y exige empaquetado con Xcode.

## 4. Requerimientos funcionales

### RF-01 — Saber qué pestaña suena

- Actor: la extensión
- Acción: informa a BtoDicta de qué pestañas están emitiendo audio
- Resultado: la bitácora puede distinguir un vídeo sonando de fondo del trabajo
  que se tiene delante
- Medida: el dato llega en menos de 2 s desde que una pestaña empieza o deja de
  sonar
- Prioridad: P1
- Criterio de aceptación:
  - Dado un navegador con una pestaña de vídeo sonando y otra de correo al frente
  - Cuando BtoDicta consulta el estado del navegador
  - Entonces recibe que la activa es el correo y que la del vídeo está sonando

### RF-02 — Texto de la página en vez de OCR

- Actor: la extensión
- Acción: envía el texto visible de la página que se está consultando
- Resultado: la bitácora guarda texto legible en lugar del resultado de un OCR
- Medida: sobre una página de artículo, el texto recibido contiene al menos el
  90 % de las palabras que hoy produce el OCR de esa misma pantalla
- Prioridad: P1
- Criterio de aceptación:
  - Dado un artículo abierto en el navegador
  - Cuando la extensión lo reporta
  - Entonces la bitácora almacena su texto sin haber ejecutado OCR sobre él

### RF-03 — Captura fiel de la pestaña

- Actor: la extensión
- Acción: entrega una imagen de la pestaña visible
- Resultado: la captura no incluye barras del sistema, el Dock ni ventanas de
  otras aplicaciones superpuestas
- Medida: la imagen corresponde únicamente al área de contenido de la pestaña
- Prioridad: P2
- Criterio de aceptación:
  - Dado una ventana del navegador parcialmente tapada por otra aplicación
  - Cuando la extensión captura la pestaña
  - Entonces la imagen muestra la página completa y nada de la ventana superpuesta

### RF-04 — Instalación opcional y sin obligar

- Actor: la persona que dicta
- Acción: instala la extensión si quiere, desde lo que BtoDicta ya trae
- Resultado: BtoDicta funciona exactamente igual sin la extensión; con ella,
  mejora lo que sabe del navegador
- Medida: con la extensión ausente o desactivada, las pruebas de la bitácora
  siguen pasando sin cambios
- Prioridad: P1
- Criterio de aceptación:
  - Dado BtoDicta sin la extensión instalada
  - Cuando se ejecuta el paquete de QA
  - Entonces pasa igual que antes de existir esta spec

### RF-05 — Excluir dominios

- Actor: la persona que dicta
- Acción: añade dominios que la extensión no debe leer
- Resultado: en esos dominios no se envía texto ni captura; a lo sumo, que existe
  una pestaña activa
- Medida: con un dominio en la lista, cero envíos de texto o imagen de ese dominio
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dominio en la lista de excluidos
  - Cuando se navega por él
  - Entonces BtoDicta no recibe ni su texto ni su captura

### RF-06 — Un solo paquete para los navegadores de Chromium

- Actor: la extensión
- Acción: se instala en Chrome, Edge y Brave sin construir tres veces
- Resultado: los tres navegadores que usa la persona quedan cubiertos
- Medida: el mismo paquete carga y funciona en los tres
- Prioridad: P1
- Criterio de aceptación:
  - Dado el paquete de la extensión
  - Cuando se carga en Chrome, Edge y Brave
  - Entonces los tres reportan su estado a BtoDicta

### RF-07 — Firefox también

- Actor: la extensión
- Acción: se entrega además empaquetada para Firefox, que hoy es el único
  navegador del que no se puede leer ni la pestaña activa desde fuera
- Resultado: Firefox deja de ser el punto ciego: pasa de no saberse nada de sus
  pestañas a saberse lo mismo que de los demás
- Medida: en Firefox se recibe la pestaña activa y las audibles, igual que en los
  tres de Chromium
- Prioridad: P2
- Criterio de aceptación:
  - Dado Firefox con la extensión cargada y una pestaña de vídeo sonando
  - Cuando BtoDicta consulta el estado del navegador
  - Entonces recibe la pestaña activa y la que suena, como en Chrome

### RF-08 — La extensión avisa cuando se queda vieja

- Actor: BtoDicta
- Acción: compara la versión que reporta la extensión con la que ella trae, y avisa si no coinciden
- Resultado: quien la tenga instalada se entera de que hay una versión nueva, en vez de seguir con una vieja sin saberlo
- Medida: con una extensión de versión anterior a la de la aplicación, aparece un aviso en menos de 2 min desde que reporta
- Prioridad: P1
- Criterio de aceptación:
  - Dado una extensión que reporta una versión anterior a la que trae la aplicación
  - Cuando envía su informe
  - Entonces la aplicación lo registra y avisa a la persona de que debe recargarla

### RF-09 — Sacar la extensión de la aplicación, con su manual

- Actor: la persona que dicta
- Acción: pide desde BtoDicta una copia de la extensión donde quiera
- Resultado: tiene la carpeta lista para cargar y un manual que explica cómo, sin buscar nada por el disco
- Medida: una sola acción deja la carpeta en el destino elegido, con el manual dentro
- Prioridad: P1
- Criterio de aceptación:
  - Dado BtoDicta instalada
  - Cuando se pide sacar la extensión al Escritorio
  - Entonces aparece una carpeta con la extensión y un manual de instalación en español

### RF-10 — Un menú en el icono de la extensión

- Actor: la persona que dicta
- Acción: pulsa el icono de la extensión y ve, en un solo sitio, si está funcionando, si BtoDicta está viva, y puede excluir o volver a mirar la página que tiene delante
- Resultado: excluir un sitio deja de exigir abrir una pantalla de opciones y teclear un dominio — se hace donde ya se está, sobre la página que se está viendo
- Medida: excluir la página actual cuesta **un** clic desde el icono, y el estado de la conexión se ve sin salir de ahí
- Prioridad: P1
- Criterio de aceptación:
  - Dado una página abierta que no está excluida
  - Cuando se pulsa el icono de la extensión
  - Entonces se ve si BtoDicta está viva y un botón que excluye ese dominio; si ya estaba excluido, el mismo botón lo devuelve

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Seguridad | El canal con BtoDicta exige el mismo token que el resto de la API local y solo escucha en 127.0.0.1 | Una petición sin token o desde otra interfaz se rechaza |
| RNF-02 | Rendimiento | La extensión no añade más de 50 ms al cargar una página ni más de 30 MB de memoria al navegador | Medición antes y después con las mismas 10 páginas |
| RNF-03 | Privacidad | 0 envíos del contenido de campos de contraseña y 0 de valores de formulario | Prueba negativa con un formulario de acceso: el cuerpo enviado no contiene ninguno de los 2 valores escritos |
| RNF-04 | Continuidad | Con BtoDicta cerrada: máximo 1 reintento por minuto y 0 bytes acumulados en el navegador | 10 min con la aplicación cerrada: ≤ 10 intentos y el almacenamiento de la extensión sigue en 0 |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| BtoDicta cerrada | La extensión calla y no guarda nada pendiente | RNF-04 |
| Página de banca o con campo de contraseña | No se envía texto ni captura | RNF-03, RF-05 |
| Navegación privada / incógnito | Se trata como una pestaña normal. Decisión de Alberto; objeción del agente registrada en §9. Requiere además que el usuario autorice la extensión en incógnito a mano, porque los navegadores no lo conceden de fábrica | RF-05 |
| La extensión deja de responder | La bitácora sigue funcionando con lo que ya tiene (foco y dirección de pestaña) | RF-04 |
| Varias ventanas y monitores | Se reporta la pestaña activa de la ventana enfocada, y todas las audibles | RF-01 |

## 7. Datos y cumplimiento

- Datos que trata: direcciones de páginas visitadas, texto visible de esas
  páginas, imágenes de pestañas, y qué pestañas emiten audio.
- Datos personales: **sí**. Es navegación del propio usuario en su equipo, para su
  propia bitácora. No sale del equipo: el destino es la API local en 127.0.0.1.
  Retención: la que ya tiene la bitácora. Sin terceros implicados.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- La API local de BtoDicta (spec 005) está disponible y admite un punto de entrada
  nuevo para el navegador.
- El usuario acepta cargar una extensión sin firmar por tienda, en modo
  desarrollador, hasta que se decida publicarla.
- `chrome.tabs.query({audible: true})` sigue disponible en Manifest V3.
- Firefox soporta `browser.tabs` con `audible`, pero exige su propio empaquetado y
  su propia firma; no basta con recompilar el de Chromium.
- Para que la extensión vea la navegación privada, el usuario debe autorizarla
  explícitamente en la página de extensiones de cada navegador. Sin ese permiso,
  el incógnito queda invisible por decisión del navegador, no de esta spec.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-20 (ampliación tras probarla)

- P: ¿Qué pasa cuando cambiemos la extensión? → R: «necesito que de alguna forma
  esta extensión se actualice cada vez que hagamos algún cambio y el sistema se
  lo haga saber al usuario» (decisión de Alberto). Nace **RF-08**. La spec se
  amplía DESPUÉS de aprobada, con esta entrada fechada: no viaja hacia atrás en
  silencio.
- P: ¿Cómo la consigue alguien que no tenga el repositorio? → R: «necesito un
  espacio donde el usuario se pueda descargar desde la app a su escritorio o
  donde quiera la extensión con su manual claro de instalación» (decisión de
  Alberto). Nace **RF-09**.
- P: ¿Cómo se excluye una página sin abrir las opciones? → R: «sería genial que
  en el icono de BtoDicta del plugin se asomen opciones para activar, desactivar,
  agregar esa página o url o dominio, o quitarlo si ya está, y que dé un detalle
  de si está funcionando y BtoDicta está vivo» (decisión de Alberto). Nace
  **RF-10**. Encaja con el motivo del RF-05: con «leer todo salvo lo excluido»,
  la velocidad de excluir ES la protección, y un clic sobre la página que se está
  viendo es más rápido que teclear un dominio en otra pantalla.
- P: ¿Se prueba en los cuatro navegadores ahora? → R: «estamos solo probando con
  Edge por el momento» (decisión de Alberto). El RF-07 (Firefox) se construye
  pero su comprobación en vivo queda pendiente de que Alberto lo pruebe.

### Sesión 2026-09-20

- P: ¿Qué debe hacer la extensión? → R: «creemos el plugin de navegador para poder
  tener control ahí y hasta para que tome capturas más fieles o copie los textos de
  lo explorado y sirva para la bitácora» (decisión de Alberto)
- P: ¿Se instala con BtoDicta? → R: «venga al instalar BtoDicta, no forzadamente
  pero sí esté ahí» (decisión de Alberto)
- P: ¿Qué regla de privacidad de base? → R: «Leer todo salvo lo que excluya»
  (decisión de Alberto). Objeción registrada del agente: es la opción con más
  riesgo de capturar algo sensible antes de excluirlo; se compensa con RNF-03
  (nunca campos de contraseña) y con que excluir sea inmediato.
- P: ¿Firefox entra en esta spec o va aparte? → R: «Sí, entra ahora» (decisión de
  Alberto). Se añade RF-07 con prioridad P2: primero los tres de Chromium con un
  solo paquete, y Firefox con su empaquetado propio.
- P: ¿Qué se hace con la navegación privada? → R: «Tratarla como una pestaña
  normal» (decisión de Alberto). Objeción registrada del agente: guardar en la
  bitácora lo abierto en privado va contra lo que se espera de ese modo. Se acata;
  además el navegador exige autorización manual para ello.
- P: ¿Rama propia o main? → R: «Directo en main» (decisión de Alberto).
- P: ¿Qué dominios se excluyen de fábrica? → R: «todo es parametrizable, no
  existen excluyentes base aún» (decisión de Alberto). La lista nace VACÍA: la
  extensión no trae ninguna exclusión escrita de antemano.
- P: ¿Se puede saber qué pestaña suena sin extensión? → R: No. Comprobado el
  2026-09-20: `audible of active tab` da error -1700 y las únicas propiedades
  expuestas son URL, name, loading, class e id. Es lo que justifica esta spec.
