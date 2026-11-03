#!/usr/bin/env python3
"""Membuat supabase/data/migrasi_qurban.sql dari hasil parse_qurban_master.py.
Pemakaian: gen_qurban_master.py master.json keluaran.sql"""
import json, re, sys, datetime as dt, collections

src, out = sys.argv[1], sys.argv[2]
rows = json.load(open(src, encoding="utf-8"))
CARE_END = dt.date(2027, 5, 17)
ROMAN = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6, "VII": 7, "VIII": 8, "IX": 9, "X": 10, "XI": 11, "XII": 12}
YMS = ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10", "2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04", "2027-05"]

def num(s):
    s = re.sub(r"[^0-9.]", "", (s or "").replace(",", ""))
    return float(s) if s else None

def inv_ok(x): return x.startswith("INV") or x.startswith("PRO")

def bill_days(v, care):
    q = num(v["nilai"]) / care
    return int(round(q)) if abs(q - round(q)) < 1e-6 and round(q) > 0 else None

def days(ym, start):
    y, m = int(ym[:4]), int(ym[5:])
    first = dt.date(y, m, 1)
    last = (dt.date(y + (m == 12), m % 12 + 1, 1) - dt.timedelta(days=1))
    return max(0, (min(last, CARE_END) - max(first, start)).days + 1)

notes = []
conv = []
def note(r, msg): notes.append(f"#{r['no']} {r['cow']} {r['nama']}: {msg}")

data, seq = [], collections.defaultdict(int)
def seed(number):
    m = re.match(r"^(PRO-INV|INV)-(\d{3})-([IVX]+)-(\d{2})$", number or "")
    if m:
        kind = "PRO" if m.group(1) == "PRO-INV" else "INV"
        seq[(kind, f"20{m.group(4)}-{ROMAN[m.group(3)]:02d}")] = max(seq[(kind, f"20{m.group(4)}-{ROMAN[m.group(3)]:02d}")], int(m.group(2)))
    m = re.match(r"^SP-(JB|PL)-(\d{3})-([IVX]+)-AMF-(\d{2})$", number or "")
    if m:
        k = ("SP", f"20{m.group(4)}-{ROMAN[m.group(3)]:02d}")
        seq[k] = max(seq[k], int(m.group(2)))

for r in rows:
    w = num(r["bobot"]); harga = num(r["harga"]); care = num(r["care_hari"])
    if not w or not harga or not care or not r["tgl_mulai"] or r["tgl_mulai"].startswith("?"):
        note(r, "DILEWATI: bobot/harga/biaya perawatan/tanggal mulai tidak lengkap di sheet")
        continue
    start = dt.date.fromisoformat(r["tgl_mulai"])
    buy_date = r["tgl_beli"] if r["tgl_beli"] and not r["tgl_beli"].startswith("?") else r["tgl_mulai"]
    bp = harga / w
    buy_price = round(bp, 2)
    if abs(bp - round(bp)) > 1e-6:
        note(r, f"harga beli/kg tidak bulat ({bp:.2f}); disimpan {buy_price:.2f}/Kg, total mengikuti Rp{harga:,.0f} +/- beberapa rupiah")
    months = [(ym, r["bulan"][ym]) for ym in YMS if r["bulan"][ym]["nilai"]]
    # cek nilai tagihan = hari x tarif
    for ym, v in months:
        exp = days(ym, start) * care
        diff = num(v["nilai"]) - exp
        if abs(diff) > 1:
            if abs(diff + care) < 1 and ym == months[0][0] and ym == start.strftime("%Y-%m"):
                conv.append(r["no"])   # sheet tidak menghitung hari mulai; aplikasi menghitungnya
            else:
                note(r, f"nilai tagihan {ym} Rp{num(v['nilai']):,.0f} tidak sama dengan {days(ym, start)} hari x Rp{care:,.0f} = Rp{exp:,.0f} (dihitung aplikasi)")
    lunas = [v["status"] == "Lunas" for _, v in months]
    inv = r["inv"].strip()
    all_lunas = bool(months) and all(lunas)
    first_lunas = bool(months) and lunas[0]
    if all_lunas or first_lunas:
        status = "PAID"
    elif inv.startswith("INV") or any(v["inv"].startswith("INV") for _, v in months):
        status = "INVOICE"
    else:
        status = "PROFORMA"
    month_invs = {v["inv"] for _, v in months}
    one_invoice = bool(months) and len(month_invs) == 1 and "" not in month_invs and inv_ok(next(iter(month_invs)))
    mode = "FULL" if all_lunas or one_invoice or not months else "MONTHLY"
    if not all_lunas and not first_lunas and any(lunas):
        note(r, "ada bulan 'Lunas' tetapi bulan pertama tidak; status pesanan dibuat INVOICE (belum lunas), cek dan tandai lunas di aplikasi bila benar")
    bills = []
    if mode == "MONTHLY" and status == "PAID":
        prev_ok = True
        for i, (ym, v) in enumerate(months[1:], start=1):
            if not prev_ok:
                if v["status"] == "Lunas": note(r, f"tagihan {ym} berstatus Lunas tetapi ada bulan kosong sebelumnya; tidak dimasukkan")
                continue
            if v["status"] == "Lunas":
                bills.append({"ym": ym, "no": v["inv"] or inv or "ARSIP", "status": "PAID", "days": bill_days(v, care)})
            elif v["inv"].startswith("INV"):
                bills.append({"ym": ym, "no": v["inv"], "status": "ISSUED", "days": bill_days(v, care)})
                prev_ok = True
            else:
                prev_ok = False
    inv_no = inv if inv.startswith("INV") else ""
    pro_no = inv if inv.startswith("PRO") else ""
    for x in (inv, r["sp_jb"], r["sp_pl"]): seed(x)
    for _, v in months: seed(v["inv"])
    data.append({"cow": r["cow"], "nick": r["nama"], "start": r["tgl_mulai"], "buy_date": buy_date, "weight": w,
                 "buy_price": buy_price, "care_price": care, "mode": mode, "status": status, "discount": care if r["no"] in conv else 0, "inv_no": inv_no, "pro_no": pro_no,
                 "sp_jb": r["sp_jb"], "sp_pl": r["sp_pl"], "bills": bills})

cnt = collections.Counter((d["status"], d["mode"]) for d in data)
sql = open("scripts/gen_qurban_master.tpl.sql", encoding="utf-8").read()
sql = sql.replace("__DATA__", json.dumps(data, ensure_ascii=False)).replace(
    "__SEQ__", json.dumps([{"kind": k, "ym": ym, "n": n} for (k, ym), n in sorted(seq.items())]))
open(out, "w", encoding="utf-8").write(sql)
print(f"{len(data)} pesanan, {sum(len(d['bills']) for d in data)} tagihan bulanan")
print(dict(cnt))
print(f"Catatan umum: {len(conv)} pesanan memakai hitungan bulan pertama tanpa hari mulai (sheet) sedangkan aplikasi menghitung hari mulai: {conv}")
print("CATATAN:"); [print(" -", n) for n in notes]
