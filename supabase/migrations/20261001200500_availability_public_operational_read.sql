-- Operational flag lets the dashboard exclude non-offerable assets from occupancy.
create function public.public_availability_assets_v2()
returns table(asset_id uuid, asset_code text, asset_name text, review_required boolean, operational text)
language sql stable security definer set search_path = '' as $$
  select a.id, a.canonical_code, a.name, a.availability_review_required, a.operational
    from public.inventory_assets a
   where a.lifecycle = 'active' and a.visibility = 'visible'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily'
   order by a.canonical_code limit 200;
$$;
revoke all on function public.public_availability_assets_v2() from public, anon, authenticated;
grant execute on function public.public_availability_assets_v2() to anon, authenticated;
