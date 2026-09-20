# ADR 004 — Un solo código fuente para la extensión, dos empaquetados

- Fecha: 2026-09-20
- Estado: Aceptada
- Spec: 006 — Extensión de navegador para la bitácora

## Contexto

Hay que cubrir cuatro navegadores: Chrome, Edge, Brave y Firefox. Los tres
primeros comparten motor; Firefox no, y exige su propio empaquetado y su propia
firma.

## Decisión

Un solo código fuente, con una capa fina que resuelve `chrome.*` o `browser.*`
según dónde corra, y dos ficheros de manifiesto. El mismo paquete vale sin
cambios para Chrome, Edge y Brave.

## Alternativa descartada: dos proyectos separados

Cada navegador con su repositorio de código, sin capa de compatibilidad ni
condicionales.

Se descarta porque el 95 % del código sería idéntico, y dos copias de lo mismo
divergen: se arregla un fallo en una y se olvida en la otra. Lo que de verdad
difiere entre ambos mundos es el manifiesto y la firma, no la lógica — y eso es
exactamente lo que sí se separa.

## Consecuencias

- Un fallo se arregla una vez.
- Hay que probar en los cuatro navegadores, porque «mismo código» no es «mismo
  comportamiento»: Firefox aplica los permisos con otro criterio.
