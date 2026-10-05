-- Carlos authorized an initial all-available calendar in the development
-- project so Katherine can correct the real occupancy afterward. This marker
-- must remain visible to staff until each asset is reviewed.
alter table public.inventory_assets
  add column availability_review_required boolean not null default false;

do $$
declare
  changed_count integer;
begin
  update public.inventory_assets
     set visibility = 'visible',
         operational = 'operational',
         booking_mode = 'exclusive_daily',
         is_provisional = false,
         availability_review_required = true,
         source_reference = concat_ws(
           ' | ', source_reference,
           'Disponibilidad inicial temporal en hercas-platform-dev por solicitud de Carlos; Katherine debe revisar contratos, bloqueos y fechas reales'
         ),
         updated_at = now()
   where lifecycle = 'active'
     and visibility = 'hidden'
     and is_provisional;
  get diagnostics changed_count = row_count;
  if changed_count <> 85 then
    raise exception 'Expected 85 provisional assets, updated %', changed_count;
  end if;
end;
$$;

-- A manager's explicit review through this existing RPC clears the marker.
create or replace function private.configure_inventory_asset_for_availability(
  p_asset uuid,
  p_visibility text,
  p_operational text,
  p_source_reference text
) returns uuid
language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null
     or not private.has_permission('cotizador.availability.manage') then
    raise exception 'Availability permission required' using errcode = '42501';
  end if;
  if p_visibility not in ('hidden', 'visible')
     or p_operational not in ('operational', 'maintenance', 'unavailable')
     or p_source_reference is null
     or length(btrim(p_source_reference)) not between 1 and 1000 then
    raise exception 'Invalid availability configuration' using errcode = '22023';
  end if;

  update public.inventory_assets
     set visibility = p_visibility,
         operational = p_operational,
         booking_mode = 'exclusive_daily',
         is_provisional = false,
         availability_review_required = false,
         source_reference = btrim(p_source_reference),
         last_verified_at = now(),
         updated_at = now()
   where id = p_asset
     and lifecycle = 'active';
  if not found then
    raise exception 'Active inventory asset required' using errcode = '23514';
  end if;
  return p_asset;
end;
$$;
