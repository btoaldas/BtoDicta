# Spec 009 — Buscar por palabras en la bitácora

- Estado: Aprobada
- Tipo: funcionalidad
- Nivel: X (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-21
- Modifica: ninguna
- Aprobada por: Alberto — 2026-09-21 — «resuelve aprobado te doy»
- Rama: main

## 1. Problema y propósito

La bitácora guarda 31 días de material —lo que se vio y lo que se dictó— y **no
hay forma de buscar en él**. El explorador solo lista lo reciente; la API local no
ofrece consulta; el agente no sabe responder «qué leí sobre esto». La propia
pantalla de ajustes ya promete la búsqueda que no existe: dice que el
reconocimiento rápido «basta para buscar por palabras sueltas».

Y el índice que la haría posible **ya está construido y se mantiene al día**:
57 403 anotaciones indexadas, 92,1 MB de los 177,2 MB de la bitácora. Nadie lo
consulta nunca. De esos 92,1 MB, **64,6 MB son una segunda copia del mismo texto**
que ya está guardado aparte — medido: 40,77 MB indexados frente a 41,05 MB
guardados, el mismo texto dos veces.

El propósito es que la búsqueda exista, que alcance también a lo que aporta la
extensión de navegador, y que el índice deje de duplicar lo que ya se guarda.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Persona que dicta | El dueño del equipo | Encuentra en segundos aquello que vio o dijo hace semanas y no recuerda dónde |
| Otros proyectos de la oficina | Lo que consume la API local | Pueden preguntar a la bitácora sin abrir la aplicación |
| BtoDicta | La aplicación de escritorio | Deja de pagar 64,6 MB por guardar dos veces lo mismo |

## 3. Alcance

### Incluye

- Buscar por palabras desde la pestaña de la bitácora.
- Buscar por la API local, con el mismo token que el resto.
- Preguntar por voz al agente y recibir respuesta.
- Que lo aportado por la extensión de navegador también se encuentre.
- Que el texto deje de guardarse dos veces.
- Conservar íntegra la bitácora ya grabada al cambiar la forma de guardarla.

### No incluye (con razón)

- **Búsqueda semántica o por significado.** Buscar por palabras cubre el caso real
  —«dónde vi esto»— y lo que hace falta ya está construido. Lo semántico pide
  vectores, un modelo cargado y una decisión de coste que hoy no toca.
- **Buscar dentro de las imágenes guardadas.** Se busca sobre el texto reconocido,
  no sobre los píxeles.
- **Cambiar la retención ni la purga.** Siguen igual: 90 días con purga automática.
- **Cambiar qué se guarda.** Esta spec cambia cómo se guarda y cómo se consulta.

## 4. Requerimientos funcionales

Formato de sw-requerimientos: actor, acción, resultado, medida. Máximo 12.

### RF-01 — Buscar por palabras desde la aplicación

- Actor: la persona que dicta
- Acción: escribe unas palabras en la pestaña de la bitácora
- Resultado: obtiene los momentos en que esas palabras aparecieron, con su hora,
  de dónde salieron y un fragmento que permita reconocerlos
- Medida: respuesta en menos de 300 ms sobre las 57 403 anotaciones indexadas hoy;
  ahora mismo la búsqueda tarda infinito porque no existe
- Prioridad: P1
- Criterio de aceptación:
  - Dado un material guardado hace tres semanas que contiene una palabra concreta
  - Cuando se escribe esa palabra en la pestaña de la bitácora
  - Entonces aparece ese momento con su hora y su origen, y se puede abrir

### RF-02 — Buscar por la API local

- Actor: otro programa de la oficina
- Acción: pregunta a BtoDicta por unas palabras, con el mismo token que ya usa
- Resultado: recibe los momentos que las contienen, sin abrir la aplicación
- Medida: la consulta responde con resultados comprobables contra los mismos que
  devuelve la aplicación; hoy ninguno de los modos que ofrece la API permite
  consultar lo guardado
- Prioridad: P2
- Criterio de aceptación:
  - Dado BtoDicta abierta y un token válido
  - Cuando otro programa pregunta por unas palabras
  - Entonces recibe los mismos momentos que vería la persona en la aplicación

### RF-03 — Preguntar por voz

- Actor: la persona que dicta
- Acción: le pregunta al agente en voz alta por algo que vio o dijo
- Resultado: el agente responde con lo que encuentra, diciendo cuándo fue y de
  dónde salió
- Medida: una pregunta hablada del tipo «qué leí sobre esto la semana pasada»
  devuelve al menos el momento correcto entre los primeros resultados
- Prioridad: P3
- Criterio de aceptación:
  - Dado un material guardado la semana pasada sobre un asunto concreto
  - Cuando se le pregunta al agente por ese asunto
  - Entonces contesta citando el momento, su hora y su origen

### RF-04 — Lo que aporta el navegador también se encuentra

- Actor: BtoDicta
- Acción: da de alta para la búsqueda el texto que entrega la extensión, igual que
  el que sale del reconocimiento de imagen
- Resultado: una página leída en el navegador se puede encontrar después por sus
  palabras
- Medida: de las 22 páginas que la extensión lleva aportadas, hoy **0** son
  encontrables; después, todas
- Prioridad: P1
- Criterio de aceptación:
  - Dado el caso de una página leída en el navegador y anotada por la extensión
  - Cuando se busca una palabra que solo aparece en esa página
  - Entonces la página figura entre los resultados

### RF-05 — El mismo texto deja de guardarse dos veces

- Actor: BtoDicta
- Acción: guarda el texto una sola vez y lo hace buscable sin copiarlo aparte
- Resultado: la bitácora ocupa mucho menos sin perder ni una palabra ni la
  capacidad de buscar
- Medida: la bitácora baja de 177,2 MB a 112,6 MB o menos, conservando los
  41,05 MB de texto de pantalla y los 7,33 MB de audio; en el estado estacionario
  de 90 días la diferencia proyectada es de unos 188 MB
- Prioridad: P1
- Criterio de aceptación:
  - Dado el archivo de bitácora actual, de 177,2 MB
  - Cuando se completa el cambio de forma
  - Entonces ocupa 112,6 MB o menos y toda búsqueda sigue encontrando lo mismo

### RF-06 — El cambio se ensaya antes de tocar lo real

- Actor: quien ejecuta el cambio
- Acción: corre el cambio entero sobre una copia de la bitácora antes que sobre la
  verdadera, y compara
- Resultado: los números que justifican tocar los datos reales se conocen de
  antemano, y si algo falla, falla sobre una copia
- Medida: recuento de anotaciones y suma de longitudes de texto idénticos entre la
  copia migrada y el original; 57 403 anotaciones indexadas, 0 perdidas
- Prioridad: P1
- Criterio de aceptación:
  - Dado un duplicado de la bitácora real
  - Cuando se corre el cambio completo sobre esa copia
  - Entonces los recuentos coinciden y el espacio recuperado es el medido, antes
    de que nadie toque la bitácora verdadera

## 5. Requerimientos no funcionales

Un RNF sin cifra es un deseo.

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Rendimiento | Una búsqueda responde en menos de 300 ms sobre 57 403 anotaciones | Cronómetro en la aplicación con el material real |
| RNF-02 | Capacidad | 0 MB de texto duplicado tras el cambio: el texto se guarda 1 vez | Comparación de tamaños antes y después con `dbstat` |
| RNF-03 | Seguridad | La búsqueda por la API exige el mismo token que el resto; 0 consultas atendidas sin él | Prueba negativa: consulta sin token y con token inválido |
| RNF-04 | Disponibilidad | El cambio de forma se ejecuta 1 vez, con BtoDicta parada, en una sola transacción y con respaldo previo verificado | Ensayo sobre copia y comprobación del respaldo |
| RNF-05 | Capacidad | Tras el cambio, indexar una anotación nueva no añade más de 1 copia de su texto al espacio ocupado | Medición del crecimiento por anotación antes y después |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| Búsqueda vacía o de una sola letra | No se busca y se dice por qué; no se recorren 57 403 anotaciones por un carácter | RF-01 |
| Palabras con tilde o en mayúsculas | Encuentran igual: el índice ya normaliza acentos y mayúsculas | RF-01 |
| Palabras que no aparecen en ningún sitio | Se dice que no hay resultados; nunca una lista vacía sin explicación | RF-01 |
| Consulta a la API sin token o con token inválido | Se rechaza, igual que el resto de modos de la API | RNF-03 |
| Búsqueda mientras la bitácora está escribiendo | Funciona: la bitácora está viva y sigue anotando durante la consulta | RF-01 |
| **El cambio de forma con BtoDicta abierta** | No se ejecuta: la bitácora escribe mientras tanto —se midieron 101 anotaciones nuevas en minutos— y migrar bajo escritura es corromper | RNF-04, RF-06 |
| El cambio se interrumpe a medias | La bitácora anterior queda intacta y el respaldo permite volver; nunca un estado a medio camino | RF-06 |
| La misma anotación se reconoce dos veces | Aparece **una** vez en los resultados. Hoy el alta en el índice no borra lo anterior, así que un segundo reconocimiento de la misma anotación la dejaría duplicada; no ha pasado —0 duplicadas medidas— pero el mecanismo lo permite y el cambio debe cerrarlo | RF-05 |
| Material guardado sin texto reconocido todavía | No aparece en los resultados hasta que se reconozca; no es un fallo | RF-01 |

## 7. Datos y cumplimiento

- Datos que trata: el texto que la bitácora ya guarda —lo reconocido de la pantalla
  y lo transcrito del audio—, en el equipo y sin salir de él.
- Datos personales: sí, los que ya contiene la bitácora. Esta spec **no añade ni un
  dato nuevo**: hace consultable lo que ya estaba guardado y deja de duplicarlo.
  Misma retención (90 días con purga automática) y mismo almacenamiento local. La
  consulta por la API queda tras el mismo token que el resto.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- El índice existente está sano: comprobado el 2026-09-21 — 28 549 anotaciones de
  pantalla y 28 753 de audio, **0 duplicadas y 0 huérfanas**.
- El texto completo sigue guardado aparte del índice, que es lo que permite
  reconstruirlo sin pérdida.
- **Migración conjunta con la spec 008.** Las dos reconstruyen lo mismo. Se
  ejecutan en **un solo paso**, con un respaldo, un ensayo sobre copia y una sola
  ventana de riesgo — decisión de Alberto del 2026-09-21. Si la 008 no se aprueba,
  esta spec se replantea el alcance de su cambio de forma.
- La ejecución sobre la bitácora real **requiere visto bueno propio y separado de
  Alberto** en el momento de correrla, con los números del ensayo delante, según la
  regla dura de la oficina.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-21

- P: ¿Se usa el índice o sobra? → R: **usarlo** — construir la búsqueda y convertir
  el índice para que deje de duplicar el texto (decisión de Alberto, sobre la
  medida de 92,1 MB de 177,2 MB sin ninguna consulta en todo el código).
- P: ¿Desde dónde se busca? → R: **las tres**: la pestaña de la aplicación, la API
  local y el agente por voz (decisión de Alberto). El agente queda como P3: es el
  más caro y el que menos se pierde si se aplaza.
- P: ¿Qué material entra? → R: **pantalla y audio** (decisión de Alberto). Los dos
  índices existen y los dos están igual de parados.
- P: ¿Se ensaya la migración sobre copia? → R: **sí, ensayo completo** antes de
  tocar la base real (decisión de Alberto), coherente con la lección de la oficina:
  el sitio donde probar nunca es el dato bueno.
- P: ¿Una migración o dos? → R: **una sola**, compartida con la spec 008: un
  respaldo, una ventana de riesgo, una verificación (decisión de Alberto).
