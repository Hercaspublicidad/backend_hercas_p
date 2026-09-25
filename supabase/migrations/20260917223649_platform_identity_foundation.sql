-- Platform foundation only. Do not combine with the old cotizador worktree migrations.
-- No passwords, Auth users, email invitations or business transactions are created here.
create schema private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (length(btrim(display_name)) between 1 and 200),
  user_kind text not null default 'pending' check (user_kind in ('pending','employee','client')),
  is_active boolean not null default false,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not is_active or (activated_at is not null and user_kind <> 'pending'))
);
create table public.roles (
  code text primary key,
  name text not null,
  scope text not null check (scope in ('staff','client')),
  unique(code, scope)
);
create table public.permissions (
  code text primary key,
  description text not null
);
create table public.role_permissions (
  role text not null references public.roles(code),
  permission text not null references public.permissions(code),
  primary key (role, permission)
);
create index role_permissions_permission_idx on public.role_permissions(permission);
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  role text not null,
  scope text not null default 'staff' check (scope = 'staff'),
  granted_by uuid references public.profiles(id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  foreign key (role, scope) references public.roles(code, scope),
  check (revoked_at is null or revoked_at >= granted_at)
);
create unique index user_roles_active_unique on public.user_roles(user_id, role) where revoked_at is null;
create index user_roles_role_idx on public.user_roles(role);
create index user_roles_granted_by_idx on public.user_roles(granted_by);

