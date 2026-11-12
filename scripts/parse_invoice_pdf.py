#!/usr/bin/env python3
"""Membaca PDF Invoice lama (Google Sheets, satu invoice per halaman) menjadi JSON mentah.
Pemakaian: pdftotext -layout invoice.pdf invoice.txt && python3 scripts/parse_invoice_pdf.py invoice.txt invoice.json
Halaman lanjutan (hanya tanda tangan) dan formulir kosong diabaikan."""
import re, json, sys, collections, datetime as dt
t=open(sys.argv[1]).read(); pages=t.split('\f')
MON={'januari':1,'january':1,'februari':2,'february':2,'maret':3,'march':3,'april':4,'mei':5,'may':5,'juni':6,'june':6,'juli':7,'july':7,'agustus':8,'august':8,'september':9,'oktober':10,'october':10,'november':11,'desember':12,'december':12,'jan':1,'feb':2,'mar':3,'apr':4,'jun':6,'jul':7,'agu':8,'agt':8,'aug':8,'sep':9,'sept':9,'okt':10,'oct':10,'nov':11,'des':12,'dec':12}
def pdate(s):
    m=re.search(r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})',s or '')
    if m and m.group(2).lower() in MON: return dt.date(int(m.group(3)),MON[m.group(2).lower()],int(m.group(1))).isoformat()
def rp(s): return float(s.replace('Rp','').replace(',',''))
out=[];notes=[]
UNIT=r'(kg|KG|Kg|g|gr|gram|pack|Pack|Karung)'
for pi,p in enumerate(pages):
    m=re.search(r'^No\.\s*:\s*(INV-\S+)\s+Surat\s+Jalan\s*:\s*(.*)$',p,re.M)
    if not m: continue
    no=m.group(1); do=m.group(2).strip() or None
    d=pdate((re.search(r'^Tanggal\s*:(.*)$',p,re.M) or [0,''])[1])
    km=re.search(r'^Kepada\s*:\s*(.*)$',p,re.M); kk=km.group(1) if km else ''
    mm=re.match(r'^(.*?)\s{2,}No\. Telepon\s*:\s*(.*)$',kk) or re.match(r'^(.*?)\s*No\. Telepon\s*:\s*(.*)$',kk)
    kepada,tel=((mm.group(1).strip(),mm.group(2).strip()) if mm else (kk.strip(),''))
    lines=p.split('\n')
    hdr=next((i for i,l in enumerate(lines) if re.match(r'\s*No\s+Deskripsi',l)),None)
    end=next((i for i,l in enumerate(lines) if l.startswith('Total Pembelanjaan')),None)
    has_price='Harga' in lines[hdr]
    blocks=[]
    for l in lines[hdr+1:end]:
        if not l.strip(): continue
        if re.match(r'^\s*\d+\s{2,}\S',l) or re.match(r'^\s*\d+\s*$',l):
            blocks.append([l])
        elif re.match(r'^[A-Za-z][A-Za-z ]{3,}?\s{2,}Rp[\d,]+\s*$',l) and not re.match(r'^ok\b',l.strip()):
            blocks.append(['   0  '+l.strip()])   # baris tanpa nomor (mis. Transportasi)
        elif blocks: blocks[-1].append(l)
    items=[]
    for b in blocks:
        txt='\n'.join(b); first=b[0]
        dm=re.match(r'^\s*(\d+)\s{2,}(.*?)(?:\s{2,}|$)',first)
        if not dm or not dm.group(2).strip(): continue   # baris nomor kosong
        desc=dm.group(2).strip()
        rest=txt[txt.index(desc)+len(desc):]
        q=re.search(r'(?<![\w.])(\d+(?:[.,]\d+)?)\s+'+UNIT+r'\b',rest)
        amts=re.findall(r'Rp[\d,]+',rest)
        tail=re.sub(r'.*Rp[\d,]+\s*','',first.split('Rp')[-1]) if False else ''
        ket=''
        if amts:
            keep=amts[:2] if has_price else amts[:1]
            last=first.rfind(keep[-1]); ket=re.sub(r'Rp[\d,]+|(?<![A-Za-z])[\d.]+(?![A-Za-z])','',first[last+len(keep[-1]):]).strip()
            # kata di baris lain
            ket=' '.join(x for x in [ket]+[re.sub(r'\s+',' ',l).strip() for l in b[1:] if not re.search(r'\d+\s+'+UNIT+r'\b',l)] if x)
        amts=amts[:2] if has_price else amts[:1]    # kolom hitung tersembunyi di sisi kanan diabaikan
        it=dict(desc=desc,qty=(q.group(1) if q else None),unit=(q.group(2) if q else None),amts=amts,ket=ket)
        items.append(it)
    tl=lines[end]; tamts=re.findall(r'Rp[\d,]+',tl)
    free=bool(re.search(r'\bfree\b',tl,re.I)) and not tamts
    def after(label):
        mm=re.search(r'^'+label+r'\s+(.*)$',p,re.M); return mm.group(1).strip() if mm else None
    dp=after('Uang Muka')
    md=re.search(r'^(?:Diskon|Potongan harga)\s+(Rp[\d,]+)\s*$',p,re.M); disc=rp(md.group(1)) if md else 0
    mj=re.search(r'^Jatuh\s+\w+\s*:\s*(.*)$',p,re.M)
    mn=re.search(r'^Note\s*:\s*(.*)$',p,re.M)
    mb=re.search(r'^\s*(Pembayaran melalui.*?)(?:\n\s+(Bank .*))?$',p,re.M)
    bank=re.sub(r'\s+',' ',(mb.group(1)+' '+(mb.group(2) or '')).strip()) if mb else None
    out.append(dict(page=pi+1,no=no,do=do,date=d,kepada=kepada,tel=tel,has_price=has_price,items=items,total=(rp(tamts[0]) if tamts else None),free=free,discount=disc,
        dp=(rp(dp) if dp and re.fullmatch(r'Rp[\d,]+',dp) else 0),due=pdate(mj.group(1)) if mj else None,note=(mn.group(1).strip().lstrip(':').strip() if mn else None),bank=bank,
        terbilang=after('Terbilang')))
json.dump(out,open(sys.argv[2],'w'),ensure_ascii=False,indent=1)
print(len(out))
