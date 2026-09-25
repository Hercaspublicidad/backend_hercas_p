import fs from 'node:fs/promises';
import {Workbook,SpreadsheetFile} from '@oai/artifact-tool';
const out='D:/api_0doo/outputs/catalogo-20260917';
const data=JSON.parse(await fs.readFile(`${out}/catalogo-auditado.json`,'utf8'));
const w=Workbook.create();
const summary=w.worksheets.add('Resumen'), catalog=w.worksheets.add('Catalogo'), assets=w.worksheets.add('Vallas'), review=w.worksheets.add('Revision');
const navy='#23374D', amber='#FFF0CF';
function setup(s,title,cols,rows){
 s.showGridLines=false;
 const r=s.getRangeByIndexes(0,0,rows,cols);r.format.font={name:'Arial',size:10,color:'#202B35'};r.format.rowHeight=25;r.format.verticalAlignment='center';
 s.getRange('A2').values=[[title]];s.getRange('A2').format.font={name:'Arial',size:15,bold:true};s.getRange('A2').format.rowHeight=31;
}
function table(s,row,headers,values,name,widths){
 const all=[headers,...values], r=s.getRangeByIndexes(row-1,0,all.length,headers.length);r.values=all;
 s.tables.add(r.address,true,name);
 const h=s.getRangeByIndexes(row-1,0,1,headers.length);h.format.fill=navy;h.format.font={bold:true,color:'#FFFFFF'};h.format.wrapText=true;h.format.rowHeight=40;
 for(let i=0;i<widths.length;i++)s.getRangeByIndexes(row-1,i,all.length,1).format.columnWidth=widths[i];
 s.freezePanes.freezeRows(row);
}
setup(catalog,'Catálogo y nombres comerciales propuestos',22,212);
catalog.getRange('A3').values=[['206 referencias. Los nombres comerciales y agrupaciones se proponen para revisión; ninguna tarifa se publica con este libro.']];
const products=[...data.products].sort((a,b)=>a.group.localeCompare(b.group,'es')||a.commercial_name.localeCompare(b.commercial_name,'es'));
table(catalog,5,['ID catálogo','Nombre comercial propuesto','Grupo propuesto','Familia','Tipo de registro','Nombre original Odoo','Referencia existente','ID externo Odoo','Atributos','Ventas con precio útil','Mediana histórica neta','Mínimo histórico neto','Máximo histórico neto','Estado del precio','Revisión necesaria','Fuente','Fila fuente','Grupo anterior','Origen','ID numérico Odoo','Verificación ID numérico','UUID catálogo'],
 products.map(p=>[p.id_catalog,p.commercial_name,p.group,p.family,p.kind,p.name_original,p.reference,p.external_id,p.attributes,p.useful_price_lines,p.history_median,p.history_min,p.history_max,p.price_status,p.review,p.source,p.row,p.old_group,p.origin,p.odoo_numeric_id,p.numeric_id_status,p.uuid]),
 'CatalogoAuditado',[21,85,31,30,25,88,21,55,13,19,23,23,23,43,65,67,13,28,24,20,42,43]);
catalog.getRange('B6:H211').format.rowHeight=43;
catalog.getRange('B6:F211').format.wrapText=true;
catalog.getRange('K6:M211').setNumberFormat('#,##0.00');
catalog.getRange('I6:J211').setNumberFormat('#,##0');
catalog.getRange('N6:O211').format.wrapText=true;
catalog.getRange('N6:O211').format.fill=amber;

setup(assets,'Conciliación de ubicaciones de vallas',12,119);
assets.getRange('A3').values=[['113 códigos de referencia; no equivalen a 113 ubicaciones activas. Control semanal del 30/08 al 05/09/2026.']];
table(assets,5,['ID activo','Código existente','ID producto','Cruce de fuentes','Estado semanal histórico','Nombre maestro','Ubicación semanal','Importe columna L','Importe columna V','Diferencia L/V','Disponibilidad actual','Fila semanal'],
 data.assets.map(a=>[a.asset_id,a.code,a.product_id,a.match,a.historical_state,a.master_name,a.weekly_location,a.price_l,a.price_v,a.price_conflict?'Revisar':'',a.live_availability,a.source_row]),
 'ConciliacionVallas',[23,20,22,25,29,90,90,22,22,23,27,18]);
assets.getRange('E6:G118').format.wrapText=true;assets.getRange('A6:L118').format.rowHeight=43;
assets.getRange('H6:I118').setNumberFormat('#,##0');
assets.getRange('D6:D118').conditionalFormats.add('containsText',{text:'Solo',format:{fill:amber}});
assets.getRange('J6:K118').format.fill=amber;

