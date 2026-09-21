# Plan técnico — Spec 009 Buscar por palabras en la bitácora

- Estado: Borrador
- Fecha: 2026-09-21
- Aprobado por: PENDIENTE
- Spec: ./spec.md (Aprobada 2026-09-21)

## 1. Enfoque en un párrafo

El índice ya existe y está sano; lo que falta es consultarlo y dejar de pagar por
la copia de texto que arrastra. Se recrea como índice **de contenido externo**
—apunta al texto ya guardado en vez de copiarlo— y se pone al día solo, mediante
disparadores en las tablas base, lo que de paso mete dentro el texto del navegador
y cierra la posibilidad de indexar dos veces lo mismo. Encima de eso, **una sola
función de búsqueda** en el índice, y tres maneras de llamarla: la pestaña de la
bitácora, la API local y el agente. La migración es la misma de la spec 008 y está
descrita en `data-model.md`.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje y framework | Swift + SQLite C y SwiftUI. El del MANIFIESTO |
| Dependencias nuevas | ninguna — FTS5 ya está en el SQLite del sistema y ya se usa |
| Almacenamiento | sí → ./data-model.md |
| Contrato de API | cambia: un modo de consulta nuevo → ./contracts/README.md |
| Pruebas | unitarias de la función de búsqueda; integración contra una copia de la bitácora real; prueba negativa de token para la API |
| Entornos afectados | local; la bitácora del equipo es el dato de producción |

## 3. Comprobación contra la constitución

- [x] Respeta principios y límites del MANIFIESTO.md
- [x] Respeta el nivel X y los módulos declarados en ROADMAP.md
- [x] Tres capas: la búsqueda vive en el índice, no en la vista; las tres entradas
      llaman a la misma función
- [x] Si toca la API: mismo token, mismo formato de error, resultados acotados
- [x] Sin secretos en código
- [x] Datos personales: los que ya contiene la bitácora; no se añade ninguno nuevo

## 4. Componentes y cambios

| Componente | Cambio | Archivos o rutas | RF que sirve |
|---|---|---|---|
| Índice | Recrear como contenido externo, con disparadores que lo mantienen | migración, ver `data-model.md` | RF-04, RF-05 |
| Anotador | Quitar el alta manual en el índice, que con disparadores sería doble | `Sources/BtoDicta/ContinuoIndice.swift` (`anotarTexto`) | RF-05 |
| Purga | Quitar el borrado manual del índice, que pasa a ser automático | `ContinuoIndice.swift` (~línea 660) | RF-05 |
| Búsqueda | Función nueva: palabras → momentos con hora, origen y fragmento | `ContinuoIndice.swift` | RF-01 |
| Pestaña | Campo de búsqueda en el explorador, que hoy solo lista lo reciente | `Sources/BtoDicta/ContinuoView.swift` | RF-01 |
| API local | Modo de consulta nuevo tras el mismo token | `Sources/BtoDicta/ApiLocal.swift` | RF-02 |
| Agente | Modo para preguntar por lo guardado | `Sources/BtoDicta/AgenteNucleo.swift`, `Modos.swift` | RF-03 |
| Ayuda de ajustes | La frase que ya promete la búsqueda deja de ser mentira | `ContinuoView.swift:700` | RF-01 |

## 5. Diagrama mínimo

```
pestaña Bitácora ─┐
API local ────────┼──> buscar(palabras) ──> índice (contenido externo)
agente de voz ────┘                              │ apunta a
                                                 ▼
                                        pantalla.texto / audio.texto
                                        (una sola copia del texto)
```

## 6. Modelo de datos

Ver `./data-model.md` — **compartido con la spec 008, una sola migración**.

## 7. Contrato

Ver `./contracts/README.md`.

## 8. Decisiones que requieren ADR

| Decisión | Alternativa descartada y por qué | ADR |
|---|---|---|
| Índice de **contenido externo** con disparadores | Mantenerlo a mano desde el código: es lo que hay hoy, y ya se le escapan dos casos — el texto del navegador nunca entra y un segundo reconocimiento duplicaría | `docs/adr/008-forma-de-la-bitacora-indice-externo-y-unicidad-parcial.md` |
| Búsqueda por palabras sobre el índice existente | Recorrido directo del texto guardado: 48,4 MB por consulta, sin ordenar por relevancia y sin normalizar acentos, teniendo el índice ya construido | `docs/adr/009-una-busqueda-tres-entradas.md` |
| Una función, tres entradas | Una consulta por entrada: tres sitios donde arreglar el mismo fallo | (recogido en el mismo ADR) |

## 9. Riesgos y cómo se prueban primero

| Riesgo | Cómo se despeja antes de construir encima |
|---|---|
| Quitar la copia deja la búsqueda lenta | **Se mide antes de fiarse**: el RNF-01 (300 ms) se comprueba sobre la copia migrada, no sobre la intuición de que el índice invertido basta |
| Los disparadores no cubren algún camino de escritura | Se prueban los tres: alta, cambio de texto y borrado por purga, cada uno con su comprobación de que el índice quedó al día |
| El borrado con contenido externo necesita el texto anterior | Es la trampa conocida de FTS5: el disparador de borrado debe emitir el texto viejo. Se prueba con un borrado real sobre la copia antes de tocar nada |
| La migración sobre datos reales | Ensayo completo sobre copia (RF-06), respaldo verificado y visto bueno separado de Alberto |
| Una prueba que nunca falla | Cada prueba nueva se ve en **ROJO** antes de arreglar |

## 10. Estrategia de verificación

| RF | Cómo se demuestra | Segundo ángulo | Prueba negativa |
|---|---|---|---|
| RF-01 | Buscar una palabra conocida de una anotación conocida, con cronómetro | Contrastar el resultado con una consulta directa sobre el texto guardado | Palabra inexistente: dice que no hay resultados |
| RF-02 | Consulta por la API con token válido | Comparar contra lo que devuelve la pestaña | Sin token y con token inválido: rechazadas |
| RF-03 | Pregunta hablada sobre material conocido | Repetir con otra formulación | Pregunta sobre algo inexistente: lo dice, no inventa |
| RF-04 | Palabra que solo está en una de las 22 páginas del navegador | Comprobar el recuento indexado de páginas web | Antes de migrar: 0 resultados (estado actual) |
| RF-05 | `dbstat` y tamaño antes y después | Suma de longitudes de texto idéntica | — |
| RF-06 | Ensayo sobre copia con recuentos comparados | Interrumpir la migración a propósito sobre la copia | El original queda intacto |

## 11. Complejidad justificada

| Pieza añadida más allá de lo simple | Por qué lo simple no basta |
|---|---|
| Disparadores en vez de altas a mano | Las altas a mano ya se dejaron dos caminos sin cubrir |
| Tres entradas a la búsqueda | Decisión de Alberto; el coste se contiene con una sola función detrás |
