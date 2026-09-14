# Spec 001 — Memoria del dictado largo

- Estado: Borrador
- Tipo: funcionalidad
- Nivel: X (heredado del ROADMAP; lo fija sw-ciclo)
- Fecha: 2026-09-14
- Modifica: ninguna
- Aprobada por: PENDIENTE
- Rama: `spec/001-memoria-dictado-largo` (el nivel X obliga a rama propia)

## 1. Problema y propósito

El audio del dictado se conserva en memoria además de en disco: mientras grabas
hay dos copias completas y al transcribir hay tres. Son 32 000 bytes por segundo,
así que seis horas de dictado ocupan 691 MB por copia — **1 382 MB grabando y
2 074 MB al transcribir**, sobre los 265 MB que la aplicación ya usa en reposo.
Con eso, macOS puede matar el proceso por presión de memoria justo cuando toca
entregar. El audio no se perdería (se escribe a disco según llega), pero el
dictado no llegaría a texto en esa sesión. Cuando esto esté hecho, la memoria que
consume un dictado no dependerá de su duración.

## 2. Actores

| Actor | Quién es | Qué gana con esta funcionalidad |
|---|---|---|
| Quien dicta | Alberto y cualquiera que use la aplicación | Puede dictar seis horas seguidas y recibir el texto completo, sin notar nada distinto en un dictado corto |

## 3. Alcance

### Incluye

- Grabación: dejar de acumular el dictado completo en memoria.
- Entrega a los motores de transcripción desde el archivo, sin cargarlo entero.
- Red de seguridad y troceo: leer los tramos que necesiten del archivo.
- Medición de memoria y de latencia como criterio de aceptación.

### No incluye (con razón)

- La bitácora continua: ya escribe y comprime por trozos; su memoria no crece
  con el tiempo.
- El pulido por tramos: resuelto en 0.59.0, spec aparte si hiciera falta.
- Cambiar el formato de grabación (16 kHz, mono, 16 bits): tocarlo afectaría a
  todos los motores y a la calidad, y el problema no es el formato.

## 4. Requerimientos funcionales

### RF-01 — Dictar seis horas y recibirlo transcrito completo

- Actor: quien dicta
- Acción: graba un dictado de seis horas y suelta la tecla
- Resultado: recibe el texto de todo lo hablado, de principio a fin
- Medida: el texto entregado contiene el habla del primer y del último minuto
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado de seis horas
  - Cuando se suelta la tecla
  - Entonces se entrega el texto completo y la aplicación sigue viva

### RF-02 — La memoria no crece con la duración

- Actor: la aplicación
- Acción: graba y transcribe dictados de duración creciente
- Resultado: la memoria atribuible al audio se mantiene acotada
- Medida: la diferencia de memoria residente entre un dictado de seis horas y
  uno de cinco minutos no pasa de 200 MB
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado de cinco minutos y otro de seis horas
  - Cuando se mide la memoria residente en el momento de transcribir
  - Entonces la diferencia entre ambas es igual o menor a 200 MB

### RF-03 — Un dictado corto no se vuelve más lento

- Actor: quien dicta
- Acción: hace un dictado de cuarenta segundos, como cualquier día
- Resultado: recibe el texto en el mismo tiempo que antes de este cambio
- Medida: el tiempo entre soltar la tecla y recibir el texto no empeora más de
  un 10 % respecto a la medición previa del mismo motor y tamaño
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado de cuarenta segundos con el motor de nube habitual
  - Cuando se compara con la medición previa al cambio
  - Entonces el tiempo no sube más de un 10 %

### RF-04 — El audio sigue a salvo ante un cierre inesperado

- Actor: la aplicación
- Acción: muere a mitad de un dictado largo
- Resultado: el audio grabado hasta ese momento sigue en disco y se recupera
- Medida: el archivo contiene el audio hasta el instante del cierre y el rescate
  de huérfanos lo incorpora
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado en curso
  - Cuando el proceso termina de forma abrupta
  - Entonces al reabrir se recupera el audio y se transcribe

### RF-05 — La reparación de tramos sigue funcionando