setup(summary,'Hercas · Revisión del catálogo',4,43);
summary.getRange('A4:C4').values=[['Control','Cantidad','Lectura correcta']];
summary.getRange('A5:C12').values=[
 ['Referencias únicas',null,'Maestro y configuración de Odoo, sin duplicados de ID.'],
 ['Referencias del maestro',205,'El consolidado anterior conserva estos mismos IDs y nombres.'],
 ['Referencia recuperada',1,'Souvenirs: seis atributos y cuatro listas de materiales.'],
 ['Candidatas comerciales',null,'Incluye ubicaciones y servicios; requieren validación para publicación.'],
 ['Registros internos',null,'MANUAL y recarga de tarjeta Cívica, separados del catálogo público.'],
 ['Referencias con precio histórico útil',null,'Historia de pedidos de venta; no son tarifas vigentes.'],
 ['Precios cargados en el maestro',0,'Las 205 celdas de precio de venta están vacías.'],
 ['Códigos de valla sin cruce',29,'20 solo en semanal y 9 solo en maestro.']];
summary.getRange('B5').formulas=[['=COUNTA(Catalogo!A6:A211)']];
summary.getRange('B8').formulas=[['=B5-B9']];
summary.getRange('B9').formulas=[['=COUNTIFS(Catalogo!C6:C211,"Registros internos")']];
summary.getRange('B10').formulas=[['=COUNTIFS(Catalogo!J6:J211,">0")']];
summary.getRange('A15:C15').values=[['Grupo propuesto','Referencias','Serie comercial propuesta']];
const series={'Alquiler y pauta exterior':'Panorama','Estructuras publicitarias':'Forma','Aplicaciones de transporte UT':'Trayecto','Servicios técnicos':'Servicio','Impresión en lona':'Impacto','Avisos en sustrato':'Presencia','Señalización':'Guía','Vinilos y corte':'Adhiere','Tecnología LED':'Luz','Impresos litográficos':'Trazo','Promocionales':'Recuerdo','Registros internos':'Interno'};
Object.entries(series).forEach(([group,brand],i)=>{
 const row=i+16;summary.getRange(`A${row}:C${row}`).values=[[group,null,`Hercas ${brand}`]];
 summary.getRange(`B${row}`).formulas=[[`=COUNTIFS(Catalogo!$C$6:$C$211,A${row})`]];
});
summary.getRange('A29:C29').values=[['Total',null,'Las agrupaciones no eliminan referencias técnicas de Odoo.']];
summary.getRange('B29').formulas=[['=SUM(B16:B27)']];
summary.getRange('A32').values=[['Correcciones principales']];
summary.getRange('A33:C38').values=[
 ['Vallas fabricadas',28,'Reclasificadas por estructura, no por la palabra lona o vinilo.'],
 ['Ubicaciones y paquetes',94,'93 ubicaciones y 1 paquete. El paquete no es un activo físico.'],
 ['Precios semanales distintos',7,'Comparar columnas L y V antes de elegir una tarifa.'],
 ['Error en precio semanal',1,'PAA-005B: L9 contiene un error de búsqueda, no un precio de 42.'],
 ['Materiales internos',344,'Costos y proveedores permanecen fuera del catálogo comercial.'],
 ['Líneas MANUAL',581,'146 en pedidos de venta; requieren revisión por descripción.']];
summary.getRange('A4:A38').format.columnWidth=37;summary.getRange('B4:B38').format.columnWidth=17;summary.getRange('C4:C38').format.columnWidth=92;
summary.getRange('C5:C38').format.wrapText=true;summary.getRange('A5:C38').format.rowHeight=34;
for(const range of ['A4:C4','A15:C15']){summary.getRange(range).format.fill=navy;summary.getRange(range).format.font={bold:true,color:'#FFFFFF'};}
summary.getRange('A29:C29').format.font={bold:true};summary.tabColor=navy;

