import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile, FileBlob } from '@oai/artifact-tool';
import { groups, decisions, sources } from './data.mjs';
const out = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1');
const ref='C:/Users/Administrador/.codex/plugins/cache/openai-curated-remote/openai-templates/0.1.1/skills/artifact-template-sales-pipeline/assets/reference.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(ref));
const summary=wb.worksheets.getItem('Sales Pipeline');
// Adaptación de contenido comercial de ejemplo a requerimientos, conservando
// la primera hoja, su paleta, tarjetas de resumen y tabla de seguimiento.
for(const t of [...summary.tables.items])t.delete();
summary.getUsedRange().unmerge();
summary.getUsedRange().clear({applyTo:'all'});
summary.getRange('A1:S100').dataValidation=null;
summary.getRange('A1:S100').conditionalFormats.deleteAll();
summary.deleteAllDrawings();
const req=wb.worksheets.add('Requerimientos');
const dec=wb.worksheets.add('Decisiones');
const guide=wb.worksheets.add('Guía y fuentes');
const dark='#0B3D2E', green='#087F5B', pale='#F0F8F3', amber='#FFF2CC';
const col=n=>{let s='';for(;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s};
function setup(s,end,rows){s.showGridLines=false;s.getRange(`A1:${end}${rows}`).format={font:{name:'Arial',size:10,color:'#243B32'},verticalAlignment:'center'};s.tabColor=s===summary?dark:s===guide?'#A4B4AA':green;}
function heading(s,text,last){s.getRange('A2').values=[[text]];s.getRange(`A2:${last}2`).format.font={name:'Arial',size:15,bold:true,color:dark};s.getRange(`A3:${last}3`).format.borders={bottom:{style:'thin',color:green}};s.getRange(`A2:${last}2`).format.rowHeight=28;}
function table(s,headers,rows,row,name,widths){
 const end=col(headers.length),bottom=row+rows.length;
 s.getRange(`A${row}:${end}${bottom}`).values=[headers,...rows];
 const t=s.tables.add(`A${row}:${end}${bottom}`,true,name);t.showFilterButton=true;t.style='TableStyleMedium4';
 s.getRange(`A${row}:${end}${row}`).format={fill:dark,font:{name:'Arial',size:10,color:'#FFFFFF',bold:true},wrapText:true,horizontalAlignment:'center',verticalAlignment:'center',rowHeight:32};
 s.getRange(`A${row+1}:${end}${bottom}`).format.wrapText=true;
 s.getRange(`A${row+1}:${end}${bottom}`).format.verticalAlignment='top';
 widths.forEach((w,i)=>s.getRange(`${col(i+1)}1:${col(i+1)}${bottom}`).format.columnWidth=w);
 for(let r=row+1;r<=bottom;r++){
  const record=rows[r-row-1];
  const lines=Math.max(...record.map((v,i)=>String(v??'').split('\n').reduce((sum,l)=>sum+Math.max(1,Math.ceil(l.length/(widths[i]*.90))),0)));
  s.getRange(`A${r}:${end}${r}`).format.rowHeight=Math.min(240,Math.max(32,lines*15+10));
 }
 return bottom;
}
const all=Object.entries(groups).flatMap(([area,rows])=>rows.map(r=>[r[0],area,...r.slice(1)]));
if(all.length!==83)throw Error('Unexpected count '+all.length);
const ids=new Set([...all.map(r=>r[0]),...decisions.map(d=>d[0])]);
for(const r of all)for(const id of r[11].match(/(?:BE|FE|INT|SER|D)-\d{3}/g)||[])if(!ids.has(id))throw Error('Missing dependency '+id);
setup(req,'P',all.length+5);heading(req,'Hercas — requerimientos e historias de usuario','P');
req.getRange('A4').values=[['Corte 18/09/2026. Filtrar por área o módulo. Complejidad, prioridad e historias son propuestas de análisis pendientes de validación.']];
const headers=['ID','Área','Módulo','Requerimiento','Alcance y límite','Origen del alcance','Estado observado','Brecha / siguiente paso','Complejidad propuesta','Motivo de complejidad','Prioridad propuesta','Dependencias / decisiones','Historia de usuario propuesta','Criterios de aceptación propuestos','Fuentes','Validación del negocio'];
const last=table(req,headers,all,6,'HercasRequerimientos',[13,17,22,34,58,23,24,62,22,44,18,32,70,86,18,24]);
req.freezePanes.freezeRows(6);req.freezePanes.freezeColumns(2);
req.getRange(`P7:P${last}`).format.fill=amber;
req.getRange(`P7:P${last}`).dataValidation={rule:{type:'list',values:['Pendiente','Aprobado','Requiere ajuste','Fuera de alcance']}};
req.getRange(`K7:K${last}`).dataValidation={rule:{type:'list',values:['P0','P1','P2']}};
req.getRange(`I7:I${last}`).dataValidation={rule:{type:'list',values:['Baja','Media','Alta','Muy alta']}};
for(const [text,fill] of [['Por definir','#FCE4D6'],['Planificado','#FFF2CC'],['Piloto','#E2EFDA'],['Parcial','#FFF2CC']])req.getRange(`G7:G${last}`).conditionalFormats.add('containsText',{text,format:{fill}});
req.getRange(`P7:P${last}`).conditionalFormats.add('containsText',{text:'Requiere ajuste',format:{fill:'#FCE4D6'}});
req.getRange(`I7:I${last}`).conditionalFormats.add('containsText',{text:'Muy alta',format:{fill:'#FCE4D6',font:{bold:true}}});

setup(dec,'L',27);heading(dec,'Decisiones para cerrar el alcance','L');
dec.getRange('A4').values=[['Responsables funcionales sugeridos. Las decisiones y fechas en amarillo se completan durante el levantamiento con Hercas.']];
const drows=decisions.map(d=>[...d,'Pendiente',null,null,null]);
const dl=table(dec,['ID','Tema','Decisión requerida','Situación / límite actual','Áreas afectadas','Responsable sugerido','Prioridad propuesta','Fuentes','Estado','Decisión acordada','Responsable asignado','Fecha de acuerdo'],drows,6,'HercasDecisiones',[12,29,76,76,34,41,18,20,22,65,30,20]);
dec.freezePanes.freezeRows(6);dec.freezePanes.freezeColumns(1);
dec.getRange(`I7:L${dl}`).format.fill=amber;dec.getRange(`L7:L${dl}`).setNumberFormat('dd/mm/yyyy');
dec.getRange(`I7:I${dl}`).dataValidation={rule:{type:'list',values:['Pendiente','En revisión','Acordada','Descartada']}};
dec.getRange(`I7:I${dl}`).conditionalFormats.addCustom('AND($I7="Acordada",OR($J7="",$K7="",$L7=""))',{fill:'#FCE4D6'});

setup(guide,'D',55);heading(guide,'Criterios de lectura y evidencia','D');
const notes=[
 ['Cobertura','Revisión de la documentación, API Python, migraciones y worktrees locales del sitio y piloto. Corte: 18/09/2026.'],
 ['Límite de verificación','Se inspeccionaron fuentes locales. No se probó el sistema en producción, no se ejecutaron pruebas del proyecto ni se revalidó Supabase/Odoo remoto.'],
 ['Alcance confirmado','Siete módulos: usuarios, cotizador, reportes, pagos, CMS, blogs/redes y agente. Pantallas, renders y captación CRM son ampliaciones documentadas.'],
 ['Origen del alcance','Existente observado: encontrado en código/piloto. Confirmado documental: capacidad o decisión expresa. Derivado del alcance: descomposición propuesta para implementar/validar.'],
 ['Código local','La función o interfaz existe en archivos revisados. No significa integrada, desplegada, probada de extremo a extremo ni aprobada por el negocio.'],
 ['Base BD documentada','Reglas y tablas con aplicación en desarrollo reportada en documentos. La evidencia remota corresponde al corte descrito por esas fuentes.'],
 ['Piloto','Funcionalidad experimental o con almacenamiento local/datos orientativos. No representa operación compartida de producción.'],
 ['Parcial','Hay evidencia de una parte de la capacidad. La columna de brecha indica lo que queda por completar o verificar.'],
 ['Planificado / Por definir','Planificado: capacidad documentada sin implementación completa localizada. Por definir: necesita decisión de negocio o proveedor antes de cerrar diseño.'],
 ['Complejidad Baja / Media','Baja: interacción o adaptación puntual con pocas reglas. Media: varias validaciones o vistas con contratos conocidos. Estimación cualitativa, no horas.'],
 ['Complejidad Alta / Muy alta','Alta: permisos, transacciones, reglas o integración externa relevantes. Muy alta: concurrencia/capacidad, múltiples proveedores o alta incertidumbre de datos/proceso.'],
 ['Prioridad propuesta','P0: condición para operar de forma coherente o lanzar el corte inicial. P1: ampliación después de dependencias. P2: mejora posterior. No son compromisos aprobados.'],
 ['Historias y aceptación','Historias redactadas a partir de capacidades encontradas. Los criterios describen comportamiento exigido, no pruebas ya superadas. Requieren validación con responsables.'],
 ['Validación del negocio','Columna amarilla permite aprobar, ajustar o excluir cada requisito. La evidencia original se mantiene separada del acuerdo del negocio.'],
 ['Dependencias','IDs BE/FE/INT/SER son requerimientos. D son decisiones. Se muestran precedencias principales, no un cronograma ni estimación de ruta crítica.'],
 ['Extensión del libro','Las tablas se pueden filtrar/ordenar. El resumen cubre filas 7 a 1000 de Requerimientos; al superar ese límite, ampliar sus rangos de fórmulas.'],
 ['Conflictos de evidencia','Migración administrativa local del 18/09 demuestra código posterior al README del 17/09, pero no demuestra despliegue. La base SQL posterior actualiza pendientes de migración anteriores.'],
 ['Indicadores del resumen','Son cantidades de requisitos por clasificación. No representan porcentaje de avance, esfuerzo completado ni aceptación productiva.']
];
table(guide,['Criterio','Aplicación'],notes,5,'HercasCriterios',[34,120]);
guide.getRange('A26').values=[['Fuentes consultadas']];guide.getRange('A26:D26').format={fill:dark,font:{bold:true,color:'#FFFFFF'},rowHeight:25};
table(guide,['Fuente','Documento / componente','Localizador de evidencia','Alcance de la evidencia'],sources,28,'HercasFuentes',[13,34,82,100]);
// Restaurar anchos de notas para no convertir sus textos en renglones excesivos.
guide.getRange('A1:A44').format.columnWidth=34;
guide.getRange('B1:B44').format.columnWidth=100;
guide.getRange('A6:B23').format.wrapText=true;
for(let r=6;r<=23;r++)guide.getRange(`A${r}:D${r}`).format.rowHeight=72;
guide.freezePanes.freezeRows(5);

setup(summary,'S',42);summary.freezePanes.unfreeze();
summary.getRange('A1:S42').format.fill='#FFFFFF';
summary.getRange('A1:S42').format.columnWidth=12;
summary.getRange('A1:A42').format.columnWidth=3;
summary.getRange('Q1:Q42').format.columnWidth=3;
summary.mergeCells('B2:P2');summary.getRange('B2').values=[['Hercas — levantamiento de requerimientos']];
summary.mergeCells('B3:P3');summary.getRange('B3').values=[['Backend, frontend, integraciones y servicios. Corte documental y de código: 18/09/2026.']];
summary.getRange('B2:P3').format={fill:dark,font:{name:'Arial',color:'#FFFFFF'},rowHeight:25};summary.getRange('B2').format.font={size:15,bold:true};
const range=c=>`Requerimientos!$${c}$7:$${c}$1000`;
const cards=[['B5:F5','B6:F7','REQUERIMIENTOS',`=COUNTA(${range('A')})`],['G5:K5','G6:K7','COMPLEJIDAD ALTA O MUY ALTA',`=COUNTIFS(${range('I')},"Alta")+COUNTIFS(${range('I')},"Muy alta")`],['L5:P5','L6:P7','DECISIONES PENDIENTES','=COUNTIFS(Decisiones!$I$7:$I$1000,"Pendiente")'],['B9:F9','B10:F11','BACKEND',`=COUNTIFS(${range('B')},"Backend")`],['G9:K9','G10:K11','FRONTEND',`=COUNTIFS(${range('B')},"Frontend")`],['L9:P9','L10:P11','INTEGRACIONES Y SERVICIOS',`=COUNTIFS(${range('B')},"Integraciones")+COUNTIFS(${range('B')},"Servicios")`]];
for(const [head,val,label,formula] of cards){summary.mergeCells(head);summary.mergeCells(val);summary.getRange(head).values=[[label]];summary.getRange(head).format={fill:pale,font:{name:'Arial',size:10,bold:true,color:'#5B6570'},horizontalAlignment:'center',rowHeight:22};summary.getRange(val).formulas=[[formula]];summary.getRange(val).setNumberFormat('0');summary.getRange(val).format={font:{name:'Arial',size:16,bold:true,color:dark},horizontalAlignment:'center',verticalAlignment:'center',borders:{preset:'outside',style:'thin',color:'#D9E0E6'}};}
summary.mergeCells('B13:P13');summary.getRange('B13').values=[['Estado observado por área']];summary.getRange('B13:P13').format={fill:green,font:{bold:true,color:'#FFFFFF'},rowHeight:24};
const sh=['Área','Total','Código local','Base BD','Piloto','Parcial','Planificado','Por definir'];
const spans=[['B','D'],['E','E'],['F','G'],['H','I'],['J','J'],['K','K'],['L','M'],['N','P']];
sh.forEach((h,i)=>{const[a,b]=spans[i];summary.mergeCells(`${a}15:${b}15`);summary.getRange(`${a}15`).values=[[h]];});
summary.getRange('B15:P15').format={fill:dark,font:{color:'#FFFFFF',bold:true},horizontalAlignment:'center',wrapText:true,rowHeight:30};
Object.keys(groups).forEach((area,i)=>{const r=16+i;for(const [a,b]of spans)summary.mergeCells(`${a}${r}:${b}${r}`);summary.getRange(`B${r}`).values=[[area]];summary.getRange(`E${r}`).formulas=[[`=COUNTIFS(${range('B')},B${r})`]];['Código local','Base BD documentada','Piloto','Parcial','Planificado','Por definir'].forEach((st,j)=>summary.getRange(`${spans[j+2][0]}${r}`).formulas=[[`=COUNTIFS(${range('B')},B${r},${range('G')},"${st}")`]]);summary.getRange(`B${r}:P${r}`).format={fill:i%2?pale:'#FFFFFF',rowHeight:28};summary.getRange(`E${r}:P${r}`).setNumberFormat('0');});
const messages=[
 'Los conteos describen evidencia disponible. No equivalen a funciones aceptadas ni a un porcentaje de avance.',
 'Requerimientos: 83 registros filtrables con alcance, historia de usuario, complejidad, prioridad, dependencias y aceptación.',
 'Decisiones: 20 asuntos con campos para registrar acuerdo, responsable y fecha. Guía y fuentes: definiciones y evidencia.',
 'Prioridades y complejidad son propuestas para validar. No se estimaron horas, costos ni fechas de entrega.',
 'Atención: inventario del sitio y fuentes comerciales usan cortes distintos. Conciliar antes de publicar disponibilidad.',
 'Avance localizado: API, base de identidad/comercial, web pública y piloto cotizador. Falta verificar integración completa.',
 'La revisión fue local y documental. No se modificó código del proyecto ni se operaron servicios remotos.'
];
messages.forEach((m,i)=>{let r=22+i*2;summary.mergeCells(`B${r}:P${r+1}`);summary.getRange(`B${r}`).values=[[m]];summary.getRange(`B${r}:P${r+1}`).format={wrapText:true,verticalAlignment:'center',fill:i===4?amber:'#FFFFFF',font:{size:11,color:'#243B32'}};});

wb.recalculate();
const count=summary.getRange('B6').values[0][0];if(count!==83)throw Error('Summary total '+count);
// Verificar que una edición cambia el conteo y restaurar antes de exportar.
const old=req.getRange('I7').values[0][0];const highBefore=summary.getRange('G6').values[0][0];
req.getRange('I7').values=[['Muy alta']];if(summary.getRange('G6').values[0][0]!==highBefore+1)throw Error('Summary does not recalculate');req.getRange('I7').values=[[old]];
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'Sales Pipeline!B15:P19',include:'values,formulas',tableMaxRows:5,tableMaxCols:15,maxChars:2500})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},summary:'Formula error scan'})).ndjson);
const output=await SpreadsheetFile.exportXlsx(wb);await output.save(out+'/Hercas - Levantamiento de requerimientos.xlsx');
for(const[sheetName,range,name]of [['Sales Pipeline','B2:P35','resumen'],['Requerimientos','A6:E9','requerimientos'],['Requerimientos','M6:P9','historias'],['Decisiones','A6:F9','decisiones'],['Guía y fuentes','A5:B10','guia'],['Guía y fuentes','A28:D31','fuentes']]){
 await fs.writeFile(out+'/'+name+'.png',new Uint8Array(await(await wb.render({sheetName,range,scale:1.2})).arrayBuffer()));
}
await fs.writeFile(out+'/verification.json',JSON.stringify({requirements:all.length,decisions:decisions.length,areas:Object.fromEntries(Object.entries(groups).map(([k,v])=>[k,v.length])),uniqueIds:new Set(all.map(x=>x[0])).size,sources:sources.length,recalculation:'count changed and restored',renderedSheets:4},null,2));
console.log('SAVED',all.length,'requirements',decisions.length,'decisions');
