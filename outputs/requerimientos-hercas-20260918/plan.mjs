import fs from 'node:fs/promises';
import {SpreadsheetFile,FileBlob} from '@oai/artifact-tool';
import {groups,decisions} from './data.mjs';
const dir='D:/api_0doo/outputs/requerimientos-hercas-20260918';
const input=dir+'/Hercas - Levantamiento de requerimientos.xlsx';
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(input));
const all=Object.entries(groups).flatMap(([area,rs])=>rs.map(r=>({id:r[0],area,module:r[1],title:r[2],scope:r[3],observed:r[5],gap:r[6],complexity:r[7],deps:r[10],accept:r[12]})));
const phases=[
 [0,'Preparación y contratos','Inspeccionar Supabase real: migraciones, Auth, RLS, Storage y datos. Consolidar decisiones, accesos a proveedores y recorrido de aceptación.','Inspeccionar API y Odoo. Entregar contrato de sesión, errores, roles e IDs. Ejecutar pruebas existentes en entorno autorizado y registrar brechas.','Inventario técnico y contratos versionados. Decisiones D-003/005/014/016/019/020 resueltas en lo necesario para identidad y gobierno de datos. Proveedores futuros con responsable y fecha límite.','Acordar contrato de identidad y usuario activo. Nadie cambia simultáneamente el mismo archivo o migración.'],
 [1,'Identidad y entorno común','Auth/MFA, RLS, empresas, membresías y RPC de administración. Después conectar invitación/login, panel de usuarios y navegación privada.','FastAPI: sesión, aceptación, errores y autorización. Preparar entornos API, auditoría básica, perímetro, monitoreo y recuperación; tú ejecutas toda configuración Supabase.','Invitar, aceptar, entrar, revocar y volver a intentar. Dos empresas aisladas. Último administrador protegido. Backend y frontend usan la misma identidad real.','Primero contrato. Anderson implementa API mientras tú haces esquema/RPC; después conectas UI y Anderson prepara pruebas negativas.'],
 [2,'Archivos y trabajos comunes','Configurar Storage, políticas, tipos y tamaños de archivo. Probar carga/descarga privada con dos identidades. Entregar contrato de archivo al frontend.','Implementar cola/trabajador persistente y estados de trabajo. Validar contenido, límites y recuperación de tareas. Conectar referencias Storage sin administrar Supabase.','Archivo privado inaccesible a otro cliente. Job sobrevive reinicio, no duplica trabajo y permite consultar fallo. Cuotas y registro de actividad comprobados.','No elegir un proveedor de colas por suposición. Si se usa Supabase, su configuración y esquema los haces tú; Anderson implementa el consumidor.'],
 [3,'Catálogo y web de consulta','Conciliar IDs y catálogo aprobado. Tú ejecutas importación a Supabase. Conectar portafolio, filtros, fichas y mapa con visibilidad verificada.','Odoo de lectura, mapeos y sincronización. Entregar payload de importación validado y APIs de catálogo. Distinguir ERP caído de catálogo vacío.','Referencias/activos/paquetes conciliados. Fotos y fichas corresponden al activo. Pines aproximados identificados. Sincronización no modifica tarifas web.','Anderson prepara extracción y validadores; tú apruebas/cargas datos y conectas pantallas. No ofrecer disponibilidad actual desde fuentes históricas.'],
 [4,'Tarifas oficiales','Versiones y restricciones SQL/RLS. Panel de revisar, editar, publicar y retirar precios. Ejecutar casos de permisos y vigencias.','Resolver precios y acuerdos en Python. API de edición/publicación que invoca contratos autorizados. Casos de cambio concurrente y precio inválido.','Tarifa vigente publicada se obtiene del servidor. Borrador no cotizable. Separación de rol precios/disponibilidad. UI y motor muestran la misma versión.','Orden interno: esquema/contrato; luego API y pantalla en paralelo; por último integración y pruebas.'],
 [5,'Cotizar, reservar y conciliar','RPC transaccionales de ocupación, instantáneas y restricciones. Conectar calendario, cotización multivalla, impresión y reapertura. Validar dos sesiones reales.','Cálculo, guardado/emisión, ciclo comercial y permisos de descuento. Expiración y conciliación Odoo. Migrar piloto con el contrato de importación que tú ejecutas.','Crear, emitir, consultar, reservar, reprogramar y cancelar. Sin doble reserva ni duplicado ERP. Cambio de tarifa controlado. Documento imprimible coincide. Migración conciliada.','Es una entrega conjunta: calendario y cotización se necesitan. No cerrar una mitad dejando Odoo, soporte, concurrencia o emisión para después.'],
 [6,'Fabricación y renders','Esquema configurable y solicitudes/resultados privados. Formularios por familia y seguimiento/revisión de renders con versiones.','Motor de reglas de fabricación y proveedor de renders. Trabajos, límites, cancelación y errores. Mantener aprobación visual separada de contratación.','Cotización configurable reproducible. Render ligado a versión, visible solo al cliente autorizado. Revisión no cambia precios ni reserva inventario.','Proveedor, modalidad y reglas aprobados antes de desarrollar. Los trabajos reutilizan infraestructura de etapa 2.'],
 [7,'Captación y CRM','Tablas/políticas de solicitudes y consentimiento. Formulario conectado al backend y respaldo WhatsApp. Validar recepción frente a alta CRM.','Recepción y validación de interesados, adaptador CRM, reintentos y conciliación de resultados inciertos.','Solicitud llega al destino CRM acordado una sola vez. Caída de Odoo conserva pendiente. No modifica contactos por solo coincidir el correo.','Cerrar formulario, API y CRM en la misma etapa; un mensaje preparado en WhatsApp no se marca como lead registrado.'],
 [8,'Pagos y reportes','Esquema/RLS para pagos y reportes, archivos privados. Checkout, seguimiento y tableros/exportaciones propios. Validación por empresa.','Pasarela, eventos verificados, conciliación y consultas/reportes. Exportaciones asíncronas. Probar duplicados y eventos fuera de orden.','Pago verificado y conciliado según contrato. Exportación conserva alcance. Otro cliente no consulta ni descarga. Fallo ERP no borra pago confirmado.','Primero contratos. Anderson prepara APIs y fixtures mientras tú haces esquema. Una sola operación activa por persona; pagos y reportes se atienden en orden dentro del paquete.'],
 [9,'Contenido, sitio y redes','Esquema editorial/RLS, CMS, blog, calendario de aprobación y páginas públicas. Casos reales, avisos legales y caché/SEO de contenido.','Backend editorial, publicación versionada, adaptador de primera red y programación persistente. Confirmación, cancelación y métricas por canal.','Editar, aprobar, publicar y retirar funciona. Cambiar contenido invalida aprobación. No duplica publicaciones. Sitio muestra contenido aprobado y no expone borradores.','Proveedor y cuentas disponibles antes de entrar. Completar primera red acordada y todos los formatos del alcance aprobado. Ampliaciones solo mediante decisión registrada.'],
 [10,'Circuito de pantallas','Modelo de capacidad compartida en Supabase, restricciones y RLS. Consola de circuito, piezas, programación y estados.','Reglas de capacidad en backend y adaptador del reproductor. Programación, desconexión, reintento, retiro y evidencia.','Piloto real autorizado: capacidad no se sobrevende; pieza inválida falla; recepción no se confunde con reproducción; cancelación/offline verificadas.','No depende de que el agente exista. Equipo/API, unidad vendida y acceso al piloto deben estar resueltos previamente.'],
 [11,'Agente de respuesta','Conversaciones/fuentes privadas en Supabase y políticas de acceso. Interfaz de chat bajo demanda y derivación humana.','Proveedor de modelo y herramientas tipadas. Consultas autorizadas, límites, fuentes y defensa ante instrucciones maliciosas. Integrar CRM ya validado si entra al corte.','Responde con fuentes vigentes; no revela datos ajenos ni inventa disponibilidad; deriva cuando no sabe. Inyección y acciones no autorizadas son rechazadas.','Usar módulos terminados. No conceder capacidades de cobrar/reservar/publicar por el mero hecho de conectar el modelo.'],
 [12,'Cierre integral y producción','Auditoría frontend, accesibilidad/SEO y recorrido completo. Verificar Supabase, restauración y evidencia de los 83 requisitos. Completar acuerdos y aceptación.','Pruebas de carga y fallo externo, alertas, recuperación API/trabajadores, secretos y despliegue. Corregir todos los fallos bloqueantes.','83 requisitos con evidencia y revisión aprobada; 20 decisiones acordadas; cero bloqueantes. Restauración probada y controles transversales verificados. Producción autorizada explícitamente.','La seguridad, pruebas y observabilidad se aplican desde etapa 1. Esta etapa consolida resultados y verifica el sistema completo, no los introduce por primera vez.']
];
const phaseIds={
 1:'BE-001 BE-002 BE-003 BE-004 BE-005 INT-002 INT-003 SER-001 FE-010 FE-011 FE-012',
 2:'SER-002 SER-005 INT-015',
 3:'BE-006 INT-001 INT-004 INT-005 INT-013 FE-002 FE-003 FE-004 FE-005',
 4:'BE-008 BE-009 BE-010 FE-015',
 5:'BE-007 BE-011 BE-012 BE-013 BE-014 BE-015 BE-016 BE-019 INT-006 INT-016 SER-003 SER-012 FE-013 FE-014 FE-016',
 6:'BE-018 BE-020 INT-011 FE-017 FE-018',
 7:'BE-028 INT-007 INT-014 FE-006',
 8:'BE-021 BE-022 INT-008 SER-004 FE-019 FE-020',
 9:'BE-023 BE-024 BE-025 INT-009 FE-001 FE-007 FE-008 FE-009 FE-021 SER-013',
 10:'BE-017 BE-026 INT-010 FE-022',
 11:'BE-027 INT-012 SER-008 FE-023',
 12:'FE-024 FE-025 SER-006 SER-007 SER-009 SER-010 SER-011 SER-014'
};
const phaseById={};for(const [p,list] of Object.entries(phaseIds))for(const id of list.split(' ')){if(phaseById[id])throw Error('Duplicate '+id);phaseById[id]=Number(p);}
if(all.length!==83||Object.keys(phaseById).length!==83||all.some(r=>!phaseById[r.id]))throw Error('Coverage mismatch');
const yours=new Set('BE-003 BE-005 BE-009 BE-011 BE-015 INT-002 INT-003 INT-004 INT-013 INT-014 INT-015 INT-016 SER-005 SER-011 SER-013 SER-014'.split(' '));
const startOverride={'SER-006':1,'SER-007':1,'SER-009':1,'SER-010':1,'SER-011':1,'SER-014':1,'FE-024':3,'FE-025':3,'SER-012':3};
const dphases=[3,3,0,4,0,10,3,6,8,8,3,9,11,0,1,0,3,5,0,0];
const dOwners=['Tú','Tú','Tú','Tú','Tú','Anderson','Tú','Anderson','Tú','Anderson','Tú','Anderson','Anderson','Tú','Tú','Tú','Anderson','Tú','Anderson','Tú'];
const subOwners={
 'BE-003':'Modelo de empresas/membresías y RLS.', 'BE-005':'Migración y RPC de administración de accesos.',
 'BE-009':'Versiones, vigencias y restricciones de precios.', 'BE-011':'Cabecera, líneas, instantáneas y restricciones SQL.',
 'BE-015':'RPC de ocupación/cancelación, bloqueos y exclusión temporal.',
 'INT-002':'Configuración Auth, claves públicas y RLS. Anderson adapta el cliente Python.',
 'INT-003':'Configuración Auth, enlaces, correo e invitaciones.',
 'INT-004':'Carga/importación y validación en Supabase. Anderson prepara extracción Odoo.',
 'INT-015':'Buckets, permisos y descarga temporal de Storage.',
 'INT-016':'Realtime si se elige; configuración y permisos. Si se usa sondeo, frontend y contrato con Anderson.',
 'SER-005':'Políticas de Storage y límites. Anderson valida/procesa archivos fuera de la BD.',
 'SER-010':'Tú: backup y restauración de Supabase. Anderson: API, trabajadores y coordinación de recuperación.'
};
const sheets={plan:wb.worksheets.add('Plan a dos'),as:wb.worksheets.add('Asignación 83'),gate:wb.worksheets.add('Cierre de etapas')};
const cover=wb.worksheets.getItem('Sales Pipeline');
cover.mergeCells('B38:P39');cover.getRange('B38').values=[['Plan de ejecución añadido: abrir Plan a dos, Asignación 83 y Cierre de etapas. Tú: Supabase + frontend. Anderson: API + integraciones externas.']];
cover.getRange('B38:P39').format={wrapText:true,fill:'#FFF2CC',font:{name:'Arial',size:11,bold:true,color:'#0B3D2E'},verticalAlignment:'center'};
const dark='#0B3D2E', pale='#F0F8F3', amber='#FFF2CC';
const col=n=>{let s='';for(;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s};
function init(s,title,last,rows){s.showGridLines=false;s.tabColor=dark;s.getRange(`A1:${last}${rows}`).format={font:{name:'Arial',size:10,color:'#243B32'},verticalAlignment:'top'};s.getRange('A2').values=[[title]];s.getRange(`A2:${last}2`).format={font:{name:'Arial',size:15,bold:true,color:dark},rowHeight:30};}
function table(s,heads,rows,row,widths,name){let last=row+rows.length,end=col(heads.length);s.getRange(`A${row}:${end}${last}`).values=[heads,...rows];const t=s.tables.add(`A${row}:${end}${last}`,true,name);t.style='TableStyleMedium4';widths.forEach((w,i)=>s.getRange(`${col(i+1)}1:${col(i+1)}${last}`).format.columnWidth=w);s.getRange(`A${row}:${end}${row}`).format={fill:dark,font:{color:'#FFFFFF',bold:true},wrapText:true,rowHeight:36,horizontalAlignment:'center',verticalAlignment:'center'};s.getRange(`A${row+1}:${end}${last}`).format.wrapText=true;rows.forEach((r,i)=>{let lines=Math.max(...r.map((v,j)=>Math.ceil(String(v??'').length/(widths[j]*.83))));s.getRange(`A${row+i+1}:${end}${row+i+1}`).format.rowHeight=Math.max(38,Math.min(245,lines*14+16));});s.freezePanes.freezeRows(row);s.freezePanes.freezeColumns(2);return last;}

const assignment=all.map(r=>{
 const owner=(r.area==='Frontend'||yours.has(r.id))?'Tú':'Anderson';
 const p=phaseById[r.id],start=startOverride[r.id]??p;
 const db=r.area==='Frontend'?'Tú conectas la interfaz con el contrato autorizado. No hay cambios de Supabase delegados a Anderson.':subOwners[r.id]??'Si requiere tablas, migraciones, RLS, RPC, Auth, Storage, Realtime o configuración Supabase, tú lo implementas. Anderson entrega contrato y casos de prueba.';
 const other=owner==='Tú'?'Anderson entrega/ajusta API, contratos y pruebas backend requeridas. Revisa con evidencias el trabajo cerrado.':'Tú implementas Supabase necesario, conectas frontend y ejecutas aceptación. Anderson no modifica el proyecto Supabase.';
 return[r.id,r.area,r.title,owner,start,p,db,other,r.deps,r.accept,'Por iniciar','Pendiente',null,null,null,null];
});
init(sheets.as,'Asignación completa — 83 requisitos, un responsable de cierre por ID','P',100);
sheets.as.getRange('A4').values=[['Todo Supabase es tuyo, incluso en requisitos cuyo responsable de cierre es Anderson. Inicio y cierre son etapas, no días.']];
const al=table(sheets.as,['ID','Área','Requerimiento','Responsable de cierre','Etapa inicio','Etapa cierre','Tu parte: Supabase / frontend','Colaboración del otro frente','Dependencias originales','Aceptación del requisito','Estado de ejecución','Revisión del otro','Evidencia / enlace','Fecha cierre','Bloqueo / pendiente','Cierre verificable'],assignment,6,[13,18,41,22,16,16,85,76,33,90,22,23,52,20,56,22],'HercasAsignacion');
sheets.as.getRange(`K7:O${al}`).format.fill=amber;
sheets.as.getRange(`K7:K${al}`).dataValidation={rule:{type:'list',values:['Por iniciar','En curso','En revisión','Bloqueado','Cerrado']}};
sheets.as.getRange(`L7:L${al}`).dataValidation={rule:{type:'list',values:['Pendiente','Aprobada','Requiere ajustes']}};
sheets.as.getRange(`N7:N${al}`).setNumberFormat('dd/mm/yyyy');
for(let r=7;r<=al;r++)sheets.as.getRange(`P${r}`).formulas=[[`=IF(AND(K${r}="Cerrado",L${r}="Aprobada",M${r}<>"",ISNUMBER(N${r}),O${r}=""),"Sí","No")`]];
sheets.as.getRange(`P7:P${al}`).conditionalFormats.addCustom('AND($K7="Cerrado",$P7="No")',{fill:'#FCE4D6'});

// Se conservan las decisiones originales y se añaden responsables de coordinación.
const ds=wb.worksheets.getItem('Decisiones');
ds.getRange('M6:Q6').values=[['Coordina la decisión','Resolver antes de etapa','Acción anticipada','Alcance del acuerdo','Verificación del acuerdo']];
ds.getRange('M6:Q6').format={fill:dark,font:{color:'#FFFFFF',bold:true},wrapText:true};
decisions.forEach((d,i)=>{let r=i+7;ds.getRange(`M${r}:Q${r}`).values=[[dOwners[i],dphases[i],i===5||i===7||i===9||i===11||i===12?'Solicitar acceso, opciones y condiciones desde etapa 0. Resolver antes de etapa indicada.':'Recoger fuente/criterio desde etapa 0 y confirmar con el dueño de negocio.',i===2||i===4||i===13||i===19?'Cerrar reglas comunes en etapa 0 y verificar detalles de cada módulo antes de su etapa.':'Registrar alternativa elegida y límites. El coordinador no reemplaza al aprobador del negocio.',null]];ds.getRange(`Q${r}`).formulas=[[`=IF(AND(I${r}="Acordada",J${r}<>"",K${r}<>"",ISNUMBER(L${r})),"Sí","No")`]];});
for(const[c,w]of [['M',25],['N',22],['O',68],['P',70],['Q',25]])ds.getRange(`${c}6:${c}26`).format.columnWidth=w;
ds.getRange('M7:Q26').format.wrapText=true;
ds.getRange('N7:N26').setNumberFormat('0');
// El plan no declara aprobadas decisiones de negocio todavía abiertas.

init(sheets.plan,'Hercas — dos operaciones en paralelo','H',50);
sheets.plan.getRange('A4').values=[['Tú: Supabase completo, frontend y aceptación. Anderson: FastAPI, Python, Odoo, integraciones externas y trabajadores.']];
const prows=phases.map(p=>[p[0],p[1],p[2],p[3],p[4],p[5],Object.entries(phaseById).filter(([,v])=>v===p[0]).map(([id])=>id).join(', '),null]);
const pl=table(sheets.plan,['Etapa','Entrega','Operación 1 — Tú','Operación 2 — Anderson','Criterio para cerrar la etapa','Cómo trabajar sin esperas','Requisitos que cierran aquí','Cantidad'],prows,6,[12,32,97,97,104,85,76,14],'HercasPlanDos');
for(let r=7;r<=pl;r++)sheets.plan.getRange(`H${r}`).formulas=[[`=COUNTIFS('Asignación 83'!$F$7:$F$89,A${r})`]];
const rules=[
 ['Comenzar ahora','Tú verificas Supabase remoto y preparas el contrato de identidad. Anderson verifica FastAPI/Odoo y prueba la API existente. Solo lectura durante el diagnóstico; implementación después de acordar contratos.'],
 ['Límite de trabajo','Máximo dos operaciones activas: una por persona. Dentro del paquete de etapa, atender un requisito a la vez por persona. Bloqueado y en revisión siguen contando como trabajo abierto.'],
 ['Regla de avance','No comenzar la siguiente etapa hasta cerrar todos los requisitos asignados al corte, acordar decisiones de entrada y superar aceptación conjunta. Ningún fallo se oculta cambiando el estado a cerrado.'],
 ['Responsable y colaboración','Un responsable de cierre por requisito evita duplicaciones. No significa que haga todas sus capas. Todo cambio Supabase lo ejecutas tú; Anderson nunca lo asume por ser dueño del backend.'],
 ['Orden dentro de cada etapa','1. Decisión y contrato. 2. Tú defines/aplicas esquema/RPC; Anderson implementa adaptadores contra ese contrato. 3. Tú conectas UI; Anderson hace pruebas backend, fallos y ajustes. 4. Prueba integrada y revisión cruzada.'],
 ['Si uno termina primero','Ayuda a probar, revisar, documentar o resolver el bloqueo de la otra operación de la misma etapa. No abrir otro módulo ni dejar una funcionalidad a medias.'],
 ['Control de carga','Tu frente reúne BD y UI. Anderson prepara OpenAPI, ejemplos, datos de prueba, validadores, scripts sin ejecución Supabase y automatización backend. Así aprovecha tu tiempo de migración y conexión de pantallas.'],
 ['Cambios de base de datos','Un solo autor/ejecutor de migraciones Supabase: tú. Revisar compatibilidad antes de aplicar. Anderson solicita el cambio mediante contrato y casos; no introduce SQL alternativo.'],
 ['Contratos y entornos','Usar la misma versión de OpenAPI, IDs, campos, errores y fixtures. Ramas/PR separados por operación. Mock sirve para desarrollar, nunca como evidencia de flujo terminado.'],
 ['Requisitos transversales','SER-006/007/009/010/011/014 y FE-024/025 se trabajan desde su etapa de inicio y se revisan en cada entrega. Cierran en etapa 12 porque abarcan todos los módulos. No se dejan para el final.'],
 ['Dependencias que forman pares','La matriz original contiene relaciones recíprocas, por ejemplo backend y adaptador de pagos. Se resuelven como un paquete de contrato, implementación paralela e integración en una misma etapa, no como dos bloqueos circulares.'],
 ['Hitos para dependencias transversales','Calidad: prueba del módulo en cada etapa. SEO: base en etapa 3, contenido en 9 y auditoría global en 12. Seguridad/auditoría/monitorización: base en 1 y cobertura ampliada en cada entrega.'],
 ['Proveedores externos','Desde etapa 0 solicitar cuentas, sandbox, documentación y decisiones para pagos, redes, pantallas, renders y agente. No ejecutar una etapa con requisitos de proveedor aún sin resolver.'],
 ['Cierre con evidencia','Aceptar exige interfaz real cuando corresponde, persistencia/permiso correctos, pruebas positivas y negativas, revisión del otro, enlace a evidencia y fecha. No se cierran requisitos por tener tablas o pantallas aisladas.'],
 ['Alcance completo','83 de 83 IDs asignados una sola vez. Las 20 decisiones tienen coordinador y etapa límite. No se excluyó requisito. Cambiar alcance requiere acuerdo explícito y actualizar la matriz.'],
 ['Duración','No hay horas disponibles, capacidad medida ni estimación validada. Las etapas no son semanas. Medir tiempo real de etapa 1 y desglosar cada paquete antes de fijar fechas.'],
 ['Fuente y corte','Base: Hercas - Levantamiento de requerimientos.xlsx, hoja Requerimientos, IDs BE/FE/INT/SER, y Decisiones D-001 a D-020. Estado original preservado; este plan no acredita implementación nueva.']
];
table(sheets.plan,['Regla','Aplicación'],rules,23,[32,155],'HercasReglasDos');
// Las reglas ocupan A:B; mantener las otras columnas del plan y envolver ambas zonas.
sheets.plan.getRange('A1:A41').format.columnWidth=32;sheets.plan.getRange('B1:B41').format.columnWidth=70;
sheets.plan.getRange('B24:B40').format.wrapText=true;
for(let r=24;r<=40;r++)sheets.plan.getRange(`A${r}:B${r}`).format.rowHeight=90;

init(sheets.gate,'Control de cierre — no avanzar con pendientes','M',30);
sheets.gate.getRange('A4').values=[['Las celdas amarillas requieren evidencia y validación real. Nada está cerrado por la creación de este plan.']];
const grows=phases.map(p=>[p[0],p[1],null,null,null,'Pendiente',null,null,'Pendiente',null,null,null,null]);
table(sheets.gate,['Etapa','Entrega','Requisitos previstos','Requisitos cerrados','Requisitos pendientes','Prueba integrada','Evidencia de etapa','Decisiones pendientes acumuladas','Controles transversales','Evidencia de controles','Bloqueos abiertos','Cierre de etapa','Avance permitido'],grows,6,[12,34,22,23,23,23,55,28,27,55,24,24,25],'HercasCierreDos');
sheets.gate.getRange('F7:G19').format.fill=amber;sheets.gate.getRange('I7:K19').format.fill=amber;
for(const c of ['F','I'])sheets.gate.getRange(`${c}7:${c}19`).dataValidation={rule:{type:'list',values:['Pendiente','Aprobada','Requiere ajustes']}};
sheets.gate.getRange('K7:K19').dataValidation={rule:{type:'whole',operator:'greaterThanOrEqual',formula1:0}};
for(let r=7;r<=19;r++){
 sheets.gate.getRange(`C${r}:E${r}`).formulas=[[`=COUNTIFS('Asignación 83'!$F$7:$F$89,A${r})`,`=COUNTIFS('Asignación 83'!$F$7:$F$89,A${r},'Asignación 83'!$P$7:$P$89,"Sí")`,`=C${r}-D${r}`]];
 sheets.gate.getRange(`H${r}`).formulas=[[`=COUNTIFS(Decisiones!$N$7:$N$26,"<="&A${r},Decisiones!$Q$7:$Q$26,"No")`]];
 sheets.gate.getRange(`L${r}`).formulas=[[`=IF(AND(E${r}=0,F${r}="Aprobada",G${r}<>"",H${r}=0,I${r}="Aprobada",J${r}<>"",ISNUMBER(K${r}),K${r}=0),"Cerrada","Pendiente")`]];
 sheets.gate.getRange(`M${r}`).formulas=[[r===7?`=IF(L${r}="Cerrada","Sí","No")`:`=IF(AND(L${r}="Cerrada",M${r-1}="Sí"),"Sí","No")`]];
}
sheets.gate.getRange('A22:B25').values=[['Control WIP','Valor'],['Tú: requisitos abiertos',null],['Anderson: requisitos abiertos',null],['Límite simultáneo',null]];
for(const [r,owner]of [[23,'Tú'],[24,'Anderson']])sheets.gate.getRange(`B${r}`).formulas=[[`=COUNTIFS('Asignación 83'!$D$7:$D$89,"${owner}",'Asignación 83'!$K$7:$K$89,"En curso")+COUNTIFS('Asignación 83'!$D$7:$D$89,"${owner}",'Asignación 83'!$K$7:$K$89,"En revisión")+COUNTIFS('Asignación 83'!$D$7:$D$89,"${owner}",'Asignación 83'!$K$7:$K$89,"Bloqueado")`]];
sheets.gate.getRange('B25').formulas=[['=IF(AND(B23<=1,B24<=1),"Dentro de 2 operaciones","Excede el límite")']];
sheets.gate.getRange('B25').conditionalFormats.add('containsText',{text:'Excede',format:{fill:'#FCE4D6'}});

wb.recalculate();
if(sheets.gate.getRange('M7').values[0][0]!=='No')throw Error('Initial stage gate unexpectedly open');
if(sheets.plan.getRange('H7:H19').values.flat().reduce((a,b)=>a+b,0)!==83)throw Error('Coverage count');
// Evidencia sola no cierra. Revisión, fecha y ausencia de pendientes son obligatorias.
sheets.as.getRange('K7').values=[['Cerrado']];sheets.as.getRange('M7').values=[['prueba temporal']];
if(sheets.as.getRange('P7').values[0][0]!=='No')throw Error('Incomplete requirement closed');
sheets.as.getRange('K7').values=[['Por iniciar']];sheets.as.getRange('M7').values=[[null]];
// Una segunda operación de la misma persona debe activar el límite.
const andRows=assignment.map((r,i)=>r[3]==='Anderson'?i+7:null).filter(Boolean).slice(0,2);
for(const r of andRows)sheets.as.getRange(`K${r}`).values=[['En curso']];
if(sheets.gate.getRange('B25').values[0][0]!=='Excede el límite')throw Error('WIP check failed');
for(const r of andRows)sheets.as.getRange(`K${r}`).values=[['Por iniciar']];
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:20},summary:'Plan formula errors'})).ndjson);
const output=dir+'/Hercas - Plan de trabajo Anderson y tu.xlsx';
await (await SpreadsheetFile.exportXlsx(wb)).save(output);
for(const [sheetName,range,file]of [['Plan a dos','A6:D9','plan-dos'],['Plan a dos','A23:B27','plan-reglas'],['Asignación 83','A6:H9','plan-asignacion'],['Cierre de etapas','A6:F10','plan-cierre'],['Decisiones','M6:Q9','plan-decisiones']])await fs.writeFile(dir+'/'+file+'.png',new Uint8Array(await(await wb.render({sheetName,range,scale:1.2})).arrayBuffer()));
console.log(JSON.stringify({output,requirements:assignment.length,owners:assignment.reduce((a,r)=>(a[r[3]]=(a[r[3]]||0)+1,a),{}),stages:phases.length,decisions:decisions.length,initialClosed:0}));
