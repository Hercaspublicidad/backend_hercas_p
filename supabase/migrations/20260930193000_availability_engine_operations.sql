-- Availability engine: controlled inventory activation, commercial holds,
-- notification outbox and tag taxonomy. Email delivery is intentionally left
-- to the backend worker; this database only records durable, auditable work.

insert into public.permissions(code, description)
values ('cotizador.availability.reserve', 'Separar temporalmente una valla')
on conflict (code) do nothing;

insert into public.role_permissions(role, permission)
values
  ('sales', 'cotizador.availability.reserve'),
  ('availability_manager', 'cotizador.availability.reserve'),
  ('systems_admin', 'cotizador.availability.reserve')
on conflict do nothing;

create table public.availability_tags (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9][a-z0-9_-]{0,78}$'),
  label text not null check (length(btrim(label)) between 1 and 120),
  category text not null check (category in ('format', 'size', 'illumination', 'location', 'audience', 'feature')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.inventory_asset_tags (
  asset_id uuid not null references public.inventory_assets(id) on delete cascade,
  tag_id uuid not null references public.availability_tags(id) on delete restrict,
  source_reference text not null check (length(btrim(source_reference)) between 1 and 1000),
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (asset_id, tag_id),
  check ((verified_at is null) = (verified_by is null))
);
create index inventory_asset_tags_tag_idx on public.inventory_asset_tags(tag_id, asset_id);

-- The reporting worker uses this canonical image reference to embed the asset
-- photograph in Excel. A URL is stored only after it is reconciled with the
-- published website or the approved Storage object.
create table public.inventory_asset_media (
  asset_id uuid primary key references public.inventory_assets(id) on delete cascade,
  image_url text not null check (length(btrim(image_url)) between 1 and 2000),
  alt_text text not null check (length(btrim(alt_text)) between 1 and 500),
  source_reference text not null check (length(btrim(source_reference)) between 1 and 1000),
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((verified_at is null) = (verified_by is null))
);
create trigger inventory_asset_media_touch
before update on public.inventory_asset_media
for each row execute function private.touch_updated_at();

create table public.availability_notification_recipients (
  id uuid primary key default gen_random_uuid(),
  email text not null unique check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  display_name text,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger availability_notification_recipients_touch
before update on public.availability_notification_recipients
for each row execute function private.touch_updated_at();

create table public.availability_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in ('availability.blocked', 'availability.released')),
  availability_entry_id uuid not null references public.availability_entries(id) on delete restrict,
  recipient_id uuid not null references public.availability_notification_recipients(id) on delete restrict,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  queued_at timestamptz not null default now(),
  locked_at timestamptz,
  sent_at timestamptz,
  attempts integer not null default 0 check (attempts >= 0 and attempts <= 100),
  last_error text check (last_error is null or length(last_error) <= 1000),
  unique (event_type, availability_entry_id, recipient_id)
);
create index availability_notification_outbox_pending_idx
  on public.availability_notification_outbox(queued_at, id)
  where sent_at is null;

