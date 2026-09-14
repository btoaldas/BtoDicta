# MANIFIESTO — BtoDicta

Documento **estable**. Dice qué es este proyecto y qué no se negocia. Lo que
cambia con el tiempo vive en `ROADMAP.md`.

## Qué es

Dictado por voz para macOS en español latino. Pulsas una tecla, hablas, y el
texto aparece en vivo junto al notch; pulsas otra vez y se pega donde estaba el
cursor. Nació porque los dictados comerciales no entendían las siglas ni los
nombres propios del español institucional ecuatoriano.

## Para quién

Alberto Aldás como usuario principal y diario, y cualquiera que descargue el
paquete publicado. No hay servidor ni cuentas: cada quien pone sus propias
claves y su audio no pasa por ninguna infraestructura del proyecto.

## El corazón: transcribir sin perder nada

Todo lo demás —modo agente, voz, bitácora, conectores, atajos— es añadido. Lo
que define a BtoDicta es que **una grabación se convierta en texto completo,
siempre**. En orden de prioridad, y sin que ninguno ceda ante el siguiente:

1. **El audio grabado no se pierde nunca.** Ni por un cierre inesperado, ni por
   un corte de luz, ni porque falle la red o el motor.
2. **Se transcribe todo**, dure lo que dure el dictado: un segundo o seis horas.
3. **Nada se pierde al trocear ni al coser** lo que se transcribió por partes.
4. **El pulido conserva todo el texto**; si no cabe, se parte, y si aun así
   falla, se entrega el original antes que una versión recortada.

## No negociable

- **Nunca se entrega menos texto del que se dictó.** Ante cualquier duda, gana
  el original completo sobre la versión mejorada pero incompleta.
- **La fluidez del usuario no se sacrifica.** Todo el trabajo de rescate,
  troceo, reintento y aprendizaje ocurre por debajo. El usuario habla y recibe
  su texto; no se le pregunta ni se le hace esperar por nuestra contabilidad.
- **Sin internet tiene que seguir funcionando.** El audio se graba igual y la
  cascada cae a motores locales. Depender de la nube para grabar es inaceptable.
- **El audio y el texto son del usuario.** Con motores locales no salen de su
  Mac; con motores de nube van solo al proveedor que él eligió, con su clave.
- **Ninguna credencial en el repositorio.** Las claves viven en `~/.btodicta/.env`
  con permisos 0600 y se registran en la bóveda personal, nunca en git.
- **No se codifican los límites de los proveedores.** Cambian y envejecen mal.
  El sistema los descubre al chocar con ellos y los olvida cuando se contradicen.
- **Nada se borra sin visto bueno explícito.** Ni audio, ni historial, ni
  registros, ni configuración del usuario.

## Cómo se decide que algo está hecho

Con evidencia reproducible, no con una afirmación. Un código 200, un «Started» o
un exit 0 no demuestran nada: hay que enseñar la salida, la captura o la
medición. Cada corrección deja una prueba propia que la habría detectado.

## Fuera de alcance

- Servidor, cuentas de usuario, sincronización entre equipos.
- Windows y Linux. Es una aplicación de macOS con Apple Silicon.
- Ser un producto comercial con soporte. Es software propio, publicado por si a
  alguien le sirve.
