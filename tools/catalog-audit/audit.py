"""Read-only audit of original Odoo exports. Never executes source formulas."""
from pathlib import Path
from collections import Counter, defaultdict
from statistics import median
from datetime import datetime
import hashlib, json, re, sys, unicodedata, uuid
import openpyxl
sys.path.insert(0, str(Path(__file__).parent / '.deps'))
import xlrd

ROOT=Path('D:/HERCAS/Cotizaciones productos')
OUT=Path('D:/api_0doo/outputs/catalogo-20260917')
OUT.mkdir(parents=True,exist_ok=True)
def norm(v):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFD',str(v or '')) if not unicodedata.combining(c)).upper().split())
def code(v): return re.sub(r'\s+','',norm(v))
def rows(name,sheet=None):
    w=openpyxl.load_workbook(ROOT/name,read_only=True,data_only=True)
    s=w[sheet] if sheet else w.active
    result=list(s.values);w.close();return result
def numeric(v): return isinstance(v,(int,float)) and not isinstance(v,bool)
def clean(v): return ' '.join(str(v or '').split())
def ident(x): return int(re.search(r'product_template_(\d+)',x).group(1))
def serial(v): return v.isoformat() if isinstance(v,datetime) else str(v)

master_name='1.Productos cotizables (product.template).xlsx'
variant_name='2.Variantes  de producto (product.template).xlsx'
history_name='Historial de líneas de cotización de los últimos 12 meses en odoo.xlsx'
master=rows(master_name)[1:]
previous=rows('outputs/base-cotizador-20260905/Base catalogo y precios cotizador Hercas.xlsx','Catalogo')[3:]
old={r[0]:r for r in previous if r[0]}
variants={}; current=None; attribute=None; configuration_rows=0
for rn,r in enumerate(rows(variant_name)[1:],2):
    if r[6] and r[5]:
        current=r[5]
        attribute=None
        assert current not in variants, ('Repeated template',current)
        variants[current]={'numeric_id':int(r[4]),'name':clean(r[6]),'row':rn,'attributes':defaultdict(set),'unit':r[9]}
    elif r[4] and not r[5]: current=None; attribute=None # section heading, not a template
    if current and r[7]: attribute=clean(r[7])
    if current and attribute and r[8]:
        variants[current]['attributes'][attribute].add(clean(r[8])); configuration_rows+=1

history=[]; parent={}; unknown=Counter()
refs={code(r[6]):norm(r[7]) for r in master if r[6]}
for rn,r in enumerate(rows(history_name)[1:],2):
    if r[1]: parent={'op':r[1],'date':r[0],'state':r[10]}
    if not r[2]: continue # relational-description rows are not sale lines
    key=norm(r[2]); prefix=re.match(r'^\[([^]]+)\]\s*(.*)$',key)
    if prefix and refs.get(code(prefix[1]))==norm(prefix[2]): key=norm(prefix[2])
    history.append({'row':rn,'product':clean(r[2]),'key':key,'quantity':r[5],
        'unit_price':r[6],'discount':r[7],'subtotal':r[8],**parent})
hist=defaultdict(list)
for h in history: hist[h['key']].append(h)
boms=defaultdict(set)
for r in rows('5.Lista de materiales (mrp.bom) (5).xlsx')[1:]:
    if r[3] and r[4]: boms[norm(r[4])].add(str(r[3]))

