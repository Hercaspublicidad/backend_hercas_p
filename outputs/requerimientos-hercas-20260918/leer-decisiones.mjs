import { SpreadsheetFile, FileBlob } from '@oai/artifact-tool';
const path='D:/api_0doo/outputs/requerimientos-hercas-20260918/plan-etapa0-fresco.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheet=wb.worksheets.getItem('Decisiones');
console.log(JSON.stringify(sheet.getRange('A1:Q30').values));
