#!/usr/bin/env python3
"""Membuat supabase/data/migrasi_invoice.sql dari hasil baca PDF Invoice lama dan NoA (status bayar).
Pemakaian: python3 scripts/gen_inv.py <invoice.json> <noa.json> <keluaran.sql>
 (invoice.json dari parse_invoice_pdf.py, noa.json dari parse_noa_pdf.py.)
Hal yang perlu dicek manusia dicetak sebagai CATATAN."""
import json, re, sys, os, datetime as dt, collections, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ropo_lib import canon, product_meta, cust_code, clean

INV_FILE, NOA_FILE, OUT = sys.argv[1:4]
HERE = os.path.dirname(os.path.abspath(__file__))
CATATAN = []
raw = json.load(open(INV_FILE))
noa = json.load(open(NOA_FILE))
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
UNDATED = "2025-10-31"          # invoice seri X-25 tidak bertanggal di dokumen asli

# ---------------------------------------------------------------- pelanggan (selaras dengan migrasi PL/Surat Jalan)
m = re.search(r"\$json\$(.*?)\$json\$", open(os.path.join(HERE, "..", "supabase", "data", "migrasi_pl_do.sql")).read(), re.S)
customers = collections.OrderedDict((c["code"], c) for c in json.loads(m.group(1))["customers"])
HOREKA = [("raya boga", "RBC"), ("habitare", "HBR"), ("alana", "ALN"), ("harper", "HPR")]
def base(n): return re.sub(r"\s+", " ", re.sub(r"\(.*?\)", "", n.lower().replace("bu ", "ibu ", 1) if n.lower().startswith("bu ") else n.lower())).replace("bpk ", "bapak ").strip()
by_base = {base(c["name"]): c["code"] for c in customers.values() if c["type"] == "OTHER"}
ALIAS = {"kedutaan besar mesir": "bapak mahmoud", "zidane catering": "ibu zidane", "ibu zidan catering": "ibu zidane", "rajab": "bapak rajab",
         "rohana": "ibu rohana", "ibu enie elastrie": "ibu eni elastri", "pak anton": "bapak anton", "ibu rizky": "ibu rizki",
         "gudings hub": "gudings hub mangga besar"}
NEW = []
def resolve(raw_name, telp=None):
    n = re.sub(r"\s+", " ", raw_name or "").strip(": ").strip()
    n = re.sub(r"\s*No\.? ?Telepon\s*:?\s*", " ", n).strip()
    if re.fullmatch(r"\(([^()]*)\)", n) and "poltek" not in n.lower(): n = n[1:-1].strip()
    phone = re.sub(r"[^\d\-]", "", telp or "") or None
    if not n or n == "-":
        customers.setdefault("UMUM", dict(code="UMUM", name="Pelanggan Umum (tanpa nama)", type="OTHER", term=0, like=[], address=None, phone=None))
        return "UMUM", phone
    low = n.lower()
    for k, code in HOREKA:
        if k in low: return code, phone
    if "aston" in low: return "AST", phone
    if "poltek" in low: return "POLITEKNIK-PELAYARAN-TAN", phone
    b = ALIAS.get(low, base(n))
    if b in by_base: return by_base[b], phone
    for bb, code in by_base.items():
        if bb == b: return code, phone
    code = cust_code(n)
    if code not in customers:
        customers[code] = dict(code=code, name=n, type="OTHER", term=0, like=[], address=None, phone=phone); NEW.append(n)
    by_base[b] = code
    return code, phone

# ---------------------------------------------------------------- produk
products = {}
PROD_ALIAS = {"top side": "Topside", "daging top side": "Daging Topside", "sengkel": "Sengkel", "oxtail/buntut": "Oxtail", "buntut": "Oxtail",
              "oxtail/buntut (end cut)": "Oxtail (end cut)", "short ribe 5 cm": "Short Ribs 5 cm", "hati sapi sample": "Hati Sapi", "tetelan sample": "Tetelan",
              "paru mentah": "Paru Mentah", "babat sapi": "Babat", "iga sapi": "Iga", "has dalam": "Has Dalam", "balungan (sumsum)": "Tulang Sumsum",
              "saikoro impor cube": "Saikoro Cube Impor", "transportasi": "Ongkir", "slice teriyaki low fat": "Slice Teriyaki Low Fat", "slice teriyaki non fat": "Slice Teriyaki Non Fat"}
