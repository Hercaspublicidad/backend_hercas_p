# Autenticación de la plataforma Hercas

## Estado verificado el 25 de septiembre de 2026

`asesoria@hercas.net` ya definió su contraseña, aceptó la invitación `42d9befb-47ae-4336-abdd-82715f3048bf` a las 22:31:13 UTC y accedió a `/plataforma` como `systems_admin`. Supabase confirma perfil activo y rol `staff` vigente. Al recargar, la sesión y el directorio administrativo siguieron disponibles. La recuperación usa un cliente de enlace sin estado PKCE breve; si la contraseña se guardó pero falla la API, `/auth/confirmar` ofrece reintentar únicamente la aceptación. El backend local volvió a conectar con Supabase después de reiniciar FastAPI.

La prueba RLS con rol `authenticated` y la identidad de `asesoria@hercas.net` mostró perfiles e invitaciones de administración. Con la identidad pendiente de `sistemas@hercas.net` mostró solo su perfil, sin invitaciones ni roles. Las transacciones de prueba se revirtieron. La prueba PGlite del administrador inicial se alineó con el correo elegido por Carlos: 35 pruebas PostgreSQL y 48 pruebas Python aprobadas. El 25/09, «Guardar permisos» respondió «Acceso actualizado» con los valores existentes; Supabase confirmó que Carlos sigue activo y conserva únicamente `systems_admin`. El frontend `376bff7` filtra los roles de la invitación según se elija empleado o empresa; tras reiniciar `localhost:3000`, el panel mostró solo roles de empleado para «Empleado de Hercas». Quedan pendientes la prueba de preparación/revocación de una invitación y la aceptación integral de FE-010/FE-011. Ninguna prueba de correo debe deducirse de la simple preparación de una invitación.

SMTP personalizado permanece desactivado. El 25/09, con autorización expresa, se configuró `SUPABASE_SECRET_KEY` solo en el `.env` local ignorado por Git y se reinició FastAPI con acceso a Supabase. Desde `/plataforma` se envió una invitación a `auxsistemas@hercas.net`: la interfaz respondió «Correo enviado» y Supabase Auth registró `invited_at` y `confirmation_sent_at` a las 16:23:26 UTC. Se revocó la invitación duplicada anterior; queda una sola vigente. La recepción en el buzón, aceptación y sesión del nuevo usuario siguen pendientes, por lo que INT-003 y FE-010 continúan abiertos. El asesor de seguridad de Supabase reporta un aviso: protección de contraseñas filtradas desactivada. La prueba SQL anterior de crear y revocar una invitación con `ROLLBACK` fue rechazada por revisión automática y no se ejecutó.

Las secciones fechadas abajo conservan la historia de diagnóstico; sus referencias a la activación pendiente describen el estado anterior a esta verificación.

## Estado al 22 de septiembre de 2026

Carlos eligió `asesoria@hercas.net` como correo del administrador inicial porque consulta `sistemas@hercas.net` en otro dispositivo. El 22/09/2026 a las 19:59:37 UTC se revocó la autorización pendiente de `sistemas@hercas.net` y se preparó la autorización `42d9befb-47ae-4336-abdd-82715f3048bf` para `asesoria@hercas.net`, rol `systems_admin`, con vencimiento el 29/09/2026 a las 19:59:37 UTC. Supabase envió la invitación Auth a las 20:18:07 UTC; registró correo confirmado e inicio de sesión a las 20:18:17 UTC. La autorización de la aplicación aún tiene `accepted_at = null`: falta definir la contraseña y validar acceso y RLS. El registro de envío en Supabase no prueba por sí solo entrega en la bandeja.

