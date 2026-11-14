import json,re,datetime,collections,openpyxl
from openpyxl.styles import Font,PatternFill
raw=json.load(open('cpj_raw.json'))
ROM=['I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII']
FM={'JAN':1,'JAN2':1,'FEB':2,'MAR':3,'APR':4,'MEI':5,'JUN':6,'JUL':7,'AGU':8,'SEP':9}
FLAG={'FFFFFF00':'NON_CPJ','FFFF9900':'OVER','FFF9CB9C':'OVER','FFFF0000':'REJECTED','FF00FFFF':'INCOMING'}
NAME=re.compile(r'^\s*(PC-)?(R-)?CPJ-(\d{3})-([IVX]+)-(\d{2})',re.I)
def monday_of_week(y,m,n):
    d1=datetime.date(y,m,1); off=(d1.weekday())  # Monday=0
    # app: week = ((day-1+off)//7)+1 -> first day of week n (Mon) = 1 + 7*(n-1) - off, min 1
    day=max(1,1+7*(n-1)-off); 
    try: return datetime.date(y,m,day)
    except: return None
def tot(lines,done=True):
    t=dict(req=0,appr=0,inc=0,must=0,spent=0)
    for l in lines:
        fl=FLAG.get(l['fill'],'NONE'); p=(l['amount'] if l['amount'] is not None else (l['price'] or 0)*(l['qty'] or 0)) or 0
        if fl=='INCOMING': t['inc']+=p; continue
        t['req']+=p
        if fl=='REJECTED': continue
        t['appr']+=p
        if fl=='NON_CPJ': continue
        t['must']+=p
        if l['ramount'] is not None: t['spent']+=l['ramount']
        elif l['rprice'] is not None or l['rqty'] is not None: t['spent']+=(l['rprice'] if l['rprice'] is not None else (l['price'] or 0))*(l['rqty'] if l['rqty'] is not None else (l['qty'] or 0))
        else: t['spent']+=p
    return t
groups=collections.OrderedDict()
ignored=[]
for key,p in raw.items():
    fk,sheet=key.split('|',1)
    mm=NAME.match(sheet)
    pc,r,nnn,mon,yy=mm.groups()
    if fk=='JAN2': continue  # salinan identik dengan JAN
    k=(fk,nnn)
    g=groups.setdefault(k,{})
    g['PC' if pc else ('R' if r else 'P')]=(sheet,p)
wb=openpyxl.Workbook(); ws=wb.active; ws.title='CPJ'
hdr=['Berkas','Sheet rencana','Sheet realisasi','Sheet petty cash','Usulan nomor','Usulan tanggal jurnal','Tanggal di sheet (header)','Nomor di sheet (header)','Jml baris rencana','Jml baris realisasi','Total permintaan (hitung)','Total permintaan (sheet)','Cocok?','Realisasi keluar (hitung)','Realisasi keluar (sheet)','Cocok?','Rentang tanggal transaksi','Baris Petty Cash','Catatan']
ws.append(hdr)
for c in ws[1]: c.font=Font(bold=True); c.fill=PatternFill('solid',fgColor='DDDDDD')
for (fk,nnn),g in groups.items():
    m=FM[fk]; y=2026
    base=g.get('R') or g.get('P')
    sh,p=base
    t=tot(p['lines']) 
    s=p['summary']
    sreq=s.get('total permintaan'); sspent=s.get('realisasi uang keluar')
    dts=sorted(l['date'] for l in p['lines'] if l['date'])
    pet=[l for l in p['lines'] if re.search(r'petty\s*cash',l['desc'],re.I)]
    note=[]
    if 'R' not in g: note.append('tanpa lembar realisasi')
    if 'P' not in g: note.append('tanpa lembar rencana')
    md=monday_of_week(y,m,int(nnn))
    ok1= (sreq is not None and abs(t['req']-sreq)<2)
    ok2= (sspent is not None and abs(t['spent']-sspent)<2)
    ws.append([fk,g.get('P',('',))[0],g.get('R',('',))[0],g.get('PC',('',))[0],f'CPJ-{nnn}-{ROM[m-1]}-26',md.isoformat() if md else '',p['hdr_date'],p['hdr_no'],len(g['P'][1]['lines']) if 'P' in g else '',len(p['lines']),round(t['req']),sreq if sreq is None else round(sreq),'ya' if ok1 else 'TIDAK',round(t['spent']),sspent if sspent is None else round(sspent),'ya' if ok2 else 'TIDAK',f"{dts[0]} s/d {dts[-1]}" if dts else '',len(pet),'; '.join(note)])
for col,w in zip('ABCDEFGHIJKLMNOPQRS',[8,22,22,24,18,16,16,20,10,10,18,18,8,18,18,8,24,10,28]): ws.column_dimensions[col].width=w
ws.freeze_panes='A2'
wb.save('Daftar_CPJ_review.xlsx')
ok=[r for r in ws.iter_rows(min_row=2,values_only=True)]
print('journals',len(ok),'req cocok',sum(1 for r in ok if r[12]=='ya'),'spent cocok',sum(1 for r in ok if r[15]=='ya'))
for r in ok: print(r[0],r[4],r[5],'|hdr',r[6],'|',r[8],r[9],'|req',r[10],r[11],r[12],'|spent',r[13],r[14],r[15],'|petty',r[17],r[18])
