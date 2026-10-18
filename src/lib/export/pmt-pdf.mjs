// Pembuat PDF "Pemasukan Toko" (Letter lanskap, hairline hitam, logo La Mitra merah). Posisi diukur dari contoh 6d79e8cc-crj.pdf (satuan pt).
import { PDFDocument, rgb, degrees } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 792, H = 612;
const BASE = 0.4284, BASE_ARIAL = 0.8034;
const BLACK = rgb(0, 0, 0);
const GRAY = rgb(0.8, 0.8, 0.8);
const X = [50.3, 74.4, 133.3, 260.8, 329.8, 398.9, 463.3, 527.8, 596.9, 665.9, 742.0];
const L = 50.3, R = 742.2, BOTTOM = 550.7, ROW = 9.7, SUM = 11.6;
const CODES = ["cash", "qris", "debit", "grab", "tf", "deposited"]; // kolom ke-4..9
const HEAD = ["NO", "TANGGAL", "DESCRIPTION", "CASH", "QRIS", "DEBIT", "GRAB", "TF REK HMI", "DISETOR", "Attachment Of Proof"];
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTH = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const ymd = (iso) => { const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return { y, m, d }; };
export const tglPendek = (iso) => { if (!iso) return ""; const { y, m, d } = ymd(iso); return `${d}-${MON[m - 1]}-${y}`; };
export const tglPanjang = (iso) => {
  if (!iso) return "";
  const { y, m, d } = ymd(iso);
  const wd = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return `${DAY[wd]}, ${MONTH[m - 1]} ${String(d).padStart(2, "0")}, ${y}`;
};
const num = (n) => Math.abs(Math.round(n)).toLocaleString("en-US");

/** d: {nomor, dari, sampai, baris[{tanggal, desc, cash,qris,debit,grab,tf,deposited}], piutang[{nama, jumlah}], total{cash..deposited, mustDeposit, income}} */
export async function buatPemasukanTokoPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const arial = await pdf.embedFont(await read("fonts", "LiberationSans-Regular.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "lamitra-logo-red.png"));
  let page;
  const T = (s, x, top, size, font = reg, color = BLACK) =>
    page.drawText(s, { x, y: H - top - (font === arial ? BASE_ARIAL : BASE) * size, size, font, color });
  const wd = (s, size, font = reg) => font.widthOfTextAtSize(s, size);
  const hline = (x0, x1, y, color = BLACK) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.5, color });
  const vline = (x, y0, y1, color = BLACK) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.5, color });
  const centerIn = (s, x0, x1, top, size, font) => T(s, (x0 + x1) / 2 - wd(s, size, font) / 2, top, size, font);
  const money = (n, ci, top, font = reg) => {
    const xr = X[ci + 1] - 1.6; // sisi kanan angka
    const s = num(n);
    const left = xr - wd(s, 7.42, font);
    T(s, left, top, 7.42, font);
    T(n < 0 ? "-Rp" : "Rp", left - (n < 0 ? 18.3 : 15.0), top, 7.42, font);
  };

  // Halaman pertama: judul, logo, keterangan
  page = pdf.addPage([W, H]);
  hline(L - 0.7, R, 53.3, GRAY); hline(L - 0.7, R, 90.4, GRAY);
  vline(50.1, 52.8, 90.9, GRAY); vline(741.7, 52.8, 90.9, GRAY);
  T("PEMASUKAN TOKO", 51.9, 70.9, 14.21, bold);
  page.drawImage(logo, { x: 702.3, y: H - 89.0, width: 38.5, height: 37.1 });
  T("NO", 51.9, 101.7, 6.8, arial); T(":", 64.0, 101.7, 6.8, arial); if (d.nomor) T(d.nomor, 68.0, 101.7, 6.8, arial);
  T("PERIODE", 76.5, 111.0, 6.8, arial);
  T("From", 51.9, 120.3, 6.8, arial); T(tglPanjang(d.dari), 76.0, 120.3, 6.8, arial);
  T("To", 51.9, 129.5, 6.8, arial); T(tglPanjang(d.sampai), 76.0, 129.5, 6.8, arial);

  let top = 146.3;
  const header = () => {
    hline(L, R, top); hline(L, R, top + 14.8);
    HEAD.forEach((h, i) => { if (i === 1) T(h, 76.0, top + 6.7, 7.42, bold); else centerIn(h, X[i], X[i + 1], top + 6.7, 7.42, bold); });
    return top + 14.8;
  };
  let y0 = top; // atas bingkai halaman ini
  let y = header();
  const closeFrame = (yEnd) => { X.forEach((x) => vline(x, y0, yEnd)); hline(L, R, yEnd); };

  const baris = d.baris.length ? d.baris : [];
  for (const r of baris) {
    if (y + ROW > BOTTOM + 0.1) {
      closeFrame(y);
      page = pdf.addPage([W, H]); y0 = 53.3; y = 53.3; hline(L, R, y);
    }
    const t = y + 4.5;
    if (r.tanggal) T(tglPendek(r.tanggal), 76.0, t, 7.42);
    // deskripsi dipotong agar tidak melewati kolom
    let desc = String(r.desc ?? ""); const maxW = X[3] - 134.9 - 2;
    while (desc && wd(desc, 7.42) > maxW) desc = desc.slice(0, -1);
    T(desc, 134.9, t, 7.42);
    CODES.forEach((c, i) => { const v = Number(r[c] ?? 0); if (v) money(v, 3 + i, t); });
    y += ROW; hline(L, R, y);
  }

  // Ringkasan: Total, uang cash yang harus disetor, piutang, Total Pendapatan
  const piut = d.piutang ?? [];
  const need = (2 + piut.length + 1) * SUM;
  if (y + need > BOTTOM + 0.1) { closeFrame(y); page = pdf.addPage([W, H]); y0 = 53.3; y = 53.3; hline(L, R, y); }
  const dataEnd = y;
  const sumRow = (label, fn, full) => {
    const t = y + 5.0;
    T(label, 259.1 - wd(label, 7.42, bold), t, 7.42, bold);
    fn(t); y += SUM; hline(full ? L : X[3] - 0, R, y);
  };
  const tt = d.total;
  sumRow("Total", (t) => { CODES.forEach((c, i) => money(tt[c], 3 + i, t, bold)); }, true);
  sumRow("Uang cash yang harus disetor", (t) => money(tt.mustDeposit, 3, t, bold), true);
  piut.forEach((p) => sumRow(`Piutang ${p.nama}`, (t) => money(Number(p.jumlah), 3, t, bold), true));
  const lastTop = y;
  const lbl = "Total Pendapatan"; const t = y + 5.0;
  T(lbl, 259.1 - wd(lbl, 7.42, bold), t, 7.42, bold);
  const s = num(tt.income), xr = X[10 - 1 + 0] + 0; // kolom DISETOR (indeks 8) -> sisi kanan X[9]
  const left = X[9] - 1.6 - wd(s, 7.42, bold); T(s, left, t, 7.42, bold); T("Rp", left - 15.0, t, 7.42, bold);
  y += SUM; hline(L, R, y);
  // garis tegak
  [X[0], X[3], X[9], X[10]].forEach((x) => vline(x, y0, y));
  [X[1], X[2]].forEach((x) => vline(x, y0, dataEnd));
  [X[4], X[5], X[6], X[7], X[8]].forEach((x) => vline(x, y0, lastTop));
  void xr;
  return pdf.save();
}
