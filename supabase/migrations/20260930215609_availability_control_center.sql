-- The authenticated sales calendar and three audited commercial actions.
-- Public customer reads still require the rate-limited API gateway.

create function private.sales_availability_calendar(
  p_asset uuid, p_start date, p_end date
) returns table(available_on date, state text, observed_at timestamptz, calendar_revision bigint)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  observed timestamptz := clock_timestamp();
begin
  if actor is null or not private.has_permission('cotizador.read') then
    raise exception 'Availability read permission required' using errcode = '42501';
  end if;
  if p_asset is null or p_start is null or p_end is null
     or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 365 then
    raise exception 'Invalid calendar interval' using errcode = '22023';
  end if;

  return query
  select day_value::date,
         case
           when asset.operational <> 'operational' then 'ocupada'
           when exists (
             select 1 from public.availability_entries e
              where e.asset_id = asset.id and e.status = 'active'
                and e.kind <> 'hold'
                and day_value::date between e.starts_on and e.ends_on
           ) then 'ocupada'
           when exists (
             select 1 from public.availability_entries e
              where e.asset_id = asset.id and e.status = 'active'
                and e.kind = 'hold' and e.expires_at > observed
                and day_value::date between e.starts_on and e.ends_on
           ) then 'reservada'
           else 'disponible'
         end,
         observed, coalesce(v.revision, 0)
    from public.inventory_assets asset
    cross join pg_catalog.generate_series(p_start, p_end, interval '1 day') day_value
    left join public.availability_live_versions v on v.asset_id = asset.id
   where asset.id = p_asset
     and asset.lifecycle = 'active'
     and asset.visibility = 'visible'
     and not asset.is_provisional
     and asset.booking_mode = 'exclusive_daily'
   order by day_value;
end;
$$;

create function public.sales_availability_calendar(
  p_asset uuid, p_start date, p_end date
) returns table(available_on date, state text, observed_at timestamptz, calendar_revision bigint)
language sql security invoker set search_path = '' as $$
  select * from private.sales_availability_calendar(p_asset, p_start, p_end);
$$;

