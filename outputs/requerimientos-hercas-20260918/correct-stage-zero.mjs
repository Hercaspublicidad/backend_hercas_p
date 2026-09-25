import fs from 'node:fs/promises';
import {SpreadsheetFile, FileBlob} from '@oai/artifact-tool';
const dir='D:/api_0doo/outputs/requerimientos-hercas-20260918';
const path=process.env.HERCAS_PLAN_EDIT_PATH || dir+'/Hercas - Plan de trabajo Anderson y tu.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path));
const sheet=wb.worksheets.getItem('Asignación 83');
const rows=sheet.getRange('A7:P89').values;
const targets=rows.map((r,i)=>({r,row:i+7})).filter(x=>['SER-011','SER-014'].includes(x.r[0]));
if(targets.length!==2)throw Error('Target rows not found');
console.log(JSON.stringify(targets.map(x=>({row:x.row,id:x.r[0],start:x.r[4],end:x.r[5],dependencies:x.r[8]}))));
if(process.argv.includes('--inspect')){
 const r=targets[0].row;
 await fs.writeFile(dir+'/etapa0-antes.png',new Uint8Array(await(await wb.render({sheetName:sheet.name,range:`A${r}:I${r}`,scale:1.2})).arrayBuffer()));
 process.exit(0);
}
const original=rows.map(r=>[...r]);
sheet.getRange('E6').values=[['Etapa inicio de ejecución']];
sheet.getRange('A4').values=[['Etapa 0: solo diagnóstico, decisiones y contratos. La ejecución inicia desde etapa 1, cuando sus prerrequisitos estén resueltos. Todo Supabase queda contigo.']];
for(const t of targets){
 sheet.getRange(`E${t.row}`).values=[[1]];
 sheet.getRange(`G${t.row}`).values=[[t.r[0]==='SER-011'
 ?'Etapa 0: preparar casos y criterios de prueba. Desde etapa 1: ejecutar pruebas de cada flujo cuando su implementación y decisiones estén listas. Aceptar cada entrega antes de avanzar; revisión integral en etapa 12.'
 :'Etapa 0: recopilar y acordar las decisiones D-003, D-005, D-014 y D-020. Desde etapa 1: implementar en Supabase las reglas aprobadas de autoridad, acceso y conservación por módulo. Revisar cada entrega y cerrar la cobertura integral en etapa 12.']];
 sheet.getRange(`H${t.row}`).values=[[t.r[0]==='SER-011'
 ?'Anderson entrega la función integrada, pruebas backend y evidencia. D-019 debe estar acordada. Preparar casos no equivale a ejecutar ni aprobar un flujo todavía inexistente.'
 :'Anderson implementa en API e integraciones los contratos de datos aprobados. Ninguna regla dependiente se implementa mientras su decisión siga pendiente.']];
}
const plan=wb.worksheets.getItem('Plan a dos');
plan.getRange('E7').values=[['Diagnóstico y contratos versionados. Decisiones D-003/005/014/016/019/020 acordadas para habilitar sus trabajos dependientes. No se ejecutan ni se cierran requisitos funcionales en etapa 0. Proveedores futuros con responsable y fecha límite.']];
const rules=plan.getRange('A24:B40').values;
for(let i=0;i<rules.length;i++)if(rules[i][0]==='Requisitos transversales')plan.getRange(`B${i+24}`).values=[['La etapa 0 prepara decisiones y pruebas. SER-011 y SER-014 comienzan ejecución desde etapa 1, solo con sus prerrequisitos resueltos. Los controles transversales se verifican en cada entrega y cierran globalmente en etapa 12.']];
const gate=wb.worksheets.getItem('Cierre de etapas');
gate.getRange('F6').values=[['Validación de etapa']];
gate.getRange('A4').values=[['Etapa 0 valida diagnóstico, decisiones y contratos. Etapas 1–12 requieren pruebas integradas. Preparar un requisito no autoriza ejecutarlo con dependencias pendientes.']];
wb.recalculate();
const after=sheet.getRange('A7:P89').values;
if(after.some(r=>r[4]===0))throw Error('An execution requirement still starts at 0');
for(let i=0;i<83;i++)for(let j=0;j<16;j++)if(!(targets.some(t=>t.row===i+7)&&[4,6,7].includes(j))&&JSON.stringify(original[i][j])!==JSON.stringify(after[i][j]))throw Error(`Unexpected change ${i+7},${j}`);
if(gate.getRange('C7').values[0][0]!==0||gate.getRange('M7').values[0][0]!=='No')throw Error('Stage zero gate changed incorrectly');
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!',options:{useRegex:true,maxResults:10}})).ndjson);
await(await SpreadsheetFile.exportXlsx(wb)).save(path);
for(const t of targets)await fs.writeFile(dir+`/etapa0-${t.r[0]}.png`,new Uint8Array(await(await wb.render({sheetName:sheet.name,range:`A${t.row}:I${t.row}`,scale:1.2})).arrayBuffer()));
await fs.writeFile(dir+'/etapa0-plan.png',new Uint8Array(await(await wb.render({sheetName:'Plan a dos',range:'A6:F7',scale:1})).arrayBuffer()));
await fs.writeFile(dir+'/etapa0-control.png',new Uint8Array(await(await wb.render({sheetName:'Cierre de etapas',range:'A6:F8',scale:1})).arrayBuffer()));
console.log('CORRECTED: 83 preserved; SER-011 and SER-014 execute from stage 1; stage 0 preparation only.');
