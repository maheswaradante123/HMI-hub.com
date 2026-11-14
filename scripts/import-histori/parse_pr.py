"""Baca lembar PR bulanan (PR-NNN-M-YY) menjadi JSON. Pemakaian: python3 -I parse_pr.py <folder upload> <keluaran.json>"""
import openpyxl, re, sys, json, datetime, glob, os
NAME = re.compile(r'^\s*PR-(\d{3})-([IVX]+)-(\d{2})\s*$', re.I)
def num(v):
    if v is None or (isinstance(v, str) and not v.strip()): return None
    if isinstance(v, (int, float)): return float(v)
    try: return float(str(v).replace('.', '').replace(',', '.'))
    except Exception: return None
def iso(v):
    return v.date().isoformat() if isinstance(v, datetime.datetime) else None
def parse_sheet(ws):
    hr = None
    for r in range(1, 25):
        if str(ws.cell(r, 1).value or '').strip().upper().startswith('A/C'): hr = r; break
    if not hr: return None
    cols = {}
    for c in range(1, ws.max_column + 1):
        v = str(ws.cell(hr, c).value or '').strip().lower()
        if v: cols.setdefault(v, c)
    m = dict(date=cols.get('tanggal'), desc=cols.get('description'), price=cols.get('price'), qty=cols.get('qty'),
             unit=cols.get('unit'), amount=cols.get('amount'), status=cols.get('status'), code=cols.get('code') or cols.get('kode'))
    hdr_no = ws['B2'].value; hdr_date = ws['B4'].value
    items = []
    blank = 0
    for r in range(hr + 1, ws.max_row + 1):
        d = ws.cell(r, m['desc']).value if m['desc'] else None
        sd = str(d or '').strip()
        if not sd:
            blank += 1
            if blank > 40: break
            continue
        blank = 0
        g = lambda k: ws.cell(r, m[k]).value if m.get(k) else None
        st = g('status')
        items.append(dict(row=r, ac=str(ws.cell(r, 1).value or '').strip() or None, date=iso(g('date')), desc=sd,
                          price=num(g('price')), qty=num(g('qty')), unit=(str(g('unit')).strip() if g('unit') else None),
                          amount=num(g('amount')), status=(str(st).strip() if st else None),
                          code=(str(g('code')).strip() if g('code') else None)))
    return dict(hdr_no=str(hdr_no).strip() if hdr_no else None, hdr_date=iso(hdr_date) or str(hdr_date), items=items, map=m)
if __name__ == '__main__':
    up, out = sys.argv[1], sys.argv[2]
    res = {}
    for f in sorted(glob.glob(os.path.join(up, '*PR-*.xlsx'))):
        wb = openpyxl.load_workbook(f, data_only=True)
        tag = re.search(r'PR-([A-Z]+)', os.path.basename(f)).group(1)
        for ws in wb.worksheets:
            if not NAME.match(ws.title): continue
            p = parse_sheet(ws)
            if p: res[f'{tag}|{ws.title.strip()}'] = p
            else: print('NOHDR', tag, ws.title)
    json.dump(res, open(out, 'w'), default=str, ensure_ascii=False)
    for k, v in res.items(): print(k, v['hdr_no'], v['hdr_date'], len(v['items']))
