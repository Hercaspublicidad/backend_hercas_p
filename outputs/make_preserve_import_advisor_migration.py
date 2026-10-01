from pathlib import Path

root = Path(r"D:\api_0doo\supabase\migrations")
source = (root / "20261001164147_availability_campaign_advisor.sql").read_text(encoding="utf-8")
start = source.index("create or replace function private.set_sales_availability_bulk(")
end = source.index("create function private.set_sales_availability_bulk_v2(")
body = source[start:end]
old_columns = "customer_name, campaign_name, advisor_id,\n          created_by, updated_by"
new_columns = "customer_name, campaign_name, advisor_id, advisor_source_label,\n          created_by, updated_by"
old_values = "entry_row.campaign_name, entry_row.advisor_id, entry_row.created_by, actor"
new_values = "entry_row.campaign_name, entry_row.advisor_id, entry_row.advisor_source_label, entry_row.created_by, actor"
if body.count(old_columns) != 2 or body.count(old_values) != 2:
    raise RuntimeError("Unexpected original bulk function")
body = body.replace(old_columns, new_columns).replace(old_values, new_values)
target = root / "20261001202500_preserve_import_advisor.sql"
target.write_text("-- Keep imported advisor names on fragments outside a partial correction.\n" + body, encoding="utf-8")
print(target)
