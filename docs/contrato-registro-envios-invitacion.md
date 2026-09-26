# Registro de intentos de envío de invitaciones

Estado: propuesta para acordar entre Carlos (Supabase y frontend) y Anderson (FastAPI). No está implementada ni desplegada.

## Problema comprobado

`POST /api/v1/auth/invitaciones/{invitation_id}/enviar` llama a Supabase Auth `/auth/v1/invite`, pero solo responde `{"sent": true}`. `GET /api/v1/auth/administracion` devuelve las invitaciones sin historial de intentos. Una respuesta HTTP 200 de Auth confirma que aceptó la solicitud; no prueba recepción, entrega ni apertura del correo. En la prueba de `auxsistemas@hercas.net` hubo respuestas 200 y un reintento 429, pero la cuenta seguía sin confirmar ni aceptar la invitación el 26/09/2026.

## Contrato propuesto

1. Carlos crea en Supabase un registro persistente de intentos, con `id`, `invitation_id`, `requested_by`, `attempted_at`, `provider_status`, `result` y `error_code` seguro. `result` admite `provider_accepted`, `provider_rejected` y `transport_error`. La tabla tiene RLS y lectura limitada a `users.manage`; ninguna clave privada ni cuerpo de respuesta se guarda en ella.
2. Anderson modifica el endpoint para registrar **un** intento por llamada al proveedor, tanto en éxito como en error. El registro se hace después de recibir la respuesta o excepción, conservando el código HTTP y un error clasificado sin datos sensibles. El backend devuelve el identificador del intento y `provider_accepted`, nunca `delivered` o `sent` como prueba de recepción. Si falla el registro, devuelve error explícito de trazabilidad; no presenta el envío como éxito verificado.
3. `GET /api/v1/auth/administracion` expone los últimos intentos de las invitaciones mostradas, paginados o limitados por invitación. Carlos muestra en el panel fecha, resultado y código HTTP, con el texto “Solicitud aceptada por Supabase; entrega al buzón no confirmada” cuando corresponda.
4. El límite de reintentos y los estados de invitación siguen independientes. Crear la invitación no envía correo. Aceptarla requiere identidad verificada. Revocarla impide nuevas solicitudes y aceptación; el historial se conserva.

## Aceptación conjunta

Con una invitación de prueba: verificar registro de aceptación del proveedor, error 429 y error de transporte; comprobar que no hay duplicados por una misma llamada, que un usuario sin `users.manage` no lee el historial, y que el panel no afirma entrega. La recepción real requiere comprobación en el buzón o telemetría de un proveedor SMTP propio. No cerrar INT-003, BE-005 ni FE-010 solo por desplegar este registro.
