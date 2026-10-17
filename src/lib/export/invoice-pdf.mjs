// Pembuat PDF Proforma/Invoice Qurban. Ukuran dan posisi diukur dari PDF contoh (A4, satuan pt),
// jadi hasilnya sama di semua perangkat dan tidak bergantung pada Excel atau font di komputer pembaca.
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { terbilangRupiah, tglEN, tglDash } from "./invoice-xlsx.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const H = 842.88, W = 595.92;
const BASE = 0.4284; // garis dasar teks = atas kotak teks + 0,4284 x ukuran huruf
const BASE_ARIAL = 0.8034; // font Arial (Liberation Sans) punya metrik vertikal berbeda dari Cairo
const BLUE = rgb(0.2392, 0.5216, 0.7765);
const GRAY = rgb(0.8, 0.8, 0.8);
const BLACK = rgb(0, 0, 0);
const HEAD = rgb(0.9765, 0.7961, 0.6118);
const ORANGE = rgb(0.902, 0.5686, 0.2196);
const LIGHT = rgb(0.851, 0.851, 0.851);
const num = (n) => Math.round(n).toLocaleString("en-US");

const COL = [49.9, 84.7, 238.2, 286.7, 335.1, 407.1, 471.9, 544.8];
const LEFT = 49.9, RIGHT = 545.1;