Se usó temporalmente `Site URL = http://localhost:3000/auth/confirmar?invitation=42d9befb-47ae-4336-abdd-82715f3048bf` para el envío desde Supabase Dashboard y luego se restauró `http://localhost:3000`. Las redirecciones admitidas apuntan a `/auth/confirmar` en este equipo. Carlos informó que los campos de contraseña aparecieron inactivos. El frontend se corrigió para procesar explícitamente el código PKCE o los tokens del fragmento y mostrar una explicación cuando falta sesión; `npm run build` pasó y el servidor local fue reiniciado. Con autorización expresa se intentó enviar recuperación al mismo correo, pero Supabase rechazó el intento con `email rate limit exceeded`; `auth.users.recovery_sent_at` siguió vacío. Se restauró de nuevo el Site URL normal. No repetir el envío hasta resolver o esperar el límite. Si la sesión del enlace inicial sigue en el mismo navegador, recargar la pantalla corregida puede permitir continuar. No se debe marcar FE-010/FE-011 ni la activación inicial como cerrados hasta validar contraseña, aceptación y sesión/RLS. No pedir que pegue tokens de acceso en el chat.

Actualización de FE-010 (22/09/2026): el enlace «Olvidé mi contraseña» desde `/auth/confirmar?invitation=...` conserva el identificador en `/recuperar`, y la solicitud de recuperación lo incluye en la URL de retorno a `/auth/confirmar`. El formulario comprueba ahora el error devuelto por Supabase y muestra el límite temporal de correo en lugar de indicar un envío exitoso. Cambio `b97b2f5` en `codex/platform-auth`; `npm run build` y `npm run lint` pasaron (lint conserva cuatro advertencias ajenas al archivo). Se verificó en el navegador local que el enlace abre `/recuperar?invitation=...`; no se envió otro correo ni se probó el retorno real, por el límite vigente. La invitación sigue sin aceptar y FE-010 no está cerrado.

Seguimiento posterior del 22/09/2026: Supabase registró `auth.users.recovery_sent_at = 21:35:47 UTC` para `asesoria@hercas.net`. La pantalla `/recuperar` mostró confirmación de solicitud; se comprobó que el campo de correo recibe foco y permite escribir. Esto acredita el registro del envío en Auth, no la recepción en la bandeja. La invitación `systems_admin` sigue con `accepted_at = null` y vence el 29/09/2026 a las 19:59:37 UTC. Carlos debe abrir el enlace recibido y definir personalmente la contraseña; después se validarán sesión, aceptación y RLS. No enviar más recuperaciones mientras esté vigente el enlace actual.

La interfaz se aclaró en `e6fc12d`: tras una solicitud de recuperación aceptada, muestra el paso de revisar el correo en lugar de dejar el formulario listo para repetirla. En `/auth/confirmar` sin sesión válida, presenta el aviso y el enlace de recuperación en lugar de dos campos de contraseña deshabilitados. Build y lint aprobados; prueba local de la ruta sin sesión aprobada. No se probó la pantalla de éxito con otro envío de correo.

## Historial hasta el 18 de septiembre de 2026

**Invitación inicial enviada:** Supabase Auth registró `invited_at` y `confirmation_sent_at` el `2026-09-18 15:41:15 UTC` para `sistemas@hercas.net`, usuario `ae7b5709-f844-4728-b758-0f0ad93d807b`. Se utilizó el servicio integrado desde Dashboard → Users → Send invitation, autorizado explícitamente por el usuario. La confirmación de envío no acredita recepción en bandeja. Al verificar, `email_confirmed_at` seguía vacío. Para ese correo se estableció temporalmente Site URL en la ruta local de confirmación con el ID de autorización y después se restauró a `http://localhost:3000`. Frontend y backend respondieron HTTP 200. Abrir el correo en este computador para completar verificación y definir contraseña. SMTP propio sigue pendiente para el envío general; no era necesario bloquear este primer intento de correo.

En esa etapa el usuario confirmó **sistemas@hercas.net** como correo del primer administrador; el 22/09/2026 cambió la elección a **asesoria@hercas.net**. El buzón de sistemas está en Microsoft y migrará a Google en aproximadamente dos semanas. No se dispone de acceso al panel DNS; el envío SMTP general y la prueba completa de activación/recuperación siguen pendientes. No se ha contratado un proveedor ni modificado DNS. El script de preparación del administrador ahora usa el nuevo correo. Preparar la autorización no activa la cuenta ni envía correos.

