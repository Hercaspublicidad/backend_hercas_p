import { SpreadsheetFile } from "@oai/artifact-tool";

const input = "D:/api_0doo/outputs/supabase-permissions-20260925/Hercas - Plan de trabajo Anderson y tu.before.xlsx";
const workbook = await SpreadsheetFile.importXlsx(input);
console.log((await workbook.inspect({ kind: "sheet", include: "id,name" })).ndjson);
for (const name of ["Plan de trabajo", "Plan", "Cronograma", "Requerimientos"]) {
  try {
    const result = await workbook.inspect({ kind: "table", range: `${name}!A1:Z80`, include: "values,formulas", tableMaxRows: 80, tableMaxCols: 26 });
    console.log(`SHEET ${name}`);
    console.log(result.ndjson);
  } catch { /* The shared workbook may use another tab name. */ }
}
