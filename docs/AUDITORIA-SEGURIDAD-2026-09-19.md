# Auditoría de seguridad — 2026-09-19

Primera auditoría sistemática de BtoDicta. Hasta ahora la seguridad se había
mirado por partes, al hilo de cada cambio; esto recorre la aplicación entera
buscando lo mismo en todos lados.

**Qué protege esta aplicación.** En esta máquina viven las credenciales de
veintitrés proveedores de IA, el audio de todo lo dictado, una bitácora que
fotografía la pantalla cada pocos segundos, y —en el mismo disco— certificados de
firma electrónica. La aplicación además ejecuta procesos, habla con veinte
servicios en la nube y, desde 0.65.0, abre una puerta local.

## Resumen

| | |
|---|---|
| Áreas revisadas | 9 |
| Hallazgos | **2** (1 alto, 1 bajo) |
| Corregidos | 2, con prueba |
| Ya estaba bien | 7 áreas |

## Hallazgo 1 (ALTO) — el texto podía ejecutar órdenes

`XttsLocalTTS.decirCon` monta un comando de shell con el texto dentro y lo
ejecuta con `zsh -lc`. El escapado cambiaba la comilla doble por una simple, y
eso no basta: dentro de comillas dobles, zsh sigue interpretando `$(...)`, los
acentos graves y la barra invertida.

**Por qué importa de verdad.** Esa función dice en voz alta lo que responde la
IA, y la IA redacta a partir de lo que se lee en la pantalla: correos, páginas y
documentos que no escribió el usuario. La cadena completa era

```
una web abierta → la IA la lee → redacta la respuesta → la voz la pronuncia → shell
```

Bastaba con que alguien pusiera la frase justa en una página que estuviera
abierta. El arreglo del prompt (0.64.0) reduce la probabilidad de que la IA
repita el texto hostil, pero no cierra esto: el texto puede llegar por otras vías.

**Corregido**: se escapan barra invertida, acento grave, `$` y comilla doble, en
ese orden. `BTODICTA_SHELLTEST` lo comprueba con cinco ataques, y además **ejecuta
de verdad** un texto que crearía un archivo: si el escapado fallara, el archivo
aparecería. No aparece.

## Hallazgo 2 (BAJO) — la ruta del bundle iba pegada al comando

`OnboardingWizard.reiniciarApp` construía `open "\(ruta)"` dentro de un
`bash -c`. La ruta es la del propio bundle, así que no la controla nadie de
fuera, pero si la aplicación viviera en una carpeta con comillas en el nombre el
entrecomillado se rompería.

**Corregido**: la ruta va como argumento posicional, el mismo patrón que ya
usaba el actualizador.

## Lo que ya estaba bien

| Área | Comprobación | Resultado |
|---|---|---|
| Credenciales en el registro | Búsqueda de claves y tokens en todas las líneas de registro | **Ninguna** |
| Permisos de archivos | `.env`, `api-token`, `config.json` | **0600** los tres |
| Validación de certificados | Búsqueda de desactivaciones de TLS | **Nadie la desactiva** |
| Ejecución de procesos | 71 usos de `Process` | Solo 3 usan shell; los otros 68 pasan argumentos |
| El actualizador | Instala un DMG descargado | Verifica **firma Ed25519** antes de instalar |
| Lo que decide la IA | El router global ejecuta capacidades | **Catálogo cerrado**: si la IA inventa algo, se descarta |
| La API local | Puerta abierta al resto del equipo | **Seis cerraduras**, cada una con prueba negativa |

## Riesgo residual que se cierra aquí

La API no tenía **tope de peticiones**: un consumidor con un bucle mal escrito
podía vaciar el saldo de nube en minutos, y el aviso de saldo bajo llega después.
Ahora hay un tope por minuto, ajustable, con 0 para quitarlo. No es una defensa
contra quien ya tenga el token —ese ya está dentro—: es la red contra el programa
propio que se equivoca, que es lo que pasa de verdad.

## Riesgos residuales que NO se cierran, y por qué

1. **El token de la API es un secreto en un archivo.** Quien pueda leer
   `~/.btodicta` puede usar los motores y gastar saldo. Es el mismo nivel que el
   `.env` que ya vivía ahí; protegerlo más exigiría el llavero del sistema, que
   es otra conversación.
2. **No hay identidad por consumidor.** Existe «alguien con el token», no
   «quién». Con un solo usuario en la máquina, distinguirlos no aporta.
3. **El registro guarda el texto dictado** si está encendido (lo está de
   fábrica). Es local, rota cada semana y hay interruptor; la razón de dejarlo
   encendido está escrita en 0.64.0.
4. **La bitácora fotografía la pantalla.** Es su función. Lo que se podía hacer
   —excluir gestores de contraseñas de fábrica y permitir excluir por título— se
   hizo en 0.64.0.

## Lo que esta auditoría NO cubre

- **Revisión línea a línea** de los 71 usos de `Process`: se comprobó cuáles
  usan shell, no todos sus argumentos.
- **Dependencias de terceros**: la aplicación no trae ninguna biblioteca externa
  de Swift, pero sí empaqueta binarios (`whisper-cli`, `llama-server`). Sus
  vulnerabilidades no se han mirado.
- **Los modelos descargados**: se bajan por HTTPS de sus repositorios, sin
  comprobar huella. Un repositorio comprometido serviría un modelo alterado.
- **Análisis dinámico**: nadie ha intentado atacar la aplicación en marcha más
  allá de las pruebas escritas aquí.
