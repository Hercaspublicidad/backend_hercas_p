# Base de cotizador y disponibilidad

## Integración del código al 05/10/2026

La rama `main` incluye las migraciones posteriores al estado descrito abajo:
`20261001214500_availability_barter_labels.sql`,
`20261001220000_manual_reservation_three_day_expiry.sql` y
`20261001221500_availability_barter_public_privacy.sql`. La clasificación de canje solo se anuncia para activos
operativos marcados como disponibles en la fuente semanal; la función pública
final entrega únicamente el ID del activo, sin nombre del socio. Las reservas
manuales vencen a los tres días, con expiración al consultar o insertar y un
trabajo `pg_cron` cada minuto. El `hold` comercial conserva su plazo técnico
separado. Esta integración de archivos no constituye una nueva ejecución de las
migraciones ni una aceptación del flujo completo de venta.

## Estado vigente del 01/10/2026

El Excel semanal de Katherine (27/09 a 03/10) se importó a Supabase desarrollo:
112 filas de fuente, 85 vallas coincidentes, 23 periodos con fechas y cliente,
cuatro activos no ofertables por su estado o por falta de fechas. APT-005 quedó
disponible por decisión expresa de Carlos; la ocupación anterior permanece
cancelada en el historial. Las 85 marcas de revisión inicial se despejaron y
el website ya no muestra el aviso general de Katherine. El calendario y los
vencimientos leen estos datos. Las cifras de alquiler del archivo son internas;
Gabriel definirá el precio público. Los asesores históricos se conservan por
nombre de origen, pendientes de vincular a cuentas de Auth identificadas.

`availability_campaign_advisor`, `availability_weekly_source_import`,
`availability_public_operational_read` y `preserve_import_advisor` agregan
campaña/asesor por intervalo, procedencia del Excel, lectura de estado operativo
y preservación de nombres al corregir parcialmente una ocupación. El tablero
muestra indicadores excluyendo las cuatro vallas no ofertables y ofrece dos
descargas XLSX; la hoja interna incluye alquileres de referencia y responsables.
El precio público y el tráfico no se publican sin la fuente aprobada.

## Avance del motor al 30 de septiembre de 2026

Decisión funcional del 30/09: la plataforma web es la autoridad de
disponibilidad. Supabase mantiene el calendario compartido que consulta el
website en tiempo real. Odoo se concilia como fuente de compromisos externos,
sin confirmar la disponibilidad por separado. La política de vencimiento y
cancelación continúa abierta en D-005.

Cada comercial usará su cuenta y vista de disponibilidad del website, conectada
al cotizador, para indicar las fechas de inicio y fin del alquiler, reservar si
lo decide y liberar vallas. Katherine lidera este proceso. El cliente final y
el comercial consultan el mismo calendario; la reserva del cliente final se
confirma al pagar. El alcance de la liberación, el paso de separación a alquiler
confirmado y la conexión segura con el pago aún requieren reglas y desarrollo.
El flujo propuesto y las brechas concretas están en
`docs/disponibilidad-centro-control.md`.
Los tres estados visibles acordados son disponible, reservada (temporal) y
ocupada. “Disponible desde [fecha]” se calcula; no se guarda como otro estado.

Las migraciones `availability_engine_operations`,
`availability_engine_security_hardening` y `harden_sales_hold` ya figuran en
`hercas-platform-dev`. Se agregaron configuración controlada de activos,
separaciones comerciales, etiquetas, referencia verificada de imagen, cola
auditable de notificaciones y una señal Realtime que solo indica que el
calendario cambió. La entrega de correos y el reporte Excel siguen pendientes.

La separación comercial verifica fechas futuras y finitas en horario de
Bogotá. Cuando se vincula una cotización, un comercial solo puede usar una
cotización propia de una cuenta activa; el responsable de disponibilidad
puede gestionar las del equipo. La restricción de exclusión de PostgreSQL
sigue impidiendo dos ocupaciones activas que se crucen.

