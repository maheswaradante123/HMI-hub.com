#!/usr/bin/env python3
"""Membuat supabase/data/migrasi_ro_po.sql dari hasil baca PDF RO & Production Order lama (Google Sheets).
Pemakaian: python3 scripts/gen_ro_po.py <ro_norm.json> <po_uniq.json> <keluaran.sql>
Aturan pemetaan ada di bagian atas file ini; hal yang perlu dicek manusia dicetak sebagai CATATAN di akhir."""
import json, re, sys, collections

RO_FILE, PO_FILE, OUT = sys.argv[1:4]
MONTHS = {m: i + 1 for i, names in enumerate([
    ["januari", "january", "jan"], ["februari", "february", "feb"], ["maret", "march", "mar"], ["april", "apr"],
    ["mei", "may"], ["juni", "june", "jun"], ["juli", "july", "jul"], ["agustus", "august", "agu", "aug"],
    ["september", "sep"], ["oktober", "october", "okt", "oct"], ["november", "nov"], ["desember", "december", "des", "dec"]]) for m in names}
CATATAN = []

def parse_dates(s):
    """Semua tanggal dalam teks seperti '30 Desember 2025, 01 & 03 Januari 2026' (bulan/tahun berlaku mundur)."""
    if not s: return []
    toks = re.findall(r"\d{4}|\d{1,2}|[A-Za-z]+", s)
    out, pend = [], []
    for t in toks:
        if re.fullmatch(r"\d{1,2}", t): pend.append(int(t))
        elif t.lower() in MONTHS and pend:
            mon = MONTHS[t.lower()]; out.append(["m", pend, mon]); pend = []
        elif re.fullmatch(r"\d{4}", t) and out and out[-1][0] == "m":
            out[-1] = ["y", out[-1][1], out[-1][2], int(t)]
    res = []
    for o in out:
        if o[0] == "y":
            for d in o[1]: res.append(f"{o[3]:04d}-{o[2]:02d}-{d:02d}")
    return res

def first_date(s):
    d = parse_dates(s)
    return d[0] if d else None

def norm_time(w):
    m = re.match(r"\s*(\d{1,2})[:.](\d{2})", w or "")
    return f"{int(m.group(1)):02d}:{m.group(2)}" if m and int(m.group(1)) < 24 else None

def clean(s):
    s = re.sub(r"\s+", " ", s or "").strip()
    return s if s and s != "-" else None

# ---------------------------------------------------------------- pelanggan
CUST = {
    "HABITARE": dict(code="HBR", name="Habitare Apart Hotel Rasuna Jakarta", type="HOREKA", term=30, like=["%habitare%"]),
    "ALANA": dict(code="ALN", name="The Alana Hotel & Conference Center", type="HOREKA", term=30, like=["%alana%"]),
    "RAYA_BOGA": dict(code="RBC", name="Raya Boga Catering", type="HOREKA", term=30, like=["%raya boga%"]),
    "HARPER": dict(code="HPR", name="Harper MT Haryono", type="HOREKA", term=30, like=["%harper%"]),
}
def cust_code(name):
    base = re.sub(r"\(.*?\)", "", name)
    base = re.sub(r"\b(bapak|ibu)\b", lambda m: "BPK" if m.group(1).lower() == "bapak" else "IBU", base, flags=re.I)
    return re.sub(r"[^A-Z0-9]+", "-", base.upper()).strip("-")[:24]

# ---------------------------------------------------------------- produk
DATE_PAREN = re.compile(r"\s*\(([^()]*\d{4}[^()]*)\)\s*$")
def split_product(raw):
    raw = (raw or "").strip()
    m = DATE_PAREN.search(raw)
    note = None
    if m:
        note = "Kirim: " + m.group(1).strip(); raw = raw[:m.start()].strip()
    return raw, note