create function private.confirm_sales_occupancy(
  p_entry uuid, p_revision integer, p_reason text, p_evidence text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  asset_id_value uuid;
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
  perform 1 from public.inventory_assets where id = asset_id_value for update;
  select * into entry_row from public.availability_entries where id = p_entry for update;
  if not found or entry_row.status <> 'active' or entry_row.kind <> 'hold'
     or entry_row.expires_at <= clock_timestamp()
     or entry_row.revision <> p_revision then
    raise exception 'Calendar changed; refresh before editing' using errcode = '40001';
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

create function public.confirm_sales_occupancy(
  p_entry uuid, p_revision integer, p_reason text, p_evidence text
) returns uuid
language sql security invoker set search_path = '' as $$
  select private.confirm_sales_occupancy(p_entry, p_revision, p_reason, p_evidence);
$$;

create function private.create_sales_occupancy(
  p_asset uuid, p_start date, p_end date, p_reason text,
  p_evidence text, p_quote uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  asset_row public.inventory_assets%rowtype;
  manager boolean;
  result uuid;
begin
  manager := private.has_permission('cotizador.availability.manage');
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability reservation permission required' using errcode = '42501';
  end if;
  if p_asset is null or p_start is null or p_end is null
     or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 365
     or p_reason is null or length(btrim(p_reason)) not between 1 and 1000
     or p_evidence is null or length(btrim(p_evidence)) not between 1 and 1000 then
    raise exception 'Invalid occupancy interval or evidence' using errcode = '22023';
  end if;
  select * into asset_row from public.inventory_assets where id = p_asset for update;
  if not found or asset_row.lifecycle <> 'active'
     or asset_row.visibility <> 'visible' or asset_row.operational <> 'operational'
     or asset_row.is_provisional or asset_row.booking_mode <> 'exclusive_daily' then
    raise exception 'Asset is not available for commercial occupancy' using errcode = '23514';
  end if;
  if p_quote is not null and not exists (
    select 1 from public.quotes q
    join public.customer_accounts c on c.id = q.customer_id and c.is_active
    where q.id = p_quote and q.status in ('draft','issued','accepted')
      and (manager or q.created_by = actor)
  ) then
    raise exception 'Quote unavailable' using errcode = '23514';
  end if;
  update public.availability_entries
     set status = 'expired', revision = revision + 1,
         reason = 'Separación comercial vencida', updated_at = now(), updated_by = actor
   where asset_id = p_asset and status = 'active' and kind = 'hold'
     and expires_at <= clock_timestamp();
  insert into public.availability_entries(
    asset_id, starts_on, ends_on, kind, status, quote_id,
    reason, evidence_reference, created_by, updated_by
  ) values (
    p_asset, p_start, p_end, 'reservation', 'active', p_quote,
    btrim(p_reason), btrim(p_evidence), actor, actor
  ) returning id into result;
  return result;
end;
$$;

create function public.create_sales_occupancy(
  p_asset uuid, p_start date, p_end date, p_reason text,
  p_evidence text, p_quote uuid default null
) returns uuid
language sql security invoker set search_path = '' as $$
  select private.create_sales_occupancy(
    p_asset, p_start, p_end, p_reason, p_evidence, p_quote
  );
$$;

create function private.release_sales_availability(
  p_entry uuid, p_revision integer, p_reason text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  asset_id_value uuid;
  entry_row public.availability_entries%rowtype;
  manager boolean;
begin
  manager := private.has_permission('cotizador.availability.manage');
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability reservation permission required' using errcode = '42501';
  end if;
  if p_entry is null or p_revision is null or p_revision < 1
     or p_reason is null or length(btrim(p_reason)) not between 1 and 1000 then
    raise exception 'Invalid release request' using errcode = '22023';
  end if;
  select asset_id into asset_id_value from public.availability_entries where id = p_entry;
  perform 1 from public.inventory_assets where id = asset_id_value for update;
  select * into entry_row from public.availability_entries where id = p_entry for update;
  if not found or entry_row.status <> 'active' or entry_row.revision <> p_revision then
    raise exception 'Calendar changed; refresh before editing' using errcode = '40001';
  end if;
  if entry_row.kind not in ('hold', 'reservation')
     or (not manager and entry_row.created_by <> actor) then
    raise exception 'This occupancy cannot be released by this user' using errcode = '42501';
  end if;
  update public.availability_entries
     set status = 'cancelled', reason = btrim(p_reason), revision = revision + 1,
         updated_at = now(), updated_by = actor
   where id = p_entry;
  return p_entry;
end;
$$;

create function public.release_sales_availability(
  p_entry uuid, p_revision integer, p_reason text
) returns uuid
language sql security invoker set search_path = '' as $$
  select private.release_sales_availability(p_entry, p_revision, p_reason);
$$;

revoke all on function
  private.sales_availability_calendar(uuid,date,date),
  private.confirm_sales_occupancy(uuid,integer,text,text),
  private.create_sales_occupancy(uuid,date,date,text,text,uuid),
  private.release_sales_availability(uuid,integer,text),
  public.sales_availability_calendar(uuid,date,date),
  public.confirm_sales_occupancy(uuid,integer,text,text),
  public.create_sales_occupancy(uuid,date,date,text,text,uuid),
  public.release_sales_availability(uuid,integer,text)
from public, anon, authenticated;

grant execute on function
  private.sales_availability_calendar(uuid,date,date),
  private.confirm_sales_occupancy(uuid,integer,text,text),
  private.create_sales_occupancy(uuid,date,date,text,text,uuid),
  private.release_sales_availability(uuid,integer,text),
  public.sales_availability_calendar(uuid,date,date),
  public.confirm_sales_occupancy(uuid,integer,text,text),
  public.create_sales_occupancy(uuid,date,date,text,text,uuid),
  public.release_sales_availability(uuid,integer,text)
to authenticated;
