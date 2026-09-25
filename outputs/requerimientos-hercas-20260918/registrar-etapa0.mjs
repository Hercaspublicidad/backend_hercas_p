import fs from 'node:fs/promises';
import { SpreadsheetFile, FileBlob } from '@oai/artifact-tool';

const dir = 'D:/api_0doo/outputs/requerimientos-hercas-20260918';
const input = process.env.HERCAS_PLAN_INPUT || dir + '/Hercas - Plan de trabajo Anderson y tu.xlsx';
const output = process.env.HERCAS_PLAN_OUTPUT || dir + '/plan-etapa0-pendiente.xlsx';
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const sheet = wb.worksheets.getItem('Cierre de etapas');

const before = sheet.getRange('A6:M8').values.map(row => [...row]);
console.log(JSON.stringify(before));

sheet.getRange('G7').values = [[
  '18/09: Supabase saludable; 5 migraciones aplicadas y 18 tablas con RLS. Pruebas locales: Python 48 OK y PostgreSQL/PGlite 35 OK. Lectura anónima bloqueada (401).'
  + ' Auth: registro público desactivado y confirmación por correo requerida.'
]];
sheet.getRange('J7').values = [[
  'Pendiente: activar el primer administrador y ejecutar sesión/RLS con dos empresas. El asesor reporta protección contra contraseñas filtradas desactivada.'
]];
sheet.getRange('K7').values = [[2]];
sheet.getRange('F7').values = [['Pendiente']];
sheet.getRange('G7').format.wrapText = true;
sheet.getRange('J7').format.wrapText = true;
sheet.getRange('7:7').format.rowHeight = 70;

wb.recalculate();
const after = sheet.getRange('A6:M8').values;
if (after[1][5] !== 'Pendiente' || after[1][10] !== 2) throw new Error('Stage 0 status was not recorded');
const errors = await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!',options:{useRegex:true,maxResults:20}});
if (/"kind":"match"/.test(errors.ndjson)) throw new Error(errors.ndjson);
await (await SpreadsheetFile.exportXlsx(wb)).save(output);
await fs.writeFile(dir + '/etapa0-registro-pendiente.png', new Uint8Array(await (await wb.render({sheetName:sheet.name,range:'A6:M8',scale:1.1})).arrayBuffer()));
console.log(JSON.stringify(after));
console.log(`STAGED=${output}`);
