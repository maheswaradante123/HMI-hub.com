// PDF "Realisasi Order" (RO). A4 lanskap, ukuran dan posisi diukur dari RO-HBR-001-II-26.pdf (satuan pt).
// Baris produk tambahan menggeser semua yang di bawahnya; halaman memanjang bila perlu.
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 842.88, H0 = 595.92, BASE = 0.4284, SKEW = 6.62;
const BLACK = rgb(0, 0, 0), PINK = rgb(0.9176, 0.8196, 0.8627), BLUE = rgb(0.2588, 0.5216, 0.9569), BAR = rgb(0.6, 0.6, 0.6), WHITE = rgb(1, 1, 1);
const SZ = 9.33, ROW = 17.5;
const COL = [49.9, 75.5, 213.2, 253.4, 297.2, 535.2, 652.4, 790.7];
const BULAN_EN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const BULAN_ID = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
const p2 = (n) => String(n).padStart(2, "0");
export const tglEn = (iso) => { if (!iso) return ""; const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return `${p2(d)} ${BULAN_EN[m - 1]} ${y}`; };
export const tglId = (iso) => { if (!iso) return ""; const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return `${p2(d)} ${BULAN_ID[m - 1]} ${y}`; };
const rp = (n) => "Rp" + Math.round(n).toLocaleString("en-US");
const qty = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });

export const PAY_OPTS = [["Cash Before Delivery", true], ["Cash and Carry (Transfer)", true], ["Cash On Delivery", true], ["Tempo (30 Hari)", false]];
// Metode bayar di sistem -> baris template yang dicentang
export const PAY_MAP = { QRIS: 0, Transfer: 1, Cash: 2, Tempo: 3 };

