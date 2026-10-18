// PDF "Production Order". A4 lanskap, ukuran dan posisi diukur dari PRODUCTION_ORDER.pdf (satuan pt).
import { PDFDocument, rgb, degrees } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 842.88, H0 = 595.92, BASE = 0.4284, SKEW = 6.62, SZ = 9.23, ROW = 13.85, LH = 11.0;
const BLACK = rgb(0, 0, 0), PINK = rgb(0.9176, 0.8196, 0.8627);
const C1 = [49.9, 131.3, 348.2, 406.4, 439.3, 555.3, 660.9];
const BULAN_ID = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
const p2 = (n) => String(n).padStart(2, "0");
const parts = (iso) => String(iso).slice(0, 10).split("-").map(Number);
export const tglId = (iso) => { if (!iso) return ""; const [y, m, d] = parts(iso); return `${p2(d)} ${BULAN_ID[m - 1]} ${y}`; };
export const tglSlash = (iso) => { if (!iso) return ""; const [y, m, d] = parts(iso); return `${p2(d)}/${p2(m)}/${y}`; };
/** "08-09 Oktober 2026" bila satu bulan, selain itu dua tanggal lengkap. */
export function leadTime(dari, sampai) {
  if (!dari && !sampai) return "";
  if (!dari || !sampai || dari === sampai) return tglId(dari || sampai);
  const [y1, m1, d1] = parts(dari), [y2, m2, d2] = parts(sampai);
  if (y1 === y2 && m1 === m2) return `${p2(d1)}-${p2(d2)} ${BULAN_ID[m2 - 1]} ${y2}`;
  return `${tglId(dari)} - ${tglId(sampai)}`;
}
const qty = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });

