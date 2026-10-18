// Pembuat PDF "Analisa Pembelian" (A4 potret). Posisi diukur dari contoh ANALISA_PEMBELIAN (satuan pt, font Cairo 7,16 pt).
// Tabel mengalir ke bawah: jumlah baris item, non-karkas dan biaya bebas; bila tidak muat, lanjut ke halaman berikutnya.
import { PDFDocument, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglPendekCpj } from "./jcp-pdf.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.92, H = 842.88;
const SZ = 7.16;
const RH = 11.2846;           // tinggi satu baris
const FL = 114.46, FR = 480.96; // tepi latar kiri dan kanan
const C = [114.73, 159.87, 235.65, 300.13, 325.39, 388.8, 480.7]; // Nomor | Jenis Item | Quantity | Satuan | Harga | Total
const O = [114.73, 159.87, 235.65, 307.66, 388.8];                // tabel biaya: Nomor | Jenis Item | Satuan | Total
const BASE = 9.43;            // garis dasar teks di bawah garis atas baris
const BASE_HEAD = 8.36;     // judul kolom tabel utama sedikit lebih tinggi pada contoh
const QTY_UP = 1.074;         // judul Quantity sedikit lebih tinggi pada contoh (isi kolom memakai garis dasar yang sama dengan kolom lain)
const BOTTOM = 800, NEXT_TOP = 56.43;
const RP_NUM = 14.5;          // jarak awal "Rp" ke awal angka
const PAD = 1.88;
const BLACK = rgb(0, 0, 0), WHITE = rgb(1, 1, 1);
const GREEN = rgb(0.851, 0.9176, 0.8275), YELLOW = rgb(1, 0.949, 0.8);
const LW = 0.4;

const fmt = (n) => Math.round(Number(n)).toLocaleString("en-US");
const fmtQ3 = (n) => Number(n).toFixed(3);
const fmtQ = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });

/** d: {nomor, tanggal, supplier, jenis, top, invoice, harga, baris:[{nama, qty, price}], nonk:[{nama, qty|null, price}], biaya:[{nama, amount}], karkas, lower|null, upper|null,
 *      total:{all, ops, totalCost, profit, meat, meatPct|null, hargaKarkas|null, lowerRatio|null, upperRatio|null}} */