Autorización inicial preparada en Supabase: `4e570210-341a-4159-a378-9a12f35947cc`, rol `systems_admin`, vencimiento `2026-09-25 15:18:18 UTC`. En ese momento no se envió esa autorización por correo. Si vence antes de aceptarla, preparar una nueva autorización y utilizar el nuevo ID. Verificación local: 35 pruebas PostgreSQL y 48 Python aprobadas.

Implementación del 18 de septiembre de 2026. Python/FastAPI valida sesiones y autoriza operaciones; Supabase Auth gestiona credenciales y recuperación; PostgreSQL aplica permisos y RLS. Next.js contiene las pantallas y envía el JWT del usuario al backend. Nunca se confía en un rol enviado por el navegador o en `user_metadata`.

## Ubicación y ejecución

- Backend: `D:\api_0doo`.
- Frontend: worktree `D:\api_0doo\.worktrees\website-auth`, rama `codex/platform-auth`, creado desde `D:\Web Hercas\Web\pagina_hercas`.
- Backend: `venv_apiodoo\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000`.
- Frontend: `npm ci`, `npm run build`, `npm start` desde el worktree.
- El `.env.local` del worktree ya contiene URL y clave pública del proyecto y `NEXT_PUBLIC_PLATFORM_API_URL=http://localhost:8000`. Está excluido de Git.
- El frontend principal no fue modificado ni se desplegó a producción. El worktree debe conservarse hasta integrar sus cambios.

## Pantallas y flujo

- `/login`: correo y contraseña, comprobación de perfil activo contra Python antes de abrir la plataforma.
- `/registrarse`: instrucciones para activar una invitación; no llama a `signUp`.
- `/recuperar`: solicitud de enlace; mensaje neutro para no revelar si existe una cuenta.
- `/auth/confirmar`: procesa enlaces Supabase (PKCE, fragmento predeterminado o `token_hash` de tipo `invite`/`recovery`), define contraseña de mínimo 12 caracteres y acepta la autorización correspondiente. Luego solicita cierre global de sesiones e inicio de sesión nuevo.
- `/plataforma`: contenido privado obtenido únicamente desde la API autenticada. El HTML inicial es una pantalla vacía de datos privados. La protección real está en Python/PostgreSQL; no depende de la redirección del navegador.
- Administradores: directorio paginado, asignación/revocación de roles de empleados, suspensión/reactivación de empleados y clientes, preparación/envío/revocación de invitaciones y matriz de permisos.
- Crear una invitación no envía correo automáticamente. El botón **Enviar correo** realiza esa acción explícita. Si falla el correo, la autorización queda pendiente y se puede reintentar o revocar.

## Roles

| Código | Uso |
|---|---|
| `systems_admin` | Usuarios, roles y administración de la plataforma |
| `sales` | Operación comercial y cotizador |
| `pricing_manager` | Precios del cotizador |
| `availability_manager` | Disponibilidades |
| `auditor` | Auditoría |
| `client_viewer` | Información de las empresas asociadas al cliente |

Los roles de clientes se asignan mediante invitaciones vinculadas a una empresa. No pueden convertirse en permisos globales de empleado. El panel permite suspender una cuenta de cliente completa; la edición individual de membresías no forma parte de esta entrega.

## Configuración externa y validaciones pendientes