def classify(name,category):
    n=norm(name)
    if n=='MANUAL': return 'INT','Registros internos','Cotización manual','Registro interno','Uso interno'
    if n=='RECARGA TARJETA CIVICA': return 'INT','Registros internos','Recargas y gastos','Registro interno','Confirmar si es costo o servicio revendible'
    if n=='PAQUETE DE VALLAS': return 'OOH','Alquiler y pauta exterior','Paquetes de ubicaciones','Paquete','Definir activos y duración del paquete'
    if category=='Punto Publicitario': return 'OOH','Alquiler y pauta exterior','Ubicaciones de valla','Ubicación','Conciliar operación, unidad y tarifa'
    if n.startswith(('INSTALACION','DESINSTALACION','MANTENIMIENTO','SERVICIO VISITA')):
        family='Instalación' if n.startswith('INSTALACION') else 'Desinstalación' if n.startswith('DESINSTALACION') else 'Mantenimiento' if n.startswith('MANTENIMIENTO') else 'Visitas técnicas'
        return 'SER','Servicios técnicos',family,'Servicio','Validar alcance y cálculo'
    if n.startswith('UT '):
        family='Vehículos' if n.startswith('UT VEHICULOS') else 'Paneles y lonas UT' if n.startswith('UT PANELES') else 'Dominación de espacios' if n.startswith('UT DOMINACION') else 'Aplicaciones en estaciones'
        return 'UT','Aplicaciones de transporte UT',family,'Producto configurable','Uso contractual; no fusionar referencias similares'
    if n=='PANTALLA LED': return 'LED','Tecnología LED','Pantallas LED','Producto por definir','Confirmar equipo, alquiler o pauta; no asumir circuito digital'
    if n=='LITOGRAFIA': return 'LIT','Impresos litográficos','Litografía','Producto configurable','Definir formatos y tirajes'
    if n.startswith('SOUVENIRS'): return 'PRO','Promocionales','Souvenirs','Producto configurable','Falta en maestro; validar alta y opciones'
    if n.startswith(('SENAL ', 'SENALIZACION')): return 'SEN','Señalización','Señales y señalización','Producto configurable','Validar medidas, material y uso'
    if n.startswith('AVISO '): return 'AVI','Avisos en sustrato','Avisos sobre soporte','Producto configurable','Conservar material; no inferir iluminación'
    if n.startswith(('VALLA CERCHA','TROQUEL','BASTIDOR','PUBLIPOSTE','BACKING','ESTRUCTURA')):
        family='Vallas de cercha' if n.startswith('VALLA CERCHA') else 'Troqueles para valla' if n.startswith('TROQUEL') else 'Bastidores' if n.startswith('BASTIDOR') else 'Publipostes' if n.startswith('PUBLIPOSTE') else 'Backings' if n.startswith('BACKING') else 'Estructuras para LED'
        return 'EST','Estructuras publicitarias',family,'Producto configurable','Estructura pendiente de definición' if n.startswith('BACKING') else 'Conservar estructura, soporte y acabado'
    if n.startswith(('FOTOTELON','PASACALLE','PENDON')):
        family='Lona impresa' if n.startswith('FOTOTELON') else 'Pasacalles' if n.startswith('PASACALLE') else 'Pendones'
        return 'LON','Impresión en lona',family,'Producto configurable','Validar medidas y acabados'
    if n.startswith(('FOTOVINILO','VINILO')): return 'VIN','Vinilos y corte','Vinilos','Producto configurable','Validar material, impresión, corte e instalación'
    raise ValueError(('Unclassified',name,category))

series={'OOH':'Panorama','EST':'Forma','LON':'Impacto','VIN':'Adhiere','AVI':'Presencia','SEN':'Guía','UT':'Trayecto','LED':'Luz','LIT':'Trazo','SER':'Servicio','PRO':'Recuerdo','INT':'Interno'}
def commercial(name,line):
    n=clean(name)
    special={'MANUAL':'Cotización a medida pendiente de aprobación','RECARGA TARJETA CIVICA':'Recarga de tarjeta Cívica',
             'SOUVENIRS_UND':'Souvenirs personalizados','PANTALLA LED':'Pantalla LED: modalidad por definir','LITOGRAFIA':'Impresos litográficos',
             'SERVICIO VISITA_UND':'Visita técnica','BACKING/CON FOTOTELON (ESTRUCTURA POR DEFINIR PRODUCTO INTERMEDIO)':'Backing con lona impresa: estructura por definir'}
    if norm(n) in special: body=special[norm(n)]
    else:
        body=n.title().replace('_',' ').replace('/', ' · ')
        for a,b in [('Fototelón','lona impresa'),('Fototelon','lona impresa'),('Fotovinilo','vinilo impreso'),('Ut ','UT '),('Mdf','MDF'),('Led','LED'),('Mopt','MOPT'),('Inmantado','imantado'),('Acrilico','acrílico'),('Pendon','Pendón')]: body=body.replace(a,b)
        if line=='OOH':
            body=re.sub(r'\b([A-Z][a-z]{2})-(\d+[A-Za-z]?)',lambda m:m.group(0).upper(),body)
    return f'Hercas {series[line]} · {body}'

records=[]
for rn,r in enumerate(master,2):
    external=r[4]
    assert external and r[7]
    oid=ident(external)
    if external in variants: assert oid==variants[external]['numeric_id']
    records.append({'external_id':external,'odoo_numeric_id':oid,'name_original':clean(r[7]),'reference':clean(r[6]),
        'category_original':r[8],'unit_original':r[10],'tax_original':r[12],'active_source':r[11],
        'master_price':r[2],'master_cost':r[1],'source':master_name,'row':rn,'origin':'Maestro',
        'numeric_id_status':'Verificado en configuración' if external in variants else 'Derivado del ID externo; verificar en Odoo'})