def product_of(desc):
    d = re.sub(r"\s+", " ", desc).strip()
    if d.lower().startswith("kekurangan tagihan"):
        products.setdefault("Kekurangan Tagihan", dict(type="SUPPORTING", unit="LS", cat=None)); return "Kekurangan Tagihan"
    cn = PROD_ALIAS.get(d.lower()) or canon(d)
    products.setdefault(cn, product_meta(cn))
    return cn

# ---------------------------------------------------------------- baris barang
def rp(s): return float(s.replace("Rp", "").replace(",", ""))
def close(a, b): return abs(a - b) <= max(2.0, 0.0006 * abs(b))
SKIP_DESC = re.compile(r"^(\d+|pack|gram|rp0|)$", re.I)
NOTE_IGNORE = {"", "ok", ".", "#ref!"}

def lines_of(o):
    """-> daftar baris (desc, product, qty_kg, unit_price, line_total, note)"""
    out = []
    for it in o["items"]:
        d = it["desc"]; a = [rp(x) for x in it["amts"]]
        if SKIP_DESC.match(d.strip()):
            if any(a) : CATATAN.append(f"{o['no']}: baris tanpa nama dengan nilai {a} dilewati")
            continue
        price = total = None
        if len(a) >= 2: price, total = a[0], a[-1]
        elif len(a) == 1: total = a[0]
        unit = (it["unit"] or "").lower()
        q = float(it["qty"].replace(",", ".")) if it["qty"] else None
        gram = unit in ("g", "gr", "gram")
        note = []
        if q is None and price is None and total:
            kg, qty, up = 1.0, 1.0, total; q = None
            note.append("Tanpa jumlah di dokumen; dicatat 1 x nilai total")
            out.append(dict(d=d, p=product_of(d), q=qty, up=up, t=total, n=note + ([it["ket"]] if (it.get("ket") or "").strip().lower() not in NOTE_IGNORE else []))); continue
        if q is None:
            if price and total:
                kg = total / price; note.append("Jumlah dihitung dari total/harga (kolom jumlah kosong di dokumen asli)")
            else:
                CATATAN.append(f"{o['no']}: baris '{d}' tanpa jumlah dan harga; dilewati"); continue
            qty, up = kg, price
        else:
            kg = q / 1000 if gram else q
            if price is None:
                if total is None or kg <= 0: CATATAN.append(f"{o['no']}: baris '{d}' tidak lengkap; dilewati"); continue
                qty, up = kg, total / kg
                if kg and not close(kg * up, total): note.append("Harga dihitung dari total/jumlah")
            elif close(kg * price, total): qty, up = kg, price
            elif not gram and q and close(q / 1000 * price, total):
                qty, up = q / 1000, price; note.append(f"{it['qty']} gram" + (f" (satuan di dokumen: {it['unit']})" if it["unit"] else ""))
            elif gram and close(q * price, total):
                qty, up = kg, price * 1000; note.append(f"Harga di dokumen Rp{price:,.0f}/gram")
            elif close(price, total):
                qty, up = 1.0, total; note.append(f"{it['qty']} {it['unit']} @ Rp{total:,.0f} per kemasan")
            else:
                qty, up = kg, round(total / kg, 2) if kg else price
                note.append(f"Harga di dokumen Rp{price:,.0f} tidak sesuai total Rp{total:,.0f}; harga disesuaikan dengan total")
                CATATAN.append(f"{o['no']}: '{d}' {it['qty']} {it['unit']} x Rp{price:,.0f} != Rp{total:,.0f}; harga disesuaikan")
        if gram and q is not None and not any("gram" in n for n in note): note.append(f"{it['qty']} gram")
        if unit in ("pack", "karung") and abs(qty - q) < 1e-9: note.append(f"{it['qty']} {it['unit']}")
        ket = (it.get("ket") or "").strip()
        if ket.lower() not in NOTE_IGNORE: note.append(ket)
        out.append(dict(d=d, p=product_of(d), q=qty, up=up, t=(total if total is not None else qty * up), n=note))
    return out

# ---------------------------------------------------------------- invoice
def okd(z):
    try: return dt.date.fromisoformat(z) if z else None
    except ValueError: return None

invs = []
MERGED = []
def month_end(no):
    mm = re.match(r"INV-\d+-([IVX]+)-(\d{2})", no)
    y, mo = 2000 + int(mm.group(2)), ROMAN.index(mm.group(1)) + 1
    return (dt.date(y + (mo == 12), mo % 12 + 1, 1) - dt.timedelta(days=1)).isoformat()

