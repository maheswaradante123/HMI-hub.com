"""Ringkasan + usulan perlakuan per transaksi untuk SATU bulan, untuk dibahas dengan pemilik sebelum SQL bulan itu dijalankan.
Pemakaian: python3 -I month_review.py <BULAN> <folder qa_*.json> <cpj_raw.json> <pr_raw.json> <mandiri.json> <keluaran.xlsx>"""
import json, sys, re, collections, datetime, openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
mon, qd, cj, pj, mj, out = sys.argv[1:7]
MONS = ['JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN', 'JUL', 'AGU', 'SEP']; MI = MONS.index(mon) + 1
PRF = {'JAN': 'JANUARI', 'FEB': 'FEBRUARI', 'MAR': 'MARET', 'APR': 'APRIL', 'MEI': 'MEI', 'JUN': 'JUNI', 'JUL': 'JULI', 'AGU': 'AGUSTUS', 'SEP': 'SEPTEMBER'}
D = lambda s: datetime.date.fromisoformat(s)
qa = {m: json.load(open(f'{qd}/qa_{m}.json')) for m in MONS}
cpj = json.load(open(cj)); pr = json.load(open(pj))
jd = {j['no']: D(j['date']) for m in MONS for j in qa[m]['journals']}
lines = [dict(l, jdate=jd[l['journal']]) for m in MONS for l in qa[m]['lines']]
bank = sorted([b for b in json.load(open(mj))], key=lambda b: (b['date'], b['time']))
deb = [b for b in bank if b['debit'] > 0]
tok = lambda s: set(re.findall(r'[a-z]{4,}', (s or '').lower()))
FEE = lambda b: b['debit'] <= 7500 and not re.search(r'KE |CENAIDJA|BRINIDJA', b['remark'])
HUTANG = lambda b: re.search(r'peng(e|a)mbalian hutang|pengambilan hutang', b['remark'], re.I)
INTERNAL = lambda b: re.search(r'HARMONI MITRA INOVIN|pemindahan dana|ADHIJAYA MITRA SEKAWAN', b['remark'], re.I)
def parse(b):
    r = b['remark']
    m = re.search(r'(?:CENAIDJA|BRINIDJA|BNIAIDJA|\w+IDJA)/(.+?)(?:99102|99105|$)', r)
    if m: return m.group(1).strip()[:90], ''
    m = re.match(r'(.*?)\s*MCM InhouseTrf KE (.+?) Transfer Fee', r)
    if m: return m.group(2).strip(), m.group(1).strip()
    return r[:60], ''
# pasangan persis lalu selisih kecil (sama seperti qa_report)
by_amt = collections.defaultdict(list)
for l in lines:
    if l['real'] and l['flag'] != 'INCOMING': by_amt[round(l['real'])].append(l)
used = set(); pairs = {}; approx = set()
win = lambda b, l: -7 <= (D(b['date']) - l['jdate']).days <= 14
for b in deb:
    if FEE(b) or HUTANG(b) or INTERNAL(b): continue
    best = None
    for l in by_amt.get(round(b['debit']), []):
        k = (l['journal'], l['line_no'])
        if k in used or not win(b, l): continue
        sc = (-len(tok(l['desc']) & tok(b['remark'])), abs((D(b['date']) - l['jdate']).days - 3))
        if best is None or sc < best[0]: best = (sc, l, k)
    if best: used.add(best[2]); pairs[id(b)] = best[1]
for b in deb:
    if id(b) in pairs or FEE(b) or HUTANG(b) or INTERNAL(b): continue
    best = None
    for l in lines:
        k = (l['journal'], l['line_no'])
        if k in used or not l['real'] or l['flag'] == 'INCOMING' or not win(b, l): continue
        diff = abs(l['real'] - b['debit'])
        if diff == 0 or diff > 10000 or diff > 0.01 * b['debit'] or not (tok(l['desc']) & tok(b['remark'])): continue
        if best is None or diff < best[0]: best = (diff, l, k)
    if best: used.add(best[2]); pairs[id(b)] = best[1]; approx.add(id(b))
# gabungan: beberapa transfer dengan catatan sama (mis. kasbon 7 orang) = satu baris CPJ
group_of = {}
rest = [b for b in deb if id(b) not in pairs and not FEE(b) and not HUTANG(b) and not INTERNAL(b)]
grp = collections.defaultdict(list)
for b in rest:
    p, note = parse(b)
    if note: grp[(note.lower()[:25], b['date'][:7])].append(b)
