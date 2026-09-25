-- Commercial foundation. No demo inventory, prices or ERP writes.
create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
set local search_path = public, extensions;

alter table public.customer_accounts
 add column external_code text unique,
 add column trade_name text,
 add column customer_type_code text not null default 'normal'
   check (customer_type_code in ('normal','agency','corporate','ut_contract')),
 add column tax_identifier text;

create table public.product_families (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 80),
 name text not null check(length(btrim(name)) between 1 and 200)
);
create table public.commercial_lines (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 80),
 name text not null check(length(btrim(name)) between 1 and 200)
);
create table public.products (
 id uuid primary key default gen_random_uuid(),
 odoo_product_id bigint unique check(odoo_product_id > 0),
 external_code text unique,
 code text not null unique check(length(btrim(code)) between 1 and 80),
 name text not null check(length(btrim(name)) between 1 and 200),
 commercial_unit text not null check(length(btrim(commercial_unit)) between 1 and 80),
 family_id uuid references public.product_families(id),
 commercial_line_id uuid references public.commercial_lines(id),
 visibility text not null default 'hidden' check(visibility in ('hidden','visible')),
 is_active boolean not null default true,
 source_synced_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index products_family_idx on public.products(family_id);
create index products_line_idx on public.products(commercial_line_id);
create index products_catalog_idx on public.products(name,id) where is_active and visibility='visible';

create table public.inventory_assets (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id),
 canonical_code text not null unique check(length(btrim(canonical_code)) between 1 and 80),
 name text not null check(length(btrim(name)) between 1 and 200),
 description text not null default '' check(length(description)<=4000),
 visibility text not null default 'hidden' check(visibility in ('hidden','visible')),
 lifecycle text not null default 'active' check(lifecycle in ('active','retired')),
 operational text not null default 'unverified' check(operational in ('unverified','operational','maintenance','unavailable')),
 is_provisional boolean not null default true,
 booking_mode text not null default 'unconfigured' check(booking_mode in ('unconfigured','exclusive_daily','shared_pending')),
 source_reference text,
 last_verified_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index assets_product_idx on public.inventory_assets(product_id);
create trigger products_touch before update on public.products
for each row execute function private.touch_updated_at();
create trigger assets_touch before update on public.inventory_assets
for each row execute function private.touch_updated_at();

create table public.product_price_versions (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id),
 version integer not null check(version>0),
 amount numeric(16,0) not null check(amount>0 and amount<=9007199254740991),
 currency text not null default 'COP' check(currency='COP'),
 commercial_unit text not null check(length(btrim(commercial_unit)) between 1 and 80),
 tax_percent numeric(5,2) not null check(tax_percent between 0 and 100),
 valid_from date not null check(isfinite(valid_from)),
 valid_until date not null check(isfinite(valid_until) and valid_until>=valid_from),
 state text not null default 'draft' check(state in ('draft','published','retired')),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 published_by uuid references public.profiles(id),
 published_at timestamptz,
 unique(product_id,version),
 check((state='draft' and published_by is null and published_at is null)
    or (state in ('published','retired') and published_by is not null and published_at is not null)),
 exclude using gist (product_id with =, daterange(valid_from,valid_until,'[]') with &&) where(state='published')
);
create index price_creator_idx on public.product_price_versions(created_by);
create index price_publisher_idx on public.product_price_versions(published_by);

