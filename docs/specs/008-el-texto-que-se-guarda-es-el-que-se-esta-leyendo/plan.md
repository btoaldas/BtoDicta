# Plan técnico — Spec 008 El texto que se guarda es el que se está leyendo

- Estado: Aprobado
- Fecha: 2026-09-21
- Aprobado por: Alberto — 2026-09-21 — «vamos aprobado todo y sigue»
- Spec: ./spec.md (Aprobada 2026-09-21)

## 1. Enfoque en un párrafo

El guion de contenido deja de ser un disparo único y pasa a vivir lo que vive la
página: mantiene en memoria un **acumulado de lo que estuvo en pantalla**, y cada
vez que la persona se detiene en un sitio nuevo emite **solo el trozo nuevo**, no
el acumulado entero. `extraerTexto` aprende a distinguir lo visible de lo que no
lo está, y el presupuesto de caracteres se reparte entre lo visto (que nunca se
desaloja) y el relleno en orden de documento (que sí). En el lado de BtoDicta no
hace falta fusionar nada: cada trozo entra como su propia anotación, que es lo que
la spec pide, y para eso la bitácora deja de exigir que la dirección sea única —
conservando esa exigencia para los archivos de captura, que es donde sirve.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje y framework | JavaScript sin dependencias (extensión, Manifest V3) y Swift + SQLite C (app). El del MANIFIESTO; no hay apartamiento |
| Dependencias nuevas | ninguna |
| Almacenamiento | sí → ../009-buscar-por-palabras-en-la-bitacora/data-model.md (compartido: una sola migración) |
| Contrato de API | no cambia: mismo `POST /navegador`, mismos campos |
| Pruebas | unitarias en `extension/pruebas/correr.mjs` (RF-01, RF-02, RF-04); integración con la bitácora real para RF-03; comprobación de recuentos para RF-05 |
| Entornos afectados | local (es una app de escritorio); la bitácora del equipo es el dato de producción |

## 3. Comprobación contra la constitución

- [x] Respeta principios y límites del MANIFIESTO.md
- [x] Respeta el nivel X y los módulos declarados en ROADMAP.md
- [x] Tres capas separadas: la extensión es un sensor, BtoDicta decide qué anota
- [x] Si toca la API: no cambia el contrato; sigue tras el mismo token
- [x] Sin secretos en código
- [x] Datos personales marcados: el texto de las páginas ya lo era en la spec 006

## 4. Componentes y cambios

| Componente | Cambio | Archivos o rutas | RF que sirve |
|---|---|---|---|
| Extractor | Separar visible de no visible; devolver fragmentos con su posición, no una cadena ya cerrada | `extension/src/texto.js` | RF-01, RF-02 |
| Guion de contenido | Acumulador por página, escucha de desplazamiento con rebote, emisión incremental, tope de emisiones | `extension/src/contenido.js` | RF-01, RF-02, RNF-03 |
| Opciones | Campo para el máximo de caracteres por página, 20 000 de fábrica | `extension/src/opciones.html`, `opciones.js` | RF-04 |
| Anotador | Deja de descartar en silencio el segundo informe de una dirección | `Sources/BtoDicta/ContinuoIndice.swift` (`anotarTextoDeNavegador`) | RF-03 |
| Forma de la bitácora | Índice único **parcial** para archivos de captura, en lugar de la exigencia sobre toda dirección | migración conjunta, ver spec 009 | RF-03, RF-05 |
| Pruebas | Casos nuevos, cada uno visto en ROJO antes de arreglar | `extension/pruebas/correr.mjs` | todos |

## 5. Diagrama mínimo

```
página ──scroll (rebote 1,5 s)──> contenido.js
                                    │  acumulado en memoria: {visto[], relleno[]}
                                    │  emite SOLO lo nuevo que cabe
                                    ▼
                                  fondo.js ──POST /navegador──> ApiLocal
                                                                   │
                                                                   ▼
                                                        una anotación por trozo
```

## 6. Modelo de datos

