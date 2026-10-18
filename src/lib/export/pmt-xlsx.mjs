// Excel "Pemasukan Toko": kolom sama dengan PDF; Total dan Total Pendapatan memakai rumus supaya bisa diubah di Excel.
import ExcelJS from "exceljs";
import { tglPendek, tglPanjang } from "./pmt-pdf.mjs";

const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const RP = '"Rp" #,##0;-"Rp" #,##0';
const COLS = ["cash", "qris", "debit", "grab", "tf", "deposited"];

export async function buatPemasukanTokoXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Pemasukan Toko", { pageSetup: { orientation: "landscape", paperSize: 1, fitToPage: true, fitToWidth: 1, fitToHeight: 0 } });
  ws.columns = [{ width: 5 }, { width: 14 }, { width: 38 }, ...COLS.map(() => { return { width: 16 }; }), { width: 22 }];
  ws.getCell("A1").value = "PEMASUKAN TOKO"; ws.getCell("A1").font = { bold: true, size: 14 };
  ws.getCell("A3").value = "NO :"; ws.getCell("C3").value = d.nomor ?? "";
  ws.getCell("A4").value = "From"; ws.getCell("C4").value = tglPanjang(d.dari);
  ws.getCell("A5").value = "To"; ws.getCell("C5").value = tglPanjang(d.sampai);
  const H = ["NO", "TANGGAL", "DESCRIPTION", "CASH", "QRIS", "DEBIT", "GRAB", "TF REK HMI", "DISETOR", "Attachment Of Proof"];
  const hr = 7;
  H.forEach((h, i) => { const c = ws.getCell(hr, i + 1); c.value = h; c.font = { bold: true }; c.alignment = { horizontal: i === 1 ? "left" : "center" }; c.border = box; });
  let r = hr + 1; const first = r;
  for (const b of d.baris) {
    ws.getCell(r, 2).value = b.tanggal ? tglPendek(b.tanggal) : "";
    ws.getCell(r, 3).value = b.desc ?? "";
    COLS.forEach((k, i) => { const v = Number(b[k] ?? 0); if (v) { const c = ws.getCell(r, 4 + i); c.value = v; c.numFmt = RP; } });
    for (let i = 1; i <= 10; i++) ws.getCell(r, i).border = box;
    r++;
  }
  const last = r - 1; const tot = r;
  ws.getCell(tot, 3).value = "Total";
  COLS.forEach((k, i) => { const L = String.fromCharCode(68 + i); const c = ws.getCell(tot, 4 + i); c.value = { formula: last >= first ? `SUM(${L}${first}:${L}${last})` : "0", result: d.total[k] }; c.numFmt = RP; });
  const must = tot + 1;
  ws.getCell(must, 3).value = "Uang cash yang harus disetor";
  Object.assign(ws.getCell(must, 4), { value: { formula: `D${tot}-I${tot}`, result: d.total.mustDeposit }, numFmt: RP });
  const piut = d.piutang ?? []; let p = must + 1; const pf = p;
  for (const x of piut) { ws.getCell(p, 3).value = `Piutang ${x.nama}`; Object.assign(ws.getCell(p, 4), { value: Number(x.jumlah), numFmt: RP }); p++; }
  const pl = p - 1; const inc = p;
  ws.getCell(inc, 3).value = "Total Pendapatan";
  Object.assign(ws.getCell(inc, 9), { value: { formula: `D${must}+SUM(D${tot}:H${tot})${piut.length ? `+SUM(D${pf}:D${pl})` : ""}`, result: d.total.income }, numFmt: RP });
  for (let i = tot; i <= inc; i++) {
    ws.getRow(i).font = { bold: true };
    ws.getCell(i, 3).alignment = { horizontal: "right" };
    for (let c = 1; c <= 10; c++) ws.getCell(i, c).border = box;
  }
  return wb;
}