-- Every client-facing report delivery is recorded before the mail worker sends
-- it. This permits multiple selected recipients without exposing deliveries to
-- other staff through the Data API.
create table public.availability_report_deliveries (
  id uuid primary key default gen_random_uuid(),
  window_start date not null check (isfinite(window_start)),
  window_end date not null check (isfinite(window_end) and window_end >= window_start and window_end <= window_start + 45),
  recipient_email text not null check (recipient_email = lower(btrim(recipient_email)) and recipient_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  customer_account_id uuid references public.customer_accounts(id) on delete set null,
  requested_by uuid not null references public.profiles(id),
  requested_at timestamptz not null default now(),
  report_object_path text,
  sent_at timestamptz,
  failed_at timestamptz,
  failure_reason text check (failure_reason is null or length(failure_reason) <= 1000),
  check (not (sent_at is not null and failed_at is not null))
);
create index availability_report_deliveries_pending_idx
  on public.availability_report_deliveries(requested_at, id)
  where sent_at is null and failed_at is null;

-- A small, safe Realtime projection. Subscribers receive only that a calendar
-- changed and then refetch through the normal RLS-protected API. Publishing
-- availability_entries itself would expose internal evidence in a websocket.
create table public.availability_live_versions (
  asset_id uuid primary key references public.inventory_assets(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  changed_at timestamptz not null default now()
);

alter table public.availability_tags enable row level security;
alter table public.inventory_asset_tags enable row level security;
alter table public.inventory_asset_media enable row level security;
alter table public.availability_notification_recipients enable row level security;
alter table public.availability_notification_outbox enable row level security;
alter table public.availability_report_deliveries enable row level security;
alter table public.availability_live_versions enable row level security;

revoke all on public.availability_tags, public.inventory_asset_tags, public.inventory_asset_media,
  public.availability_notification_recipients, public.availability_notification_outbox,
  public.availability_report_deliveries
  from public, anon, authenticated;
grant select on public.availability_tags, public.inventory_asset_tags, public.inventory_asset_media,
  public.availability_live_versions to authenticated;

create policy availability_tags_read on public.availability_tags for select to authenticated
using ((select private.has_permission('cotizador.read')));
create policy inventory_asset_tags_read on public.inventory_asset_tags for select to authenticated
using ((select private.has_permission('cotizador.read')));
create policy inventory_asset_media_read on public.inventory_asset_media for select to authenticated
using ((select private.has_permission('cotizador.read')));
create policy availability_live_versions_read on public.availability_live_versions for select to authenticated
using ((select private.has_permission('cotizador.read')));

create function private.configure_inventory_asset_for_availability(
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

create function public.configure_inventory_asset_for_availability(
  p_asset uuid,
  p_visibility text,
  p_operational text,
  p_source_reference text
) returns uuid
language sql security invoker set search_path = '' as $$
  select private.configure_inventory_asset_for_availability(
    p_asset, p_visibility, p_operational, p_source_reference
  );
$$;

create function private.create_sales_hold(
  p_asset uuid,
  p_start date,
  p_end date,
  p_reason text,
  p_quote uuid default null
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  asset_row public.inventory_assets%rowtype;
  result uuid;
  expires_at_value timestamptz := clock_timestamp() + interval '2 hours';
begin
  if (select auth.uid()) is null
     or not (
       private.has_permission('cotizador.availability.reserve')
       or private.has_permission('cotizador.availability.manage')
     ) then
    raise exception 'Availability reservation permission required' using errcode = '42501';
  end if;
  if p_start is null or p_end is null or p_end < p_start
     or p_end - p_start > 365
     or p_reason is null or length(btrim(p_reason)) not between 1 and 1000 then
    raise exception 'Invalid availability hold' using errcode = '22023';
  end if;

  select * into asset_row
    from public.inventory_assets
   where id = p_asset
   for update;
  if not found
     or asset_row.lifecycle <> 'active'
     or asset_row.visibility <> 'visible'
     or asset_row.operational <> 'operational'
     or asset_row.is_provisional
     or asset_row.booking_mode <> 'exclusive_daily' then
    raise exception 'Asset is not available for commercial reservation' using errcode = '23514';
  end if;
  if p_quote is not null and not exists (
    select 1 from public.quotes
     where id = p_quote and status in ('draft', 'issued', 'accepted')
  ) then
    raise exception 'Quote unavailable' using errcode = '23514';
  end if;

  update public.availability_entries
     set status = 'expired',
         revision = revision + 1,
         reason = 'Separación comercial vencida',
         updated_at = now(),
         updated_by = (select auth.uid())
   where asset_id = p_asset
     and status = 'active'
     and kind = 'hold'
     and expires_at <= clock_timestamp();

  insert into public.availability_entries(
    asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
    reason, created_by, updated_by
  ) values (
    p_asset, p_start, p_end, 'hold', 'active', expires_at_value, p_quote,
    btrim(p_reason), (select auth.uid()), (select auth.uid())
  ) returning id into result;
  return result;
end;
$$;

create function public.create_sales_hold(
  p_asset uuid,
  p_start date,
  p_end date,
  p_reason text,
  p_quote uuid default null
) returns uuid
language sql security invoker set search_path = '' as $$
  select private.create_sales_hold(p_asset, p_start, p_end, p_reason, p_quote);
$$;

-- Public data is deliberately limited to the current or following calendar
-- month and returns only dates that can be requested. It never exposes a
-- customer, quote, reservation reason or the type of block.
create function public.public_asset_available_days(
  p_asset_code text,
  p_month date
) returns table(available_on date)
language plpgsql security definer set search_path = '' as $$
declare
  month_start date := date_trunc('month', p_month)::date;
  month_end date;
begin
  if p_asset_code is null or length(btrim(p_asset_code)) not between 1 and 80
     or p_month is null
     or month_start not in (
       date_trunc('month', current_date)::date,
       (date_trunc('month', current_date) + interval '1 month')::date
     ) then
    raise exception 'Only the current or following month can be consulted' using errcode = '22023';
  end if;
  month_end := (month_start + interval '1 month - 1 day')::date;

  return query
  select calendar_day::date
    from generate_series(month_start, month_end, interval '1 day') as calendar_day
    join public.inventory_assets asset
      on asset.canonical_code = upper(btrim(p_asset_code))
     and asset.lifecycle = 'active'
     and asset.visibility = 'visible'
     and asset.operational = 'operational'
     and not asset.is_provisional
     and asset.booking_mode = 'exclusive_daily'
   where not exists (
     select 1
       from public.availability_entries entry
      where entry.asset_id = asset.id
        and entry.status = 'active'
        and (entry.expires_at is null or entry.expires_at > clock_timestamp())
        and calendar_day::date between entry.starts_on and entry.ends_on
   )
   order by calendar_day;
end;
$$;

create function private.queue_availability_notification()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  notification_type text;
  asset_code text;
  recipient record;
begin
  if tg_op = 'INSERT' and new.status = 'active' then
    notification_type := 'availability.blocked';
  elsif tg_op = 'UPDATE' and old.status = 'active' and new.status in ('cancelled', 'expired') then
    notification_type := 'availability.released';
  else
    return new;
  end if;

  select canonical_code into asset_code
    from public.inventory_assets where id = new.asset_id;
  for recipient in
    select id from public.availability_notification_recipients where is_active
  loop
    insert into public.availability_notification_outbox(
      event_type, availability_entry_id, recipient_id, payload
    ) values (
      notification_type, new.id, recipient.id,
      jsonb_build_object(
        'asset_code', asset_code,
        'starts_on', new.starts_on,
        'ends_on', new.ends_on,
        'kind', new.kind,
        'status', new.status,
        'revision', new.revision
      )
    ) on conflict (event_type, availability_entry_id, recipient_id) do nothing;
  end loop;
  return new;
end;
$$;

create trigger availability_notification_enqueue
after insert or update of status on public.availability_entries
for each row execute function private.queue_availability_notification();

create function private.touch_availability_live_version()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare target_asset uuid := coalesce(new.asset_id, old.asset_id);
begin
  insert into public.availability_live_versions(asset_id, revision, changed_at)
  values (target_asset, 1, now())
  on conflict (asset_id) do update
    set revision = public.availability_live_versions.revision + 1,
        changed_at = excluded.changed_at;
  return coalesce(new, old);
end;
$$;

create trigger availability_live_version_touch
after insert or update or delete on public.availability_entries
for each row execute function private.touch_availability_live_version();

do $$
begin
  if not exists (
    select 1
      from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'availability_live_versions'
  ) then
    alter publication supabase_realtime add table public.availability_live_versions;
  end if;
end;
$$;

revoke all on function private.configure_inventory_asset_for_availability(uuid, text, text, text),
  private.create_sales_hold(uuid, date, date, text, uuid),
  private.queue_availability_notification(),
  private.touch_availability_live_version()
  from public, anon, authenticated;
revoke all on function public.configure_inventory_asset_for_availability(uuid, text, text, text),
  public.create_sales_hold(uuid, date, date, text, uuid),
  public.public_asset_available_days(text, date)
  from public, anon;
grant execute on function private.configure_inventory_asset_for_availability(uuid, text, text, text),
  private.create_sales_hold(uuid, date, date, text, uuid)
  to authenticated;
grant execute on function public.configure_inventory_asset_for_availability(uuid, text, text, text),
  public.create_sales_hold(uuid, date, date, text, uuid)
  to authenticated;
grant execute on function public.public_asset_available_days(text, date)
  to anon, authenticated;
