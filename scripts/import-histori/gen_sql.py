"""Buat skrip SQL impor histori CPJ + PR per bulan dari JSON hasil parse_cpj.py dan parse_pr.py.

Pemakaian:
  python3 -I gen_sql.py <cpj_raw.json> <pr_raw.json> <folder keluaran> [bulan ...]
Bulan: JAN FEB MAR APR MEI JUN JUL AGU SEP (kosong = semua). Keluaran: impor_<bulan>.sql dan qa_<bulan>.json.

Aturan (disepakati dengan pemilik):
- Nomor dokumen eksplisit: CPJ-NNN-<romawi bulan file>-26 sesuai nama lembar; PR-NNN-<romawi>-26 sesuai nama lembar.
- Baris jurnal diambil dari lembar R-CPJ (lembar realisasi = rencana + baris tambahan). Langsung berstatus REALIZED.
- Tanggal jurnal = hari Senin pada/setelah tanggal item dominan di lembar CPJ rencana.
- Status PR apa adanya (Approved->APPROVED, closed->CLOSED, ...). A/C GA dipetakan ke RT.
- Skrip menolak jalan bila nomor dokumen sudah ada (aman dijalankan ulang).
"""
import json, sys, re, uuid, datetime, collections, os

ROMAN = {'JAN': 'I', 'FEB': 'II', 'MAR': 'III', 'APR': 'IV', 'MEI': 'V', 'JUN': 'VI', 'JUL': 'VII', 'AGU': 'VIII', 'SEP': 'IX'}
PRFILE = {'JAN': 'JANUARI', 'FEB': 'FEBRUARI', 'MAR': 'MARET', 'APR': 'APRIL', 'MEI': 'MEI', 'JUN': 'JUNI', 'JUL': 'JULI', 'AGU': 'AGUSTUS', 'SEP': 'SEPTEMBER'}
NS = uuid.UUID('6f1c2d9a-0b0e-4d0e-9a55-3a1f4a7c2e11')
STATUS = {'approved': 'APPROVED', 'closed': 'CLOSED', 'received': 'RECEIVED', 'draft': 'DRAFT', 'cancel': 'CANCELLED', 'order': 'ORDERED',
          'on delivery': 'ORDERED', 'move': 'CANCELLED', None: 'DRAFT'}
FLAG = {'FF00FFFF': 'INCOMING', 'FFFF9900': 'OVER', 'FFFFFF00': 'NON_CPJ', 'FFFF0000': 'REJECTED', 'FFF9CB9C': 'OVER'}
CHANNEL = {'cash': 'cash', 'pc': 'cash', '(pc)': 'cash', 'kopra': 'KOPRA', 'tf': 'tf', 'offline': 'offline', 'shopee': 'tf'}
PAYNOTE = 'Tf Mandiri 1290015674415 HARMONI MITRA INOVINDO'
TITLE = re.compile(r'^\s*(PC-)?(R-)?CPJ-(\d{3})-([IVX]+)-(\d{2})[\s\.]*$', re.I)


USED = set()  # item PR yang sudah tertaut (dibawa antarbulan: pekan pertama boleh memakai lembar PR terakhir bulan lalu)


def uid(*p): return str(uuid.uuid5(NS, '|'.join(map(str, p))))
def q(s):
    if s is None: return 'null'
    return "'" + str(s).replace("'", "''") + "'"
def n(x, d=2):
    if x is None: return 'null'
    return repr(round(float(x), d)) if float(x) != int(float(x)) else str(int(float(x)))
def norm(s): return re.sub(r'[^a-z0-9]+', ' ', (s or '').lower()).strip()
def d2(s): return datetime.date.fromisoformat(s) if s else None
def next_monday(d):
    """Senin pekan berjalan bila tanggal Senin-Rabu, selain itu Senin berikutnya (PR biasanya Jumat, CPJ Senin)."""
    if d.weekday() <= 2: return d - datetime.timedelta(days=d.weekday())
    return d + datetime.timedelta(days=(7 - d.weekday()) % 7)
def mapac(a): return 'RT' if (a or '').upper() == 'GA' else (a or '').upper() or None


def modal_date(items, key='date'):
    c = collections.Counter(i[key] for i in items if i.get(key))
    return d2(c.most_common(1)[0][0]) if c else None


