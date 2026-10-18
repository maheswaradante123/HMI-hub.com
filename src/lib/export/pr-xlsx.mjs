// Excel "Purchase Request": kolom sama dengan PDF. Amount = Price x Qty (rumus) dan Total = penjumlahan Amount (rumus).
// Barang yang dibatalkan atau ditolak tidak ikut dijumlahkan (kolom Status dipakai SUMIFS).
import ExcelJS from "exceljs";
import { tglPendekCpj, tglPanjangCpj } from "./jcp-pdf.mjs";
import { PR_PILL, prJumlah, prTotal } from "./pr-pdf.mjs";

const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const RP = '"Rp" #,##0;-"Rp" #,##0';
const GREY = "FFB7B7B7";
const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });

/** d: {nomor, tanggal, baris:[{ac, kode, tanggal, desc, price, qty, unit, status, pembelian, bukti}]} */
export async function buatPrXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("PR", { pageSetup: { orientation: "landscape", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 } });
  ws.columns = [{ width: 8 }, { width: 6 }, { width: 14 }, { width: 8 }, { width: 46 }, { width: 14 }, { width: 8 }, { width: 8 }, { width: 16 }, { width: 12 }, { width: 14 }, { width: 28 }];
  ws.getCell("A2").value = "No"; ws.getCell("B2").value = ":"; ws.getCell("C2").value = d.nomor; ws.getCell("C2").font = { bold: true };
  ws.getCell("A3").value = "Date"; ws.getCell("B3").value = ":"; ws.getCell("C3").value = tglPanjangCpj(d.tanggal);
  const h = 5;
  ["A/C.", "No.", "Tanggal", "", "Description", "Price", "Qty", "Unit", "Amount", "Status", "Pembelian", "Attachment of Proof"].forEach((t, i) => {
    const c = ws.getCell(h, i + 1); c.value = t; c.font = { bold: true }; c.fill = fill(GREY); c.border = box;
    c.alignment = { horizontal: i === 10 || i === 11 ? "left" : "center", vertical: "bottom", wrapText: i === 11 };
  });
  ws.mergeCells(h, 3, h, 4);
  let r = h + 1; const first = r;
  for (const [i, b] of d.baris.entries()) {
    const set = (c, v, extra = {}) => Object.assign(ws.getCell(r, c), { value: v, ...extra });
    const pc = PR_PILL[b.status] ?? PR_PILL.DRAFT;
    set(1, b.ac ?? "", { font: { bold: true, italic: true }, alignment: { horizontal: "center" } });
    set(2, b.no ?? i + 1, { font: { bold: true }, alignment: { horizontal: "center" } });
    set(3, b.tanggal ? tglPendekCpj(b.tanggal) : "", { font: { bold: true }, alignment: { horizontal: "right" } });
    set(4, b.kode ?? "", { font: { bold: true } });
    set(5, b.desc ?? "");
    set(6, Number(b.price), { numFmt: RP });
    set(7, Number(b.qty), { alignment: { horizontal: "center" } });
    set(8, b.unit ?? "", { alignment: { horizontal: "center" } });
    set(9, { formula: `F${r}*G${r}`, result: prJumlah(b) }, { numFmt: RP });
    set(10, pc.label, { font: { color: { argb: "FF" + pc.fg } }, fill: fill("FF" + pc.bg), alignment: { horizontal: "center" } });
    set(11, b.pembelian ?? "");
    set(12, b.bukti ?? "");
    set(13, b.status);
    for (let c = 1; c <= 12; c++) ws.getCell(r, c).border = box;
    r++;
  }
  const last = Math.max(r - 1, first);
  ws.getColumn(13).hidden = true; // jenis status untuk rumus Total
  const tot = r;
  ws.getCell(tot, 8).value = "Total"; ws.getCell(tot, 8).font = { bold: true }; ws.getCell(tot, 8).alignment = { horizontal: "center" };
  ws.getCell(tot, 9).value = { formula: `SUM(I${first}:I${last})-SUMIFS(I${first}:I${last},M${first}:M${last},"CANCELLED")-SUMIFS(I${first}:I${last},M${first}:M${last},"REJECTED")`, result: prTotal(d.baris) };
  ws.getCell(tot, 9).numFmt = RP; ws.getCell(tot, 9).font = { bold: true };
  ws.getCell(tot, 8).border = box; ws.getCell(tot, 9).border = box;
  ws.views = [{ state: "frozen", ySplit: h }];
  return wb;
}
