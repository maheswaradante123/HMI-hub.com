// Excel "Analisa Pembelian": susunan sama dengan PDF. Total, Total Penjualan, SubTotal, Total biaya, Keuntungan,
// Daging, Persentase, Harga Karkas dan rasio Lower/Upper Side memakai rumus supaya bisa diubah di Excel.
import ExcelJS from "exceljs";
import { tglPendekCpj } from "./jcp-pdf.mjs";

const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const RP = '"Rp" #,##0;-"Rp" #,##0';
const GREEN = "FFD9EAD3", YELLOW = "FFFFF2CC";
const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });

/** d: sama dengan buatApPdf, ditambah baris[].meat (true bila kategori Daging) dan manualTotal (angka atau null). */
export async function buatApXlsx(d) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Analisa", { pageSetup: { orientation: "portrait", paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 } });
  ws.columns = [{ width: 9 }, { width: 30 }, { width: 15 }, { width: 12 }, { width: 20 }, { width: 22 }, { width: 6 }];
  const set = (ref, value, extra = {}) => Object.assign(ws.getCell(ref), { value, ...extra });

  ws.mergeCells("A2:F2");
  set("A2", "ANALISA PEMBELIAN", { font: { size: 18, color: { argb: "FFFFFFFF" } }, fill: fill("FF000000"), alignment: { vertical: "middle" } });
  ws.getRow(2).height = 30;
  [["Nomor", d.nomor, "Supplier", d.supplier], ["Tanggal", tglPendekCpj(d.tanggal), "TOP (Jatuh Tempo)", d.top ? tglPendekCpj(d.top) : ""], ["Jenis Sapi", d.jenis, "Nomor Invoice", d.invoice ?? ""]].forEach(([l1, v1, l2, v2], i) => {
    const r = 4 + i;
    set(`A${r}`, l1); set(`B${r}`, `: ${v1}`);
    ws.mergeCells(`C${r}:D${r}`); set(`C${r}`, l2); set(`E${r}`, `: ${v2}`);
  });
  set("E3", "Harga :", { alignment: { horizontal: "right" } });
  set("F3", Number(d.harga), { numFmt: RP, fill: fill(GREEN) });

  const h = 8;
  ["Nomor", "Jenis Item", "Quantity", "Satuan", "Harga Jual/Satuan", "Total"].forEach((t, i) => {
    const c = ws.getCell(h, i + 1); c.value = t; c.font = { bold: true }; c.fill = fill(GREEN); c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
  });
  const rows = [...d.baris.map((r) => ({ ...r, qty: Number(r.qty) })), ...d.nonk.map((r) => ({ ...r, qty: r.qty == null ? null : Number(r.qty), meat: false }))];
  let r = h + 1; const first = r;
  rows.forEach((x, i) => {
    set(`A${r}`, i + 1, { alignment: { horizontal: "center" } });
    set(`B${r}`, x.nama ?? "");
    set(`C${r}`, x.qty ? x.qty : null, { numFmt: "0.000", fill: fill(YELLOW), alignment: { horizontal: "center" } });
    set(`D${r}`, "Kg", { alignment: { horizontal: "center" } });
    set(`E${r}`, Number(x.price), { numFmt: RP });
    set(`F${r}`, { formula: `C${r}*E${r}`, result: (x.qty ?? 0) * Number(x.price) }, { numFmt: RP });
    set(`G${r}`, x.meat ? "Y" : "");
    for (let c = 1; c <= 6; c++) ws.getCell(r, c).border = box;
    r++;
  });
  const last = Math.max(r - 1, first);
  ws.getColumn(7).hidden = true; // penanda item Daging untuk rumus
  ws.mergeCells(`A${r}:E${r}`);
  set(`A${r}`, "Total Penjualan", { font: { bold: true, size: 11 }, alignment: { horizontal: "right" } });
  set(`F${r}`, { formula: `SUM(F${first}:F${last})`, result: d.total.all }, { numFmt: RP, font: { bold: true } });
  for (let c = 1; c <= 6; c++) Object.assign(ws.getCell(r, c), { fill: fill(GREEN), border: box });
  const tot = r;

  r += 2;
  ws.mergeCells(`A${r}:D${r}`);
  set(`A${r}`, "BIAYA OPERASIONAL", { font: { bold: true }, alignment: { horizontal: "center" } });
  for (let c = 1; c <= 4; c++) Object.assign(ws.getCell(r, c), { fill: fill(GREEN), border: box });
  r++;
  ["Nomor", "Jenis Item", "Satuan", "Total"].forEach((t, i) => {
    const c = ws.getCell(r, i + 1); c.value = t; c.font = { bold: true }; c.fill = fill(GREEN); c.border = box; c.alignment = { horizontal: "center" };
  });
  r++; const cf = r;
  d.biaya.forEach((c, i) => {
    set(`A${r}`, i + 1, { alignment: { horizontal: "right" } });
    set(`B${r}`, c.nama ?? "");
    set(`C${r}`, "Lamsam");
    set(`D${r}`, Number(c.amount) ? Number(c.amount) : null, { numFmt: RP });
    for (let k = 1; k <= 4; k++) ws.getCell(r, k).border = box;
    r++;
  });
  const cl = Math.max(r - 1, cf);
  ws.mergeCells(`A${r}:C${r}`);
  set(`A${r}`, "SubTotal", { font: { bold: true, size: 11 }, alignment: { horizontal: "right" } });
  set(`D${r}`, { formula: `SUM(D${cf}:D${cl})`, result: d.total.ops }, { numFmt: RP, font: { bold: true } });
  const sub = r; r++;
  ws.mergeCells(`A${r}:C${r}`);
  set(`A${r}`, "Total", { font: { bold: true, size: 11 }, alignment: { horizontal: "right" } });
  set(`D${r}`, d.manualTotal != null ? Number(d.manualTotal) : { formula: `F3+D${sub}`, result: d.total.totalCost }, { numFmt: RP, font: { bold: true } });
  const gt = r;
  for (const rr of [sub, gt]) {
    for (let c = 1; c <= 3; c++) Object.assign(ws.getCell(rr, c), { fill: fill(GREEN), border: box });
    Object.assign(ws.getCell(rr, 4), { fill: fill(YELLOW), border: box });
  }

  r += 2;
  ws.mergeCells(`A${r}:B${r}`);
  set(`A${r}`, "Keuntungan :");
  set(`C${r}`, { formula: `F${tot}-D${gt}`, result: d.total.profit }, { numFmt: RP });
  for (let c = 1; c <= 3; c++) ws.getCell(r, c).fill = fill(GREEN);
  r += 2;
  const meat = r;
  set(`B${r}`, "Daging"); set(`C${r}`, { formula: `SUMIFS(C${first}:C${last},G${first}:G${last},"Y")`, result: d.total.meat }, { numFmt: "0.000" });
  r++; const car = r;
  set(`B${r}`, "Karkas"); set(`C${r}`, Number(d.karkas), { numFmt: "#,##0.###" });
  r++;
  set(`B${r}`, "Persentase"); set(`C${r}`, { formula: `IF(C${car}=0,"",C${meat}/C${car})`, result: d.total.meatPct == null ? "" : d.total.meatPct / 100 }, { numFmt: "0.00%" });
  r++;
  set(`B${r}`, "Harga Karkas"); set(`C${r}`, { formula: `IF(C${car}=0,"",F3/C${car})`, result: d.total.hargaKarkas ?? "" }, { numFmt: '"Rp"#,##0' });
  r += 2;
  [["Lower Side", d.lower, d.total.lowerRatio], ["UpperSide", d.upper, d.total.upperRatio]].forEach(([l, v, ratio]) => {
    if (v == null) return;
    set(`A${r}`, l); set(`B${r}`, Number(v), { numFmt: "0.000", alignment: { horizontal: "right" } });
    set(`C${r}`, { formula: `IF(C${meat}=0,"",B${r}/C${meat})`, result: ratio ?? "" }, { numFmt: "0.0000000000" });
    r++;
  });
  return wb;
}
