# Publicación documental — Spec 013

- Objetivo: dejar revisable el requerimiento de bitácora solo de grabaciones.
- Entorno: repositorio Git local, rama `main`; remoto existente `origin` en GitHub.
- Estado inicial: árbol limpio y `main` alineada con `origin/main`.
- Autoridad: pedido explícito de requerimiento, diagnóstico y flujo commit/push.
- Acción: incorporar spec, investigación, revisión, bitácora e índices; commit
  documental y `git push origin main` sin forzar.
- Impacto: publicación de documentación técnica genérica; sin cambios de
  aplicación, datos de usuario, instalación, configuración o release.
- Verificación: verificador SDD, revisión independiente, inspección del diff
  público y coincidencia de hash local/remoto después del push.
- Recuperación: eventual commit inverso revisado y autorizado; sin reescritura
  de historia ni borrado de historial de usuario.
- Estado de funcionalidad: borrador sin aprobación; no implementada.

## Corrección documental posterior

- Objetivo: incorporar default activo al instalar/actualizar y suspensión del
  oyente de voz, confirmados expresamente en la aclaración del requerimiento.
- Acción: actualizar spec, investigación, checklist, bitácora y este manifiesto;
  nuevo commit documental y push normal a `origin/main`.
- Impacto: solo documentación pública; no se modifica la app ni la configuración
  de ninguna instalación. La publicación de una release queda pendiente.
- Verificación: 8 RF, 3 RNF, sin errores/avisos; revisión de alcance y del diff;
  hash local/remoto y blob de spec idénticos después del push.
- Recuperación: eventual commit inverso revisado y autorizado; sin reescritura.
