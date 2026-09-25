import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile, FileBlob } from '@oai/artifact-tool';

const dir = 'D:/api_0doo/outputs/requerimientos-hercas-20260918';
const sourcePath = process.env.HERCAS_REQUIREMENTS_INPUT || dir + '/requerimientos-compartido-fresco.xlsx';
const planPath = process.env.HERCAS_PLAN_INPUT || dir + '/plan-compartido-para-requerimientos.xlsx';
const output = process.env.HERCAS_REQUIREMENTS_OUTPUT || dir + '/Hercas - Levantamiento de requerimientos corregido.xlsx';
const source = await SpreadsheetFile.importXlsx(await FileBlob.load(sourcePath));
const plan = await SpreadsheetFile.importXlsx(await FileBlob.load(planPath));
const requirements = source.worksheets.getItem('Requerimientos').getRange('A7:P89').values;
const assignments = plan.worksheets.getItem('Asignación 83').getRange('A7:P89').values;
const decisions = plan.worksheets.getItem('Decisiones').getRange('A7:Q26').values;
const sources = source.worksheets.getItem('Guía y fuentes').getRange('A29:D43').values;
if (requirements.length !== 83 || assignments.length !== 83 || decisions.length !== 20) throw new Error('La fuente no contiene los 83 requisitos, las 83 asignaciones y las 20 decisiones esperadas.');

const assignmentById = new Map(assignments.map(row => [row[0], row]));
if (new Set(requirements.map(row => row[0])).size !== 83) throw new Error('Hay IDs de requisito duplicados.');
for (const row of requirements) if (!assignmentById.has(row[0])) throw new Error(`Falta asignación para ${row[0]}.`);

