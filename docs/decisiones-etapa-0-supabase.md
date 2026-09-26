# Decisiones de etapa 0 a cargo de Supabase

Estas decisiones deben acordarse antes de implementar los requisitos que dependen de ellas. No se marca ninguna como cerrada hasta contar con la respuesta del responsable funcional.

## D-003 — Precios y unidades

Definir para cada familia comercial: moneda, unidad de venta, regla de redondeo, descuentos permitidos y quién publica una tarifa. La propuesta técnica es COP, precio sin descuento por defecto, redondeo al peso y publicación exclusiva del rol `pricing_manager`.

## D-005 — Disponibilidad operativa

Definir qué sistema tiene autoridad final, el tiempo de expiración de una pre-reserva por familia y quién puede cancelarla. La propuesta técnica es que Odoo confirme la reserva definitiva, Supabase administre la consulta y el calendario, y que las excepciones de cancelación queden auditadas.

## D-014 — Captación CRM

Definir cuándo un formulario o conversación crea un lead, campos obligatorios, consentimiento, regla para detectar duplicados y equipo destino. La propuesta técnica es guardar el consentimiento y la fuente, crear lead solo después de validación, y usar correo o teléfono normalizados para advertir posibles duplicados sin fusionar registros automáticamente.

## D-016 — Alta y administración inicial

Estado técnico confirmado al 26/09/2026: registro público cerrado, confirmación por correo requerida, migraciones aplicadas y RLS activo. `asesoria@hercas.net` aceptó la invitación del primer administrador, inició sesión y accedió a `/plataforma` con `systems_admin`. El aislamiento entre dos empresas se probó en SQL con identidades y registros temporales revertidos, incluida la revocación de una membresía. La validación integral sigue pendiente: Supabase remoto tiene cero empresas y cero membresías reales, y falta comprobar el portal con dos sesiones de clientes reales. No cerrar D-016 ni BE-003 con la sola prueba SQL.

## D-020 — Límites y conservación

Definir tamaño y tipo de archivos permitidos, cuotas por empresa, retención de conversaciones, leads, cotizaciones, auditoría y soportes. La propuesta inicial es no habilitar Storage ni Realtime para datos de negocio hasta aprobar estas reglas; conservar auditoría por el período que determine el responsable de datos.
