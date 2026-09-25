# Base de identidad de Hercas

## Decisiones confirmadas

- Una compañía operadora: Hercas. customer_accounts representa **empresas cliente**,
  no varias compañías operadoras.
- Acceso por invitación; varios usuarios pueden compartir una empresa cliente.
- Correo inicial indicado: **sitemas@hercas.net**, literalmente. No se corrigió a
  sistemas@hercas.net ni se envió ningún correo.
- Precios y disponibilidad se administran mediante roles separados.

## Estado

Migración preparada y probada en PostgreSQL embebido PGlite. El contrato mínimo de
Supabase Auth se simula en esas pruebas; no prueban correo, Auth remoto, el gateway
Data API ni concurrencia de varias conexiones. Las pruebas no acceden a Odoo.

**Aplicada remotamente el 17 de septiembre de 2026** mediante el conector autorizado,
en `hercas-platform-dev` (`mmstapaovlvflbiiqgxv`). Historial remoto y local alineados:
`20260917223649_platform_identity_foundation` y `20260917223752_identity_advisor_hardening`.
Verificación remota: nueve tablas con RLS, sin lectura anónima ni escrituras genéricas
authenticated; seis roles creados. Asesor de seguridad sin hallazgos tras restringir
la función automática `public.rls_auto_enable`. Se completaron tres índices compuestos.
Solo quedan avisos informativos de [índices aún sin uso](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index),
esperables en esta base nueva. No se crearon usuarios Auth ni se enviaron invitaciones.

No aplicar conjuntamente las migraciones de `app/.worktrees`: son el esquema piloto
del cotizador, no esta nueva base de plataforma. El SQL es para una base sin estas
tablas y falla ante conflictos; no elimina ni reemplaza estructuras existentes.
Antes de aplicar hay que inspeccionar tablas y migraciones remotas.

## Tablas

La base comercial también está aplicada: nueve tablas adicionales de catálogo,
tarifas, cotizaciones y calendario, para **18 tablas en total**. Ver
[cotizador y disponibilidad](COTIZADOR.md) para reglas, pruebas y límites actuales.

| Tabla | Propósito |
| --- | --- |
| profiles | Identidad web vinculada a Auth; estado y tipo de usuario |
| roles | Roles internos y de empresa cliente |
| permissions | Catálogo explícito de permisos |
| role_permissions | Permisos que agrupa cada rol |
| user_roles | Asignaciones internas de Hercas y su revocación |
| customer_accounts | Empresas cliente y referencia opcional a contacto Odoo |
| customer_memberships | Usuarios de cada empresa cliente, con rol y revocación |
| invitations | Autorización de alta, destino, caducidad y aceptación |
| audit_events | Actor, operación, entidad y fecha; sin copiar secretos ni cuerpos |

Todas tienen RLS y carecen de acceso anónimo. Los perfiles nacen pendientes e
inactivos, sin leer user_metadata ni conceder privilegios por correo. Staff y clientes
tienen ámbitos separados. Los clientes consultan únicamente sus membresías y
empresas activas. El backend sigue usando el JWT del usuario para las consultas.

Las funciones SECURITY DEFINER están en private, con search_path vacío y grants
acotados. Los helpers consultan el usuario actual para evitar recursión RLS, y la
aceptación es la única mutación publicada mediante una función invoker. Los triggers
de Auth/auditoría no son ejecutables por clientes API y no conceden roles por sí solos.

La gestión administrativa es por SQL de operador en este corte: no se otorgan
INSERT/UPDATE/DELETE genéricos a authenticated, ni siquiera al administrador web.
Los endpoints/pantallas de invitación, revocación y edición se construirán después
con permisos específicos. Las asignaciones iniciales de permisos no implementan por
sí solas reportes, cotizaciones ni otros módulos futuros.

## Configuración de Auth y puesta en uso pendientes

1. Conector autorizado y proyecto inspeccionado: completado.
2. Migraciones aplicadas y asesores revisados: completado.
3. En Authentication → Sign In / Providers, desactivar **Allow new users to sign up**
   y **Allow anonymous sign-ins**. Mantener confirmación de correo. El config.toml
   de este repositorio establece esto para el entorno local; **no cambia el remoto**.
4. Configurar URL del sitio, destinos de redirección exactos y correo de invitación
   apropiado al entorno. Todavía no existe pantalla frontend de aceptación.
5. Revisar el correo y ejecutar `admin/prepare_initial_admin.sql` como propietario.
   Solo crea la autorización pendiente, no un usuario ni un envío de correo.
6. Enviar explícitamente una invitación Auth al destinatario autorizado desde el
   Dashboard o el futuro backend administrativo. No crear una contraseña para él.
7. Tras aceptar la invitación Auth y verificar su correo, obtener una sesión y
   llamar con su access_token a
   `POST /api/v1/auth/invitaciones/{id}/aceptar`.
8. Verificar `/api/v1/auth/sesion`, acceso administrativo y pruebas de aislamiento
   en el proyecto real. Configurar MFA privilegiado antes de producción.

La aceptación usa la identidad Auth verificada e invitada, su correo y la invitación
vigente bloqueada en transacción. No concede acceso a un usuario suspendido ni cambia
un cliente a empleado. Repetir la aceptación no duplica ni restaura permisos revocados.
El UUID identifica la autorización, no sustituye el enlace seguro enviado por Auth.

Una nueva invitación debe ser creada por un operador autorizado indicando email,
user_kind, rol y empresa cuando sea cliente. La expiración es de hasta siete días.
En este corte el alta de la autorización y el envío de Auth son pasos administrativos
separados; no hay pantalla ni API de envío implementadas.

## Pruebas reproducibles

```powershell
npm --prefix tools/database ci
npm --prefix tools/database test
.\venv_apiodoo\Scripts\python.exe -m unittest discover -s tests -q
```

Node/PGlite/CLI son herramientas de desarrollo, no dependencias de la web ni del
backend en producción. Versiones fijadas y lockfile en tools/database.

Documentación: [configuración de Auth](https://supabase.com/docs/guides/auth/general-configuration),
[RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
