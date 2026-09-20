# ADR 003 — La extensión entra por la API local, no levanta su propio canal

- Fecha: 2026-09-20
- Estado: Aceptada
- Spec: 006 — Extensión de navegador para la bitácora

## Contexto

Una extensión de navegador tiene que entregar a la aplicación lo que ve: qué
pestaña está activa, cuáles suenan, el texto de la página y su captura.

## Decisión

Se añade un punto de entrada, `POST /navegador`, a la API local que ya existe
(spec 005). Hereda sus seis cerraduras: apagada de fábrica, solo loopback, token
en archivo 0600 comparado en tiempo constante, rutas resueltas, cuerpo acotado y
límite de peticiones.

## Alternativa descartada: un canal propio de la extensión

Sería más simple de escribir por separado —un puerto suyo, un protocolo suyo— y
evitaría tocar código auditado.

Se descarta por lo mismo que la hace atractiva: sería **una segunda puerta**. Las
cerraduras de la spec 005 costaron una batería de pruebas negativas que encontró
un fallo real —la carpeta temporal del sistema estaba indebidamente permitida, lo
que abría los temporales de todas las aplicaciones—. Reproducir ese trabajo en un
canal nuevo significa reproducir también la oportunidad de equivocarse, y duplicar
lo que hay que mantener al día.

Una aplicación que vive en la barra de menús de un equipo con certificados de
firma no necesita dos puertas.

## Consecuencias

- La extensión no funciona si la API local está apagada. Es correcto: apagarla es
  la forma de cerrar todo de una vez.
- El punto nuevo comparte el límite de peticiones con las transcripciones. Si un
  consumidor externo satura la API, la extensión espera. Aceptado: la bitácora
  tolera un hueco; una transcripción perdida, no.
