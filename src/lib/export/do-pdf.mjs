// PDF dan Excel Surat Jalan (Delivery Order). A5 lanskap, ukuran dan posisi diukur dari DO-005-X-26.pdf (satuan pt).
// Baris barang tambahan menggeser catatan, tanda tangan, dan garis bawah; halaman memanjang agar tetap satu lembar.
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import ExcelJS from "exceljs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglPl } from "./pl-pdf.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.92, H0 = 420, BASE = 0.4284, SKEW = 6.62, SZ = 9.89, ROW = 13.6;
const BLACK = rgb(0, 0, 0), GREEN = rgb(0.851, 0.9176, 0.8275), BAR = rgb(0.4, 0.4, 0.4);
const COL = [70.2, 118.4, 282.9, 398.5, 525.2];
const SIG = [70.2, 178.0, 282.9, 398.5];
export const DIREKTUR = "Misbahudin";
// Format Indonesia: koma untuk desimal, titik untuk ribuan (10 kg -> "10,000").
export const kgFmt = (n) => {
  const [i, f] = Math.abs(Number(n)).toFixed(3).split(".");
  return (Number(n) < 0 ? "-" : "") + i.replace(/\B(?=(\d{3})+(?!\d))/g, ".") + "," + f;
};

/** d: {nomor, tanggal(iso), kepada, telepon, baris[{desc, jenis, qty (angka, atau teks untuk surat jalan arsip), unit}], catatan, pengawas, penerima} */
export async function buatSuratJalanPdf(d) {
  const rows = d.baris.length ? d.baris : [];
  const n = Math.max(rows.length, 1);
  const s = (n - 1) * ROW;
  const H = H0 + s;
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const sig = await pdf.embedPng(await read("assets", "sig-misbahudin-pl.png"));
  const bull = await pdf.embedPng(await read("assets", "lamitra-bull-black.png"));
  const page = pdf.addPage([W, H]);
  const T = (t, x, top, size, font = reg, skew = 0) =>
    t && page.drawText(t, { x: skew ? x + 1.6 : x, y: H - top - BASE * size, size, font, color: BLACK, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const wd = (t, size, font = reg) => font.widthOfTextAtSize(t, size);
  const center = (t, x0, x1, top, size, font = reg, skew = 0) => t && T(t, (x0 + x1) / 2 - wd(t, size, font) / 2, top, size, font, skew);
  const fit = (t, maxW, size, font = reg) => { t = String(t ?? ""); while (t && wd(t, size, font) > maxW) t = t.slice(0, -1); return t; };
  const hline = (x0, x1, y) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: 0.3, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.3, color: BLACK });
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);

  T("SURAT", 72.3, 69.9, 40.39, bold); T("JALAN", 197.8, 69.9, 40.39, bold); // kerning contoh antar kata
  page.drawImage(bull, { x: 461.9, y: H - 113.8, width: 60.6, height: 60 });
  T("No.", 72.3, 113.2, SZ); T(":", 112.5, 113.2, SZ); T(d.nomor, 119.2, 113.2, SZ, bold, SKEW);
  T("Tanggal", 72.3, 126.2, SZ); T(":", 112.5, 126.2, SZ); T(tglPl(d.tanggal), 120.6, 126.2, SZ);
  T("Kepada", 72.3, 139.2, SZ); T(":", 112.5, 139.2, SZ); T(fit(d.kepada, 215, 9.06), 120.6, 139.6, 9.06);
  if (d.telepon) { T("No. Telepon", 339.3, 139.2, SZ, bold); T(":", 393.9, 139.2, SZ, bold); T(d.telepon, 400.7, 139.2, SZ); }

  rect(69.9, 525.5, 158.9, 188.0, GREEN);
  hline(69.9, 525.5, 159.2); hline(69.9, 525.5, 187.7);
  ["No", "Deskripsi", "Jenis", "Keterangan"].forEach((h, i) => center(h, COL[i], COL[i + 1], 172.6, SZ, bold));
  rows.forEach((r, i) => {
    const top = 193.6 + i * ROW;
    center(String(i + 1), COL[0], COL[1], top, SZ);
    T(fit(r.desc, COL[2] - COL[1] - 6, 10.71), 120.6, top + 0.3, 10.71);
    center(fit(r.jenis, COL[3] - COL[2] - 6, SZ), COL[2], COL[3], top, SZ);
    center(typeof r.qty === "string" ? fit(r.qty, COL[4] - COL[3] - 6, SZ) : `${kgFmt(r.qty)}${r.unit ? " " + r.unit : ""}`, COL[3], COL[4], top + 0.6, SZ);
  });
  for (let i = 0; i < n; i++) hline(69.9, 525.5, 201.3 + i * ROW);
  const bot = 201.6 + (n - 1) * ROW;
  COL.forEach((x) => vline(x, 158.9, bot));

  T("Note", 72.3, 206.6 + s, SZ, bold); T(":", 112.5, 206.6 + s, SZ, bold); T(fit(d.catatan || "-", 400, SZ), 120.6, 206.6 + s, SZ);
  page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
  page.drawImage(sig, { x: 191.1, y: H - (304.8 + s), width: 75.4, height: 69.8 });
  page.pushOperators(popGraphicsState());
  [["Pengawas", d.pengawas], ["Direktur Produksi", DIREKTUR], ["Pembeli / Penerima", d.penerima]].forEach(([lab, nm], i) => {
    center(lab, SIG[i], SIG[i + 1], 315.4 + s, SZ, bold, SKEW);
    center(fit(nm ?? "", SIG[i + 1] - SIG[i] - 4, SZ), SIG[i], SIG[i + 1], 328.4 + s, SZ, reg, SKEW);
  });
  hline(69.9, 398.8, 323.1 + s);
  rect(69.9, 525.5, 348.7 + s, 362.3 + s, BAR);
  return pdf.save();
}

