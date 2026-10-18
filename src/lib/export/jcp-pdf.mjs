// Pembuat PDF "Cash Payment Journal" (A4 portrait, tabel Excel diperkecil, font 4,23 pt). Posisi diukur dari contoh cpj.pdf (satuan pt).
// Tinggi halaman bertambah bila baris banyak, sehingga ringkasan, legenda, dan kotak tanda tangan tetap satu halaman.
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.92, H0 = 842.88;
const BASE = 0.4284;
const BLACK = rgb(0, 0, 0), WHITE = rgb(1, 1, 1);
const SZ = 4.23;
const X = [50.34, 71.98, 80.64, 119.58, 158.53, 230.08, 264.12, 294.13, 320.38, 364.81, 409.81, 454.82, 499.83, 544.83];
const L = 50.2, R = 544.98;
const TOP = 121.46, ROW0 = 135.45, RH = 6.0603;
const RP_GAP = 3.73;
const FILL = { NON_CPJ: [1, 1, 0], OVER: [1, 0.6, 0], REJECTED: [1, 0, 0], INCOMING: [0, 1, 1] };
const MONTH = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DAY = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const ymd = (iso) => { const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return { y, m, d }; };
export const tglPendekCpj = (iso) => { if (!iso) return ""; const { y, m, d } = ymd(iso); return `${String(d).padStart(2, "0")}-${MON[m - 1]}-${y}`; };
export const tglPanjangCpj = (iso) => { if (!iso) return ""; const { y, m, d } = ymd(iso); return `${DAY[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]}, ${MONTH[m - 1]} ${d}, ${y}`; };
const fmt = (n) => Math.round(Number(n)).toLocaleString("en-US");
const fmtQ = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });
const hasV = (v) => v !== null && v !== undefined && v !== "";

/** d: {nomor, tanggal, status, initiatorNama, initiatorJabatan, approverNama, approverJabatan, payNote, note,
 *      baris:[{tanggal, ac, kode, desc, price, qty, unit, flag, realPrice, realQty, bukti}], hitung:{planAmount(l), realAmount(l)}, total:{requested,approved,cashIn,mustPay,toSpend,spent,remaining}, ttdInitiator(bool)} */