export async function buatApPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const wd = (s, font = reg, size = SZ) => font.widthOfTextAtSize(s, size);
  const RP_GAP = RP_NUM - wd("Rp");
  let page = null, lines = [], y = 0;

  const T = (s, x, base, font = reg, size = SZ, color = BLACK) => s !== "" && page.drawText(s, { x, y: H - base, size, font, color });
  const right = (s, xr, base, font = reg, size = SZ) => T(s, xr - wd(s, font, size), base, font, size);
  const center = (s, x0, x1, base, font = reg, size = SZ) => T(s, (x0 + x1) / 2 - wd(s, font, size) / 2, base, font, size);
  const rp = (v, xr, base, font = reg) => {
    const neg = Number(v) < 0;
    const s = fmt(Math.abs(Number(v)));
    right(s, xr, base, font);
    const xRp = xr - wd(s, font) - RP_GAP - wd("Rp", font);
    T("Rp", xRp, base, font);
    if (neg) T("-", xRp - wd("-", font) - 0.5, base, font);
  };
  const fill = (x0, x1, y0, y1, color) => page.drawRectangle({ x: x0, y: H - y1, width: x1 - x0, height: y1 - y0, color });
  // Garis ditunda sampai akhir halaman agar selalu berada di atas latar warna.
  const hline = (x0, x1, yy) => lines.push([x0, H - yy, x1, H - yy]);
  const vline = (x, y0, y1) => lines.push([x, H - y0, x, H - y1]);
  const flush = () => { for (const [x0, y0, x1, y1] of lines) page.drawLine({ start: { x: x0, y: y0 }, end: { x: x1, y: y1 }, thickness: LW, color: BLACK }); lines = []; };
  const newPage = (top) => { if (page) flush(); page = pdf.addPage([W, H]); y = top; };
  const need = (n) => { if (y + n * RH > BOTTOM) newPage(NEXT_TOP); };
  const band = (y0, y1, x0, x1, color) => fill(x0, x1, y0 - 0.27, y1 + 0.27, color); // latar sedikit melewati garis tepi, seperti contoh

  // ---- Judul dan data dokumen ----
  newPage(143.75);
  fill(114.46, 480.96, 53.2, 76.31, BLACK);
  T("ANALISA PEMBELIAN", 116.61, 70.935, reg, 17.91, WHITE);
  [["Nomor", d.nomor, "Supplier", d.supplier], ["Tanggal", tglPendekCpj(d.tanggal), "TOP (Jatuh Tempo)", d.top ? tglPendekCpj(d.top) : ""], ["Jenis Sapi", d.jenis, "Nomor Invoice", d.invoice ?? ""]].forEach(([l1, v1, l2, v2], i) => {
    const b = [96.73, 108.015, 119.3][i];
    T(l1, 116.61, b); T(":", 155.31, b); T(v1, 161.75, b);
    T(l2, 237.53, b); T(":", 302.01, b); T(v2, 309.54, b);
  });
  fill(413.79, 480.96, 87.06, 98.88, GREEN);
  T("Harga", 390.68, 96.73); T(":", 410.42, 96.73); rp(d.harga, 478.81, 96.73);

  // ---- Tabel hasil penjualan ----
  band(y, y + RH, FL, FR, GREEN);
  hline(FL, FR, y); hline(FL, FR, y + RH);
  C.forEach((x) => vline(x, y, y + RH));
  center("Nomor", C[0], C[1], y + BASE_HEAD, bold); center("Jenis Item", C[1], C[2], y + BASE_HEAD, bold);
  center("Quantity", C[2], C[3], y + BASE_HEAD - QTY_UP, bold); center("Satuan", C[3], C[4], y + BASE_HEAD, bold);
  center("Harga Jual/Satuan", C[4], C[5], y + BASE_HEAD, bold); center("Total", C[5], C[6], y + BASE_HEAD, bold);
  y += RH;

  const rows = [...d.baris.map((r) => ({ ...r, qty: Number(r.qty) })), ...d.nonk.map((r) => ({ ...r, qty: r.qty == null ? null : Number(r.qty) }))];
  // Bagi baris per halaman lebih dulu supaya latar kuning kolom Quantity satu bidang per halaman.
  const chunks = [];
  for (let i = 0, cap = Math.max(1, Math.floor((BOTTOM - y) / RH)); i < rows.length; cap = Math.floor((BOTTOM - NEXT_TOP) / RH)) { chunks.push(rows.slice(i, i + cap)); i += cap; }
  let no = 0;
  chunks.forEach((chunk, ci) => {
    if (ci > 0) { newPage(NEXT_TOP); hline(FL, FR, y); }
    fill(235.38, 300.4, y - 0.27, y + chunk.length * RH + 0.27, YELLOW); // kolom Quantity berlatar kuning
    for (const r of chunk) {
      const top = y, b = top + BASE;
      center(String(++no), C[0], C[1], b);
      T(r.nama ?? "", C[1] + PAD, b);
      if (r.qty) center(fmtQ3(r.qty), C[2], C[3], b);
      center("Kg", C[3], C[4], b);
      rp(r.price, C[5] - PAD, b);
      rp((r.qty ?? 0) * Number(r.price), C[6] - PAD, b);
      y += RH;
      hline(FL, FR, y);
      C.forEach((x) => vline(x, top, y));
    }
  });

  // Baris Total Penjualan
  need(1);
  band(y, y + RH, FL, FR, GREEN);
  hline(FL, FR, y + RH);
  [C[0], C[5], C[6]].forEach((x) => vline(x, y, y + RH));
  right("Total Penjualan", C[5] - PAD, y + 8.91, bold, 8.6);
  rp(d.total.all, C[6] - PAD, y + 9.45, bold);
  y += RH * 2; // satu baris kosong sebelum tabel biaya

  // ---- Biaya operasional ----
  need(4);
  band(y, y + RH * 2, FL, 389.07, GREEN);
  hline(FL, 389.07, y); hline(FL, 389.07, y + RH); hline(FL, 389.07, y + RH * 2);
  vline(O[0], y, y + RH); vline(O[4], y, y + RH);
  center("BIAYA OPERASIONAL", O[0], O[4], y + BASE, bold);
  y += RH;
  O.forEach((x) => vline(x, y, y + RH));
  center("Nomor", O[0], O[1], y + BASE, bold); center("Jenis Item", O[1], O[2], y + BASE, bold);
  center("Satuan", O[2], O[3], y + BASE, bold); center("Total", O[3], O[4], y + BASE, bold);
  y += RH;
  d.biaya.forEach((c, i) => {
    if (y + RH > BOTTOM) { newPage(NEXT_TOP); hline(FL, 389.07, y); }
    const top = y, b = top + BASE;
    right(String(i + 1), O[1] - PAD, b);
    T(c.nama ?? "", O[1] + PAD, b);
    T("Lamsam", O[2] + PAD, b);
    if (Number(c.amount)) rp(c.amount, O[4] - PAD, b);
    y += RH;
    hline(FL, 389.07, y);
    O.forEach((x) => vline(x, top, y));
  });
  need(2);
  band(y, y + RH * 2, FL, 307.92, GREEN);
  band(y, y + RH * 2, 307.39, 389.07, YELLOW);
  [["SubTotal", d.total.ops], ["Total", d.total.totalCost]].forEach(([label, v], i) => {
    const top = y + i * RH, b = top + BASE;
    right(label, O[3] - 1.89, b, bold, 9.31);
    rp(v, O[4] - PAD, b, bold);
    hline(FL, 389.07, top + RH);
    [O[0], O[3], O[4]].forEach((x) => vline(x, top, top + RH));
  });
  y += RH * 2;

  // ---- Keuntungan dan ringkasan ----
  const hasSides = d.lower != null || d.upper != null;
  need(2 + 1 + 1 + 4 + (hasSides ? 1 + (d.lower != null) + (d.upper != null) : 0));
  y += RH; // satu baris kosong
  band(y, y + RH, FL, 235.91, GREEN);
  T("Keuntungan", 116.61, y + BASE); T(":", 154.73, y + BASE); rp(d.total.profit, 233.76, y + BASE);
  y += RH * 2;
  const t = d.total;
  [["Daging", fmtQ3(t.meat)], ["Karkas", fmtQ(d.karkas)], ["Persentase", t.meatPct == null ? "" : `${t.meatPct.toFixed(2)}%`], ["Harga Karkas", t.hargaKarkas == null ? "" : `${t.hargaKarkas < 0 ? "-" : ""}Rp${fmt(Math.abs(t.hargaKarkas))}`]].forEach(([l, v], i) => {
    T(l, 161.75, y + i * RH + BASE); right(v, 298.25, y + i * RH + BASE);
  });
  y += RH * 4;
  if (hasSides) {
    y += RH;
    [["Lower Side", d.lower, t.lowerRatio], ["UpperSide", d.upper, t.upperRatio]].forEach(([l, v, ratio]) => {
      if (v == null) return;
      T(l, 116.61, y + BASE - 0.537, reg, 7.88);
      right(fmtQ3(v), 233.76, y + BASE);
      if (ratio != null) right(ratio.toFixed(10), 298.25, y + BASE);
      y += RH;
    });
  }
  flush();
  return Buffer.from(await pdf.save());
}