- Actor: la red de seguridad del dictado
- Acción: repara un tramo que el motor en vivo se saltó o se dejó
- Resultado: lo hace leyendo del archivo, con el mismo resultado que antes
- Medida: las baterías `REDTEST2` y `PARTIRTEST` pasan sin cambios
- Prioridad: P1
- Criterio de aceptación:
  - Dado un dictado con un hueco detectado
  - Cuando se repara leyendo el audio del archivo
  - Entonces se recupera el mismo texto que con el audio en memoria

## 5. Requerimientos no funcionales

| ID | Dimensión | Requerimiento con cifra u observable | Cómo se mide |
|---|---|---|---|
| RNF-01 | Capacidad | Soporta un dictado de 6 h (691 MB de audio) sin que la memoria residente pase de 700 MB | `ps -o rss` durante el dictado sintético de 6 h |
| RNF-02 | Rendimiento | Leer un tramo de 25 MB del archivo tarda menos de 50 ms | Medición en la propia aplicación, registrada |
| RNF-03 | Disponibilidad | 6 de 6 baterías existentes en verde, 0 fallos, 0 pruebas omitidas | `PARTIRTEST`, `TROCEOTEST`, `CRONOTEST`, `FISHTEST`, `REDTEST2`, `ROBUSTEZTEST` |
| RNF-04 | Usabilidad | 0 avisos nuevos, 0 preguntas al usuario y 0 pasos añadidos al dictado | Revisión de la interfaz antes y después |

## 6. Casos límite y fallos

| Situación | Comportamiento esperado | RF |
|---|---|---|
| El disco se queda sin espacio a mitad de un dictado de horas | Se avisa y se conserva lo grabado hasta ahí; no se pierde lo anterior | RF-04 |
| El archivo del dictado no se puede leer al ir a transcribir | Se entrega lo que haya en memoria antes que nada; nunca se entrega vacío en silencio | RF-01 |
| Se va el internet a mitad de la grabación | La grabación continúa igual y al terminar la cascada cae a un motor local | RF-01 |
| Seis horas superan el techo de todos los motores de nube | El troceo de 0.59.0 las parte y las cose; la memoria sigue acotada porque los tramos se leen del archivo de uno en uno | RF-02 |
| El equipo tiene poca memoria libre | La aplicación no acumula, así que no compite: el consumo es el mismo que con un dictado corto | RF-02 |

## 7. Datos y cumplimiento

- Datos que trata: audio de voz y su transcripción, del propio usuario, en su
  equipo.
- Datos personales: sí — la voz lo es. No cambia nada respecto a hoy: el audio
  ya se escribe en `~/BtoDicta Bitácora` y en el historial del usuario, no sale
  del equipo salvo al motor de nube que él eligió con su clave. Sin base de
  datos nueva, sin retención nueva, sin terceros nuevos.
- Cobra o factura: no.

## 8. Supuestos y dependencias

- El audio del dictado ya se escribe a disco según llega (`HistoryWriter`), y el
  rescate de huérfanos ya existe. Esta spec **aprovecha** esa escritura; no la
  añade.
- Medido en el equipo de referencia: leer 25 MB del archivo recién escrito tarda
  1 ms, frente a los ~23 000 ms que tarda la llamada de transcripción que viene
  después. El disco no puede ser el cuello de botella.
- `URLSession` sabe transmitir desde un archivo sin cargarlo en memoria.
- El banco de pruebas con voz sintética (0.58.0) permite generar seis horas de
  dictado sin que nadie tenga que hablar seis horas.

## 9. Decisiones y aclaraciones

### Sesión 2026-09-14

- P: ¿Hasta qué duración hay que aguantar? → R: seis horas — «hagámosle de una
  vez para seis horas de grabación» (decisión del responsable del producto)
- P: ¿Se crean `ROADMAP.md` y `MANIFIESTO.md` para poder abrir la spec? → R: sí
  (decisión del responsable del producto)
- P: ¿Leer del disco no será más lento que la memoria? → R: preocupación
  registrada del responsable del producto — «no podemos sacrificar la
  eficiencia, la garantía y la disponibilidad del sistema por memoria». Se
  midió: 1 ms leer un tramo frente a 23 000 ms de la llamada siguiente. Queda
  como RF-03 y RNF-02, con cifra y prueba, en vez de como promesa.
- P: ¿Nivel X o P? → R: [PENDIENTE DE DECISIÓN: el responsable del producto pidió que se le explicara la diferencia; recomendación argumentada: X]
