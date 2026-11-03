#!/usr/bin/env python3
"""Mengurai PDF 'Master Sapi 2026-2027' (Google Sheet) menjadi JSON per sapi, berdasarkan posisi kata (pdftotext -bbox).
Pemakaian: parse_qurban_master.py master.pdf keluaran.json"""
import json, re, subprocess, sys, tempfile, os

pdf, out = sys.argv[1], sys.argv[2]
tmp = tempfile.mkdtemp()
subprocess.run(["pdftotext", "-bbox", pdf, os.path.join(tmp, "b.html")], check=True)
t = open(os.path.join(tmp, "b.html"), encoding="utf-8").read()
words = [(float(a), float(b), float(c), float(d), w.replace("&amp;", "&")) for a, b, c, d, w in
         re.findall(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', t)]
body = sorted([w for w in words if w[1] > 62.5 and w[1] < 400], key=lambda w: (w[1], w[0]))

# kelompokkan per baris (selisih y kecil = satu baris)
rows, cur, last = [], [], None
for w in body:
    if last is None or abs(w[1] - last) <= 0.7:
        cur.append(w)
    else:
        rows.append(cur); cur = [w]
    last = w[1] if last is None or abs(w[1] - last) > 0.7 else last
if cur: rows.append(cur)

MONTH_EDGES = [232, 268.5, 307.5, 346.5, 387, 427.5, 464, 500.5, 540, 579.5, 619, 658.5, 700]
YMS = ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10", "2026-11", "2026-12", "2027-01", "2027-02", "2027-03", "2027-04", "2027-05"]

def join(ws): return " ".join(w[4] for w in sorted(ws, key=lambda w: w[0])).strip()
def money(s):
    m = re.sub(r"[^0-9.]", "", s.replace(",", ""))
    return float(m) if m else None

def parse_date(s):
    s = s.strip()
    if not s: return None
    m = re.match(r"^(\d{1,2})[- ]([A-Za-z]{3})[- ](\d{4})$", s)
    if not m: return "?" + s
    mon = {"Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6, "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12}[m.group(2)]
    return f"{m.group(3)}-{mon:02d}-{int(m.group(1)):02d}"

res = []
for r in rows:
    r = sorted(r, key=lambda w: w[0])
    no_w = [w for w in r if w[0] < 33]
    if not no_w or not re.fullmatch(r"\d+", no_w[0][4]):
        continue   # baris total dsb.
    left = [w for w in r if w[0] < 70]
    cow = join([w for w in left if 33 <= w[0] < 46.5])
    nama = join([w for w in left if 46.5 <= w[0] < 70])
    def col(a, b): return join([w for w in r if a <= w[0] < b])
    d = {
        "no": int(no_w[0][4]), "cow": cow, "nama": nama,
        "tgl_beli": parse_date(col(110, 128)), "bobot": col(128, 136), "harga": col(136, 151.2),
        "inv": col(151.2, 166.5), "sp_jb": col(166.5, 186), "sp_pl": col(186, 206),
        "tgl_mulai": parse_date(col(206, 220.5)), "care_hari": col(220.5, 232.3),
        "bulan": {},
        "kanan": col(700, 900),
    }
    for i, ym in enumerate(YMS):
        a, b = MONTH_EDGES[i], MONTH_EDGES[i + 1]
        ws = [w for w in r if a <= w[0] < b]
        nilai = [w for w in ws if w[4].startswith("Rp")]
        stat = [w for w in ws if w[4] in ("Lunas",) or w[4].lower() in ("belum", "pending")]
        inv = [w for w in ws if w not in nilai and w not in stat]
        d["bulan"][ym] = {"nilai": join(nilai), "inv": join(inv), "status": join(stat)}
    res.append(d)
json.dump(res, open(out, "w"), ensure_ascii=False, indent=1)
print(len(res), "baris")
