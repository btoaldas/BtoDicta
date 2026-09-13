# Camino feliz

Marca un caso como aprobado solo si el resultado visible **y** el registro coinciden.
Los textos “QA” se pueden borrar al terminar.

| ID | Di exactamente | Resultado esperado | Evidencia clave |
|---|---|---|---|
| CF-01 | `Este es un dictado normal para comprobar que BtoDicta no inventa ninguna acción.` | Pega el texto pulido en el campo activo; no abre apps ni llama al agente. | `dictado_inicio`, `dictado_cierre`; sin `plan_autonomo`. |
| CF-02 | Activa con la pulsación configurada, dicta `Prueba de activación por función` y detén. | Una o doble Fn respeta Ajustes; una sola Fn siempre detiene. | Notch abre/cierra una vez. |
| CF-03 | `Oye <AGENTE>`; espera la respuesta; luego `Dime mis tareas de hoy`. | Responde “te escucho” y abre una sola escucha agéntica para el segundo turno. | `activacion_reposo_acuse` y luego `activacion`. |
| CF-04 | `Oye <AGENTE>, ¿cómo está la computadora?` | Informa batería, disco, CPU, memoria, red y VPN; si no hay VPN lo dice sin fallar. | `plan` + `resultado_herramienta`. |
| CF-05 | `Modo traducir inglés, buenos días equipo.` | El notch cambia a Traducir, traduce y al siguiente dictado vuelve visual y funcionalmente a Dictado. | `resolucion`/`despacho`; siguiente `modo_visual=dictado`. |
| CF-06 | `Modo traducir quichua, ¿cómo estás?` | Traduce a quichua o explica que el proveedor no pudo; nunca imprime el comando. | Idioma `quichua` en `resolucion`. |
| CF-07 | `Modo traducir inglés correo, mañana nos reunimos a las ocho.` | Traduce y prepara un correo; no lo envía. | `cadena`, etapas traducir→correo. |
| CF-08 | `Resume, traduce al inglés y envía por correo y por WhatsApp a Andrés: mañana nos reunimos a las ocho.` | Modal claro con las etapas; una Fn confirma; prepara ambos destinos según política, sin autoenviar. | `confirmacion_presentada`, `plan_si`, `plan`. |
| CF-09 | `Por favor, ayúdame a traducir lo siguiente: Necesito encontrar una forma de hacer algo bueno.` | Pregunta si deseas traducir; una Fn confirma. | Fuente natural/gramatical en `resolucion`. |
| CF-10 | Repite CF-09 y pulsa `X`. | Descarta la propuesta y pega/procesa como dictado normal; X no cancela el texto. | `plan_no`; continúa entrega normal. |
| CF-11 | `Anótame una tarea: revisar el Zentrix mañana a las ocho de la mañana.` | Crea una tarea local con fecha/hora 08:00 y aviso habilitado. | Tareas y Notas + registro de guardado local. |
| CF-12 | `Oye <AGENTE>, recuérdame mañana a las ocho de la noche llamar a Rafael.` | Crea Recordatorio con 20:00, no 12:00. | `resultado_herramienta` con fecha verificada. |
| CF-13 | `Oye <AGENTE>, crea un evento de reunión mañana a las diez de la mañana.` | Crea evento a las 10:00 mediante EventKit. | Resultado real de calendario. |
| CF-14 | `Necesito que guardes una nota: QA, revisar el informe del viernes.` | Guarda una nota dentro de BtoDicta, no abre Notas de Apple. | `guardado_local`, tipo nota. |
| CF-15 | `Oye <AGENTE>, crea una nota de Apple titulada QA Compras: pan, café y arroz.` | Crea una nota con título y lista legible. | `resultado_herramienta`; nota visible en Apple Notes. |
| CF-16 | `Oye <AGENTE>, abre Outlook y escribe un correo para equipo@example.com, asunto reunión, cuerpo: nos vemos mañana.` | Abre un borrador con Para, Asunto y Cuerpo; no envía. | `borrador_correo` con campos verificados. |
| CF-17 | `Oye <AGENTE>, abre Word y crea un oficio completo solicitando apoyo para los juegos internos.` | Crea documento nuevo con párrafos/saltos y formato legible, no una sola línea. | `aplicacion` y resultado del documento. |
| CF-18 | `Oye <AGENTE>, busca el archivo informe final y muéstrame todos los resultados en Finder.` | Finder muestra una búsqueda cuyo criterio contiene “informe final”; no sugerencias arbitrarias. | `resultado_herramienta`/ruta o búsqueda. |
| CF-19 | `Oye <AGENTE>, haz una captura de una sección, guárdala en Descargas con el nombre informe, cópiala y ábrela.` | Pide seleccionar área; oculta notch; crea `informe.png`, copia y abre. | `captura_solicitud`, `captura_mac`, ruta. |
| CF-20 | `Oye <AGENTE>, graba la pantalla durante 15 segundos con micrófono y guarda en Documentos.` | Oculta notch, graba 15 s, guarda con extensión de video y muestra resultado persistente “Ver en Finder”; no habla durante la grabación. | `grabacion_continua_inicio/fin`, ruta existente. |
| CF-21 | `Oye <AGENTE>, graba la pantalla hasta que yo la detenga y guarda en Documentos.`; luego Fn una vez. | Graba por segmentos recuperables; una Fn detiene; une/guarda el archivo y muestra ruta. | `grabacion_parte_*`, `grabacion_detener_ui`. |
| CF-22 | `Oye <AGENTE>, envía por WhatsApp a Andrés: mensaje QA, nos vemos mañana.` | Si hay varios Andrés, muestra selector; abre el elegido y pega texto sin enviarlo. | `whatsapp` con coincidencias y destinatario. |
| CF-23 | `Oye <AGENTE>, toma una captura y prepárala por WhatsApp para Andrés.` | Captura y pega la imagen en el chat; con autoenvío apagado queda en el input. | `captura_whatsapp_pegar`, nunca `autoenviar`. |
| CF-24 | `Oye <AGENTE>, pon música.` | Inicia una selección aleatoria; en arranque frío espera a Apple Music y no se limita a reanudar una pista incorrecta. | `musica` o `musica_failover` razonado. |
| CF-25 | `Oye <AGENTE>, reproduce en Spotify música andina.` | Si Spotify está instalado, busca “música andina” y reproduce un resultado; si no, usa el failover configurado. | Proveedor y consulta en `musica`. |
| CF-26 | `Oye <AGENTE>, modo música interno, reproduce Julio Jaramillo.` | Reproductor interno busca y reproduce; Play/Pausa/Anterior/Siguiente funcionan; Detener no arranca otra pista. | Evento `musica`, proveedor interno. |
| CF-27 | `Oye <AGENTE>, ¿qué clima hace hoy en Quito, Pichincha, Ecuador?` | Da clima de Quito con fuente/fecha; no necesita GPS por ciudad explícita. | Resultado de herramienta clima. |
| CF-28 | `Oye <AGENTE>, pon el volumen al setenta y cinco por ciento.` | Volumen queda en 75 % y responde brevemente. | Acción volumen + evidencia real. |
| CF-29 | Mientras el asistente habla, pulsa Fn y di `Ahora dime solo la primera tarea.` | Interrumpe voz/proceso anterior y escucha el nuevo turno sin mezclar respuestas tardías. | Cancelación/barge-in y token nuevo. |
| CF-30 | Recorre Ajustes y posa el puntero sobre cinco botones sin texto, luego `Buscar actualización`. | Tooltips aparecen rápido; el actualizador informa versión o error claro sin quedar bloqueado. | Interfaz usable y log del actualizador. |
