# Disponibilidad de vallas como centro de control

Investigación y estado de implementación al 01/10/2026. Desarrolla la decisión
D-005; la aceptación del flujo completo continúa pendiente.

## Estado vigente tras el Excel semanal recibido

La hoja de la semana del 27/09 al 03/10/2026 contiene 112 filas de vallas;
85 coinciden con el catálogo ofertable. Se guardaron las 112 filas originales
como evidencia privada en Supabase, con hash SHA-256 del archivo. Se cargaron
23 intervalos con cliente y fechas (20 marcados arrendados y tres que figuraban
disponibles pese a tener cliente hasta el 05/10). Esos tres intervalos siguen
ocupados hasta la fecha indicada para evitar una oferta duplicada. Cuatro vallas
quedaron no ofertables: CAC-005, PAA-005B, PRB-027 y SPT-001; esta última figura
arrendada sin fechas. APT-005 se liberó por decisión expresa del usuario y su
ocupación previa quedó cancelada en el historial. Las 85 marcas generales de
revisión inicial se despejaron y se quitó la notificación de Katherine.

El precio del Excel corresponde a alquileres registrados y se conserva sólo en
el reporte interno. Gabriel definirá el precio público. El tráfico sigue sin
fuente verificada para este archivo. Los asesores históricos aparecen por nombre
del Excel; para asignarlos como usuarios responsables en nuevas operaciones
faltan sus cuentas identificadas en Auth. El porcentaje de ocupación usa sólo
las 81 vallas ofertables y el intervalo visible.

## Regla principal

El calendario operativo de Supabase es la autoridad única. Website público,
vista del comercial, cotizador y procesos de conciliación leen el mismo estado.
Odoo aporta compromisos que deben incorporarse antes de ofrecer un periodo; no
confirma la disponibilidad por una vía paralela. Katherine coordina la operación.

La disponibilidad para un activo e intervalo se calcula a partir de su estado
operativo y comercial, su modalidad de venta y las ocupaciones vigentes:
reservas, separaciones no vencidas, mantenimiento y compromisos externos. Una
separación vencida deja de impedir la venta, pero su estado debe conciliarse en
la base antes de insertar una ocupación nueva. El resultado de una consulta es
informativo y lleva hora de actualización; cada escritura vuelve a comprobar el
activo y el intervalo en una transacción. La exclusión de periodos solapados en
PostgreSQL es la última protección contra la sobreventa.

El proceso actual depende de una persona que revisa un chat y envía una lista
semanal. La vista web debe sustituir esa lista como consulta diaria y mostrar
el cambio a todos en cuanto se guarda. Para el operador, las acciones principales
son **tapar**, **tapar temporalmente** y **destapar** una valla para fechas
concretas; el sistema traduce esas acciones a estados auditables.

Por decisión del usuario, cada intervalo de una valla ofertable muestra solo
tres estados: **disponible**, **reservada** y **ocupada**. “Próximamente libre”
no es un cuarto estado; se calcula como “disponible desde [fecha]” a partir del
fin conocido de la ocupación o reserva vigente. Si no hay fecha de liberación
confirmada, no se promete una. El estado siempre depende de las fechas
consultadas. Los activos sin validación o fuera de operación no se publican
como disponibles.

| Acción visible | Efecto en el calendario | Regla mínima |
| --- | --- | --- |
| Tapar | Pasa el intervalo a **ocupada** por alquiler confirmado o bloqueo operativo | Exigir tipo, fechas, responsable y soporte según el tipo |
| Tapar temporalmente | Pasa el intervalo a **reservada** hasta una hora de vencimiento | Mostrar vencimiento y volver a disponible automáticamente si no se confirma |
| Destapar | Cancela una ocupación o reserva temporal; queda **disponible** si no hay otro impedimento | Exigir permiso, motivo y revisión; una ocupación pagada requiere además tratar la devolución |

No se representa una valla como un único interruptor libre/ocupada: puede estar
ocupada una semana y libre la siguiente. La pantalla puede ofrecer botones
simples, pero cada acción se aplica a un intervalo explícito. Katherine ve
el tablero completo; cada comercial usa su cuenta y el mismo calendario.

## Flujo recomendado

1. **Consultar primero.** Cliente y comercial eligen valla y fechas de inicio
   y fin; el servidor devuelve estado por día, precio vigente si corresponde,
   hora de actualización y alternativas cuando el intervalo está ocupado.
   El comercial puede ver además quién la tapó, por qué y hasta cuándo; el
   cliente solo ve si se puede reservar. La
   vista pública solo expone disponibilidad agregada, nunca cliente, cotización,
   motivo de bloqueo, evidencia ni identidad del comercial.
