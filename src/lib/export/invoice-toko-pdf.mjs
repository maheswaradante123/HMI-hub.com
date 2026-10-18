// Pembuat PDF Invoice toko (A5 lanskap, hijau, logo La Mitra). Ukuran dan posisi diukur dari INV-002-X-26.pdf (satuan pt).
// Baris tabel tambahan menggeser semua yang di bawahnya, dan halaman memanjang agar tetap satu lembar.
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglEN, tglID } from "./invoice-xlsx.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.92, H0 = 420;
const BASE = 0.4284, BASE_ARIAL = 0.8034;
const BLUE = rgb(0.2392, 0.5216, 0.7765);
const GRAY = rgb(0.8, 0.8, 0.8);
const INK = rgb(0.1333, 0.1333, 0.1333);
const BLACK = rgb(0, 0, 0);
const GREEN = rgb(0.851, 0.9176, 0.8275);
const BAR = rgb(0.6, 0.6, 0.6);
const SKEW = 6.62; // miring teks rekening dan surat jalan pada contoh
const rp = (n) => "Rp" + Math.round(n).toLocaleString("en-US");
const COL = [50.3, 80.4, 198.9, 250.3, 319.8, 404.1, 474.5, 544.9];
const LEFT = 50.0, RIGHT = 545.1, ROW = 10.2;

/** d: {nomor, tanggal(iso), kepada, suratJalan?, telepon?, baris[{desc,qty,unit,harga}], uangMuka, jatuhTempo(iso), bankInfo?, penandatangan?, tandaTangan?} */
export async function buatInvoiceTokoPdf(d) {
  const rows = d.baris.length ? d.baris : [];
  const dy = Math.max(0, rows.length - 1) * ROW;
  const H = H0 + dy;
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const arial = await pdf.embedFont(await read("fonts", "LiberationSans-Regular.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "lamitra-logo.png"));
  const page = pdf.addPage([W, H]);

  const T = (s, x, top, size, font = reg, color = BLACK, skew = 0) =>
    page.drawText(s, { x, y: H - top - (font === arial ? BASE_ARIAL : BASE) * size, size, font, color, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const wd = (s, size, font = reg) => font.widthOfTextAtSize(s, size);
  const centerIn = (s, x0, x1, top, size, font = reg, color = BLACK) => T(s, (x0 + x1) / 2 - wd(s, size, font) / 2, top, size, font, color);
  const rightAt = (s, xr, top, size, font = reg, color = BLACK) => T(s, xr - wd(s, size, font), top, size, font, color);
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.5, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.5, color: BLACK });
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);
  const img = (im, x0, x1, top, bot) => {
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(im, { x: x0, y: H - bot, width: x1 - x0, height: bot - top });
    page.pushOperators(popGraphicsState());
  };

  // judul, logo, keterangan
  T("INVOICE", 51.9, 95.4, 30.26, bold);
  img(logo, 492.0, 529.5, 89.7, 136.5);
  const meta = (l, v, top, vcolor = BLACK) => { T(l, 51.9, top, 6.79, bold); T(":", 76.6, top, 6.79, bold); T(v, 82.0, top, 6.79, reg, vcolor); };
  meta("No.", d.nomor, 128.2, INK);
  meta("Tanggal", tglEN(d.tanggal, true), 137.9);
  meta("Kepada", d.kepada, 147.6);
  if (d.suratJalan) { T("Surat Jalan", 200.6, 128.2, 6.79, bold); T(":", 236.9, 128.2, 6.79, bold); T(d.suratJalan, 251.0, 128.2, 6.79, reg, BLACK, SKEW); }
  if (d.telepon) { T("No. Telepon", 200.6, 147.6, 6.79, bold); T(":", 236.5, 147.6, 6.79, bold); T(d.telepon, 252.0, 147.4, 7.41); }

  // tabel
  const tabEnd = 183.6 + ROW * Math.max(rows.length, 1);
  rect(LEFT, RIGHT, 162.1, 183.9, GREEN);
  ["No", "Deskripsi", "Qty", "Satuan", "Harga Per Satuan", "Total", "Keterangan"].forEach((h, i) => {
    if (h === "Deskripsi") T(h, 123.5, 172.6, 8.03, bold); else centerIn(h, COL[i], COL[i + 1], 172.6, 8.03, bold);
  });
  let tot = 0;
  rows.forEach((b, i) => {
    const top = 188.3 + ROW * i, j = b.qty * b.harga;
    tot += j;
    centerIn(String(i + 1), COL[0], COL[1], top, 8.03);
    T(b.desc, 82.0, top, 8.03);
    centerIn(Number(b.qty).toLocaleString("en-US", { maximumFractionDigits: 3 }), COL[2], COL[3], top, 8.03);
    centerIn(b.unit || "", COL[3], COL[4], top, 8.03);
    centerIn(rp(b.harga), COL[4], COL[5], top - 0.2, 7.41);
    centerIn(rp(j), COL[5], COL[6], top, 8.03);
  });
  hline(LEFT, RIGHT, 162.3); hline(LEFT, RIGHT, 183.6);
  for (let k = 1; k <= Math.max(rows.length, 1); k++) hline(LEFT, RIGHT, 183.6 + ROW * k);
  COL.forEach((x) => vline(x, 162.1, tabEnd + 0.3));

  // ringkasan
  const dp = d.uangMuka || 0, kur = tot - dp;
  let y = tabEnd;
  const sumRow = (label, value, h, filled, textTop) => {
    if (filled) rect(198.7, RIGHT, y, y + h, GREEN);
    T(label, 51.9, y + textTop, 8.03, bold, GRAY);
    if (value !== null) rightAt(rp(value), 543.3, y + textTop, 8.03, bold);
    y += h; hline(LEFT, RIGHT, y);
  };
  sumRow("Total Pembelanjaan", tot, 13.9, true, 6.6);
  sumRow("Uang Muka", dp, 13.9, false, 6.5);
  sumRow("Kekurangan", kur, 14.8, true, 7.0);
  sumRow("Terbilang", null, 9.8, false, 4.7);

  // rekening
  const parts = d.bankInfo
    ? [["Pembayaran melalui transfer ", reg], [d.bankInfo, bold]]
    : [["Pembayaran melalui transfer ", reg], ["Bank Mandiri a/n. Harmoni Mitra Inovindo", bold], [" 1290015674415", bold]];
  const w = parts.reduce((a, [s, f]) => a + wd(s, 7.41, f), 0);
  let x = 297.5 - w / 2;
  parts.forEach(([s, f]) => { T(s, x, 253.0 + dy, 7.41, f, BLUE, SKEW); x += wd(s, 7.41, f); });
  T("Jatuh Tempo : " + tglID(d.jatuhTempo), 51.9, 265.0 + dy, 7.41, reg, BLUE);

  // tanda tangan
  const ttd = d.tandaTangan !== false && (!d.penandatangan || d.penandatangan === "Ahmad Hunain");
  if (ttd) img(await pdf.embedPng(await read("assets", "sig-hunain-toko.png")), 90.3, 151.9, 290.4 + dy, 327.5 + dy);
  centerIn("Direktur Keuangan", LEFT, 199.2, 333.8 + dy, 6.79);
  hline(LEFT, 199.2, 338.8 + dy);
  centerIn(d.penandatangan || "Ahmad Hunain", LEFT, 199.2, 342.5 + dy, 6.17, arial);
  rect(LEFT, RIGHT, 351.5 + dy, 354.3 + dy, BAR);

  return pdf.save();
}
