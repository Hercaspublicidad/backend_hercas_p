# Migración Next.js → Python

## Alcance del sitio

Un proyecto Supabase de desarrollo para todo el sitio Hercas, con autenticación
compartida. El cotizador es el primer módulo de negocio. Producción tendrá su propio
entorno y configuración. Los permisos internos se almacenan en user_roles y se
revocan explícitamente; no se toman de datos editables por el usuario.

## Contratos trasladados

Decisión posterior del usuario: disponibilidades mantenidas en la plataforma por
una encargada y precios por producto gestionados por el rol de administrador de precios del cotizador. Diseñar paneles y
permisos separados, historial y publicación de tarifas; Odoo sigue aportando datos
maestros. La conciliación de compromisos ERP y la eventual salida de tarifas hacia
Odoo deben acordarse. Estos paneles y la actualización en vivo no están implementados.

- calculate-quote.ts → app/modules/cotizador/domain/quotes.py: alquiler y adicionales se suman por
  separado y redondean a COP entero; después se calculan descuento e IVA.
- resolve-price.ts → app/modules/cotizador/domain/pricing.py: cliente/producto, cliente/línea,
  cliente/portafolio, descuento por tipo y tarifa normal. La vigencia incluye ambos
  extremos. Coincidencia de cliente sin acentos, espacios exteriores o mayúsculas.
- validate-price-book.ts → modelos Pydantic: valores finitos, precios enteros
  seguros, fechas reales y coherencia del alcance de las reglas.
- holds.ts → app/modules/cotizador/domain/availability.py: 72 horas y rangos inclusivos.

Se usa Decimal y ROUND_HALF_UP para evitar el redondeo al par de round() en Python.
Esto conserva la intención monetaria del piloto, sin reproducir errores de coma
flotante de JavaScript. Se rechazan resultados fuera del rango entero seguro JS.

Endurecimientos deliberados: un tarifario borrador no resuelve un precio utilizable;
una publicación necesita autor y fecha; no se valida como reserva una separación
vencida ni sin soporte. Estas reglas puras no implementan bloqueo de base de datos.

## Diferencias que deben resolverse antes de las escrituras

El esquema de referencia tiene avances útiles, pero no representa todavía todas
las reglas del piloto:

1. customer_pricing_rules no tiene alcance por línea comercial.
2. add_priced_quote_item redondea a dos decimales, aplica otras reglas y no calcula
   IVA/descuento excepcional como el piloto. No se conecta esa RPC a un guardado
   que aparente equivalencia con la simulación Python.
3. quote_status SQL usa accepted/rejected; el piloto usa además held/reserved,
   occupied/completed/lost. Debe separarse el estado comercial del bloqueo físico
   y definir la equivalencia de estados antes de importar datos históricos.
4. Falta persistir separaciones/reservas y excluir cruces atómicamente. Consultar
   disponibilidad y después insertar por HTTP no evita reservas simultáneas.
5. Las cotizaciones y tarifas de localStorage necesitan importación validada y
   mapeo de IDs. No se deben publicar automáticamente las referencias del catálogo.
6. La unidad comercial puede ser semana u otra unidad: no derivar periods desde
   días sin una regla explícita por producto.

Siguiente corte: revisar y probar el esquema en el nuevo proyecto Supabase;
configurar perfiles/roles de prueba; preparar migraciones que concilien estas
diferencias; implementar transacciones de guardado/publicación/reserva; integrar
el frontend con autenticación y eliminar la autoridad de localStorage.

La base de identidad, su ajuste de seguridad y la base de cotizador/disponibilidad
se aplicaron en `hercas-platform-dev` el 17 de septiembre de 2026. La configuración
remota de Auth, los paneles y el resto de módulos siguen pendientes; ver
`supabase/README.md` y `supabase/COTIZADOR.md`.