export async function buatSuratJalanXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Surat Jalan", { pageSetup: { orientation: "landscape", paperSize: 11, fitToPage: true, fitToWidth: 1, fitToHeight: 0 }, views: [{ showGridLines: false }] });
  const thin = { style: "thin", color: { argb: "FF000000" } }, box = { top: thin, bottom: thin, left: thin, right: thin };
  const F = (o = {}) => ({ name: "Cairo", size: 10, ...o });
  ws.columns = [{ width: 4 }, ...[48.2, 164.5, 115.6, 126.7].map((p) => ({ width: Math.round((p / 5.6) * 10) / 10 }))];
  ws.getCell("B2").value = "SURAT JALAN"; ws.getCell("B2").font = F({ size: 30, bold: true }); ws.getRow(2).height = 50;
  const logo = wb.addImage({ filename: path.join(DIR, "assets", "lamitra-bull-black.png"), extension: "png" });
  ws.addImage(logo, { tl: { col: 4.2, row: 0.5 }, ext: { width: 70, height: 70 } });
  const meta = (r, l, v, o = {}) => { ws.getCell(r, 2).value = l; ws.getCell(r, 2).font = F(); ws.getCell(r, 3).value = ": " + (v ?? ""); ws.getCell(r, 3).font = F(o); };
  meta(4, "No.", d.nomor, { bold: true, italic: true }); meta(5, "Tanggal", tglPl(d.tanggal)); meta(6, "Kepada", d.kepada);
  if (d.telepon) { ws.getCell(6, 5).value = "No. Telepon  : " + d.telepon; ws.getCell(6, 5).font = F(); ws.getCell(6, 5).alignment = { horizontal: "right" }; }
  const hr = 8;
  ["No", "Deskripsi", "Jenis", "Keterangan"].forEach((h, i) => {
    const c = ws.getCell(hr, i + 2); c.value = h; c.font = F({ bold: true }); c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
    c.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD9EAD3" } };
  });
  ws.getRow(hr).height = 24;
  let r = hr + 1;
  d.baris.forEach((b, i) => {
    [i + 1, b.desc, b.jenis, typeof b.qty === "string" ? b.qty : Number(b.qty)].forEach((v, j) => {
      const c = ws.getCell(r, j + 2); c.value = v; c.font = F(); c.border = box;
      c.alignment = { horizontal: j === 1 ? "left" : "center", vertical: "middle" };
      if (j === 3 && typeof b.qty !== "string") c.numFmt = `0.000"${b.unit ? " " + b.unit : ""}"`;
    });
    r++;
  });
  ws.getCell(r, 2).value = "Note"; ws.getCell(r, 2).font = F({ bold: true });
  ws.getCell(r, 3).value = ": " + (d.catatan || "-"); ws.getCell(r, 3).font = F();
  r += 2;
  const id = wb.addImage({ filename: path.join(DIR, "assets", "sig-misbahudin-pl.png"), extension: "png" });
  ws.addImage(id, { tl: { col: 2.3, row: r - 1 }, ext: { width: 85, height: 79 } });
  r += 5;
  [["Pengawas", d.pengawas], ["Direktur Produksi", DIREKTUR], ["Pembeli / Penerima", d.penerima]].forEach(([l, nm], i) => {
    const col = i + 2;
    const a = ws.getCell(r, col); a.value = l; a.font = F({ bold: true, italic: true }); a.alignment = { horizontal: "center" }; a.border = { bottom: thin };
    const b = ws.getCell(r + 1, col); b.value = nm ?? ""; b.font = F({ italic: true }); b.alignment = { horizontal: "center" };
  });
  return wb;
}
