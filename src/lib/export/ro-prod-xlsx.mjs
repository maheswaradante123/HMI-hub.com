// Excel "Realisasi Order" (RO) dan "Production Order": susunan kolom dan isi sama dengan PDF/template.
import ExcelJS from "exceljs";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglEn, tglId, PAY_OPTS, PAY_MAP } from "./ro-pdf.mjs";
import { tglSlash } from "./prod-pdf.mjs";

const ASSETS = path.join(path.dirname(fileURLToPath(import.meta.url)), "assets");
const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const PINK = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEAD1DC" } };
const FONT = "Cairo";
const f = (o = {}) => ({ name: FONT, size: 9, ...o });
const BLUE = "FF4285F4";
const w = (pt) => Math.round((pt / 5.6) * 10) / 10; // lebar kolom dari ukuran PDF (pt)

export async function buatRoXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("RO", { pageSetup: { orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 }, views: [{ showGridLines: false }] });
  ws.columns = [25.6, 137.7, 40.2, 43.8, 238, 117.2, 138.3].map((p) => ({ width: w(p) }));
  ws.getCell("A2").value = "REALISASI ORDER"; ws.getCell("A2").font = f({ size: 28, bold: true }); ws.getRow(2).height = 44;
  const lab = (r, l) => { ws.mergeCells(r, 1, r, 2); ws.getCell(r, 1).value = l; ws.getCell(r, 1).font = f({ bold: true }); };
  const meta = (r, l, v, bold) => { lab(r, l); ws.getCell(r, 3).value = ": " + (v ?? ""); ws.getCell(r, 3).font = f({ bold }); };
  meta(4, "Nomor", d.nomor); meta(5, "Tanggal", tglEn(d.tanggal));
  meta(7, "Nama Pemesan", d.pemesan, true); meta(8, "Alamat Pengiriman", d.alamat); meta(9, "No. Telepon", d.telepon);
  ws.getCell("F7").value = "Tanggal Kirim"; ws.getCell("G7").value = ": " + tglId(d.tglKirim);
  ws.getCell("F8").value = "Waktu Pengiriman"; ws.getCell("G8").value = ": " + (d.waktuKirim ?? "");
  for (const a of ["F7", "F8", "G7", "G8"]) ws.getCell(a).font = f({ bold: true });
  const hr = 11;
  ["No", "Nama Produk", "Qty", "Satuan", "Jenis Potongan", "Jenis Pengemasan", "Harga"].forEach((h, i) => {
    const c = ws.getCell(hr, i + 1); c.value = h; c.font = f({ bold: true }); c.fill = PINK; c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
  });
  let r = hr + 1;
  (d.baris.length ? d.baris : []).forEach((b, i) => {
    const vals = [i + 1, b.nama, Number(b.qty), b.unit, b.potong, b.kemas, Number(b.harga)];
    vals.forEach((v, j) => {
      const c = ws.getCell(r, j + 1); c.value = v; c.border = box;
      c.font = f({ bold: j >= 5 });
      c.alignment = { horizontal: j === 6 ? "right" : j === 1 || j === 4 ? "left" : "center", vertical: "middle" };
      if (j === 6) c.numFmt = '"Rp"#,##0';
    });
    r++;
  });
  r += 1;
  const payIdx = PAY_MAP[d.bayar] ?? -1;
  lab(r, "Metode Pembayaran :");
  PAY_OPTS.forEach(([t, it], i) => { const c = ws.getCell(r + i, 3); c.value = (i === payIdx ? "☑ " : "☐ ") + t; c.font = f({ bold: true, italic: it, color: { argb: BLUE } }); });
  r += PAY_OPTS.length + 1;
  const del = d.kirim === "Delivery" ? 0 : d.kirim === "Pick Up di Toko" ? 1 : -1;
  lab(r, "Metode Pengiriman :");
  [["Delivery", true], ["Pick up di Toko", true]].forEach(([t, it], i) => { const c = ws.getCell(r + i, 3); c.value = (i === del ? "☑ " : "☐ ") + t; c.font = f({ bold: true, italic: it, color: { argb: BLUE } }); });
  r += 3;
  lab(r, "Catatan :");
  ws.getCell(r, 3).value = d.catatan || "-"; ws.getCell(r, 3).font = f({ bold: true });
  r += 2;
  ws.getCell(r, 1).value = "Dibuat oleh:"; ws.getCell(r, 1).font = f();
  r += 1;
  if (d.tandaTangan) {
    const id = wb.addImage({ filename: path.join(ASSETS, "sig-syifa-ro.png"), extension: "png" });
    ws.addImage(id, { tl: { col: 0.4, row: r - 0.7 }, ext: { width: 80, height: 48 } });
  }
  r += 3;
  ws.getCell(r, 1).value = d.jabatan ?? "Marketing"; ws.getCell(r, 1).font = f();
  ws.getCell(r + 1, 1).value = d.pembuat ?? ""; ws.getCell(r + 1, 1).font = f();
  ws.getCell(r + 1, 1).border = { top: thin };
  ws.getCell(r + 1, 2).border = { top: thin };
  r += 3;
  for (let c = 1; c <= 7; c++) ws.getCell(r, c).fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF999999" } };
  void fs;
  return wb;
}

