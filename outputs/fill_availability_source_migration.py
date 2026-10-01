from pathlib import Path
import json

root = Path(r"D:\api_0doo")
path = root / "supabase/migrations/20261001193000_availability_weekly_source_import.sql"
source = (root / "outputs/katherine-availability-20261001.json").read_text(encoding="utf-8")
records = json.loads(source)
if len(records) != 112 or any("$source$" in json.dumps(row) for row in records):
    raise RuntimeError("Unexpected source format")
body = path.read_text(encoding="utf-8")
if body.count("__SOURCE_JSON__") != 1 or body.count("__SOURCE_HASH__") != 6:
    raise RuntimeError("Migration already populated or changed")
body = body.replace("__SOURCE_JSON__", json.dumps(records, ensure_ascii=False, separators=(",", ":")))
body = body.replace("__SOURCE_HASH__", "30B66DBF47FFA1D560C62981495DFBE166DD5DD5A3BBBB95990C87C677F15F5B")
path.write_text(body, encoding="utf-8")
print(f"Prepared {len(records)} source rows in {path.name}")