def build(cpj, pr, mon, prev_date=None):
    """Kembalikan (journals, sheets, qa) untuk satu bulan."""
    rom = ROMAN[mon]
    # --- lembar PR bulan ini
    sheets = {}
    for k, v in pr.items():
        f, t = k.split('|')
        if f != PRFILE[mon]: continue
        m = re.match(r'PR-(\d{3})-([IVX]+)-(\d{2})', t.strip())
        sheets[int(m.group(1))] = dict(no=f'PR-{m.group(1)}-{m.group(2)}-{m.group(3)}', raw=v, nnn=int(m.group(1)))
    for s in sheets.values():
        s['date'] = modal_date(s['raw']['items']) or d2(s['raw']['hdr_date'])
        s['id'] = uid('PR', s['no'])
        for i, it in enumerate(s['raw']['items'], 1):
            it['line_no'] = i
            it['id'] = uid('PRI', s['no'], i)
    # --- lembar CPJ bulan ini
    plan, real = {}, {}
    for k, v in cpj.items():
        f, t = k.split('|')
        if f != mon: continue
        m = TITLE.match(t)
        if not m: continue
        (real if m.group(2) else plan)[(int(m.group(3)), bool(m.group(1)))] = v
    journals = []
    for (nnn, pc), v in sorted(real.items()):
        if pc: continue  # lembar PC- (rincian Petty Cash) ditangani terpisah
        p = plan.get((nnn, False))
        ps = sheets.get(nnn)
        dt = (ps['date'] if ps else None) or (modal_date(p['lines']) if p else None) or modal_date(v['lines']) or d2(v['hdr_date'])
        jd = next_monday(dt) if dt else None
        no = f'CPJ-{nnn:03d}-{rom}-26'
        journals.append(dict(no=no, nnn=nnn, id=uid('JCP', no), date=jd, plan=p, real=v, plan_modal=dt))
    # Irama mingguan murni: jurnal ke-1 = Senin 5 Jan 2026, lalu tiap 7 hari (38 pekan sampai 21 Sep) - cocok dengan nomor lembar
    # tiap bulan (4,4,5,4,4,4,5,4,4). Lembar PR = Jumat sebelumnya (3 hari sebelum jurnal). Tanggal di header Excel sering basi.
    prev = prev_date
    for j in journals:
        j['date'] = (prev + datetime.timedelta(days=7)) if prev else datetime.date(2026, 1, 5)
        prev = j['date']
        ps = sheets.get(j['nnn'])
        if ps: ps['date'] = j['date'] - datetime.timedelta(days=3)
    return journals, sheets


def link_items(journals, sheets, prev_sheets):
    """Cocokkan baris jurnal ke item PR: deskripsi+jumlah sama persis dulu, lalu deskripsi saja di lembar yang sama."""
    used = USED
    pool_by = {}
    for s in list(sheets.values()) + list(prev_sheets.values()): pool_by[s['no']] = s
    res = {}
    for j in journals:
        cand = [s for s in sheets.values() if s['nnn'] in (j['nnn'], j['nnn'] - 1)]
        if j['nnn'] == 1: cand += list(prev_sheets.values())
        cand = sorted(cand, key=lambda s: (s['nnn'] != j['nnn'], -s['nnn']))
        plankeys = collections.Counter((norm(l['desc']), round(l['amount'] or 0)) for l in (j['plan']['lines'] if j['plan'] else []))
        for pass_ in (1, 2):
            for l in j['real']['lines']:
                if (j['id'], l['row']) in res: continue
                nd = norm(l['desc']); am = round(l['amount'] or 0)
                if pass_ == 2 and not plankeys.get((nd, am)) and not any(k[0] == nd for k in plankeys): continue
                for s in cand:
                    hit = None
                    for it in s['raw']['items']:
                        if it['id'] in used or norm(it['desc']) != nd: continue
                        if pass_ == 1 and round(it['amount'] or 0) != am: continue
                        hit = it; break
                    if hit:
                        used.add(hit['id']); res[(j['id'], l['row'])] = (hit, s, pass_); break
    return res


