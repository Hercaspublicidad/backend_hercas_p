# Base de cotizador y disponibilidad

Aplicada en `hercas-platform-dev` (`mmstapaovlvflbiiqgxv`) el 17 de septiembre de
2026: `20260917224601_cotizador_availability_foundation`. La plataforma tiene ahora
18 tablas públicas con RLS. No se cargaron productos, tarifas, clientes ni reservas
reales. No se modificó Odoo.

| Tabla nueva | Función |
| --- | --- |
| product_families | Familias del catálogo |
| commercial_lines | Líneas comerciales |
| products | Producto, unidad comercial, visibilidad y referencia Odoo |
| inventory_assets | Activos físicos, estado y modalidad de ocupación |
| product_price_versions | Importe COP, impuesto explícito, unidad, vigencia y versión |
| quotes | Cabecera, empresa cliente, instantáneas e importes |
| quote_lines | Detalle ligado a una versión de precio y producto |
| availability_entries | Separaciones, reservas, mantenimiento y compromisos externos |
| availability_events | Historial de cambios del calendario |

Se reutiliza `customer_accounts` para evitar duplicar empresas cliente. Su referencia
Odoo es opcional; una carga posterior debe resolver y verificar el mapeo.

## Reglas implementadas

- Precios positivos, publicación identificada por autor/fecha y vigencia sin cruces
  para el mismo producto. Una versión publicada solo admite retiro; no edición de
  su importe. Borradores y precios retirados no sirven para nuevas líneas.
- Al insertar una línea, PostgreSQL obtiene el precio, impuesto y descripción de
  la versión publicada. Los importes suministrados por el operador se reemplazan.
  Se calculan subtotal e impuesto redondeados por línea, luego se suman en cabecera.
  Esta convención es específica del nuevo documento persistido: la simulación piloto
  sigue redondeando subtotales agrupados y no emite ni guarda documentos oficiales.
- Las cotizaciones empiezan vacías en borrador. Emitir exige líneas y vigencia;
  después cabecera y líneas quedan inmutables. Corrección, aceptación, cancelación,
  descuentos y documentos adicionales requieren un flujo posterior; los descuentos
  persistidos están bloqueados en cero hasta definir sus autorizaciones.
- Disponibilidad diaria con ambas fechas inclusivas y exclusión PostgreSQL para
  impedir ocupaciones activas superpuestas en un mismo activo. Ver
  [restricciones de rangos](https://www.postgresql.org/docs/current/rangetypes.html#RANGETYPES-CONSTRAINT).
- Solo activos verificados, no provisionales y `exclusive_daily` admiten ocupaciones
  mediante la función de gestión. Reservas/separaciones requieren además estado
  operativo y visibilidad. Los activos comienzan sin configurar; no se asume que
  un catálogo recién importado esté disponible.
- Las separaciones exigen vencimiento explícito; no se generalizó la regla piloto
  de 72 horas. Al añadir ocupación se expiran las separaciones vencidas del activo
  dentro de la misma transacción. No hay un cron de expiración desplegado.
- Cancelación con motivo y revisión esperada: una edición desactualizada falla.
  Reservas y compromisos externos requieren referencia de soporte; todavía no se
  valida la existencia del archivo en Storage. No guardar URLs públicas de documentos
  privados ni credenciales en ese campo.
- Calendario y cotizaciones son internos. No se publican datos comerciales al acceso
  anónimo ni a cuentas cliente; la publicación del portal externo se implementará
  con políticas específicas. La tabla de disponibilidad es consultable por personal
  con `cotizador.read`; el endpoint de calendario omite razones y soporte.

## Operaciones disponibles y pendientes

RPC de Supabase `add_availability` y `cancel_availability` verifican identidad activa
y `cotizador.availability.manage`, bloquean el activo y conservan historial. Las
funciones elevadas permanecen en `private`; las públicas son invoker. No se conceden
escrituras genéricas a `authenticated`, ni siquiera para administradores web.

La API Python expone `GET /api/v1/cotizador/disponibilidades` con `asset_id`,
`starts_on`, `ends_on`, paginación e intervalo de hasta 366 días. Filtra ocupaciones
activas y separaciones aún vigentes. Esta lista no confirma disponibilidad: también
debe comprobarse la configuración y operación del activo al reservar.

Productos, inventario, clientes y cotizaciones tienen tablas compatibles con sus
rutas de lectura. La gestión de catálogo, edición/publicación de tarifas y escritura
de cotizaciones se realiza **solo por operador SQL** en esta etapa. Tener el rol
`pricing_manager` aún no proporciona una pantalla ni una RPC para editar precios.
Faltan endpoints/paneles de gestión, conversión atómica de separación en reserva,
reprogramación y administración operativa de activos.

También faltan importación/reconciliación Odoo, Auth remoto por invitación, primer
administrador, publicación al cliente y notificaciones en vivo. `shared_pending`
bloquea la venta parcial de pantallas hasta definir segundos, franjas o capacidad.
La base no añade scripts ni suscripciones al frontend público.

## Verificación

- 27 pruebas PostgreSQL embebido, incluyendo identidad, RLS, roles separados,
  exclusión temporal, expiración, trazabilidad, precios y cotizaciones inmutables.
- 44 pruebas Python de API/dominio, con servicios externos simulados.
- Verificación remota de RLS y grants en las 18 tablas; asesor de seguridad sin
  hallazgos. Rendimiento: solo [índices aún sin uso](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index)
  en esta base nueva, conservados por su propósito de integridad/consulta.
- Prueba transaccional remota de solapamiento, cancelación, historial y reutilización
  de fechas; todos sus registros se revirtieron con ROLLBACK, sin enviar correos.
- No se probaron dos conexiones concurrentes, carga real, entrega Realtime ni flujo
  completo de Auth. La exclusión de ocupaciones reside en una restricción de la BD,
  no solo en una consulta previa del backend.
