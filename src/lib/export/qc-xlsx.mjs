// Pembuat file Excel QC Report (meniru contoh QC-002-IX-26, Adhimitra Farm).
import ExcelJS from "exceljs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { tglID } from "./invoice-xlsx.mjs";

const ASSETS = path.join(path.dirname(fileURLToPath(import.meta.url)), "assets");
const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };
const hari = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 864e5);
const F = (o = {}) => ({ name: "Cairo", size: 12.5, ...o });
const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });
const WARNA = ["FFCFE2F3", "FFD9EAD3"]; // biru, hijau (bergantian per sapi)

/** Hitung blok penimbangan: perkembangan (kg) & ADG (kg/hari) terhadap penimbangan sebelumnya. */
export function hitungJurnal(sapi) {
  let prevBobot = sapi.bobotAwal, prevTgl = sapi.tglAwal;
  return sapi.timbang.map((t) => {
    const gain = t.bobot - prevBobot, d = hari(prevTgl, t.tgl);
    const row = { tgl: t.tgl, bobot: t.bobot, gain, adg: d > 0 ? Math.round((gain / d) * 100) / 100 : 0 };
    prevBobot = t.bobot; prevTgl = t.tgl; return row;
  });
}

/**
 * data: { nomor, publish(iso), kepada, catatan, sapi:[{nomor, bobotAwal, tglAwal(iso), timbang:[{tgl, bobot}]}],
 *         ppic, qc, direktur }
 */