create table public.quotes (
 id uuid primary key default gen_random_uuid(),
 quote_number bigint generated always as identity unique,
 customer_id uuid not null references public.customer_accounts(id),
 created_by uuid not null references public.profiles(id),
 status text not null default 'draft' check(status in ('draft','issued','accepted','rejected','cancelled')),
 currency text not null default 'COP' check(currency='COP'),
 customer_snapshot jsonb not null check(jsonb_typeof(customer_snapshot)='object'),
 requirements_snapshot jsonb not null default '{}' check(jsonb_typeof(requirements_snapshot)='object'),
 valid_until date not null check(isfinite(valid_until)),
 subtotal numeric(16,0) not null default 0 check(subtotal between 0 and 9007199254740991),
 discount_total numeric(16,0) not null default 0 check(discount_total=0), -- discount approval workflow pending
 tax_total numeric(16,0) not null default 0 check(tax_total between 0 and 9007199254740991),
 total numeric(16,0) generated always as (subtotal-discount_total+tax_total) stored,
 issued_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(total between 0 and 9007199254740991),
 check(status not in ('issued','accepted','rejected') or issued_at is not null)
);
create index quotes_customer_time_idx on public.quotes(customer_id,created_at desc,id);
create index quotes_creator_idx on public.quotes(created_by);
create index quotes_time_idx on public.quotes(created_at desc,id desc);
create table public.quote_lines (
 id uuid primary key default gen_random_uuid(),
 quote_id uuid not null references public.quotes(id),
 line_number integer not null check(line_number>0),
 product_id uuid not null references public.products(id),
 price_version_id uuid not null references public.product_price_versions(id),
 product_snapshot jsonb not null check(jsonb_typeof(product_snapshot)='object'),
 quantity numeric(12,3) not null check(quantity>0 and quantity<=1000000),
 periods numeric(12,3) not null check(periods>0 and periods<=1000000),
 unit_price numeric(16,0) not null check(unit_price>0 and unit_price<=9007199254740991),
 tax_percent numeric(5,2) not null check(tax_percent between 0 and 100),
 subtotal numeric(16,0) generated always as(round(quantity*periods*unit_price,0)) stored,
 tax_total numeric(16,0) generated always as(round(round(quantity*periods*unit_price,0)*tax_percent/100,0)) stored,
 unique(quote_id,line_number)
);
create index quote_lines_product_idx on public.quote_lines(product_id);
create index quote_lines_price_idx on public.quote_lines(price_version_id);

create function private.prepare_quote() returns trigger language plpgsql set search_path='' as $$
declare customer public.customer_accounts%rowtype;
begin
 if new.status<>'draft' or new.issued_at is not null or new.subtotal<>0 or new.tax_total<>0 then
   raise exception 'New quotes must start as empty drafts' using errcode='23514';
 end if;
 select * into customer from public.customer_accounts where id=new.customer_id and is_active;
 if not found then raise exception 'Active customer required' using errcode='23514'; end if;
 new.customer_snapshot:=jsonb_build_object('name',customer.name,'trade_name',customer.trade_name,
   'tax_identifier',customer.tax_identifier,'odoo_partner_id',customer.odoo_partner_id);
 return new;
end; $$;
create trigger quote_prepare before insert on public.quotes for each row execute function private.prepare_quote();

create table public.availability_entries (
 id uuid primary key default gen_random_uuid(),
 asset_id uuid not null references public.inventory_assets(id),
 starts_on date not null check(isfinite(starts_on)),
 ends_on date not null check(isfinite(ends_on) and ends_on>=starts_on),
 kind text not null check(kind in ('hold','reservation','maintenance','external_commitment')),
 status text not null default 'active' check(status in ('active','cancelled','expired')),
 expires_at timestamptz,
 quote_id uuid references public.quotes(id),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 evidence_reference text check(length(btrim(evidence_reference)) between 1 and 1000),
 revision integer not null default 1 check(revision>0),
 created_by uuid not null references public.profiles(id),
 updated_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((kind='hold' and expires_at is not null and isfinite(expires_at) and expires_at>created_at)
   or (kind<>'hold' and expires_at is null)),
 check(kind not in ('reservation','external_commitment') or evidence_reference is not null),
 check(status<>'expired' or kind='hold'),
 exclude using gist (asset_id with =, daterange(starts_on,ends_on,'[]') with &&) where(status='active')
);
create index availability_asset_idx on public.availability_entries(asset_id);
create index availability_quote_idx on public.availability_entries(quote_id);
create index availability_creator_idx on public.availability_entries(created_by);
create index availability_updater_idx on public.availability_entries(updated_by);
create index availability_expiry_idx on public.availability_entries(expires_at) where status='active' and kind='hold';
create table public.availability_events (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null references public.availability_entries(id),
 actor_id uuid references public.profiles(id),
 revision integer not null,
 previous_state jsonb,
 new_state jsonb not null,
 occurred_at timestamptz not null default now(),
 unique(entry_id,revision)
);
create index availability_events_actor_idx on public.availability_events(actor_id);

-- Private, non-callable trigger: preserves the calendar history without exposing evidence.
create function private.log_availability() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.availability_events(entry_id,actor_id,revision,previous_state,new_state)
 values(new.id,(select auth.uid()),new.revision,
   case when tg_op='UPDATE' then to_jsonb(old)-'evidence_reference' else null end,
   to_jsonb(new)-'evidence_reference');
 return new;
end; $$;
create trigger availability_history after insert or update on public.availability_entries
for each row execute function private.log_availability();

