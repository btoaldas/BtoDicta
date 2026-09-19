# Verificación 005 — API de transcripción para servicios externos

- Fecha: 2026-09-19
- Versión: 0.65.0
- Nivel X: prueba negativa por cada cerradura

## Lo que importa: las cerraduras

El riesgo de esta funcionalidad nunca fue que fallara, sino que dejara una puerta
abierta sin que nadie se enterara. Las cinco se comprueban con `BTODICTA_APITEST`
y, además, con peticiones reales por HTTP.

| Cerradura | Prueba negativa | Resultado |
|---|---|---|
| Apagada de fábrica | Sin configuración previa, `activa()` | **false** |
| Solo loopback | `curl` a la IP de la red (192.168.0.185:8787) | **no responde** |
| Token | Petición sin cabecera, con token inventado, con el anterior tras regenerar | **rechazadas las tres** |
| Rutas | `/etc/hosts`, `/tmp/../etc/passwd`, carpeta con el mismo prefijo de nombre | **rechazadas las tres** |
| Tamaño | Tope de 1 MB en el cuerpo | **acotado** |

El token se compara en **tiempo constante**: una comparación normal se detiene en
el primer byte distinto, y esa diferencia permite adivinarlo byte a byte.

La comprobación de rutas **resuelve antes de comparar**. Sin eso,
`/var/folders/…/../../../etc/passwd` empieza por una carpeta permitida y acaba
donde no debe. Y se compara con barra final, para que una carpeta que solo
comparte prefijo de nombre no cuele.

Un rechazo anota el motivo, **nunca el token recibido ni la ruta pedida**:
dejarlos en el registro filtraría justo lo que se protege.

## RF por RF

| RF | Veredicto | Evidencia |
|---|---|---|
| RF-01 transcribir desde otro proceso | **Cumple** | Audio sintético por HTTP → «Probando la interfaz local de … con la Universidad Estatal Amazónica», Fish Audio, 3 296 ms |
| RF-02 elegir motor | **Cumple** | `"motor":"local"` → Voxtral local en 1 812 ms; `automatico` → Fish Audio. El motor devuelto coincide con el pedido |
| RF-03 vocabulario de contexto | **Cumple** | Los términos de la petición entran al glosario **solo durante esa petición**: el glosario del usuario no se toca |
| RF-04 nadie sin autorización | **Cumple** | Ver tabla de cerraduras |
| RF-05 no se leen rutas arbitrarias | **Cumple** | Ver tabla de cerraduras |
| RF-06 las credenciales no salen | **Cumple** | El consumidor manda una ruta y recibe texto; nunca toca `~/.btodicta/.env` |
| RF-07 pulir por el contrato | **Cumple** | «esto es una prueba de pulido sin puntuacion» → «Esto es una prueba de pulido, sin puntuación ni mayúsculas, a ver qué hace.», DeepSeek V4.1 Flash |
| RF-08 el comando global deja de conocer las tripas | **Pendiente** | Ver desviaciones |

## Requerimientos no funcionales

| ID | Umbral | Medido | Veredicto |
|---|---|---|---|
| RNF-01 | ≤ 200 ms de arranque, ≤ 30 MB en reposo | Un oyente TCP parado; sin diferencia apreciable en `MEMTEST` | Cumple |
| RNF-02 | Un dictado no pierde nada con una petición a la vez | La API usa la misma cascada, que ya cede ante el dictado | Cumple |
| RNF-03 | Cada rechazo dice su motivo | Siete motivos distintos, cada uno en una frase | Cumple |
| RNF-04 | Prueba negativa por cerradura | 16 comprobaciones en `APITEST`, todas negativas salvo tres de control | Cumple |

## Segundo ángulo

Las cerraduras no se dan por buenas con la batería interna: se comprobaron
**desde fuera**, con `curl`, contra el proceso real escuchando. `lsof` confirma
que el puerto está atado a `127.0.0.1` y no a todas las interfaces:

```
BtoDicta  67357  bto  5u  IPv4  TCP 127.0.0.1:8787 (LISTEN)
```

## Desviaciones respecto al plan

**RF-08 queda fuera de esta entrega.** Reescribir el comando global
`transcribir` para que consuma la API exige tocar un archivo que vive **fuera de
este repositorio** (`~/.local/bin`, documentado en el skill `transcribir`). La
API ya está y el contrato es estable, así que el comando se puede reescribir
cuando se quiera; hacerlo desde aquí sería modificar herramientas de la máquina
por cuenta propia. Queda anotado, no olvidado.

## Riesgos residuales

1. **El token es un secreto en un archivo.** Quien pueda leer `~/.btodicta` puede
   usar los motores y gastar saldo. Es el mismo nivel de protección que `.env`,
   que ya vive ahí.
2. **La puerta está cerrada de fábrica**, pero una vez abierta lo está para
   cualquier proceso del usuario que encuentre el token. No hay identidad por
   consumidor: no existe «quién» pidió, solo «alguien con el token».
3. **Sin límite de peticiones.** Un consumidor con un bucle puede gastar saldo de
   nube deprisa. El aviso de saldo bajo avisa, pero después.
4. **El puerto puede estar ocupado.** Si otro programa tiene el 8787, la API no
   arranca y lo dice en el registro; hay ajuste para cambiarlo, pero no busca uno
   libre sola.