create table public.customer_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  odoo_partner_id bigint unique check (odoo_partner_id > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.customer_memberships (
  id uuid primary key default gen_random_uuid(),
  customer_account_id uuid not null references public.customer_accounts(id),
  user_id uuid not null references public.profiles(id),
  role text not null default 'client_viewer',
  scope text not null default 'client' check (scope = 'client'),
  granted_by uuid references public.profiles(id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  foreign key (role, scope) references public.roles(code, scope),
  check (revoked_at is null or revoked_at >= granted_at)
);
create unique index customer_memberships_active_unique
  on public.customer_memberships(customer_account_id, user_id) where revoked_at is null;
create index customer_memberships_user_idx on public.customer_memberships(user_id, customer_account_id) where revoked_at is null;
create index customer_memberships_role_idx on public.customer_memberships(role);
create index customer_memberships_granted_by_idx on public.customer_memberships(granted_by);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null check (email = lower(btrim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'),
  user_kind text not null check (user_kind in ('employee','client')),
  role text not null,
  scope text not null,
  customer_account_id uuid references public.customer_accounts(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  accepted_by uuid references public.profiles(id),
  revoked_at timestamptz,
  foreign key (role, scope) references public.roles(code, scope),
  check ((user_kind='employee' and scope='staff' and customer_account_id is null)
      or (user_kind='client' and scope='client' and customer_account_id is not null)),
  check (expires_at > created_at and expires_at <= created_at + interval '7 days'),
  check ((accepted_at is null) = (accepted_by is null)),
  check (accepted_at is null or (accepted_at >= created_at and accepted_at < expires_at)),
  check (revoked_at is null or revoked_at >= created_at)
);
create index invitations_email_idx on public.invitations(email);
create index invitations_customer_idx on public.invitations(customer_account_id);
create index invitations_creator_idx on public.invitations(created_by);
create index invitations_acceptor_idx on public.invitations(accepted_by);
create index invitations_role_idx on public.invitations(role);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid, -- Preserve audit when an Auth identity is administratively removed.
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  entity text not null,
  entity_id text not null,
  occurred_at timestamptz not null default now()
);
create index audit_events_actor_time_idx on public.audit_events(actor_id, occurred_at desc);
create index audit_events_entity_idx on public.audit_events(entity, entity_id, occurred_at desc);

insert into public.roles(code,name,scope) values
 ('systems_admin','Administrador de plataforma','staff'),
 ('sales','Comercial','staff'),
 ('pricing_manager','Administrador de precios del cotizador','staff'),
 ('availability_manager','Administrador de disponibilidad','staff'),
 ('auditor','Auditor','staff'),
 ('client_viewer','Consulta de empresa cliente','client');
insert into public.permissions(code,description) values
 ('users.manage','Gestionar acceso por invitación'),
 ('customers.read','Consultar cuentas cliente internas'),
 ('customers.manage','Administrar cuentas cliente'),
 ('cotizador.read','Consultar cotizador interno'),
 ('cotizador.calculate','Simular cotizaciones'),
 ('cotizador.pricing.manage','Administrar precios'),
 ('cotizador.availability.manage','Administrar disponibilidad'),
 ('audit.read','Consultar auditoría de acceso'),
 ('reports.read_own','Consultar reportes autorizados de su empresa');
insert into public.role_permissions(role,permission)
 select 'systems_admin', code from public.permissions;
insert into public.role_permissions(role,permission) values
 ('sales','customers.read'), ('sales','cotizador.read'), ('sales','cotizador.calculate'),
 ('pricing_manager','cotizador.read'), ('pricing_manager','cotizador.calculate'),
 ('pricing_manager','cotizador.pricing.manage'),
 ('availability_manager','cotizador.read'), ('availability_manager','cotizador.availability.manage'),
 ('auditor','audit.read'), ('client_viewer','reports.read_own');

-- These private helpers read authorization tables without recursive RLS. They
-- never accept an arbitrary subject and always bind results to auth.uid().
create function private.active_user() returns boolean language sql stable security definer
set search_path = '' as $$
 select (select auth.uid()) is not null and exists (
   select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active
 );
$$;
create function private.has_permission(required_permission text) returns boolean
language sql stable security definer set search_path = '' as $$
 select (select auth.uid()) is not null and exists (
   select 1 from public.profiles p
   join public.user_roles r on r.user_id=p.id and r.revoked_at is null
   join public.role_permissions rp on rp.role=r.role
   where p.id=(select auth.uid()) and p.is_active and p.user_kind='employee'
     and rp.permission=required_permission
 );
$$;
create function private.is_customer_member(account_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select (select auth.uid()) is not null and exists (
   select 1 from public.profiles p
   join public.customer_memberships m on m.user_id=p.id and m.revoked_at is null
   join public.customer_accounts a on a.id=m.customer_account_id and a.is_active
   where p.id=(select auth.uid()) and p.is_active and p.user_kind='client' and a.id=account_id
 );
$$;

-- Auth trigger has no browser caller (auth.uid() may be null). It can only create
-- an inactive pending profile; it never trusts metadata or grants privileges.
create function private.on_auth_user_created() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,display_name) values(new.id,'Usuario invitado');
 return new;
end;
$$;
create trigger platform_auth_profile after insert on auth.users
for each row execute function private.on_auth_user_created();
-- Preserve existing Auth accounts as pending; never auto-promote by email.
insert into public.profiles(id,display_name)
select id,'Usuario pendiente' from auth.users on conflict (id) do nothing;

create function private.audit_identity_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.audit_events(actor_id,action,entity,entity_id)
 values((select auth.uid()),tg_op,tg_table_name,coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'));
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$$;
create function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at:=now(); return new; end;
$$;
create trigger profiles_touch before update on public.profiles
for each row execute function private.touch_updated_at();
create trigger customers_touch before update on public.customer_accounts
for each row execute function private.touch_updated_at();

create function private.accept_invitation(invitation_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
 actor uuid := (select auth.uid());
 identity_row auth.users%rowtype;
 invitation public.invitations%rowtype;
 profile public.profiles%rowtype;
begin
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into identity_row from auth.users where id=actor;
 if not found or identity_row.email is null or identity_row.email_confirmed_at is null or identity_row.invited_at is null
 then raise exception 'Verified invited identity required' using errcode='42501'; end if;

 -- Lock profile first to serialize different invitations for the same account.
 select * into profile from public.profiles where id=actor for update;
 if not found or (not profile.is_active and profile.activated_at is not null)
 then raise exception 'Profile unavailable' using errcode='42501'; end if;

 select * into invitation from public.invitations where id=invitation_id for update;
 if not found or invitation.email <> lower(btrim(identity_row.email))
    or invitation.revoked_at is not null
 then raise exception 'Invitation unavailable' using errcode='42501'; end if;
 if invitation.accepted_by=actor then return invitation.id; end if;
 if invitation.accepted_at is not null or invitation.expires_at <= now()
 then raise exception 'Invitation unavailable' using errcode='42501'; end if;
 if profile.user_kind not in ('pending',invitation.user_kind)
 then raise exception 'Identity kind mismatch' using errcode='42501'; end if;
 if invitation.customer_account_id is not null then
   perform 1 from public.customer_accounts where id=invitation.customer_account_id and is_active for share;
   if not found then raise exception 'Customer unavailable' using errcode='42501'; end if;
 end if;
 update public.profiles set user_kind=invitation.user_kind,is_active=true,
   activated_at=coalesce(activated_at,now()) where id=actor;
 if invitation.user_kind='employee' then
   insert into public.user_roles(user_id,role,granted_by)
   values(actor,invitation.role,invitation.created_by)
   on conflict (user_id,role) where revoked_at is null do nothing;
 else
   insert into public.customer_memberships(customer_account_id,user_id,role,granted_by)
   values(invitation.customer_account_id,actor,invitation.role,invitation.created_by)
   on conflict (customer_account_id,user_id) where revoked_at is null do nothing;
 end if;
 update public.invitations set accepted_at=now(),accepted_by=actor where id=invitation.id;
 return invitation.id;
end;
$$;
-- Public entry point is invoker; elevated implementation stays in private.
create function public.accept_invitation(invitation_id uuid) returns uuid
language sql security invoker set search_path = '' as $$
 select private.accept_invitation(invitation_id);
$$;

alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.customer_accounts enable row level security;
alter table public.customer_memberships enable row level security;
alter table public.invitations enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_read on public.profiles for select to authenticated
using (id=(select auth.uid()) or (select private.has_permission('users.manage')));
create policy roles_read on public.roles for select to authenticated using ((select private.active_user()));
create policy permissions_read on public.permissions for select to authenticated using ((select private.active_user()));
create policy role_permissions_read on public.role_permissions for select to authenticated using ((select private.active_user()));
create policy user_roles_read on public.user_roles for select to authenticated
using ((select private.active_user()) and (user_id=(select auth.uid()) or (select private.has_permission('users.manage'))));
create policy customers_read on public.customer_accounts for select to authenticated
using ((select private.has_permission('customers.read')) or private.is_customer_member(id));
create policy memberships_read on public.customer_memberships for select to authenticated
using ((select private.active_user()) and (user_id=(select auth.uid()) or (select private.has_permission('users.manage'))));
create policy invitations_read on public.invitations for select to authenticated
using ((select private.has_permission('users.manage')));
create policy audit_read on public.audit_events for select to authenticated
using ((select private.has_permission('audit.read')));

-- Administration is SQL-only in this foundation; no broad authenticated writes.
-- Invitation acceptance is the only exposed mutation and checks verified identity.
revoke all on public.profiles,public.roles,public.permissions,public.role_permissions,
 public.user_roles,public.customer_accounts,public.customer_memberships,public.invitations,
 public.audit_events from public,anon,authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles,public.roles,public.permissions,public.role_permissions,
 public.user_roles,public.customer_accounts,public.customer_memberships,public.invitations,
 public.audit_events to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.active_user(),private.has_permission(text),
 private.is_customer_member(uuid),private.accept_invitation(uuid) to authenticated;
revoke all on function public.accept_invitation(uuid) from public,anon,authenticated;
grant execute on function public.accept_invitation(uuid) to authenticated;

create trigger profiles_audit after insert or update or delete on public.profiles
for each row execute function private.audit_identity_change();
create trigger user_roles_audit after insert or update or delete on public.user_roles
for each row execute function private.audit_identity_change();
create trigger customers_audit after insert or update or delete on public.customer_accounts
for each row execute function private.audit_identity_change();
create trigger memberships_audit after insert or update or delete on public.customer_memberships
for each row execute function private.audit_identity_change();
create trigger invitations_audit after insert or update or delete on public.invitations
for each row execute function private.audit_identity_change();

-- New tables/functions require explicit grants in future migrations.
alter default privileges in schema public revoke all on tables from public,anon,authenticated;
alter default privileges in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges in schema private revoke all on tables from public,anon,authenticated;
alter default privileges in schema private revoke execute on functions from public,anon,authenticated;