-- Published prices are snapshots. Only explicit retirement may change them.
create function private.guard_published_price() returns trigger language plpgsql set search_path='' as $$
begin
 if old.state<>'draft' then
   if tg_op='DELETE' then raise exception 'Published price is immutable' using errcode='23514'; end if;
   if old.state='retired' or new.state<>'retired'
      or (to_jsonb(old)-'state') is distinct from (to_jsonb(new)-'state') then
     raise exception 'Published price is immutable' using errcode='23514';
   end if;
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end; $$;
create trigger published_price_guard before update or delete on public.product_price_versions
for each row execute function private.guard_published_price();

-- Operator-only quotation authoring for this foundation; prices never come from the browser.
create function private.prepare_quote_line() returns trigger language plpgsql set search_path='' as $$
declare q public.quotes%rowtype; p public.product_price_versions%rowtype; product public.products%rowtype;
begin
 if tg_op='UPDATE' and (new.quote_id<>old.quote_id or new.id<>old.id) then
   raise exception 'Line cannot be reassigned' using errcode='23514';
 end if;
 select * into q from public.quotes where id=case when tg_op='DELETE' then old.quote_id else new.quote_id end for update;
 if not found or q.status<>'draft' or q.issued_at is not null then
   raise exception 'Quote is immutable' using errcode='23514';
 end if;
 if tg_op='DELETE' then return old; end if;
 select * into p from public.product_price_versions where id=new.price_version_id for share;
 if not found or p.state<>'published' or current_date not between p.valid_from and p.valid_until
    or p.product_id<>new.product_id or p.currency<>q.currency then
   raise exception 'Published valid price required' using errcode='23514';
 end if;
 select * into product from public.products where id=p.product_id and is_active and visibility='visible';
 if not found then raise exception 'Product unavailable' using errcode='23514'; end if;
 new.unit_price:=p.amount; new.tax_percent:=p.tax_percent;
 new.product_snapshot:=jsonb_build_object('code',product.code,'name',product.name,'commercial_unit',p.commercial_unit,'price_version',p.version);
 return new;
end; $$;
create trigger quote_line_prepare before insert or update or delete on public.quote_lines
for each row execute function private.prepare_quote_line();
create function private.retotal_quote() returns trigger language plpgsql set search_path='' as $$
declare target uuid:=case when tg_op='DELETE' then old.quote_id else new.quote_id end;
begin
 update public.quotes set subtotal=(select coalesce(sum(subtotal),0) from public.quote_lines where quote_id=target),
 tax_total=(select coalesce(sum(tax_total),0) from public.quote_lines where quote_id=target),updated_at=now() where id=target;
 if tg_op='DELETE' then return old; end if; return new;
end; $$;
create trigger quote_retotal after insert or update or delete on public.quote_lines
for each row execute function private.retotal_quote();
create function private.guard_quote() returns trigger language plpgsql set search_path='' as $$
begin
 if old.issued_at is not null or old.status<>'draft' then
   raise exception 'Issued quote is immutable; lifecycle workflow pending' using errcode='23514';
 end if;
 if tg_op='DELETE' then return old; end if;
 if new.status<>'draft' then
   if new.status<>'issued' or new.issued_at is null or new.valid_until<current_date
      or not exists(select 1 from public.quote_lines where quote_id=old.id) then
     raise exception 'Cannot issue quote' using errcode='23514';
   end if;
 end if;
 if new.subtotal<>(select coalesce(sum(subtotal),0) from public.quote_lines where quote_id=old.id)
    or new.tax_total<>(select coalesce(sum(tax_total),0) from public.quote_lines where quote_id=old.id) then
   raise exception 'Totals must match quote lines' using errcode='23514';
 end if;
 return new;
end; $$;
create trigger quote_guard before update or delete on public.quotes for each row execute function private.guard_quote();

