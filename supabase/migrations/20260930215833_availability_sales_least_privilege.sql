-- Sales can reserve, confirm and release their own entries through the
-- dedicated RPCs. Calendar-wide administration remains with Katherine's role.
delete from public.role_permissions
where role = 'sales' and permission = 'cotizador.availability.manage';
