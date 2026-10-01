-- Reconciles the published website inventory with the operational catalog.
-- These rows remain hidden, provisional and unbookable until reception verifies
-- their current commercial status through the availability activation workflow.
with source(canonical_code, product_code, name, description, source_reference) as (
  values
    (
      'CAC-005',
      'HRC-P-021308',
      'VALLA CAC-005 EN CAUCASIA 10X4 MEDELLÍN-CAUCASIA',
      'Estación Terpel entrada al aeropuerto, antes del Hospital César Uribe Piedrahíta',
      'Inventario web vigente — ficha CAC-005, conciliación 2026-09-30'
    ),
    (
      'PAA-005B',
      'HRC-P-021372',
      'VALLA PAA-005B EN PALMAS 12X4 ORIENTE-OCCIDENTE',
      'Asados Doña Rosa Aeropuerto',
      'Inventario web vigente — ficha PAA-005B, conciliación 2026-09-30'
    ),
    (
      'PRB-027',
      'HRC-P-021413',
      'VALLA PRB-027 EN AUTOPISTA MEDELLÍN-BOGOTÁ 12X4 OCCIDENTE-ORIENTE',
      'Autopista Medellín Bogotá',
      'Inventario web vigente — ficha PRB-027, conciliación 2026-09-30'
    )
)
insert into public.inventory_assets(
  product_id, canonical_code, name, description, visibility, lifecycle,
  operational, is_provisional, booking_mode, source_reference
)
select
  product.id, source.canonical_code, source.name, source.description, 'hidden',
  'active', 'unverified', true, 'unconfigured', source.source_reference
from source
join public.products product on product.code = source.product_code
on conflict (canonical_code) do nothing;
