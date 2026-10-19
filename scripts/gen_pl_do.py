#!/usr/bin/env python3
"""Membuat supabase/data/migrasi_pl_do.sql dari hasil baca PDF Packing List & Surat Jalan lama (Google Sheets).
Pemakaian: python3 scripts/gen_pl_do.py <pl_parsed.json> <sj_parsed.json> <ropo_data.json> <keluaran.sql>
(ropo_data.json dibuat oleh gen_ro_po.py dengan argumen ke-4.) Hal yang perlu dicek manusia dicetak sebagai CATATAN."""
import json, re, sys, os, datetime as dt, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ropo_lib import *

PL_FILE, SJ_FILE, ROPO_FILE, OUT = sys.argv[1:5]
CATATAN = []
ropo = json.load(open(ROPO_FILE))

def okd(z):
    try: return dt.date.fromisoformat(z) if z else None
    except ValueError: return None

def pdate(s):
    s = re.sub(r"^[A-Za-z]+,\s*", "", (s or "").strip(": ").strip())
    m = re.match(r"(\d{1,2})[-/](\d{1,2})[-/](\d{4})", s)
    if m: return f"{int(m.group(3)):04d}-{int(m.group(2)):02d}-{int(m.group(1)):02d}"
    return first_date(s)

# ---------------------------------------------------------------- pelanggan
customers = collections.OrderedDict((c["code"], c) for c in ropo["customers"])
HOREKA = [("raya boga", "RBC"), ("habitare", "HBR"), ("alana", "ALN"), ("harper", "HPR")]
def base(n): return re.sub(r"\s+", " ", re.sub(r"\(.*?\)", "", n.lower().replace("bu ", "ibu ", 1) if n.lower().startswith("bu ") else n.lower())).replace("bpk ", "bapak ").strip()
by_base = {base(c["name"]): c["code"] for c in customers.values() if c["type"] == "OTHER"}
ALIAS = {"kedutaan besar mesir": "bapak mahmoud"}
def resolve(raw, telp=None):
    n = re.sub(r"\s+", " ", (raw or "")).strip(": ").strip()
    n = re.sub(r"\s*No\.? ?Telepon\s*:?\s*", " ", n).strip()
    phone = None
    m = re.search(r"\(?\b(0[\d\- ]{8,})\)?\s*$", n)
    if m: phone = m.group(1).strip(); n = n[:m.start()].strip()
    if not phone and telp: phone = re.sub(r"[^\d\-]", "", telp) or None
    if not n or n == "-":
        key = "UMUM"
        customers.setdefault(key, dict(code="UMUM", name="Pelanggan Umum (tanpa nama)", type="OTHER", term=0, like=[], address=None, phone=None))
        return key, phone
    low = n.lower()
    for k, code in HOREKA:
        if k in low: return code, phone
    if "aston" in low:
        customers.setdefault("AST", dict(code="AST", name="Hotel Aston Priority Simatupang", type="HOREKA", term=30, like=["%aston%"], address=None, phone=phone))
        return "AST", phone
    b = ALIAS.get(low, base(n))
    for bb, code in by_base.items():
        if bb == b or (b in ALIAS.values() and bb.startswith(b)): return code, phone
    code = cust_code(n)
    if code not in customers: customers[code] = dict(code=code, name=n, type="OTHER", term=0, like=[], address=None, phone=phone)
    by_base[b] = code
    return code, phone

# ---------------------------------------------------------------- produk (jenis item di PL)
products = {}
def pl_product(jenis):
    j = re.sub(r"\s+", " ", jenis or "").strip()
    if j.startswith("("): j = "Jeroan " + j      # "Jeroan" terpotong di kolom pada satu dokumen (PL-004-VII-26)
    note = None
    m = re.search(r"\((.*)\)\s*$", j)
    if m: note = m.group(1).strip(); j = j[:m.start()].strip()
    k = j.lower()
    j = {"beef cl": "Beef CL", "oxtail": "Oxtail", "oktail": "Oxtail", "tulang sum-sum": "Tulang Sumsum"}.get(k, j)
    cn = canon(j)
    products.setdefault(cn, product_meta(cn))
    return cn, note

