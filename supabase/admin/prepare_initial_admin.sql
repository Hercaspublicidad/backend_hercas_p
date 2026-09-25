-- Execute once as database owner AFTER foundation migration.
-- This prepares authorization only. It does NOT create an Auth user or send email.
-- Administrator email selected by Carlos on 2026-09-22: asesoria@hercas.net.
begin;
do $$
begin
  perform pg_advisory_xact_lock(736123001);
  if exists (select 1 from public.user_roles where role='systems_admin' and revoked_at is null)
  then raise exception 'An administrator already exists'; end if;
  if not exists (
    select 1 from public.invitations where email='asesoria@hercas.net'
      and role='systems_admin' and revoked_at is null
      and accepted_at is null and expires_at > now()
  ) then
    insert into public.invitations(email,user_kind,role,scope)
    values('asesoria@hercas.net','employee','systems_admin','staff');
  end if;
end;
$$;
select id,email,expires_at from public.invitations
where email='asesoria@hercas.net' and role='systems_admin'
  and revoked_at is null and accepted_at is null and expires_at>now();
commit;
