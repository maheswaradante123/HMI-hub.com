"""Workbook pemeriksaan impor: pasangan baris CPJ <-> mutasi Mandiri, debit tanpa pasangan, baris tanpa PR, status PR janggal.
Pemakaian: python3 -I qa_report.py <folder qa_*.json> <mandiri.json> <keluaran.xlsx>"""
import json, sys, re, glob, collections, datetime, openpyxl
from openpyxl.styles import Font, PatternFill
qd, mj, out = sys.argv[1:4]
MONS = ['JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN', 'JUL', 'AGU', 'SEP']
qa = {m: json.load(open(f'{qd}/qa_{m}.json')) for m in MONS}
D = lambda s: datetime.date.fromisoformat(s)
jd = {j['no']: D(j['date']) for m in MONS for j in qa[m]['journals']}
lines = [dict(l, jdate=jd[l['journal']]) for m in MONS for l in qa[m]['lines']]
items = [dict(i, mon=m) for m in MONS for i in qa[m]['items']]
bank = [b for b in json.load(open(mj)) if b['debit'] > 0]
bank.sort(key=lambda b: (b['date'], b['time']))
tok = lambda s: set(w for w in re.findall(r'[a-z]{4,}', (s or '').lower()))
FEE = lambda b: b['debit'] <= 7500 and not re.search(r'KE |CENAIDJA|BRINIDJA', b['remark'])
HUTANG = lambda b: re.search(r'peng(e|a)mbalian hutang|pengambilan hutang', b['remark'], re.I)
INTERNAL = lambda b: re.search(r'HARMONI MITRA INOVIN|pemindahan dana', b['remark'], re.I)
MAK = lambda b: re.search(r'maheswara aulia', b['remark'], re.I)
# --- pasangkan: jumlah realisasi sama persis, tanggal bank dalam [Senin-7, Senin+14], satu-satu
by_amt = collections.defaultdict(list)
for l in lines:
    if l['real'] and l['flag'] != 'INCOMING': by_amt[round(l['real'])].append(l)
used = set(); pairs = {}
for b in bank:
    if FEE(b) or HUTANG(b) or INTERNAL(b): continue
    bd = D(b['date']); best = None
    for l in by_amt.get(round(b['debit']), []):
        k = (l['journal'], l['line_no'])
        if k in used: continue
        dd = (bd - l['jdate']).days
        if not (-7 <= dd <= 14): continue
        sc = (-len(tok(l['desc']) & tok(b['remark'])), abs(dd - 3))
        if best is None or sc < best[0]: best = (sc, l, k)
    if best: used.add(best[2]); pairs[id(b)] = best[1]
matched = [b for b in bank if id(b) in pairs]
unm = [b for b in bank if id(b) not in pairs and not FEE(b) and not HUTANG(b) and not INTERNAL(b) and D(b['date']) <= datetime.date(2026, 9, 18)]
unm_after = [b for b in bank if id(b) not in pairs and not FEE(b) and not HUTANG(b) and not INTERNAL(b) and D(b['date']) > datetime.date(2026, 9, 18)]
nobank = [l for l in lines if l['real'] and l['flag'] != 'INCOMING' and (l['journal'], l['line_no']) not in used]
wb = openpyxl.Workbook()
def sheet(name, head, rows, widths):
    ws = wb.create_sheet(name); ws.append(head)
    for c in ws[1]: c.font = Font(bold=True); c.fill = PatternFill('solid', fgColor='DDDDDD')
    for r in rows: ws.append(r)
    for i, w in enumerate(widths): ws.column_dimensions[chr(65 + i)].width = w
    ws.freeze_panes = 'A2'; return ws
ws = wb.active; ws.title = 'Ringkasan'
ws.append(['Bulan', 'Jurnal', 'Baris', 'Total rencana (Rp)', 'Total realisasi (Rp)', 'Baris tertaut ke PR', '% tertaut', 'Debit Mandiri s/d 18 Sep (Rp)', 'Pasangan bank<->CPJ (baris)', 'Debit Mandiri tanpa pasangan (baris)'])
for c in ws[1]: c.font = Font(bold=True)
for i, m in enumerate(MONS, 1):
    L = [l for l in lines if l['journal'] in {j['no'] for j in qa[m]['journals']}]
    bm = [b for b in bank if b['date'].startswith(f'2026-{i:02d}') and not FEE(b) and not HUTANG(b)]
    ws.append([m, len(qa[m]['journals']), len(L), round(sum(l['plan'] for l in L if l['flag'] != 'INCOMING')), round(sum(l['real'] for l in L if l['flag'] != 'INCOMING')),
               sum(1 for l in L if l['pr']), round(100 * sum(1 for l in L if l['pr']) / len(L)), round(sum(b['debit'] for b in bm)),
               sum(1 for b in bm if id(b) in pairs), sum(1 for b in bm if id(b) not in pairs)])