export async function buatCpjPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "adhimitra-logo-rgba.png"));
  const sigArfan = await pdf.embedPng(await read("assets", "sig-arfan-cpj.png"));

  const rows = d.baris.length ? d.baris : [];
  const n = Math.max(rows.length, 1);
  const tBottom = ROW0 + n * RH;
  const sumTop = tBottom;
  const legendTop = sumTop + 4 * RH; // 723.27 di contoh
  const noteTop = legendTop + 5 * RH;
  const boxTop = noteTop + RH;
  const SIGH = 32.6;
  const boxBottom = boxTop + RH + SIGH + 2 * RH;
  const H = Math.max(H0, boxBottom + 32.7);
  const page = pdf.addPage([W, H]);
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);

  const T = (s, x, top, size = SZ, font = reg, color = BLACK, italic = false) =>
    s !== "" && page.drawText(s, { x, y: H - top - BASE * size, size, font, color, ...(italic ? { ySkew: degrees(6.62) } : {}) });
  const wd = (s, size = SZ, font = reg) => font.widthOfTextAtSize(s, size);
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.3, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.3, color: BLACK });
  const rect = (x0, x1, top, bot, c) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color: rgb(c[0], c[1], c[2]) });
  const center = (s, x0, x1, top, size = SZ, font = reg, italic = false) => T(s, (x0 + x1) / 2 - wd(s, size, font) / 2, top, size, font, BLACK, italic);
  const right = (s, xr, top, size = SZ, font = reg, italic = false) => T(s, xr - wd(s, size, font), top, size, font, BLACK, italic);
  const rp = (v, xr, top, font = reg) => { // "Rp" + angka rata kanan
    const s = fmt(v);
    right(s, xr, top, SZ, font);
    T("Rp", xr - wd(s, SZ, font) - RP_GAP - wd("Rp", SZ, font), top, SZ, font);
  };
  const fit = (s, maxW, font = reg, ellipsis = false) => {
    if (wd(s, SZ, font) <= maxW) return s;
    let t = s;
    while (t.length > 1 && wd(t + (ellipsis ? "…" : ""), SZ, font) > maxW) t = t.slice(0, -1);
    return t + (ellipsis ? "…" : "");
  };

  // Kepala halaman
  rect(L, R, 53.66, 60.01, [0, 0, 0]);
  T("PT. HARMONI MITRA INOVINDO", 181.69, 56.63, 3.85, reg, WHITE);
  T("CASH PAYMENT JOURNAL", 51.35, 77.56, 8.85, bold);
  page.drawImage(logo, { x: 260.52, y: H - (68.66 + 17.6), width: 29.13, height: 17.6 });
  T("No", 51.35, 100.52, 5.77); T(":", 64.63, 100.52, 5.77); T(d.nomor, 72.99, 99.11, SZ, bold);
  T("Date", 51.35, 112.31, 3.85, bold); T(":", 60.9, 112.31, 3.85, bold); T(tglPanjangCpj(d.tanggal), 72.99, 112.31, 3.85, bold);

  // Warna baris (sisi rencana) dan sorotan realisasi yang berbeda dari rencana
  const done = d.status === "REALIZED";
  rows.forEach((r, i) => {
    const y = ROW0 + i * RH;
    if (FILL[r.flag]) rect(L, 364.95, y, y + RH, FILL[r.flag]);
    const grey = [0.9529, 0.9529, 0.9529];
    const ra = d.hitung.realAmount(r, done);
    if (hasV(r.realPrice) && Number(r.realPrice) !== Number(r.price)) rect(X[9], X[10], y, y + RH, grey);
    if (hasV(r.realQty) && Number(r.realQty) !== Number(r.qty)) rect(X[10], X[11], y, y + RH, grey);
    if (ra !== null && ra !== d.hitung.planAmount(r)) rect(X[11], X[12], y, y + RH, grey);
  });
  // Pita header
  rect(L, 364.95, TOP, 135.59, [0.7176, 0.7176, 0.7176]);
  rect(364.66, R, TOP, 135.59, [0.6235, 0.7725, 0.9098]);

  // Garis tabel
  hline(L, R, 121.6); hline(L, R, ROW0);
  hline(119.44, 158.67, 128.53); hline(364.66, R, 128.53);
  for (let i = 0; i < n; i++) hline(L, R, ROW0 + (i + 1) * RH);
  X.forEach((x, i) => vline(x, i >= 10 ? 128.38 : TOP, i >= 10 && i < 13 ? tBottom : tBottom));
  vline(X[0], TOP, legendTop); vline(X[8], TOP, legendTop); vline(X[9], TOP, legendTop);
  vline(X[11], 128.38, sumTop + 3 * RH); vline(X[13], TOP, sumTop + 3 * RH);

  // Teks header
  center("A/C.", X[0], X[1], 128.01, SZ, bold); center("No.", X[1], X[2], 128.01, SZ, bold);
  center("Tanggal Transaksi", X[2], X[3], 128.01, SZ, bold); center("Description", X[4], X[5], 128.01, SZ, bold);
  center("Price", X[5], X[6], 128.01, SZ, bold); center("Qty", X[6], X[7], 128.01, SZ, bold); center("Unit", X[7], X[8], 128.01, SZ, bold); center("Amount", X[8], X[9], 128.01, SZ, bold);
  center("Realization", X[9], X[13], 124.55, SZ, bold);
  center("Price", X[9], X[10], 131.47, SZ, bold); center("Qty", X[10], X[11], 131.47, SZ, bold); center("Amount", X[11], X[12], 131.47, SZ, bold);
  center("Attachment Of Proof", X[12], X[13], 131.47, SZ, bold);

  // Isi baris
  rows.forEach((r, i) => {
    const t = ROW0 + i * RH + 2.95;
    center(r.ac ?? "", X[0], X[1], t, SZ, bold, true);
    center(String(i + 1), X[1], X[2], t, SZ, reg);
    right(tglPendekCpj(r.tanggal), 119.1, t, SZ, bold);
    T(r.kode ?? "", 120.59, t, SZ, bold);
    T(fit(r.desc ?? "", X[5] - 159.54 - 0.3), 159.54, t);
    rp(r.price, X[6] - 1.01, t);
    center(fmtQ(r.qty), X[6], X[7], t);
    center(r.unit ?? "", X[7], X[8], t);
    rp(d.hitung.planAmount(r), X[9] - 1.01, t);
    if (hasV(r.realPrice)) rp(r.realPrice, X[10] - 1.01, t);
    if (hasV(r.realQty)) center(fmtQ(r.realQty), X[10], X[11], t);
    const ra = d.hitung.realAmount(r, done);
    if (ra !== null) rp(ra, X[12] - 1.01, t);
    if (r.bukti) {
      page.drawRectangle({ x: 502.7, y: H - (ROW0 + i * RH + 4.6), width: 3.0, height: 3.4, color: rgb(0.86, 0.2, 0.2) });
      T(fit(r.bukti, X[13] - 508.09 - 2.9, reg, true), 508.09, t - 0.25);
    }
  });

  // Ringkasan (hanya penjumlahan)
  rect(L, 320.52, sumTop - 0.28, legendTop, [0.7176, 0.7176, 0.7176]);
  rect(364.66, 454.96, sumTop - 0.28, sumTop + 3 * RH, [0.6235, 0.7725, 0.9098]);
  for (let k = 0; k <= 3; k++) hline(L, R, sumTop + k * RH);
  hline(L, X[9] + 0.14, sumTop + 4 * RH);
  hline(X[9], R, sumTop + 3 * RH);
  const left = [["Total Permintaan", d.total.requested], ["Total Yang Disetujui", d.total.approved], ["Uang Saat ini", d.total.cashIn], ["Yang harus dibayarkan", d.total.mustPay]];
  const rightB = [["Yang perlu dibelanjakan", d.total.toSpend], ["Realisasi Uang Keluar", d.total.spent], ["Sisa Uang", d.total.remaining]];
  left.forEach(([lab, v], k) => { const t = sumTop + k * RH + 2.7; right(lab, 319.82, t, SZ, bold, true); rp(v, 363.8, t, bold); });
  rightB.forEach(([lab, v], k) => { const t = sumTop + k * RH + 2.7; right(lab, 454.26, t, SZ, bold, true); rp(v, 543.82, t, bold); });
  vline(X[0], sumTop, legendTop);

  // Legenda
  const lg = legendTop;
  center("Payment", L, 72.12, lg + 2.5, SZ, bold); T(":", 78.59, lg + 2.5, SZ, bold); T(d.payNote ?? "", 159.54, lg + 2.5, SZ, bold);
  [["Terbayarkan oleh non rekening CPJ", FILL.NON_CPJ], ["Over Budget CPJ Sebelumnya", FILL.OVER], ["Permintaan ditolak", FILL.REJECTED], ["Uang Masuk", FILL.INCOMING]].forEach(([txt, col], k) => {
    const y = lg + (k + 1) * RH;
    rect(L, 72.12, y - 0.23, y + RH + 0.1, col); T(":", 78.59, y + 2.5, SZ, bold); T(txt, 159.54, y + 2.5, SZ, bold);
  });
  center("Note", L, 72.12, noteTop + 2.5, SZ, bold); T(":", 78.59, noteTop + 2.5, SZ, bold); T(d.note ?? "", 159.54, noteTop + 2.5, SZ, bold);

  // Kotak tanda tangan
  const bx = [50.34, 197.48, 230.08];
  const r1 = boxTop + RH, r2 = r1 + SIGH, r3 = r2 + RH, r4 = r3 + RH;
  [boxTop, r1, r2, r3, r4].forEach((y) => hline(L, 230.22, y));
  bx.forEach((x) => vline(x, boxTop, r4));
  center("Initiator", bx[0], bx[1], boxTop + 2.65); center("Approval", bx[1], bx[2], boxTop + 2.65);
  if (d.ttdInitiator) {
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(sigArfan, { x: 106.51, y: H - (r1 + 0.15 + 32.03), width: 34.8, height: 32.03 });
    page.pushOperators(popGraphicsState());
  }
  center(d.initiatorNama ?? "", bx[0], bx[1], r2 + 2.66); center(d.approverNama ?? "", bx[1], bx[2], r2 + 2.66);
  center(d.initiatorJabatan ?? "", bx[0], bx[1], r3 + 2.66, SZ, bold); center(d.approverJabatan ?? "", bx[1], bx[2], r3 + 2.66, SZ, bold);

  return Buffer.from(await pdf.save());
}
