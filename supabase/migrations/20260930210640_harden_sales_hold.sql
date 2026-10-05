-- The public invoker wrapper keeps its signature. Harden the privileged hold
-- implementation so sales staff cannot attach another salesperson's quote.
create or replace function private.create_sales_hold(
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
  actor uuid := (select auth.uid());
  today_bogota date := (clock_timestamp() at time zone 'America/Bogota')::date;
  expires_at_value timestamptz := clock_timestamp() + interval '2 hours';
begin
  if actor is null
     or not (
       private.has_permission('cotizador.availability.reserve')
       or private.has_permission('cotizador.availability.manage')
     ) then
    raise exception 'Availability reservation permission required' using errcode = '42501';
  end if;
  if p_start is null or p_end is null
     or not isfinite(p_start) or not isfinite(p_end)
     or p_start < today_bogota or p_end < p_start
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
    select 1
      from public.quotes q
      join public.customer_accounts customer
        on customer.id = q.customer_id and customer.is_active
     where q.id = p_quote
       and q.status in ('draft', 'issued', 'accepted')
       and (
         q.created_by = actor
         or private.has_permission('cotizador.availability.manage')
       )
  ) then
    raise exception 'Quote unavailable' using errcode = '23514';
  end if;

  update public.availability_entries
     set status = 'expired',
         revision = revision + 1,
         reason = 'Separación comercial vencida',
         updated_at = now(),
         updated_by = actor
   where asset_id = p_asset
     and status = 'active'
     and kind = 'hold'
     and expires_at <= clock_timestamp();

  insert into public.availability_entries(
    asset_id, starts_on, ends_on, kind, status, expires_at, quote_id,
    reason, created_by, updated_by
  ) values (
    p_asset, p_start, p_end, 'hold', 'active', expires_at_value, p_quote,
    btrim(p_reason), actor, actor
  ) returning id into result;
  return result;
end;
$$;
