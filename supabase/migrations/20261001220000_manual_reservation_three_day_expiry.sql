-- Temporary commercial reservations last at most 72 hours from creation.
-- Applied in the development project; keep this versioned SQL with the backend.
alter table public.availability_entries drop constraint availability_entries_check1;
alter table public.availability_entries add constraint availability_entries_expiry_check
  check (
    (kind = 'hold' and expires_at is not null and isfinite(expires_at) and expires_at > created_at)
    or (kind = 'manual_reservation' and expires_at is not null and isfinite(expires_at)
        and expires_at > created_at and expires_at <= created_at + interval '3 days')
    or (kind not in ('hold','manual_reservation') and expires_at is null)
  );
alter table public.availability_entries drop constraint availability_entries_check3;
alter table public.availability_entries add constraint availability_entries_expired_kind_check
  check (status <> 'expired' or kind in ('hold','manual_reservation'));

create function private.set_manual_reservation_deadline()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.kind = 'manual_reservation' and new.expires_at is null then
    new.expires_at := new.created_at + interval '3 days';
  end if;
  return new;
end;
$$;
create trigger availability_manual_reservation_deadline
before insert or update of kind, expires_at on public.availability_entries
for each row execute function private.set_manual_reservation_deadline();
revoke all on function private.set_manual_reservation_deadline() from public, anon, authenticated;

create function private.expire_manual_reservations(p_asset uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare changed integer;
begin
  update public.availability_entries
     set status = 'expired', revision = revision + 1,
         updated_at = clock_timestamp(),
         reason = 'Reserva temporal vencida automáticamente tras 72 horas'
   where kind = 'manual_reservation' and status = 'active'
     and expires_at <= clock_timestamp()
     and (p_asset is null or asset_id = p_asset);
  get diagnostics changed = row_count;
  return changed;
end;
$$;
revoke all on function private.expire_manual_reservations(uuid) from public, anon, authenticated;

create function private.expire_manual_reservations_before_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.expire_manual_reservations(new.asset_id);
  return new;
end;
$$;
create trigger availability_expire_before_insert
before insert on public.availability_entries
for each row execute function private.expire_manual_reservations_before_insert();
revoke all on function private.expire_manual_reservations_before_insert() from public, anon, authenticated;

create index availability_manual_reservation_expiry_idx
  on public.availability_entries(expires_at)
  where status = 'active' and kind = 'manual_reservation';

create or replace function public.public_availability_matrix(p_start date, p_end date)
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
                 and e.kind in ('manual_reservation','hold')
                 and e.expires_at > observed
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

create or replace function private.sales_availability_calendar(
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
                and e.kind in ('reservation','maintenance','external_commitment')
                and day_value::date between e.starts_on and e.ends_on
           ) then 'ocupada'
           when exists (
             select 1 from public.availability_entries e
              where e.asset_id = asset.id and e.status = 'active'
                and e.kind in ('manual_reservation','hold') and e.expires_at > observed
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

create or replace function public.public_availability_expirations(p_month date)
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
     and (e.kind <> 'manual_reservation' or e.expires_at > clock_timestamp())
     and e.ends_on >= today_bogota
     and e.ends_on >= month_start
     and e.ends_on < (month_start + interval '1 month')::date
   order by e.ends_on, a.canonical_code
   limit 200;
end;
$$;

create or replace function private.sales_availability_assignments_v2(p_start date, p_end date)
returns table(asset_id uuid, starts_on date, ends_on date, state text,
  customer_name text, campaign_name text, advisor_id uuid, advisor_name text)
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
         coalesce(e.customer_name, q.customer_snapshot->>'name'),
         e.campaign_name, e.advisor_id,
         coalesce(case when advisor.display_name = 'Usuario invitado'
              then coalesce(advisor_auth.email::text, advisor.display_name)
              else advisor.display_name end, e.advisor_source_label)
    from public.availability_entries e
    join public.inventory_assets a on a.id = e.asset_id
    left join public.quotes q on q.id = e.quote_id
    left join public.profiles advisor on advisor.id = e.advisor_id
    left join auth.users advisor_auth on advisor_auth.id = e.advisor_id
   where e.status = 'active' and e.kind in ('hold','manual_reservation','reservation')
     and (e.kind not in ('hold','manual_reservation') or e.expires_at > clock_timestamp())
     and e.starts_on <= p_end and e.ends_on >= p_start
     and a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
   order by e.ends_on, a.canonical_code limit 500;
end;
$$;

-- Keep the booking RPC from treating a timed-out manual reservation as another
-- commercial's active overlap before it reaches its insert trigger.
create or replace function private.set_sales_availability_bulk_v2(
  p_assets uuid[], p_start date, p_end date, p_state text,
  p_reason text, p_evidence text, p_customer_name text, p_campaign_name text,
  p_advisor uuid, p_expected_revisions bigint[]
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  manager boolean := private.has_permission('cotizador.availability.manage');
  changed integer;
  updated_assignments integer;
  target_asset uuid;
begin
  if actor is null or not (manager or private.has_permission('cotizador.availability.reserve')) then
    raise exception 'Availability permission required' using errcode = '42501';
  end if;
  if p_state <> 'disponible' then
    if p_campaign_name is null or length(btrim(p_campaign_name)) not between 1 and 200
       or p_advisor is null or (not manager and p_advisor <> actor)
       or not exists (
         select 1 from public.profiles p
          where p.id = p_advisor and p.is_active and p.user_kind = 'employee'
            and exists (select 1 from public.user_roles r where r.user_id = p.id
              and r.revoked_at is null and r.role in ('sales','availability_manager'))
       ) then raise exception 'Valid campaign and active advisor required' using errcode = '22023'; end if;
  end if;
  for target_asset in select distinct id from unnest(p_assets) id where id is not null loop
    perform private.expire_manual_reservations(target_asset);
  end loop;
  changed := private.set_sales_availability_bulk(
    p_assets,p_start,p_end,p_state,p_reason,p_evidence,p_customer_name,p_expected_revisions
  );
  if p_state <> 'disponible' then
    update public.availability_entries e
       set campaign_name = btrim(p_campaign_name), advisor_id = p_advisor,
           revision = revision + 1, updated_at = now(), updated_by = actor
     where e.asset_id = any(p_assets) and e.status = 'active'
       and e.starts_on = p_start and e.ends_on = p_end
       and e.created_by = actor
       and e.kind = case when p_state = 'reservada' then 'manual_reservation' else 'reservation' end;
    get diagnostics updated_assignments = row_count;
    if updated_assignments <> changed then
      raise exception 'New assignment missing' using errcode = '40001';
    end if;
  end if;
  return changed;
end;
$$;

create extension if not exists pg_cron;
select cron.schedule(
  'hercas-expire-manual-reservations', '* * * * *',
  'select private.expire_manual_reservations(null)'
);
