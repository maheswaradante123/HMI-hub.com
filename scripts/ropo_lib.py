"""Fungsi bersama pembuat skrip migrasi RO/PO dan Packing List/Surat Jalan (baca tanggal, nama produk, pelanggan, kemasan)."""
import re
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