export async function buatProdXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Production Order", { pageSetup: { orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 }, views: [{ showGridLines: false }] });
  ws.columns = [81.4, 216.9, 58.2, 32.9, 116, 105.6, 100].map((p) => ({ width: w(p) }));
  const logo = wb.addImage({ filename: path.join(ASSETS, "lamitra-logo-black.png"), extension: "png" });
  ws.addImage(logo, { tl: { col: 5.2, row: 0.3 }, ext: { width: 90, height: 74 } });
  ws.getCell("A2").value = "PRODUCTION ORDER"; ws.getCell("A2").font = f({ size: 28, bold: true }); ws.getRow(2).height = 44;
  const L = (r, l, v, o = {}) => {
    ws.getCell(r, 1).value = l; ws.getCell(r, 1).font = f({ bold: true, italic: !o.up });
    ws.getCell(r, 2).value = ": " + (v ?? ""); ws.getCell(r, 2).font = f({ bold: !!o.vb });
  };
  L(4, "Number", d.nomor); L(5, "Publish Date", tglSlash(d.tanggal)); L(7, "Customer", d.customer, { vb: true }); L(8, "No. Telepon", d.telepon, { up: true });
  const R = (r, l, v, vb) => { ws.getCell(r, 5).value = l; ws.getCell(r, 5).font = f({ bold: true, italic: true }); ws.getCell(r, 6).value = ": " + (v ?? ""); ws.getCell(r, 6).font = f({ bold: vb }); };
  R(4, "Lead Time", d.leadTime, false); R(5, "RO Number", d.roNomor, false); R(7, "Order Date", tglId(d.tglOrder), true); R(8, "Delivery Date", d.tglKirim, true);
  const hr = 10;
  ["No", "Nama Produk", "Qty", "Satuan", "Jenis Potongan", "Jenis Pengemasan"].forEach((h, i) => {
    const c = ws.getCell(hr, i + 1); c.value = h; c.font = f({ bold: true }); c.fill = PINK; c.border = box; c.alignment = { horizontal: "center" };
  });
  let r = hr + 1;
  d.baris.forEach((b, i) => {
    [i + 1, b.nama, Number(b.qty), b.unit, b.potong, b.kemas].forEach((v, j) => {
      const c = ws.getCell(r, j + 1); c.value = v; c.border = box; c.font = f();
      c.alignment = { horizontal: j === 1 || j === 4 || j === 5 ? "left" : "center", vertical: "middle" };
    });
    r++;
  });
  r += 2;
  const rows = [["Metode Pengiriman", d.metode, true, true], ["Jadwal Pengiriman", d.jadwal, false, true], ["Alamat Pengiriman", d.alamat, false, false], ["PIC Pengiriman", d.pic, false, true], ["Kode Sapi", d.kodeSapi || "-", true, true]];
  rows.forEach(([l, v, lb, vb], i) => {
    const row = r + i;
    ws.getCell(row, 1).value = l; ws.getCell(row, 1).font = f({ bold: lb }); ws.getCell(row, 1).border = box;
    ws.mergeCells(row, 2, row, 3);
    const c = ws.getCell(row, 2); c.value = v ?? ""; c.font = f({ bold: vb }); c.alignment = { wrapText: true, vertical: "middle" };
    ws.getCell(row, 2).border = box; ws.getCell(row, 3).border = box;
    if (l === "Alamat Pengiriman") ws.getRow(row).height = 26;
  });
  ws.getCell(r, 4).value = "Note :"; ws.getCell(r, 4).font = f({ bold: true });
  ws.getCell(r, 5).value = d.catatan || "-"; ws.getCell(r, 5).font = f({ size: 8 });
  const foot = r + rows.length + 2;
  ws.getCell(foot, 1).value = "*Dokumen ini diterbitkan menggunakan media digital, tidak memerlukan tanda tangan sebagai tanda persetujuan";
  ws.getCell(foot, 1).font = f({ size: 8 });
  return wb;
}
