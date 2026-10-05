-- Source-marked barter inventory remains subject to the live availability calendar.
-- Only operational inventory that Katherine marked DISPONIBLE is advertised as barter.
create function public.public_availability_barter_assets()
returns table(asset_id uuid, partner_name text)
language sql security definer set search_path = '' as $$
  select r.asset_id,
         case
           when lower(btrim(r.source->>'customer')) = 'florida' then 'Florida'
           when lower(btrim(r.source->>'customer')) = 'funeraria gomez' then 'Funeraria Gómez'
           when lower(btrim(r.source->>'customer')) = 'puerta del norte' then 'Puerta del Norte'
           when lower(btrim(r.source->>'customer')) = 'cotelco' then 'Cotelco'
         end
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