for o in raw:
    c, ph = resolve(o["kepada"], o["tel"])
    d = o["date"]; notes = []
    mn = re.match(r"INV-0(\d{3})-([IVX]+-\d{2})$", o["no"])
    if mn:
        CATATAN.append(f"{o['no']}: nomor memakai 4 angka; ditulis INV-{mn.group(1)}-{mn.group(2)}"); notes.append(f"Nomor di dokumen asli: {o['no']}")
        o["no"] = f"INV-{mn.group(1)}-{mn.group(2)}"
    if not d:
        d = month_end(o["no"]); notes.append(f"Tanggal kosong di dokumen asli; diisi akhir bulan sesuai nomor ({d})")
        CATATAN.append(f"{o['no']}: tanggal kosong; dipakai {d}")
    ls = lines_of(o)
    if not ls and not o["total"]:
        CATATAN.append(f"{o['no']}: formulir kosong (tanpa barang dan tanpa nilai); tidak dimigrasi"); continue
    free = o["free"] or (o["total"] == 0) or (o["total"] is None and not ls)
    if not free and o["total"]:
        smp = [l for l in ls if "sample" in " ".join(l["n"]).lower()]
        if smp and close(o["total"], sum(l["t"] for l in ls if l not in smp)):
            for l in smp: l["n"].append(f"Sample, tidak ditagih (harga normal Rp{l['up']:,.0f}/kg)"); l["up"] = 0.0; l["t"] = 0.0
    if o["total"] is None and not o["free"]:
        CATATAN.append(f"{o['no']}: total tidak terbaca; dihitung dari baris")
    # gabungkan produk kembar dalam satu invoice (batasan: satu produk satu baris)
    merged = collections.OrderedDict()
    for l in ls:
        if l["p"] in merged:
            k = merged[l["p"]]; k["t"] += l["t"]; k["q"] += l["q"]; k["up"] = round(k["t"] / k["q"], 2); k["n"] += l["n"] + [f"Digabung dengan baris '{l['d']}'"]
            k["d"] += " + " + l["d"]
            MERGED.append(o["no"])
        else: merged[l["p"]] = l
    ls = list(merged.values())
    s = round(sum(l["t"] for l in ls), 2)
    if free:
        total = 0.0
        for l in ls:
            l["n"].append(f"Gratis/sample (harga normal Rp{l['up']:,.0f}/kg)"); l["up"] = 0.0
    else:
        total = o["total"] if o["total"] is not None else s
        if abs(total - s) > 1.5:
            CATATAN.append(f"{o['no']} ({o['kepada']}): total di dokumen Rp{total:,.0f} != jumlah baris Rp{s:,.0f}")
            notes.append(f"Total di dokumen Rp{total:,.0f}; jumlah baris Rp{s:,.0f}")
    disc = o.get("discount") or 0
    if disc and not free:
        notes.append(f"Diskon/potongan harga Rp{disc:,.0f} (total tagihan sudah dikurangi)")
    if o["note"] and o["note"].strip("-: "): notes.insert(0, o["note"])
    tb = (o.get("terbilang") or "")
    due = o["due"]
    dd, du = okd(d), okd(due)
    if du and dd and du < dd: du = None
    dp = o["dp"] or 0
    if dp > total - (0 if free else disc): CATATAN.append(f"{o['no']}: uang muka Rp{dp:,.0f} melebihi total; diabaikan"); dp = 0
    invs.append(dict(no=o["no"], base=o["no"], page=o["page"], c=c, d=d, due=(du.isoformat() if du else None), do=o["do"], kep=o["kepada"] or None, ph=ph,
                     bank=o["bank"], notes="; ".join(notes) or None, dp=dp, sub=total, total=round(total - (0 if free else disc), 2), free=free,
                     it=[dict(p=l["p"], q=round(l["q"], 3), pr=round(l["up"], 2), n=("; ".join([l["d"]] + l["n"]) if (l["n"] or l["d"] != l["p"]) else None)) for l in ls]))
    if not ls: CATATAN.append(f"{o['no']}: tanpa baris barang")

# nomor ganda: yang tanggalnya lebih akhir diberi akhiran -2, -3
cnt = collections.Counter(i["no"] for i in invs)
seen = collections.defaultdict(int)
for i in sorted(invs, key=lambda i: (i["d"], -i["page"])):
    if cnt[i["no"]] > 1:
        seen[i["no"]] += 1
        if seen[i["no"]] > 1:
            old = i["no"]; i["no"] = f"{old}-{seen[old]}"
            CATATAN.append(f"{old}: nomor dipakai dua invoice (pelanggan {i['kep']}, {i['d']}); yang kedua diberi nomor {i['no']}")
            i["notes"] = "; ".join(x for x in [i["notes"], f"Nomor asli di dokumen: {old} (dipakai ganda)"] if x)