def gen(cpj, pr, mon, prev_sheets, prev_date=None):
    journals, sheets = build(cpj, pr, mon, prev_date)
    links = link_items(journals, sheets, prev_sheets)
    out = []
    qa = dict(month=mon, journals=[], lines=[], items=[])
    A = out.append
    A(f'-- Impor histori CPJ & PR bulan {mon} 2026 (dibuat otomatis oleh scripts/import-histori/gen_sql.py)')
    A('-- Jalankan sekali di Supabase SQL Editor. Aman: berhenti bila nomor dokumen sudah ada. Semua dalam satu transaksi.')
    A('do $imp$')
    A('declare v_uid uuid;')
    A('begin')
    A("  select up.id into v_uid from public.user_profiles up join public.roles r on r.id = up.role_id where r.is_superuser and up.is_active order by up.created_at limit 1;")
    A("  if v_uid is null then raise exception 'Tidak ada pengguna superuser aktif untuk dijadikan pemohon'; end if;")
    nos = [s['no'] for s in sheets.values()]
    jnos = [j['no'] for j in journals]
    A(f"  if exists (select 1 from public.purchase_requests where doc_number in ({','.join(q(x) for x in nos)})) then raise exception 'Lembar PR bulan {mon} sudah ada, impor dibatalkan'; end if;")
    A(f"  if exists (select 1 from public.cash_journals where doc_number in ({','.join(q(x) for x in jnos)})) then raise exception 'Jurnal CPJ bulan {mon} sudah ada, impor dibatalkan'; end if;")
    # --- PR
    for s in sorted(sheets.values(), key=lambda s: s['nnn']):
        A(f"  insert into public.purchase_requests (id, doc_number, request_date, requester_id, reason, status, created_by, updated_by) values ({q(s['id'])}, {q(s['no'])}, {q(s['date'])}, v_uid, 'Impor histori dari Excel', 'OPEN', v_uid, v_uid);")
        rows, hist = [], []
        for it in s['raw']['items']:
            st = STATUS.get((it['status'] or '').strip().lower() or None, 'DRAFT')
            qty = it['qty']; price = it['price']; amt = it['amount']; note = []
            if not qty or qty <= 0:
                note.append('qty kosong/0 di Excel'); price = amt if amt else (price or 0); qty = 1
            ch = None
            idate = it['date'] or str(s['date'])
            ac = mapac(it['ac']) or 'OPR'
            if ac not in ('OPR', 'RT', 'MKT', 'TOKO'): ac = 'OPR'; note.append(f"A/C Excel '{it['ac']}'")
            if it['ac'] == 'GA': note.append('A/C Excel GA')
            if (it['status'] or '').strip().lower() in ('move', 'on delivery'): note.append(f"Status Excel: {it['status']}")
            it['_st'] = st; it['_note'] = note
            rows.append(f"({q(it['id'])},{q(s['id'])},{it['line_no']},{q(it['desc'])},{n(qty,3)},{q(it['unit'])},{n(price)},{q(ac)},{q((it['code'] or 'BP').upper())},'tf',{q(idate)},v_uid,{q(st)},{q('; '.join(note) or None)})")
            hist.append(f"({q(s['id'])},{q(it['id'])},null,{q(st)},'Impor histori dari Excel',v_uid,{q(idate + ' 09:00+07')})")
            qa['items'].append(dict(sheet=s['no'], row=it['row'], desc=it['desc'], amount=amt, status_excel=it['status'], status=st, note='; '.join(note)))
        if rows:
            A('  insert into public.pr_items (id, pr_id, line_no, item_name, qty, unit, estimated_price, ac, code, pay_method, item_date, requester_id, status, notes) values')
            A('   ' + ',\n   '.join(rows) + ';')
            A('  insert into public.pr_status_history (pr_id, item_id, from_status, to_status, note, changed_by, changed_at) values')
            A('   ' + ',\n   '.join(hist) + ';')
    # --- CPJ
    for j in sorted(journals, key=lambda j: j['nnn']):
        v = j['real']
        A(f"  insert into public.cash_journals (id, doc_number, journal_date, approver_name, approver_title, pay_note, notes, approved_on, realized_on, status, created_by, updated_by) values ({q(j['id'])}, {q(j['no'])}, {q(j['date'])}, 'Ahmad Hunain', 'Finance Director', {q(PAYNOTE)}, {q('Impor histori dari Excel (lembar R-CPJ-' + f'{j['nnn']:03d}' + ')')}, {q(j['date'])}, {q(j['date'] + datetime.timedelta(days=6))}, 'REALIZED', v_uid, v_uid);")
        rows = []; prev_ac = None; no = 0; lk = 0
        for l in v['lines']:
            no += 1
            ac = mapac(l['ac']) or prev_ac or 'OPR'; prev_ac = ac
            price = l['price']; qty = l['qty']; amt = l['amount']
            if price is None: price = amt if amt is not None else 0; qty = qty if qty is not None else 1
            if qty is None: qty = 1
            if l['rprice'] is None and l['rqty'] is None:
                rp, rq = (l['ramount'], 1) if l['ramount'] else (0, 0)
            else:
                rp, rq = (l['rprice'] or 0), (l['rqty'] if l['rqty'] is not None else 1)
            flag = FLAG.get(l['fill'] or '', 'NONE')
            proof = l['proof'] if (l['proof'] or '').startswith('http') else None
            text = None if proof or not l['proof'] else str(l['proof']).strip().lower()
            link = links.get((j['id'], l['row']))
            pid = link[0]['id'] if link else None
            if link and text in CHANNEL: link[0]['_pay'] = CHANNEL[text]
            if link and text: link[0]['_note'].append(f'CPJ: {text}')
            if link: lk += 1
            rows.append(f"({q(uid('JCPL', j['no'], no))},{q(j['id'])},{no},{q(l['date'])},{q(ac)},{q((l['code'] or '').upper() or None)},{q(l['desc'])},{n(price)},{n(qty,3)},{q(l['unit'])},{q(flag)},{q(pid)},{n(rp)},{n(rq,3)},{q(proof)})")
            ra = (rp or 0) * (rq or 0)
            qa['lines'].append(dict(journal=j['no'], line_no=no, row=l['row'], date=l['date'], ac=ac, desc=l['desc'], plan=(price or 0) * (qty or 0), plan_excel=amt,
                                    real=ra, real_excel=l['ramount'], flag=flag, text=text, proof=bool(proof), pr=(link[1]['no'] + '#' + str(link[0]['row']) if link else None),
                                    pr_status=(link[0]['_st'] if link else None), pass_=(link[2] if link else None), fill=l['fill']))
        A('  insert into public.cash_journal_lines (id, journal_id, line_no, trans_date, ac, code, description, price, qty, unit, flag, pr_item_id, real_price, real_qty, proof) values')
        A('   ' + ',\n   '.join(rows) + ';')
        A(f"  update public.cash_journals j set plan_hash = (select md5(coalesce(string_agg(concat_ws('|', l.line_no, l.ac, l.code, l.description, l.price, l.qty, l.unit, l.flag, l.pr_item_id), E'\\n' order by l.line_no), '')) from public.cash_journal_lines l where l.journal_id = j.id) where j.id = {q(j['id'])};")
        A(f"  insert into public.doc_status_history (doc_type, doc_id, from_status, to_status, note, changed_by, changed_at) values ('JCP',{q(j['id'])},null,'DRAFT','Impor histori dari Excel',v_uid,{q(str(j['date']) + ' 08:00+07')}),('JCP',{q(j['id'])},'DRAFT','ACC','Impor histori dari Excel',v_uid,{q(str(j['date']) + ' 09:00+07')}),('JCP',{q(j['id'])},'ACC','REALIZED','Impor histori dari Excel',v_uid,{q(str(j['date'] + datetime.timedelta(days=6)) + ' 17:00+07')});")
        pl = sum((l['amount'] or 0) for l in v['lines'])
        qa['journals'].append(dict(no=j['no'], date=str(j['date']), plan_modal=str(j['plan_modal']), lines=len(v['lines']), linked=lk, plan_total=pl,
                                   real_total=sum(x['real'] for x in qa['lines'] if x['journal'] == j['no']),
                                   sheet_summary=v['summary'], hdr_date=v['hdr_date'], hdr_no=v['hdr_no']))
    # perbarui catatan & metode bayar item PR yang tertaut (setelah tahu kanal dari lembar CPJ)
    ups = []
    for s in sheets.values():
        for it in s['raw']['items']:
            pay = it.get('_pay'); note = '; '.join(it['_note'])
            if pay or note:
                ups.append(f"({q(it['id'])},{q(pay)},{q(note or None)})")
    if ups:
        A('  update public.pr_items i set pay_method = coalesce(x.pay, i.pay_method), notes = x.note from (values')
        A('   ' + ',\n   '.join(ups))
        A('  ) as x(id, pay, note) where i.id = x.id::uuid;')
    A('end $imp$;')
    return '\n'.join(out) + '\n', qa, sheets, max(j['date'] for j in journals)


if __name__ == '__main__':
    cpj = json.load(open(sys.argv[1])); pr = json.load(open(sys.argv[2])); outdir = sys.argv[3]
    mons = sys.argv[4:] or list(ROMAN)
    os.makedirs(outdir, exist_ok=True)
    prev = {}; pd = None
    for mon in ROMAN:
        sql, qa, sheets, pd = gen(cpj, pr, mon, prev, pd)
        prev = {k: v for k, v in sheets.items() if v['nnn'] == max(sheets)}
        if mon in mons:
            open(f'{outdir}/impor_{mon}.sql', 'w').write(sql)
            json.dump(qa, open(f'{outdir}/qa_{mon}.json', 'w'), default=str, ensure_ascii=False)
            print(mon, 'jurnal', len(qa['journals']), 'baris', len(qa['lines']), 'item PR', len(qa['items']),
                  'tertaut', sum(1 for x in qa['lines'] if x['pr']))
