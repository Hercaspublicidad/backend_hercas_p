import fs from 'node:fs/promises';
import { SpreadsheetFile, FileBlob } from '@oai/artifact-tool';

const dir = 'D:/api_0doo/outputs/requerimientos-hercas-20260918';
const path = process.env.HERCAS_REQUIREMENTS_INPUT || dir + '/requerimientos-compartido-fresco.xlsx';
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheetNames = ['Sales Pipeline', 'Requerimientos', 'Decisiones', 'Guía y fuentes'];
console.log(JSON.stringify({ sheets: wb.worksheets.items.map(s => s.name) }));
for (const name of sheetNames) {
  const sheet = wb.worksheets.getItem(name);
  const range = name === 'Sales Pipeline' ? 'A1:P40' : name === 'Requerimientos' ? 'A1:P95' : name === 'Decisiones' ? 'A1:Q30' : 'A1:P50';
  console.log(JSON.stringify({ name, values: sheet.getRange(range).values }));
  await fs.writeFile(dir + '/auditoria-' + name.replaceAll(' ', '-').replaceAll('í', 'i') + '.png', new Uint8Array(await (await wb.render({sheetName:name, range, scale:0.8})).arrayBuffer()));
}
const errors = await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:100}});
console.log(errors.ndjson);