for key, g in grp.items():
    if len(g) < 2: continue
    tot = sum(x['debit'] for x in g)
    for l in lines:
        k = (l['journal'], l['line_no'])
        if k in used or not l['real'] or abs(l['real'] - tot) > max(5000, 0.01 * tot) or not all(win(x, l) for x in g): continue
        if not (tok(l['desc']) & tok(g[0]['remark'])): continue
        used.add(k)
        for x in g: pairs[id(x)] = l; group_of[id(x)] = len(g)
        break
# usulan A/C dan kode dari baris CPJ historis yang paling mirip
hist = [(tok(l['desc']), l) for l in lines if l['desc']]
def guess(text):
    t = tok(text); best = None
    for ht, l in hist:
        j = len(t & ht)
        if j and (best is None or j > best[0]): best = (j, l)
    return best[1] if best else None
wk = lambda d: next((j for j, dt in sorted(jd.items(), key=lambda x: x[1], reverse=True) if D(d) >= dt), None)
wb = openpyxl.Workbook()
def sheet(name, head, rows, widths):
    ws = wb.create_sheet(name); ws.append(head)
    for c in ws[1]: c.font = Font(bold=True); c.fill = PatternFill('solid', fgColor='DDDDDD')
    for r in rows: ws.append(r)
    for i, w in enumerate(widths): ws.column_dimensions[chr(65 + i)].width = w
    ws.freeze_panes = 'A2'; return ws
js = [j for j in qa[mon]['journals']]
# --- Ringkasan
ws = wb.active; ws.title = 'Ringkasan'
ws.append([f'RINGKASAN {mon} 2026 (rekening: hanya Mandiri 1290015674415 tersedia untuk Januari-Maret; BCA mulai April, BRI mulai Juni)']); ws['A1'].font = Font(bold=True)
ws.append([])
ws.append(['PR (lembar)', 'Tanggal lembar', 'Item', 'Total (tanpa cancel/draft)', 'Approved', 'Received', 'Closed', 'Order', 'Draft', 'Cancel/Move'])
for c in ws[3]: c.font = Font(bold=True)
for it in sorted([i for i in qa[mon]['items']], key=lambda i: i['sheet']):
    pass
bys = collections.defaultdict(list)
for it in qa[mon]['items']: bys[it['sheet']].append(it)
for sh, its in sorted(bys.items()):
    c = collections.Counter(i['status'] for i in its)
    ws.append([sh, str(jd[f'CPJ-{sh[3:6]}-{sh.split("-")[2]}-26'] - datetime.timedelta(days=3)) if f'CPJ-{sh[3:6]}-{sh.split("-")[2]}-26' in jd else '', len(its), round(sum(i['amount'] or 0 for i in its if i['status'] not in ('CANCELLED', 'DRAFT'))), c['APPROVED'], c['RECEIVED'], c['CLOSED'], c['ORDERED'], c['DRAFT'], c['CANCELLED']])
ws.append([])
ws.append(['CPJ / R-CPJ', 'Tanggal jurnal', 'Baris CPJ (rencana)', 'Total rencana CPJ (sheet CPJ)', 'Baris R-CPJ', 'Total rencana R-CPJ', 'Total realisasi R-CPJ', 'Tertaut PR', 'Debit Mandiri pekan itu', 'Kredit Mandiri pekan itu', 'Debit yang berpasangan', 'Debit belum di CPJ'])
for c in ws[ws.max_row]: c.font = Font(bold=True)
for j in js:
    n = int(j['no'][4:7]); pk = [k for k in cpj if k.startswith(mon + '|') and re.match(rf'\s*CPJ-{n:03d}-', k.split('|')[1])]
    pl = cpj[pk[0]]['lines'] if pk else []
    d0 = D(j['date']); d1 = d0 + datetime.timedelta(days=6)
    wb_ = [b for b in bank if str(d0) <= b['date'] <= str(d1)]
    dd = [b for b in wb_ if b['debit'] > 0 and not FEE(b) and not HUTANG(b) and not INTERNAL(b)]
    ws.append([j['no'], j['date'], len(pl), round(sum(l['amount'] or 0 for l in pl)), j['lines'], round(j['plan_total']), round(j['real_total']), j['linked'],
               round(sum(b['debit'] for b in wb_ if b['debit'] > 0)), round(sum(b['credit'] for b in wb_)), sum(1 for b in dd if id(b) in pairs), sum(1 for b in dd if id(b) not in pairs)])