2. **Comercial.** Entra con su cuenta, usa la vista conectada al cotizador y
   decide si crea una reserva temporal para el intervalo. Una operación
   de confirmación posterior convierte esa reserva temporal en ocupación/alquiler con
   evidencia y sin liberar temporalmente el intervalo. La duración de la
   separación y quién puede liberarla siguen pendientes de decisión.
3. **Cliente final.** Ve el mismo calendario. Al iniciar el pago se crea una
   reserva temporal breve asociada al intento de compra, para evitar cobrar dos
   veces la misma capacidad. La duración debe cubrir el tiempo real de pago y
   acordarse con negocio y la pasarela. La pantalla muestra que la reserva
   queda pendiente hasta que el servidor verifique el pago. Un evento firmado
   y procesado una sola vez convierte la reserva temporal vigente en ocupación en una
   transacción. Si el pago falla o la separación vence, se libera y se informa
   al cliente. Si llega pago tras vencimiento o aparece un conflicto, no se
   promete la valla: se abre conciliación y devolución o alternativa según la
   política comercial que se acuerde.
4. **Liberar o reprogramar.** Exigir identidad, permiso sobre esa reserva,
   motivo y revisión esperada. Registrar historial; después de un pago,
   coordinar devolución y cambio de estado comercial. No borrar ocupaciones.
5. **Actualizar las vistas.** Una señal Realtime anuncia que cambió una valla;
   cada vista vuelve a consultar el servidor. Al recuperar conexión también
   refresca. Una señal o caché nunca autoriza una reserva.

## Contratos y controles necesarios

- Consulta única por activo e intervalo, reutilizada por web pública y cotizador,
  con paginación y límites de rango. Estado visible: disponible, reservada u
  ocupada; “disponible desde” es información calculada. Los motivos internos
  y documentos nunca se exponen en la respuesta pública. Validar fecha civil
  de Bogotá y semántica de
  extremos inclusivos antes de diseñar la interfaz.
- Escrituras separadas y con permisos: separar, confirmar reserva comercial,
  confirmar pago, liberar y reprogramar. Comprobar rol y propiedad del objeto
  en el servidor; una cuenta cliente no llama operaciones de comercial.
- Idempotencia por intento de reserva y por evento del proveedor de pago.
  Verificar firma, importe, moneda, estado del pago, identificador de intento
  y correspondencia con activo/intervalo antes de confirmar. Procesar eventos
  duplicados y fuera de orden sin crear dos reservas. Las claves secretas solo
  residen en el servidor.
- Protección contra abuso en consulta pública, creación de separaciones y
  pago: límites por usuario/IP, intervalos válidos, observabilidad y alertas.
  Separaciones abandonadas expiran mediante proceso programado y también se
  depuran dentro de la transacción que intenta ocupar el activo.
- Pruebas de aceptación con dos comerciales y un cliente simultáneos; pago
  tardío, duplicado o fallido; expiración; liberación ajena; desconexión;
  compromiso de Odoo no conciliado; y recurso no habilitado.

## Estado comprobado en este repositorio

- `availability_entries` ya tiene exclusión GiST de intervalos activos para
  una valla exclusiva por día, historial y revisión. `create_sales_hold` exige
  permiso, fechas futuras y activo habilitado, y expira separaciones vencidas
  del activo antes de insertar. Su duración fija actual es dos horas, pendiente
  de política comercial.
- `sales_availability_calendar` consulta hasta 366 días por activo habilitado y
  devuelve solo disponible, reservada u ocupada, hora observada y revisión.
  La lectura pública usa `public_asset_availability` con intervalo acotado;
  aún falta un límite de uso por IP. `public_asset_available_days` continúa
  sin acceso anónimo.
- `create_sales_occupancy`, `confirm_sales_occupancy` y
  `release_sales_availability` permiten tapar, convertir una separación y destapar
  con fechas, soporte, propietario y revisión. Todos los comerciales conservan
  `reserve`; el permiso global `manage` queda reservado a administración.
  La confirmación vuelve a comprobar que la valla siga operativa. La prueba remota
  reversible cubrió estados, cruce de fechas, propiedad, revisión y retirada de
  operación entre separación y confirmación.
  Faltan pago, aceptación integral y conciliación de Odoo.
- Por autorización de Carlos, las 85 vallas se inicializaron como disponibles en
  `hercas-platform-dev` para probar el motor. Este fue el estado inicial antes
  de importar la hoja semanal descrita arriba.
- `public_availability_assets` y `public_asset_availability` entregan al website
  solo código, nombre, revisión pendiente y estado diario. El intervalo público
  máximo es de 46 días inclusivos dentro del próximo año. La vista
  `/disponibilidad` muestra los estados y se actualiza cada 30 segundos.