export async function buatQcXlsx(data) {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("QC Report", {
    pageSetup: { paperSize: 1, orientation: "portrait", fitToPage: false, scale: 85, horizontalCentered: true, margins: { left: 0.5, right: 0.5, top: 0.78, bottom: 0.4, header: 0, footer: 0 } },
    views: [{ showGridLines: false }],
  });
  const px = [56, 93, 93, 112, 112, 113]; // diukur dari PDF contoh (letter, skala 85%)
  ws.columns = px.map((w) => ({ width: Math.round((w * 0.94 / 0.85 / 7) * 10) / 10 }));
  let r = 1;
  ws.getRow(r).height = 68; ws.mergeCells(r, 1, r, 6);
  const t = ws.getCell(r, 1); t.value = "Quality Control Report"; t.font = { name: "Cairo", size: 32, bold: true }; t.alignment = { vertical: "bottom" };
  ws.addImage(wb.addImage({ filename: path.join(ASSETS, "adhimitra-logo.png"), extension: "png" }), { tl: { col: 5.35, row: 0.0 }, ext: { width: 122, height: 111 } });
  r++; ws.getRow(r).height = 22; r++;
  const meta = (lbl, val, right) => {
    ws.getRow(r).height = 15.9;
    ws.mergeCells(r, 1, r, 3);
    ws.getCell(r, 1).value = { richText: [{ text: lbl + "  ", font: F({ bold: true, size: 11.5 }) }, { text: ": " + val, font: F({ size: 11.5 }) }] };
    if (right) { ws.mergeCells(r, 5, r, 6); ws.getCell(r, 5).value = right; ws.getCell(r, 5).font = F({ size: 11.5 }); }
    r++;
  };
  meta("No.", data.nomor, "sekretariat@adhimitrafarm.com");
  meta("Publish", tglID(data.publish).replace(/ (\p{L}+) /u, (m, b) => " " + b.slice(0, 3) + " ").replace(/^(\d+) (\p{L}{3}) /u, "$1-$2-").replace(/-(\p{L}{3})-/u, (m, b) => "-" + b + "-"), "085-123-123-918");
  meta("Kepada", data.kepada);
  ws.getRow(r).height = 14.7; r++;

  ["No.", "Nomor Sapi", "Bobot Awal"].forEach((h, i) => {
    const c = ws.getCell(r, i + 1); c.value = h; c.font = F({ bold: true }); c.fill = fill("FFD9D2E9"); c.border = box; c.alignment = { horizontal: "center", vertical: "middle" };
  });
  ws.mergeCells(r, 4, r, 6);
  for (let k = 4; k <= 6; k++) { ws.getCell(r, k).fill = fill("FFD9D2E9"); ws.getCell(r, k).border = box; }
  const jh = ws.getCell(r, 4); jh.value = "Jurnal Penimbangan"; jh.font = F({ bold: true }); jh.alignment = { horizontal: "center", vertical: "middle" };
  ws.getRow(r).height = 31.8; r++;

  data.sapi.forEach((s, i) => {
    const jur = hitungJurnal(s), tint = fill(WARNA[i % 2]);
    const start = r, end = r + jur.length * 3 - 1;
    jur.forEach((j) => {
      ws.getRow(r).height = 15.75; ws.getRow(r + 1).height = 15.75; ws.getRow(r + 2).height = 15.75;
      ws.mergeCells(r, 4, r, 6);
      for (let k = 4; k <= 6; k++) { ws.getCell(r, k).fill = tint; ws.getCell(r, k).border = box; }
      const h = ws.getCell(r, 4); h.value = "Penimbangan " + tglID(j.tgl); h.font = F({ bold: true }); h.alignment = { horizontal: "center", vertical: "middle" };
      r++;
      ["Bobot", "Perkembangan", "ADG"].forEach((x, k) => { const c = ws.getCell(r, 4 + k); c.value = x; c.font = F({ bold: true }); c.fill = tint; c.border = box; c.alignment = { horizontal: "center" }; });
      r++;
      [`${j.bobot}Kg`, `${j.gain}Kg`, j.adg.toFixed(2)].forEach((x, k) => { const c = ws.getCell(r, 4 + k); c.value = x; c.font = F(); c.border = box; c.alignment = { horizontal: "center" }; });
      r++;
    });
    [[1, i + 1], [2, s.nomor], [3, `${s.bobotAwal}Kg`]].forEach(([col, v]) => {
      ws.mergeCells(start, col, end, col);
      const c = ws.getCell(start, col); c.value = v; c.font = F({ size: 14 }); c.alignment = { horizontal: "center", vertical: "middle" };
      for (let q = start; q <= end; q++) ws.getCell(q, col).border = box;
    });
  });
  ws.getRow(r).height = 16.5; r++;
  ws.getRow(r).height = 16; ws.mergeCells(r, 1, r, 6);
  ws.getCell(r, 1).value = { richText: [{ text: "Catatan : ", font: F({ bold: true, size: 14 }) }, { text: " " + (data.catatan || "Sapi dalam keadaan sehat."), font: F({ size: 12.5 }) }] };
  r++; ws.getRow(r).height = 15.8; r++;
  ws.getRow(r).height = 16;
  ws.mergeCells(r, 1, r, 3); ws.getCell(r, 1).value = "Laporan ini disusun oleh"; ws.getCell(r, 1).font = F({ size: 11.5 });
  ws.mergeCells(r, 4, r, 6); ws.getCell(r, 4).value = "Mengetahui"; ws.getCell(r, 4).font = F({ size: 11.5 }); ws.getCell(r, 4).alignment = { horizontal: "center" };
  r++;
  ws.getRow(r).height = 14.6; r++;
  const sigTop = r; ws.getRow(r).height = 95; r++;
  const add = (f, col, w, h, dx = 0) => ws.addImage(wb.addImage({ filename: path.join(ASSETS, f), extension: "png" }), { tl: { col: col + dx, row: sigTop - 1 + 0.05 }, ext: { width: w, height: h } });
  add("qc-sig-ppic.png", 0.3, 165, 97); add("qc-sig-qc.png", 2.83, 150, 88); add("qc-sig-dir-stempel.png", 4.8, 120, 120);
  ws.getRow(r).height = 15.75;
  // ketiga kolom tanda tangan: A:C, D:E, F -> disesuaikan dengan contoh (3 blok rata)
  const blocks = [[1, 2], [3, 4], [5, 6]];
  blocks.forEach(([a, b], k) => {
    ws.mergeCells(r, a, r, b); const c = ws.getCell(r, a); c.value = ["PPIC", "Quality Control", "Dir. Operasional"][k]; c.font = F({ size: 11.5 }); c.alignment = { horizontal: "center" };
  });
  r++; ws.getRow(r).height = 15.75;
  blocks.forEach(([a, b], k) => {
    ws.mergeCells(r, a, r, b); const c = ws.getCell(r, a); c.value = [data.ppic, data.qc, data.direktur][k]; c.font = F({ size: 11.5 }); c.alignment = { horizontal: "center" };
    ws.getCell(r, a).border = { top: thin }; ws.getCell(r, b).border = { top: thin };
  });
  r++; ws.getRow(r).height = 5;
  for (let k = 1; k <= 6; k++) ws.getCell(r, k).fill = fill("FF999999");
  ws.eachRow((row) => row.eachCell((c) => { c.alignment = { ...(c.alignment || {}), vertical: (c.alignment && c.alignment.vertical) || "middle" }; }));
  return wb;
}
export async function simpanQc(data, file) { await (await buatQcXlsx(data)).xlsx.writeFile(file); }
