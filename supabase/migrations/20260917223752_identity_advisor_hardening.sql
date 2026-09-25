-- Dashboard automatic-RLS event trigger is not an API operation.
-- Guard allows replay in local databases where the dashboard helper is absent.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;
drop index public.user_roles_role_idx;
create index user_roles_role_idx on public.user_roles(role, scope);
drop index public.customer_memberships_role_idx;
create index customer_memberships_role_idx on public.customer_memberships(role, scope);
drop index public.invitations_role_idx;
create index invitations_role_idx on public.invitations(role, scope);
