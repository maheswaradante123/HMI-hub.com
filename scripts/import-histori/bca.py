import re,glob,json
rows=[]
for f in sorted(glob.glob('*ESTATEMENT*.txt')):
    t=open(f).read().split('\n')
    per=re.search(r'PERIODE\s*:\s*(\w+)\s+(\d{4})',re.sub(r'\s+',' ',open(f).read().replace('PE RIOD E','PERIODE')) ) 
    ym=re.search(r'_(\d{4})(\d{2})\.txt',f); year,mon=ym.group(1),ym.group(2)
    cur=None; ents=[]
    for ln in t:
        m=re.match(r'^\s+(\d{2})/(\d{2})\s{2,}(\S.*)$',ln)
        if m and not m.group(3).startswith('SALDO AWAL'):
            cur=dict(d=m.group(1),m=m.group(2),lines=[ln]); ents.append(cur); continue
        if re.search(r'SALDO AWAL\s*:',ln): cur=None
        if cur is not None and ln.strip():
            if re.search(r'Bersambung|HALAMAN|REKENING GIRO|KCP|CATATAN',ln): continue
            cur['lines'].append(ln)
    for e in ents:
        mut=None;dbt=False;desc=[]
        for i,ln in enumerate(e['lines']):
            body=ln
            toks=[(mm.start(),mm.end(),mm.group(1),bool(mm.group(2))) for mm in re.finditer(r'(?<![\d.,/])(\d{1,3}(?:,\d{3})*\.\d{2})( DB)?',ln)]
            for s,en,val,db in toks:
                if en<=128 and mut is None and s>80: mut=float(val.replace(',','')); dbt=db
            txt=re.sub(r'(?<![\d.,/])\d{1,3}(?:,\d{3})*\.\d{2}( DB)?','',ln)
            txt=re.sub(r'^\s*\d{2}/\d{2}','',txt)
            desc.append(re.sub(r'\s+',' ',txt).strip())
        if mut is None: continue
        rows.append(dict(date=f"{year}-{e['m']}-{e['d']}",remark=' | '.join(x for x in desc if x),debit=mut if dbt else 0.0,credit=0.0 if dbt else mut,src=f"{year}-{mon}"))
import collections
c=collections.defaultdict(lambda:[0,0.0,0,0.0])
for r in rows:
    k=r['src']; c[k][0]+=r['debit']>0;c[k][1]+=r['debit'];c[k][2]+=r['credit']>0;c[k][3]+=r['credit']
for k in sorted(c): print(k,'DB n',c[k][0],round(c[k][1],2),'CR n',c[k][2],round(c[k][3],2))
json.dump(rows,open('bca.json','w'))
