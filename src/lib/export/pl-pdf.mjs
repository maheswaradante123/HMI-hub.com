// PDF dan Excel Packing List. A4 potret, ukuran dan posisi diukur dari Packing_List.pdf (satuan pt).
// Baris tambahan menggeser total, catatan, dan tanda tangan ke bawah (satu lembar memanjang bila lebih dari 22 baris).
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import ExcelJS from "exceljs";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.92, H0 = 842.88, BASE = 0.4284, SKEW = 6.62, SZ = 10.02, ROW = 18.8, BASE_ROWS = 22;
const BLACK = rgb(0, 0, 0), GREEN = rgb(0.851, 0.9176, 0.8275), BAR = rgb(0.4, 0.4, 0.4);
const COL = [18.5, 79.3, 165.1, 331.1, 501.5];
const BULAN = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
export const tglPl = (iso) => { if (!iso) return ""; const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return `${d} ${BULAN[m - 1]} ${y}`; };
export const kg = (n) => String(Math.round(Number(n) * 1000) / 1000);
const pad2 = (n) => String(n).padStart(2, "0");
export const DIREKTUR = "Misbahudin";

/** d: {nomor, tanggal, kepada, telepon, baris[{jenis, net, gross}], catatan, pengawas, penerima} */
export async function buatPackingListPdf(d) {
  const rows = d.baris;
  const dy = (Math.max(rows.length, 1) - BASE_ROWS) * ROW;
  const H = Math.max(H0, H0 + dy);
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const sig = await pdf.embedPng(await read("assets", "sig-misbahudin-pl.png"));
  const page = pdf.addPage([W, H]);
  const T = (t, x, top, size, font = reg, skew = 0) =>
    t && page.drawText(t, { x: skew ? x + 1.6 : x, y: H - top - BASE * size, size, font, color: BLACK, ...(skew ? { ySkew: degrees(skew) } : {}) });
  const wd = (t, size, font = reg) => font.widthOfTextAtSize(t, size);
  const center = (t, x0, x1, top, size, font = reg, skew = 0) => t && T(t, (x0 + x1) / 2 - wd(t, size, font) / 2, top, size, font, skew);
  const fit = (t, maxW, size, font = reg) => { t = String(t ?? ""); while (t && wd(t, size, font) > maxW) t = t.slice(0, -1); return t; };
  const hline = (x0, x1, y, th = 0.3) => page.drawLine({ start: { x: x0, y: H - y }, end: { x: x1, y: H - y }, thickness: th, color: BLACK });
  const vline = (x, y0, y1) => page.drawLine({ start: { x, y: H - y0 }, end: { x, y: H - y1 }, thickness: 0.3, color: BLACK });
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));
  page.node.setExtGState(PDFName.of("GSM"), gs);

  T("Packing List", 20.7, 75.6, 32.58, bold);
  T("No.", 20.7, 129.1, SZ); T(":", 74.6, 129.1, SZ); T(d.nomor, 80.0, 129.1, SZ, bold, SKEW);
  T("Tanggal", 20.7, 142.9, SZ); T(":", 74.6, 142.9, SZ); T(tglPl(d.tanggal), 81.4, 142.9, SZ);
  T("Kepada", 20.7, 156.1, SZ); T(":", 74.6, 156.1, SZ); T(fit(d.kepada, 270, SZ), 81.4, 156.1, SZ);
  if (d.telepon) { T("No. Telepon", 365.9, 156.1, SZ); T(": " + d.telepon, 419.8, 156.1, SZ); }

  rect(18.2, 501.8, 176.0, 205.5, GREEN);
  hline(18.2, 501.8, 176.4); hline(18.2, 501.8, 205.2);
  ["No Item", "Jenis Item", "Net Weight (Kg)", "Gross Weight (Kg)"].forEach((h, i) => center(h, COL[i], COL[i + 1], 189.9, SZ, bold));
  const n = Math.max(rows.length, 1);
  rows.forEach((r, i) => {
    const top = 213.7 + i * ROW;
    center(pad2(i + 1), COL[0], COL[1], top, SZ);
    center(fit(r.jenis, COL[2] - COL[1] - 6, SZ), COL[1], COL[2], top, SZ);
    center(kg(r.net), COL[2], COL[3], top, SZ);
    center(kg(r.gross), COL[3], COL[4], top, SZ);
  });
  for (let i = 0; i < n; i++) hline(18.2, 501.8, 224.0 + i * ROW);
  const totTop = 205.2 + n * ROW; // garis atas baris total
  const bot = totTop + ROW;
  hline(18.2, 501.8, bot - 0.3);
  const tNet = rows.reduce((s, r) => s + Number(r.net || 0), 0), tGross = rows.reduce((s, r) => s + Number(r.gross || 0), 0);
  center("Total", COL[0], COL[2], 627.2 + dy, SZ, bold); center(kg(tNet), COL[2], COL[3], 627.2 + dy, SZ, bold); center(kg(tGross), COL[3], COL[4], 627.2 + dy, SZ, bold);
  [COL[0], COL[2], COL[3], COL[4]].forEach((x) => vline(x, 176.0, bot));
  vline(COL[1], 176.0, totTop);
  T("Note:", 20.7, 642.9 + dy, SZ, bold); T(fit(d.catatan || "-", 440, SZ, bold), 46.3, 642.9 + dy, SZ, bold);

  const im = (img, x0, x1, top, bt) => {
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(img, { x: x0, y: H - bt, width: x1 - x0, height: bt - top });
    page.pushOperators(popGraphicsState());
  };
  im(sig, 209.9, 280.7, 676.0 + dy, 740.5 + dy);
  const cols = [[COL[0], COL[2], "Pengawas", d.pengawas], [COL[2], COL[3], "Direktur Produksi", DIREKTUR], [COL[3], COL[4], "Pembeli / Penerima", d.penerima]];
  for (const [x0, x1, lab, nm] of cols) { center(lab, x0, x1, 747.5 + dy, SZ, bold, SKEW); center(fit(nm ?? "", x1 - x0 - 6, SZ), x0, x1, 760.7 + dy, SZ, reg, SKEW); }
  hline(18.2, 501.8, 755.2 + dy);
  rect(18.2, 501.8, 771.2 + dy, 773.7 + dy, BAR);
  return pdf.save();
}