# ---------------------------------------------------------------- tautan PL -> PO/RO
ro_cust = {r["no"]: r["c"] for r in ropo["ros"]}
ro_dd = {r["no"]: (r["c"], r["dd"]) for r in ropo["ros"]}
po_info = []
for p in ropo["pos"]:
    c = ro_cust.get(p["ro"]) if p["ro"] else None
    if c is None and p["ro"] and "-AST-" in p["ro"]: c = "AST"
    po_info.append((p["no"], p["ro"], c, [okd(z) for z in p["ds"] if okd(z)]))

pls = []
for x in sorted(json.load(open(PL_FILE)), key=lambda x: pdate(x["tgl"]) or ""):
    no = x["no"].lstrip(":")
    d = pdate(x["tgl"])
    if not d: raise SystemExit(f"{no}: tanggal tidak terbaca")
    c, ph = resolve(x["kepada"], x.get("telp"))
    notes = []
    if clean(x.get("note")): notes.append(clean(x["note"]))
    items = []
    for it in x["items"]:
        cn, dnote = pl_product(it["jenis"])
        net = it["net"]
        if net is None or net <= 0: CATATAN.append(f"{no}: baris {it['no']} berat net tidak valid"); continue
        g = it.get("gross"); inotes = []
        if dnote: inotes.append(dnote)
        if g is not None and (g < net or g - net > 0.3):
            inotes.append(f"Gross di dokumen: {g} (tidak wajar, tidak disimpan)"); CATATAN.append(f"{no}: baris {it['no']} gross {g} tidak wajar terhadap net {net}; gross dikosongkan"); g = None
        elif g is None and any(i.get("g1") for i in x["items"]): inotes.append("Gross tidak terbaca di dokumen")
        if it.get("potongan"): inotes.append(f"Jumlah potongan: {it['potongan']}")
        items.append(dict(p=cn, q=round(net, 3), g=g, n="; ".join(inotes) or None))
    if not items: CATATAN.append(f"{no}: tanpa baris barang")
    sn = round(sum(i["q"] for i in items), 3)
    if x.get("total_net") is not None and abs(sn - x["total_net"]) > 0.002:
        notes.append(f"Total net di dokumen {x['total_net']} kg, jumlah baris {sn} kg")
        CATATAN.append(f"{no}: total net di dokumen {x['total_net']} != jumlah baris {sn}")
    if not any(i["g"] is not None for i in items): CATATAN.append(f"{no}: tanpa gross weight")
    # tautan: PO dengan pelanggan sama dan tanggal kirim sama persis (hanya bila tepat satu; bila beberapa PO dari RO yang sama, tautkan RO saja)
    dd = okd(d)
    m = [k for k in po_info if k[2] == c and any(z == dd for z in k[3])]
    po = ro = None
    if len(m) == 1: po, ro = m[0][0], m[0][1]
    elif len(m) > 1 and len({k[1] for k in m}) == 1 and m[0][1]: ro = m[0][1]
    elif not m:
        r = [n for n, (cc, d2) in ro_dd.items() if cc == c and d2 == d]
        if len(r) == 1: ro = r[0]
    pls.append(dict(no=no, c=c, d=d, ph=ph, sup=clean(x.get("pengawas")), n="; ".join(notes) or None, po=po, ro=ro, it=items))
pl_key = collections.defaultdict(list)
for p in pls: pl_key[(p["c"], p["d"])].append(p["no"])

# ---------------------------------------------------------------- Surat Jalan
sjs = []
raw = json.load(open(SJ_FILE))
seen = collections.Counter()
last_date = None
for x in raw:
    if not x.get("items"):
        CATATAN.append(f"halaman {x['page']}: {x.get('no')} tanpa barang (formulir kosong); tidak dimigrasi"); continue
    kep = re.sub(r"\s*No\.? ?Telepon.*$", "", x.get("kepada") or "").strip()
    tel = x.get("telp") or ((re.search(r"No\.? ?Telepon\s*:?\s*(.*)$", x.get("kepada") or "") or [None, None])[1])
    c, ph = resolve(kep, tel if tel and tel != "-" else None)
    d = pdate(x.get("tgl"))
    notes = []
    if not d:
        d = last_date; notes.append("Tanggal kosong di dokumen asli; diisi tanggal surat jalan sebelumnya")
        CATATAN.append(f"{x.get('no')}: tanggal kosong; dipakai {d}")
    last_date = d
    note = clean(x.get("note"))
    if note: notes.insert(0, note)
    drv = None
    m = re.search(r"staff(?: toko)?(?: La Mitra)?[,\s]*\(?(?:Pak |Bu )?([A-Z][A-Za-z]+)", x.get("note") or "")
    if m and m.group(1) not in ("La", "Mitra"): drv = m.group(1)
    items = []
    for it in x["items"]:
        items.append(dict(d=clean(it["desc"]), j=clean(it["jenis"]), q=clean(it["ket"])))
    sjs.append(dict(no=x.get("no"), page=x["page"], c=c, d=d, ph=ph, drv=drv, n="; ".join(notes) or None,
                    rc=clean(x.get("penerima")), it=items))
