# Manifiesto — Implementación de spec 013

- Fecha: 2026-10-06
- Autorización: Alberto pidió commit, push y GitHub, y aprobó continuar con plan, tareas e implementación («si dale»).
- Entorno actual: main, remoto GitHub del proyecto; base documental f610dd6.
- Objetivo: bitácora solo durante grabaciones explícitas por defecto al actualizar; suspender oyente por voz y backlog ambiental automático.
- Cambio exacto: código, pruebas y documentos de spec 013; migración SQLite aditiva; extensión 0.6.0.
- Impacto: futuros clientes adoptan el default al instalar la actualización; false explícito y maestro se conservan. Sin cambios directos en instalaciones existentes, datos personales ni credenciales.
- Mutación externa prevista: commit sobre main según excepción bitácora, seguido de push normal a origin/main. Sin force-push, borrados, instalación ni release.
- Verificación: suites nativa/JavaScript, reposo real con perfil aislado, build debug/release, revisión independiente y diff sin secretos; reconciliar HEAD, origin/main y GitHub después del push.
- Recuperación: commit de reversión revisado; conservar columnas aditivas, configuración e historial. No ejecutar rollback destructivo.
