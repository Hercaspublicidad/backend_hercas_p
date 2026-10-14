create or replace function private.set_sales_availability_bulk_v3(
 p_assets uuid[], p_start date, p_end date, p_state text,
 p_reason text, p_evidence text, p_customer_name text, p_campaign_name text,
 p_advisor uuid, p_expected_revisions bigint[], p_hold_hours integer default 72
) returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid()); changed integer; deadlines integer;
begin
 if actor is null or not (private.has_permission('cotizador.availability.reserve') or private.has_permission('cotizador.availability.manage')) then
  raise exception 'Availability permission required' using errcode='42501';
 end if;
 if p_state='reservada' and (p_hold_hours is null or p_hold_hours not between 1 and 72) then
  raise exception 'Negotiation window must be between 1 and 72 hours' using errcode='22023';
 end if;
 changed := private.set_sales_availability_bulk_v2(p_assets,p_start,p_end,p_state,p_reason,p_evidence,p_customer_name,p_campaign_name,p_advisor,p_expected_revisions);
 if p_state='reservada' then
  update public.availability_entries
     set expires_at=created_at + make_interval(hours=>p_hold_hours),
         revision=revision+1, updated_at=now(),updated_by=actor
   where asset_id=any(p_assets) and status='active' and kind='manual_reservation'
     and starts_on=p_start and ends_on=p_end and created_by=actor and created_at=now();
  get diagnostics deadlines=row_count;
  if deadlines<>changed then raise exception 'Reservation deadline update mismatch' using errcode='40001'; end if;
 end if;
 return changed;
end $$;
create or replace function public.set_sales_availability_bulk_v3(
 p_assets uuid[], p_start date, p_end date, p_state text,
 p_reason text, p_evidence text, p_customer_name text, p_campaign_name text,
 p_advisor uuid, p_expected_revisions bigint[], p_hold_hours integer default 72
) returns integer language sql security invoker set search_path='' as $$
 select private.set_sales_availability_bulk_v3(p_assets,p_start,p_end,p_state,p_reason,p_evidence,p_customer_name,p_campaign_name,p_advisor,p_expected_revisions,p_hold_hours);
$$;
revoke all on function private.set_sales_availability_bulk_v3(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer),public.set_sales_availability_bulk_v3(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer) from public,anon;
grant execute on function private.set_sales_availability_bulk_v3(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer),public.set_sales_availability_bulk_v3(uuid[],date,date,text,text,text,text,text,uuid,bigint[],integer) to authenticated;
notify pgrst,'reload schema';
