import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El paquete lee su versión del
// Info.plist, que NO se inyecta desde aquí: hay que subir las dos a la vez
// (`CFBundleShortVersionString` y `CFBundleVersion`). `scripts/release.sh`
// compara ambas y no publica si difieren.

enum Version {
    static let numero = "0.66.1"
    static let fecha = "2026-09-14"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
        ("0.66.1", "2026-09-19", [
            "LOS MODELOS SE COMPRUEBAN UNO A UNO, NO SOLO POR SU FORMA. Desde 0.65.3 se miraba que lo descargado fuera un modelo de verdad y no una página de error. Ahora se comprueba además que sea EXACTAMENTE el modelo esperado: cada uno del catálogo lleva su huella fijada, y si lo que llega no coincide no se instala, aunque venga del sitio de siempre y parezca correcto",
            "Las huellas no salen de dar por bueno lo que ya había: se tomaron de lo que publica Hugging Face para cada archivo y se contrastaron con los modelos instalados en esta máquina. Los cuatro coincidían",
            "Un modelo que NO está en el catálogo se sigue instalando igual: puedes bajar el que quieras y no es asunto de la aplicación impedirlo. Lo que no puede pasar es que uno del catálogo llegue cambiado",
            "Los que ya tenías se revisan también, una vez al arrancar y sin estorbar. Solo avisa: que un modelo cambie puede ser normal si su repositorio lo actualizó, y esa decisión es de quien lo publica",
        ]),
        ("0.66.0", "2026-09-19", [
            "MOTORES LOCALES AL DÍA. whisper.cpp pasa de la 1.9.1 a la 1.9.4 —449 cambios, 81 de ellos arreglos— y el motor de embeddings se pone al día con casi mil cambios acumulados desde julio. Actualizar esto tiene su riesgo, porque una versión nueva puede cambiar lo que transcribe, así que se comprobó ANTES de instalar nada: el mismo audio da el texto IDÉNTICO letra por letra, incluido uno con siglas y nombres propios, que es donde más se notaría",
            "OTROS PROGRAMAS DE TU MAC YA PUEDEN TRANSCRIBIR DE VERDAD. La puerta local está encendida y el comando `transcribir` de la Mac la usa: antes alcanzaba las carpetas internas de BtoDicta, y se habría roto el día que algo cambiara de sitio. Ahora habla por un contrato, y si BtoDicta está cerrada sigue funcionando como siempre en vez de fallar",
            "Las carpetas desde las que la puerta local acepta audios se SUMAN a las de siempre, en vez de reemplazarlas. Antes había que acordarse de repetir las tres de fábrica al añadir una, y era fácil acabar abriendo de más. Y ahora se rechazan las carpetas demasiado amplias aunque se pongan a mano: abrir la carpeta personal entera convertiría esto en un lector de todo tu disco",
        ]),
        ("0.65.4", "2026-09-19", [
            "DEJA DE GASTAR LLAMADAS CONTRA CUENTAS VACÍAS. Cuando un proveedor se quedaba sin saldo, se apartaba media hora — el mismo tiempo que si la clave estuviera mal. Pero el saldo no vuelve solo en media hora, así que cada treinta minutos se gastaba otra llamada para recibir exactamente el mismo error. En un solo día se contaron 57",
            "Ahora el tiempo depende de si el problema se arregla solo: seis horas cuando falta saldo o cuota, media hora cuando es la clave —que puedes cambiar en cualquier momento—, cinco minutos cuando solo hay prisa, y dos cuando el servidor del proveedor está caído",
        ]),
        ("0.65.3", "2026-09-19", [
            "LO QUE SE DESCARGA SE COMPRUEBA ANTES DE INSTALARSE. Al bajar un modelo se guardaba lo que llegara, sin mirar nada. Si el servidor devolvía un error, un aviso de mantenimiento o una pantalla de inicio de sesión, eso quedaba guardado CON EL NOMBRE DEL MODELO, y el fallo aparecía días después al usarlo, con un mensaje sobre un formato inválido que no llevaba a ninguna parte",
            "Ahora se mira la respuesta del servidor, el tamaño y el contenido: si no es un modelo de verdad no se instala nada y el registro dice qué llegó. De cada modelo instalado se anota su huella, para poder ver si cambia después sin que nadie lo haya tocado",
            "Y una versión ya no puede publicarse sin los motores que funcionan sin internet. Viajan dentro de la aplicación copiados desde las carpetas de compilación, y si un día esas carpetas no estaban, el paquete salía sin ellos EN SILENCIO: la aplicación parecía normal hasta que alguien intentaba dictar sin conexión. Ahora se comprueba antes de firmar",
            "Tercera y última revisión completa, esta de lo que la aplicación no escribió pero sí ejecuta: los motores que lleva dentro y los modelos que se baja",
        ]),
        ("0.65.2", "2026-09-19", [
            "UN DICTADO QUE NO SE PUEDE GUARDAR YA NO PARECE GUARDADO. Si el archivo donde se escribe el audio no se podía abrir —disco lleno, permisos, un disco externo que se desconecta—, la aplicación seguía como si nada: el contador de bytes subía igual y todo parecía normal. Podías dictar media hora contra el vacío y enterarte al ir a buscarlo",
            "Ahora se dice en el registro con todas las letras, el contador solo sube cuando la escritura ocurrió de verdad, y si el disco se llena A MITAD del dictado también avisa —una vez, no cuarenta veces por minuto—",
            "Segunda revisión completa de la aplicación, esta preguntando «cuando algo falla, ¿se entera alguien?». Cinco áreas, un fallo. Las otras cuatro estaban bien",
        ]),
        ("0.65.1", "2026-09-19", [
            "ARREGLADO UN AGUJERO DE SEGURIDAD REAL. La voz local construye un comando del sistema con el texto dentro para hablar. Ese texto se protegía a medias, y bastaba que contuviera cierta forma de escritura para que el sistema EJECUTARA lo que hubiera ahí. Suena rebuscado hasta que se ve la cadena entera: la bitácora lee lo que hay en tu pantalla —correos, páginas ajenas—, la IA redacta con ello, y la voz lo pronuncia. Alguien solo tenía que escribir la frase adecuada en una web que estuvieras mirando",
            "Ahora el texto se neutraliza antes de llegar al sistema. La comprobación no se conforma con revisar el código: EJECUTA de verdad un texto preparado para crear un archivo y comprueba que no aparece",
            "La puerta local para otros programas tiene ahora un tope de peticiones por minuto, ajustable. Sin él, un programa tuyo con un bucle mal escrito podía vaciarte el saldo de las nubes en minutos, y el aviso de saldo bajo llega después",
            "Primera revisión de seguridad completa de la aplicación: nueve áreas. Las otras siete estaban bien — ninguna clave aparece en el registro, los archivos con credenciales solo los puede leer su dueño, nadie desactiva la verificación de certificados, la actualización comprueba su firma antes de instalarse, y lo que la IA decide se descarta si no está en el catálogo real",
        ]),
        ("0.65.0", "2026-09-19", [
            "OTROS PROGRAMAS DE TU MAC PUEDEN TRANSCRIBIR CON BtoDicta. Hasta ahora, cualquier proyecto tuyo que necesitara convertir audio en texto tenía que instalar sus propios modelos de varios gigabytes o contratar otro servicio. Ahora te lo pide a ti: le mandas la ruta de un audio y te devuelve el texto, usando los mismos motores, la misma cascada y el mismo vocabulario que tu dictado. También puede pedirte pulir un texto",
            "Se enciende en Configuración → Ajustes, y VIENE CERRADA. Al abrirla aparece un token: trátalo como una contraseña, porque quien lo tenga puede transcribir con tus motores y gastar tu saldo",
            "Lo que NO puede hacer, por diseño: atender desde otro equipo —escucha solo en tu propia máquina—, leer cualquier archivo del disco —solo audios de Descargas, Documentos y la carpeta temporal— ni entrar sin token, ni con uno antiguo si lo cambias",
            "Puedes elegir motor en cada petición: «local» para que no salga nada de tu equipo, «nube», o que decida la cascada. Y pasarle tus siglas para esa petición concreta, sin tocar tu glosario",
        ]),
        ("0.64.3", "2026-09-19", [
            "EL REGISTRO YA TE DICE QUÉ HACER, no un número. Cuando un proveedor se aparta, en vez de «en cuarentena 30 min por HTTP 402» leerás «se quedó sin saldo o sin cuota», «no acepta la clave (¿caducó o se copió mal?)» o «demasiadas peticiones seguidas». El código sigue apareciendo detrás, para diagnosticar",
            "Dos resúmenes generados en el mismo segundo ya no comparten archivo. El nombre escalaba a la hora y al segundo, pero dos rutinas que caen a la vez —o una manual justo encima de una automática— todavía se pisaban",
            "Con esto se cierran los veinticuatro pendientes que venían arrastrándose desde versiones anteriores. Otros cuatro resultaron ser cosas que el código ya había arreglado por el camino, y se comprobó uno a uno en vez de darlos por buenos",
        ]),
        ("0.64.2", "2026-09-19", [
            "Los resúmenes del día ya no se quedan cortos sin explicación. Si una rutina se disparaba mientras la bitácora estaba transcribiendo, generaba su documento igual, con el día a medio procesar. Ahora espera unos minutos y lo hace con el material completo",
            "Y ya no congelan la aplicación mientras se preparan: armar el material de un día entero —que puede pasar de doscientos mil caracteres— se hacía en el mismo hilo que dibuja la ventana",
            "Limpieza de restos que nadie alcanzaba: los trocitos de audio de menos de medio segundo no se pueden transcribir, así que no entraban al índice; y como la limpieza solo borra lo indexado, se quedaban en disco para siempre",
            "El trozo que se está grabando en este momento ya no entra al índice a medio escribir, con una duración que todavía no es la suya",
            "Arrastrar un deslizador de los ajustes de la bitácora reiniciaba el planificador en cada paso del arrastre. Ahora espera a que sueltes",
        ]),
        ("0.64.1", "2026-09-19", [
            "SE ACABARON LOS ARCHIVOS HUÉRFANOS AL CERRAR. Al salir, la bitácora encolaba el cierre del trozo que estaba grabando y volvía al instante, así que el proceso moría antes de que llegara a cerrarlo: uno huérfano por cada cierre, treinta y ocho en dos semanas. El rescate del arranque los recuperaba, pero recuperar es peor que no romper. Medido después: cero, en dos ciclos completos de cerrar y abrir",
            "EL AUDIO DEL SISTEMA VUELVE SOLO. Un error del flujo lo dejaba muerto hasta que alguien tocara los ajustes, y nada te avisaba de que había dejado de grabar. Lo que lo tumba suele ser pasajero —cambiar de salida de audio, una pantalla que se desconecta—, así que ahora reintenta con espera creciente hasta cinco veces",
            "La pestaña de la bitácora va más ligera: pedía los documentos y las transcripciones por separado, y cada petición recorría el árbol ENTERO. Con meses de historial son decenas de miles de archivos recorridos dos veces en cada refresco. Ahora es un solo recorrido",
            "La retención que fijaste vuelve a aplicarse sola cada pocas horas. Solo se revisaba al arrancar, y esta aplicación se deja abierta días: una sesión larga seguía guardando material que ya debería haberse ido",
            "Y la limpieza dejó de mentir: si un archivo no se puede borrar —permisos, disco lleno, un disco externo desconectado— su ficha se queda en el índice en vez de desaparecer. Antes el archivo seguía en disco sin que nada supiera que existía, y la retención parecía cumplida sin estarlo",
            "Un pulido que volvía correcto pero vacío ya no se pierde: los modelos que razonan devuelven a veces el texto en otro campo, y se contaba como fallo con un código de éxito al lado",
        ]),
        ("0.64.0", "2026-09-19", [
            "LA BITÁCORA YA NO FOTOGRAFÍA TU GESTOR DE CONTRASEÑAS. Podía excluir aplicaciones desde el primer día, pero la lista venía vacía: si no la rellenabas a mano, no protegía nada. Ahora trae de fábrica 1Password, Bitwarden, KeePassXC, Dashlane, Proton Pass, el llavero del sistema y Contraseñas de Apple, entre otros. Sus ventanas no aparecen siquiera en la imagen",
            "Y una segunda defensa para lo que no se puede excluir por aplicación: una pestaña del banco en el navegador. Puedes indicar palabras que, si salen en el TÍTULO de la ventana, impiden guardar esa captura. Viene vacía a propósito, porque una palabra demasiado común te dejaría sin bitácora media jornada",
            "LO QUE SE LEE EN TU PANTALLA YA NO PUEDE DARLE ÓRDENES A LA IA. El resumen del día se arma con texto leído de correos, páginas y documentos ajenos, y cualquiera puede traer una frase del tipo «ignora las instrucciones anteriores». Ese material viaja ahora dentro de una valla impredecible, distinta en cada llamada, con una regla que manda sobre todo lo demás: lo de ahí dentro se lee, se menciona si viene al caso, y no se obedece",
            "El texto de lo que dictas se guarda en el registro, y ahora puedes apagarlo. Sigue encendido de fábrica porque ese registro es local, se borra solo cada semana y es lo único que permite ver después que un pulido te recortó el dictado. Apagado, las líneas siguen ahí con la medida en vez del contenido",
        ]),
        ("0.63.7", "2026-09-19", [
            "EL AUDIO DEJA DE COPIARSE EN TODO EL RECORRIDO. Al guardar un dictado, el historial recibía los bytes y volvía a escribir el mismo archivo que el grabador acababa de crear. Ahora lo ADOPTA moviéndolo, que es un renombrado: cuesta igual con diez segundos que con seis horas y no pasa un byte por memoria. De paso, el audio de trabajo deja de acumularse, porque deja de existir donde estaba en cuanto pasa al historial",
            "Los motores que corren en tu Mac también dejan de copiarlo: necesitan un archivo y se lo damos con un enlace, no con una copia. En un dictado de seis horas eran 1,3 GB de trabajo para nada",
            "ARREGLADO UN FALLO QUE PODÍA PERDER UN DICTADO. El nombre de cada dictado es la hora al segundo, así que dos dictados en el mismo segundo compartían archivo y el segundo pisaba al primero. Ahora cada uno va al suyo",
            "Pedir el cierre de la conexión sobre la sesión que comparte la aplicación deja un socket muerto que la petición siguiente hereda, y se queda esperando hasta agotar su plazo. Se corrigió en los motores de transcripción en 0.59.0 y había vuelto en TRECE sitios: la voz, el resumen del día, el ruteo de modos, transcribir un archivo del historial. Retirado en todos, y ahora hay una comprobación automática que lo vigila en cada versión, para que no vuelva una tercera vez",
        ]),
        ("0.63.6", "2026-09-19", [
            "Cierre de la mejora de memoria: las pruebas internas dicen ahora también CUÁNTO TARDAN, no solo si pasan. Leer un tramo de 25 MB del medio de un dictado de seis horas: 2,9 milésimas de segundo. Armar el paquete del envío, comparado por los dos caminos: para una hora de audio, 7 ms en memoria contra 54 ms en disco",
            "Ese dato se publica tal cual porque también dice lo que empeora: escribir a disco es más lento en términos relativos. En absoluto son milésimas frente a los segundos que tarda cualquier transcripción, y a cambio se ahorran 115 MB de memoria por hora de audio. En un dictado corto la diferencia es de una milésima",
        ]),
        ("0.63.5", "2026-09-19", [
            "LOS DOCE MOTORES SUBEN EL AUDIO DESDE EL DISCO. Antes, enviar un dictado armaba en memoria un paquete que contenía el audio entero: sumado a la copia que ya existía, un dictado de seis horas necesitaba cerca de dos gigas en el momento del envío. Ahora ese paquete se escribe a disco copiando el audio por trozos pequeños y se transmite desde ahí. Medido con seis horas: preparar el envío cuesta 0 MB",
            "Con esto, un dictado de seis horas ocupa 80 MB de principio a fin —grabar 13, terminar 3, enviar 0— frente a los cerca de 2 000 MB de antes. El audio viaja como una ruta de archivo desde que sueltas la tecla hasta el motor; solo se lee entero para guardarlo en el historial, y ya con la transcripción hecha",
            "Arreglado de paso el envío por lotes de ElevenLabs, que se había quedado fuera de la corrección de 0.59.0: seguía pidiendo el cierre de la conexión, así que el dictado siguiente heredaba un socket muerto y esperaba en balde hasta agotar su plazo",
            "Antes de tocar ningún motor se comprobó que el paquete nuevo es EXACTAMENTE el de antes, byte a byte, con audios de un segundo, un minuto y una hora. Esa comprobación queda como prueba permanente: BTODICTA_SUBIDATEST=1",
        ]),
        ("0.63.4", "2026-09-18", [
            "EL DICTADO DEJA DE VIVIR EN LA MEMORIA. El grabador retenía en RAM todo lo hablado, y al soltar la tecla armaba encima una segunda copia completa para enviarla. Medido en un dictado de seis horas: 1 388 MB. Ahora el audio se escribe al archivo según entra y en memoria solo queda una ventana de tres minutos —lo máximo que la vista previa en vivo puede pedir—, así que soltar la tecla ya no copia nada: devuelve la ruta del archivo que ya estaba escrito. Misma prueba: 80 MB",
            "Lo curioso es que la aplicación creía tener esto resuelto desde 0.60.0, y la medición que lo decía era correcta pero medía otro componente: probaba el escritor de la bitácora, que sí escribe sin acumular, y nunca pasaba por el grabador del dictado. La prueba ahora recorre el camino real, que es de lo que sirve una prueba",
            "El audio de trabajo de cada dictado se conserva los días que tú fijes —siete de fábrica, 0 para no borrar nunca— en Configuración → Ajustes → Audio de trabajo. Ronda los 115 MB por hora dictada. Es la copia de trabajo del grabador: el audio del historial se guarda aparte y no se toca",
            "REABRIR LA APLICACIÓN YA NO VUELVE A MANDAR EL RESUMEN POR CORREO. El registro de qué se había enviado y qué día vivía solo en memoria, de modo que cada arranque posterior a la hora fijada creía que no había mandado nada y mandaba otra vez. Una tarde de reinicios produjo diecisiete correos al mismo destinatario cuando tocaban dos. Ahora se guarda en disco, y si un envío falla se reintenta en la vuelta siguiente en vez de perder el día",
            "La bitácora vuelve a decir en el registro cuándo empieza a escuchar. El contador no se reiniciaba, así que ese aviso solo salía la primera vez de la sesión y las recuperaciones tras cederle el micrófono al dictado quedaban mudas: parecía rota una bitácora que estaba grabando bien",
            "Por dentro, el cuerpo de cada envío a los motores se arma en disco en vez de en memoria, copiando el audio por ventanas. Comprobado byte a byte contra el camino anterior con audios de un segundo, un minuto y una hora antes de cambiar ningún motor",
        ]),
        ("0.63.3", "2026-09-18", [
            "El fallo corregido en 0.63.2 —«el micrófono no aceptó la escucha»— estaba también en la BITÁCORA y en la activación por voz, con el mismo patrón línea por línea. En la bitácora era peor que en el grabador, porque ahí nadie está mirando: si la escucha no entraba, dejaba de grabar EN SILENCIO y no había ninguna señal hasta buscar audio que no existía",
            "Los dos pasan a resolver el formato en el momento de instalar la escucha y a armar el conversor con el primer audio real, rearmándolo si el micrófono cambia de frecuencia a mitad de la grabación",
            "En la bitácora, el mapa de canales viaja ahora con el conversor. Importa: con la cancelación de eco activa el micrófono llega con NUEVE canales, y sin ese mapa la conversión a mono devuelve cero marcos y el audio se pierde sin avisar",
            "Comprobado con la bitácora encendida cediendo el micrófono a un grabador real mientras suena voz por los parlantes: 182 208 bytes capturados con nivel máximo. Y en la aplicación real, dos arranques seguidos de la bitácora, los dos con audio",
        ]),
        ("0.63.2", "2026-09-18", [
            "ARREGLADO el fallo que obligaba a cerrar y volver a abrir la aplicación: «el micrófono no aceptó la escucha». Ocurría al pulsar la tecla justo cuando la bitácora acababa de soltar el micrófono. La aplicación leía el formato del aparato inmediatamente después de fijarlo, y macOS todavía no había terminado de conmutar, así que devolvía el del aparato ANTERIOR —44 100 Hz cuando ya estaba en 48 000, o al revés—. Ese formato es válido, de modo que pasaba la comprobación añadida en 0.54.1, y la escucha se rechazaba con «format mismatch»: el dictado no arrancaba y no había forma de seguir sin reiniciar",
            "Ahora no se le pasa ningún formato: lo resuelve el propio motor de audio en el instante de instalar la escucha, así que la discrepancia no puede existir. El conversor se arma con el formato del primer trozo de audio REAL y se rearma solo si el micrófono cambia de frecuencia a mitad de la grabación",
            "Y si aun así algo falla, se reintenta hasta tres veces con un respiro entre ellas en vez de rendirse al primer intento. En el registro se veía que el mismo micrófono que rechazaba la escucha entregaba audio sin problema segundos después",
            "Prueba propia del caso exacto —soltar y volver a tomar el micrófono sin pausa, con la bitácora disputándolo—: BTODICTA_MICRELEVO=10",
        ]),
        ("0.63.1", "2026-09-15", [
            "NUEVO PROVEEDOR DE IA: OpenCode Go, la suscripción mensual con decenas de modelos abiertos incluidos —DeepSeek, GLM, Qwen, Kimi, MiniMax, Grok—. Sirve para pulir, para los modos y para el agente. NO transcribe ni habla, solo expone modelos de texto, así que no aparece entre los motores de dictado",
            "Ojo con la trampa: la misma clave vale para dos extremos distintos. El de pago por uso (Zen) y el del plan (Go) son URL diferentes, así que es fácil llamar al equivocado y concluir que no hay saldo cuando el plan está activo. Y el de Go exige una cabecera de sesión o rechaza la petición",
            "La prueba de vida de OpenCode no usa su listado de modelos: se le pregunta por el camino que de verdad se usa, pidiendo un solo token de respuesta. Medido al elegir el modelo por defecto: deepseek-v4.1-flash pule en 2,8 s frente a los 17-20 s de las alternativas, y el coste que devuelve la respuesta es cero porque lo cubre el plan",
        ]),
        ("0.63.0", "2026-09-15", [
            "PANEL DE SALUD: una sección nueva en Configuración con el estado real de todo, sin abrir el registro. Saldo de los proveedores que lo publican, prueba de vida de TODOS los que tengas configurados —veintitrés en una instalación normal, entre IA, dictado y voz—, quién está apartado ahora mismo y por qué, los techos de tamaño que la aplicación ha aprendido de cada motor, y la cola de la bitácora",
            "AVISO DE SALDO BAJO: hasta ahora uno se enteraba de que se acabó cuando un dictado fallaba a mitad. Se avisa al bajar del 15 % o de 5 dólares, una vez al día por proveedor, sin interrumpir nada. Los umbrales se ajustan con «saldo_aviso_fraccion» y «saldo_aviso_minimo_usd»",
            "SEIS proveedores dan saldo de verdad, cada uno en su unidad: ElevenLabs en caracteres, Fish Audio, DeepSeek, OpenRouter y Novita en dinero, y Speechmatics en horas consumidas. La lista salió de PROBARLOS uno por uno con claves reales, no de la documentación: Deepgram y Anthropic sí tienen consulta de saldo pero exigen clave de administrador, así que con una clave normal es como si no existiera",
            "De los demás no se inventa una estimación —no cuadraría con la factura—: se prueba si responden y se LEE lo que contestan. Ahí aparecen cosas que de otro modo no se saben, como una cuenta suspendida por impago o por llegar al tope de gasto del mes; el panel lo dice con esas palabras en vez de con un código HTTP",
            "Prueba propia: BTODICTA_SALUDTEST=1",
        ]),
        ("0.62.1", "2026-09-14", [
            "ARREGLADO de raíz que el pulido se volviera lento cuando un proveedor de IA deja de contestar. La aplicación ya apartaba al que fallaba, pero a una espera agotada le daba solo QUINCE SEGUNDOS: al dictado siguiente, un minuto después, volvía a llamarlo y se comía su plazo entero otra vez. Ahora el castigo sube con los fallos seguidos —un minuto, cinco, un cuarto de hora— y se perdona entero en cuanto el proveedor vuelve a contestar. Un mal momento se disculpa; una caída de horas no se paga en cada dictado",
            "ARREGLADO que un dictado largo pudiera entregarse recortado. La comprobación de integridad exigía que el resultado bajara de 32 caracteres para sospechar, así que un dictado de cinco mil devuelto con ochocientos pasaba como bueno. Ahora se rechaza cualquier pulido que pierda más de la mitad de las letras y se entrega el original. Vale para cualquier proveedor y modelo, sin tener que saber cuál razona ni cuánto gasta pensando antes de escribir",
            "Prueba propia: BTODICTA_PULIDOTEST=1 (16 comprobaciones)",
        ]),
        ("0.62.0", "2026-09-14", [
            "El pulido apartaba ya a los proveedores caídos; lo que fallaba era el plazo con que lo hacía. Corregido en 0.62.1",
            "LOS ENVÍOS DE CORREO SON AHORA UNA LISTA, no un horario con un periodo común. Cada línea es un envío independiente con su hora, su periodo y sus días: el resumen de ayer a las 07:00 todos los días, el de hoy a las 20:00, y el de la semana los sábados por la mañana. Se añaden y se quitan desde Configuración, y lo que ya tuvieras configurado se convierte solo",
            "Prueba propia de la cuarentena del pulido: BTODICTA_PULIDOTEST=1",
        ]),
        ("0.61.0", "2026-09-14", [
            "LA BITÁCORA DEL DÍA, EN TU CORREO. BtoDicta junta lo transcrito del periodo que elijas, lo consolida con tu propia IA en UN SOLO texto —sin repetir la misma idea porque se dijo tres veces— y te lo manda. En Configuración → Ajustes pones tu servidor, tu usuario y a quién quieres que llegue: el correo sale de TU cuenta, no de ninguna infraestructura del proyecto",
            "El botón «Probar envío» no dice solo si funcionó: cuando falla dice POR QUÉ y qué mirar. Clave equivocada, puerto cerrado, destinatario inválido y servidor caído dan mensajes distintos, cada uno con su consejo — con Gmail, por ejemplo, avisa de que hace falta una «contraseña de aplicación»",
            "Envío automático a la hora o las horas que fijes, cada una con su periodo (el día de hoy, el anterior o la semana). Si el equipo estaba dormido, sale al despertar en vez de perderse ese día. Y cuando quieras, a mano desde el menú de la barra",
            "Cada intento queda en el registro con su causa, y el diálogo completo con el servidor se puede ver con BTODICTA_SMTPDEBUG=1 sin que la clave aparezca nunca",
            "Prueba propia: BTODICTA_CORREOTEST=1 — envía de verdad y comprueba que cada tipo de fallo se identifica por separado",
        ]),
        ("0.60.0", "2026-09-14", [
            "EL DICTADO DEJA DE VIVIR EN LA MEMORIA. El audio se guardaba por partida doble en RAM —en el grabador y en una copia aparte— además del archivo en disco que ya se escribía mientras hablas. A 32 000 bytes por segundo eso son 691 MB por copia en un dictado de seis horas. Ahora el archivo es la única fuente: quien necesita un tramo lo lee de ahí. Medido con seis horas simuladas, la memoria subió 0 MB",
            "El grabador suelta el audio en cuanto entrega el .wav, en vez de conservarlo hasta el dictado siguiente: durante toda la transcripción convivían dos copias completas para nada",
            "La vista previa en vivo con motor local copiaba el dictado ENTERO cada 1,6 segundos para transcribir un adelanto. Ahora toma solo los últimos dos minutos, que es lo único que esa vista necesita",
            "Prueba propia que mide la memoria de verdad: BTODICTA_MEMTEST=6",
            "PENDIENTE de la segunda etapa: al mandar el audio a transcribir sigue haciéndose una copia, porque los motores reciben los datos y no el archivo. Eso limita el dictado muy largo hasta que la entrega sea también desde disco",
        ]),
        ("0.59.3", "2026-09-14", [
            "ARREGLADO: el aviso de «Esc otra vez para cancelar» cerraba el notch. Seguías grabando pero perdías de vista el texto en vivo, el cronómetro y las barras de voz, que es justo lo que hace falta para decidir si cancelar o no. Ahora el aviso sale sin esconder nada y, al pasar, el notch recupera lo que decía",
            "Los ajustes de cancelación ya están en Configuración → Ajustes, justo debajo de «Cancelar con Esc»: pedir dos pulsaciones, confirmar también al tocar el notch, y desde cuántos segundos se guarda lo cancelado. Antes solo existían en el archivo de configuración",
        ]),
        ("0.59.2", "2026-09-14", [
            "UN ESCAPE SUELTO YA NO CANCELA EL DICTADO. Mientras grabas, esa tecla queda capturada en todo el sistema, de modo que pulsarla para cerrar una vista previa o una ventana cualquiera cortaba la grabación. Ahora hay que pulsarla DOS veces seguidas: la primera solo avisa en el notch («Esc otra vez para cancelar») y la segunda cancela. Se vuelve al comportamiento anterior con «esc_doble» en false, y la ventana para repetir se ajusta con «esc_doble_s»",
            "Nuevo ajuste «cancelar_confirma» (apagado por omisión): con él, cancelar tocando el notch también pide repetirse. Se confirma repitiendo la acción y no con un cuadro de diálogo, porque un modal a mitad de un dictado interrumpe más de lo que protege",
        ]),
        ("0.59.1", "2026-09-14", [
            "CANCELAR UN DICTADO YA NO LO BORRA. Hasta ahora, cancelar ejecutaba un borrado real del archivo de audio y del texto: no se abandonaba la grabación, se destruía. Y como la tecla Escape queda registrada como atajo GLOBAL mientras grabas, bastaba con pulsarla para cerrar una ventana de otra aplicación para perder el dictado entero. Ahora un dictado cancelado se cierra como cualquier otro —queda su .wav en el historial y en la bitácora, junto al texto que ya se hubiera transcrito— y se recupera desde donde se recuperan todos. Solo se descarta lo que dura menos de dos segundos, que es una pulsación accidental sin nada dentro; el umbral se ajusta con «cancelar_conserva_desde_s»",
            "Prueba propia: BTODICTA_CANCELTEST=1",
            "PENDIENTE, y conviene saberlo: Escape sigue siendo un atajo global, así que puede seguir interrumpiendo un dictado desde otra aplicación. Ya no se pierde nada cuando pasa, pero hay que volver a empezar",
        ]),
        ("0.59.0", "2026-09-14", [
            "SE ACABARON LOS DICTADOS QUE NO CABEN. Todo motor de transcripción tiene un techo de tamaño y ninguno lo anuncia igual: Fish rechaza a partir de unos 25 MB con un «format not recognised» que ni menciona el tamaño. Ahora, cuando un motor rechaza el envío entero de una forma que puede ser de tamaño, la aplicación parte el audio en tramos con solape y lo reintenta CON EL MISMO MOTOR, cosiendo después por coincidencia de palabras. Medido: 20 minutos de dictado que antes fallaban salen ahora completos, 3 348 palabras de las 3 360 habladas",
            "Y lo aprende: el techo de cada motor queda anotado, así que la próxima vez parte de entrada sin pagar el rechazo. Pero solo aprende de lo que dice el SERVIDOR — una caída de internet no deja ninguna medida, porque si no una desconexión de un minuto marcaría al motor con un techo falso durante semanas. Si más adelante entra algo más grande de lo que supuestamente no admitía, la medida se tira entera; y en cualquier caso caduca a las dos semanas",
            "Lo mismo con el pulido: si la IA devuelve la respuesta cortada por falta de contexto, se aprende su techo y a partir de entonces el texto se pule por tramos partidos POR FRASES, nunca a mitad de palabra. Un dictado de dos horas se pule entero en vez de quedarse en crudo",
            "ARREGLADO un cuelgue intermitente que afectaba a LOS DOCE motores de transcripción de nube: todos mandaban «Connection: close» sobre la conexión compartida, así que el servidor la cerraba al responder pero la aplicación se la quedaba igual, y el dictado siguiente escribía contra un socket muerto hasta agotar el plazo. Medido con ocho dictados de 40 segundos separados por 45: SEIS tardaban 18,7 segundos en vez de 1,8. Con la conexión que se renueva sola tras veinte segundos de reposo, los mismos ocho bajaron a 1,5-2,5 segundos y ninguno se colgó. Nunca se perdió texto —el reintento siempre rescataba—, pero costaba diecisiete segundos de espera",
            "Prueba propia del troceo, con 24 comprobaciones: BTODICTA_PARTIRTEST=1",
        ]),
        ("0.58.0", "2026-09-14", [
            "CRONÓMETRO DE GRABACIÓN en el notch: bajo las barras de voz aparece cuánto llevas grabando, en minutos y segundos. Al terminar, el aviso dice la duración del audio («Cerrando dictado · 3:00 grabados…», «Transcribiendo 3:00…»), medida del propio audio y no del reloj, así que una pausa no la falsea. Pasada la hora cambia a h:mm:ss",
            "BANCO DE PRUEBAS SINTÉTICO: la aplicación puede generar dictados con la voz que ya trae macOS y mandarlos por el camino real del motor de nube, a las duraciones que se le pidan y repetidos. Nació de un fallo que no se reproducía desde fuera y que obligaba a dictar a mano una y otra vez. Se usa con BTODICTA_STRESS=<segundos> y no cuesta síntesis, solo el audio transcrito",
            "Con ese banco quedó medido que la transcripción de Fish Audio tarda un 3-4 % de lo que dura el audio —tres minutos se transcriben en menos de seis segundos—, así que el aviso de lentitud pasa a medirse contra la duración del audio en vez de contra un número fijo que marcaba como lentos los dictados largos normales",
        ]),
        ("0.57.2", "2026-09-13", [
            "Fish Audio deja constancia de cuánto tarda cada transcripción y con cuántos kilobytes. Desde fuera de la aplicación esa API responde en menos de 3 segundos, pero algún dictado largo agota el plazo dentro de ella: sin la medición el diagnóstico es adivinanza, y ahora cada llamada lenta o fallida queda anotada con su tamaño y su tiempo",
            "El reintento ante un corte de conexión ya se comprobó en uso real: un dictado que habría cambiado de motor se resolvió con Fish Audio al segundo intento",
        ]),
        ("0.57.1", "2026-09-13", [
            "ARREGLADO un falso positivo que cambiaba de motor sin motivo: un dictado largo con Fish Audio agotaba un plazo de espera fijo de 60 s y el dictado se iba a otro motor teniendo el primero perfectamente sano — encima ya lo había transcrito y cobrado, así que se pagaba por un texto que no llegaba. El plazo es ahora proporcional al audio (15-30 s) y, si el corte fue de la conexión y no del servidor, se reintenta una vez antes de rendirse. Medido: 72 s de audio se transcriben en menos de 3 s",
            "VISTA PREVIA EN VIVO: cuando falta el modelo de dictado de macOS, la app lo descarga sola en segundo plano en vez de quedarse sin vista previa para siempre y sin decir por qué. Es lo que enseña que te está escuchando con los motores de nube que transcriben por lotes",
            "Fish Audio ahorra crédito solo: prueba primero su modelo de voz gratuito y solo cae al de pago si aquel falla (se desactiva con «fish_tts_ahorro»)",
            "El modelo de transcripción de Fish Audio se llama ahora por su nombre real, transcribe-1, en vez de una etiqueta genérica",
        ]),
        ("0.57.0", "2026-09-13", [
            "NUEVO PROVEEDOR: Fish Audio, y hace las dos cosas con una sola clave, como ElevenLabs — habla con tu voz clonada y transcribe. Aparece tanto en el catálogo de motores de transcripción como en el de voces de nube, y se configura igual que el resto con tu propia key (FISH_API_KEY)",
            "La voz se elige por el «reference_id» de tu clon en fish.audio, no por un nombre. Modelos de voz s2.1-pro, s2-pro, s1 y s2.1-pro-free; este último viene puesto por defecto porque habla sin gastar crédito",
            "En Fish Audio el crédito de API es una bolsa DISTINTA de la de la plataforma web y empieza en cero: la suscripción de la web no paga llamadas de API. Sin recargarlo, todo lo que no sea el modelo gratuito responde 402 — BtoDicta lo pone en cuarentena 30 minutos y sigue con el motor siguiente, sin que el dictado se entere",
            "Prueba propia reproducible de ida y vuelta (voz → audio → transcripción): BTODICTA_FISHTEST=1",
        ]),
        ("0.56.2", "2026-09-13", [
            "ARREGLADO: un dictado podía quedarse sin entregar para siempre. Cuando la recuperación de texto perdido arrancaba el motor por lotes y este se atascaba, nadie cortaba la espera: el texto no llegaba nunca y el panel se quedaba en «Recuperando lo que falta». Ahora la recuperación entrega SIEMPRE lo que tenga al cumplirse su tope, y el proceso atascado se detiene solo",
            "ARREGLADO: cada congelación del motor en vivo costaba minuto y medio de audio transcritos para nada. Se pedía la ventana de audio y después se descartaba el resultado por no saber en qué punto del texto coserlo. Ahora ese punto se anota en el momento en que el motor enmudece, así que la ventana se aprovecha y el tramo congelado a mitad del dictado sí se recupera",
            "ARREGLADO: las elisiones marcadas con el carácter «…» no se detectaban; solo las escritas con tres puntos. Según qué motor transcribiera, la mitad de los huecos quedaba invisible",
            "ARREGLADO: al pasar de BetoDicta a BtoDicta, el registro de la semana en curso se quedaba con el nombre anterior y no volvía a archivarse nunca — una semana entera desaparecía del diagnóstico. Ahora se une al nuevo, en orden y sin borrar nada: el original se conserva aparte",
            "Prueba propia reproducible de los cuatro arreglos: BTODICTA_REDTEST2=1",
        ]),
        ("0.56.1", "2026-09-13", [
            "ARREGLADO el asistente de mudanza, que no llegaba a instalar nada. Dos fallos encadenados: viajaba sin la clave con la que se comprueba la firma de las descargas (toda instalación moría con «firma del release no válida»), y preguntaba si había una versión «más nueva» cuando él viaja dentro del mismo paquete que la aplicación, así que la respuesta era siempre «ya estás al día». Ahora lleva la clave y pide directamente el último paquete publicado",
            "Probado de punta a punta: el asistente descarga, verifica la firma, instala la aplicación, la abre y se cierra solo",
            "El constructor del asistente y el publicador comprueban ahora que lleve la clave y el certificado; si faltaran, el paquete no se publica. Hay prueba propia: BTODICTA_PUENTETEST=1",
        ]),
        ("0.56.0", "2026-09-13", [
            "ASISTENTE DE MUDANZA para quien tenía BetoDicta: el paquete lleva ahora una segunda aplicación con el nombre y el identificador anteriores. La actualización automática de una instalación vieja la encuentra, la instala y abre un asistente que explica el cambio y hace la mudanza en un clic — antes esa actualización se cancelaba con un error de identidad y había que resolverlo a mano",
            "El asistente descarga BtoDicta, comprueba su firma, la instala y la abre; si algo falla, enseña los cuatro pasos para hacerlo a mano y un botón que lleva a la página de descargas",
            "El puente no toca ni un dato: solo instala. Las carpetas y las claves las muda BtoDicta al abrirse, como hasta ahora",
            "El publicador verifica en cada versión que el puente viaja firmado y con el identificador anterior: sin eso, quien venga de la versión vieja se quedaría sin camino",
        ]),
        ("0.55.1", "2026-09-13", [
            "ARREGLADO un efecto del cambio de nombre: al mudarse la carpeta de la bitácora, su índice seguía apuntando a la ruta anterior, daba por perdido todo el material y lo registraba otra vez como pendiente. En una instalación real quedaron 63 567 elementos marcados para reprocesar cuando ya estaban transcritos y leídos. Ahora las rutas del índice se corrigen en el mismo momento de la mudanza, antes de que nada lo abra: ni un segundo de trabajo repetido",
        ]),
        ("0.55.0", "2026-09-13", [
            "LA APP SE LLAMA AHORA BtoDicta. Cambia el nombre en todas partes: la aplicación, la barra de menús, el instalador, la documentación y el repositorio",
            "TUS DATOS SE MUDAN SOLOS: al abrir por primera vez, la carpeta de modelos, voces, historial y ajustes (~/.betodicta) y la de la bitácora pasan a llamarse como la app. Se MUEVEN, no se copian, así que es instantáneo aunque pesen decenas de gigas; si algo no se pudiera mover, se conserva donde está y se registra — nada se borra",
            "TUS CLAVES SIGUEN AHÍ: las credenciales guardadas en el Llavero se leen con el nombre anterior y se reescriben con el nuevo la primera vez que se usan. No hay que teclear ninguna otra vez",
            "OJO, PERMISOS: al ser una aplicación nueva para macOS, el sistema volverá a pedirte micrófono, accesibilidad y automatización la primera vez. Es normal y solo pasa una vez",
        ]),
        ("0.54.2", "2026-09-13", [
            "ARREGLADO el micrófono mudo: la app fijaba a la fuerza el aparato de entrada en el motor de audio y eso DEJA EL MICRÓFONO SIN ENTREGAR NADA. Medido en el mismo Mac: sin fijarlo, 24 buffers en 2,5 s; fijándolo, la llamada devuelve «correcto» y llegan CERO. Resultado: la bitácora reiniciándose en bucle y un dictado entero perdido sin un solo byte. Ahora solo se fija cuando de verdad hay que cambiar de aparato — si el sistema ya tiene el que quieres, no se toca nada",
            "FUNCIONA CON CUALQUIER EQUIPO: la frecuencia del micrófono la pone cada Mac (44 100, 48 000, 96 000 Hz…) y la app la convierte a la suya; ninguna cuenta del código depende ya del hardware de turno",
            "UN DICTADO SIN AUDIO YA NO SE QUEDA PENSANDO: si a los 6 segundos no ha entrado ni un buffer, se cierra y te avisa («el micrófono no está entregando audio») en vez de esperar indefinidamente",
            "Prueba nueva BTODICTA_MICTEST=1: lista los micrófonos del equipo, dice cuál se usa y confirma si entra audio de verdad",
        ]),
        ("0.54.1", "2026-09-13", [
            "ARREGLADO un cierre de la app al empezar a dictar: si el micrófono estaba cambiando de estado justo al pulsar la tecla (la bitácora acababa de soltarlo), macOS devolvía un formato inválido y la app se caía a mitad de la grabación. Ahora se comprueba el formato, se reintenta tras un respiro y, si el micrófono no está, se avisa sin cerrar nada",
            "ARREGLADO un bucle de la bitácora: cuando el motor de audio arrancaba pero no entregaba sonido, se reiniciaba cada 8 segundos sin parar. El contador se reiniciaba al arrancar el motor, y el motor arranca siempre; ahora solo se reinicia cuando llega audio de verdad",
            "La bitácora NO se apaga nunca por esto: si el micrófono no responde, baja el ritmo a un intento por minuto y vuelve sola en cuanto esté libre, sin llenar el registro",
        ]),
        ("0.54.0", "2026-09-13", [
            "NUNCA MÁS FALTA TEXTO EN UN DICTADO LARGO. Los motores de dictado en vivo pueden saltarse frases (dejando «...») y hasta dejar de transcribir del todo aunque sigas hablando: medido en un dictado real de 15 minutos, se perdieron 120 palabras, el cierre entero incluido. Ahora la app lo detecta y lo recupera sola",
            "VIGÍA DEL MOTOR: si hay voz y el texto deja de crecer, el motor está colgado — se relanza en caliente DESDE el punto exacto en que se quedó, no desde el principio, y lo ya transcrito se conserva. Hasta 8 rescates por dictado, con freno si el motor no revive",
            "REPARACIÓN QUIRÚRGICA, NO TRABAJO DOBLE: al terminar solo se revisan los tramos rotos —una ventana corta de audio por cada uno— y se cosen en su sitio por coincidencia de palabras. Un dictado sano no paga NADA: cero re-transcripciones, cero espera. El dictado de 15 minutos se reparó entero en 6,6 s frente a los 44 s de rehacerlo",
            "VARIAS ROTURAS EN LA MISMA GRABACIÓN: se atienden todas, una por una, más el final; y el texto ya no queda con puntos suspensivos donde el motor se saltó algo",
            "El registro dice qué pasó y qué se recuperó, y los avisos del motor local (que iban a un agujero negro) ahora se ven",
            "Detección determinista y recuperación con tu motor local: sin IA, sin nube y sin coste",
        ]),
        ("0.53.1", "2026-09-10", [
            "DICTADO PROTEGIDO: se excluyen clasificadores como Prompt Guard del pulido; un puntaje o una respuesta inválida pasa al respaldo y nunca sustituye silenciosamente el texto original",
            "ARCHIVOS CON CASCADA: MP3, M4A, MP4, MOV y WAV se normalizan localmente antes de usar los motores STT habilitados en tu orden; ya no van obligatoriamente a ElevenLabs. Conversión sin modificar originales y con protocolos de red restringidos",
            "PULIDO ADAPTATIVO: espera base de 8 s por proveedor, ampliada para textos y contextos largos hasta 120 s. La cascada comparte un presupuesto de 24 a 240 s; no repite timeouts y conserva el original si nadie responde",
            "MODELOS GENERATIVOS: DeepSeek V4.1 Flash sin razonamiento para pulir y Groq GPT OSS 20B como opción económica; cuarentena temporal por cuota, autenticación, red o servidor caído",
            "HISTORIAL RECUPERABLE: muestra rescates aditivos sin duplicar entradas ni sobrescribir los originales; copia del último dictado más eficiente y fechas relativas corregidas en el resumen de tareas",
        ]),
        ("0.53.0", "2026-09-01", [
            "LA BITÁCORA VUELVE A COMPRIMIR: desde el 17 de agosto cada fragmento de audio se quedaba en PCM crudo (el m4a se validaba con el escritor aún abierto, fallaba y se borraba el archivo bueno) — 17,5 GB en dos semanas. Corregido, con validación estricta por marcos antes de soltar el crudo, y RECOMPRESIÓN en segundo plano de todo lo que quedó atrás (pasadas de 1 500 archivos, una por minuto mientras quede cola, se detiene si dictas, cada m4a se comprueba antes de borrar su PCM). Ajuste y botón «Recomprimir ahora» en Bitácora",
            "STREAMING SCRIBE SIN CUOTA: cuando ElevenLabs cerraba la sesión por cuota o clave, la app seguía mandándole audio diez veces por segundo durante todo el dictado (19 539 líneas de error en tres días) y nadie pasaba al plan B. Ahora corta de una, el proveedor entra en cuarentena real (30 min) y el motor local toma el dictado a mitad de frase con todo el audio acumulado",
            "CAPTURAS DE PANTALLA CON EL EQUIPO CARGADO: el rescate de 30 s marcaba como «colgada» (y culpaba al permiso) una captura que solo iba lenta durante la tanda; umbral holgado, mensaje con la causa real y ajuste opcional para pausar la pantalla mientras corre una tanda",
            "RUTINAS DE RESUMEN HONESTAS: sin material en el rango se registra como omitida, no como fallo; si la IA no responde, el log dice por qué (HTTP, red, sin contenido) y se prueban hasta dos respaldos de tu cascada de pulido",
            "SIN INTERNET, SIN VUELTAS: el pulido ya no recorre los 16 proveedores de nube uno por uno; salta directo a tu motor local o entrega el texto original, y la voz cae a la de macOS un minuto",
            "Prueba de robustez ampliada (12 comprobaciones): compresión pcm→m4a real, cierre del streaming por cuota y clasificador de «sin conexión»",
        ]),
        ("0.52.0", "2026-09-01", [
            "ARREGLADO el crash diario de las 20:00: al hablar el resumen vespertino, el audio de ElevenLabs lanzaba una excepción de macOS (salida de audio cambiada/apagada) que tumbaba la app entera. Ahora TODO el audio va por un atrapador nativo: si falla, hace failover al siguiente motor de voz — la app nunca se cae por el audio",
            "ElevenLabs SIN CRÉDITOS ya baja al respaldo de una: se salta 60 min (sin los ~3 s de silencio por frase) y avisa una vez en el notch (\"🔇 ElevenLabs sin créditos → hablo con la voz de macOS\")",
            "AssemblyAI volvía 400 en CADA dictado y en la bitácora (2 873 fallos en dos días) porque su API deprecó `speech_model`; corregido con `speech_models` (best → universal-3-5-pro). Verificado con una transcripción real",
            "Cuarentena de proveedores STT: un fallo determinista (4xx) se salta 30 min sin gastar la llamada ni sumar latencia; un acierto lo limpia. Una sola línea en el log, sin spam",
            "Log honesto: los errores HTTP ya no se atribuyen a ElevenLabs cuando son de otro proveedor; y la voz de macOS registra cuándo habla (antes no se podía saber si el respaldo funcionó)",
            "Test de regresión BTODICTA_ROBUSTEZTEST=1 que cubre las 4 clases de fallo (9 comprobaciones, incluida una transcripción real por AssemblyAI)",
        ]),
        ("0.51.0", "2026-08-17", [
            "TODAS TUS PANTALLAS: la bitácora captura cada monitor conectado (dos, tres, los que haya), cada uno con su deduplicación y su archivo; el fallo de una pantalla que se desconecta ya no aborta las demás",
            "DIARIOS PUROS POR CANAL: cada día queda en tres archivos legibles sin la app — voz (micrófono y dictados), audio del sistema y texto en pantalla (OCR) — reconstruidos completos tras cada tanda: nunca duplican y se regeneran si los borras",
            "PROCESAMIENTO A PETICIÓN: botones «Todo», «Solo voz», «Solo sistema» y «Solo pantalla» para drenar el canal que elijas ahora mismo, sin esperar a la programación",
            "GESTIÓN DE DOCUMENTOS: desde el explorador puedes abrir para editar, exportar, eliminar con confirmación o REGENERAR un día con otro prompt sin pisar el original; pestaña nueva de transcripciones con acceso directo a la carpeta del día",
        ]),
        ("0.50.0", "2026-08-17", [
            "BITÁCORA CONTINUA (apagada de fábrica): graba tu voz, el audio del sistema y capturas de pantalla en segundo plano para reconstruir la jornada. El dictado por doble Fn manda SIEMPRE: la bitácora le cede el micrófono y vuelve sola — es regla del código, no un ajuste",
            "TANDA DIFERIDA: nada se transcribe en caliente; en una pasada (cada N minutos, a hora fija, al abrir, al apagar o a mano) transcribe con tu cascada de motores, lee las capturas con OCR local, aplica tu glosario y reemplazos —corrección fonética incluida— y comprime el audio crudo un ~88 %",
            "DOCUMENTOS CON IA: biblioteca de 10 prompts editables y restaurables (resumen, ideas, tareas, decisiones…); rutinas programadas que conviven (mediodía y noche a la vez) sin pisarse; material como línea de tiempo con hora, canal y contexto de apps; tu voz con prioridad; y sin perder nada — si el día no cabe en un envío, se trocea y se une al final",
            "CEREBRO Y PRIVACIDAD: la IA que redacta es elegible entre tus conectadas, incluidas locales (Ollama, LM Studio) con las que nada sale del equipo; cada documento abre con su rango real de contexto; puerta anti-eco para no registrar como tuyo lo que sonó por los parlantes",
            "RETENCIÓN CON CABEZA: 30/60/90 días o para siempre; antes de borrar avisa si hay material sin transcribir ni leer, y la purga automática se detiene hasta tu visto bueno",
        ]),
        ("0.49.0", "2026-07-20", [
            "MODO CONEXIÓN API: un modo puede hablar con cualquier API REST que declares (URL, autenticación, endpoints con variables tipadas y un prompt que le enseña a la IA a usarla). Dictas en lenguaje natural, la IA arma el llamado y te cuenta el resultado hablado con el estilo que pidas. Nada del sistema concreto vive en la app: todo es configuración tuya",
            "AUTENTICACIÓN Y SEGURIDAD: sin auth, API key o usuario+clave→token (con re-login automático). La clave vive en el Llavero, jamás en el archivo ni en los registros. La IA nunca ejecuta HTTP ni ve credenciales: solo propone un plan JSON que Swift valida. Fail-closed en https, sin redirecciones fuera del host declarado",
            "ESCRITURA CON VISTO BUENO: los endpoints que modifican datos siempre piden tu confirmación (proponer → ves la tabla del servidor con scroll → función confirma), con tiempo generoso para leer y la opción de ajustar la propuesta por voz sin empezar de cero; ninguna escritura se dispara sin tu OK",
            "COMPARTIR MODOS: exporta tus modos propios —conexiones completas incluidas— a un paquete JSON SIN ninguna clave ni dato de entorno; tu compañero importa con casillas los que elija y solo pone la suya",
        ]),
        ("0.48.1", "2026-07-19", [
            "TRANSCRIBE.CPP 0.2.0 ACTUALIZADO: incorpora la revisión 8c7ae67 con las nuevas bases de diarización de MOSS y Granite sin activar funciones no configuradas por el usuario",
            "PUENTE LOCAL RECONSTRUIDO: bto-stream se volvió a enlazar contra la ABI nueva y conserva el protocolo READY, parciales y resultado final que usa el notch",
            "COMPATIBILIDAD REAL VERIFICADA: 33/33 pruebas upstream, Canary por lotes, Nemotron streaming y Voxtral Realtime ejecutados con modelos y audio reales en Metal",
        ]),
        ("0.48.0", "2026-07-19", [
            "REPRODUCTOR INTERNO RESILIENTE: separa Buscar, Favoritos, Historial, Cola y Mis listas; conserva cada fuente, filtra localmente, mezcla la pestaña activa y evita repetir lo recién escuchado",
            "VIDEOS BLOQUEADOS SIN ROMPER LA MÚSICA: los errores de reproducción embebida 101/150 muestran un aviso y saltan automáticamente al siguiente elemento; el recorrido es acotado y nunca entra en bucle",
            "CONTROLES VERIFICADOS DE PUNTA A PUNTA: Play, Pausa y Stop esperan el estado real del IFrame; Pantalla muestra solo el video y Compacto conserva visible el tamaño mínimo permitido por YouTube",
            "CUOTA CON DEGRADACIÓN LOCAL: contabiliza las 100 búsquedas diarias predeterminadas, muestra el saldo estimado y, al agotarse la cuota o fallar la red, busca sin IA en resultados previos, favoritos, cola, historial y listas ya abiertas",
            "GOOGLE EXPLICADO SIN AMBIGÜEDAD: la interfaz distingue API key para búsqueda pública de OAuth de escritorio para Mis listas, guía la autorización externa y mantiene tokens, historial, cola y caché con permisos privados",
        ]),
        ("0.47.1", "2026-07-19", [
            "MOTORES NATIVOS ACTUALIZADOS CON EVIDENCIA: incorpora transcribe.cpp 5a5a496 y llama.cpp b10068 tras comprobar procedencia, licencias, API pública, Metal, binarios ARM64 y modelos reales Canary, Nemotron, Voxtral y BGE-M3",
            "VOXTRAL LOCAL CORREGIDO: la instrucción llega antes que el audio al servidor multimodal; evita respuestas de rechazo y recupera la transcripción real con el glosario intacto",
            "PUENTE STREAMING REPRODUCIBLE Y SEGURO: make bto-stream valida todas las bibliotecas, construye aparte y reemplaza el ejecutable únicamente al terminar correctamente; un fallo conserva el motor anterior",
        ]),
        ("0.47.0", "2026-07-19", [
            "VOZ XTTS ESTABLE HASTA EL FINAL: segmenta localmente los textos largos sin depender de spaCy, conserva pausas naturales y valida el cierre completo del flujo HTTP para no aceptar audios truncados ni frases que se mueren al final",
            "CALENTAMIENTO LOCAL PARAMETRIZABLE: conserva únicamente el motor de voz activo, lo protege 60 minutos al abrir y 15 minutos después de usarlo, y puede precompilar XTTS o Qwen3-MLX con una frase silenciosa editable",
            "ACTIVACIÓN MANOS LIBRES REARMADA: al terminar, cancelar o responder, el oyente de presencia vuelve de forma verificable; el ícono de la barra se reconstruye si macOS lo pierde y conserva el color dinámico de plantilla",
            "MODO MÚSICA MÁS PRECISO: diferencia buscar de reproducir dentro del mismo modo, reconoce proveedor y orden sin fabricar etapas duplicadas y conserva la degradación configurada entre reproductores",
            "QA REPRODUCIBLE VERSIONADO: paquete de camino feliz y estrés con 15 comprobaciones locales automáticas, guiones manuales, evidencia privada y pruebas específicas para voz, modos, permisos, tareas y acciones",
            "CALIDAD ANTES QUE NOVEDAD: Chatterbox-MLX se midió como carril experimental y no se activó al quedar por debajo de la identidad de XTTS; la voz de referencia y todos los motores existentes permanecen intactos",
        ]),
        ("0.46.0", "2026-07-19", [
            "REPRODUCTOR INTERNO DE MÚSICA: BtoDicta · YouTube integra búsqueda, cola, Anterior, Play/Pausa, Stop y Siguiente; diferencia buscar de reproducir, verifica el estado real y participa en la cascada configurable de Modo Música",
            "GOOGLE SIN CONTRASEÑAS EMBEBIDAS: búsqueda mediante YouTube Data API v3 con API key propia u OAuth de escritorio en el navegador externo, PKCE y retorno exclusivo a 127.0.0.1; el token revocable queda protegido en el archivo privado de claves",
            "GRABACIONES MÁS CLARAS: reconoce grabemos, hagamos, inicia y comienza; si falta el área pregunta pantalla o ventana conservando la orden original, y al terminar deja una confirmación persistente con la ruta y Ver en Finder",
            "CONTROL LOCAL DEL VOLUMEN: entiende porcentaje, subir, bajar, máximo, silencio y reactivar; comprueba el estado final del Mac antes de responder y evita falsos positivos como volumen de ventas",
            "PERMISOS GUIADOS: el primer arranque explica y enlaza Notificaciones, voz de Apple, pantalla, Contactos, Calendario, Recordatorios, Ubicación, Música, Automatización y archivos sin volver obligatorias las funciones opcionales",
            "AUTOAYUDA RÁPIDA: botones, enlaces e interruptores muestran una explicación inmediata y conservan descripciones para VoiceOver; la burbuja visual es parametrizable",
            "XTTS RESIDENTE MÁS ÁGIL: la voz local espera y reutiliza el servidor ya cargado en vez de levantar un generador completo por cada frase; mantiene streaming y batch como degradación segura",
        ]),
        ("0.45.0", "2026-07-19", [
            "ACTIVACIÓN MANOS LIBRES CONFIGURABLE: el nombre y las frases pertenecen al usuario; una pausa local despierta al asistente, ofrece un acuse breve editable y abre un turno limpio. El listener es opt-in, libera el micrófono al trabajar y convive con una pasarela Siri/Atajos instalable",
            "DICTADO ASISTIDO SIN MANOS: dicta, transcribe, escribe, corrige, actualiza o mejora un texto; BtoDicta quita únicamente la orden, pule con degradación al original, pega en la aplicación activa y conserva opcionalmente el portapapeles. Decir solo ‘dictado’ abre una segunda toma automática",
            "ATAJOS Y RECETAS PORTABLES: instaladores firmados para Escuchar asistente, BtoDicta Universal y Música; biblioteca editable para resumen/jornada/reunión/selección/estado del Mac/HomeKit/audio, con permisos, riesgo, evidencia e importación o exportación JSON",
            "TAREAS, NOTAS Y APPLE: recordatorios locales con fecha, calendario y avisos recuperables; resúmenes configurables; EventKit para Recordatorios/Calendario y creación de Notas de Apple con formato, lectura posterior y confirmación únicamente cuando el contenido real coincide",
            "CLIMA REAL: consulta por ciudad o mediante una ubicación aproximada opcional del Mac, con permiso explícito, HTTPS, caché breve en memoria y respuesta verificable sin entregar la pregunta a una IA que pueda inventarla",
            "VOCES LOCALES MÁS SEGURAS: carril Máxima XTTS restaurado dentro de BtoDicta, alternativa equilibrada Qwen3-TTS/MLX en Apple Silicon, paquetes/personas recuperables, confirmación antes de cambiar o quitar y failover cuando un audio generado está dañado",
            "ROBUSTEZ DEL ASISTENTE: evita fugas de instrucciones, preserva la cascada de proveedores, encadena texto generado hacia borradores/WhatsApp, verifica música y actualización, y reconoce formas naturales como ‘grabemos la pantalla’ sin confundir grabaciones de audio ni narraciones",
        ]),
        ("0.44.0", "2026-07-18", [
            "ASISTENTE POR VOZ CONFIGURABLE: nombre, personalidad, frases de activación, memoria corta local, tres niveles de autonomía y respuestas en texto o texto+voz; resuelve localmente primero y usa Hermes, una IA conectada o Codex solo cuando hace falta",
            "CUENTA CHATGPT MEDIANTE CODEX OFICIAL: autorización delegada al CLI, modelo y esfuerzo de razonamiento elegibles, failover y uso separado para asistente, pulido, traducción y modos; nunca se mezcla con STT, TTS, embeddings ni con la API de OpenAI",
            "ACCIONES NATIVAS VERIFICABLES: Recordatorios y Calendario mediante EventKit, búsqueda de archivos con Spotlight/Finder, borradores en Gmail/Mail/Outlook que nunca se envían solos, documentos Word con estructura visual y ejecución de Atajos elegidos por el usuario",
            "MODO MÚSICA CON FAILOVER: Apple Music espera su arranque en frío y confirma audio real; Spotify reproduce el primer resultado visible y verificado; buscar nunca pulsa Play; si falla, salta de motor sin abrir una cadena de ventanas y conserva un Atajo firmado como puente opcional",
            "CAPTURA Y GRABACIÓN POR VOZ: pantalla, ventana, selección o cuadrante; destino, nombre, portapapeles, apertura, micrófono y clics. Las grabaciones sin duración se detienen con una sola fn o el menú, se guardan por fragmentos recuperables y ocultan el notch",
            "WHATSAPP SEGURO PARA ADJUNTOS: política configurable entre solo portapapeles, preparar sin enviar y autoenviar explícito; el autoenvío exige detectar una vista previa nueva y un único botón Enviar, y bloquea retornos automáticos accidentales",
            "INTERFAZ Y AUDITORÍA: menú compacto de consumos, panel con desplazamiento, permisos explicados por función, registros locales protegidos y una matriz QA reproducible para rutas naturales, acciones y regresiones",
            "ACTUALIZADOR CORREGIDO: tras autenticar todo el DMG con Ed25519 y montarlo en solo lectura, acepta la identidad fijada del certificado autofirmado de BtoDicta sin crear un bypass para archivos no autenticados",
            "ENTRENAMIENTO PIPER: progreso y confirmaciones muestran el estado real en lugar de porcentajes estáticos o capas visuales superpuestas",
        ]),
        ("0.43.0", "2026-07-17", [
            "VERSIÓN ESTABLE: lleva al canal general todo lo probado en la beta 0.42.0 y vuelve a dejar GitHub latest disponible para las instalaciones que reciben solo versiones estables",
            "INTENCIÓN NATURAL MULTIETAPA: entiende pedidos como \"resume, traduce al quichua y envía por correo y WhatsApp a Andrés\", conserva destinatarios y confirma el plan completo antes de ejecutar acciones externas; fn confirma y X continúa como dictado normal",
            "NUEVO MODO APLICACIÓN: inventaría las apps realmente instaladas en cada Mac y permite decir \"modo abrir aplicación Word, borrador del informe\"; resuelve alias y ambigüedades, espera a que la app tome el foco y nunca pulsa Enter ni envía contenido",
            "SEGURIDAD Y DEGRADACIÓN SUAVE: reglas locales primero, embeddings con margen e IA opcional solo como último árbitro; una app desconocida, una IA ausente o una interpretación ambigua nunca bloquean ni convierten texto normal en una acción silenciosa",
            "ACTUALIZACIONES ENDURECIDAS: cada DMG estable lleva una firma Ed25519 separada verificada por la app, además de la identidad del bundle; rechaza descargas alteradas o sin firma. Las copias 0.40–0.42 aceptan 0.43 por el mismo certificado y, desde 0.43, el flujo automático queda protegido también por esta firma distribuible",
            "MODOS SIN ESTADO PEGADO: al terminar un modo de un solo uso, nombre, color y ejecución vuelven juntos al modo por defecto; cada nuevo dictado vuelve a sincronizar el notch como segunda barrera",
            "CONFIRMACIÓN CON UNA FN REAL: el modal de intención ignora la opción de doble-fn y acepta una sola pulsación, incluso si la pregunta aparece entre bajar y soltar la tecla; detener una grabación nunca confirma a ciegas su propio resultado",
            "CAJA NEGRA DE MODOS AMPLIADA: registra inicio/cierre, resolución consolidada, modal, origen de la respuesta y restauración visual; el manual incluye 24 casos reproducibles para probar rutas positivas, negativas y encadenadas",
            "QA REPRODUCIBLE: nuevas matrices para aplicaciones, planificación natural, regresiones, audio y arbitraje por IA, además del registro detallado que permite seguir mejorando los modos",
        ]),
        ("0.42.0-beta", "2026-07-17", [
            "CADENAS COLOQUIALES: di \"por favor, envía un correo que traduzca lo siguiente: …\" y BtoDicta detecta las MÚLTIPLES intenciones (en cualquier orden) y te confirma todo de una: \"¿TRADUCIR y enviar por correo? fn = sí\" → traduce y abre el correo con el resultado. Nunca ejecuta sin confirmar",
            "Capa GRAMATICAL: entiende el verbo del modo en cualquier conjugación sin decir \"modo\" (\"tradúceme esto al quichua…\", \"búscame en google…\", \"apúntame como tarea…\" cambian directo). Si es ambiguo (\"quiero traducir algo…\"), pregunta con un mini-aviso en el notch (fn = sí)",
            "Motor de embeddings INTERNO (sin Ollama ni nada): BtoDicta sirve su propio bge-m3 con el llama-server que ya trae. Descarga única de ~417 MB con permiso; ~7 ms por consulta (medido) con precalentamiento al pulsar fn; duerme tras 10 min. Sirve para modos semánticos, búsqueda del historial y glosario. Ollama/OpenAI/Gemini/Mistral siguen como opciones",
            "Auditoría multi-agente del sistema de modos con 10 correcciones confirmadas (pausa que se despintaba, recorte con puntuación, prioridad del comando en vivo vs contexto, notch pegado, y más) + matriz QA automatizada (56 casos verdes)",
        ]),
        ("0.41.0", "2026-07-16", [
            "PREVIEW EN VIVO UNIVERSAL: en macOS 26, el notch muestra localmente lo que vas diciendo con Apple DictationTranscriber aunque el motor real (por ejemplo Groq) no tenga streaming; es solo visual y la cascada elegida conserva la transcripción definitiva",
            "DESTILACIÓN XTTS → Piper/ONNX: desde una voz XTTS ya entrenada puedes crear su variante rápida, conservar Calidad + ⚡ Rápida en la misma persona, validar inteligibilidad/parecido y llevar ambas en el paquete portable",
            "CONTINUACIÓN TRAS APAGADO en toda la destilación: conserva cantidad, etapas y calidad; detecta dataset, entrenamiento o validación a medias; reutiliza clips y resultados ya válidos sin lanzar procesos duplicados",
            "Checkpoint de seguridad rodante cada 200 pasos: al reanudar elige el corte más nuevo entre hitos y seguro; la validación incremental reintenta fallos transitorios en vez de guardar ceros falsos",
            "Arreglo del Modo Agente con clon XTTS: la respuesta ya no cierra BtoDicta cuando el audio empieza desde el hilo de red; callbacks y notch se sincronizan siempre en el hilo principal",
            "Activación opcional con doble fn incluida en la versión estable: doble toque para empezar y uno para detener; con push-to-talk, mantén el segundo toque y suelta para transcribir",
        ]),
        ("0.40.0", "2026-07-16", [
            "VERSIÓN ESTABLE: restaura el canal releases/latest de GitHub para que las instalaciones antiguas vuelvan a encontrar y recibir actualizaciones",
            "Actualizador compatible con ESTABLES Y BETAS: canal Automático, Solo estables o Estables y beta; si GitHub latest excluye prereleases, usa la lista general como failover",
            "Revisión periódica configurable cada 1, 3, 6, 12 o 24 horas, más botones visibles para Comprobar de nuevo y Reintentar sin reiniciar BtoDicta",
            "Activación opcional con doble pulsación: dos toques para iniciar y uno para detener; con push-to-talk, mantén el segundo toque y suelta para transcribir",
        ]),
        ("0.39.0-beta", "2026-07-14", [
            "Validación de voz Piper: al terminar el entrenamiento, pulsa “Validar y graficar” y BtoDicta genera muestras de cada checkpoint, mide INTELIGIBILIDAD (Whisper transcribe y compara) + PARECIDO de voz (d-vector), dibuja una GRÁFICA y marca el mejor — o te avisa si TODOS salieron mal (para que nunca elijas basura a ciegas)",
            "Diagnóstico: el entrenamiento Piper necesita MUCHÍSimas más épocas (no 5000 pasos) para salir inteligible; la validación ahora lo deja clarísimo con números y gráfica",
        ]),
        ("0.38.0-beta", "2026-07-14", [
            "Cancelar al agente ahora lo mata DE RAÍZ, no solo el bypass: auditamos y vimos que Hermes corría el trabajo (y sus herramientas: shell, etc.) como procesos aparte que quedaban VIVOS al cancelar. Ahora se mata el árbol completo (Hermes + sus herramientas + subprocesos) — el trabajo se detiene de verdad",
            "BARGE-IN: mientras la IA responde, pulsa fn y la INTERRUMPES para decirle otra cosa — se corta lo actual y grabas lo nuevo, que sigue la MISMA conversación (Hermes conserva el contexto). Como interrumpir a alguien; más natural para hablar de ida y vuelta",
        ]),
        ("0.37.0-beta", "2026-07-14", [
            "CANCELAR el agente/voz como con el dictado: pulsa Esc (o toca el notch) y se cancela TODO al instante — mata a Hermes/IA en curso, ignora respuestas en vuelo y corta el audio de raíz (Apple, nube y streaming local). Ya no dependes de esperar a que Hermes termine su relajo",
            "Vale para cualquier motor de agente (Hermes, IA local o nube) y para todos los modos que hablan",
        ]),
        ("0.36.0-beta", "2026-07-14", [
            "BETA: el entrenamiento de voces es experimental; puede cambiar o fallar. Lo etiquetamos beta mientras lo estabilizamos",
            "Bitácora con avance GLOBAL + avance de la FASE + subfase (época·paso / archivo), todo en vivo",
            "CPU se muestra en NÚCLEOS reales (ej. “5.7 de 18 núcleos, 31%”) en vez del confuso 500%+",
            "GPU e IA (Neural Engine) se muestran honestos: “sin usar (entrena en CPU)”",
            "Velocidad (pasos/s) y ETA siempre visibles cuando entrena",
        ]),
        ("0.35.0", "2026-07-14", [
            "Progreso del entrenamiento Piper AHORA SÍ EN VIVO: la app imprime el paso ella misma (paso a paso, con velocidad y ETA) en vez de esperar a Lightning, que no volcaba su barra al archivo. La bitácora se llena en tiempo real desde el primer paso, sin esperar al primer checkpoint",
        ]),
        ("0.34.0", "2026-07-14", [
            "BITÁCORA VIVA al entrenar una voz Piper: ves en la app, refrescándose solo, la FASE (1/2), el porcentaje real, paso/total, época, velocidad (it/s), tiempo estimado (ETA), CPU, RAM, disco, fragmentos, checkpoints y errores — más el registro imprimiéndose en vivo. Todo queda también en dataset.log y piper.log",
            "“⏹ Detener del todo”: el botón mata el entrenamiento DE RAÍZ (y sus procesos: torch, Whisper, ffmpeg) y te confirma que no quedó nada corriendo. Tú tienes el control, sin depender de nadie",
            "MUCHO más rápido en Apple Silicon: el entrenamiento usa solo los núcleos veloces (incluir los lentos lo dejaba clavado sin avanzar). De no arrancar en 25 min a ~1.4s por paso",
            "Progreso correcto: el porcentaje ya no se queda pegado cerca de 0 (se calcula el paso global bien). Reentrenar reusa el dataset ya hecho (no re-transcribe) y no mezcla cortes viejos",
        ]),
        ("0.33.0", "2026-07-14", [
            "ENTRENAR una voz PIPER (rápida, ⚡): hornea una voz FIJA que habla casi al instante (~5× tiempo real). Desde Biblioteca de voces → carpeta de audios + nombre + persona → entrena en segundo plano y eliges el mejor corte escuchándolo. XTTS se queda para clonar con máxima calidad",
            "CALIDAD parametrizable (Media/Alta/Baja): Media usa base en ESPAÑOL (recomendada); Alta es más nítida pero más lenta; Baja es la más veloz. Alta/Baja parten de base en inglés y se adaptan a tu español",
            "Progreso EN VIVO con porcentaje y fases: ves “transcribiendo X de Y (%)” y luego “paso X de Y (%)”, minuto a minuto. Registra todo en logs",
            "Resumible de verdad: puedes cerrar la ventana e incluso salir de BtoDicta; el entrenamiento sigue en segundo plano y al reabrir el progreso vuelve a aparecer. Si se apaga la compu, “Reanudar” continúa desde el último corte",
            "Todo funciona en cualquier Mac: lo pesado (motor, base ~0.8-1 GB por calidad) se descarga bajo demanda de fuentes verificadas (rhasspy/piper-checkpoints); nada pesado en la app. Avisa si falta ffmpeg o las herramientas de Apple",
        ]),
        ("0.32.0", "2026-07-14", [
            "ENTRENAR una voz nueva DENTRO de BtoDicta (🎓 en Clon local): eliges una carpeta de audios + nombre, la app recomienda las etapas según cuánta voz haya, entrena en segundo plano con progreso EN VIVO + gráfica, y al final eliges el mejor corte (escuchas cada uno) → sale tu paquete portable. La persona (cómo habla) se saca sola",
            "Muchos más motores de voz en la nube: OpenAI, Google Gemini, Deepgram, Cartesia, Inworld, PlayHT, Azure — cada uno con su voz/modelo y streaming (WebSocket) configurable, con tu key",
            "Subir un clon de FUERA aunque venga incompleto: BtoDicta arma lo que falta; si no trae muestras te las pide (➕🎙); si no trae persona la genera transcribiendo las muestras (🧠)",
            "Motor de voz propio y aislado que corre tus clones (se instala con un botón; no toca tu sistema)",
        ]),
        ("0.31.0", "2026-07-14", [
            "Motor de voz INTERNO y aislado: BtoDicta corre tus clones con su propio Python (se instala con un botón, ~3-4 GB bajo ~/.btodicta/, no toca tu sistema). Ya no dependes de herramientas externas",
            "SUBIR y DESCARGAR voces: importa un paquete de voz portable (⬆︎) o descárgalo para llevarlo (⬇︎). Cada voz lleva su persona (cómo habla)",
            "Streaming del clon local (por voz): tu voz clonada suena MIENTRAS se genera (1er sonido en ~1-2s). Activable por cada voz, no global",
            "Arreglado: en la cascada de Modelos ya puedes arrastrar cualquier motor (Apple, Azure, OpenAI…) al orden que quieras — antes se trababa con proveedores ocultos",
        ]),
        ("0.30.0", "2026-07-14", [
            "Apple Speech NATIVO como motor de dictado: on-device, gratis, sin API key, sin internet (macOS 26+). Actívalo en la cascada",
            "Voz del sistema mejorada: eliges motor (voz de macOS · ElevenLabs tu voz clonada · clon local) con failover — nunca queda mudo",
            "ElevenLabs por STREAMING (WebSocket): tu voz clonada empieza a sonar en ~75-130ms mientras se genera",
            "Biblioteca de VOCES clonadas locales: agrega/sube/elige tus voces; cada una con su PERSONA (cómo habla) — el Agente redacta en ese estilo y lo dice con esa voz. 100% local",
            "Pulido MÁS RÁPIDO tras inactividad: la red se mantiene caliente (latido) y el pulido reusa la conexión — sin la espera de ~14s con VPN",
            "Modo Agente: te responde por voz + texto usando tus tareas/notas; eliges con qué IA piensa y con qué voz habla",
        ]),
        ("0.29.0", "2026-07-14", [
            "Muchos más buscadores en el modo Buscar: Wikipedia, Gmail, Outlook/Hotmail, Facebook, Amazon, MercadoLibre, X (Twitter), GitHub — y puedes AGREGAR los tuyos (nombre + URL con {q})",
            "Embeddings LOCALES por defecto (Ollama bge-m3): el glosario inteligente, el reconocimiento de modos y la búsqueda semántica corren en tu Mac — gratis, privados, sin internet ni latencia. Y si no tienes ningún motor, la app sigue funcionando igual (sin error ni demora)",
            "Menos latencia con VPN: la app 'despierta' la red mientras hablas (WireGuard/OpenVPN/etc. que duermen el túnel ya no te hacen esperar en el primer dictado)",
            "Pulido más robusto ante caídas: reintento con conexión fresca y, si sigue fallando, salto al siguiente proveedor; nunca se queda colgado",
            "Voz del sistema (texto → voz): BtoDicta ya puede LEERTE respuestas en voz (voz de macOS, gratis) — primer paso del Modo Agente. En Ajustes → Avanzado",
        ]),
        ("0.28.0", "2026-07-14", [
            "Reconocimiento inteligente de modos MÁS PRECISO: la zona-comando se ajusta sola (ventana dinámica) — corta donde la intención se entiende y conserva el resto como contenido (ej. \"modo mándale un WhatsApp a Ana, nos vemos\" reconoce WhatsApp y guarda \"a Ana, nos vemos\")",
            "El sistema se MEJORA A SÍ MISMO: nuevo \"Mejorar modos\" (Ajustes → Modos, icono varita) — analiza el registro y te dice qué reconoció mal, con un clic agregas los comandos no reconocidos como ejemplos, o pide sugerencias a tu IA. Y un registro detallado en ~/.btodicta/logs/modos.jsonl (opcional)",
            "Arreglo: la ventana de Reemplazos ya no corta el encabezado al activar \"coincidir por audio\"",
        ]),
        ("0.27.0", "2026-07-14", [
            "Reconocimiento INTELIGENTE de modos por voz (Ajustes → Avanzado, opt-in): entiende el llamado de un modo aunque lo digas de mil formas (\"modo mándale un WhatsApp…\", \"modo apúntame una tarea…\") con embeddings. Solo actúa si empieza con \"modo\" (o mal-escuchas: mudo/molde/…) y el exacto no acertó; si nada se parece, sigue como texto normal",
            "Es parametrizable (cuántas palabras del inicio se analizan + sensibilidad) y ENTRENABLE por ti: en Ajustes → Modos, cada modo tiene un campo \"Ejemplos\" para agregar TUS formas de pedirlo, procesadas con tu motor de embeddings (Ollama local o el que elijas)",
        ]),
        ("0.26.0", "2026-07-14", [
            "Glosario inteligente (Ajustes → Avanzado, opt-in): en el pulido manda a la IA solo los términos del glosario afines a lo que dictaste (con embeddings), no todos. Prompt más corto = pulido MÁS RÁPIDO, y escala aunque tu glosario crezca a cientos de términos",
            "Importar contactos de WhatsApp desde cualquier lado: auto-detecta vCard (.vcf de teléfono/iCloud/Outlook), CSV de Google/Gmail (inglés y español) y de Outlook/Edge, o CSV/JSON simple; te dice cuántos válidos/inválidos",
            "WhatsApp \"enviar a <nombre>\" más preciso: entiende el nombre aunque el dictado le ponga punto o coma, y el modal prioriza los contactos más probables (muestra hasta 6 de los que coincidan)",
        ]),
        ("0.25.0", "2026-07-14", [
            "WhatsApp con CONTACTOS: importa tu lista (CSV/JSON o export de Google/Gmail) o usa tus Contactos de Mac; di \"modo whatsapp, a Andrés, hola\" y abre su chat con el texto. Si hay varios, eliges en un modal. Exportar CSV/JSON te da el formato",
            "Modos de ACCIÓN listos para las apps de Mac por defecto: Outlook, Correo, WhatsApp, Notas, Recordatorios, Calendario, Finder, Safari, Música, Terminal, Mapas, Spotlight y tu propia web (btodicta.eztic.ec). Créalos/edítalos en Ajustes → Modos",
            "Reconocimiento por VOZ más flexible: varias frases por modo (failover ante mal-escuchas, ej. \"mudo tarea\"=\"modo tarea\") y matcheo por raíz (\"buscador\"→buscar, \"traduce\"→traducir)",
            "Cadenas por voz más robustas: tolera comas/puntos, \"modo\" repetido por etapa, y el idioma tras \"a\" (\"modo traducir a inglés correo, …\")",
            "Arreglos: idiomas con coma (\"modo traducir portugués, …\"), y \"modo <app>\" sin texto ya abre la app sin pedir contenido",
        ]),
        ("0.24.0", "2026-07-14", [
            "Modos ENCADENADOS por voz: junta un paso + una acción en una frase — \"modo traducir quichua a correo, hacer la merienda\" traduce y abre un correo con el texto; \"modo traducir inglés whatsapp, nos vemos\" traduce y abre WhatsApp. Orden-independiente y con conectores (a, y, en…) que se ignoran",
            "Frases de voz MÚLTIPLES por modo (failover ante mal-escuchas del STT): cada modo acepta varias separadas por coma (ej. Tarea: \"modo tarea, mudo tarea, molde tarea\"). Añade las tuyas en Ajustes → Modos",
            "WhatsApp con failover: abre la app de escritorio si la tienes, si no wa.me (web) y te sugiere instalarla",
            "Arreglo: decir solo el comando sin texto (\"modo tarea\" y nada más) ya no crea una tarea vacía — te avisa",
        ]),
        ("0.23.0", "2026-07-14", [
            "Tareas y notas (nueva pestaña): dicta con el modo Tarea o Nota (o \"modo tarea …\") y se guardan en una lista LOCAL en tu Mac. Marca hechas, borra, limpia o agrega a mano",
            "Nuevo modo ACCIÓN: dicta y se abre una app o página con tu texto — Nuevo correo (mailto), Outlook, WhatsApp, o abre Notas/Recordatorios/Calendario/Finder/Mensajes (copia el texto para pegar), o TU propia URL con {q} (ej. tu intranet). Sin IA — hazlo un modo propio con su frase de voz (ej. \"modo whatsapp …\")",
        ]),
        ("0.22.0", "2026-07-14", [
            "FAILOVER de pulido: si tienes 2+ IAs de chat conectadas, ordénalas en Ajustes → Pulido (\"Failover de pulido\") y si la 1ª (ej. Groq) no responde, salta sola a la 2ª, 3ª… (ej. OpenAI → OpenRouter → local). El pulido ya no se queda sin funcionar por un proveedor caído",
            "Modos por VOZ con argumento: \"modo traducir quichua …\" traduce a quichua; \"modo buscar google …\" busca en Google — el dato ajusta el modo solo por ese dictado (sin argumento usa el idioma/buscador por defecto). Reconoce rellenos (\"al\", \"en\") y alias (ddg, yt, mapas…)",
            "Transcribir con selector \"Procesar como:\": aplica un modo (Correo, Oficio, Traducir…) al archivo que subes o al dictado que re-transcribes",
            "Nuevo idioma de traducción: quichua (con banderita 🇪🇨)",
        ]),
        ("0.21.0", "2026-07-13", [
            "NUEVO: MODOS — decide qué hacer con lo dictado. Además de Dictado (pulir), elige Correo, Oficio, Tarea, Nota, Traducir, Asistente o Buscar; cada modo con su propia IA y su prompt. Cámbialo al vuelo desde el notch (arriba-izquierda) o el menú de la barra, como el proveedor",
            "El modo elegido al vuelo es de UN SOLO USO: se aplica a ese dictado y vuelve al modo POR DEFECTO (configúralo en Ajustes → Modos; puedes dejarlo fijo apagando el interruptor)",
            "Activa un modo POR VOZ (empieza el dictado con 'modo tarea …'), POR APP o POR SITIO WEB (ej. en Outlook usa Correo; en tu intranet usa Oficio)",
            "Modo TRADUCIR con selector de idioma (con banderita) y opción de agregar los idiomas que quieras",
            "Modo BUSCAR: dictas y se abre el buscador con tu consulta — Google, Bing, DuckDuckGo, YouTube, Google Maps, Spotlight (⌘Espacio) o una URL propia",
            "Crea tus PROPIOS modos con nombre, comportamiento, prompt e IA a tu gusto",
        ]),
        ("0.20.11", "2026-07-13", [
            "En Modelos, los motores que transcriben EN VIVO (texto mientras hablas) llevan ahora una etiqueta 'EN VIVO': locales Nemotron/Voxtral Realtime, ElevenLabs realtime, y los de nube por WebSocket (Deepgram, Soniox, AssemblyAI, Speechmatics, Gladia). Verde = activo; gris = lo soporta, actívalo en Avanzado",
            "Speechmatics en vivo más robusto: si su conexión falla, ahora cae al plan B al instante y con el motivo en el registro (antes se demoraba y no decía por qué)",
        ]),
        ("0.20.10", "2026-07-13", [
            "Ayuda por proveedor: cada IA de nube (chat y voz) tiene ahora un icono ⓘ con una explicación INSTANTÁNEA (qué es, si es gratis, si va en vivo) y un enlace 'Conseguir clave' que abre la página oficial donde sacas tu API key — sin perder tiempo buscándola",
        ]),
        ("0.20.9", "2026-07-13", [
            "Motores locales de transcripción al día: whisper.cpp (ggml 0.16.0, más allá de v1.9.1), llama.cpp (build 9976) y transcribe.cpp (v0.1.3) — mejoras de rendimiento y correcciones de los proyectos base, sin tocar tu configuración ni tus modelos",
        ]),
        ("0.20.8", "2026-07-13", [
            "MUCHOS motores de transcripción nuevos, varios GRATIS: Groq Whisper, Hugging Face y Cloudflare (gratis), Fireworks, Deepgram, AssemblyAI, Gladia y Speechmatics; y de pago premium Soniox (mejor español latino) y Azure AI Speech (con locale es-EC de Ecuador). Ollama y LM Studio locales se ofrecen solo si tienen un modelo whisper (detección inteligente)",
            "TEXTO EN VIVO también en la nube: Deepgram, Soniox, AssemblyAI, Speechmatics y Gladia pueden transcribir por WebSocket mientras hablas (actívalo en Avanzado → 'STT en vivo para la nube')",
            "7 IAs de pulido GRATIS más: Cerebras, GitHub Models, NVIDIA NIM, Together, Novita, Z.ai (GLM) y SiliconFlow; y plantilla lista de Cloudflare Workers AI (solo pones tu Account ID)",
            "Precios REALES de todos los modelos (voz y chat) y se actualizan solos desde una fuente mantenida, sin gastar IA; en Estadísticas ves además el GASTO de pulido con IA (hoy/semana/mes) con gráfica",
            "Búsqueda por SIGNIFICADO en el Historial (semántica): encuentra dictados por idea, no por palabra exacta; eliges con cuál IA se calcula (Ollama local gratis, OpenAI, Gemini o Mistral)",
            "Tu gateway propio ahora también puede TRANSCRIBIR (antes solo pulía); y salvaguarda anti-inyección opcional para IAs de terceros",
        ]),
        ("0.20.7", "2026-07-12", [
            "Pulir/traducir con Anthropic (Claude) y Gemini (Google) — se suman a Groq, OpenAI, Mistral, OpenRouter, DeepSeek y xAI. Pon tu key en 'Conectar más IAs'",
            "Push-to-talk: opción para grabar mientras MANTIENES la tecla y terminar al soltarla (Ajustes → General). El modo toque sigue de default",
            "Detección de IA local EN VIVO: LM Studio / Ollama recién abiertos ya se detectan sin reiniciar la app; y elige un modelo de CHAT por defecto (no uno de embeddings)",
        ]),
        ("0.20.6", "2026-07-12", [
            "El selector de pulido muestra 'proveedor · modelo', y puedes elegir el modelo de CUALQUIER IA (nube, local o gateway) al vuelo con el botón 'Descubrir', no solo de los gateways",
            "Descubrir modelos trae el PRECIO por modelo cuando el proveedor lo publica (ej. OpenRouter): '$in/$out por millón de tokens' o 'gratis'",
            "Aviso de privacidad al pulir con una IA de nube o gateway de terceros (tu texto sale de tu Mac) — configurable en Avanzado. Si el gateway usa http sin cifrar, la API key ya no se envía",
            "Descubrir prueba más rutas (/v1/models, /openai/v1/models, /api/v1/models) y acepta una ruta manual para gateways raros",
            "La app no se cuelga al abrir sin internet (el chequeo de actualización es asíncrono y falla rápido)",
        ]),
        ("0.20.5", "2026-07-12", [
            "SEGURIDAD: la actualización ahora VERIFICA la firma del DMG antes de instalar — solo se instala si viene firmado con el mismo certificado de la app; un release manipulado se rechaza. Se quitó el borrado a ciegas de la cuarentena.",
            "SEGURIDAD: las API keys y los gateways (.env, config, personalizadas) se guardan con permisos 0600 (solo tú), y la key no se manda si el gateway usa http sin cifrar.",
            "Auditoría de seguridad completa del sistema (revisión adversarial) — sin puertas traseras ni fugas; correcciones aplicadas.",
        ]),
        ("0.20.4", "2026-07-12", [
            "La app avisa sola: al abrir revisa si hay versión nueva y te lo muestra abajo-izquierda ('Actualización disponible') y en el menú de la barra — puedes ver las novedades antes de actualizar",
            "Nuevo en Avanzado: 'Autoactualizar' (baja e instala sola la versión nueva) y 'Buscar actualización al abrir' (ambos parametrizables)",
            "Gateways propios: 'Descubrir modelos' ahora guarda TODOS los modelos y puedes elegir cualquiera al vuelo desde Ajustes → Pulido, sin abrir el editor",
            "Se puede instalar/actualizar por Homebrew: 'brew install --cask --force' para adoptar una instalación previa; 'brew upgrade --greedy' para traer la última",
        ]),
        ("0.20.3", "2026-07-12", [
            "Descubrir modelos en gateways propios ahora SÍ encuentra la lista aunque tu URL base no lleve /v1: lo prueba solo y te avisa que la API está bajo /v1",
            "El actualizador muestra el PORCENTAJE de descarga con barra de progreso (antes solo decía 'descargando')",
            "Las secciones plegables (Avanzado, Conectar más IAs) se abren al hacer clic en TODO el título, no solo en la flechita",
        ]),
        ("0.20.2", "2026-07-12", [
            "El ícono de la barra de menú ahora REACCIONA: late en rojo mientras grabas y en morado mientras procesa/pule; vuelve a normal al terminar",
            "En el aviso de novedades, botón 'Revisar todas las novedades' que abre Créditos con el historial completo",
        ]),
        ("0.20.1", "2026-07-12", [
            "Más IAs para pulir/traducir: DeepSeek, xAI (Grok), y GATEWAYS personalizados (tu propia URL base, API key, esquema de auth Bearer/X-API-Key/encabezado propio, encabezados extra y descubrimiento de modelos)",
            "Las novedades de la actualización ahora se ven bien formateadas (ya no en texto plano)",
        ]),
        ("0.20.0", "2026-07-12", [
            "Pulido y traducción con CUALQUIER IA conectada: Groq, OpenAI, Mistral, OpenRouter — y hasta LOCAL (LM Studio, Ollama), que se detectan solos si están corriendo. Elige cuál en Ajustes → Pulido",
            "El pulido ya no se cae por cortes de red (reintenta solo) y su espera es ajustable (Avanzado), más larga para textos largos",
            "Al terminar un dictado, opcional: añadir un espacio, pulsar Enter (enviar en chats) o Shift+Enter (salto de línea)",
            "Reemplazos: botón 'probar' (ver qué caza la fonética) y 'escuchar' la pronunciación; y coincidencia por AUDIO experimental (reconoce tus términos por tu propia voz grabada, con soporte de siglas)",
        ]),
        ("0.19.1", "2026-07-11", [
            "Asistente de primer arranque: te guía en 8 pasos por permisos, IA de nube y local, el orden del failover, aprendizaje y preferencias — con check en vivo de los permisos",
            "La app aprende de ti: corriges una palabra donde la pegaste (Sentrix → Zentrix) y la recuerda sola. En la terminal o Claude Code, selecciónala y pulsa ⌘⇧L",
            "Corrección por sonido (fonética): corrige lo que SUENA como un término tuyo, término por término y siempre reversible",
            "Revierte lo aprendido desde Estadísticas, y apoya el proyecto con un cafecito ☕",
            "Precios por MODELO (no por proveedor) y editables: cada modelo con su costo real, y el gasto del mes se calcula por el modelo que de verdad se usó",
        ]),
        ("0.18.0", "2026-07-10", [
            "Pestaña Historial: todos tus dictados con buscador (sin distinguir tildes), escuchar el audio, copiar y abrir en Finder",
            "OpenAI y Mistral (Voxtral nube) ya funcionan de verdad: pon tu key en Modelos y actívalos en la cascada",
            "Descargas de modelos en segundo plano + botón ✕ para cancelarlas",
            "'Guardado ✓' al guardar la API key y ⌘V/⌘C funcionan en todos los campos",
        ]),
        ("0.17.2", "2026-07-10", [
            "Las API keys viven solo en la configuración de la app (adiós rutas de la máquina del desarrollador)",
            "Mensaje claro cuando falta la key: 'ponla en Configuración → Modelos'",
            "Instrucciones de primera apertura al día para macOS moderno",
        ]),
        ("0.17.1", "2026-07-10", [
            "La app trae TODOS los motores dentro: Voxtral Mini 3B ya no pide instalar nada (adiós brew) — descargar, arrastrar y dictar",
        ]),
        ("0.17.0", "2026-07-10", [
            "Conmutación de motor EN CALIENTE: cambia de IA a mitad del dictado y el motor nuevo retoma todo lo dicho — sin perder una palabra",
            "Selector rápido de proveedor: desde el menú de la barra o con un clic sobre el letrero del notch",
            "El log y las estadísticas nombran el motor exacto (Voxtral/Nemotron en vivo)",
            "btodicta.eztic.ec es la página oficial (en Créditos y README)",
        ]),
        ("0.16.7", "2026-07-10", [
            "Dictados seguidos con ElevenLabs ya no caen a Whisper: el cierre normal de un dictado exitoso contaba como fallo de red (falsa cuarentena)",
            "El plan B en vivo respeta TU orden de la cascada (Whisper #2 antes que Nemotron #3)",
            "Un dictado vacío ya no pega frases raras del pulido ('No hay transcripción para limpiar')",
        ]),
        ("0.16.6", "2026-07-10", [
            "Blindaje final contra el cierre inesperado al dictar con red lenta (doble arranque del grabador)",
        ]),
        ("0.16.5", "2026-07-10", [
            "El notch te dice con qué motor dictas: letrero encima del fn (verde = en vivo, gris = al soltar) que rota cuando el failover conmuta",
        ]),
        ("0.16.4", "2026-07-10", [
            "Failover TRANSPARENTE: el micrófono arranca al instante y si la nube no responde en 4s, el streaming local toma el mando con todo tu audio — sin esperas ni errores",
            "Si la red muere a MITAD del dictado, el audio completo se rescata por la cascada (ya no se pega un pedazo)",
            "Blindaje interno: 8 arreglos de concurrencia y ciclos de vida (dictados consecutivos rápidos, audio duplicado, cierres)",
        ]),
        ("0.16.3", "2026-07-10", [
            "Red caída sin drama: si el streaming falla, el próximo dictado graba directo (sin esperar 'Conectando…')",
            "La nube lenta ya no te frena: a los 15s salta al motor local automáticamente",
        ]),
        ("0.16.2", "2026-07-10", [
            "Micrófono fijado al integrado del Mac: el iPhone cercano (Continuity) ya no roba el micrófono y deja el dictado mudo",
            "Selector de micrófono en Ajustes (integrado / automático / cualquiera conectado)",
        ]),
        ("0.16.1", "2026-07-10", [
            "Release de prueba del actualizador: si estás leyendo esto desde la app, ¡la actualización con un clic funcionó! 🎉",
        ]),
        ("0.16.0", "2026-07-10", [
            "Actualización con un clic: la app revisa GitHub, descarga la versión nueva y se reinstala sola",
            "Botón 'Verificar actualización' junto a la versión",
        ]),
        ("0.15.0", "2026-07-10", [
            "Proveedores separados por familia: Voxtral, Nemotron y Canary, cada uno con su switch y su modelo",
            "Cascada de failover con arrastre (drag & drop) y etiquetas EN VIVO",
            "Instalador DMG y sistema de versiones visible",
        ]),
        ("0.14.0", "2026-07-10", [
            "Dictado EN VIVO 100% local: Voxtral Realtime 4B y Nemotron 3.5 Streaming (motor transcribe.cpp)",
            "Canary 1B Flash por lotes (93x tiempo real)",
            "Texto en vivo también con Whisper local (re-transcripción caliente)",
        ]),
        ("0.13.0", "2026-07-10", [
            "Voxtral Mini 3B local (llama.cpp) en la cascada",
            "Glosario universal: los términos llegan a TODOS los motores",
            "Ventana rediseñada con barra lateral escalable",
        ]),
        ("0.12.0", "2026-07-10", [
            "Whisper local residente bajo demanda: carga al dictar, se apaga solo a los 120s",
            "Rescate automático de dictados tras cierres inesperados",
            "Catálogo de modelos Whisper descargables y API keys por proveedor",
        ]),
        ("0.10.0", "2026-07-09", [
            "Failover multi-proveedor: ElevenLabs → Groq → Whisper local",
            "CRUD de glosario y reemplazos, estadísticas con gráficas, log total",
            "Transcripción de archivos y re-transcripción del historial",
        ]),
        ("0.7.0", "2026-07-09", [
            "Pausa real de música y videos al dictar (mediaremote-adapter)",
            "Firma estable: los permisos ya no se pierden al actualizar",
        ]),
        ("0.4.0", "2026-07-09", [
            "Esc cancela, sonidos, autoarranque, modo estudio",
            "Historial caja negra: audio y texto a disco mientras dictas",
        ]),
        ("0.1.0", "2026-07-09", [
            "Nace BtoDicta: fn para dictar, ElevenLabs Scribe, panel del notch",
        ]),
    ]
}
