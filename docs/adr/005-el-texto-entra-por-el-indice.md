# ADR 005 — El texto de la página entra por el índice ya hecho, sin tocar el OCR

- Fecha: 2026-09-20
- Estado: Aceptada
- Spec: 006 — Extensión de navegador para la bitácora

## Contexto

Hoy lo que se sabe de una página es el resultado de un OCR sobre una captura de
pantalla: caro en CPU y con errores de lectura. La extensión puede entregar el
texto real.

## Decisión

El texto llega al índice por `registrarPantalla`, **con su texto ya puesto**.
`ContinuoOCR.procesarPendientes` solo trabaja sobre lo que llega sin texto, así
que no lo toca. No se escribe una sola línea para «desactivar el OCR».

## Alternativa descartada: una bandera que apague el OCR para el navegador

Añadir un interruptor —«no hagas OCR de lo que venga de la extensión»— y
consultarlo en el bucle del OCR.

Se descarta porque sería **código nuevo para conseguir lo que el sistema ya hace
solo**. Cada bandera es una rama más que probar y un estado más que explicar, y
esta no añadiría comportamiento: solo repetiría la condición que el OCR ya evalúa.

## Consecuencias

- Menos CPU: las páginas leídas por la extensión no pasan por reconocimiento de
  imagen.
- Si la extensión deja de enviar texto, el OCR vuelve a ocuparse sin que nadie
  cambie nada. La degradación es automática.
