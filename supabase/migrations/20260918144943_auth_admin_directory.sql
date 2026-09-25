create function private.admin_user_directory(page_offset integer default 0)
returns table(id uuid,display_name text,user_kind text,is_active boolean,email text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_permission('users.manage') then raise exception 'Forbidden' using errcode='42501'; end if;
 if page_offset<0 or page_offset is null then raise exception 'Invalid page' using errcode='22023'; end if;
 return query select p.id,p.display_name,p.user_kind,p.is_active,u.email::text
 from public.profiles p join auth.users u on u.id=p.id
 order by p.created_at,p.id limit 100 offset page_offset;
end $$;
create function public.admin_user_directory(page_offset integer default 0)
returns table(id uuid,display_name text,user_kind text,is_active boolean,email text)
language sql stable security invoker set search_path='' as $$select * from private.admin_user_directory(page_offset)$$;
revoke all on function private.admin_user_directory(integer),public.admin_user_directory(integer) from public,anon,authenticated;
grant execute on function private.admin_user_directory(integer),public.admin_user_directory(integer) to authenticated;