/** d: {nomor, tanggal, pemesan, alamat, telepon, tglKirim, waktuKirim, baris[{nama,qty,unit,potong,kemas,harga}], bayar, kirim, catatan, pembuat?, jabatan?, tandaTangan?} */
export async function buatRoPdf(d) {
  const rows = d.baris.length ? d.baris : [{}];
  const s = (rows.length - 1) * ROW;
  const H = Math.max(H0, 501 + s + 95);
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const page = pdf.addPage([W, H]);
  const T = (t, x, top, size, font = reg, color = BLACK, skew = 0) =>
    t && page.drawText(t, { x: skew ? x + 1.6 : x, y: H - top - BASE * size, size, font, color, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const wd = (t, size, font = reg) => font.widthOfTextAtSize(t, size);
  const center = (t, x0, x1, top, size, font = reg) => T(t, (x0 + x1) / 2 - wd(t, size, font) / 2, top, size, font);
  const fit = (t, maxW, size, font = reg) => { t = String(t ?? ""); while (t && wd(t, size, font) > maxW) t = t.slice(0, -1); return t; };
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.3, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.3, color: BLACK });
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);

  T("REALISASI ORDER", 51.9, 86.3, 38.11, bold);
  const meta = (l, v, top, vb = false) => { T(l, 51.9, top, SZ, bold); T(":", 152.0, top, SZ, bold); T(v, 162.7, top, SZ, vb ? bold : reg); };
  meta("Nomor", d.nomor, 143.0); meta("Tanggal", tglEn(d.tanggal), 155.2);
  meta("Nama Pemesan", fit(d.pemesan, 360, SZ, bold), 179.7, true);
  meta("Alamat Pengiriman", fit(d.alamat, 372, SZ), 192.0); meta("No. Telepon", d.telepon ?? "", 204.2);
  T("Tanggal Kirim", 537.2, 179.7, SZ, bold); T(": " + tglId(d.tglKirim), 616.8, 179.7, SZ, bold);
  T("Waktu Pengiriman", 537.2, 192.0, SZ, bold); T(": " + fit(d.waktuKirim, 170, SZ, bold), 616.0, 192.0, SZ, bold);

  // tabel produk
  const bot = 252.3 + rows.length * ROW; // dasar tabel
  rect(49.6, 790.9, 235.1, 252.6, PINK);
  hline(49.6, 790.9, 235.4); hline(49.6, 790.9, 252.3);
  ["No", "Nama Produk", "Qty", "Satuan", "Jenis Potongan", "Jenis Pengemasan", "Harga"].forEach((h, i) => center(h, COL[i], COL[i + 1], 242.7, SZ, bold));
  rows.forEach((r, i) => {
    const top = 260.2 + i * ROW;
    if (r.nama === undefined) { hline(49.6, 790.9, 252.3 + (i + 1) * ROW - 0.5); return; }
    center(String(i + 1), COL[0], COL[1], top, SZ);
    T(fit(r.nama, COL[2] - COL[1] - 6, SZ), 77.6, top, SZ);
    center(qty(r.qty), COL[2], COL[3], top, SZ);
    center(r.unit ?? "", COL[3], COL[4], top, SZ);
    T(fit(r.potong, COL[5] - COL[4] - 4, SZ), 299.2, top, SZ);
    center(fit(r.kemas, COL[6] - COL[5] - 4, SZ, bold), COL[5], COL[6], top, SZ, bold);
    const h = rp(r.harga); T(h, 788.6 - wd(h, SZ, bold), top, SZ, bold);
    hline(49.6, 790.9, 269.8 + i * ROW);
  });
  COL.forEach((x) => vline(x, 235.1, bot + 0.3));

  // checkbox bergaya template
  const rr = (w, h, r) => `M ${r} 0 L ${w - r} 0 Q ${w} 0 ${w} ${r} L ${w} ${h - r} Q ${w} ${h} ${w - r} ${h} L ${r} ${h} Q 0 ${h} 0 ${h - r} L 0 ${r} Q 0 0 ${r} 0 Z`;
  const box = (top, on) => {
    const x = 147.6, y = H - top;
    if (on) {
      page.drawSvgPath(rr(11.2, 11.2, 1.9), { x, y, color: BLUE, borderWidth: 0 });
      page.drawSvgPath("M 1.9 5.6 L 4.7 7.8 L 8.9 2.8", { x, y, borderColor: WHITE, borderWidth: 1.05, borderLineCap: 1 });
    } else {
      page.drawSvgPath(rr(10, 10, 1.4), { x: x + 0.6, y: y - 0.6, borderColor: BLUE, borderWidth: 1.2 });
    }
  };
  const bn = (t, x, top, ital) => T(t, x, top, SZ, bold, BLUE, ital ? SKEW : 0);
  const payIdx = PAY_MAP[d.bayar] ?? -1;
  T("Metode Pembayaran", 51.9, 286.5 + s, SZ, bold); T(":", 140.2, 286.5 + s, SZ, bold);
  PAY_OPTS.forEach(([t, it], i) => { box(282.3 + s + i * 12.25, i === payIdx); bn(t, it ? 161.4 : 162.7, 287.1 + s + i * 12.25, it); });
  const del = d.kirim === "Delivery" ? 0 : d.kirim === "Pick Up di Toko" ? 1 : -1;
  T("Metode Pengiriman", 51.9, 347.7 + s, SZ, bold); T(":", 139.5, 347.7 + s, SZ, bold);
  box(343.6 + s, del === 0); bn("Delivery", 161.4, 348.3 + s, true);
  box(355.8 + s, del === 1); bn("Pick up", 161.4, 360.6 + s, true); bn("di Toko", 161.4 + wd("Pick up", SZ, bold) + 2.5, 360.6 + s, false);
  T("Catatan", 51.9, 384.5 + s, SZ, bold); T(":", 140.3, 384.5 + s, SZ, bold); T(fit(d.catatan || "-", 600, SZ, bold), 147.6, 385.1 + s, SZ, bold);

  // pembuat dan tanda tangan
  T("Dibuat oleh:", 51.9, 409.6 + s, SZ);
  if (d.tandaTangan) {
    const im = await pdf.embedPng(await read("assets", "sig-syifa-ro.png"));
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(im, { x: 72.3, y: H - (460.2 + s), width: 58.9, height: 35.0 });
    page.pushOperators(popGraphicsState());
  }
  center(d.jabatan ?? "Marketing", 49.6, 161.0, 470.8 + s, SZ);
  hline(49.6, 161.0, 477.4 + s);
  center(d.pembuat ?? "", 49.6, 161.0, 482.5 + s, SZ);
  rect(49.6, 790.9, 488.8 + s, 501.0 + s, BAR);
  return pdf.save();
}