const dark = '#0B3D2E', green = '#087F5B', pale = '#F0F8F3', amber = '#FFF2CC', text = '#243B32';
const wb = new Workbook({});
const summary = wb.worksheets.add('Resumen');
const backlog = wb.worksheets.add('Backlog operativo');
const detail = wb.worksheets.add('Detalle de requisitos');
const dec = wb.worksheets.add('Decisiones');
const evidence = wb.worksheets.add('Fuentes y evidencia');
const col = n => { let s = ''; for (; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
const init = (sheet, title, last, rows) => {
  sheet.showGridLines = false;
  sheet.getRange(`A1:${last}${rows}`).format = { font: { name: 'Arial', size: 10, color: text }, verticalAlignment: 'center' };
  sheet.getRange('A2').values = [[title]];
  sheet.getRange(`A2:${last}2`).format = { font: { name: 'Arial', size: 15, color: dark, bold: true }, rowHeight: 28 };
  sheet.getRange(`A3:${last}3`).format.borders = { bottom: { style: 'thin', color: green } };
};
const addTable = (sheet, headers, rows, start, widths, name, wrap = true) => {
  const end = col(headers.length), last = start + rows.length;
  sheet.getRange(`A${start}:${end}${last}`).values = [headers, ...rows];
  const table = sheet.tables.add(`A${start}:${end}${last}`, true, name);
  table.style = 'TableStyleMedium4';
  table.showFilterButton = true;
  sheet.getRange(`A${start}:${end}${start}`).format = { fill: dark, font: { name: 'Arial', size: 10, color: '#FFFFFF', bold: true }, horizontalAlignment: 'center', verticalAlignment: 'center', wrapText: true, rowHeight: 34 };
  sheet.getRange(`A${start + 1}:${end}${last}`).format.verticalAlignment = 'top';
  if (wrap) sheet.getRange(`A${start + 1}:${end}${last}`).format.wrapText = true;
  widths.forEach((width, i) => sheet.getRange(`${col(i + 1)}1:${col(i + 1)}${last}`).format.columnWidth = width);
  return last;
};

// Vista de trabajo: una fila por requisito y solo los datos para priorizar y ejecutar.
const backlogRows = requirements.map(row => {
  const a = assignmentById.get(row[0]);
  return [row[0], row[1], row[2], row[3], a[3], a[4], a[5], row[10], row[8], row[6], row[11], row[7], a[10], a[11], row[15]];
});
init(backlog, 'Backlog operativo — 83 requisitos', 'O', 95);
backlog.getRange('A4').values = [['Filtra por etapa, responsable, prioridad o estado. “Cerrado” exige evidencia y revisión aprobada en el plan compartido.']];
const backlogLast = addTable(backlog, ['ID', 'Área', 'Módulo', 'Requerimiento', 'Responsable de cierre', 'Etapa inicio', 'Etapa cierre', 'Prioridad', 'Complejidad', 'Estado técnico', 'Dependencias', 'Siguiente paso / bloqueo', 'Ejecución', 'Revisión cruzada', 'Validación negocio'], backlogRows, 6, [13,16,23,38,22,15,15,14,16,21,31,54,18,20,22], 'HercasBacklog');
backlog.freezePanes.freezeRows(6); backlog.freezePanes.freezeColumns(4);
backlog.getRange(`M7:O${backlogLast}`).format.fill = amber;
backlog.getRange(`M7:M${backlogLast}`).dataValidation = { rule: { type: 'list', values: ['Por iniciar', 'En curso', 'En revisión', 'Bloqueado', 'Cerrado'] } };
backlog.getRange(`N7:N${backlogLast}`).dataValidation = { rule: { type: 'list', values: ['Pendiente', 'Aprobada', 'Requiere ajustes'] } };
backlog.getRange(`O7:O${backlogLast}`).dataValidation = { rule: { type: 'list', values: ['Pendiente', 'Aprobado', 'Requiere ajuste', 'Fuera de alcance'] } };
backlog.getRange(`J7:J${backlogLast}`).conditionalFormats.add('containsText', { text: 'Por definir', format: { fill: '#FCE4D6' } });
backlog.getRange(`M7:M${backlogLast}`).conditionalFormats.add('containsText', { text: 'Bloqueado', format: { fill: '#FCE4D6', font: { bold: true } } });
backlog.getRange(`O7:O${backlogLast}`).conditionalFormats.add('containsText', { text: 'Requiere ajuste', format: { fill: '#FCE4D6' } });
for (let r = 7; r <= backlogLast; r++) backlog.getRange(`A${r}:O${r}`).format.rowHeight = 38;

// Detalle: conserva alcance, historia y criterios sin forzar el uso diario de una tabla de 16 columnas.
const detailRows = requirements.map(row => [row[0], row[3], row[4], row[5], row[6], row[7], row[9], row[12], row[13], row[14]]);
init(detail, 'Detalle de alcance, historias y aceptación', 'J', 95);
detail.getRange('A4').values = [['Esta hoja conserva el detalle completo. Usa el Backlog operativo para gestionar el trabajo diario.']];
const detailLast = addTable(detail, ['ID', 'Requerimiento', 'Alcance y límite', 'Origen', 'Estado técnico', 'Brecha / siguiente paso', 'Motivo de complejidad', 'Historia de usuario', 'Criterios de aceptación', 'Fuentes'], detailRows, 6, [13,35,68,24,23,62,48,68,86,18], 'HercasDetalle');
detail.freezePanes.freezeRows(6); detail.freezePanes.freezeColumns(2);
for (let r = 7; r <= detailLast; r++) detail.getRange(`A${r}:J${r}`).format.rowHeight = 76;

// Decisiones: se mantiene la matriz completa del plan, con la información de coordinación por etapa.
init(dec, 'Decisiones para cerrar el alcance', 'Q', 30);
dec.getRange('A4').values = [['Las decisiones de negocio siguen pendientes hasta que tengan acuerdo, responsable y fecha. Las verificaciones técnicas se registran como evidencia, no sustituyen la aprobación.']];
const decisionLast = addTable(dec, ['ID', 'Tema', 'Decisión requerida', 'Situación / límite', 'Áreas afectadas', 'Responsable sugerido', 'Prioridad', 'Fuentes', 'Estado', 'Decisión acordada', 'Responsable asignado', 'Fecha acuerdo', 'Coordina', 'Resolver antes de etapa', 'Acción anticipada', 'Alcance del acuerdo', 'Verificación'], decisions, 6, [12,27,65,65,32,37,14,18,18,65,28,18,16,20,64,66,20], 'HercasDecisiones');
dec.freezePanes.freezeRows(6); dec.freezePanes.freezeColumns(2);
dec.getRange(`I7:L${decisionLast}`).format.fill = amber;
dec.getRange(`I7:I${decisionLast}`).dataValidation = { rule: { type: 'list', values: ['Pendiente', 'En revisión', 'Acordada', 'Descartada'] } };
dec.getRange(`L7:L${decisionLast}`).setNumberFormat('dd/mm/yyyy');
for (let r = 7; r <= decisionLast; r++) dec.getRange(`A${r}:Q${r}`).format.rowHeight = 58;

// Evidencia actualizada; evita que los textos de septiembre contradigan los controles ya efectuados.
init(evidence, 'Fuentes y evidencia', 'D', 45);
const notes = [
  ['Corte y propósito', '18/09/2026. Libro corregido para separar operación, detalle, decisiones y evidencia. No marca requisitos como cerrados por la existencia de código o tablas.'],
  ['Estado remoto verificado', 'Supabase de desarrollo saludable: cinco migraciones aplicadas, 18 tablas funcionales con RLS, registro público desactivado y confirmación por correo requerida.'],
  ['Pruebas ejecutadas', '48 pruebas Python/FastAPI y 35 pruebas PostgreSQL/PGlite aprobadas. La lectura anónima de perfiles, empresas y productos devolvió 401.'],
  ['Bloqueos de etapa 0', 'Activar al primer administrador y ejecutar la prueba de sesión/RLS con dos empresas. La protección contra contraseñas filtradas está desactivada en el asesor de seguridad.'],
  ['Límite de evidencia', 'La verificación técnica no sustituye la validación del negocio, la aceptación de flujos reales ni decisiones de precio, disponibilidad, CRM y retención.'],
  ['Regla de responsables', 'Tú ejecutas Supabase, frontend y aceptación. Anderson ejecuta FastAPI, reglas Python, Odoo, integraciones externas y trabajadores. Máximo dos operaciones activas: una por persona.']
];
addTable(evidence, ['Criterio', 'Aplicación'], notes, 5, [32,140], 'HercasNotas');
evidence.getRange('A13').values = [['Fuentes consultadas']];
evidence.getRange('A13:D13').format = { fill: dark, font: { color: '#FFFFFF', bold: true }, rowHeight: 24 };
const sourceLast = addTable(evidence, ['Fuente', 'Documento / componente', 'Localizador de evidencia', 'Alcance de la evidencia'], sources, 15, [12,34,82,98], 'HercasFuentes');
evidence.freezePanes.freezeRows(5);
for (let r = 6; r <= 10; r++) evidence.getRange(`A${r}:B${r}`).format.rowHeight = 48;
for (let r = 16; r <= sourceLast; r++) evidence.getRange(`A${r}:D${r}`).format.rowHeight = 58;

// Resumen: métricas accionables, sin presentar el estado técnico como porcentaje de avance.
init(summary, 'Hercas — levantamiento de requerimientos', 'L', 36);
summary.getRange('A4').values = [['Vista ejecutiva. El Backlog operativo contiene responsables y etapas; el detalle, historias y criterios están separados para que la tabla sea legible.']];
const cards = [
  ['A6:C6', 'A7:C8', 'REQUISITOS', '=COUNTA(\'Backlog operativo\'!$A$7:$A$1000)'],
  ['D6:F6', 'D7:F8', 'DECISIONES ABIERTAS', '=COUNTIFS(Decisiones!$I$7:$I$1000,"Pendiente")+COUNTIFS(Decisiones!$I$7:$I$1000,"En revisión")'],
  ['G6:I6', 'G7:I8', 'BLOQUEOS ETAPA 0', 2],
  ['J6:L6', 'J7:L8', 'RLS EN TABLAS FUNCIONALES', 18]
];
for (const [head, value, label, formula] of cards) {
  summary.mergeCells(head); summary.mergeCells(value); summary.getRange(head).values = [[label]]; summary.getRange(value).formulas = [[typeof formula === 'string' && formula.startsWith('=') ? formula : `=${formula}`]];
  summary.getRange(head).format = { fill: pale, font: { color: '#59636B', bold: true }, horizontalAlignment: 'center', rowHeight: 22 };
  summary.getRange(value).format = { font: { name: 'Arial', size: 16, color: dark, bold: true }, horizontalAlignment: 'center', verticalAlignment: 'center', borders: { preset: 'outside', style: 'thin', color: '#D9E0E6' } };
}
summary.getRange('A11').values = [['Distribución por frente']];
summary.getRange('A11:F11').format = { fill: green, font: { color: '#FFFFFF', bold: true }, rowHeight: 24 };
const areaRows = ['Backend', 'Frontend', 'Integraciones', 'Servicios'].map(area => [area, null, null, null]);
addTable(summary, ['Área', 'Requisitos', 'En etapa 0', 'Estado técnico “Por definir”'], areaRows, 13, [24,22,22,35], 'HercasResumenAreas', false);
for (let r = 14; r <= 17; r++) {
  summary.getRange(`B${r}`).formulas = [[`=COUNTIFS('Backlog operativo'!$B$7:$B$1000,A${r})`]];
  summary.getRange(`C${r}`).formulas = [[`=COUNTIFS('Backlog operativo'!$B$7:$B$1000,A${r},'Backlog operativo'!$F$7:$F$1000,0)`]];
  summary.getRange(`D${r}`).formulas = [[`=COUNTIFS('Backlog operativo'!$B$7:$B$1000,A${r},'Backlog operativo'!$J$7:$J$1000,"Por definir")`]];
}
summary.getRange('A20').values = [['Qué se corrigió']];
summary.getRange('A20:L20').format = { fill: green, font: { color: '#FFFFFF', bold: true }, rowHeight: 24 };
const corrected = [
  ['Operación diaria', 'El Backlog operativo concentra ID, dueño, etapas, dependencias, estado y siguiente paso.'],
  ['Trazabilidad', 'El detalle conserva alcance, historia de usuario, aceptación y fuentes por requisito.'],
  ['Decisiones', 'La matriz incluye responsable de coordinación, etapa límite, acción anticipada y verificación.'],
  ['Evidencia vigente', 'Se actualizaron los controles de Supabase y los bloqueos reales de la etapa 0.'],
  ['Control de avance', 'Los requisitos permanecen pendientes hasta tener evidencia, revisión cruzada y validación del negocio.']
];
addTable(summary, ['Aspecto', 'Resultado'], corrected, 22, [28,110], 'HercasCorrecciones');
summary.getRange('A22:B26').format.wrapText = true;
for (let r = 23; r <= 27; r++) summary.getRange(`A${r}:B${r}`).format.rowHeight = 36;
summary.getRange('A30').values = [['Siguiente paso: activar el primer administrador, probar sesión/RLS con dos empresas y cerrar las decisiones de etapa 0 antes de iniciar implementación funcional.']];
summary.getRange('A30:L31').format = { fill: amber, wrapText: true, verticalAlignment: 'center', font: { bold: true, color: dark } };
summary.mergeCells('A30:L31');

wb.recalculate();
if (summary.getRange('A7').values[0][0] !== 83) throw new Error(`El resumen no recalculó los 83 requisitos: ${summary.getRange('A7').values[0][0]}`);
const formulaErrors = await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30}});
if (/"kind":"match"/.test(formulaErrors.ndjson)) throw new Error(formulaErrors.ndjson);
await (await SpreadsheetFile.exportXlsx(wb)).save(output);
for (const [sheetName, range, name] of [['Resumen','A2:L31','requerimientos-corregido-resumen'], ['Backlog operativo','A2:O12','requerimientos-corregido-backlog'], ['Detalle de requisitos','A2:J10','requerimientos-corregido-detalle'], ['Decisiones','A2:Q10','requerimientos-corregido-decisiones']]) {
  await fs.writeFile(`${dir}/${name}.png`, new Uint8Array(await (await wb.render({sheetName, range, scale: 1})).arrayBuffer()));
}
console.log(JSON.stringify({output, requirements: requirements.length, decisions: decisions.length, details: detailRows.length, formulaErrors: 0}));