def canon(name):
    n = re.sub(r"\s+", " ", name.replace(";", "l")).strip() if name == "Oxtai;" else re.sub(r"\s+", " ", name).strip()
    k = n.lower()
    m = re.fullmatch(r"(beef )?cl ?(\d+)", k)
    if m: return f"Beef CL {m.group(2)}"
    if k == "beef cl": return "Beef CL"
    m = re.fullmatch(r"tetelan cl ?(\d+)", k)
    if m: return f"Tetelan CL {m.group(1)}"
    table = {"lidah": "Lidah Sapi", "lidah sapi": "Lidah Sapi", "oxtail (buntut)": "Oxtail", "iga sapi": "Iga",
             "paru sapi bersih": "Paru Bersih", "paru sapi mentah": "Paru Mentah", "tulang sum-sum": "Tulang Sumsum",
             "babat sapi": "Babat", "tulang sumsum": "Tulang Sumsum"}
    return table.get(k, n)

def category(name):
    k = name.lower()
    if k in ("ongkir",) or k.startswith("ongkos"): return None
    if "tulang" in k or "short ribs" in k or k.startswith("iga"): return "Tulang"
    if any(w in k for w in ("babat", "usus", "lidah", "paru", "jeroan")): return "Jeroan"
    return "Daging"

def product_meta(name):
    k = name.lower()
    if k == "ongkir" or k.startswith("ongkos"): return dict(type="SUPPORTING", unit="LS", cat=None)
    if "satu ekor" in k: return dict(type="MANUFACTURE", unit="EKOR", cat="Daging")
    return dict(type="MANUFACTURE", unit="GRAM", cat=category(name))

PACK = {"vacuum 4 kg": "Vacuum 4 Kg", "pack per 4 kg": "Vacuum 4 Kg", "vaccum 4kg": "Vacuum 4 Kg", "vaccum4kg": "Vacuum 4 Kg", "vaccum 4kg": "Vacuum 4 Kg",
        "vacuum 1 kg": "Vacuum 1 Kg", "pack 1 kg": "Vacuum 1 Kg", "vacuum 3 kg": "Vacuum 3 Kg", "wrap": "Wrap", "tray + wrap": "Tray + Wrap",
        "wrap + vacuum": "Wrap + Vacuum 4 Kg", "wrap + vacuum 4 kg": "Wrap + Vacuum 4 Kg", "vacuum 4 kg, pack 1 kg": "Vacuum 4 Kg",
        "tray + wrap / vacuum 4 kg": "Tray + Wrap", "vacuum 4 kg / wrap": "Wrap + Vacuum 4 Kg"}
def pack(raw):
    raw = clean(raw)
    if not raw: return None, None
    mapped = PACK.get(re.sub(r"\s+", " ", raw).lower())
    note = None if mapped and mapped.lower() == raw.lower() else f"Pengemasan di dokumen: {raw}"
    return mapped, note

def qty_of(q, unit):
    if q is None: return None
    v = float(str(q).replace(",", "."))
    return v / 1000 if (unit or "").lower() == "g" else v

def money(s):
    t = re.sub(r"[^\d]", "", str(s)) if s is not None else ""
    return int(t) if t else 0

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
    pos.append(dict(no=no, ro=ro, od=od, nd=nd, n="; ".join(notes) or None, sn=clean(p["jadwal"]), ad=clean(p["alamat"]),
                    pic=clean(p["pic"]), cow=cow, it=items))
    if len({(i["p"], i["q"], i["cut"]) for i in items}) < len(items):
        CATATAN.append(f"{no}: ada baris yang persis sama (ganda di dokumen asli); dipertahankan")

ro_of_po = collections.Counter(p["ro"] for p in pos if p["ro"])
for r, n in ro_of_po.items():
    if n > 1: CATATAN.append(f"{r}: punya {n} Production Order (aturan 'satu RO satu PO aktif' dilewati saat migrasi)")
for p in pos:
    if p["od"] is None: raise SystemExit(f"{p['no']}: tanggal publish tidak terbaca")

data = dict(customers=list(customers.values()), products=[dict(name=k, **v) for k, v in sorted(products.items())], ros=ros, pos=pos)
js = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("$json$", "")
sql = open(__file__.replace("gen_ro_po.py", "gen_ro_po.tpl.sql")).read().replace("/*DATA*/", js)
open(OUT, "w").write(sql)
print(f"RO {len(ros)} ({sum(len(r['it']) for r in ros)} baris), PO {len(pos)} ({sum(len(p['it']) for p in pos)} baris), produk {len(products)}, pelanggan {len(customers)}, ukuran {len(sql)//1024} KB")
for c in CATATAN: print("CATATAN:", c)
