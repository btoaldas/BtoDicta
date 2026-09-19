# ADR 002 — La API local se escribe sobre Network.framework

- Fecha: 2026-09-19
- Estado: Aceptada
- Spec: 005 — API de transcripción para servicios externos

## Contexto

Hay que servir tres rutas HTTP en loopback para que otros programas del equipo
puedan pedir una transcripción.

## Decisión

Se escribe sobre `Network.framework`, que ya está en la aplicación: el envío de
correo por SMTP lo usa.

## Alternativa descartada: un marco web de terceros

Es lo cómodo y lo que se haría sin pensarlo. Se descarta porque el trabajo real
aquí no es enrutar peticiones —son tres rutas— sino **no abrir una puerta**: en
esta máquina hay certificados de firma y credenciales de veintitrés proveedores.

Una dependencia externa añade superficie que hay que vigilar y actualizar, y con
ella una promesa implícita de mantenerla al día durante años. A cambio ahorra
unas doscientas líneas que además queremos leer con lupa, porque son justamente
las que deciden quién entra.

## Consecuencias

- Hay que analizar HTTP a mano: cabeceras, `Content-Length` y el corte entre
  cabeceras y cuerpo. Es poco y está acotado, pero es código propio que puede
  tener errores propios.
- El primer intento tuvo uno: el puerto se le pasaba a `NWListener` dos veces —en
  los parámetros y en `on:`— y el oyente ni se creaba. El mensaje que salía
  («no pude abrir el puerto») mandaba a buscar un conflicto inexistente. Ahora el
  error del sistema se registra tal cual.
- El segundo fue el análisis de cabeceras: partir por `:` con `split` fallaba, y
  el token no se leía aunque viajara bien. Se reescribió buscando el prefijo de
  la línea, que es lo que soporta los `\r\n` y los valores con dos puntos
  (`Host: 127.0.0.1:8787`).
- No se admite HTTPS, y no hace falta: el tráfico no sale de la máquina.
