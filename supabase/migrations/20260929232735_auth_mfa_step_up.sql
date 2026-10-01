-- A user who enrolled MFA must complete it before changing access controls.
-- Users with no enrolled factor keep the existing onboarding flow.
create function private.has_strong_auth() returns boolean
language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and (
    not exists (
      select 1 from auth.mfa_factors factor
      where factor.user_id=(select auth.uid()) and factor.status='verified'
    )
    or coalesce((select auth.jwt()->>'aal'), 'aal1')='aal2'
  );
$$;

create function private.require_strong_auth() returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.has_strong_auth() then
    raise exception 'Multi-factor authentication required' using errcode='42501';
  end if;
end;
$$;

create function public.require_strong_auth() returns void
language sql security invoker set search_path='' as $$
  select private.require_strong_auth();
$$;

revoke all on function private.has_strong_auth(), private.require_strong_auth(),
  public.require_strong_auth() from public, anon, authenticated;
grant execute on function private.has_strong_auth(), private.require_strong_auth(),
  public.require_strong_auth() to authenticated;

create or replace function private.admin_update_access(target_user uuid, new_roles text[], active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare kind text;
begin
 perform pg_advisory_xact_lock(736123001);
 if not private.has_permission('users.manage') or not private.has_strong_auth() then raise exception 'Forbidden' using errcode='42501'; end if;
 if active is null or new_roles is null then raise exception 'Invalid access' using errcode='22023'; end if;
 select user_kind into kind from public.profiles where id=target_user and activated_at is not null for update;
 if not found then raise exception 'Active identity not found' using errcode='22023'; end if;
 if kind='client' and cardinality(new_roles)>0 then raise exception 'Client roles are scoped to companies' using errcode='22023'; end if;
 if exists(select 1 from unnest(new_roles) r where r is null or not exists(select 1 from public.roles where code=r and scope='staff'))
 then raise exception 'Invalid role' using errcode='22023'; end if;
 if not active or not ('systems_admin'=any(new_roles)) then
   if not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id
     where p.id<>target_user and p.is_active and r.role='systems_admin' and r.revoked_at is null)
   then raise exception 'Last administrator must remain active' using errcode='22023'; end if;
 end if;
 update public.user_roles set revoked_at=now() where user_id=target_user and revoked_at is null and not(role=any(new_roles));
 insert into public.user_roles(user_id,role,granted_by) select target_user,r,auth.uid() from (select distinct unnest(new_roles) r) x
 on conflict (user_id,role) where revoked_at is null do nothing;
 update public.profiles set is_active=active where id=target_user;
end $$;

create or replace function private.admin_create_invitation(invite_email text,invite_role text,account_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; role_scope text; normalized_email text;
begin
 if not private.has_permission('users.manage') or not private.has_strong_auth() then raise exception 'Forbidden' using errcode='42501'; end if;
 normalized_email:=lower(btrim(invite_email));
 if normalized_email is null or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
   raise exception 'Invalid email' using errcode='22023';
 end if;
 select scope into role_scope from public.roles where code=invite_role;
 if role_scope is null then raise exception 'Invalid role' using errcode='22023'; end if;
 if account_id is not null and not exists(select 1 from public.customer_accounts where id=account_id and is_active)
 then raise exception 'Invalid customer' using errcode='22023'; end if;
 insert into public.invitations(email,user_kind,role,scope,customer_account_id,created_by)
 values(normalized_email,case when role_scope='staff' then 'employee' else 'client' end,invite_role,role_scope,account_id,auth.uid())
 on conflict (email) where accepted_at is null and revoked_at is null do update
 set user_kind=excluded.user_kind,
     role=excluded.role,
     scope=excluded.scope,
     customer_account_id=excluded.customer_account_id,
     created_by=excluded.created_by,
     created_at=now(),
     expires_at=now()+interval '7 days'
 returning id into result;
 return result;
end $$;

create or replace function private.admin_revoke_invitation(invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_permission('users.manage') or not private.has_strong_auth() then raise exception 'Forbidden' using errcode='42501'; end if;
 update public.invitations set revoked_at=now() where id=invitation_id and accepted_at is null and revoked_at is null;
end $$;

create or replace function private.admin_update_role_permissions(target_role text, new_permissions text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(736123002);
  if not private.has_permission('users.manage') or not private.has_strong_auth() then
    raise exception 'Forbidden' using errcode='42501';
  end if;
  if target_role is null or new_permissions is null
     or not exists (select 1 from public.roles where code=target_role) then
    raise exception 'Invalid role permissions' using errcode='22023';
  end if;
  if exists (
    select 1 from unnest(new_permissions) permission_code
    where permission_code is null
       or not exists (select 1 from public.permissions where code=permission_code)
  ) then
    raise exception 'Invalid permission' using errcode='22023';
  end if;
  if target_role='systems_admin' and not ('users.manage'=any(new_permissions)) then
    raise exception 'Systems administrator must retain user management' using errcode='22023';
  end if;
  delete from public.role_permissions
  where role=target_role and not (permission=any(new_permissions));
  insert into public.role_permissions(role,permission)
  select target_role, permission_code from (select distinct unnest(new_permissions) permission_code) permissions
  on conflict (role,permission) do nothing;
end;
$$;