-- Only the availability role can mutate the calendar. Lock asset before its entries.
create function private.add_availability(p_asset uuid,p_start date,p_end date,p_kind text,p_reason text,
 p_expires timestamptz default null,p_quote uuid default null,p_evidence text default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare a public.inventory_assets%rowtype; result uuid;
begin
 if (select auth.uid()) is null or not private.has_permission('cotizador.availability.manage') then
   raise exception 'Availability permission required' using errcode='42501';
 end if;
 select * into a from public.inventory_assets where id=p_asset for update;
 if not found or a.booking_mode<>'exclusive_daily' or a.lifecycle<>'active' or a.is_provisional then
   raise exception 'Asset must be verified and exclusively bookable' using errcode='23514';
 end if;
 if p_kind in ('hold','reservation') and (a.operational<>'operational' or a.visibility<>'visible') then
   raise exception 'Asset unavailable' using errcode='23514';
 end if;
 if p_kind='hold' and (p_expires is null or p_expires<=clock_timestamp()) then
   raise exception 'Future expiration required' using errcode='23514';
 end if;
 if p_quote is not null and not exists(select 1 from public.quotes where id=p_quote and status in ('draft','issued','accepted')) then
   raise exception 'Quote unavailable' using errcode='23514';
 end if;
 update public.availability_entries set status='expired',revision=revision+1,updated_at=now(),updated_by=(select auth.uid()),reason='Hold expired'
 where asset_id=p_asset and status='active' and kind='hold' and expires_at<=clock_timestamp();
 insert into public.availability_entries(asset_id,starts_on,ends_on,kind,reason,expires_at,quote_id,evidence_reference,created_by,updated_by)
 values(p_asset,p_start,p_end,p_kind,p_reason,p_expires,p_quote,p_evidence,(select auth.uid()),(select auth.uid())) returning id into result;
 return result;
end; $$;
create function public.add_availability(p_asset uuid,p_start date,p_end date,p_kind text,p_reason text,
 p_expires timestamptz default null,p_quote uuid default null,p_evidence text default null) returns uuid
language sql security invoker set search_path='' as $$
 select private.add_availability(p_asset,p_start,p_end,p_kind,p_reason,p_expires,p_quote,p_evidence);
$$;
create function private.cancel_availability(p_entry uuid,p_revision integer,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare a uuid; e public.availability_entries%rowtype;
begin
 if (select auth.uid()) is null or not private.has_permission('cotizador.availability.manage') then
   raise exception 'Availability permission required' using errcode='42501';
 end if;
 select asset_id into a from public.availability_entries where id=p_entry;
 perform 1 from public.inventory_assets where id=a for update;
 select * into e from public.availability_entries where id=p_entry for update;
 if not found or e.status<>'active' or p_revision is null or e.revision<>p_revision then
   raise exception 'Calendar changed; refresh before editing' using errcode='40001';
 end if;
 update public.availability_entries set status='cancelled',reason=p_reason,revision=revision+1,
 updated_at=now(),updated_by=(select auth.uid()) where id=p_entry;
 return p_entry;
end; $$;
create function public.cancel_availability(p_entry uuid,p_revision integer,p_reason text) returns uuid
language sql security invoker set search_path='' as $$ select private.cancel_availability(p_entry,p_revision,p_reason); $$;

-- RLS reads. Customer portal remains closed until explicit publication workflow exists.
do $$
declare t text;
begin
 foreach t in array array['product_families','commercial_lines','products','inventory_assets','product_price_versions','quotes','quote_lines','availability_entries','availability_events'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on public.%I from public,anon,authenticated',t);
   execute format('grant select on public.%I to authenticated',t);
   execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.audit_identity_change()',t||'_audit',t);
 end loop;
 foreach t in array array['product_families','commercial_lines','products','inventory_assets'] loop
   execute format('create policy staff_read on public.%I for select to authenticated using ((select private.has_permission(''cotizador.read'')))',t);
 end loop;
end; $$;
create policy price_read on public.product_price_versions for select to authenticated using
 ((select private.has_permission('cotizador.pricing.manage')) or (state='published' and (select private.has_permission('cotizador.calculate'))));
create policy quote_read on public.quotes for select to authenticated using
 ((select private.has_permission('customers.read')) or (select private.has_permission('audit.read')));
create policy quote_line_read on public.quote_lines for select to authenticated using
 (exists(select 1 from public.quotes q where q.id=quote_id));
create policy calendar_read on public.availability_entries for select to authenticated using
 ((select private.has_permission('cotizador.read')));
create policy calendar_history_read on public.availability_events for select to authenticated using
 ((select private.has_permission('cotizador.availability.manage')) or (select private.has_permission('audit.read')));
-- All mutation entrypoints are explicit; no general table writes even for web admins.
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.active_user(),private.has_permission(text),private.is_customer_member(uuid),private.accept_invitation(uuid) to authenticated;
grant execute on function private.add_availability(uuid,date,date,text,text,timestamptz,uuid,text),private.cancel_availability(uuid,integer,text) to authenticated;
revoke all on function public.add_availability(uuid,date,date,text,text,timestamptz,uuid,text),public.cancel_availability(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.add_availability(uuid,date,date,text,text,timestamptz,uuid,text),public.cancel_availability(uuid,integer,text) to authenticated;
revoke all on sequence public.quotes_quote_number_seq from public,anon,authenticated;