- **Realizado:** registro público y cuentas anónimas desactivados; confirmación de correo, cambio seguro de contraseña y mínimo de 12 caracteres configurados; redirecciones locales de `/auth/confirmar` verificadas; primer administrador `asesoria@hercas.net` activo. Site URL de desarrollo: `http://localhost:3000`.
- **Pendiente:** configurar y verificar un proveedor SMTP y remitente para la entrega general. El correo de recuperación de Carlos llegó anteriormente y Supabase Auth aceptó el envío de una invitación a `auxsistemas@hercas.net`, pero aún no se ha confirmado su recepción en el buzón. SMTP personalizado sigue desactivado.
- **Realizado:** `SUPABASE_SECRET_KEY` se configuró con autorización expresa únicamente en el `.env` local ignorado por Git; `AUTH_SITE_URL=http://localhost:3000`. Se reinició FastAPI con acceso a Supabase y el endpoint volvió a responder con validación de sesión, en lugar del error de conexión. La clave no debe incluirse en Git, Next.js ni el chat.
- **Realizado parcialmente:** desde el panel se envió una invitación autorizada y se revocó la duplicada. Supabase Auth registró el envío a las 16:23:26 UTC. **Pendiente:** comprobar recepción, aceptación de la nueva identidad, sesión, permisos y aislamiento RLS antes de cerrar el flujo.
- **Pendiente:** probar suspensión/revocación desde una sesión real y enrolamiento MFA. TOTP está habilitado en Auth y el límite AAL1 activo, pero no se ha validado el enrolamiento.
- **Limitación conocida:** la protección de contraseñas filtradas aparece desactivada y Supabase indica que requiere plan Pro; no se contrató un plan. CAPTCHA tampoco está configurado.

`supabase/admin/prepare_initial_admin.sql` fue usado para preparar al administrador inicial y no debe repetirse como paso pendiente. No usar SQL para insertar contraseñas o fabricar identidades en `auth.users`.

## Seguridad y límites

- RLS en las tablas y funciones administrativas privadas con `search_path` vacío; sin ejecución anónima. Correo del directorio accesible únicamente a `users.manage`.
- Mutaciones de permisos atómicas, auditadas, con bloqueo para impedir desactivar o degradar al último administrador.
- Cuenta suspendida o rol revocado: se aplica en la siguiente operación del backend y en RLS, sin esperar renovación del JWT.
- `signOut` revoca refresh tokens; un JWT de acceso emitido puede seguir válido hasta su vencimiento. No se promete revocación instantánea del JWT por cerrar sesión. La suspensión sí se comprueba en cada solicitud.
- Respuestas Python `no-store`, errores sanitizados, validación sin eco de inputs, CORS limitado al frontend configurado.
- Pantallas Auth: `noindex`, `no-referrer`, bloqueo de iframes y CSP parcial (`frame-ancestors`, `object-src`, `base-uri`, `form-action`). No es una CSP estricta contra cualquier XSS.
- El SDK Auth solo se importa en pantallas de acceso/plataforma. Las páginas comerciales siguen estáticas y sin chequeos de Auth en cada visita.
- No se implementó WAF ni CAPTCHA. TOTP está habilitado en Auth, pero falta probar enrolamiento y recuperación. Son capas adicionales y no sustituyen autenticación/RLS.

## Verificación

- 48 pruebas Python: incluye bloqueo de rutas administrativas, no escalada desde metadata, uso exclusivo de secreto en envío Auth y no filtración de errores.
- 35 pruebas PostgreSQL/PGlite: RLS, aislamiento entre clientes, invitaciones, último administrador, suspensión y permisos comerciales.
- `npm run build`: 190 páginas generadas, TypeScript correcto.
- ESLint: sin errores nuevos; cuatro avisos previos en formulario de cotización e imágenes de encabezado/pie.
- `npm audit`: cero vulnerabilidades después de corregir Next.js a 16.3.5, MapLibre a 6.10.0 y transitivas. La actualización mayor de MapLibre requiere verificar el mapa real además de la compilación.
- Navegador: login, registro por invitación, recuperación, rechazo de credenciales incorrectas, rechazo de callback sin sesión y redirección anónima desde plataforma.
- Carlos completó correo de recuperación → contraseña → aceptación → login real; falta repetir el flujo para una nueva identidad y validar entrega general de invitaciones.
- Migraciones `auth_administration` y `auth_admin_directory` aplicadas al proyecto `mmstapaovlvflbiiqgxv`. El asesor de seguridad reportó el 25/09/2026 únicamente la protección de contraseñas filtradas desactivada.
