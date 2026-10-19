#!/usr/bin/env python3
"""Membuat supabase/data/migrasi_ro_po.sql dari hasil baca PDF RO & Production Order lama (Google Sheets).
Pemakaian: python3 scripts/gen_ro_po.py <ro_norm.json> <po_uniq.json> <keluaran.sql>
Aturan pemetaan ada di bagian atas file ini; hal yang perlu dicek manusia dicetak sebagai CATATAN di akhir."""
import json, re, sys, collections

RO_FILE, PO_FILE, OUT = sys.argv[1:4]
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ropo_lib import *
CATATAN = []

# ---------------------------------------------------------------- RO
ros_raw = json.load(open(RO_FILE))
products = {}
customers = collections.OrderedDict()
ros = []
seen_no = set()
for o in sorted(ros_raw, key=lambda x: (first_date(x["tanggal"]) or "")):
    no = o["no"]
    assert no not in seen_no, f"nomor RO ganda {no}"; seen_no.add(no)
    if o["src"] in CUST: c = CUST[o["src"]]; key = c["code"]
    else:
        nm = re.sub(r"\s+", " ", o["pemesan"]).strip(); c = dict(code=cust_code(nm), name=nm, type="OTHER", term=0, like=[]); key = c["code"]
    if key not in customers:
        customers[key] = dict(c, address=clean(o["alamat"]), phone=clean(o["telp"]))
    od = first_date(o["tanggal"]); alld = parse_dates(o["tgl_kirim"]); dd = alld[0] if alld else None
    notes = []
    if clean(o["catatan"]): notes.append(clean(o["catatan"]))
    if len(alld) > 1: notes.append("Tanggal kirim di dokumen: " + re.sub(r"\s+", " ", o["tgl_kirim"]))
    if dd and od and dd < od:
        CATATAN.append(f"{no}: tanggal kirim {dd} lebih awal dari tanggal order {od}; tanggal kirim dikosongkan (teks asli di catatan)")
        notes.append("Tanggal kirim di dokumen: " + o["tgl_kirim"]); dd = None
    tm = norm_time(o["waktu"])
    w = clean(o["waktu"])
    if w and (tm is None or len(w) > 9 and not re.fullmatch(r"\d{1,2}[:.]\d{2} WIB", w)): notes.append("Waktu kirim di dokumen: " + w)
    ck = [x for x in o["centang"]]
    pay_txt = [x for x in ck if not re.search(r"delivery$|pick ?up", x, re.I) or re.search(r"cash before delivery|cash on delivery", x, re.I)]
    low = " | ".join(pay_txt).lower()
    if "tempo" in low: payment = "Tempo"
    elif "transfer" in low or "cash before delivery" in low: payment = "Transfer"
    elif "cash" in low or "tunai" in low or "cod" in low: payment = "Cash"
    else: payment = None
    if len(pay_txt) > 1 and "tempo" in low and ("cash" in low or "transfer" in low):
        CATATAN.append(f"{no}: dua metode bayar tercentang ({' + '.join(pay_txt)}); dipakai Tempo")
    if pay_txt and pay_txt != ["Tempo (30 Hari)"]: notes.append("Pembayaran di dokumen: " + ", ".join(pay_txt))
    if payment is None: CATATAN.append(f"{no}: metode bayar tidak terbaca")
    delivery = "Pick Up di Toko" if any(re.search(r"pick ?up", x, re.I) for x in ck) else "Delivery"
    items = []
    for it in o["items_n"]:
        name, dnote = split_product(it["produk"]); cn = canon(name)
        products.setdefault(cn, product_meta(cn))
        unit = (it["satuan"] or "").lower()
        q = qty_of(it["qty"], unit)
        pk, pnote = pack(it["kemas"])
        inotes = [x for x in [dnote, pnote, clean(it.get("ket")), f"Qty di dokumen: {int(it['qty'])} g" if unit == "g" else None] if x]
        if q is None or q <= 0: CATATAN.append(f"{no}: baris {it['no']} {name} qty tidak valid"); continue
        items.append(dict(p=cn, q=round(q, 3), pr=it["harga"] or 0, cut=clean(it["potong"]), pk=pk, n="; ".join(inotes) or None))
        if not it["harga"]: CATATAN.append(f"{no}: {name} tanpa harga (diisi 0)")
    ros.append(dict(no=no, c=key, od=od, dd=dd, n="; ".join(notes) or None, on=clean(re.sub(r"Cen$", "Center", o["pemesan"])),
                    ph=clean(o["telp"]), ad=clean(o["alamat"]), tm=tm, pay=payment, dm=delivery, it=items))

