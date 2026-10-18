// Excel "Cash Payment Journal": kolom sama dengan PDF. Amount dan ringkasan memakai rumus penjumlahan (SUMIFS per jenis baris).
// Kolom N (jenis baris) dan O (rencana yang belum direalisasi) disembunyikan sebagai bantuan rumus.
import ExcelJS from "exceljs";
import { tglPendekCpj, tglPanjangCpj } from "./jcp-pdf.mjs";

const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const RP = '"Rp" #,##0;-"Rp" #,##0';
const GREY = "FFB8B8B8", BLUE = "FF9EC5E8";
const FILL = { NON_CPJ: "FFFFFF00", OVER: "FFFF9900", REJECTED: "FFFF0000", INCOMING: "FF00FFFF" };
const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });
const hasV = (v) => v !== null && v !== undefined && v !== "";

export async function buatCpjXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("CPJ", { pageSetup: { orientation: "portrait", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 } });
  ws.columns = [{ width: 7 }, { width: 5 }, { width: 14 }, { width: 8 }, { width: 44 }, { width: 14 }, { width: 8 }, { width: 8 }, { width: 16 }, { width: 14 }, { width: 8 }, { width: 16 }, { width: 28 }, { width: 10, hidden: true }, { width: 14, hidden: true }];
  ws.getCell("A1").value = "PT. HARMONI MITRA INOVINDO"; ws.getCell("A1").font = { color: { argb: "FFFFFFFF" }, size: 8 };
  for (let c = 1; c <= 13; c++) ws.getCell(1, c).fill = fill("FF000000");
  ws.getCell("A3").value = "CASH PAYMENT JOURNAL"; ws.getCell("A3").font = { bold: true, size: 16 };
  ws.getCell("A5").value = "No :"; ws.getCell("C5").value = d.nomor; ws.getCell("C5").font = { bold: true };
  ws.getCell("A6").value = "Date :"; ws.getCell("C6").value = tglPanjangCpj(d.tanggal); ws.getCell("C6").font = { bold: true };

  const h1 = 8, h2 = 9;
  const left = ["A/C.", "No.", "Tanggal Transaksi", "", "Description", "Price", "Qty", "Unit", "Amount"];
  left.forEach((t, i) => { ws.mergeCells(h1, i + 1, h2, i + 1); const c = ws.getCell(h1, i + 1); c.value = t; });
  ws.mergeCells(h1, 10, h1, 13); ws.getCell(h1, 10).value = "Realization";
  ["Price", "Qty", "Amount", "Attachment Of Proof"].forEach((t, i) => { ws.getCell(h2, 10 + i).value = t; });
  for (let r = h1; r <= h2; r++) for (let c = 1; c <= 13; c++) { const x = ws.getCell(r, c); x.font = { bold: true }; x.alignment = { horizontal: "center", vertical: "middle" }; x.border = box; x.fill = fill(c <= 9 ? GREY : BLUE); }

  let r = h2 + 1; const first = r;
  const done = d.status === "REALIZED";
  for (const [i, b] of d.baris.entries()) {
    const plan = d.hitung.planAmount(b), ra = d.hitung.realAmount(b, done);
    const set = (c, v, extra = {}) => Object.assign(ws.getCell(r, c), { value: v, ...extra });
    set(1, b.ac ?? "", { font: { bold: true, italic: true }, alignment: { horizontal: "center" } });
    set(2, i + 1, { alignment: { horizontal: "center" } });
    set(3, b.tanggal ? tglPendekCpj(b.tanggal) : "", { font: { bold: true }, alignment: { horizontal: "right" } });
    set(4, b.kode ?? "", { font: { bold: true } });
    set(5, b.desc ?? "");
    set(6, Number(b.price), { numFmt: RP });
    set(7, Number(b.qty), { alignment: { horizontal: "center" } });
    set(8, b.unit ?? "", { alignment: { horizontal: "center" } });
    set(9, { formula: `F${r}*G${r}`, result: plan }, { numFmt: RP });
    if (hasV(b.realPrice)) set(10, Number(b.realPrice), { numFmt: RP });
    if (hasV(b.realQty)) set(11, Number(b.realQty), { alignment: { horizontal: "center" } });
    if (ra !== null) set(12, ra, { numFmt: RP });
    set(13, b.bukti ?? "");
    set(14, b.flag);
    set(15, { formula: `IF(L${r}="",I${r},0)`, result: ra === null ? plan : 0 });
    if (FILL[b.flag]) for (let c = 1; c <= 9; c++) ws.getCell(r, c).fill = fill(FILL[b.flag]);
    for (let c = 1; c <= 13; c++) ws.getCell(r, c).border = box;
    r++;
  }
  const last = Math.max(r - 1, first);
  const rng = (col) => `${col}${first}:${col}${last}`;
  const S = (col, flag) => `SUMIFS(${rng(col)},${rng("N")},"${flag}")`;
  const t = d.total;
  const sum = r;
  const L = [["Total Permintaan", `SUMIFS(${rng("I")},${rng("N")},"<>INCOMING")`, t.requested], ["Total Yang Disetujui", `${S("I", "NONE")}+${S("I", "NON_CPJ")}+${S("I", "OVER")}`, t.approved],
    ["Uang Saat ini", S("I", "INCOMING"), t.cashIn], ["Yang harus dibayarkan", `${S("I", "NONE")}+${S("I", "OVER")}`, t.mustPay]];
  const Rr = [["Yang perlu dibelanjakan", `${S("O", "NONE")}+${S("O", "OVER")}`, t.toSpend], ["Realisasi Uang Keluar", `${S("L", "NONE")}+${S("L", "OVER")}`, t.spent], ["Sisa Uang", `I${sum + 2}-L${sum + 1}`, t.remaining]];
  L.forEach(([lab, f, v], k) => {
    ws.mergeCells(sum + k, 1, sum + k, 8);
    const a = ws.getCell(sum + k, 1); a.value = lab; a.font = { bold: true, italic: true }; a.alignment = { horizontal: "right" };
    for (let c = 1; c <= 8; c++) { ws.getCell(sum + k, c).fill = fill(GREY); ws.getCell(sum + k, c).border = box; }
    Object.assign(ws.getCell(sum + k, 9), { value: { formula: f, result: v }, numFmt: RP, font: { bold: true }, border: box });
  });
  Rr.forEach(([lab, f, v], k) => {
    ws.mergeCells(sum + k, 10, sum + k, 11);
    const a = ws.getCell(sum + k, 10); a.value = lab; a.font = { bold: true, italic: true }; a.alignment = { horizontal: "right" };
    for (let c = 10; c <= 11; c++) { ws.getCell(sum + k, c).fill = fill(BLUE); ws.getCell(sum + k, c).border = box; }
    Object.assign(ws.getCell(sum + k, 12), { value: { formula: f.startsWith("I") ? `I${sum + 2}-L${sum + 1}` : f, result: v }, numFmt: RP, font: { bold: true }, border: box });
  });

  let y = sum + 5;
  ws.getCell(y, 1).value = "Payment"; ws.getCell(y, 3).value = ":"; ws.getCell(y, 5).value = d.payNote ?? "";
  [["Terbayarkan oleh non rekening CPJ", "NON_CPJ"], ["Over Budget CPJ Sebelumnya", "OVER"], ["Permintaan ditolak", "REJECTED"], ["Uang Masuk", "INCOMING"]].forEach(([txt, f], k) => {
    ws.getCell(y + 1 + k, 1).fill = fill(FILL[f]); ws.getCell(y + 1 + k, 3).value = ":"; ws.getCell(y + 1 + k, 5).value = txt;
  });
  ws.getCell(y + 5, 1).value = "Note"; ws.getCell(y + 5, 3).value = ":"; ws.getCell(y + 5, 5).value = d.note ?? "";
  for (let rr = y; rr <= y + 5; rr++) for (const c of [1, 3, 5]) ws.getCell(rr, c).font = { bold: true };
  y += 7;
  ws.getCell(y, 1).value = "Initiator"; ws.getCell(y, 5).value = "Approval";
  ws.getCell(y + 2, 1).value = d.initiatorNama ?? ""; ws.getCell(y + 2, 5).value = d.approverNama ?? "";
  ws.getCell(y + 3, 1).value = d.initiatorJabatan ?? ""; ws.getCell(y + 3, 5).value = d.approverJabatan ?? "";
  ws.getCell(y + 3, 1).font = { bold: true }; ws.getCell(y + 3, 5).font = { bold: true };
  ws.getRow(y + 1).height = 40;
  return wb;
}