for col, w in zip('ABCDEFGHIJ', [8, 8, 8, 20, 20, 12, 10, 24, 22, 24]): ws.column_dimensions[col].width = w
sheet('Tanggal jurnal', ['Jurnal', 'Tanggal jurnal (usulan)', 'Tanggal di header Excel', 'Nomor di header Excel', 'Baris', 'Tertaut PR', 'Total rencana', 'Total realisasi (baris)', 'Total realisasi menurut ringkasan Excel'],
      [[j['no'], j['date'], j['hdr_date'], j['hdr_no'], j['lines'], j['linked'], round(j['plan_total']), round(j['real_total']), j['sheet_summary'].get('realisasi uang keluar')] for m in MONS for j in qa[m]['journals']], [16, 20, 20, 22, 8, 10, 16, 20, 26])
sheet('Debit bank tanpa pasangan', ['Tanggal', 'Jumlah', 'Keterangan bank', 'Keterangan (catatan)'],
      [[b['date'], b['debit'], b['remark'], 'Maheswara Aulia Khrisna - tentukan masuk CPJ atau tidak' if MAK(b) else ('Istianto tanpa kata hutang - cek' if re.search('istianto', b['remark'], re.I) else '')] for b in unm], [12, 16, 110, 50])
sheet('Debit bank 19 Sep - 14 Nov', ['Tanggal', 'Jumlah', 'Keterangan bank'], [[b['date'], b['debit'], b['remark']] for b in unm_after], [12, 16, 110])
sheet('Pasangan bank-CPJ', ['Tanggal bank', 'Jumlah', 'Keterangan bank', 'Jurnal', 'Baris', 'Deskripsi CPJ'], [[b['date'], b['debit'], b['remark'], pairs[id(b)]['journal'], pairs[id(b)]['line_no'], pairs[id(b)]['desc']] for b in matched], [12, 16, 90, 16, 7, 50])
sheet('CPJ tanpa PR', ['Jurnal', 'Baris', 'Tanggal', 'A/C', 'Deskripsi', 'Rencana', 'Realisasi', 'Jenis baris', 'Catatan Excel'],
      [[l['journal'], l['line_no'], l['date'], l['ac'], l['desc'], round(l['plan']), round(l['real']), l['flag'], l['text']] for l in lines if not l['pr'] and l['plan']], [16, 7, 12, 7, 60, 14, 14, 11, 12])
sheet('CPJ real. tanpa pasangan bank', ['Jurnal', 'Baris', 'Tanggal', 'Deskripsi', 'Realisasi', 'Catatan Excel (kanal)'],
      [[l['journal'], l['line_no'], l['date'], l['desc'], round(l['real']), l['text']] for l in nobank], [16, 7, 12, 60, 14, 14])
sheet('Status PR janggal', ['Lembar PR', 'Baris Excel', 'Deskripsi', 'Jumlah', 'Status Excel', 'Status di aplikasi', 'Catatan'],
      [[i['sheet'], i['row'], i['desc'], i['amount'], i['status_excel'], i['status'], i['note']] for i in items if i['status'] in ('DRAFT', 'CANCELLED') or i['note']], [14, 10, 60, 14, 12, 14, 40])
# item PR approved/received/closed tetapi tidak ada di baris CPJ mana pun
linked = {l['pr'] for l in lines if l['pr']}
sheet('PR disetujui tanpa CPJ', ['Lembar PR', 'Baris Excel', 'Deskripsi', 'Jumlah', 'Status'],
      [[i['sheet'], i['row'], i['desc'], i['amount'], i['status']] for i in items if i['status'] in ('APPROVED', 'RECEIVED', 'CLOSED', 'ORDERED') and f"{i['sheet']}#{i['row']}" not in linked], [14, 10, 60, 14, 12])
wb.save(out)
print('pasangan', len(matched), 'debit tanpa pasangan', len(unm), 'setelah 18 Sep', len(unm_after), 'CPJ tanpa bank', len(nobank))
for m in wb.sheetnames: print(m, wb[m].max_row - 1)
