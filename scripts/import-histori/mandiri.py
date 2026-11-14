import pdfplumber,re,sys,json,glob,os,datetime
from multiprocessing import Pool
AMT=re.compile(r'^-?[\d,]+\.\d{2}$')
DATE=re.compile(r'^\d{2}$')
MON={'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12}
def money(s): return float(s.replace(',',''))
def parse(path):
    out=[];prev_last=None
    with pdfplumber.open(path) as pdf:
        for pn,page in enumerate(pdf.pages):
            words=page.extract_words(keep_blank_chars=False,use_text_flow=False,x_tolerance=2,y_tolerance=2)
            hdr={w['text']:w for w in words if w['text'] in('Posting','Remark','Reference','Debit','Credit','Balance')}
            if 'Balance' not in hdr or 'Debit' not in hdr: continue
            ytop=max(w['bottom'] for w in words if w['text'] in('Posting','Remark','Debit','Credit','Balance'))
            xr=hdr['Remark']['x0']-2; xref=hdr['Reference']['x0']-2
            dx,cx,bx=hdr['Debit']['x1'],hdr['Credit']['x1'],hdr['Balance']['x1']
            body=[w for w in words if w['top']>ytop-1 and w['bottom']<page.height-45]
            # amount words
            nums=[w for w in body if AMT.match(w['text']) and w['x0']>xref+40]
            rows={}
            for w in nums:
                key=round(w['top']/3)
                rows.setdefault(key,[]).append(w)
            anchors=[]
            for k,ws in sorted(rows.items()):
                d=[w for w in ws if abs(w['x1']-dx)<45]; c=[w for w in ws if abs(w['x1']-cx)<45]; b=[w for w in ws if abs(w['x1']-bx)<45]
                if d and c and b:
                    anchors.append(dict(y=ws[0]['top'],debit=money(d[0]['text']),credit=money(c[0]['text']),balance=money(b[0]['text']),rem=[],dt=[]))
            if not anchors: continue
            for w in body:
                if AMT.match(w['text']) and w['x0']>xref+40: continue
                if w['x0']<xr-1: zone='dt'
                elif w['x0']<xref: zone='rem'
                else: zone='ref'
                if zone=='ref':
                    if w['text']=='-': continue
                    zone='rem'
                # nearest anchor
                best=min(anchors,key=lambda a:abs(a['y']-w['top']))
                if w['top']<anchors[0]['y']-14 and prev_last is not None and zone=='rem' :
                    tgt=prev_last
                else: tgt=best
                tgt['rem' if zone=='rem' else 'dt'].append(w)
            for a in anchors:
                out.append(a); prev_last=a
    res=[]
    for a in out:
        dtw=' '.join(w['text'] for w in sorted(a['dt'],key=lambda w:(round(w['top']/3),w['x0'])))
        m=re.search(r'(\d{2}) (\w{3}) (\d{4}),?\s*(\d{2}:\d{2}:\d{2})?',dtw)
        t=re.search(r'(\d{2}:\d{2}:\d{2})',dtw)
        date=f"{m.group(3)}-{MON[m.group(2)]:02d}-{m.group(1)}" if m else None
        rem=' '.join(w['text'] for w in sorted(a['rem'],key=lambda w:(round(w['top']/3),w['x0'])))
        res.append(dict(date=date,time=t.group(1) if t else None,remark=rem,debit=a['debit'],credit=a['credit'],balance=a['balance']))
    return res
def run(p):
    r=parse(p); return os.path.basename(p),r
if __name__=='__main__':
    files=sorted(glob.glob('/mnt/user-data/uploads/*Acc_Statement_1290015674415*.pdf'))
    with Pool(4) as pool: outs=pool.map(run,files)
    allr=[]
    for name,r in outs:
        mm=re.search(r'_(\d{4}-\d{2})-\d{2}_',name).group(1)
        # validate running balance
        bad=0
        for i in range(1,len(r)):
            exp=round(r[i-1]['balance']+r[i]['credit']-r[i]['debit'],2)
            if abs(exp-r[i]['balance'])>0.01: bad+=1
        print(mm,len(r),'tx; debit',round(sum(x['debit'] for x in r)),'credit',round(sum(x['credit'] for x in r)),'balance-breaks',bad)
        for x in r: x['src']=mm
        allr+=r
    json.dump(allr,open('mandiri.json','w'))
