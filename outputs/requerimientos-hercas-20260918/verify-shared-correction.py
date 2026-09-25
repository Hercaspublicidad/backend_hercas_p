from pathlib import Path
import zipfile
import xml.etree.ElementTree as E

base = Path(__file__).parent
ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
def content(path):
    with zipfile.ZipFile(path) as z:
        strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            strings = [''.join(x.itertext()) for x in E.fromstring(z.read('xl/sharedStrings.xml'))]
        result = {}
        features = {}
        for name in z.namelist():
            if not (name.startswith('xl/worksheets/sheet') and name.endswith('.xml')):
                continue
            root = E.fromstring(z.read(name))
            for c in root.findall('.//m:sheetData/m:row/m:c', ns):
                v = c.find('m:v', ns)
                f = c.find('m:f', ns)
                val = v.text if v is not None else None
                if c.attrib.get('t') == 's':
                    val = strings[int(val)]
                elif c.attrib.get('t') == 'inlineStr':
                    val = ''.join(c.find('m:is', ns).itertext())
                if val is not None or f is not None:
                    result[(name, c.attrib['r'])] = (val, f.text if f is not None else None)
            features[name] = {
                tag: len(root.findall('.//m:' + tag, ns))
                for tag in ['tablePart','dataValidation','conditionalFormatting','pane','mergeCell']
            }
        return result, features

old, of = content(base / 'shared-plan-before-correction.xlsx')
new, nf = content(base / 'shared-plan-review.xlsx')
diff = {k for k in set(old) | set(new) if old.get(k) != new.get(k)}
allowed = {
    **{'xl/worksheets/sheet6.xml': {'A4','E6','E86','G86','H86','E89','G89','H89'}},
    'xl/worksheets/sheet5.xml': {'E7','B33'},
    'xl/worksheets/sheet7.xml': {'A4','F6'}
}
for sheet, cell in sorted(diff):
    if cell not in allowed.get(sheet, set()):
        raise RuntimeError(f'Unexpected change: {sheet} {cell}')
assert of == nf, 'Native feature count changed'
assert len(diff) == 12, diff
print('Verified: exactly 12 intended cell changes; other values/formulas preserved; tables, validations, formatting rules, panes and merges retained.')
