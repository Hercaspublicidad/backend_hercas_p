import { Workbook } from '@oai/artifact-tool';
console.log((await Workbook.help('*', {include:'index,examples,notes', maxChars:3000})).ndjson);
