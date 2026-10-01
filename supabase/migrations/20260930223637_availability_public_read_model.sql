-- Public read model: only identity-free asset labels and interval states.
-- A visible asset may still be awaiting Katherine's inventory review.
create function public.public_availability_assets()
returns table(
  asset_id uuid, asset_code text, asset_name text, review_required boolean
)
language sql stable security definer set search_path = '' as $$
  select a.id, a.canonical_code, a.name, a.availability_review_required
    from public.inventory_assets a
   where a.lifecycle = 'active'
     and a.visibility = 'visible'
     and not a.is_provisional
     and a.booking_mode = 'exclusive_daily'
   order by a.canonical_code
   limit 200;
$$;

create function public.public_asset_availability(
  p_asset_code text, p_start date, p_end date
) returns table(
  available_on date, state text, observed_at timestamptz, calendar_revision bigint
)
language plpgsql security definer set search_path = '' as $$
declare
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  observed timestamptz := clock_timestamp();
begin
  if p_asset_code is null or length(btrim(p_asset_code)) not between 1 and 80
     or p_start is null or p_end is null
     or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start
     or p_end - p_start > 45 or p_end > today_bogota + 365 then
    raise exception 'Invalid public availability interval' using errcode = '22023';
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
   where asset.canonical_code = upper(btrim(p_asset_code))
     and asset.lifecycle = 'active'
     and asset.visibility = 'visible'
     and not asset.is_provisional
     and asset.booking_mode = 'exclusive_daily'
   order by day_value;
end;
$$;

revoke all on function
  public.public_availability_assets(),
  public.public_asset_availability(text,date,date)
from public, anon, authenticated;
grant execute on function
  public.public_availability_assets(),
  public.public_asset_availability(text,date,date)
to anon, authenticated;
