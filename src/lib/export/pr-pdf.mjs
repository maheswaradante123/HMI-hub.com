// Pembuat PDF "Purchase Request" (A4 lanskap, lembar mingguan). Posisi diukur dari contoh PR-APRIL-26 (satuan pt).
// Halaman 1 memuat No/Date dan header tabel; halaman berikutnya hanya melanjutkan baris. Baris Total di akhir tabel.
import { PDFDocument, rgb, degrees } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglPendekCpj, tglPanjangCpj } from "./jcp-pdf.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 842.88, H = 595.92;
const SZ = 8.14;
const X = [17.5, 66.39, 115.28, 169.17, 223.06, 445.83, 511.39, 558.06, 604.72, 670.28, 729.72, 776.39, 823.06];
const RH = 11.667;
const HEAD_TOP = 111.67, ROW0 = 135.28, NEXT_TOP = 53.61, BOTTOM = 540.6;
const BASE_OFF = 9.164;   // garis dasar teks di bawah garis atas baris
const BASE_BOLD = 8.609;  // tanggal dan kode (tebal) sedikit lebih tinggi pada contoh
const RP_NUM = 16.5;      // jarak "Rp" ke awal angka
const PAD = 1.95;
const BLACK = rgb(0, 0, 0);
const hex = (h) => rgb(parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255);

/** Warna status: latar pil dan warna teks (diukur dari contoh), label seperti tulisan di contoh. */
export const PR_PILL = {
  DRAFT: { label: "Draft", bg: "B10202", fg: "FFCFC9" },
  SUBMITTED: { label: "Diajukan", bg: "FCE8B2", fg: "7A4F01" },
  APPROVED: { label: "Approved", bg: "FFCFC9", fg: "B10202" },
  REJECTED: { label: "Ditolak", bg: "7F1D1D", fg: "FEE2E2" },
  ORDERED: { label: "Order", bg: "11734B", fg: "D4EDBC" },
  RECEIVED: { label: "Received", bg: "FFE5A0", fg: "473821" },
  CLOSED: { label: "closed", bg: "5A3286", fg: "E5CFF2" },
  CANCELLED: { label: "cancel", bg: "3D3D3D", fg: "E5E5E5" },
};
export const prJumlah = (b) => Number(b.price) * Number(b.qty);
/** Total lembar: barang yang dibatalkan atau ditolak tidak dihitung. */
export const prTotal = (baris) => baris.reduce((s, b) => s + (b.status === "CANCELLED" || b.status === "REJECTED" ? 0 : prJumlah(b)), 0);

const fmt = (n) => Math.round(Number(n)).toLocaleString("en-US");
const fmtQ = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });

