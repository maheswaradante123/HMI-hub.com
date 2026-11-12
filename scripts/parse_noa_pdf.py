#!/usr/bin/env python3
"""Membaca PDF 'Notes of Accounting' (NoA) per pelanggan Horeka: warna sel Kredit tiap baris tagihan.
hijau = sudah dibayar; putih / kuning / oranye = belum dibayar.
Pemakaian: python3 scripts/parse_noa_pdf.py <keluaran.json> Harper=<harper.pdf> Alana=<alana.pdf> Habitare=<habitare.pdf>
Butuh pdftotext dan pdftoppm (poppler-utils) dan Pillow."""
import re, sys, json, subprocess, tempfile, os, collections
from PIL import Image

def words(html):
    out = []
    for pi, p in enumerate(re.split(r"<page ", html)[1:]):
        for m in re.finditer(r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>', p):
            out.append(dict(pg=pi + 1, x0=float(m[1]), y0=float(m[2]), x1=float(m[3]), y1=float(m[4]), t=m[5]))
    return out

def cls(rgb):
    r, g, b = rgb[:3]
    if r > 235 and g > 235 and b > 235: return "putih"
    if r > 230 and g > 230 and b < 120: return "kuning"
    if r > 230 and 120 < g < 190 and b < 80: return "oranye"
    if g > r + 8 and g >= b: return "hijau"
    return f"lain{rgb}"

def read(pdf, tmp, name):
    html = os.path.join(tmp, name + ".html")
    subprocess.run(["pdftotext", "-bbox", "-layout", pdf, html], check=True)
    subprocess.run(["pdftoppm", "-r", "100", "-png", pdf, os.path.join(tmp, name)], check=True)
    pngs = {int(re.search(r"-(\d+)\.png$", f).group(1)): os.path.join(tmp, f) for f in os.listdir(tmp) if f.startswith(name + "-") and f.endswith(".png")}
    w = words(open(html).read()); S = 100 / 72; res = []
    cache = {}
    for x in w:
        if not re.fullmatch(r"INV-\d{3}-[IVX]+-\d{2}", x["t"]) or not (250 < x["x0"] < 380): continue
        yc = (x["y0"] + x["y1"]) / 2
        row = [y for y in w if y["pg"] == x["pg"] and abs((y["y0"] + y["y1"]) / 2 - yc) < 9 and y["x0"] > x["x1"] and y["t"].startswith("Rp")]
        if not row: res.append(dict(inv=x["t"], warna="tidak-terbaca", amt=None)); continue
        a = max(row, key=lambda y: y["x0"]) if name != "Habitare" else max(row, key=lambda y: y["x0"])
        im = cache.setdefault(x["pg"], Image.open(pngs[x["pg"]]).convert("RGB"))
        res.append(dict(inv=x["t"], amt=a["t"], warna=cls(im.getpixel((int((a["x0"] - 3) * S), int(((a["y0"] + a["y1"]) / 2) * S))))))
    return res

if __name__ == "__main__":
    out = sys.argv[1]; res = {}
    with tempfile.TemporaryDirectory() as tmp:
        for arg in sys.argv[2:]:
            name, pdf = arg.split("=", 1)
            res[name] = read(pdf, tmp, name)
            print(name, len(res[name]), dict(collections.Counter(r["warna"] for r in res[name])))
    json.dump(res, open(out, "w"), ensure_ascii=False, indent=1)
