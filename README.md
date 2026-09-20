# 🎙 BtoDicta

Dictado por voz para macOS que **abraza el notch**: pulsa una tecla, habla, y el texto aparece EN VIVO junto al notch de tu Mac mientras las barras laten con tu voz. Pulsa de nuevo y el texto se pega donde estaba tu cursor.

## 🌐 Página oficial

**[btodicta.eztic.ec](https://btodicta.eztic.ec/)** — todo sobre la app, motores y guía de instalación.

## 📖 Manual de usuario

**[Manual completo](docs/MANUAL.md)** — instalación, cada pestaña, cada motor, cada ajuste, con capturas.

## ⬇️ Descarga

**[Descargar BtoDicta (DMG) — última versión](https://github.com/btoaldas/BtoDicta/releases/latest)**

Arrastra a Aplicaciones. Requiere macOS 14+ y Apple Silicon.

### O con Homebrew

```bash
brew install --cask btoaldas/tap/btodicta
# firma propia: para saltar el aviso de Gatekeeper
brew install --cask --no-quarantine btoaldas/tap/btodicta
```

Instala siempre el **último release**. La app también se actualiza sola desde dentro: las copias 0.40–0.42 aceptan 0.43 porque conserva su misma identidad de firma; desde 0.43, además, el DMG completo se autentica con Ed25519.

**Primera apertura** (macOS dirá "Apple no pudo verificar…" porque la app es open source y no viene de la App Store): pulsa "Listo" → **Ajustes del Sistema → Privacidad y seguridad** → baja hasta "Seguridad" → **"Abrir de todos modos"**. Es una sola vez.

![BtoDicta en acción — panel junto al notch con latido de voz, tecla fn y texto en vivo](docs/screenshot.png)

Hecho en Ecuador 🇪🇨 para el español latino — nació porque los dictados comerciales no entendían las siglas y nombres propios del español institucional.

## Características

### Novedades 0.75.0

- **El filtro del navegador mira la pestaña activa**, por su dirección: mirando
  YouTube no graba; escribiendo un correo con un vídeo detrás, sí.
- La dirección evita el engaño del título (un artículo *sobre* YouTube no es un
  vídeo). Chrome, Edge, Brave, Safari y Arc.

### Novedades 0.74.0

- **Filtro de bitácora por aplicación y título**: el juego, el reproductor o
  YouTube dejan de entrar. El audio de las apps excluidas **ni se captura**, así
  que funciona con el juego minimizado o la música en otro monitor.
- **Lista de excepciones que gana a la de exclusiones**: apartar un navegador
  entero y rescatar las reuniones de dentro.
- De fábrica no se filtra nada. Lo apartado va a la papelera, no se borra.

### Novedades 0.73.1

- **El motor de embeddings se duerme de verdad**: retenía ~400 MB y su vigía era
  un `Timer` registrado desde cualquier hilo, así que el apagado iba a ratos.
  Ahora no depende del hilo, y una prueba lo verifica de punta a punta.

### Novedades 0.73.0

- **Los cuatro motores mudos, recuperados**: el `.resume()` que faltaba aparecía
  en TRES sitios. Speechmatics 0,37 % en 4,3 s; Gladia y AssemblyAI igual.
- Comprobación automática que caza tareas de red creadas y nunca arrancadas.
  El QA pasa de 19 a 20.

### Novedades 0.72.1

- **Portero con varios motores**: para cerrar la puerta deben coincidir todos;
  para abrirla basta uno.
- Medido: los locales que transcriben con 0,00 % de error frenan **0 de 12**
  trozos de ruido (alucinan texto); Apple Speech frena 10 de 12.

### Novedades 0.72.0

- **Cuatro motores mudos por un `.resume()` que faltaba**: el sondeo del
  resultado se creaba sin arrancar. El servicio cobraba y la app no recogía.
- **Portero local** antes de gastar el motor bueno: de 12 trozos de ambiente
  llegaban 12 al motor de pago, ahora llega 1. Las voces pasan todas.
- **Papelera propia** para el ruido, recuperable una semana. Apagada de fábrica.

### Novedades 0.71.0

- **Motor concreto por la API**: `{"motor": "mistral"}` en vez de solo
  local/nube/automatico, sin cascada detrás — necesario para comparar motores.
- `scripts/comparar-motores.py` mide todos con el mismo audio y referencia.

### Novedades 0.70.0

- **Los motores locales ya no se rinden con un dictado largo**: una hora hacía
  que Voxtral pidiera 64 GB y devolviera vacío; como no era un error de tamaño
  explícito, no se troceaba. Ahora sí. Misma hora, 0,43 % de error.
- **Y el caso que no fallaba**: un motor que devuelve solo los primeros minutos
  como si fueran todo. Se detecta por desproporción texto/voz y se reintenta.
- Ambos en el punto por el que pasan los 20+ motores. QA de 18 a 19.

### Novedades 0.69.0

- **Casi 5 GB de memoria menos al arrancar**: la comprobación de huella de los
  modelos leía por trozos pero no soltaba lo leído. Ahora ocupa 1 MB.
- **Dictado largo verificado con micrófono real**: 63 minutos, 37 796 trozos,
  cero huecos, memoria plana en 28 MB.
- Las pruebas de memoria medían el RSS, que cuenta páginas ya liberadas (5 564 MB
  frente a 56 MB reales). Ahora miden `phys_footprint`. El QA pasa de 17 a 18.

### Novedades 0.68.0

- **Las tareas automáticas dejan de repetirse al reabrir la app**: hasta tres
  resúmenes del mismo día, cada uno con su llamada a la IA.
- Y el fallo contrario en las de intervalo: una rutina de «cada 3 h» podía no
  llegar nunca si cerrabas antes.
- El patrón se buscó en **todo el código** y lo vigila una comprobación
  automática. El QA pasa de 16 a 17 pruebas.

### Novedades 0.67.1

- **El aviso de saldo bajo deja de repetirse** en cada arranque: 68 avisos en un
  día por un registro que vivía en memoria.
- Puedes **silenciar un proveedor** que ya sabes agotado, sin callar a los demás.

### Novedades 0.67.0

- **El panel dice en qué se va el dinero**: gasto por motor y por mes. El primer
  vistazo revela que ElevenLabs se llevaba el **98-99 %** del total.
- **Y cuánto tarda cada motor**, medido al usarlos. Mediana, no promedio.
- No reordena nada solo: pone los números delante para que decidas.

### Novedades 0.66.2

- **El silencio deja de viajar a la nube.** La bitácora mandaba a transcribir sus
  trozos mudos: **312 llamadas gastadas en un día** para no obtener nada. Ahora se
  mira el audio antes, en local.
- El margen es generoso: 90 ms de sonido en un trozo de 30 s bastan para que se
  mande. Ajustable, y con el umbral en 0 se manda todo.

### Novedades 0.66.1

- **Los modelos se comprueban uno a uno**, no solo por su forma: cada uno del
  catálogo lleva su **huella fijada**, tomada de lo que publica Hugging Face y
  contrastada con lo instalado.
- Un modelo ajeno al catálogo se sigue instalando igual.
- Los que ya tenías se revisan al arrancar, sin estorbar y sin borrar nada.

### Novedades 0.66.0

- **Motores locales al día**: whisper.cpp 1.9.4 y el de embeddings con ~1000
  cambios acumulados. Comprobado antes de instalar: **texto idéntico** letra por
  letra, y los mismos vectores de embeddings.
- **El comando `transcribir` de la Mac usa ya la API**: deja de conocer las
  carpetas internas.
- Las carpetas permitidas de la API **se suman** a las de fábrica, y se rechazan
  las demasiado amplias aunque se pongan a mano.

### Novedades 0.65.4

- **Deja de gastar llamadas contra cuentas vacías.** Un proveedor sin saldo se
  apartaba media hora, pero el saldo no vuelve solo en media hora: 57 llamadas
  desperdiciadas en un día. Ahora el tiempo depende de si el problema se arregla
  solo.

### Novedades 0.65.3

- **Lo que se descarga se comprueba antes de instalarse**: una página de error ya
  no queda guardada con el nombre del modelo.
- Una versión **no puede publicarse sin los motores** que funcionan sin internet.
- Tercera auditoría, esta de cadena de suministro: 4 áreas, 2 hallazgos.

### Novedades 0.65.2

- **Un dictado que no se puede guardar ya no parece guardado.** Si el archivo no
  se podía abrir, el contador de bytes subía igual y todo parecía normal.
- Segunda auditoría, esta de corrección de errores: 5 áreas, 1 hallazgo.

### Novedades 0.65.1

- **Arreglado un agujero de seguridad real**: el texto que pronuncia la voz local
  podía ejecutar órdenes del sistema. La cadena era pantalla → IA → voz → shell.
- La puerta local tiene **tope de peticiones**, para que un bucle mal escrito no
  te vacíe el saldo.
- Primera **auditoría de seguridad** completa: 9 áreas, 2 hallazgos, 7 correctas.

### Novedades 0.65.0

- **Otros programas de tu Mac pueden transcribir con BtoDicta.** Le mandan la
  ruta de un audio y reciben el texto, con los mismos motores y el mismo
  vocabulario que tu dictado. También pueden pedirle pulir un texto.
- **Viene cerrada.** Se enciende en Ajustes y usa un token. Escucha solo en tu
  propia máquina y solo lee audios de Descargas, Documentos y la temporal.

### Novedades 0.64.3

- **El registro dice qué hacer, no un número**: «se quedó sin saldo», «no acepta
  la clave», en vez de «HTTP 402». El código sigue detrás.
- Dos resúmenes del mismo segundo ya no comparten archivo.
- Con esto se cierran los **24 pendientes** arrastrados de versiones anteriores.

### Novedades 0.64.2

- Los resúmenes del día ya no salen cortos por generarse con el día a medio
  transcribir, ni congelan la ventana mientras se preparan.
- Limpieza de trocitos de audio que la purga nunca alcanzaba.
- El trozo que se está grabando ya no entra al índice a medio escribir.
- Arrastrar un deslizador ya no reinicia el planificador en cada paso.

### Novedades 0.64.1

- **Se acabaron los archivos huérfanos al cerrar.** Medido: de 2–4 por arranque a
  **cero**.
- **El audio del sistema vuelve solo** tras un error, en vez de quedarse muerto
  sin avisar.
- La pestaña de la bitácora recorría el árbol **dos veces** por refresco.
- La retención vuelve a aplicarse sola cada pocas horas, no solo al arrancar.
- La limpieza dejó de des-indexar archivos que no consiguió borrar.
- Un pulido que vuelve correcto pero con el texto en otro campo ya no se pierde.

### Novedades 0.64.0

- **La bitácora ya no fotografía tu gestor de contraseñas.** Podía excluir apps
  desde siempre, pero la lista venía **vacía**. Ahora trae de fábrica los
  gestores conocidos y el llavero del sistema.
- Segunda capa por **título de ventana**, para lo que no se excluye por app —una
  pestaña del banco en el navegador—. Vacía de fábrica.
- **Lo que se lee en pantalla ya no puede darle órdenes a la IA**: el material
  viaja dentro de una valla impredecible con una regla que manda sobre el resto.
- El texto dictado en el registro pasa a ser un ajuste.

### Novedades 0.63.7

- **El audio deja de copiarse en todo el recorrido.** El historial adopta el
  archivo del grabador moviéndolo en vez de reescribirlo, y los motores locales
  lo reciben por enlace, no por copia. En seis horas, 1,3 GB de trabajo que
  desaparecen.
- **Arreglado un fallo que podía perder un dictado**: dos dictados en el mismo
  segundo compartían archivo y el segundo pisaba al primero.
- El cierre de conexión sobre la sesión compartida había vuelto en **trece
  sitios**. Retirado, y ahora una comprobación automática lo vigila.

### Novedades 0.63.6

- Las pruebas internas miden también el tiempo: leer un tramo de 25 MB de un
  dictado de seis horas tarda **2,9 ms**. Armar el paquete del envío de una hora
  de audio: 7 ms en memoria contra 54 ms en disco — más lento en relativo,
  milésimas en absoluto, y 115 MB menos de memoria.

### Novedades 0.63.5

- **Los doce motores suben el audio desde el disco.** Enviar un dictado armaba en
  memoria un paquete con el audio entero dentro. Ahora se escribe a disco por
  trozos y se transmite desde ahí: **preparar el envío de seis horas cuesta 0 MB**.
- Un dictado de seis horas ocupa **80 MB de principio a fin** —grabar 13,
  terminar 3, enviar 0— frente a cerca de 2 000 MB antes.
- Arreglado el envío por lotes de ElevenLabs, que se quedó fuera de la corrección
  de 0.59.0 y seguía heredando sockets muertos.

### Novedades 0.63.4

- **El dictado deja de vivir en la memoria.** El grabador retenía todo lo hablado
  en RAM y al terminar hacía una segunda copia completa: **1 388 MB** en un
  dictado de seis horas. Ahora el audio va al archivo según entra y terminar no
  copia nada. Misma prueba: **80 MB**.
- La aplicación creía tener esto resuelto desde 0.60.0. La medición que lo decía
  era correcta, pero **probaba otro componente** y nunca pasaba por el grabador.
- **El audio de trabajo se conserva los días que fijes** (siete de fábrica, 0 =
  nunca), en *Ajustes → Audio de trabajo*.
- **Reabrir la app ya no reenvía el resumen por correo.** El registro de lo
  enviado vivía en memoria; una tarde de reinicios mandó diecisiete correos
  cuando tocaban dos.
- La bitácora vuelve a decir cuándo empieza a escuchar tras cederle el micrófono
  al dictado.

### Novedades 0.63.3

- **El mismo fallo de 0.63.2 estaba en la bitácora**, y ahí era peor: si la
  escucha no entraba, **dejaba de grabar en silencio**. Corregido igual, más el
  mapa de canales, que ahora viaja con el conversor — con la cancelación de eco
  el micrófono llega con nueve canales y sin ese mapa el audio se perdía sin
  avisar. La activación por voz recibe el mismo arreglo.

### Novedades 0.63.2

- **Arreglado el «el micrófono no aceptó la escucha»** que obligaba a cerrar y
  volver a abrir la app. Pasaba al dictar justo cuando la bitácora soltaba el
  micrófono: se leía el formato del aparato anterior —44 100 Hz cuando ya estaba
  en 48 000— y la escucha se rechazaba. Ahora el formato lo resuelve el motor de
  audio en el momento, y si algo falla se reintenta tres veces.

### Novedades 0.63.1

- **OpenCode Go** como proveedor de IA: la suscripción mensual con decenas de
  modelos abiertos incluidos, para pulido, modos y agente. **No transcribe**:
  solo expone modelos de texto.

### Novedades 0.63.0

- **Panel de salud**: el estado real de todo en una pantalla, sin abrir el
  registro. **Saldo de seis proveedores** (ElevenLabs en caracteres; Fish,
  DeepSeek, OpenRouter y Novita en dinero; Speechmatics en horas) y **prueba de
  vida de los veintitrés** que tengas configurados, quién está apartado y por
  qué, techos aprendidos y cola de la bitácora.
- Al probarlos se **lee lo que contestan**, así que salen cosas que de otro modo
  no se saben: una cuenta suspendida por impago aparece dicha con esas palabras,
  no como un código HTTP.
- **Aviso de saldo bajo**: antes te enterabas cuando fallaba un dictado. Ahora
  avisa al bajar del 15 % o de 5 dólares, una vez al día por proveedor.

### Novedades 0.62.1

- **El pulido lento, de raíz.** Ya se apartaba al proveedor caído, pero solo
  **quince segundos**: al dictado siguiente volvía a llamarlo. Ahora el castigo
  sube con los fallos seguidos (1 min → 5 → 15) y se perdona en cuanto conteste.
- **Un dictado largo ya no puede entregarse recortado.** La comprobación exigía
  bajar de 32 caracteres para sospechar, así que 5 000 → 800 pasaba como bueno.
  Ahora se rechaza cualquier pulido que pierda **más de la mitad** de las letras.

### Novedades 0.62.0

- **El pulido ya no reintenta al que acaba de fallar.** Si un proveedor deja de
  contestar, cada dictado pagaba su plazo otra vez: pulir 577 caracteres pasó de
  un segundo a **veintitrés**. Ahora se aparta unos minutos y vuelve solo en
  cuanto conteste bien.
- **Los envíos de correo son una lista**, no un horario con un periodo común:
  cada línea con su hora, su periodo y sus días. El de ayer a las 07:00, el de
  hoy a las 20:00 y el de la semana los sábados.

### Novedades 0.61.0

- **La bitácora del día, en tu correo.** BtoDicta junta lo transcrito, lo
  consolida con tu IA en un solo texto sin repetir ideas y te lo manda desde **tu
  propia cuenta** de correo. Automático a la hora que fijes, o a mano desde el
  menú.
- **La prueba de envío dice por qué falló**, no solo que falló: clave, puerto,
  destinatario o servidor dan mensajes distintos, cada uno con su consejo.

### Novedades 0.60.0

- **El dictado deja de vivir en la memoria.** El audio se guardaba por partida
  doble en RAM además del archivo que ya se escribe en disco mientras hablas —
  691 MB por copia en un dictado de seis horas. Ahora el archivo es la única
  fuente. **Medido: seis horas simuladas, 0 MB de subida.**
- El grabador suelta el audio en cuanto entrega el `.wav`, y la vista previa en
  vivo con motor local toma solo los últimos dos minutos en vez de copiar el
  dictado entero cada 1,6 segundos.
- Pendiente: la entrega al motor de transcripción todavía hace una copia.

### Novedades 0.59.3

- **El aviso de cancelar ya no esconde el notch.** Seguías grabando pero perdías
  de vista el texto en vivo y el cronómetro.
- **Los ajustes de cancelación están en la interfaz**, en *Configuración →
  Ajustes*, debajo de «Cancelar con Esc».

### Novedades 0.59.2

- **Un Escape suelto ya no cancela el dictado.** Hay que pulsarlo **dos veces
  seguidas**: la primera solo avisa en el notch. Así puedes cerrar una vista
  previa con Esc sin cortar lo que estás grabando.
- Nuevo ajuste `cancelar_confirma` (apagado): hace que cancelar desde el notch
  también pida repetirse.

### Novedades 0.59.1

- **Cancelar un dictado ya no lo borra.** Cancelar ejecutaba un borrado real del
  audio y del texto. Y como Escape es un atajo **global** mientras grabas,
  bastaba pulsarlo para cerrar una ventana ajena para perder el dictado entero.
  Ahora queda guardado en el historial y se recupera como cualquier otro; solo se
  descarta lo que dura menos de dos segundos.
- Pendiente: Escape sigue siendo global, así que aún puede interrumpir un
  dictado. Ya no se pierde nada, pero hay que volver a empezar.

### Novedades 0.59.0

- **Se acabaron los dictados que no caben.** Cada motor tiene un techo de tamaño
  y ninguno lo anuncia igual. Ahora, si un motor rechaza el envío entero, la app
  **parte el audio en tramos con solape y reintenta con el mismo motor**,
  cosiendo después. Medido: 20 minutos que antes fallaban salen completos —
  3 348 palabras de las 3 360 habladas.
- **Lo aprende, y se desdice solo.** El techo de cada motor queda anotado para no
  volver a pagar el rechazo. Pero solo aprende de lo que dice el servidor: una
  caída de internet **no** deja medida. Si luego entra algo más grande, la medida
  se tira; y caduca a las dos semanas.
- **El pulido igual**: si la IA corta la respuesta por contexto, el texto se pule
  por tramos partidos por frases. Un dictado de dos horas se pule entero.
- **Arreglado un cuelgue intermitente en los doce motores de nube**: todos
  mandaban `Connection: close` sobre la conexión compartida, así que el dictado
  siguiente heredaba un socket ya cerrado y esperaba en balde hasta agotar el
  plazo. Medido: de ocho dictados separados por 45 s, **seis tardaban 18,7 s en
  vez de 1,8**. Ahora la conexión se renueva sola y ninguno se cuelga.

### Novedades 0.58.0

- **Cronómetro de grabación en el notch**: bajo las barras de voz ves cuánto
  llevas grabando. Al terminar, el aviso dice la duración del audio
  (*"Transcribiendo 3:00…"*), medida del propio audio y no del reloj.
- **Banco de pruebas sintético**: la app genera dictados con la voz de macOS y
  los manda por el camino real del motor de nube, a la duración y repeticiones
  que se le pidan. Sirve para cazar fallos que solo aparecen con audio largo sin
  tener que dictar a mano veinte veces.
- Medido con él: la transcripción de Fish Audio tarda un **3-4 % de lo que dura
  el audio** — tres minutos se transcriben en menos de seis segundos.

### Novedades 0.57.2

- **Fish Audio mide cada transcripción** (tamaño y tiempo) y anota en el registro
  las que tardan más de lo normal o fallan. Desde fuera de la app esa API
  responde en menos de 3 segundos; si dentro tarda más, ahora queda constancia
  con el dato exacto en vez de una suposición.

### Novedades 0.57.1

- **Se acabó el cambio de motor sin motivo.** Un dictado largo con Fish Audio
  agotaba un plazo fijo de 60 s y se iba a otro motor con el primero sano —y ya
  transcrito y cobrado, así que se pagaba por texto que no llegaba. El plazo es
  ahora proporcional al audio y, si el corte fue de la conexión, se reintenta
  una vez antes de rendirse.
- **La vista previa en vivo se arregla sola**: si falta el modelo de dictado de
  macOS, la app lo descarga en segundo plano en lugar de quedarse muda para
  siempre. Es lo que te enseña que está escuchando con los motores de nube que
  transcriben por lotes.
- **Fish Audio ahorra crédito solo**: prueba su modelo de voz gratuito primero y
  solo paga si aquel falla.

### Novedades 0.57.0

- **Fish Audio, nuevo proveedor de voz y de transcripción.** Como ElevenLabs,
  hace las dos cosas con una sola clave (`FISH_API_KEY`): habla con **tu voz
  clonada** y transcribe. Aparece en los dos catálogos y se configura igual que
  el resto, con tu propia key.
- La voz se elige por el **`reference_id`** de tu clon en fish.audio, no por un
  nombre. Modelos `s2.1-pro`, `s2-pro`, `s1` y `s2.1-pro-free` — este último
  viene puesto porque **habla sin gastar crédito**.
- Aviso que ahorra tiempo: en Fish el **crédito de API es una bolsa distinta**
  de la de la web y empieza en cero. Sin recargarlo, todo lo que no sea el
  modelo gratuito responde 402; BtoDicta lo detecta, lo pone en cuarentena 30
  minutos y sigue con el motor siguiente.

### Novedades 0.56.2

- **El dictado se entrega siempre.** Si la recuperación de texto perdido
  arrancaba el motor por lotes y este se atascaba, nadie cortaba la espera: el
  texto no llegaba nunca. Ahora hay un tope que entrega lo recuperado pase lo
  que pase, y al proceso atascado se le manda parar.
- **Cada congelación costaba minuto y medio de audio para nada.** Se pedía la
  ventana y se descartaba el resultado por no saber dónde coserlo. Ese punto se
  anota ahora en el instante en que el motor enmudece, así que el tramo
  congelado a mitad del dictado sí se recupera.
- **Las elisiones marcadas con «…» ya se ven** (antes solo las de tres puntos).
- **Al venir de BetoDicta, el registro de la semana ya no se pierde**: se une al
  nuevo en orden y el original se conserva aparte.

### Novedades 0.56.1

- **El asistente de mudanza ya instala de verdad.** Viajaba sin la clave con la
  que se comprueban las firmas y además preguntaba por una versión «más nueva»
  que nunca podía existir. Probado de punta a punta.

### Novedades 0.56.0

- **Asistente de mudanza para quien venía de BetoDicta**: el paquete incluye una
  segunda aplicación con el nombre e identificador anteriores, de modo que la
  actualización automática de una instalación vieja la instala y abre un
  asistente que hace la mudanza en un clic. Antes esa actualización se cancelaba
  con un error de identidad.

### Novedades 0.55.1

- **El índice de la bitácora se corrige al mudar la carpeta**: antes quedaba
  apuntando a la ruta anterior y volvía a marcar como pendiente material ya
  transcrito y leído. Ahora no se repite ni un segundo de trabajo.

### Novedades 0.55.0

- **La app pasa a llamarse BtoDicta.** Nombre nuevo en la aplicación, la barra de
  menús, el instalador, la documentación y el repositorio.
- **Tus datos se mudan solos** al abrir por primera vez: modelos, voces,
  historial, ajustes y bitácora pasan a las carpetas con el nombre nuevo. Se
  mueven, no se copian, así que es instantáneo aunque pesen decenas de gigas.
- **Las credenciales del Llavero se migran solas** la primera vez que se usan.
- **macOS volverá a pedir permisos** (micrófono, accesibilidad, automatización)
  por ser una aplicación nueva para el sistema. Solo la primera vez.
- **Los Atajos de macOS** que ya tuvieras siguen apuntando a la app anterior:
  hay que volver a generarlos desde la app Atajos.

### Novedades 0.54.2

- **Micrófono mudo, arreglado**: la app fijaba a la fuerza el aparato de entrada
  y eso dejaba el micrófono sin entregar nada (la llamada del sistema decía
  «correcto» y no llegaba un solo buffer). Ahora solo se fija cuando hay que
  cambiar de aparato de verdad.
- **Funciona en cualquier Mac**: la frecuencia del micrófono la pone cada equipo
  y la app la convierte a la suya; ninguna cuenta depende ya del hardware.
- **Un dictado sin audio avisa** a los 6 segundos en vez de quedarse esperando.

### Novedades 0.54.1

- **La app ya no se cierra al empezar a dictar**: si el micrófono estaba
  cambiando de estado justo al pulsar la tecla (la bitácora acababa de soltarlo),
  macOS devolvía un formato inválido y el proceso abortaba a mitad de la
  grabación. Ahora se valida el formato, se reintenta tras un respiro y, si no
  hay micrófono, se avisa sin cerrar nada.
- **La bitácora ya no se reinicia en bucle**: cuando el motor de audio arrancaba
  sin entregar sonido se reiniciaba cada 8 segundos indefinidamente. Sigue
  vigilando siempre —grabar es su función—, pero baja a un intento por minuto y
  se recupera sola en cuanto el micrófono responde.

### Novedades 0.54.0

- **Que nunca falte texto en un dictado largo**: los motores de dictado en vivo
  pueden saltarse una frase (dejando «...») o dejar de transcribir aunque sigas
  hablando. Ahora un vigía lo detecta —hay voz y el texto no crece— y **relanza
  el motor desde el punto exacto** en que se quedó, conservando lo ya transcrito.
- **Reparación quirúrgica, no trabajo doble**: al terminar solo se revisan los
  tramos rotos, cada uno con una ventana corta de audio, y se cosen en su sitio
  por coincidencia de palabras. Un dictado sano no paga nada: cero
  re-transcripciones y cero espera. Varias roturas en la misma grabación se
  atienden todas. Sin IA y sin nube: corre con tu motor local.

### Novedades 0.53.1

- **Dictado protegido**: los clasificadores como Prompt Guard no sirven para
  redactar y ya no se ofrecen para pulido. Si llega un puntaje o una respuesta
  inválida, se intenta el respaldo; si ninguno sirve, se conserva el original.
- **Archivos por la misma cascada STT**: WAV, MP3, M4A, MP4 y MOV se convierten
  localmente a WAV antes de usar tus motores habilitados en el orden elegido.
  Ya no existe la ruta directa obligatoria a ElevenLabs. Ogg y otros códecs pueden
  utilizar un ffmpeg ya instalado; sin decodificador compatible se avisa sin subir nada.
- **Pulido adaptativo**: base de 8 s por proveedor, ampliada según texto y contexto
  hasta 120 s. La cascada comparte un máximo de 24 s para textos cortos y hasta
  240 s para los largos. Cuota, clave inválida y problemas de red activan cuarentena.
- **Modelos generativos actuales**: DeepSeek V4.1 Flash (`deepseek-flash`), sin
  razonamiento para pulir; Groq GPT OSS 20B como opción de menor tarifa pública
  de producción consultada. Los precios son estimaciones, no facturas.
- **Historial recuperable**: los rescates aditivos se muestran sin duplicar entradas
  ni sobrescribir los textos originales. Corregidos los días relativos del resumen
  de tareas y optimizada la copia del último dictado.

![Espera del pulido: captura real de la compilación de validación](docs/img/pulido-adaptativo-0531.png)

Detalles, límites y pruebas: [QA de cascada y pulido](docs/QA-cascada-pulido-2026-09-10.md).

- **Bitácora continua (opt-in)**: graba tu voz, el audio del sistema y capturas de pantalla en segundo plano; transcribe y lee todo en tandas diferidas con tus motores; y genera documentos del día (resumen, ideas, tareas…) con la IA que elijas —local o nube— mediante rutinas programables. El dictado siempre tiene prioridad sobre el micrófono. Apagada de fábrica.

- **Modos — entiende la intención y decide qué hacer**: además de **Dictado**, usa **Correo, Oficio, Tarea, Nota, Traducir, Resumir, Asistente, Agente, Buscar, Música** o **Aplicación**, cada uno con comportamiento/color propios. El modo Aplicación hace un inventario de las apps reales del Mac: *"modo abrir aplicación Word, borrador del informe"* abre Word y coloca el texto (sin enviarlo). Entiende comandos explícitos y pedidos naturales, incluso cadenas de **1 a N etapas** (*"resume, traduce al quichua y envía por correo y WhatsApp"*) con idioma y destinatario. Ante una propuesta, el notch se expande: **fn una vez confirma; X continúa el dictado normal**. Reglas locales → embeddings con margen → IA opcional como último árbitro, siempre con degradación suave y sin ejecutar acciones ambiguas. También admite pausa en vivo, app/sitio, un solo uso y modos propios.
- **Asistente por voz parametrizable**: nombre, personalidad y disparadores libres de mínimo dos palabras. En macOS 26 ofrece **activación manos libres local y opt-in**. El comportamiento recomendado es estable y funciona como un timbre: dices solamente la frase configurada, una pausa acústica configurable confirma que terminaste, BtoDicta responde con una alternativa breve editable (*“Te escucho”*, *“Dímelo”*, *“Cuéntame”*…) y abre un turno Agente limpio. El **dictado asistido sin manos** entiende *“dicta/transcribe/escribe/corrige/mejora esto…”*: pule, pega en el campo original y conserva opcionalmente el portapapeles; *“dictado”* solo abre un segundo turno automático. Cada salida se configura por separado y degrada al texto original sin IA. Si el parcial crece con contenido, el candidato se cancela; frase + orden en una sola toma sigue disponible como opción avanzada, apagada por defecto. El listener se pausa al grabar, procesar o hablar y se rearma al volver a reposo. Una **pasarela Siri/Atajos firmada e instalable** adopta el nombre actual del agente; cuando manos libres ocupa el micrófono, una compatibilidad local opt-in reconoce solo *“Oye Siri + nombre”* sin robar órdenes genéricas a Siri. Antes de despertar no registra ni sube ambiente; fn sigue disponible y versiones anteriores degradan sin bloquear. Como toda app de terceros que usa el micrófono, macOS mantiene visible su indicador de privacidad. Incluye memoria corta local con seguimientos (*“mándaselo a Andrés”*), IA propia, Hermes o **cuenta ChatGPT mediante Codex oficial**, con modelo/razonamiento elegibles, failover y tres niveles de autonomía. La cuenta Codex también puede elegirse para **pulido, traducción y la IA de cada Modo**, pero está identificada como IA de texto y **no entra en la cascada STT**. Entiende órdenes estructuradas como *“abre Gmail y escribe un correo para a@b.com…”* o *“abre Word y crea un oficio…”*: enruta localmente, usa IA solo para redactar, abre **borradores que nunca envía solo** y permite crear un archivo mediante selector nativo. También consulta el **clima y pronóstico reales** y controla **porcentaje, subida/bajada, máximo y silencio del volumen del Mac**, todo localmente y con verificación del estado final. Puede responder en texto o texto+voz y nunca anuncia éxito antes de la evidencia. Recordatorios/Calendario usan EventKit; **Nota de Apple crea, da formato y vuelve a leer una nota real mediante la automatización oficial de Notes**; archivos usan Spotlight. La cuenta ChatGPT y el API OpenAI siguen separados; BtoDicta delega la autorización a Codex y nunca lee sus credenciales.
- **Modo Conexión API — habla con cualquier sistema que declares**: un modo puede conectar BtoDicta con **cualquier API REST** (un sistema de tu trabajo, una API pública, tu backend). Configuras URL, autenticación (sin auth, API key o **usuario+clave→token**), endpoints con variables tipadas, y un **prompt** que le enseña a la IA cómo usarla; **la IA arma el llamado desde tu dictado libre** y te cuenta el resultado hablado con el estilo que pidas. Nada del sistema concreto vive en la app: **todo es configuración tuya**. Los endpoints de **escritura siempre piden tu visto bueno** (proponer → ves la tabla del servidor → **fn** confirma), con tiempo generoso para leer y la opción de ajustar la propuesta por voz sin empezar de cero. **La IA nunca ejecuta HTTP ni ve las credenciales** (solo propone un plan JSON que Swift valida); la **clave vive en el Llavero**, jamás en el archivo ni en los registros; fail-closed en `https`, sin redirecciones fuera del host. **Compartes tus conexiones** exportando tus modos a un paquete JSON **sin ninguna clave**: tu compañero importa los que elija y solo pone la suya. Apagado por defecto (*Ajustes → Asistente → Conexiones API*)
- **Recetas de automatización y Atajos portables**: incluye Resumen del día, empezar/cerrar jornada, reunión, actuar o leer la selección, estado del Mac, captura inteligente, conversión de audio seleccionado y escenas HomeKit autorizadas. Las recetas encadenan pasos con evidencia y se importan/exportan como paquetes JSON **Trabajo, Universidad, Casa o Personal**. El wizard pregunta el nombre del asistente y ofrece tres instaladores firmados, recuperables luego desde Ajustes: **Escuchar asistente, BtoDicta Universal y Reproducir música**. macOS siempre pide consentimiento para añadirlos. El puente universal acepta acciones estructuradas para música, calendario, recordatorios, apps, foco, HomeKit y capturas sin exportar claves ni obligar a mantener decenas de Atajos aislados.
- **Tareas y notas con recordatorios locales**: detecta fechas dictadas, muestra un tablero y calendario, avisa una sola vez mediante notificación de macOS + notch y, si quieres, la voz TTS elegida. Al despertar o volver a la app recupera lo vencido. Los resúmenes de mañana/tarde son configurables; permanecen 100 % locales o pueden recibir redacción opcional de la IA elegida, con fallback local en seis segundos.
- **Captura y grabación de pantalla por voz**: pantalla completa/principal, ventana, selección o cuadrante; Escritorio/Descargas/Documentos/selector; nombre, portapapeles, abrir, duración, micrófono y clics configurables. Entiende también formas naturales como *“grabemos la pantalla”* o *“hagamos una grabación”* sin convertir una grabación de audio en captura; si falta el área, pregunta **pantalla o ventana** y conserva el pedido. Sin duración, BtoDicta graba de inmediato y una sola pulsación de la tecla de dictado —o **Detener y guardar** en su menú— cierra el `.mov` exactamente en la carpeta pedida. Al terminar deja una confirmación persistente con la ruta y **Ver en Finder**. Fragmentos periódicos configurables protegen las tomas largas y se recuperan al reabrir tras una caída; el notch permanece oculto. Para WhatsApp eliges **solo portapapeles**, **pegar sin enviar** (recomendado) o **autoenviar** de forma explícita; incluso entonces solo envía si Accesibilidad confirma que apareció una vista previa nueva del adjunto.
- **Modo Música con failover y reproductor interno**: Apple Music, Spotify, **BtoDicta · YouTube**, YouTube Music, YouTube, SoundCloud, Bandcamp o un buscador propio con `{q}`; la cascada se ordena y salta lo no disponible. **“Pon/reproduce”** intenta hacer sonar una coincidencia; **“busca”** abre resultados sin reproducir. El reproductor propio conserva por separado **Buscar, Favoritos, Historial, Cola y Mis listas**, permite filtrar y mezclar la fuente activa, y confirma Play/Pausa/Stop con el estado real del IFrame. Un video bloqueado para aplicaciones (errores 101/150) se omite una sola vez, avisa y continúa; nunca entra en bucle. La búsqueda oficial muestra un contador diario y, al agotarse la cuota o fallar la red, cae sin IA a resultados previos, favoritos, cola, historial y listas ya abiertas. **Pantalla** muestra solo el video; **Compacto** recorta la interfaz pero conserva visible el reproductor oficial. Usa YouTube Data API + IFrame Player oficiales, con API key propia para búsqueda pública u OAuth de escritorio para listas privadas, autorizado en el navegador y sin contraseña embebida ni extracción de audio. *“Pon música”* elige por defecto una pista distinta al azar, aunque puedes configurarlo para reanudar lo último. Para un artista/título que no está local, consulta el catálogo público oficial de Apple, selecciona el primer resultado **visible** mediante Accesibilidad y verifica la fila/trackId real antes de afirmar éxito. En Spotify y YouTube Music, una orden explícita de reproducir busca, activa un resultado verificable y comprueba el estado; una orden de buscar nunca pulsa Play. El Atajo firmado **“BtoDicta · Reproducir música”** sigue incluido como puente opcional. Si un motor no confirma audio, salta al siguiente sin inventar éxito.
- **Texto en vivo 100% LOCAL**: Voxtral Realtime 4B o Nemotron 3.5 Streaming (motor [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)) — ves lo que dices mientras lo dices, sin internet. En 0.48.1 se verificaron con modelos reales `transcribe.cpp` 8c7ae67 (motor 0.2.0) y `llama.cpp` b10068; Canary, Nemotron y Voxtral Realtime conservaron la compatibilidad tras reconstruir el puente local contra la ABI nueva. Voxtral Mini sigue enviando primero la instrucción y luego el audio. Las revisiones exactas y su QA quedan en [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md)
- **Preview universal en el notch**: en macOS 26, el dictado nativo de Apple puede mostrar **en vivo y de forma local** lo que vas diciendo aunque el motor real (por ejemplo Groq) trabaje por lotes. Es solo una vista previa: al soltar `fn`, tu cascada elegida hace la transcripción definitiva
- **Texto en vivo en la nube**: streaming por WebSocket con ElevenLabs Scribe v2 Realtime y (opt-in) **Deepgram, Soniox, AssemblyAI, Speechmatics, Gladia** — marcados con etiqueta **"EN VIVO"** en la lista de motores
- **Muchos motores de transcripción, varios GRATIS y otros premium**: nube compatible-OpenAI (ElevenLabs, Groq Whisper gratis, OpenAI, Mistral Voxtral, Fireworks) · API propia (Hugging Face gratis, Deepgram, AssemblyAI, Gladia, Speechmatics, Cloudflare, **Soniox**, **Azure con es-EC de Ecuador**) · locales con detección inteligente (Ollama/LM Studio solo si tienen whisper). Precios por hora **se actualizan solos** desde LiteLLM
- **Failover multi-motor**: cascada arrastrable; si uno falla, salta al siguiente solo. Un gateway propio también puede transcribir (no solo pulir)
- **Modelos locales descargables desde la app**: Whisper (tiny→large-v3), Voxtral Mini 3B y Realtime 4B, Nemotron 3.5, Canary 1B Flash
- **Tu propia voz, local, segura y portable**: una persona puede conservar hasta cuatro carriles sin perder ninguno: **✨ Máxima (XTTS + Resemble Enhance)**, **Calidad (XTTS residente)**, **⚖️ Equilibrada (Qwen3‑TTS sobre MLX, streaming local en Apple Silicon)** y **⚡ Rápida (Piper/ONNX)**. Máxima replica dentro de BtoDicta la receta de mayor identidad (parámetros XTTS, restauración y normalización), sin llamar a Hermes ni a una carpeta de Descargas. Entrenar también usa scripts y bases verificadas gestionadas por la app. Solo el motor activo queda caliente: 60 min al abrir, 15 min tras usarlo y una frase silenciosa opcional, todo editable. Los textos largos XTTS se segmentan localmente y un stream truncado ya no se acepta como completo. El paquete portable lleva modelo, referencias, persona y recetas; los runtimes comunes se instalan una vez. Quitar una voz la mueve a una papelera recuperable y cambiar/quitar componentes siempre pide confirmación
- **Panel abraza-notch**: latido de voz a la izquierda del notch, tecla a la derecha, teleprompter de una línea debajo — negro puro, como si fuera parte del hardware
- **Tecla `fn`** (o F1–F12, configurable) — toque limpio para empezar/terminar, las combinaciones fn+otra-tecla no lo disparan; opcionalmente exige **doble pulsación para iniciar** y una para detener
- **Keyterms**: tu vocabulario personal viaja al modelo — nombres propios y términos técnicos salen bien a la primera
- **Reemplazos**: correcciones automáticas post-transcripción (palabra completa, sin distinguir mayúsculas)
- **Pulido con cualquier IA + elige el modelo**: pule/traduce con Groq, OpenAI, Mistral, OpenRouter, DeepSeek, xAI, **Anthropic (Claude)**, **Gemini (Google)**, **Moonshot/Kimi K2.6** o **Kimi K3/K2.7 con la cuota de tu cuenta Kimi Code**, además de tu gateway propio — o **local** (LM Studio/Ollama, sin que nada salga de tu Mac). Eliges el **modelo** de cada proveedor al vuelo y, si publica precios, ves el costo. Las claves de Kimi API y Kimi Code se mantienen separadas para no mezclar cobros/cuotas. Aviso de privacidad al usar nube/terceros
- **Push-to-talk opcional**: graba mientras mantienes la tecla y termina al soltarla (o el modo toque de siempre)
- **Caja negra**: cada dictado guarda audio y texto en `historial/año/mes/día/` — el audio se escribe a disco EN VIVO chunk a chunk; un crash no te roba ni un segundo
- **Pausa real de multimedia**: al dictar pausa lo que suene (Edge, Chrome, Music, Spotify, YouTube…) y lo reanuda al terminar, además de bajar el volumen; usa el estado real de reproducción, sin bug de toggle
- **Guardián del silencio**: si te olvidas la tecla abierta, se cierra solo tras N segundos sin voz (no le regalas plata a la nube)
- **Odómetro + gasto de pulido**: minutos dictados por día/semana/mes/año y costo estimado, más KPIs de gasto de pulido con IA (tokens→costo) con gráfica, en Estadísticas
- **Búsqueda por significado en el historial** (semántica, opt-in): encuentra dictados por IDEA, no por palabra exacta, con embeddings — motor a elegir (Ollama local gratis, OpenAI, Gemini, Mistral)
- **Salvaguarda anti-inyección** (opt-in): si un gateway de terceros devuelve texto anómalo (comandos shell que no dictaste), pega tu dictado original
- **Ayuda por proveedor**: cada IA de nube (chat y voz) trae un icono de ayuda con explicación instantánea y un enlace **"Conseguir clave"** que abre la página oficial de su API key
- **Copiar último dictado**: rescate en un clic desde el menú
- **Actualizador estable/beta**: canal automático, solo estable o estable+beta; consulta al abrir y periódicamente (1–24 h), permite comprobar a mano y usa failover cuando GitHub excluye las prereleases de `latest`

## Requisitos

- macOS 14+ (Apple Silicon)
- **Nada más para empezar**: los motores **locales** (Whisper, Voxtral, Nemotron, Canary) corren 100% offline, gratis y **sin ninguna API key**
- *(Opcional)* la API key de un servicio de **nube** si quieres máxima calidad o texto en vivo — varios con capa **GRATIS** (Groq Whisper 2000/día, Hugging Face…). El asistente te lo pone fácil y cada proveedor tiene un botón "Conseguir clave"
- *(Solo para compilar desde el código)* Xcode 26+

## Instalación

```bash
git clone https://github.com/btoaldas/BtoDicta.git
cd BtoDicta
make install       # compila y copia a /Applications
open -a BtoDicta
```

Tu API key, por cualquiera de estas vías:

```bash
mkdir -p ~/.btodicta
echo 'ELEVENLABS_API_KEY=tu_key_aqui' > ~/.btodicta/.env
```

o exporta la variable de entorno `ELEVENLABS_API_KEY`.

### Permisos de macOS

BtoDicta necesita **Micrófono**, **Monitorización de entrada** (para la tecla `fn`) y **Accesibilidad** (para pegar el texto). **Grabación de pantalla** solo se solicita si activas capturas/grabaciones desde el Asistente. **Ubicación** es opcional y solo se pide cuando consultas el clima sin decir una ciudad; una ciudad explícita no usa GPS. macOS pide cada permiso al primer uso correspondiente.

### Firma de código (opcional pero recomendado)

macOS identifica cada app por su firma. Con firma **ad-hoc** (por defecto), cada `make install` genera una firma distinta y macOS te vuelve a pedir los permisos. Para que **los permisos se conserven entre recompilaciones**, crea tu propio certificado — una sola vez:

```bash
./scripts/crear-certificado.sh
```

Genera un certificado personal `BtoDicta Self Signed` en **tu** llavero. El `make install` lo detecta y firma con él automáticamente (si no existe, cae a ad-hoc sin fallar).

**¿Por qué no viene un certificado en el repo?** Porque un certificado de firma es una **identidad personal**, como tu firma o la llave de tu casa: compartir su clave privada dejaría que cualquiera suplante tu app. Por eso cada quien crea el suyo y la clave privada nunca sale de tu Mac. No es un secreto tan crítico como una API key, pero la buena práctica es que sea tuyo e intransferible.

## Configuración

Todo vive en `~/.btodicta/` (editable desde el menú 🎙):

| Archivo | Qué es |
|---|---|
| `config.json` | tecla, modelo, silencio_max_seg, sonidos, esc_cancela, atenuar_multimedia, silenciar_ademas, post_proceso, prompt_pulido, panel_visible, modo_desarrollo… |
| `keyterms.txt` | Tu vocabulario, una palabra por línea (streaming usa las primeras 50) |
| `reemplazos.json` | `[{"original": "variante1, variante2", "replacement": "Palabra"}]` |
| `historial/` | Tus dictados: `.wav` + `.txt` por año/mes/día |
| `uso.jsonl` | El odómetro |
| `agente_memoria.json` | Memoria conversacional corta y local del asistente |
| `agente_rutinas.json` | Recetas incluidas, personalizaciones y rutinas del usuario |
| `atajos_apple.json` | Atajos descubiertos, habilitación individual y nivel de riesgo |
| `logs/agente.jsonl` | Decisiones y resultados auditables del asistente |

Modelos: `scribe_v2_realtime` (texto en vivo) · `scribe_v2` · `scribe_v1` (por lotes, más barato).

## Entorno de desarrollo

- **macOS 14+** en Apple Silicon · **Xcode 26+** (Swift 6) · sin dependencias externas: Swift puro + AppKit/AVFoundation
- `make install` compila (Swift Package Manager) y arma el bundle firmado con certificado propio en /Applications
- **QA reproducible**: `scripts/qa-paquete.sh --automatico` ejecuta pruebas locales seguras sin abrir apps ni enviar nada. Las matrices, 30 casos manuales de camino feliz, 50 casos de estrés y la hoja de resultados están en [`qa/0.47.0/`](qa/0.47.0/README.md). `--audio` y `--ia` son pruebas opcionales que pueden consumir los proveedores configurados.
- Código modular en `Sources/BtoDicta/` (Config, Recorder, HistoryWriter, MediaControl, clientes Scribe, panel, AppDelegate…)
- Los usuarios normales NO tocan archivos: el asistente de configuración (y Ajustes → Modelos) guarda las claves y ajustes solos en `~/.btodicta/`. Los `*.example` (`.env.example`, `config.example.json`, `keyterms.example.txt`, `reemplazos.example.json`) son solo **referencia del formato** para desarrolladores o para pre-cargar valores a mano — opcionales
- Este entorno se actualiza con el proyecto: si algo no compila en una versión nueva de Xcode, abre un issue

## Privacidad y seguridad de datos

- **Tu voz solo viaja al motor que TÚ elijas** (cifrada: HTTPS/WSS) — o a **ningún lado** si usas un motor local (Whisper/Voxtral/Nemotron/Canary, 100% offline). No hay analítica, ni telemetría, ni terceros ocultos
- **Tu API key jamás se escribe en logs** ni en el código — vive en tu `~/.btodicta/.env` (bloqueado por `.gitignore`)
- **Tus dictados nunca salen de tu Mac**: `historial/` y `uso.jsonl` son archivos locales tuyos; la carpeta `~/.btodicta` queda en `700` y los archivos con secretos (`.env`, gateways) en `600`
- **Actualizaciones verificadas por firma**: desde 0.43, cada DMG lleva una firma **Ed25519 separada** y BtoDicta contiene solo la clave pública para comprobarla; además exige el mismo bundle id y certificado de la app. Un DMG alterado, una firma ausente o una app distinta se rechazan. Las claves privadas de release nunca salen del Mac del autor
- **Gateways propios**: la API key no se envía si el gateway usa `http://` sin cifrar
- El portapapeles se restaura tras cada pegado — lo que tenías copiado no se pierde
- Cada release pasa por **revisión de código y de seguridad** antes de publicarse

## Hoja de ruta

Lo que sigue (pendiente e ideas — ¿te falta algo? [abre un issue](https://github.com/btoaldas/BtoDicta/issues/new)):

- [ ] **Google Cloud Speech (Chirp)** — español LATAM tope de gama (requiere autenticación con cuenta de servicio GCP)
- [ ] **Azure AI Speech EN VIVO** — hoy va por lotes; su tiempo real es por SDK
- [ ] Afinar el streaming en vivo de cada motor de nube (Deepgram, AssemblyAI, Gladia…) con pruebas reales de punta a punta
- [ ] **Traducción en vivo** mientras dictas
- [ ] Más idiomas y mejor multilingüe según lo que pidan
- [ ] Dictado por comandos de voz (puntuación y formato hablados)

## Créditos

Creado por **Alberto Aldás** ([@btoaldas](https://github.com/btoaldas)) en compañía de **Claude** (Anthropic) — programado a pura voz, dictándole a las mismas herramientas que lo inspiraron. Inspirado en el gran corazón open source de [Handy](https://github.com/cjpais/Handy) de **@cjpais**.

**Motores y librerías de código abierto:**
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) y [llama.cpp](https://github.com/ggml-org/llama.cpp) (ggml-org) — Whisper y Voxtral locales
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) — streaming local en vivo (Voxtral Realtime / Nemotron)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) de Jonas van den Berg (BSD-3-Clause) — pausa de multimedia
- [Ollama](https://ollama.com) y [LM Studio](https://lmstudio.ai) — IA local (chat, embeddings, whisper)

**Datos y fuentes:** [LiteLLM](https://github.com/BerriAI/litellm) (precios de modelos que se actualizan solos) · [Open-Meteo](https://open-meteo.com/) y [GeoNames](https://www.geonames.org/) (geocodificación y pronóstico meteorológico) · modelos ASR: Whisper de OpenAI ([ggml de ggerganov](https://huggingface.co/ggerganov/whisper.cpp)), Voxtral de Mistral ([GGUF de ggml-org](https://huggingface.co/ggml-org/Voxtral-Mini-3B-2507-GGUF)), Nemotron y Canary de NVIDIA ([GGUF de handy-computer](https://huggingface.co/handy-computer)) · [bge-m3](https://huggingface.co/BAAI/bge-m3) (BAAI, búsqueda semántica).

**Servicios de IA que puedes conectar** (opcionales, muchos con capa gratis) — transcripción: ElevenLabs, Groq, OpenAI, Mistral, Fireworks, Hugging Face, Deepgram, AssemblyAI, Gladia, Speechmatics, Cloudflare, Soniox, Azure · pulido/traducción: OpenRouter, Anthropic, Google Gemini, DeepSeek, xAI, **Moonshot AI/Kimi**, **Kimi Code por cuenta**, Cerebras, GitHub Models, NVIDIA, Together, Novita, Z.ai, SiliconFlow. Cada uno con su enlace y botón "Conseguir clave" dentro de la app (Créditos y Modelos).

## Licencia

[GPL-3.0](LICENSE) — libre para siempre: cualquiera puede usarlo, estudiarlo y mejorarlo, pero nadie puede convertirlo en un producto cerrado. Las mejoras se quedan en la comunidad.
