# Plan 006 — Extensión de navegador para la bitácora

- Estado: Aprobado
- Fecha: 2026-09-20
- Aprobado por: Alberto — 2026-09-20 — «aprobado, dale con las tareas»
- Spec: `spec.md` (Aprobada 2026-09-20, nivel X)
- Rama: `main`

## 1. La forma del sistema

La extensión **no es un cliente más de la API**: es un sensor. Solo observa y
empuja lo que ve a la aplicación, que sigue decidiendo todo.

```
Navegador (Chrome/Edge/Brave/Firefox)
  └─ extensión ──POST /navegador──▶ BtoDicta (127.0.0.1:8787)
       · pestaña activa (url, título)        │
       · pestañas audibles                    ├─▶ FiltroBitacora   (RF-01)
       · texto de la página                   ├─▶ ContinuoIndice   (RF-02)
       · captura de la pestaña                └─▶ carpeta de bitácora (RF-03)
```

Un solo punto de entrada nuevo, `POST /navegador`, sobre la API que ya existe
(spec 005) con su token y su cerradura de loopback. No se abre ningún puerto más.

## 2. Qué se reutiliza tal cual

Nada de esto se reimplementa:

- **La API local** con sus seis cerraduras. El punto nuevo hereda token,
  loopback, tope de cuerpo y límite de peticiones.
- **`FiltroBitacora`** (0.74) decide qué entra. La extensión solo le da mejores
  datos: hoy adivina por foco y dirección; con esto sabrá qué suena de verdad.
- **`ContinuoIndice.registrarPantalla(ruta:instante:app:ventana:)`** ya acepta
  app y ventana. El texto de la extensión entra por ahí **con su texto ya
  puesto**, y por eso `ContinuoOCR.procesarPendientes` —que solo trabaja sobre lo
  que llega sin texto— no lo tocará. Ese es todo el cambio para el RF-02: no hay
  que desactivar el OCR, basta con no darle trabajo.
- **La papelera de la bitácora** (0.74) para lo que el filtro aparte.

## 3. La extensión

**Manifest V3, un solo código fuente, dos empaquetados.** Chrome, Edge y Brave
comparten motor y aceptan el mismo paquete sin cambios (RF-06). Firefox usa la
misma API bajo el espacio `browser.*` y admite Manifest V3, pero exige su propio
empaquetado y su propia firma (RF-07); se resuelve con una capa fina que mapea
`chrome.*` a `browser.*` y dos ficheros de manifiesto, no con dos códigos.

Permisos, y ninguno de más:

| Permiso | Para qué | Sin él |
|---|---|---|
| `tabs` | pestaña activa y `audible` | No hay RF-01 |
| `scripting` + `activeTab` | leer el texto de la página | No hay RF-02 |
| `<all_urls>` | leer en cualquier sitio, que es lo que pidió Alberto | Habría que autorizar dominio a dominio |

`captureVisibleTab` cubre el RF-03 sin permiso adicional más allá de los
anteriores.

## 4. Las cerraduras de este sensor

El riesgo aquí no es que falle: es que **vea de más**. La decisión fue «leer todo
salvo lo que excluya», que es la postura con más superficie, así que las
protecciones van en el lado de la extensión y no en el de la aplicación:

1. **Nunca se leen campos de contraseña ni valores de formulario** (RNF-03). Se
   extrae texto del documento excluyendo `input`, `textarea` y `[contenteditable]`.
   No es configurable: no hay caso de uso legítimo para lo contrario.
2. **Lista de dominios excluidos** (RF-05), consultable y editable desde la propia
   extensión, para que excluir algo cueste dos clics y no una visita a un archivo
   de configuración. Con la postura elegida, la velocidad de excluir importa.
3. **Sin acumulación**: si la aplicación no responde, se descarta y se reintenta
   como mucho una vez por minuto (RNF-04). La extensión **no es un almacén**.
4. **El token no viaja en la URL** ni queda en el historial: va en la cabecera.

## 5. Comprobación contra la constitución

- [x] **El audio grabado no se pierde nunca.** Esto no toca el audio.
- [x] **Nunca se entrega menos texto del que se dictó.** No toca el dictado.
- [x] **La fluidez del usuario no se sacrifica.** RNF-02 acota el coste en el
      navegador; si la extensión falla, la bitácora sigue como hoy (RF-04).