for external,v in variants.items():
    if external not in {p['external_id'] for p in records}:
        records.append({'external_id':external,'odoo_numeric_id':v['numeric_id'],'name_original':v['name'],'reference':'',
            'category_original':None,'unit_original':v['unit'],'tax_original':None,'active_source':None,'master_price':None,'master_cost':None,
            'source':variant_name,'row':v['row'],'origin':'Solo configuración','numeric_id_status':'Verificado en configuración'})

for p in records:
    line,group,family,kind,review=classify(p['name_original'],p['category_original'])
    p.update({'id_catalog':'HRC-P-'+str(p['odoo_numeric_id']).zfill(6),'uuid':str(uuid.uuid5(uuid.NAMESPACE_URL,'https://hercas.net/catalog/product.template/'+p['external_id'])),
        'line_code':line,'group':group,'family':family,'kind':kind,'review':review,'commercial_name':commercial(p['name_original'],line),
        'old_group':old.get(p['external_id'],[None]*8)[7], 'approved_for_web':False,'current_sale_price':None})
    v=variants.get(p['external_id'],{})
    p['attributes']=len(v.get('attributes',{}));p['configuration_rows']=sum(map(len,v.get('attributes',{}).values()))
    p['bom_count']=len(boms[norm(p['name_original'])])
    h=hist[norm(p['name_original'])]
    good=[x for x in h if x['state']=='Pedido de venta' and numeric(x['unit_price']) and x['unit_price']>1
          and numeric(x['discount']) and 0<=x['discount']<=100 and x['unit_price']*(1-x['discount']/100)>1]
    net=[x['unit_price']*(1-x['discount']/100) for x in good]
    p.update({'history_lines':len(h),'sale_lines':sum(x['state']=='Pedido de venta' for x in h),'useful_price_lines':len(net),
        'history_min':min(net) if net else None,'history_median':median(net) if net else None,'history_max':max(net) if net else None,
        'last_sale':max((x['date'] for x in good if isinstance(x['date'],datetime)),default=None),
        'history_source_rows':','.join(str(x['row']) for x in good),
        'price_status':'Histórico variable; no tarifa vigente' if net else 'Sin referencia histórica útil',
        'history_match':'Nombre exacto normalizado; prefijo de referencia solo si coincide con maestro; historial sin ID'})

# Read both old-format sheets; only the explicit August/September cut is the comparison.
weekly_file=next(ROOT.glob('Disponible*.xls'))
w=xlrd.open_workbook(weekly_file)
s=w.sheet_by_name('Increm 2026 -no todas la va (2)')
weekly_header=s.row_values(1)
weekly=[];zone=''
for i in range(2,s.nrows):
    r=s.row_values(i)
    if r[0]:zone=clean(r[0])
    if not re.fullmatch(r'[A-Z]{2,4}-\d+[A-Z]?',code(r[1])):continue
    value=lambda j:s.cell_value(i,j) if s.cell_type(i,j)==xlrd.XL_CELL_NUMBER else None
    weekly.append({'code':code(r[1]),'zone':zone,'location':clean(r[2]),'measure':clean(r[3]),'orientation':clean(r[5]),
        'state':clean(r[6]),'price_h':value(7),'price_j':value(9),
        'price_l':value(11),'price_v':value(21),
        'raw_price_l':xlrd.error_text_from_code[r[11]] if s.cell_type(i,11)==xlrd.XL_CELL_ERROR else r[11],
        'row':i+1,'source':weekly_file.name,'sheet':s.name,
        'has_campaign_data':any(bool(r[j]) for j in [12,13,14,15] if j<len(r))})
by_code={a['code']:a for a in weekly};assert len(by_code)==len(weekly)
master_assets={code(p['reference']):p for p in records if p['kind']=='Ubicación'}
assert '' not in master_assets
assets=[]
for c in sorted(set(master_assets)|set(by_code)):
    p=master_assets.get(c);a=by_code.get(c)
    assets.append({'asset_id':'HRC-A-'+c,'code':c,'product_id':p['id_catalog'] if p else None,
        'master_name':p['name_original'] if p else None,'weekly_location':a['location'] if a else None,
        'match':'Maestro y semanal' if p and a else 'Solo maestro' if p else 'Solo semanal',
        'historical_state':a['state'] if a else None,'price_l':a['price_l'] if a else None,'price_v':a['price_v'] if a else None,
        'price_conflict':bool(a and a['price_l'] is not None and a['price_l']>0 and a['price_v'] is not None and a['price_l']!=a['price_v']),
        'live_availability':'No verificada','source_row':a['row'] if a else None})