/** d: {nomor, tanggal, customer, telepon, leadTime, roNomor, tglOrder, tglKirim, baris[{nama,qty,unit,potong,kemas}], metode, jadwal, alamat, pic, kodeSapi, catatan} */
export async function buatProdPdf(d) {
  const rows = d.baris.length ? d.baris : [{}];
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "lamitra-logo-black.png"));
  const wd = (t, size, font = reg) => font.widthOfTextAtSize(t, size);
  // pecah alamat menjadi baris sesuai lebar kolom nilai
  const wrap = (t, maxW, size, font) => {
    const out = []; let cur = "";
    for (const w of String(t ?? "").split(/\s+/).filter(Boolean)) {
      const nx = cur ? cur + " " + w : w;
      if (wd(nx, size, font) > maxW && cur) { out.push(cur); cur = w; } else cur = nx;
    }
    if (cur) out.push(cur);
    return out.length ? out : [""];
  };
  const addr = wrap(d.alamat, 268, SZ, reg);
  const s1 = (rows.length - 1) * ROW;
  const extra = (addr.length - 2) * LH; // posisi dasar diukur dari contoh dengan alamat dua baris
  const H = Math.max(H0, 421.7 + s1 + Math.max(0, extra) + 80);
  const page = pdf.addPage([W, H]);
  const T = (t, x, top, size, font = reg, skew = 0) =>
    t && page.drawText(t, { x: skew ? x + 1.6 : x, y: H - top - BASE * size, size, font, color: BLACK, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const center = (t, x0, x1, top, size, font = reg) => T(t, (x0 + x1) / 2 - wd(t, size, font) / 2, top, size, font);
  const fit = (t, maxW, size, font = reg) => { t = String(t ?? ""); while (t && wd(t, size, font) > maxW) t = t.slice(0, -1); return t; };
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.3, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.3, color: BLACK });

  T("PRODUCTION ORDER", 51.9, 99.2, 37.69, bold);
  page.drawImage(logo, { x: 680.2, y: H - 144.2, width: 79.0, height: 64.6 });
  const L = (t, top, upright = false) => T(t, upright ? 51.9 : 50.6, top, SZ, bold, upright ? 0 : SKEW);
  L("Number", 156.4); T(":", 174.8, 156.4, SZ, bold); T(d.nomor, 186.9, 156.4, SZ);
  L("Publish Date", 170.3); T(":", 174.8, 170.3, SZ, bold); T(tglSlash(d.tanggal), 186.9, 170.3, SZ);
  L("Customer", 196.2); T(":", 174.8, 196.2, SZ, bold); T(fit(d.customer, 340, SZ, bold), 186.9, 196.2, SZ, bold);
  L("No. Telepon", 210.1, true); T(":", 174.8, 210.1, SZ, bold); T(d.telepon ?? "", 186.9, 210.1, SZ);
  const R = (t, top) => T(t, 556.0, top, SZ, bold, SKEW);
  R("Lead Time", 156.4); T(": " + (d.leadTime ?? ""), 662.9, 156.4, SZ);
  R("RO Number", 170.3); T(": " + (d.roNomor ?? ""), 662.9, 170.3, SZ);
  R("Order Date", 196.2); T(": " + tglId(d.tglOrder), 662.9, 196.2, SZ, bold);
  R("Delivery Date", 210.1); T(": " + fit(d.tglKirim ?? "", 125, SZ, bold), 662.9, 210.1, SZ, bold);

  // tabel produk
  page.drawRectangle({ x: 49.6, y: H - 256.2, width: 661.2 - 49.6, height: 14.5, color: PINK });
  hline(49.6, 661.2, 242.0); hline(49.6, 661.2, 255.9);
  ["No", "Nama Produk", "Qty", "Satuan", "Jenis Potongan", "Jenis Pengemasan"].forEach((h, i) => center(h, C1[i], C1[i + 1], 248.2, SZ, bold));
  rows.forEach((r, i) => {
    const top = 262.0 + i * ROW;
    if (r.nama !== undefined) {
      center(String(i + 1), C1[0], C1[1], top, SZ);
      T(fit(r.nama, C1[2] - C1[1] - 5, SZ), 133.3, top, SZ);
      center(qty(r.qty), C1[2], C1[3], top, SZ);
      center(r.unit ?? "", C1[3], C1[4], top, SZ);
      T(fit(r.potong, C1[5] - C1[4] - 4, SZ), 441.4, top, SZ);
      T(fit(r.kemas, C1[6] - C1[5] - 4, SZ), 557.3, top, SZ);
    }
    hline(49.6, 661.2, 269.7 + i * ROW);
  });
  C1.forEach((x) => vline(x, 241.7, 270.0 + s1));

  // tabel pengiriman
  const y0 = 292.8 + s1;
  const rh = [ROW, ROW, ROW + LH * (addr.length - 1), ROW, ROW];
  const ys = [y0]; rh.forEach((h) => ys.push(ys.at(-1) + h));
  ys.forEach((y) => hline(49.6, 406.7, y));
  [49.9, 131.3, 406.4].forEach((x) => vline(x, y0 - 0.3, ys.at(-1) + 0.3));
  T("Metode Pengiriman", 51.9, 298.9 + s1, SZ, bold); T(d.metode ?? "", 133.3, 298.9 + s1, SZ, bold);
  T("Jadwal Pengiriman", 51.9, 312.8 + s1, SZ); T(fit(d.jadwal, 270, SZ, bold), 133.3, 312.8 + s1, SZ, bold);
  T("Alamat Pengiriman", 51.9, 331.8 + s1 + extra / 2, SZ);
  addr.forEach((ln, i) => T(ln, 133.3, 326.6 + s1 + i * LH, SZ));
  T("PIC Pengiriman", 51.9, 351.4 + s1 + extra, SZ); T(fit(d.pic, 270, SZ, bold), 133.3, 351.4 + s1 + extra, SZ, bold);
  T("Kode Sapi", 51.9, 365.3 + s1 + extra, SZ, bold); T(fit(d.kodeSapi || "-", 270, SZ, bold), 133.3, 365.3 + s1 + extra, SZ, bold);
  T("Note", 408.5, 298.9 + s1, SZ, bold); T(":", 429.8, 298.9 + s1, SZ, bold); T(fit(d.catatan || "-", 340, 7.69), 441.4, 300.2 + s1, 7.69);
  T("*Dokumen ini diterbitkan menggunakan media digital, tidak memerlukan tanda tangan sebagai tanda persetujuan", 51.9, 415.0 + s1 + extra, 7.69);
  return pdf.save();
}
