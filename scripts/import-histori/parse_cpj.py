import openpyxl,re,glob,os,json,datetime,collections
UP='/mnt/user-data/uploads/'
FILES={'JAN':'208970d2-CPJ_JANUARI.xlsx','JAN2':'71227701-CPJ_JANUARI_2026.xlsx','FEB':'94b0f771-CPJ_FEBRUARI.xlsx','MAR':'9959877e-CPJ_MARET.xlsx','APR':'030ca691-CPJ_APRIL.xlsx','MEI':'7954a680-CPJ_MEI.xlsx','JUN':'f504fea7-CPJ_JUNI.xlsx','JUL':'91f78744-CPJ_JULI.xlsx','AGU':'d01ea8cb-CPJ_AGUSTUS.xlsx','SEP':'36cc14b3-CPJ_SEPTEMBER.xlsx'}
NAME=re.compile(r'^\s*(PC-)?(R-)?CPJ-(\d{3})-([IVX]+)-(\d{2})[\s\.]*$',re.I)
def num(v):
    if v is None or v=='' or (isinstance(v,str) and v.strip()==''): return None
    if isinstance(v,(int,float)): return float(v)
    try: return float(str(v).replace('.','').replace(',','.'))
    except: return None
def fillrgb(c):
    try:
        if c.fill and c.fill.fill_type=='solid':
            col=c.fill.fgColor
            if col.type=='rgb': return col.rgb
            if col.type=='theme': return f'theme{col.theme}:{round(col.tint or 0,2)}'
            if col.type=='indexed': return f'idx{col.indexed}'
    except Exception: pass
    return None
def parse_sheet(ws):
    # find header row
    hr=None
    for r in range(1,30):
        if str(ws.cell(r,1).value or '').strip().upper().startswith('A/C'): hr=r;break
    if not hr: return None
    cols={}
    for c in range(1,ws.max_column+1):
        v=str(ws.cell(hr,c).value or '').strip().lower()
        if v: cols.setdefault(v,c)
    sub={}
    for c in range(1,ws.max_column+1):
        v=str(ws.cell(hr+1,c).value or '').strip().lower()
        if v: sub.setdefault(v,[]).append(c)
    realc=cols.get('realization')
    def sc(name):
        for c in sub.get(name,[]):
            if realc and c>=realc: return c
    m=dict(ac=1,no=cols.get('no.'),date=cols.get('tanggal transaksi'),desc=cols.get('description'),price=cols.get('price'),qty=cols.get('qty'),unit=cols.get('unit'),amount=cols.get('amount'),
           rprice=sc('price'),rqty=sc('qty'),ramount=sc('amount'),proof=sc('attachment of proof'))
    # code col: between date and desc with header empty
    code=None
    if m['date'] and m['desc'] and m['desc']-m['date']>1: code=m['date']+1
    m['code']=code
    hdr_no=ws['B8'].value; hdr_date=ws['B10'].value
    lines=[];summary={}
    r=hr+2
    while r<=ws.max_row:
        a=ws.cell(r,1).value
        sa=str(a or '').strip()
        if sa.lower().startswith('total permintaan'):
            for rr in range(r,r+5):
                lab=str(ws.cell(rr,1).value or '').strip().lower(); lab2=None
                for c in range(2,ws.max_column+1):
                    v=ws.cell(rr,c).value
                    if isinstance(v,str) and v.strip() and not v.strip().startswith(':'): lab2=(c,v.strip().lower());break
                vals=[(c,ws.cell(rr,c).value) for c in range(2,ws.max_column+1) if isinstance(ws.cell(rr,c).value,(int,float))]
                if lab: summary[lab]=vals[0][1] if vals else None
                if lab2 and vals:
                    summary[lab2[1]]=[v for c,v in vals if c>lab2[0]][0] if [v for c,v in vals if c>lab2[0]] else None
            break
        d=ws.cell(r,m['desc']).value if m['desc'] else None
        sd=str(d or '').strip()
        if sd:
            price=num(ws.cell(r,m['price']).value) if m['price'] else None; qty=num(ws.cell(r,m['qty']).value) if m['qty'] else None
            dt=ws.cell(r,m['date']).value if m['date'] else None
            dtv=dt.date().isoformat() if isinstance(dt,datetime.datetime) else None
            pc=None
            if m['proof']:
                pcell=ws.cell(r,m['proof']); pc=pcell.hyperlink.target if pcell.hyperlink else (str(pcell.value).strip() if pcell.value not in (None,'') else None)
            fl=fillrgb(ws.cell(r,m['desc'])) or fillrgb(ws.cell(r,1))
            lines.append(dict(row=r,ac=sa or None,code=(str(ws.cell(r,code).value).strip() if code and ws.cell(r,code).value else None),date=dtv,desc=sd,price=price,qty=qty,
                unit=(str(ws.cell(r,m['unit']).value).strip() if m['unit'] and ws.cell(r,m['unit']).value else None),amount=num(ws.cell(r,m['amount']).value) if m['amount'] else None,
                rprice=num(ws.cell(r,m['rprice']).value) if m['rprice'] else None,rqty=num(ws.cell(r,m['rqty']).value) if m['rqty'] else None,
                ramount=num(ws.cell(r,m['ramount']).value) if m['ramount'] else None,proof=pc,fill=fl))
        r+=1
    return dict(hdr_no=str(hdr_no).strip() if hdr_no else None,hdr_date=hdr_date.date().isoformat() if isinstance(hdr_date,datetime.datetime) else str(hdr_date),lines=lines,summary=summary,map=m)
if __name__=='__main__':
    out={}
    for k,f in FILES.items():
        wb=openpyxl.load_workbook(UP+f,data_only=True)
        for ws in wb.worksheets:
            mm=NAME.match(ws.title)
            if not mm: continue
            p=parse_sheet(ws)
            if not p: print('NOHDR',k,ws.title);continue
            out[f'{k}|{ws.title}']=p
            fills=collections.Counter(l['fill'] for l in p['lines'])
            ps=sum((l['amount'] or 0) for l in p['lines'])
            print(k,repr(ws.title),p['hdr_no'],p['hdr_date'],len(p['lines']),'plan',round(ps),'sumTotReq',p['summary'].get('total permintaan'),dict(fills))
    json.dump(out,open('cpj_raw.json','w'),default=str)
