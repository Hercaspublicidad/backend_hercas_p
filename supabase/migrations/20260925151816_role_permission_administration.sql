create function private.admin_update_role_permissions(target_role text, new_permissions text[]) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(736123002);
  if not private.has_permission('users.manage') then
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

create function public.admin_update_role_permissions(target_role text,new_permissions text[]) returns void
language sql security invoker set search_path='' as $$
  select private.admin_update_role_permissions(target_role,new_permissions);
$$;

create function private.audit_role_permission_change() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into public.audit_events(actor_id,action,entity,entity_id)
  values (
    (select auth.uid()),
    tg_op,
    'role_permissions',
    coalesce(to_jsonb(new)->>'role',to_jsonb(old)->>'role') || ':' || coalesce(to_jsonb(new)->>'permission',to_jsonb(old)->>'permission')
  );
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create trigger role_permissions_audit after insert or update or delete on public.role_permissions
for each row execute function private.audit_role_permission_change();

revoke all on function private.admin_update_role_permissions(text,text[]),public.admin_update_role_permissions(text,text[]),private.audit_role_permission_change() from public,anon,authenticated;
grant execute on function private.admin_update_role_permissions(text,text[]),public.admin_update_role_permissions(text,text[]) to authenticated;