setup(review,'Hallazgos y decisiones del catálogo',4,35);
const findings=[
 ['Conservación de IDs','205 de 205 IDs y nombres coinciden con el consolidado anterior.','Conservar ID externo y referencia; HRC-P es un alias estable nuevo.','Maestro: Sheet1!E2:H206; consolidado: Catalogo!A4:D208'],
 ['Agrupación de estructuras','28 VALLA CERCHA estaban en Lonas y textiles o Impresión y vinilos.','Agrupar por estructura; material, soporte y acabado se conservan como configuración.','Maestro: Sheet1!H10:J37; consolidado: Catalogo!C12:H39'],
 ['Souvenirs omitido','ID 26279; seis atributos y cuatro listas de materiales.','Incluir como candidato; falta validación de alta en el maestro.','2.Variantes: Sheet1!E5035:J5035; 5.Lista de materiales'],
 ['Registros internos','MANUAL y RECARGA TARJETA CIVICA no definen un producto público estandarizado.','MANUAL permanece como flujo de excepción; confirmar tratamiento contable/comercial de recarga.','Maestro: Sheet1!H72:I74'],
 ['Plantillas y opciones','192 plantillas y 7.488 filas de atributos/valores; no 7.488 SKU.','Preservar plantillas y modelar opciones por producto; no multiplicar combinaciones automáticamente.','2.Variantes: Sheet1!A1:J7504'],
 ['Vallas sin correspondencia','84 códigos cruzan; 20 solo semanal y 9 solo maestro.','Revisar altas, retiros y alias; no publicar disponibilidad a partir del corte pasado.','Maestro y Disponible Semana: hoja Increm 2026 -no todas la va (2)'],
 ['Tarifas de vallas','7 diferencias L/V y un error en L9. Hay importes cero en alternativas.','Administrador de precios elige versión y vigencia; cero no significa gratuito.','Disponible Semana: L7/V7, L9, L52/V52, L62/V62, L100:V103'],
 ['Precios del maestro','205 precios y costos del encabezado vacíos.','No fabricar tarifas desde costos, medianas ni precios de proveedores.','1.Productos cotizables: Sheet1!B2:C206'],
 ['Historia de venta','5.151 líneas reales; filas de descripciones relacionales excluidas. Corte 15/04–03/09/2026.','Solo Pedido de venta y precio neto mayor a 1; importes no comparables sin configuración y unidad.','Historial de líneas: Sheet1!A1:O8474'],
 ['Moneda y unidad','Historial no exporta moneda ni unidad por línea. El maestro usa Unidades.','Confirmar COP y unidad comercial; no convertir automáticamente a mes o m².','Maestro columna K; historial encabezados A1:O1'],
 ['Pantalla LED','Pantalla LED y estructura LED son dos referencias diferentes.','Definir venta de equipo, alquiler o pauta. No equivalen por sí solas al circuito programático.','Maestro: Sheet1!H70:H73'],
 ['Aplicaciones UT','Arcos y dominación/arco, contrahuellas y dominación/contrahuellas tienen IDs diferentes.','Mantenerlos separados hasta validar alcance contractual; semejanza no prueba duplicado.','Maestro: Sheet1!E77:J97'],
 ['Historial no mapeado','Una línea RVN-501 difiere en el nombre; Anticipo es un concepto financiero.','Conciliar RVN-501 por código; no crear un producto por cada descripción histórica.','Historial; detalle de procedencia en catalogo-auditado.json'],
 ['Preparación del backend','La base SQL tiene catálogo y precios simples, pero aún no atributos, configuraciones y reglas versionadas.','Ampliar el modelo antes de automatizar todos los productos configurables.','Base del backend Python/Supabase revisada en esta tarea'],
 ['Alcance de la revisión','65 libros inventariados: 18 xlsx y 47 xls. Contenido clave releído desde originales.','No se recalcularon los cotizadores heredados ni se ejecutó código Python incluido en celdas.','Archivos originales conservados; huellas SHA-256 en catalogo-auditado.json'],
 ['Estado de la entrega','IDs y nombres asignados en este catálogo de revisión. Sin escrituras en Odoo o Supabase.','Revisar nombres y excepciones antes de publicar productos o precios.','Catálogo de esta entrega']];
table(review,5,['Tema','Evidencia','Tratamiento propuesto','Fuente'],findings,'RevisionCatalogo',[29,85,100,95]);
review.getRange('A6:D21').format.wrapText=true;review.getRange('A6:D21').format.rowHeight=67;
w.recalculate();
const inspect=await w.inspect({kind:'table',range:'Resumen!A4:C12',include:'values,formulas',tableMaxRows:9,tableMaxCols:3,maxChars:2800});
console.log(inspect.ndjson);
const errors=await w.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:20},maxChars:1000});console.log(errors.ndjson);
for(const [sheet,range] of [['Resumen','A1:C38'],['Catalogo','A1:D10'],['Vallas','A1:E12'],['Revision','A1:C9']]){
 const image=await w.render({sheetName:sheet,range,scale:1,format:'png'});
 await fs.writeFile(`${out}/${sheet}.png`,new Uint8Array(await image.arrayBuffer()));
}
const x=await SpreadsheetFile.exportXlsx(w);await x.save(`${out}/Catalogo Hercas revisado.xlsx`);
console.log('Exported Catalogo Hercas revisado.xlsx');
