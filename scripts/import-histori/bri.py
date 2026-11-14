import re,glob,json
rows=[]
for f in sorted(glob.glob('*IBIZ*.txt')):
    t=open(f).read().split('\n')
    cur=None
    for ln in t:
        m=re.match(r'^\s*(\d{2})/(\d{2})/(\d{2}) (\d{2}:\d{2}:\d{2})\s+(.*?)\s{2,}(\S+)\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s*$',ln)
        if m:
            d,mo,y,tm,desc,usr,db,cr,bal=m.groups()
            cur=dict(date=f'20{y}-{mo}-{d}',time=tm,remark=desc.strip(),user=usr,debit=float(db.replace(',','')),credit=float(cr.replace(',','')),balance=float(bal.replace(',','')),src=f[:8])
            rows.append(cur)
        elif cur is not None and ln.strip() and not re.search(r'Halaman|Page|Tanggal|Saldo|Balance|Statement|Transaction|Kepada|Akun|Hal\b',ln) and re.match(r'^\s{20,}\S',ln) and len(ln.strip())<80:
            pass
bad=0
for i in range(1,len(rows)):
    if abs(rows[i-1]['balance']+rows[i]['credit']-rows[i]['debit']-rows[i]['balance'])>0.01: bad+=1; 
print(len(rows),'tx; breaks',bad)
import collections
c=collections.defaultdict(lambda:[0,0.0,0,0.0])
for r in rows:
    k=r['date'][:7]
    if r['debit']>0: c[k][0]+=1;c[k][1]+=r['debit']
    if r['credit']>0: c[k][2]+=1;c[k][3]+=r['credit']
for k in sorted(c): print(k,[round(x,2) for x in c[k]])
kinds=collections.Counter(re.sub(r'[\d_]+',' ',r['remark'])[:30] for r in rows)
print(kinds.most_common(15))
json.dump(rows,open('bri.json','w'))
for r in rows:
    if r['debit']>0: print(r['date'],r['remark'][:70],r['debit'])