Ver `../009-buscar-por-palabras-en-la-bitacora/data-model.md`. **La migración es
una sola y vive allí**: esta spec aporta el requisito de que una dirección pueda
repetirse; la 009 aporta el resto del cambio de forma.

## 7. Contrato

No cambia. `POST /navegador` sigue aceptando `url`, `titulo`, `texto`, `captura` y
la fotografía de pestañas. Lo único distinto es que ahora llegan varios informes
por página y cada uno trae un trozo, no el documento desde el principio.

## 8. Decisiones que requieren ADR

| Decisión | Alternativa descartada y por qué | ADR |
|---|---|---|
| Emisión **incremental**: cada informe lleva solo el trozo nuevo | Reenviar el acumulado entero en cada informe: con hasta 40 informes por página multiplicaría el mismo texto por 40 en la bitácora, justo lo que esta spec dice no hacer | `docs/adr/006-emision-incremental-del-texto-de-una-pagina.md` |
| **Reserva de presupuesto**: el primer informe llena como mucho el 30 % del máximo con relleno de orden de documento; el resto queda para lo que se lea | Llenar el tope de entrada: el acumulado quedaría completo antes del primer desplazamiento y ninguna re-lectura podría aportar nada — reproduce el fallo que se está corrigiendo | `docs/adr/007-reserva-de-presupuesto-en-el-primer-informe.md` |
| Índice único **parcial** sobre las rutas que no son direcciones web | Quitar la exigencia de unicidad del todo: perdería la protección real contra indexar dos veces el mismo archivo de captura | `docs/adr/008-forma-de-la-bitacora-indice-externo-y-unicidad-parcial.md` (compartido) |

## 9. Riesgos y cómo se prueban primero

| Riesgo | Cómo se despeja antes de construir encima |
|---|---|
| La visibilidad no se puede medir en una pestaña sin pintar | **Ya medido el 2026-09-21**: con el panel oculto el navegador informa alto de ventana 0 y ningún fragmento resulta visible. Es el caso límite declarado: no se re-lee |
| El goteo en páginas de desplazamiento infinito | Se construye primero el contador de emisiones y su prueba; sin ese tope no se enchufa la escucha |
| Varias anotaciones por página inflan la bitácora | Se mide un día real antes y después (RNF-04, 2 MB/día). La emisión incremental es lo que lo evita |
| Una prueba que nunca falla | **Cada prueba nueva se ve en ROJO** contra el código sin arreglar antes de fiarse de ella. Regla de la oficina, no opcional |

## 10. Estrategia de verificación

| RF | Cómo se demuestra | Segundo ángulo | Prueba negativa |
|---|---|---|---|
| RF-01 | Prueba con documento sintético de 178 000 caracteres y ventana simulada al 60 %: el texto emitido contiene lo visible | Bitácora real: leer un artículo largo por la mitad y consultar qué quedó anotado | Sin desplazarse: se emite una sola vez, como hoy |
| RF-02 | Presupuesto lleno con visto + relleno: se cuenta qué se desaloja | Inspección del acumulado tras 10 desplazamientos | Documento que cabe entero: no se desaloja nada |
| RF-03 | Dos informes de la misma dirección → dos anotaciones | Consulta a la bitácora por esa dirección | Antes de migrar: el segundo se descarta (estado actual, documentado) |
| RF-04 | Ajuste a 60 000 y medición de lo guardado | Recarga de la extensión: el valor persiste | Valor inválido o vacío: vuelve a 20 000, no rompe |
| RF-05 | Recuentos y sumas de texto antes y después de migrar | Ensayo sobre copia primero (spec 009, RF-06) | Migración interrumpida a propósito sobre la copia: el original intacto |

## 11. Complejidad justificada

| Pieza añadida más allá de lo simple | Por qué lo simple no basta |
|---|---|
| Acumulador con dos cubos (visto / relleno) | Un solo cubo en orden de documento es exactamente el comportamiento que falla hoy |
| Rebote y tope de emisiones | Sin ellos, una cronología de red social emite un informe por rueda de ratón |
| Reserva de presupuesto | Sin ella la re-lectura existe pero no cabe: el tope ya está lleno cuando llega |