- [x] **Sin internet sigue funcionando.** Todo es local, `127.0.0.1`.
- [x] **El audio y el texto son del usuario.** El destino es su propia máquina.
- [x] **Ninguna credencial en el repositorio.** El token se lee de
      `~/.btodicta/api-token` y lo pega el usuario en la extensión.
- [x] **Nada se borra sin visto bueno.** La extensión no borra; lo apartado va a
      la papelera.
- [x] **No es un servidor.** No se abre puerto nuevo.
- [x] **Datos personales:** sí, y marcados en la spec §7. No salen del equipo.

Nivel X: prueba negativa por cada cerradura.

## 6. Decisiones con alternativa descartada

Salen a `docs/adr/`:

- **ADR-003 — Un punto de entrada nuevo en la API local, no un servidor propio de
  la extensión.** Alternativa descartada: que la extensión levantase su propio
  canal. Se descarta porque duplicaría las cerraduras ya auditadas de la spec 005
  y abriría una segunda superficie que mantener.
- **ADR-004 — Un código fuente con dos empaquetados, no dos extensiones.**
  Alternativa descartada: proyectos separados para Chromium y Firefox. Se descarta
  porque el 95 % del código es idéntico y dos copias divergen; lo que difiere es
  el manifiesto y la firma.
- **ADR-005 — El texto entra por el índice con el texto ya puesto, en vez de
  desactivar el OCR.** Alternativa descartada: una bandera que apague el OCR para
  páginas del navegador. Se descarta porque el OCR ya ignora lo que trae texto:
  añadir la bandera sería código nuevo para lograr lo que el sistema hace solo.

## 7. Riesgo mayor y cómo se prueba primero

**Que la extensión mande a la bitácora algo que no debía**: una contraseña, un
extracto bancario, una página que el usuario creía privada. Es el riesgo que
justifica el orden de las tareas.

Por eso no se empieza por lo vistoso. El orden es:

1. El punto de entrada con su token y sus rechazos, y **sus pruebas negativas**,
   antes de que la extensión exista.
2. La extracción de texto **con la exclusión de contraseñas y formularios**, y su
   prueba negativa sobre un formulario de acceso real, antes de enviar nada.
3. La lista de dominios excluidos, antes de leer de forma continua.
4. Solo entonces: pestañas audibles, texto continuo y capturas.

Es el mismo criterio que la spec 005: primero las cerraduras, después la
funcionalidad. Allí funcionó — una batería de pruebas negativas encontró que
`/var/folders` estaba indebidamente en las carpetas permitidas.

## 8. Cómo se mide que quedó hecho

| RF / RNF | Medida |
|---|---|
| RF-01 | Con un vídeo sonando y el correo al frente, la respuesta dice activa=correo y audible=vídeo, en < 2 s |
| RF-02 | El texto recibido de un artículo contiene ≥ 90 % de las palabras que da el OCR de esa pantalla |
| RF-03 | La captura de una ventana tapada muestra la página entera y nada de la ventana superpuesta |
| RF-04 | Con la extensión desinstalada, `qa-paquete.sh` pasa igual que hoy (22 pruebas) |
| RF-05 | Con un dominio excluido: 0 envíos de texto y 0 de imagen de ese dominio |
| RF-06 | El mismo paquete carga y reporta en Chrome, Edge y Brave |
| RF-07 | El paquete de Firefox reporta pestaña activa y audibles |
| RNF-01 | Petición sin token → 401; desde una IP que no es loopback → sin respuesta |
| RNF-02 | 10 páginas con y sin extensión: < 50 ms de diferencia al cargar y < 30 MB de memoria |
| RNF-03 | Formulario con usuario y contraseña: el cuerpo enviado no contiene ninguno de los 2 valores |
| RNF-04 | 10 min con BtoDicta cerrada: ≤ 10 intentos y almacenamiento de la extensión en 0 |

## 9. Lo que este plan NO hace

- No publica en ninguna tienda de extensiones.
- No modifica páginas, no bloquea contenido, no automatiza navegación.
- No sustituye la captura de pantalla del sistema: la complementa dentro del
  navegador, y fuera de él todo sigue igual.
- No cambia el filtro de la bitácora (0.74-0.75): le da mejores datos.
