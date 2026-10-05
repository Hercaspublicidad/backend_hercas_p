-- The public calendar needs only the classification, not the barter partner name.
drop function public.public_availability_barter_assets();
create function public.public_availability_barter_assets()
returns table(asset_id uuid)
language sql security definer set search_path = '' as $$
  select distinct r.asset_id
    from private.availability_import_rows r
    join public.inventory_assets a on a.id = r.asset_id
      and a.availability_source_batch = r.batch_sha256
   where r.source->>'state' = 'DISPONIBLE'
     and lower(btrim(r.source->>'customer')) in
       ('florida', 'funeraria gomez', 'puerta del norte', 'cotelco')
     and a.lifecycle = 'active' and a.visibility = 'visible'
     and a.operational = 'operational'
     and not a.is_provisional and a.booking_mode = 'exclusive_daily';
$$;
revoke all on function public.public_availability_barter_assets() from public, anon, authenticated;
grant execute on function public.public_availability_barter_assets() to anon, authenticated;
