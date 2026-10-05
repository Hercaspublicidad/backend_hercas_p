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
                and (e.kind = 'manual_reservation'
                     or (e.kind = 'hold' and e.expires_at > observed))
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
