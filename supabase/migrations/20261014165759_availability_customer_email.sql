alter table public.availability_entries add column if not exists customer_email text;
alter table public.availability_entries add constraint availability_customer_email_valid check (customer_email is null or (length(customer_email) <= 254 and customer_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'));
CREATE OR REPLACE FUNCTION private.set_sales_availability_bulk(p_assets uuid[], p_start date, p_end date, p_state text, p_reason text, p_evidence text, p_customer_name text, p_expected_revisions bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          reason, evidence_reference, customer_name, campaign_name, advisor_id, advisor_source_label, customer_email,
          created_by, updated_by
        ) values (
          asset_id_value, entry_row.starts_on, p_start - 1, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name,
          entry_row.campaign_name, entry_row.advisor_id, entry_row.advisor_source_label, entry_row.customer_email, entry_row.created_by, actor
        );
      end if;
      if entry_row.ends_on > p_end then
        insert into public.availability_entries(
          asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
          reason, evidence_reference, customer_name, campaign_name, advisor_id, advisor_source_label, customer_email,
          created_by, updated_by
        ) values (
          asset_id_value, p_end + 1, entry_row.ends_on, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name,
          entry_row.campaign_name, entry_row.advisor_id, entry_row.advisor_source_label, entry_row.customer_email, entry_row.created_by, actor
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
        btrim(p_customer_name), actor, actor
      );
    end if;
  end loop;
  return array_length(p_assets, 1);
end;
$function$
;
CREATE OR REPLACE FUNCTION private.sales_availability_assignments_v3(p_start date, p_end date)
 RETURNS TABLE(asset_id uuid, starts_on date, ends_on date, state text, customer_name text, campaign_name text, advisor_id uuid, advisor_name text, customer_email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
              else advisor.display_name end, e.advisor_source_label), e.customer_email
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
$function$
;
create or replace function public.sales_availability_assignments_v3(p_start date,p_end date)
returns table(asset_id uuid,starts_on date,ends_on date,state text,customer_name text,campaign_name text,advisor_id uuid,advisor_name text,customer_email text)
language sql security invoker set search_path='' as $$
select * from private.sales_availability_assignments_v3(p_start,p_end);
$$;
create function private.set_sales_availability_bulk_v4(
p_assets uuid[],p_start date,p_end date,p_state text,p_reason text,p_evidence text,
p_customer_name text,p_campaign_name text,p_advisor uuid,p_expected_revisions bigint[],
p_hold_hours integer,p_customer_email text)
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid()); changed integer; assigned integer;
begin
if actor is null or not (private.has_permission('cotizador.availability.reserve') or private.has_permission('cotizador.availability.manage')) then
raise exception 'Availability permission required' using errcode='42501'; end if;
if p_state <> 'disponible' and (p_customer_email is null or length(btrim(p_customer_email)) > 254 or btrim(p_customer_email) !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$') then
raise exception 'A valid customer email is required' using errcode='22023'; end if;
changed := private.set_sales_availability_bulk_v3(p_assets,p_start,p_end,p_state,p_reason,p_evidence,p_customer_name,p_campaign_name,p_advisor,p_expected_revisions,p_hold_hours);
if p_state <> 'disponible' then
update public.availability_entries set customer_email=btrim(p_customer_email), revision=revision+1, updated_at=now(),updated_by=actor
where asset_id=any(p_assets) and starts_on=p_start and ends_on=p_end and status='active'
and created_by=actor and created_at=now() and kind=case when p_state='reservada' then 'manual_reservation' else 'reservation' end;
get diagnostics assigned=row_count;
if assigned<>changed then raise exception 'Customer email update mismatch' using errcode='40001'; end if;
end if;
return changed;
end $$;
create function public.set_sales_availability_bulk_v4(
p_assets uuid[],p_start date,p_end date,p_state text,p_reason text,p_evidence text,
p_customer_name text,p_campaign_name text,p_advisor uuid,p_expected_revisions bigint[],
p_hold_hours integer,p_customer_email text)
returns integer language sql security invoker set search_path='' as $$
select private.set_sales_availability_bulk_v4(p_assets,p_start,p_end,p_state,p_reason,p_evidence,p_customer_name,p_campaign_name,p_advisor,p_expected_revisions,p_hold_hours,p_customer_email);
$$;
revoke all on function private.set_sales_availability_bulk_v4(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer,text),public.set_sales_availability_bulk_v4(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer,text),private.sales_availability_assignments_v3(date,date),public.sales_availability_assignments_v3(date,date) from public,anon;
grant execute on function private.set_sales_availability_bulk_v4(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer,text),public.set_sales_availability_bulk_v4(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer,text),private.sales_availability_assignments_v3(date,date),public.sales_availability_assignments_v3(date,date) to authenticated;
notify pgrst,'reload schema';
