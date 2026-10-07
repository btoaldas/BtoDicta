# Contratos

`ContinuoCapturaSesion.shared.contextoActual()` devuelve contexto autorizado o nil. Contexto contiene sesion nullable, generacion e inicio. `vigente` invalida trabajo asíncrono de otra ventana. `sesionAutorizada` permite incorporar audio explícito ya finalizado cuya ventana no fue interrumpida por pausa o reconfiguración. Un WAV que atraviesa la interrupción se conserva completo en historial y no se adopta entero a la bitácora. `admiteMaterial(sesion:instante:)` valida navegador tardío contra la ventana de origen.

GET autenticado `/navegador/captura`: `capturando`, `solo_grabaciones`, `sesion` e `inicio` Unix. No usa el cupo de proveedores; tiene límite propio. Consulta previa a lectura DOM/captura y revalidación nativa en POST `/navegador`. Sin permiso o ante error no se captura. Texto e imagen incluyen sesión e instante. Se respetan filtros y exclusiones.

Los nuevos parámetros opcionales de sesión/manual/permitirSolicitud conservan compatibilidad de consumidores existentes. Dictados que ya tienen texto no vuelven al lote STT; un texto vacío permanece pendiente.

La pantalla descarta imágenes cuyo API termina después del cierre; la imagen autorizada que ya llegó puede escribirse y pasar OCR después. La extensión consulta cada 500 ms: las grabaciones ultracortas tienen captura nativa inicial, sin promesa de que el navegador llegue a sondear cada una. La extensión 0.6.0 debe recargarse para aplicar la guarda previa al DOM; la API nueva deniega el ingreso de clientes antiguos sin sesión válida.
