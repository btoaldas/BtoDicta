# Auditoría de corrección de errores — 2026-09-19

Compañera de la de seguridad. Aquella pregunta «¿puede entrar alguien?»; esta
pregunta **«cuando algo falla, ¿se entera alguien?»**.

Para una aplicación de dictado, el peor fallo no es el que avisa: es el que no
avisa. Grabar media hora contra un archivo que nunca se abrió, y descubrirlo al
buscar el dictado.

## Resumen

| | |
|---|---|
| Áreas revisadas | 5 |
| Hallazgos | **1** (alto) |
| Corregidos | 1, con prueba |
| Ya estaba bien | 4 áreas |

## Hallazgo (ALTO) — el contador de bytes mentía

`HistoryWriter` abre su archivo con `try?`. Si falla —disco lleno, permisos, un
volumen que se desconecta— `pcmHandle` queda vacío y **nadie lo dice**. A partir
de ahí:

```swift
func append(chunk: Data) {
    pcmHandle?.write(chunk)     // no hace nada, y no se queja
    bytesEscritos += chunk.count // pero el contador SUBE igual
}
```

`bytesEscritos` no es un dato cualquiera: es **la medida del dictado**, con la que
el resto de la aplicación decide si hubo algo que transcribir y cuánto duró. Con
el archivo cerrado, la aplicación creía tener treinta minutos de audio que no
existían en ninguna parte.

Además, escribir puede fallar **a mitad** aunque abrir haya ido bien: el disco se
llena mientras se dicta. Eso tampoco se veía.

**Corregido:**

- Si el archivo no se abre, se dice en el registro con esas palabras: «este
  dictado no se está guardando».
- El contador solo sube cuando la escritura **de verdad ocurrió**.
- Un fallo a mitad avisa **una vez**, no en cada trozo: hay cuarenta por minuto.
- El texto del dictado tampoco se pierde en silencio: sus dos escrituras avisan.

`BTODICTA_ESCRITURATEST` lo comprueba con un escritor sano y otro al que se le
quita el archivo por debajo, que es lo que pasa cuando el disco se llena.

## Lo que ya estaba bien

| Área | Comprobación | Resultado |
|---|---|---|
| Desempaquetado forzoso | 43 usos de `!` | Todos sobre literales o tras su guarda |
| `try!` | 12 usos | Todos son expresiones regulares con patrón literal: no pueden fallar en producción |
| `as!` | 2 usos | Los dos van precedidos de la comprobación de tipo (`CFGetTypeID`) |
| `mejor!` | 7 usos | Tras un cortocircuito `== nil ||`: seguro |
| Cascada de motores | Qué pasa si fallan todos | Devuelve el último error, y el audio queda guardado |

## Lo que esta auditoría NO cubre

- **Los 993 `try?` restantes**, uno a uno. Se revisaron los de los caminos
  críticos —escribir audio y texto del usuario—; los demás son cachés, ajustes y
  limpiezas donde tragarse el error es la respuesta correcta.
- **Qué pasa con el disco lleno de verdad**: se reprodujo cerrando el archivo,
  no llenando un disco.
- **Fallos del sistema de archivos a nivel de bloque**: corrupción silenciosa, un
  volumen que miente sobre lo escrito. Fuera del alcance de esta aplicación.
