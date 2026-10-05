-- Keep a single pending invitation per normalized email. Existing historical
-- rows are retained for audit; only duplicate pending rows are revoked.
with ranked_pending as (
  select id,
    row_number() over (partition by email order by created_at desc, id desc) as position
  from public.invitations
  where accepted_at is null and revoked_at is null
)
update public.invitations invitation
set revoked_at=now()
from ranked_pending ranked
where invitation.id=ranked.id and ranked.position > 1;

create unique index invitations_one_pending_per_email
  on public.invitations(email)
  where accepted_at is null and revoked_at is null;

create or replace function private.admin_create_invitation(invite_email text,invite_role text,account_id uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid; role_scope text; normalized_email text;
begin
 if not private.has_permission('users.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
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
