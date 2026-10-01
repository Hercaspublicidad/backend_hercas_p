-- Explicit RLS policies for operational queues. The tables keep their grants
-- revoked; these policies document and enforce the intended minimum readers.
create policy availability_notification_recipients_manager_read
on public.availability_notification_recipients
for select to authenticated
using ((select private.has_permission('cotizador.availability.manage')));

create policy availability_notification_outbox_no_browser_access
on public.availability_notification_outbox
for select to authenticated
using (false);

create policy availability_report_deliveries_read
on public.availability_report_deliveries
for select to authenticated
using (
  requested_by = (select auth.uid())
  or (select private.has_permission('cotizador.availability.manage'))
);

-- The public calendar will be delivered through the Python API after its
-- rate-limit and response cache are implemented. Do not expose a SECURITY
-- DEFINER function through the Data API in the meantime.
revoke execute on function public.public_asset_available_days(text, date)
from anon, authenticated;