/** d: {nomor, tanggal, baris:[{ac, kode, tanggal, desc, price, qty, unit, status, pembelian, bukti}]} */
export async function buatPrPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const wd = (s, font = reg, size = SZ) => font.widthOfTextAtSize(s, size);
  const RP_GAP = RP_NUM - wd("Rp");

  const rows = d.baris;
  // Pembagian halaman: halaman 1 mulai di ROW0, halaman lanjutan di NEXT_TOP. Baris Total ikut baris terakhir bila muat.
  const pages = [];
  let cur = [], top = ROW0;
  for (const r of rows) {
    if (top + RH > BOTTOM) { pages.push(cur); cur = []; top = NEXT_TOP; }
    cur.push(r); top += RH;
  }
  const totalFits = top + RH <= BOTTOM;
  pages.push(cur);
  if (!totalFits) pages.push([]);

  let page, y0;
  const T = (s, x, base, font = reg, color = BLACK, italic = false) =>
    s !== "" && page.drawText(s, { x, y: H - base, size: SZ, font, color, ...(italic ? { ySkew: degrees(14.04) } : {}) });
  const center = (s, x0, x1, base, font = reg, color = BLACK, italic = false) => T(s, (x0 + x1) / 2 - wd(s, font) / 2, base, font, color, italic);
  const right = (s, xr, base, font = reg) => T(s, xr - wd(s, font), base, font);
  const hline = (x0, x1, y, w = 0.4) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: w, color: BLACK });
  const vline = (x, ya, yb, w = 0.4) => page.drawLine({ start: { x, y: H - ya }, end: { x, y: H - yb }, thickness: w, color: BLACK });
  const rp = (v, xr, base, font = reg) => {
    const s = fmt(v);
    right(s, xr, base, font);
    T("Rp", xr - wd(s, font) - RP_GAP - wd("Rp", font), base, font);
  };
  const fit = (s, maxW, ellipsis = false) => {
    if (wd(s) <= maxW) return s;
    let t = s;
    while (t.length > 1 && wd(t + (ellipsis ? "…" : "")) > maxW) t = t.slice(0, -1);
    return t + (ellipsis ? "…" : "");
  };
  const pill = (x, top, w, h, color) => {
    const r = h / 2;
    page.drawSvgPath(`M ${r} 0 H ${w - r} A ${r} ${r} 0 0 1 ${w - r} ${h} H ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`, { x, y: H - top, color });
  };

  pages.forEach((list, pi) => {
    page = pdf.addPage([W, H]);
    y0 = pi === 0 ? ROW0 : NEXT_TOP;
    const n = list.length;
    const lastPage = pi === pages.length - 1;
    const bodyBottom = y0 + n * RH;

    if (pi === 0) {
      T("No", 19.44, 74.444); T(":", 38.2, 74.444); T(d.nomor, 68.33, 74.444, bold, rgb(0.133, 0.133, 0.133));
      T("Date", 19.44, 97.778); T(":", 39.3, 97.778); T(tglPanjangCpj(d.tanggal), 68.33, 97.778);
      // Header abu-abu
      page.drawRectangle({ x: X[0] - 0.28, y: H - ROW0, width: X[12] - X[0] + 0.56, height: ROW0 - HEAD_TOP, color: rgb(0.7176, 0.7176, 0.7176) });
      const hb = 132.778;
      center("A/C.", X[0], X[1], hb, bold); center("No.", X[1], X[2], hb, bold); center("Tanggal", X[2], X[3], hb, bold);
      center("Description", X[4], X[5], hb, bold); center("Price", X[5], X[6], hb, bold); center("Qty", X[6], X[7], hb, bold);
      center("Unit", X[7], X[8], hb, bold); center("Amount", X[8], X[9], hb, bold); center("Status", X[9], X[10], hb, bold);
      T("Pembelian", 731.67, hb, bold);
      T("Attachment", 778.3, 121.11, bold); T("of Proof", 778.3, 131.11, bold);
      hline(X[0], X[12], HEAD_TOP + 0.27, 0.6);
    } else {
      hline(X[0], X[12], y0, 0.6);
    }

    list.forEach((r, i) => {
      const top0 = y0 + i * RH;
      const b = top0 + BASE_OFF;
      center(r.ac ?? "", X[0], X[1], b, bold, BLACK, true);
      center(String(r.no), X[1], X[2], b, bold);
      right(tglPendekCpj(r.tanggal), X[3] - 1.6, top0 + BASE_BOLD, bold);
      T(r.kode ?? "", X[3] + PAD, top0 + BASE_BOLD, bold);
      T(fit(r.desc ?? "", X[5] - X[4] - 2 * PAD), X[4] + PAD, b);
      rp(r.price, X[6] - PAD, b);
      center(fmtQ(r.qty), X[6], X[7], b);
      center(r.unit ?? "", X[7], X[8], b);
      rp(prJumlah(r), X[9] - PAD, b);
      const pc = PR_PILL[r.status] ?? PR_PILL.DRAFT;
      pill(675.56, top0 + 1.39, 48.88, 9.78, hex(pc.bg));
      center(pc.label, 671.25, 719.55, b, reg, hex(pc.fg)); // teks sedikit ke kiri dari tengah pil, seperti contoh
      T(fit(r.pembelian ?? "", X[11] - X[10] - 2 * PAD), X[10] + PAD, b);
      if (r.bukti) {
        const txt = fit(r.bukti, 821.03 - 4.9 - 790.9, true);
        const w = Math.min(821.03 - 778.33, 790.9 + wd(txt) + 4.9 - 778.33);
        pill(778.33, top0 + 1.39, w, 9.78, hex("E8EAED"));
        page.drawSvgPath("M 1.2 0 H 4.66 Q 5.86 0 5.86 1.2 V 4.66 Q 5.86 5.86 4.66 5.86 H 1.2 Q 0 5.86 0 4.66 V 1.2 Q 0 0 1.2 0 Z", { x: 781.67, y: H - (top0 + 3.35), color: hex("EA4335") });
        page.drawSvgPath("M 1 4.2 L 2.1 2.7 L 2.9 3.6 L 3.5 2.9 L 4.9 4.2 Z", { x: 781.67, y: H - (top0 + 3.35), color: rgb(1, 1, 1) });
        T(txt, 790.9, b);
      }
    });

    // Garis tabel
    const gridBottom = bodyBottom;
    for (let i = 1; i <= n; i++) hline(X[0], X[12], y0 + i * RH);
    const vTop = pi === 0 ? HEAD_TOP : y0;
    X.forEach((x) => vline(x, vTop, gridBottom));
    if (n > 0) hline(X[0], X[12], gridBottom, 0.6);

    if (lastPage) {
      const ty = pi === pages.length - 1 && n === 0 ? y0 : bodyBottom;
      const b = ty + BASE_OFF;
      const tot = prTotal(rows);
      hline(X[7], X[9], ty, 0.4); hline(X[7], X[9], ty + RH, 0.6);
      vline(X[7], ty, ty + RH); vline(X[8], ty, ty + RH); vline(X[9], ty, ty + RH);
      center("Total", X[7], X[8], b, bold);
      rp(tot, X[9] - PAD, b, bold);
    }
  });
  return Buffer.from(await pdf.save());
}