names={norm(p['name_original']) for p in records}
unmapped=Counter(h['product'] for h in history if h['key'] not in names and not re.match(r'^\[?KIT',h['key']))
manual=[h for h in history if h['key']=='MANUAL']
# No automatic catalog creation from free-text historical lines.
manifest=[]
for f in sorted(ROOT.glob('*')):
    if f.suffix.lower() not in ('.xls','.xlsx'):continue
    if f.suffix.lower()=='.xls':
        b=xlrd.open_workbook(f); info=[{'sheet':x.name,'rows':x.nrows,'cols':x.ncols} for x in b.sheets()]
    else:
        b=openpyxl.load_workbook(f,read_only=True,data_only=True); info=[{'sheet':x.title,'rows':x.max_row,'cols':x.max_column} for x in b.worksheets];b.close()
    manifest.append({'file':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'sheets':info})

stats={'master_products':len(master),'union_products':len(records),'unique_ids':len({p['external_id'] for p in records}),
 'duplicate_normalized_names':{n:c for n,c in Counter(norm(p['name_original']) for p in records).items() if c>1},
 'master_categories':dict(Counter(r[8] for r in master)), 'master_price_populated':sum(r[2] is not None for r in master),
 'configured_templates':len(variants),'master_without_configuration':sum(p['external_id'] not in variants for p in records if p['origin']=='Maestro'),
 'configuration_options_rows':configuration_rows,
 'new_groups':dict(Counter(p['group'] for p in records)), 'types':dict(Counter(p['kind'] for p in records)),
 'original_vs_previous_ids_equal':{p['external_id'] for p in records if p['origin']=='Maestro'}==set(old),
 'same_ids_name_differences':sum(norm(p['name_original'])!=norm(old[p['external_id']][2]) for p in records if p['external_id'] in old),
 'history_actual_lines':len(history),'history_parent_orders':len({h['op'] for h in history}),
 'history_start':min(h['date'] for h in history if isinstance(h['date'],datetime)),
 'history_end':max(h['date'] for h in history if isinstance(h['date'],datetime)),
 'master_with_useful_history':sum(p['useful_price_lines']>0 for p in records if p['origin']=='Maestro'),
 'manual_lines':len(manual),'manual_sale_lines':sum(h['state']=='Pedido de venta' for h in manual),
 'weekly_codes':len(weekly),'master_asset_codes':len(master_assets),'union_asset_codes':len(assets),
 'asset_matches':dict(Counter(a['match'] for a in assets)),
 'weekly_title':s.cell_value(0,0),'weekly_headers':weekly_header,
 'weekly_states':dict(Counter(a['state'] for a in weekly)),
 'price_conflict_codes':[a['code'] for a in assets if a['price_conflict']],
 'source_books':len(manifest),'source_xls':sum(m['file'].endswith('.xls') for m in manifest)}
frontend=json.loads(Path('D:/HERCAS/cotizador-hercas/src/data/catalog.json').read_text(encoding='utf8'))
stats['frontend_references']=len(frontend['billboards'])
stats['frontend_ids_match_advertising_master']={x['odooId'] for x in frontend['billboards']}=={p['external_id'] for p in records if p['line_code']=='OOH'}
materials=rows('8A Producto Materiales (product.template).xlsx')[1:]
stats['internal_materials']=sum(bool(r[0]) for r in materials)
stats['materials_positive_cost']=sum(numeric(r[3]) and r[3]>0 for r in materials)
stats['weekly_price_errors']=[{'code':x['code'],'row':x['row'],'error':x['raw_price_l']} for x in weekly if isinstance(x['raw_price_l'],str) and x['raw_price_l'].startswith('#')]
stats['cercha_misgrouped_previously']=sum(norm(p['name_original']).startswith('VALLA CERCHA') and p['old_group'] in ('Lonas y textiles','Impresión y vinilos') for p in records)
payload={'as_of':'2026-09-17','stats':stats,'products':records,'assets':assets,'weekly':weekly,
 'unmapped_history':[{'name':n,'lines':c} for n,c in unmapped.most_common()], 'manifest':manifest}
(OUT/'catalogo-auditado.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2,default=serial),encoding='utf8')
assert len({p['id_catalog'] for p in records})==len(records)
assert len({p['uuid'] for p in records})==len(records)
assert len({p['commercial_name'] for p in records})==len(records)
print(json.dumps(stats,ensure_ascii=False,indent=2,default=serial))
print('UNMAPPED HISTORY',json.dumps(payload['unmapped_history'][:20],ensure_ascii=False))
