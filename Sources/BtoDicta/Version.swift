import Foundation

// MARK: - Versión de la app (UN solo lugar; actualizar aquí en cada release)
//
// La UI (sidebar, Créditos, menú) lee de aquí. El paquete lee su versión del
// Info.plist, que NO se inyecta desde aquí: hay que subir las dos a la vez
// (`CFBundleShortVersionString` y `CFBundleVersion`). `scripts/release.sh`
// compara ambas y no publica si difieren.

enum Version {
    static let numero = "0.56.2"
    static let fecha = "2026-09-13"

    /// Historial literal, la más nueva primero. Se muestra en Créditos.
    static let historial: [(version: String, fecha: String, cambios: [String])] = [
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
