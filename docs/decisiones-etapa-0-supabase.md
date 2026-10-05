# Decisiones de etapa 0 a cargo de Supabase

Estas decisiones deben acordarse antes de implementar los requisitos que dependen de ellas. No se marca ninguna como cerrada hasta contar con la respuesta del responsable funcional.

## D-003 — Precios y unidades

Definir para cada familia comercial: moneda, unidad de venta, regla de redondeo, descuentos permitidos y quién publica una tarifa. La propuesta técnica es COP, precio sin descuento por defecto, redondeo al peso y publicación exclusiva del rol `pricing_manager`.

## D-005 — Disponibilidad operativa

Decisión del usuario (30/09/2026): la plataforma web manda en la disponibilidad y será la herramienta operativa en tiempo real. El calendario compartido de Supabase es la fuente de verdad para consultas, separaciones, bloqueos y reservas; el website y los demás clientes autorizados lo consultan y modifican mediante operaciones controladas. Odoo no confirma ni reemplaza ese estado. Si Odoo registra compromisos sobre los mismos activos, deben incorporarse al calendario web antes de ofrecer esas fechas y conciliarse sin crear una segunda autoridad.

Cada comercial tendrá su propia cuenta en el website y una vista de disponibilidad conectada al cotizador. El cliente final que accede al website y el comercial ven la misma disponibilidad, derivada del mismo calendario. El comercial puede reservar una valla si lo decide durante la gestión de la venta; indica fecha de inicio y fecha de fin según el tiempo acordado, y puede liberarla mediante un flujo trazable. Para el cliente final, la reserva se confirma cuando paga. Katherine lidera el proceso de disponibilidad, sin ser la única persona que registra operaciones. La comprobación de capacidad y el registro de cada operación deben ser atómicos para impedir reservas cruzadas.

Siguen pendientes de decisión el tiempo de expiración de una separación por familia, el alcance de liberación de cada comercial (propias o de todo el equipo), los estados y evidencia para convertir una separación comercial en alquiler confirmado, el evento de pago verificado y su manejo ante fallos o concurrencia, y el tratamiento de compromisos ERP. La separación técnica actual de dos horas no constituye aún una política comercial aprobada. D-005 permanece parcialmente abierta hasta implementar y validar ambos flujos y estos puntos.

La investigación técnica y el flujo recomendado se documentan en `docs/disponibilidad-centro-control.md`. Se propone consulta única como centro de control, separación breve al iniciar pago, conversión transaccional tras pago verificado e idempotencia de eventos. La duración y excepciones requieren decisión funcional antes de activar reservas reales.

Decisión adicional: para cada intervalo de una valla ofertable, el website muestra únicamente **disponible**, **reservada** (temporal) u **ocupada** (confirmada o bloqueada). “Próximamente libre” será una fecha calculada y visible como “disponible desde…”, no un cuarto estado. Las acciones simples del operador son tapar, tapar temporalmente y destapar; cada una exige fechas y se registra con trazabilidad. Actualmente la lista semanal se obtiene revisando un chat; el tablero web debe reemplazar esa consulta manual.

## D-014 — Captación CRM

Definir cuándo un formulario o conversación crea un lead, campos obligatorios, consentimiento, regla para detectar duplicados y equipo destino. La propuesta técnica es guardar el consentimiento y la fuente, crear lead solo después de validación, y usar correo o teléfono normalizados para advertir posibles duplicados sin fusionar registros automáticamente.

## D-016 — Alta y administración inicial

Estado técnico confirmado al 26/09/2026: registro público cerrado, confirmación por correo requerida, migraciones aplicadas y RLS activo. `asesoria@hercas.net` aceptó la invitación del primer administrador, inició sesión y accedió a `/plataforma` con `systems_admin`. El aislamiento entre dos empresas se probó en SQL con identidades y registros temporales revertidos, incluida la revocación de una membresía. La validación integral sigue pendiente: Supabase remoto tiene cero empresas y cero membresías reales, y falta comprobar el portal con dos sesiones de clientes reales. No cerrar D-016 ni BE-003 con la sola prueba SQL.

## D-020 — Límites y conservación

Definir tamaño y tipo de archivos permitidos, cuotas por empresa, retención de conversaciones, leads, cotizaciones, auditoría y soportes. La propuesta inicial es no habilitar Storage ni Realtime para datos de negocio hasta aprobar estas reglas; conservar auditoría por el período que determine el responsable de datos.