Se probó la RPC remota con dos identidades en una transacción revertida:
cotización ajena y fechas inválidas rechazadas, cotización propia aceptada y
solapamiento rechazado. Después de `ROLLBACK` se confirmaron cero cuentas,
cotizaciones y ocupaciones de prueba. Después, Carlos autorizó habilitar
provisionalmente las 85 vallas en desarrollo para visualizar el motor, con
revisión pendiente de Katherine. No se ha probado la conexión completa con el panel ni
una reserva real. La duración de la separación implementada actualmente es
de dos horas y requiere decisión funcional en D-005 antes de usarse como
política comercial definitiva.

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
- Cotizaciones, motivos y soportes son internos. La consulta pública de
  disponibilidad solo expone código, nombre, revisión pendiente y estado diario;
  omite datos comerciales. La tabla de disponibilidad requiere `cotizador.read`.

## Operaciones disponibles y pendientes

Actualización 30/09/2026: la migración `availability_control_center` añadió
`sales_availability_calendar` (estados por día, 366 días como máximo),
`create_sales_occupancy` (tapar), `confirm_sales_occupancy` (convertir una
separación sin liberar el intervalo) y `release_sales_availability` (destapar).
Estas RPC son solo para cuentas comerciales autenticadas; verifican permiso,
propiedad de la ocupación y revisión. `availability_sales_least_privilege`
retiró `cotizador.availability.manage` del rol `sales`, que antes permitía
modificar reservas ajenas por la RPC administrativa. El rol conserva
`cotizador.availability.reserve`. La consulta pública del website usa
`public_availability_assets` y `public_asset_availability`, con respuesta sin
datos internos, intervalo de 46 días inclusivos y horizonte de un año.
Queda pendiente protección adicional contra abuso.
`availability_confirm_asset_guard` impide confirmar una separación si el activo
dejó de estar visible u operativo antes de la confirmación.

Antes de recibir el Excel semanal, `hercas-platform-dev` tenía 85 activos
habilitados provisionalmente, cero ocupaciones activas y 85 marcas de revisión.
El estado vigente después de la carga consta al inicio de este documento.
La vista `/disponibilidad` de la rama frontend `integraci0n` ya permite a
comerciales autenticados marcar ocupaciones con motivo/soporte y liberarlas con
motivo. La prueba reversible del 01/10 pasó de disponible a ocupada y de vuelta
a disponible en APT-003; el historial cancelado queda auditado.
La prueba remota de las nuevas RPC se ejecutó dentro de una transacción revertida.

El 01/10/2026 se aplicó `availability_bulk_workbench` en
`hercas-platform-dev`. `public_availability_matrix` lee hasta 31 días de las
85 vallas en una sola respuesta y `public_availability_expirations` lista
vencimientos del mes sin datos de cliente. Para comerciales autenticados,
`sales_availability_assignments` muestra valla, intervalo, estado y cliente.
`set_sales_availability_bulk` permite cambiar hasta 100 vallas y un rango de
hasta 12 meses a disponible, reservada u ocupada. Exige cliente en reservas y
ocupaciones nuevas, soporte al ocupar, motivo en todo cambio, revisiones actuales
y permiso sobre cada intervalo afectado. Conserva los fragmentos que quedan
fuera del rango editado y ejecuta toda la selección en una transacción.
`manual_reservation` permanece reservada hasta liberación o cambio manual;
`hold` mantiene su vencimiento de dos horas. La prueba reversible produjo
reservada/ocupada/disponible/ocupada/reservada en el mismo activo y se revirtió.
Esa revisión general inicial fue sustituida después por el Excel semanal importado.
`availability_manual_state_consistency` asegura que el calendario comercial
devuelva `reservada` para la reserva manual, igual que las dos consultas
públicas; la comparación se probó en una transacción revertida.

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
Faltan endpoints/paneles de gestión, reprogramación y administración operativa
de activos. La conversión atómica comercial ya está en la base.

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