for i in invs:
    mm = re.match(r"INV-\d{3}-([IVX]+)-(\d{2})", i["base"]); dm = okd(i["d"])
    if mm and dm and (ROMAN[dm.month - 1] != mm.group(1) or f"{dm.year % 100:02d}" != mm.group(2)) and i["d"] != UNDATED:
        CATATAN.append(f"{i['no']}: bulan pada nomor tidak sama dengan tanggal invoice {i['d']}")

# ---------------------------------------------------------------- status bayar (NoA: hijau = dibayar)
noa_code = {"Harper": "HPR", "Alana": "ALN", "Habitare": "HBR"}
noa_map = {}; noa_amt = {}
for k, rows in noa.items():
    for r in rows:
        key = (noa_code[k], r["inv"])
        if key in noa_map and noa_map[key] != r["warna"]: CATATAN.append(f"NoA {k}: {r['inv']} muncul dua kali dengan warna berbeda")
        noa_map[key] = r["warna"]; noa_amt[key] = float(r["amt"].replace("Rp", "").replace(",", "")) if r.get("amt") else None
used = set(); stat = collections.Counter()
for i in invs:
    key = (i["c"], i["base"])
    if i["free"]: i["st"] = "PAID"; stat["gratis"] += 1; continue
    if i["c"] in noa_code.values():
        w = noa_map.get(key)
        if w is None:
            i["st"] = "PAID"; stat["Horeka tidak ada di NoA -> lunas"] += 1
            CATATAN.append(f"{i['no']} ({i['c']}, {i['d']}, Rp{i['total']:,.0f}): tidak tercantum di NoA; dianggap lunas")
        else:
            used.add(key); i["st"] = "PAID" if w == "hijau" else "OPEN"; stat[f"NoA {w}"] += 1
            na = noa_amt.get(key)
            if na is not None and abs(na - i["total"]) > 1.5:
                CATATAN.append(f"{i['no']} ({i['c']}): nilai di NoA Rp{na:,.0f} != total invoice Rp{i['total']:,.0f}")
            if w not in ("hijau", "putih", "kuning", "oranye"): CATATAN.append(f"{i['no']}: warna NoA tidak dikenal {w}")
    else:
        i["st"] = "PAID"; stat["pelanggan lain -> lunas"] += 1
for key, w in noa_map.items():
    if key not in used: CATATAN.append(f"NoA: {key[1]} ({key[0]}, warna {w}) tidak ada pasangannya di PDF invoice")
for i in invs:
    if i["st"] == "PAID": i["paid"] = i["total"]
    else:
        i["paid"] = i["dp"]
        i["st"] = "PARTIAL" if i["dp"] > 0 else "ISSUED"
    i.pop("free"); i.pop("page"); i.pop("base")
    if i["dp"] == 0: i["dp"] = 0

invs.sort(key=lambda i: (i["d"], i["no"]))
usedc = {i["c"] for i in invs}
for i in invs: i["sub"] = i.get("sub", i["total"])
data = dict(customers=[c for c in customers.values() if c["code"] in usedc], products=[dict(name=k, **v) for k, v in sorted(products.items())], invs=invs)
js = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("$json$", "")
sql = open(os.path.join(HERE, "gen_inv.tpl.sql")).read().replace("/*DATA*/", js)
open(OUT, "w").write(sql)
tot = sum(i["total"] for i in invs); open_ = sum(i["total"] - i["paid"] for i in invs if i["st"] in ("ISSUED", "PARTIAL"))
print(f"Invoice {len(invs)} ({sum(len(i['it']) for i in invs)} baris), nilai Rp{tot:,.0f}, belum dibayar {sum(1 for i in invs if i['st'] in ('ISSUED','PARTIAL'))} invoice Rp{open_:,.0f}; "
      f"pelanggan baru {len(NEW)}, produk {len(products)}, ukuran {len(sql)//1024} KB")
print("status:", dict(stat))
print("pelanggan baru:", NEW)
print(f"CATATAN: {len(set(MERGED))} invoice punya produk kembar yang digabung per produk (harga rata-rata): {sorted(set(MERGED))[:3]}...")
for c in CATATAN: print("CATATAN:", c)
