# Plan 005 — API de transcripción para servicios externos

- Estado: Aprobado
- Fecha: 2026-09-19
- Aprobado por: Alberto — 2026-09-19 — autonomía dada para cerrar la spec entera
- Spec: `spec.md` (Aprobada 2026-09-19, nivel X)
- Rama: `main`

## 1. Forma del contrato

**HTTP en `127.0.0.1`, con token.** Decidido por Alberto el 2026-09-18.

```
POST /transcribir   { "archivo": "/ruta/audio.wav", "motor": "automatico",
                      "vocabulario": ["UEA", "EVA"] }
                  → { "texto": "…", "motor": "Fish Audio", "ms": 2740 }

POST /pulir         { "texto": "…" }
                  → { "texto": "…", "proveedor": "deepseek" }

GET  /estado      → { "version": "0.65.0", "motores": 23, "listo": true }
```

Cabecera `Authorization: Bearer <token>` en todas salvo `/estado`, que solo dice
si hay alguien escuchando.

## 2. Por qué no se usa un marco web

Se escribe sobre `Network.framework`, que ya está en la aplicación: el envío de
correo por SMTP lo usa. Meter una dependencia de terceros para servir tres rutas
en loopback añade superficie de actualización y de seguridad a cambio de nada.
Sale a `docs/adr/002`.

## 3. Las cinco cerraduras

El riesgo de esta funcionalidad no es que falle: es que abra una puerta. En esta
máquina hay certificados de firma y credenciales de veintitrés proveedores.

1. **Escucha solo en `127.0.0.1`.** No en `0.0.0.0`. Ni siquiera la red local
   llega.
2. **Token obligatorio**, generado al encender la función y guardado con permisos
   `0600` en `~/.btodicta/api-token`. Se compara en **tiempo constante**: una
   comparación normal filtra el token byte a byte por el tiempo que tarda.
3. **Rutas permitidas.** Solo se transcriben archivos dentro de las carpetas que
   el usuario autorice, y la ruta se resuelve antes de comprobar —si no, un
   `../../` se salta la comprobación—.
4. **Apagada de fábrica.** Quien no la use no tiene nada abierto.
5. **Tamaño acotado** del cuerpo de la petición, para que nadie llene la memoria
   mandando un JSON de un giga.

## 4. Qué se reutiliza tal cual

Nada de esto se reimplementa: la cascada de motores, el troceo por techo
aprendido, las cuarentenas, el vocabulario de contexto y la cadena de pulido.
La API es una puerta a lo que ya existe, no un camino paralelo — un camino
paralelo envejecería distinto y acabaría comportándose distinto.

El audio se pasa **por ruta**, aprovechando lo hecho en la spec 001: una
transcripción pedida desde fuera no carga el archivo en memoria.

## 5. Comprobación contra la constitución

- [x] **Nunca se entrega menos texto del que se dictó.** La API usa la misma
      cascada con sus reintentos y su troceo.
- [x] **La fluidez del usuario no se sacrifica.** El dictado tiene prioridad: si
      hay uno en curso, la petición externa espera. Es el mismo criterio que ya
      aplica la bitácora.
- [x] **Sin internet tiene que seguir funcionando.** Con `motor: "local"` no sale
      nada del equipo.
- [x] **El audio y el texto son del usuario.** No salen de la máquina salvo por
      los motores de nube que ya estaban configurados.
- [x] **Ninguna credencial en el repositorio.** El token se genera en la máquina
      y vive en `~/.btodicta`, nunca en el código ni en el registro.
- [x] **Nada se borra sin visto bueno.** La API no borra nada: ni acepta una
      operación de borrado.
- [x] **No es un servidor.** El MANIFIESTO excluye «servidor» y «sincronización
      entre equipos»: esto es una tubería entre procesos del mismo Mac, atada a
      `127.0.0.1`. Si algún día hace falta a distancia, será otra spec.
- [x] **Datos personales.** No se introduce ninguno nuevo.

Nivel X: prueba negativa por cada cerradura.

## 6. Riesgo mayor y cómo se prueba primero

**Que la puerta quede abierta sin que nadie se entere.** Fue exactamente lo que
pasó en otro proyecto de la oficina: un panel quedó sin contraseña porque se
confió en un código 200 y en el nombre de una variable, y se descubrió al leer el
contenido de la respuesta.

Por eso el orden empieza por las cerraduras, y cada una con su prueba negativa:

1. Las cinco cerraduras y su batería, antes de que el servidor transcriba nada.
2. Una petición sin token, con token equivocado, con una ruta fuera de las
   permitidas, con un recorrido de directorios, y desde una interfaz que no es
   loopback. Las cinco tienen que ser rechazadas.
3. Solo entonces, conectar la cascada.

## 7. Cómo se mide que quedó hecho

| RF / RNF | Medida |
|---|---|
| RF-01 | El mismo audio devuelve el mismo texto por la API que por la aplicación |
| RF-02 | El motor devuelto coincide con el pedido; con `automatico`, el salto queda en el registro |
| RF-03 | Un audio con siglas sale distinto con y sin vocabulario, y el correcto es el del vocabulario |
| RF-04 | 0 peticiones atendidas sin token válido y 0 desde fuera de `127.0.0.1` |
| RF-05 | Rutas fuera de lo permitido rechazadas, incluido un recorrido de directorios |
| RF-06 | El consumidor transcribe por nube sin leer `~/.btodicta/.env` |
| RF-07 | Pulir un texto por la API devuelve el mismo resultado que la aplicación |
| RF-08 | `grep` sobre el comando global no encuentra rutas internas |
| RNF-01 | ≤ 200 ms de arranque y ≤ 30 MB en reposo |
| RNF-02 | Un dictado de 60 s con una petición externa simultánea: 0 palabras perdidas |
| RNF-03 | Cuatro peticiones inválidas, cada una con su motivo nombrado |
| RNF-04 | Prueba negativa por cada cerradura |

## 8. Lo que este plan NO hace

- No sirve a otra máquina.
- No expone el TTS ni el modo agente.
- No transcribe en vivo por streaming para terceros.
- No mueve el comando global a este repositorio; lo reescribe para consumir la
  API, que es lo acordado.