- La vista `/disponibilidad` permite a cuentas comerciales o de gestión marcar
  como ocupada la valla seleccionada durante las fechas consultadas, indicando
  motivo y referencia de soporte. También permite liberar una ocupación con
  motivo y revisión esperada; el servidor verifica permisos, propiedad y cruce
  de fechas. Prueba reversible del 01/10: APT-003 pasó a ocupada y volvió a
  disponible; quedan cero ocupaciones activas y una fila cancelada de auditoría.
- Actualización 01/10: `availability_bulk_workbench` añade una matriz pública
  acotada a 31 días, reservas manuales persistentes (`manual_reservation`),
  cambios masivos de hasta 100 vallas y 12 meses con revisión optimista,
  control de propietario y transacción única. Un cambio parcial divide los
  intervalos anteriores y conserva el estado fuera de las fechas editadas.
  Las reservas manuales siguen vigentes hasta que un usuario autorizado las
  convierta, cambie o libere; `create_sales_hold` continúa con dos horas.
  Cada reserva/ocupación manual nueva exige nombre de cliente; la consulta
  autenticada `sales_availability_assignments` lo entrega al equipo comercial.
  La tabla interna sigue protegida por `cotizador.read`. La consulta
  pública muestra estados y próximos vencimientos sin identidad del cliente.
  El website muestra las 85 vallas en una tabla compacta, acciones dentro del
  calendario, selección múltiple, atajos de 1/3/6/12 meses y reporte mensual.
  Prueba remota revertida: APT-003 reservada 32 días, ocupada ocho días y
  liberada tres días intermedios; el resto mantuvo su estado esperado.
  Una migración correctiva alinea `sales_availability_calendar` con la matriz
  y la consulta pública: las tres devolvieron `reservada` para una reserva
  manual en una segunda prueba reversible.
  `next build`, TypeScript y ESLint pasaron; la página cargó 85 vallas en navegador.
  La ocupación anterior de APT-005 se canceló posteriormente con el Excel semanal.
- Aún no se identificó una cuenta activa de Katherine por nombre en la base de
  desarrollo. Para administrar ocupaciones ajenas, su cuenta debe recibir el rol
  `availability_manager`; cualquier cuenta `sales` activa puede ocupar fechas y
  liberar las ocupaciones que creó.
- El plan oficial UNC y el libro colaborativo de SharePoint registran la consulta
  pública y el control comercial comprobado, con estado parcial. La carga semanal
  sustituyó la revisión general inicialmente prevista; quedan los casos concretos
  descritos arriba y la aceptación integral del negocio.

## Campaña, asesor, indicadores y descargas (01/10/2026)

- La migración `availability_campaign_advisor` agrega campaña y asesor responsable
  a cada intervalo de reserva u ocupación manual. El asesor se selecciona entre
  cuentas comerciales activas; el servidor comprueba permisos y conserva los
  datos cuando una corrección divide el intervalo. El reporte interno devuelve
  cliente, campaña y asesor. Una prueba transaccional revertida de APT-003
  confirmó la lectura sin dejar filas de prueba.
- El módulo muestra vencimientos e indicadores antes del buscador. Ocupación real
  es días-valla ocupados entre días-valla del período visible; el compromiso
  incluye también los días reservados. Son indicadores del calendario consultado,
  no una cifra de facturación. Las dos descargas XLSX son disponibilidad y
  vencimientos del mes. La primera incluye hoja para clientes y, solo a personal
  autorizado, hoja interna con cliente, campaña, asesor y ocupación por valla.
  La segunda agrega esos datos comerciales únicamente para personal autorizado.
- La hoja de clientes lista las vallas disponibles durante todo el período
  consultado. Incluye enlace a la foto principal cuando existe. Precio y tráfico
  figuran por confirmar/verificar: Gabriel definirá la tarifa pública y el
  archivo recibido no verifica tráfico. No se inventan valores.
- Dos perfiles comerciales
  activos tienen el nombre genérico «Usuario invitado»; en el selector se muestra
  el correo de su cuenta para distinguirlos. Los asesores del Excel importado
  conservan su nombre histórico mientras se identifican sus cuentas.

## Fuentes técnicas


- PostgreSQL: [rangos y restricciones de exclusión](https://www.postgresql.org/docs/current/rangetypes.html)
  y [transacciones concurrentes](https://www.postgresql.org/docs/current/transaction-iso.html).
- Supabase: [RLS y permisos de tablas](https://supabase.com/docs/guides/database/postgres/row-level-security)
  y [notificaciones de cambios](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes).
- Stripe como referencia de pasarela, sin selección de proveedor:
  [webhooks firmados, duplicados y orden de eventos](https://docs.stripe.com/webhooks)
  e [idempotencia](https://docs.stripe.com/api/idempotent_requests).
- OWASP: [autorización por objeto](https://api-security.owasp.org/editions/2023/en/0xa1-broken-object-level-authorization/).
