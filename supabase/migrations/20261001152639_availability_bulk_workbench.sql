-- A manual reservation remains reserved until staff changes its interval.
alter table public.availability_entries drop constraint availability_entries_kind_check;
alter table public.availability_entries add constraint availability_entries_kind_check
  check (kind in ('hold','manual_reservation','reservation','maintenance','external_commitment'));
alter table public.availability_entries add column customer_name text
  check (customer_name is null or length(btrim(customer_name)) between 1 and 200);

create function public.public_availability_matrix(p_start date, p_end date)
returns table(asset_id uuid, states text[], calendar_revision bigint, observed_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  observed timestamptz := clock_timestamp();
begin
  if p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 30
     or p_end > today_bogota + 365 then
    raise exception 'Invalid availability interval' using errcode = '22023';
  end if;
  return query
  select a.id,
         array(
           select case
             when a.operational <> 'operational' then 'ocupada'
             when exists (
               select 1 from public.availability_entries e
               where e.asset_id = a.id and e.status = 'active'
                 and e.kind in ('reservation','maintenance','external_commitment')
                 and d.day_value::date between e.starts_on and e.ends_on
             ) then 'ocupada'
             when exists (
               select 1 from public.availability_entries e
               where e.asset_id = a.id and e.status = 'active'
                 and (e.kind = 'manual_reservation'
                      or (e.kind = 'hold' and e.expires_at > observed))
                 and d.day_value::date between e.starts_on and e.ends_on
             ) then 'reservada'
             else 'disponible' end
           from pg_catalog.generate_series(p_start, p_end, interval '1 day') d(day_value)
           order by d.day_value
         ), coalesce(v.revision, 0), observed
    from public.inventory_assets a
    left join public.availability_live_versions v on v.asset_id = a.id
   where a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
   order by a.canonical_code
   limit 200;
end;
$$;

create function public.public_availability_expirations(p_month date)
returns table(asset_code text, asset_name text, ends_on date, state text)
language plpgsql security definer set search_path = '' as $$
declare
  month_start date := date_trunc('month', p_month)::date;
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if p_month is null or not isfinite(p_month)
     or month_start < date_trunc('month', today_bogota)::date
     or month_start > date_trunc('month', today_bogota + 365)::date then
    raise exception 'Invalid expiration month' using errcode = '22023';
  end if;
  return query
  select a.canonical_code, a.name, e.ends_on,
         case when e.kind = 'manual_reservation' then 'reservada' else 'ocupada' end
    from public.availability_entries e
    join public.inventory_assets a on a.id = e.asset_id
   where a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
     and e.status = 'active' and e.kind in ('manual_reservation','reservation')
     and e.ends_on >= today_bogota
     and e.ends_on >= month_start
     and e.ends_on < (month_start + interval '1 month')::date
   order by e.ends_on, a.canonical_code
   limit 200;
end;
$$;

create function private.set_sales_availability_bulk(
  p_assets uuid[], p_start date, p_end date, p_state text,
  p_reason text, p_evidence text, p_customer_name text, p_expected_revisions bigint[]
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  manager boolean := private.has_permission('cotizador.availability.manage');
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  asset_id_value uuid;
  asset_row public.inventory_assets%rowtype;
  entry_row public.availability_entries%rowtype;
  current_revision bigint;
  asset_index integer;
begin
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability permission required' using errcode = '42501';
  end if;
  if p_assets is null or coalesce(array_length(p_assets, 1), 0) not between 1 and 100
     or array_length(p_expected_revisions, 1) is distinct from array_length(p_assets, 1)
     or exists (select 1 from unnest(p_assets) a where a is null)
     or (select count(distinct a) from unnest(p_assets) a) <> array_length(p_assets, 1)
     or p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 365
     or p_state is null or p_state not in ('disponible','reservada','ocupada')
     or p_reason is null or length(btrim(p_reason)) not between 1 and 1000
     or (p_state <> 'disponible' and (p_customer_name is null or length(btrim(p_customer_name)) not between 1 and 200))
     or (p_state = 'ocupada' and (p_evidence is null or length(btrim(p_evidence)) not between 1 and 1000))
     or exists (select 1 from unnest(p_expected_revisions) r where r is null or r < 0) then
    raise exception 'Invalid bulk availability change' using errcode = '22023';
  end if;

  -- All assets are locked in the same order as other availability RPCs.
  for asset_id_value in select a from unnest(p_assets) a order by a loop
    perform 1 from public.inventory_assets where id = asset_id_value for update;
    if not found then raise exception 'Asset unavailable' using errcode = '23514'; end if;
  end loop;
  for asset_index in 1..array_length(p_assets, 1) loop
    asset_id_value := p_assets[asset_index];
    select * into asset_row from public.inventory_assets where id = asset_id_value;
    if asset_row.lifecycle <> 'active' or asset_row.visibility <> 'visible'
       or asset_row.operational <> 'operational' or asset_row.is_provisional
       or asset_row.booking_mode <> 'exclusive_daily' then
      raise exception 'Asset unavailable for editing' using errcode = '23514';
    end if;
    select coalesce(v.revision, 0) into current_revision
      from public.inventory_assets a left join public.availability_live_versions v on v.asset_id = a.id
     where a.id = asset_id_value;
    if current_revision <> p_expected_revisions[asset_index] then
      raise exception 'Calendar changed; refresh before editing' using errcode = '40001';
    end if;

    update public.availability_entries
       set status = 'expired', revision = revision + 1, updated_at = now(),
           updated_by = actor, reason = 'Separación comercial vencida'
     where asset_id = asset_id_value and status = 'active' and kind = 'hold'
       and expires_at <= clock_timestamp();

    for entry_row in
      select * from public.availability_entries
       where asset_id = asset_id_value and status = 'active'
         and starts_on <= p_end and ends_on >= p_start
       order by starts_on for update
    loop
      if entry_row.kind not in ('hold','manual_reservation','reservation')
         or (not manager and entry_row.created_by <> actor) then
        raise exception 'Another user controls an overlapping interval' using errcode = '42501';
      end if;
      update public.availability_entries
         set status = 'cancelled', revision = revision + 1, updated_at = now(),
             updated_by = actor, reason = btrim(p_reason)
       where id = entry_row.id;
      if entry_row.starts_on < p_start then
        insert into public.availability_entries(
          asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
          reason, evidence_reference, customer_name, created_by, updated_by
        ) values (
          asset_id_value, entry_row.starts_on, p_start - 1, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name, entry_row.created_by, actor
        );
      end if;
      if entry_row.ends_on > p_end then
        insert into public.availability_entries(
          asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
          reason, evidence_reference, customer_name, created_by, updated_by
        ) values (
          asset_id_value, p_end + 1, entry_row.ends_on, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name, entry_row.created_by, actor
        );
      end if;
    end loop;
    if p_state <> 'disponible' then
      insert into public.availability_entries(
        asset_id, starts_on, ends_on, kind, status, reason,
        evidence_reference, customer_name, created_by, updated_by
      ) values (
        asset_id_value, p_start, p_end,
        case when p_state = 'reservada' then 'manual_reservation' else 'reservation' end,
        'active', btrim(p_reason),
        case when p_state = 'ocupada' then btrim(p_evidence) else null end,
        btrim(p_customer_name),
        actor, actor
      );
    end if;
  end loop;
  return array_length(p_assets, 1);
end;
$$;

create function public.set_sales_availability_bulk(
  p_assets uuid[], p_start date, p_end date, p_state text,
  p_reason text, p_evidence text, p_customer_name text, p_expected_revisions bigint[]
) returns integer language sql security invoker set search_path = '' as $$
  select private.set_sales_availability_bulk(
    p_assets, p_start, p_end, p_state, p_reason, p_evidence, p_customer_name, p_expected_revisions
  );
$$;

create function public.sales_availability_assignments(p_start date, p_end date)
returns table(asset_id uuid, starts_on date, ends_on date, state text, customer_name text)
language plpgsql security definer set search_path = '' as $$
declare today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
begin
  if (select auth.uid()) is null or not (
    private.has_permission('cotizador.availability.reserve')
    or private.has_permission('cotizador.availability.manage')
  ) then raise exception 'Availability permission required' using errcode = '42501'; end if;
  if p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 365 then
    raise exception 'Invalid assignment interval' using errcode = '22023';
  end if;
  return query
  select e.asset_id, e.starts_on, e.ends_on,
         case when e.kind in ('hold','manual_reservation') then 'reservada' else 'ocupada' end,
         coalesce(e.customer_name, q.customer_snapshot->>'name')
    from public.availability_entries e
    join public.inventory_assets a on a.id = e.asset_id
    left join public.quotes q on q.id = e.quote_id
   where e.status = 'active' and e.kind in ('hold','manual_reservation','reservation')
     and (e.kind <> 'hold' or e.expires_at > clock_timestamp())
     and e.starts_on <= p_end and e.ends_on >= p_start
     and a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
   order by e.ends_on, a.canonical_code limit 500;
end;
$$;

-- Preserve the one-valla calendar's 46-day limit for existing consumers.
create or replace function public.public_asset_availability(
  p_asset_code text, p_start date, p_end date
) returns table(available_on date, state text, observed_at timestamptz, calendar_revision bigint)
language plpgsql security definer set search_path = '' as $$
declare
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  observed timestamptz := clock_timestamp();
begin
  if p_asset_code is null or length(btrim(p_asset_code)) not between 1 and 80
     or p_start is null or p_end is null or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start or p_end - p_start > 45
     or p_end > today_bogota + 365 then
    raise exception 'Invalid public availability interval' using errcode = '22023';
  end if;
  return query
  select d.day_value::date,
         case
           when a.operational <> 'operational' then 'ocupada'
           when exists (
             select 1 from public.availability_entries e
             where e.asset_id = a.id and e.status = 'active'
               and e.kind in ('reservation','maintenance','external_commitment')
               and d.day_value::date between e.starts_on and e.ends_on
           ) then 'ocupada'
           when exists (
             select 1 from public.availability_entries e
             where e.asset_id = a.id and e.status = 'active'
               and (e.kind = 'manual_reservation'
                    or (e.kind = 'hold' and e.expires_at > observed))
               and d.day_value::date between e.starts_on and e.ends_on
           ) then 'reservada'
           else 'disponible' end,
         observed, coalesce(v.revision, 0)
    from public.inventory_assets a
    cross join pg_catalog.generate_series(p_start, p_end, interval '1 day') d(day_value)
    left join public.availability_live_versions v on v.asset_id = a.id
   where a.canonical_code = upper(btrim(p_asset_code))
     and a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
   order by d.day_value;
end;
$$;

create or replace function private.release_sales_availability(
  p_entry uuid, p_revision integer, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  manager boolean := private.has_permission('cotizador.availability.manage');
  entry_row public.availability_entries%rowtype;
  asset_id_value uuid;
begin
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability permission required' using errcode = '42501';
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
  if entry_row.kind not in ('hold','manual_reservation','reservation')
     or (not manager and entry_row.created_by <> actor) then
    raise exception 'This interval cannot be released by this user' using errcode = '42501';
  end if;
  update public.availability_entries
     set status = 'cancelled', reason = btrim(p_reason), revision = revision + 1,
         updated_at = now(), updated_by = actor
   where id = p_entry;
  return p_entry;
end;
$$;

revoke all on function public.public_availability_matrix(date,date),
  public.public_availability_expirations(date),
  private.set_sales_availability_bulk(uuid[],date,date,text,text,text,text,bigint[]),
  public.set_sales_availability_bulk(uuid[],date,date,text,text,text,text,bigint[]),
  public.sales_availability_assignments(date,date)
from public, anon, authenticated;
grant execute on function public.public_availability_matrix(date,date),
  public.public_availability_expirations(date) to anon, authenticated;
grant execute on function private.set_sales_availability_bulk(uuid[],date,date,text,text,text,text,bigint[]),
  public.set_sales_availability_bulk(uuid[],date,date,text,text,text,text,bigint[]),
  public.sales_availability_assignments(date,date)
to authenticated;
