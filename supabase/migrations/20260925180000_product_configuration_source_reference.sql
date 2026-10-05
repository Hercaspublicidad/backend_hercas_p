-- Every product profile needs a durable source reference. Product codes are not reused
-- as a substitute for the commercial name; this reference identifies the origin record.
update public.product_configuration_profiles profile
set source_reference = case
  when product.external_code like 'provisional:valla:%' then 'INVENTORY-' || product.code
  when product.odoo_product_id is not null then 'ODOO-TEMPLATE-' || product.odoo_product_id::text
  else 'HERCAS-CATALOG-' || product.code
end
from public.products product
where product.id = profile.product_id
  and nullif(btrim(profile.source_reference), '') is null;

alter table public.product_configuration_profiles
  alter column source_reference set not null,
  add constraint product_configuration_profiles_source_reference_check
    check (length(btrim(source_reference)) between 1 and 200);

create index product_configuration_profiles_source_reference_idx
  on public.product_configuration_profiles(source_reference);