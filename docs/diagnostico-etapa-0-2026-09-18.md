# Diagnóstico de etapa 0 — 18 de septiembre de 2026

## Evidencia obtenida

- El proyecto Supabase responde en `GET /auth/v1/health` con HTTP 200.
- Las consultas anónimas a perfiles, empresas cliente y productos devolvieron HTTP 401. Esto confirma que no hay lectura pública disponible en esos recursos; no sustituye la prueba con sesiones reales.
- Las migraciones locales incluyen identidad, administración, catálogo, disponibilidad y cotizador. La documentación del proyecto registra que las migraciones de administración ya fueron aplicadas al entorno de desarrollo.
- Las pruebas locales finalizaron correctamente: 48 de Python/FastAPI y 35 de PostgreSQL/PGlite. Cubren autorización, RLS, aislamiento entre empresas, invitaciones, suspensión y protección del último administrador.
- La revisión remota confirmó que las cinco migraciones previstas están aplicadas y que las 18 tablas funcionales tienen RLS habilitado. El proyecto de desarrollo está saludable.
- El entorno remoto contiene un perfil y una invitación, pero todavía no tiene roles de usuario, empresas cliente, membresías ni datos comerciales. Por ello aún no existe la base mínima para ejecutar el ensayo real con dos empresas.
- El asesor de seguridad solo reporta que la protección contra contraseñas filtradas está desactivada. El aviso de rendimiento se limita a índices sin uso en un entorno que todavía no recibe carga; no deben eliminarse antes de medir operaciones reales.

## Estado de identidad

La invitación inicial para el administrador de sistemas fue preparada y enviada previamente. Aún falta que la persona destinataria complete el enlace, establezca la contraseña e inicie sesión. Sin esa sesión no se puede comprobar el flujo real de activación ni las políticas RLS entre dos empresas.

La consulta actual a la configuración de Auth confirmó `disable_signup=true`: el registro público está cerrado y se requiere confirmación de correo. Tampoco hay MFA implementado para esta entrega; su definición queda pendiente como decisión de alcance.

## Bloqueos para cerrar la etapa 0

1. Completar la activación del primer administrador y comprobar inicio de sesión, aceptación de invitación y cierre de sesión.
2. Crear o disponer de dos identidades de prueba asociadas a empresas distintas y ejecutar la prueba real de aislamiento RLS.
3. Definir si MFA es requisito de salida y, si lo es, el método permitido y los roles obligatorios.

## Siguiente operación permitida

La persona responsable de Supabase puede realizar esos cuatro controles sin iniciar trabajo de módulos. Anderson puede, en paralelo, dejar documentado el contrato de sincronización con Odoo sin implementar integraciones ni alterar datos. Al cerrarse los bloqueos se actualiza el plan y se habilita la etapa 1.
