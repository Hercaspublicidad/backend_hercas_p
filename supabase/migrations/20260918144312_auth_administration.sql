create function private.admin_update_access(target_user uuid, new_roles text[], active boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare kind text;
begin
 perform pg_advisory_xact_lock(736123001);
 if not private.has_permission('users.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
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
create function public.admin_update_access(target_user uuid,new_roles text[],active boolean) returns void
language sql security invoker set search_path='' as $$select private.admin_update_access(target_user,new_roles,active)$$;

create function private.admin_create_invitation(invite_email text,invite_role text,account_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; role_scope text;
begin
 if not private.has_permission('users.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 select scope into role_scope from public.roles where code=invite_role;
 if role_scope is null then raise exception 'Invalid role' using errcode='22023'; end if;
 if account_id is not null and not exists(select 1 from public.customer_accounts where id=account_id and is_active)
 then raise exception 'Invalid customer' using errcode='22023'; end if;
 insert into public.invitations(email,user_kind,role,scope,customer_account_id,created_by)
 values(lower(btrim(invite_email)),case when role_scope='staff' then 'employee' else 'client' end,invite_role,role_scope,account_id,auth.uid()) returning id into result;
 return result;
end $$;
create function public.admin_create_invitation(invite_email text,invite_role text,account_id uuid default null) returns uuid
language sql security invoker set search_path='' as $$select private.admin_create_invitation(invite_email,invite_role,account_id)$$;
create function private.admin_revoke_invitation(invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_permission('users.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 update public.invitations set revoked_at=now() where id=invitation_id and accepted_at is null and revoked_at is null;
end $$;
create function public.admin_revoke_invitation(invitation_id uuid) returns void
language sql security invoker set search_path='' as $$select private.admin_revoke_invitation(invitation_id)$$;
revoke all on function private.admin_update_access(uuid,text[],boolean),public.admin_update_access(uuid,text[],boolean),
 private.admin_create_invitation(text,text,uuid),public.admin_create_invitation(text,text,uuid),
 private.admin_revoke_invitation(uuid),public.admin_revoke_invitation(uuid) from public,anon,authenticated;
grant execute on function private.admin_update_access(uuid,text[],boolean),public.admin_update_access(uuid,text[],boolean),
 private.admin_create_invitation(text,text,uuid),public.admin_create_invitation(text,text,uuid),
 private.admin_revoke_invitation(uuid),public.admin_revoke_invitation(uuid) to authenticated;