# ---------------------------------------------------------------- PO
pos_raw = json.load(open(PO_FILE))
ro_nos = {r["no"] for r in ros}
cnt = collections.Counter(p["no"] for p in pos_raw)
used = collections.Counter()
pos = []
for p in pos_raw:
    no = p["no"]
    if cnt[no] > 1:
        used[no] += 1; no = f"{no}-{'AB'[used[no]-1]}"
        CATATAN.append(f"{p['no']}: nomor dipakai dua PO berbeda; dibedakan menjadi {no}")
    od = first_date(p["publish"]) or first_date(p["order_date"])
    nd = first_date(p["delivery"]) or first_date(p["jadwal"])
    notes = []
    if clean(p["note"]): notes.append(clean(p["note"]))
    ro = p["ro"] if p["ro"] in ro_nos else None
    if p["ro"] and not ro:
        notes.append(f"RO asal: {p['ro']} (tidak ada di arsip RO yang dimigrasi)" + (f", customer: {p['customer']}" if p.get("customer") else ""))
        CATATAN.append(f"{no}: RO {p['ro']} tidak ada di arsip; PO tanpa tautan RO")
    if nd and od and nd < od:
        notes.append("Tanggal kirim di dokumen: " + p["delivery"]); CATATAN.append(f"{no}: tanggal kirim {nd} lebih awal dari tanggal publish {od}; dikosongkan"); nd = None
    cow = clean(p["kode_sapi"])
    if cow and cow.startswith("*Dokumen"): cow = None
    items = []
    for it in p["items"]:
        name, dnote = split_product(it["Nama Produk"]); cn = canon(name)
        products.setdefault(cn, product_meta(cn))
        unit = (it["Satuan"] or "").lower()
        qnote = None
        if not re.fullmatch(r"\d+([.,]\d+)?", it["Qty"] or ""):
            qnote = f"Jumlah di dokumen: {it['Qty']} (bukan angka); diisi 1 kg sebagai penanda"; q = 1.0
            CATATAN.append(f"{no}: {name} jumlah '{it['Qty']}' bukan angka; diisi 1")
        else: q = qty_of(it["Qty"], unit)
        pk, pnote = pack(it["Jenis Pengemasan"])
        inotes = [x for x in [dnote, qnote, pnote, f"Qty di dokumen: {it['Qty']} g" if unit == "g" else None] if x]
        if q is None or q <= 0: CATATAN.append(f"{no}: {name} qty tidak valid"); continue
        items.append(dict(p=cn, q=round(q, 3), cut=clean(it["Jenis Potongan"]), pk=pk, n="; ".join(inotes) or None))
    pos.append(dict(ds=sorted(set(parse_dates(p["delivery"]) + parse_dates(p["jadwal"]))), no=no, ro=ro, od=od, nd=nd, n="; ".join(notes) or None, sn=clean(p["jadwal"]), ad=clean(p["alamat"]),
                    pic=clean(p["pic"]), cow=cow, it=items))
    if len({(i["p"], i["q"], i["cut"]) for i in items}) < len(items):
        CATATAN.append(f"{no}: ada baris yang persis sama (ganda di dokumen asli); dipertahankan")

ro_of_po = collections.Counter(p["ro"] for p in pos if p["ro"])
for r, n in ro_of_po.items():
    if n > 1: CATATAN.append(f"{r}: punya {n} Production Order (aturan 'satu RO satu PO aktif' dilewati saat migrasi)")
for p in pos:
    if p["od"] is None: raise SystemExit(f"{p['no']}: tanggal publish tidak terbaca")

data = dict(customers=list(customers.values()), products=[dict(name=k, **v) for k, v in sorted(products.items())], ros=ros, pos=pos)
if len(sys.argv) > 4: json.dump(data, open(sys.argv[4], "w"), ensure_ascii=False)   # dipakai gen_pl_do.py untuk menautkan PL ke RO/PO
data["pos"] = [{k: v for k, v in p.items() if k != "ds"} for p in pos]
js = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("$json$", "")
sql = open(__file__.replace("gen_ro_po.py", "gen_ro_po.tpl.sql")).read().replace("/*DATA*/", js)
open(OUT, "w").write(sql)
print(f"RO {len(ros)} ({sum(len(r['it']) for r in ros)} baris), PO {len(pos)} ({sum(len(p['it']) for p in pos)} baris), produk {len(products)}, pelanggan {len(customers)}, ukuran {len(sql)//1024} KB")
for c in CATATAN: print("CATATAN:", c)
