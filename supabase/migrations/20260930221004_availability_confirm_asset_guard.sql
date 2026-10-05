-- A hold cannot become a confirmed occupancy after the asset has been removed
-- from sale or marked out of operation.
create or replace function private.confirm_sales_occupancy(
  p_entry uuid, p_revision integer, p_reason text, p_evidence text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  asset_id_value uuid;
  asset_row public.inventory_assets%rowtype;
  entry_row public.availability_entries%rowtype;
  manager boolean;
begin
  manager := private.has_permission('cotizador.availability.manage');
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability reservation permission required' using errcode = '42501';
  end if;
  if p_entry is null or p_revision is null or p_revision < 1
     or p_reason is null or length(btrim(p_reason)) not between 1 and 1000
     or p_evidence is null or length(btrim(p_evidence)) not between 1 and 1000 then
    raise exception 'Invalid occupancy confirmation' using errcode = '22023';
  end if;
  select asset_id into asset_id_value from public.availability_entries where id = p_entry;
  select * into asset_row from public.inventory_assets where id = asset_id_value for update;
  select * into entry_row from public.availability_entries where id = p_entry for update;
  if not found or entry_row.status <> 'active' or entry_row.kind <> 'hold'
     or entry_row.expires_at <= clock_timestamp()
     or entry_row.revision <> p_revision then
    raise exception 'Calendar changed; refresh before editing' using errcode = '40001';
  end if;
  if asset_row.lifecycle <> 'active' or asset_row.visibility <> 'visible'
     or asset_row.operational <> 'operational' or asset_row.is_provisional
     or asset_row.booking_mode <> 'exclusive_daily' then
    raise exception 'Asset is no longer available for occupancy' using errcode = '23514';
  end if;
  if not manager and entry_row.created_by <> actor then
    raise exception 'This reservation belongs to another commercial user' using errcode = '42501';
  end if;
  update public.availability_entries
     set kind = 'reservation', expires_at = null, reason = btrim(p_reason),
         evidence_reference = btrim(p_evidence), revision = revision + 1,
         updated_at = now(), updated_by = actor
   where id = p_entry;
  return p_entry;
end;
$$;