ws.append([]); ws.append(['Pekan = Senin-Minggu mulai tanggal jurnal. Debit/kredit bank termasuk biaya admin, pengembalian hutang, dan pemindahan antar rekening.'])
for col, w in zip('ABCDEFGHIJKL', [26, 16, 16, 24, 12, 20, 20, 12, 22, 22, 18, 18]): ws.column_dimensions[col].width = w
# --- Transaksi bank belum di CPJ
mb = [b for b in deb if b['date'].startswith(f'2026-{MI:02d}')]
rows = []
for b in mb:
    if FEE(b): continue
    p, note = parse(b); g = guess(note + ' ' + p)
    wkno = wk(b['date'])
    if id(b) in pairs: continue
    if HUTANG(b): act = 'Bukan CPJ (pengembalian hutang)'
    elif INTERNAL(b): act = 'Bukan CPJ (antar rekening/perusahaan sendiri)'
    elif re.search(r'istianto', b['remark'], re.I): act = 'TANYA: transfer ke Istianto tanpa kata hutang'
    elif re.search(r'maheswara aulia', b['remark'], re.I): act = 'TANYA: transfer ke Maheswara Aulia Khrisna'
    elif re.search(r'ATM|S1RH', b['remark']) and not p.startswith(('CEN', 'BRI')): act = 'TANYA: penarikan/transfer ATM'
    elif not wkno: act = 'TANYA: jatuh sebelum CPJ pertama (pekan Desember, CPJ-nya belum ada)'
    else: act = 'Tambah baris NON_CPJ'
    rows.append([b['date'], 'Mandiri', b['debit'], p, note, b['remark'][:70] if not note else '', wkno or '(sebelum jurnal pertama)', act, (g['ac'] if g else ''), (g['desc'][:35] if g else ''), 'Ya / Tidak / ubah: '])
sheet('Transaksi bank belum di CPJ', ['Tanggal', 'Bank', 'Jumlah', 'Penerima', 'Catatan transfer', 'Keterangan bank', 'Masuk jurnal', 'Usulan perlakuan', 'Usulan A/C (dari baris mirip)', 'Contoh baris CPJ mirip', 'Keputusan Anda'], rows, [12, 9, 14, 38, 38, 30, 20, 44, 14, 36, 22])
mp = [b for b in mb if id(b) in pairs]
sheet('Sudah berpasangan', ['Tanggal bank', 'Jumlah bank', 'Penerima', 'Catatan transfer', 'Jurnal', 'Baris', 'Deskripsi CPJ', 'Realisasi CPJ', 'Cara cocok'],
      [[b['date'], b['debit'], parse(b)[0], parse(b)[1], pairs[id(b)]['journal'], pairs[id(b)]['line_no'], pairs[id(b)]['desc'], round(pairs[id(b)]['real']), ('gabungan %d transfer' % group_of[id(b)]) if id(b) in group_of else ('selisih kecil' if id(b) in approx else 'persis')] for b in mp], [12, 14, 34, 34, 15, 7, 46, 14, 20])
mine = [l for l in lines if l['journal'] in {j['no'] for j in js}]
nob = [l for l in mine if l['real'] and l['flag'] != 'INCOMING' and (l['journal'], l['line_no']) not in used]
sheet('CPJ tanpa transfer bank', ['Jurnal', 'Baris', 'Tanggal', 'A/C', 'Deskripsi', 'Realisasi', 'Kanal di Excel', 'Jenis baris', 'Tertaut PR'], [[l['journal'], l['line_no'], l['date'], l['ac'], l['desc'], round(l['real']), l['text'], l['flag'], l['pr']] for l in nob], [15, 7, 12, 7, 56, 14, 14, 11, 16])
sheet('PR vs CPJ', ['Lembar PR', 'Baris Excel', 'Deskripsi', 'Jumlah', 'Status Excel', 'Masalah'],
      [[i['sheet'], i['row'], i['desc'], i['amount'], i['status_excel'], ('di CPJ tetapi PR ' + i['status']) if False else (i['note'] or ('PR ' + i['status']))] for i in qa[mon]['items'] if i['status'] in ('DRAFT', 'CANCELLED') or i['note']], [14, 10, 56, 14, 12, 40])
wb.save(out)
c = collections.Counter(r[7] for r in rows)
print(mon, 'berpasangan', len(mp), 'belum', len(rows), dict(c), 'CPJ tanpa bank', len(nob), round(sum(l['real'] for l in nob)))