# nomor: ganda -> yang tanggalnya lebih akhir diberi akhiran -B; kosong -> nomor berikutnya di bulan itu
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
cnt = collections.Counter(s["no"] for s in sjs if s["no"])
first_seen = {}
for s in sorted(sjs, key=lambda s: (s["d"], s["page"])):
    if s["no"] and cnt[s["no"]] > 1:
        if s["no"] in first_seen:
            CATATAN.append(f"{s['no']}: nomor dipakai dua surat jalan (tanggal {first_seen[s['no']]} dan {s['d']}); yang kedua diberi akhiran -B")
            s["no"] += "-B"
        else: first_seen[s["no"]] = s["d"]
for s in sjs:
    if s["no"]:
        m = re.match(r"DO-\d{3}-([IVX]+)-(\d{2})", s["no"])
        dm = okd(s["d"])
        if m and dm and (ROMAN[dm.month - 1] != m.group(1) or f"{dm.year % 100:02d}" != m.group(2)):
            CATATAN.append(f"{s['no']}: bulan pada nomor tidak sama dengan tanggal surat jalan {s['d']}")
for s in sjs:
    if not s["no"]:
        dm = okd(s["d"]); suffix = f"-{ROMAN[dm.month - 1]}-{dm.year % 100:02d}"
        used = [int(re.match(r"DO-(\d{3})", t["no"]).group(1)) for t in sjs if t["no"] and t["no"].endswith(suffix)]
        s["no"] = f"DO-{max(used or [0]) + 1:03d}{suffix}"
        s["n"] = "; ".join(x for x in [s["n"], "Nomor kosong di dokumen asli; diberi nomor " + s["no"]] if x)
        CATATAN.append(f"halaman {s['page']}: nomor kosong; diberi {s['no']}")
# tautan ke PL: pelanggan dan tanggal sama, 1:1
sj_key = collections.defaultdict(list)
for s in sjs: sj_key[(s["c"], s["d"])].append(s)
nlink = 0
for k, lst in sj_key.items():
    cand = pl_key.get(k, [])
    if len(cand) == 1 and len(lst) == 1: lst[0]["pl"] = cand[0]; nlink += 1
    elif cand and lst: CATATAN.append(f"{[s['no'] for s in lst]} dan PL {cand}: pelanggan/tanggal sama tetapi tidak 1:1; tidak ditautkan")
for s in sjs: s.setdefault("pl", None)

for s in sjs: s.pop("page")
data = dict(customers=[c for c in customers.values() if c["code"] not in {x["code"] for x in ropo["customers"]} or True],
            products=[dict(name=k, **v) for k, v in sorted(products.items())], pls=pls, dos=sjs)
js = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("$json$", "")
sql = open(__file__.replace("gen_pl_do.py", "gen_pl_do.tpl.sql")).read().replace("/*DATA*/", js)
open(OUT, "w").write(sql)
print(f"PL {len(pls)} ({sum(len(p['it']) for p in pls)} baris), SJ {len(sjs)} ({sum(len(s['it']) for s in sjs)} baris), tautan SJ-PL {nlink}, "
      f"PL ke PO {sum(1 for p in pls if p['po'])}, PL ke RO saja {sum(1 for p in pls if p['ro'] and not p['po'])}, "
      f"pelanggan {len(customers)}, produk {len(products)}, ukuran {len(sql)//1024} KB")
for c in CATATAN: print("CATATAN:", c)