export async function buatInvoicePdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const arial = await pdf.embedFont(await read("fonts", "LiberationSans-Regular.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "hmi-logo.png"));
  const sign = await pdf.embedPng(await read("assets", "sig-hunain-inv.png"));
  const page = pdf.addPage([W, H]);

  const T = (s, x, top, size, font = reg, color = BLACK, skew = 0) =>
    page.drawText(s, { x, y: H - top - (font === arial ? BASE_ARIAL : BASE) * size, size, font, color, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const wd = (s, size, font = reg) => font.widthOfTextAtSize(s, size);
  const centerIn = (s, x0, x1, top, size, font = reg, color = BLACK) => T(s, (x0 + x1) / 2 - wd(s, size, font) / 2, top, size, font, color);
  const rightAt = (s, xr, top, size, font = reg, color = BLACK) => T(s, xr - wd(s, size, font), top, size, font, color);
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.5, color: BLACK });
  const vline = (x, y0, y1, color = BLACK) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.5, color });
  // Gambar dicampur mode "multiply" supaya latar putih tanda tangan tidak menutupi logo di bawahnya.
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);
  const img = (im, x0, x1, top, bot) => {
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(im, { x: x0, y: H - bot, width: x1 - x0, height: bot - top });
    page.pushOperators(popGraphicsState());
  };

  const proforma = d.judul !== "INVOICE";
  // judul dan logo
  T(d.judul, 51.8, 71.5, 31.35, bold);
  img(logo, 453.6, 540.5, 56, 115);
  // keterangan
  [["No.", d.nomor, 117.9], ["Tanggal", tglEN(d.tanggal), 128.0], ["Kepada", d.kepada, 138.0]].forEach(([l, v, top]) => {
    T(l, 51.8, top, 7.03, bold); T(":", 77.4, top, 7.03, bold); T(v, 86.4, top, 7.03);
  });

  // tabel
  const rows = d.baris;
  const y0 = 173.4 + 10.1 * rows.length; // garis bawah tabel
  rect(49.9, RIGHT, 163.1, 173.7, HEAD);
  ["No", "Deskripsi", "Qty", "Satuan", "Harga Per Satuan", "Total", "Keterangan"].forEach((h, i) => centerIn(h, COL[i], COL[i + 1], 168.2, 8.32, bold));
  let tot = 0;
  rows.forEach((b, i) => {
    const top = 178.3 + 10.1 * i, j = b.qty * b.harga;
    tot += j;
    centerIn(String(i + 1), COL[0], COL[1], top, 8.32);
    T(b.desc, 86.4, top, 8.32);
    centerIn(Number(b.qty).toLocaleString("en-US", { maximumFractionDigits: 2 }), COL[2], COL[3], top, 8.32);
    centerIn(b.unit, COL[3], COL[4], top, 8.32);
    T("Rp", 363.5, top, 8.32); rightAt(num(b.harga), 405.4, top, 8.32);
    const nTxt = num(j), nx = 470.2 - wd(nTxt, 8.32);
    T("Rp", nx - 7.3 - wd("Rp", 8.32), top, 8.32); T(nTxt, nx, top, 8.32);
  });
  hline(49.9, RIGHT, 163.4);
  for (let k = 0; k <= rows.length; k++) hline(49.9, RIGHT, 173.4 + 10.1 * k);
  COL.forEach((x) => vline(x, 163.1, y0 + 0.2));
  vline(50.1, 163.1, y0 + 0.2);

  // ringkasan
  const dsk = d.diskon || 0, dp = d.uangMuka || 0, kur = tot - dsk - dp;
  const sum = [];
  if (d.tampilTotal) sum.push(["Total", tot, true]);
  sum.push(["Total Pembelanjaan", d.tampilTotal ? tot - dsk : tot, true]);
  if (!d.tampilTotal && d.diskon !== undefined) sum.push(["Discount", dsk, true]);
  sum.push(["Uang Muka", dp, false], ["Kekurangan", kur, true]);
  let top = y0 - 0.25;
  sum.forEach(([lbl, v, fill], k) => {
    if (fill) rect(238.0, RIGHT, top, top + 12, ORANGE);
    if (fill && lbl !== "Kekurangan") vline(238.2, top, top + 12, rgb(0.7176, 0.7176, 0.7176));
    T(lbl, 51.8, top + 5.2, 9.6, bold, GRAY);
    if (lbl !== "Uang Muka" || proforma || dp > 0) { // pada invoice, uang muka kosong dibiarkan tanpa angka
      const s = num(v), x = 543.1 - wd(s, 9.6, bold);
      T(s, x, top + 5.2, 9.6, bold); T("Rp", x - 8.4 - wd("Rp", 9.6, bold), top + 5.2, 9.6, bold);
    }
    top += 12; hline(LEFT, RIGHT, top);
  });
  // terbilang
  if (!proforma) rect(238.0, RIGHT, top, top + 12, LIGHT);
  T("Terbilang", 51.8, top + 5.2, 9.6, bold, GRAY);
  centerIn(terbilangRupiah(kur).replace(/(Rupiah)( Rupiah)+/, "Rupiah"), 238.2, 544.8, top + 3.3, 6.4, arial);
  top += 12; hline(LEFT, RIGHT, top);

  // rekening
  const bank1 = [["Pembayaran melalui transfer ", reg], ["Bank Mandiri a/n. Harmoni Mitra Inovindo", bold], [" 1290015674415", reg]];
  const w1 = bank1.reduce((a, [s, f]) => a + wd(s, 8.32, f), 0);
  let x = 297.4 - w1 / 2 + 1.18;
  bank1.forEach(([s, f]) => { T(s, x, top + 4.8, 8.32, f, BLUE, 14.04); x += wd(s, 8.32, f); });
  const bank2 = [["Bank Rakyat Indonesia (BRI) a/n. Harmoni Mitra Inovindo", bold], [" 117001000653562", reg]];
  const w2 = bank2.reduce((a, [s, f]) => a + wd(s, 8.32, f), 0);
  x = 474.2 - w2 + 1.18;
  bank2.forEach(([s, f]) => { T(s, x, top + 15.4, 8.32, f, BLUE, 14.04); x += wd(s, 8.32, f); });

  // jatuh tempo dan catatan
  let n = top + 25.2;
  if (!proforma) {
    T("Jatuh Tempo", 51.8, n, 7.68, reg, BLUE); T(":", 121.4, n, 7.68, reg, BLUE); T(tglDash(d.jatuhTempo), 127.1, n, 7.68, reg, BLUE);
    n += 10;
  }
  T("Note", 51.8, n, 7.68, reg, BLUE); T(":", 121.6, n, 7.68, reg, BLUE); T(d.catatan || "", 127.1, n, 7.68, reg, BLUE);

  // tanda tangan
  if (proforma) {
    img(logo, 124.7, 191.0, n + 6.2, n + 43.6);
    img(sign, 70.1, 144.9, n + 16.8, n + 51.8);
  } else {
    img(logo, 138.7, 204.9, n + 11.0, n + 48.4);
    img(sign, 72.5, 147.3, n + 13.4, n + 48.4);
  }
  const dy = proforma ? 0 : 0.5;
  centerIn("Direktur Keuangan", 49.9, 238.5, n + 60.8 + dy, 7.03);
  hline(49.9, 238.5, n + 65.9 + dy);
  centerIn("Ahmad Hunain", 49.9, 238.5, n + 69.3 + dy, 6.4, arial);
  if (proforma) rect(49.9, RIGHT, n + 75.8, n + 77.2, rgb(0.6, 0.6, 0.6));

  return pdf.save();
}
