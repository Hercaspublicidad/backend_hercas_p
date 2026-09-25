import fs from 'node:fs/promises';
import { SpreadsheetFile, FileBlob } from '@oai/artifact-tool';

const dir = 'D:/api_0doo/outputs/requerimientos-hercas-20260918';
const input = process.env.HERCAS_REQUIREMENTS_INPUT || dir + '/Hercas - Levantamiento de requerimientos corregido.xlsx';
const output = process.env.HERCAS_REQUIREMENTS_OUTPUT || dir + '/Hercas - Levantamiento de requerimientos corregido - Carlos.xlsx';
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const areas = {
  'Resumen': 'A1:L36',
  'Backlog operativo': 'A1:O95',
  'Detalle de requisitos': 'A1:J95',
  'Decisiones': 'A1:Q30',
  'Fuentes y evidencia': 'A1:D45'
};
const col = n => { let s = ''; for (; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
let changed = 0;
for (const [name, range] of Object.entries(areas)) {
  const sheet = wb.worksheets.getItem(name);
  const values = sheet.getRange(range).values;
  for (let r = 0; r < values.length; r++) for (let c = 0; c < values[r].length; c++) {
    if (typeof values[r][c] !== 'string' || !values[r][c].includes('Tú')) continue;
    sheet.getRange(`${col(c + 1)}${r + 1}`).values = [[values[r][c].replaceAll('Tú', 'Carlos')]];
    changed++;
  }
}
if (changed === 0) throw new Error('No se encontró el responsable “Tú” en el libro.');
wb.recalculate();
for (const [name, range] of Object.entries(areas)) {
  if (wb.worksheets.getItem(name).getRange(range).values.flat().some(value => typeof value === 'string' && value.includes('Tú'))) throw new Error(`Quedó una referencia a “Tú” en ${name}.`);
}
const errors = await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:20}});
if (/"kind":"match"/.test(errors.ndjson)) throw new Error(errors.ndjson);
await (await SpreadsheetFile.exportXlsx(wb)).save(output);
await fs.writeFile(dir + '/requerimientos-carlos-backlog.png', new Uint8Array(await (await wb.render({sheetName:'Backlog operativo',range:'A2:O12',scale:1})).arrayBuffer()));
console.log(JSON.stringify({output, changed, formulaErrors: 0}));