export async function buatPackingListXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Packing List", { pageSetup: { orientation: "portrait", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 }, views: [{ showGridLines: false }] });
  const thin = { style: "thin", color: { argb: "FF000000" } }, box = { top: thin, bottom: thin, left: thin, right: thin };
  const F = (o = {}) => ({ name: "Cairo", size: 10, ...o });
  ws.columns = [10.8, 15, 29.6, 29.6].map((w) => ({ width: w }));
  ws.getCell("A2").value = "Packing List"; ws.getCell("A2").font = F({ size: 26, bold: true }); ws.getRow(2).height = 40;
  const meta = (r, l, v, o = {}) => { ws.getCell(r, 1).value = l; ws.getCell(r, 1).font = F(); ws.getCell(r, 2).value = ": " + (v ?? ""); ws.getCell(r, 2).font = F(o); };
  meta(4, "No.", d.nomor, { bold: true, italic: true }); meta(5, "Tanggal", tglPl(d.tanggal)); meta(6, "Kepada", d.kepada);
  if (d.telepon) { ws.getCell(6, 4).value = "No. Telepon  : " + d.telepon; ws.getCell(6, 4).font = F(); ws.getCell(6, 4).alignment = { horizontal: "right" }; }
  const hr = 8;
  ["No Item", "Jenis Item", "Net Weight (Kg)", "Gross Weight (Kg)"].forEach((h, i) => {
    const c = ws.getCell(hr, i + 1); c.value = h; c.font = F({ bold: true }); c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
    c.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFD9EAD3" } };
  });
  ws.getRow(hr).height = 30;
  let r = hr + 1;
  d.baris.forEach((b, i) => {
    [pad2(i + 1), b.jenis, Number(b.net), Number(b.gross)].forEach((v, j) => {
      const c = ws.getCell(r, j + 1); c.value = v; c.font = F(); c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
      if (j >= 2) c.numFmt = "0.###";
    });
    ws.getRow(r).height = 19; r++;
  });
  const first = hr + 1, last = r - 1;
  ws.mergeCells(r, 1, r, 2);
  ws.getCell(r, 1).value = "Total"; ws.getCell(r, 1).font = F({ bold: true }); ws.getCell(r, 1).alignment = { horizontal: "center" };
  [["C", 3], ["D", 4]].forEach(([L, ci], k) => {
    const c = ws.getCell(r, ci);
    const tot = d.baris.reduce((s, b) => s + Number(k ? b.gross : b.net), 0);
    c.value = last >= first ? { formula: `SUM(${L}${first}:${L}${last})`, result: Math.round(tot * 1000) / 1000 } : 0;
    c.font = F({ bold: true }); c.numFmt = "0.###"; c.alignment = { horizontal: "center" };
  });
  for (let c = 1; c <= 4; c++) ws.getCell(r, c).border = box;
  r += 1;
  ws.getCell(r, 1).value = "Note: " + (d.catatan || "-"); ws.getCell(r, 1).font = F({ bold: true });
  r += 2;
  const id = wb.addImage({ filename: path.join(DIR, "assets", "sig-misbahudin-pl.png"), extension: "png" });
  ws.addImage(id, { tl: { col: 2.35, row: r - 1 }, ext: { width: 95, height: 88 } });
  r += 5;
  [["Pengawas", d.pengawas], ["Direktur Produksi", DIREKTUR], ["Pembeli / Penerima", d.penerima]].forEach(([l, nm], i) => {
    const col = i === 0 ? 1 : i + 2;
    if (i === 0) ws.mergeCells(r, 1, r, 2);
    const a = ws.getCell(r, col); a.value = l; a.font = F({ bold: true, italic: true }); a.alignment = { horizontal: "center" };
    const b = ws.getCell(r + 1, col); b.value = nm ?? ""; b.font = F({ italic: true }); b.alignment = { horizontal: "center" };
    if (i === 0) ws.mergeCells(r + 1, 1, r + 1, 2);
  });
  for (let c = 1; c <= 4; c++) ws.getCell(r, c).border = { bottom: thin };
  return wb;
}
