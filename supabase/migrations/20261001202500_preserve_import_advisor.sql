-- Keep imported advisor names on fragments outside a partial correction.
create or replace function private.set_sales_availability_bulk(
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
          reason, evidence_reference, customer_name, campaign_name, advisor_id, advisor_source_label,
          created_by, updated_by
        ) values (
          asset_id_value, entry_row.starts_on, p_start - 1, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name,
          entry_row.campaign_name, entry_row.advisor_id, entry_row.advisor_source_label, entry_row.created_by, actor
        );
      end if;
      if entry_row.ends_on > p_end then
        insert into public.availability_entries(
          asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
          reason, evidence_reference, customer_name, campaign_name, advisor_id, advisor_source_label,
          created_by, updated_by
        ) values (
          asset_id_value, p_end + 1, entry_row.ends_on, entry_row.kind,
          'active', entry_row.expires_at, entry_row.quote_id,
          entry_row.reason, entry_row.evidence_reference, entry_row.customer_name,
          entry_row.campaign_name, entry_row.advisor_id, entry_row.advisor_source_label, entry_row.created_by, actor
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
$$;
