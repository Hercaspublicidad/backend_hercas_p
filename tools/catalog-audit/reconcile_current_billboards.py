"""Reconcile named source rows; never manufacture a row to hit a target count."""
import sys,json,re,hashlib
from pathlib import Path
from collections import Counter
sys.path.insert(0,str(Path(__file__).parent/'.deps'))
import xlrd

root=Path('D:/HERCAS/Comercial')
source=next(root.glob('*06 de Septiembre*.xls'))
sheet=xlrd.open_workbook(source).sheet_by_name('Increm 2026 -no todas la va (2)')
output=Path('D:/api_0doo/outputs/catalogo-20260917')
records=[]; zone=''
def key(code):
    return re.sub(r'[^A-Z0-9]','',code.upper())
for i in range(2,107):
    if sheet.cell_value(i,0): zone=str(sheet.cell_value(i,0)).strip()
    raw=str(sheet.cell_value(i,1)).strip()
    if not raw:continue
    state=str(sheet.cell_value(i,6)).strip()
    selection='candidate_visible' if state in ('DISPONIBLE','ARRENDADA') else 'pending_confirmation' if 'verificar' in state.lower() or raw=='PAA-005B' else 'hidden'
    records.append({'code_original':raw,'matching_key':key(raw),'zone':zone,'source_row':i+1,
        'source_state':state,'selection':selection,'location':str(sheet.cell_value(i,2)).strip(),
        'note':str(sheet.cell_value(i,18)).strip()})
assert len({r['matching_key'] for r in records})==len(records)
confirmed=[r for r in records if r['selection']=='candidate_visible']
assert len(confirmed)==82
prior=json.loads((output/'catalogo-auditado.json').read_text(encoding='utf8'))
current={r['matching_key']:r for r in records}
all_keys=set(current)|{key(a['code']) for a in prior['assets']}
decision=[]
for k in sorted(all_keys):
    r=current.get(k)
    old=next((a for a in prior['assets'] if key(a['code'])==k),None)
    decision.append({'matching_key':k,'code':r['code_original'] if r else old['code'],
        'product_id':old['product_id'] if old else None,'selection':r['selection'] if r else 'hidden',
        'reason':r['source_state'] if r else 'Ausente de la sábana más reciente localizada',
        'source_row':r['source_row'] if r else None})
payload={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'sheet':sheet.name,'source_period':'2026-09-06/2026-09-12','requested_count':83,
    'source_summary':{'available_metropolitan':sheet.cell_value(120,1),'available_towns':sheet.cell_value(121,1),'rented':sheet.cell_value(122,1)},
    'detail_counts':dict(Counter(r['selection'] for r in records)),
    'publication_status':'blocked_missing_exact_83rd_code','applied_to_database':False,
    'rows':records,'selection':decision}
(output/'seleccion-vallas-vigentes-pendiente.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'rows':len(records),'detail_counts':payload['detail_counts'],
    'by_zone':dict(Counter(r['zone'] for r in confirmed)),
    'pending':[r['code_original'] for r in records if r['selection']=='pending_confirmation'],
    'selection_counts':dict(Counter(r['selection'] for r in decision))},ensure_ascii=False,indent=2))
