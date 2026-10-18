// Pembuat file Excel Invoice / Proforma-Invoice yang meniru contoh Owner (INV-002-X-26, INV-003-X-26, PRO-INV-001-X-26).
// Dua varian: "toko" (A5 lanskap, hijau, logo La Mitra) dan "qurban" (A4 potret, oranye, logo HMI).
import ExcelJS from "exceljs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ASSETS = path.join(path.dirname(fileURLToPath(import.meta.url)), "assets");
const GREY = "FFCCCCCC", BLUE = "FF3D85C6";
const thin = { style: "thin", color: { argb: "FF000000" } };
const box = { top: thin, bottom: thin, left: thin, right: thin };

const fmtNum = (n) => Number(n).toLocaleString("en-US", { maximumFractionDigits: 3 });
const BULAN_EN = ["January","February","March","April","May","June","July","August","September","October","November","December"];
const BULAN_ID = ["Januari","Februari","Maret","April","Mei","Juni","Juli","Agustus","September","Oktober","November","Desember"];
const pad2 = (n) => String(n).padStart(2, "0");
// "5 October 2026" (qurban) / "09 October 2026" (toko)
export const tglEN = (iso, padDay = false) => { const [y, m, d] = iso.split("-").map(Number); return `${padDay ? pad2(d) : d} ${BULAN_EN[m - 1]} ${y}`; };
export const tglID = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${BULAN_ID[m - 1]} ${y}`; };
export const tglDash = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d}-${BULAN_EN[m - 1].slice(0, 3)}-${y}`; };

const SATUAN = ["", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan", "sepuluh", "sebelas"];
export function terbilang(n) {
  n = Math.floor(n);
  if (n < 12) return SATUAN[n];
  if (n < 20) return terbilang(n - 10) + " belas";
  if (n < 100) return terbilang(Math.floor(n / 10)) + " puluh" + (n % 10 ? " " + terbilang(n % 10) : "");
  if (n < 200) return "seratus" + (n - 100 ? " " + terbilang(n - 100) : "");
  if (n < 1000) return terbilang(Math.floor(n / 100)) + " ratus" + (n % 100 ? " " + terbilang(n % 100) : "");
  if (n < 2000) return "seribu" + (n - 1000 ? " " + terbilang(n - 1000) : "");
  if (n < 1e6) return terbilang(Math.floor(n / 1e3)) + " ribu" + (n % 1e3 ? " " + terbilang(n % 1e3) : "");
  if (n < 1e9) return terbilang(Math.floor(n / 1e6)) + " juta" + (n % 1e6 ? " " + terbilang(n % 1e6) : "");
  if (n < 1e12) return terbilang(Math.floor(n / 1e9)) + " miliar" + (n % 1e9 ? " " + terbilang(n % 1e9) : "");
  return String(n);
}
const title = (s) => s.replace(/\b\p{L}/gu, (c) => c.toUpperCase());
export const terbilangRupiah = (n) => (n === 0 ? "Nol Rupiah" : title(terbilang(n)) + " Rupiah");

/**
 * data: {
 *   varian: "toko" | "qurban", judul: "INVOICE" | "PROFORMA-INVOICE", nomor, tanggal(iso), kepada,
 *   suratJalan?, telepon?, baris: [{desc, qty, unit, harga}], diskon?, uangMuka?, jatuhTempo?(iso),
 *   catatan?: string  (qurban: kalimat setelah "Note :")
 *   bankInfo?, penandatangan?, tandaTangan?: boolean (varian toko)
 *   tampilTotal?: boolean (proforma menampilkan baris "Total" di atas "Total Pembelanjaan")
 * }
 */
const H = (n) => n;
const LEBAR = 0.94; // koreksi konversi lebar kolom Excel -> piksel saat dicetak
const SKALA = 0.825; // contoh dicetak pada skala ini terhadap ukuran huruf asli // tinggi baris (pt) mengikuti skala contoh
export async function buatInvoiceXlsx(data) {
  const toko = data.varian === "toko";
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(data.judul === "INVOICE" ? "Invoice" : "Proforma", {
    pageSetup: { paperSize: toko ? 11 : 9, orientation: toko ? "landscape" : "portrait", fitToPage: false, scale: Math.round(SKALA * 100),
      margins: { left: 0.71, right: 0.4, top: toko ? 1.045 : 0.6, bottom: 0.4, header: 0, footer: 0 }, horizontalCentered: false },
    views: [{ showGridLines: false }],
  });
  // lebar kolom (px Google Sheets -> karakter Excel)
  const px = toko ? [40, 159, 68, 93, 112, 93, 95] : [45, 205, 64, 65, 96, 87, 97]; // px @96dpi, diukur dari PDF contoh
  ws.columns = px.map((w) => ({ width: Math.round((w * LEBAR / SKALA / 7) * 10) / 10 }));
  const F = (o = {}) => ({ name: "Cairo", size: 10, ...o });
  const fill = (argb) => ({ type: "pattern", pattern: "solid", fgColor: { argb } });
  const HEAD = toko ? "FFD9EAD3" : "FFF9CB9C";
  const TOT = toko ? "FFD9EAD3" : "FFE69138";
  let r = 1;

  // --- judul + logo
  ws.getRow(r).height = toko ? 62 : 72;
  ws.mergeCells(r, 1, r, 5);
  const t = ws.getCell(r, 1);
  t.value = data.judul; t.font = { name: "Cairo", size: toko ? 36 : 38, bold: true }; t.alignment = { vertical: "bottom", horizontal: "left" };
  if (toko) {
    const img = wb.addImage({ filename: path.join(ASSETS, "lamitra-logo.png"), extension: "png" });
    ws.addImage(img, { tl: { col: 6.45, row: 0.3 }, ext: { width: 56, height: 70 } });
  } else {
    const img = wb.addImage({ filename: path.join(ASSETS, "hmi-logo.png"), extension: "png" });
    ws.addImage(img, { tl: { col: 5.95, row: 0.05 }, ext: { width: 124, height: 84 } });
  }
  r++;
  ws.getRow(r).height = toko ? 3.5 : 18; r++;

  // --- meta
  // contoh: label "No." menempel di kolom A, nilai di B; supaya tidak terpotong, A:B digabung
  const sp = (n) => " ".repeat(Math.max(0, n));
  const mrow = (row, label, value, extra, padKiri = 0) => {
    ws.getRow(row).height = toko ? 12.3 : 12.5;
    ws.mergeCells(row, 1, row, extra ? 3 : 7);
    const a = ws.getCell(row, 1);
    // titik dua sejajar seperti contoh (label dipadatkan dengan spasi)
    a.value = { richText: [{ text: label + sp(padKiri) + " ", font: F({ size: 9, bold: true }) }, { text: ":  " + value, font: F({ size: 9 }) }] };
    if (extra) {
      ws.mergeCells(row, 4, row, 7);
      const e = ws.getCell(row, 4);
      e.value = { richText: [{ text: extra[0] + sp(extra[3] || 0) + " ", font: F({ size: 9, bold: true }) }, { text: ":" + sp(8) + extra[1], font: F({ size: 9, italic: !!extra[2] }) }] };
    }
  };
  mrow(r++, "No.", data.nomor, data.suratJalan ? ["Surat Jalan", data.suratJalan, true, 1] : null, 9);
  mrow(r++, "Tanggal", tglEN(data.tanggal, toko), null, 0);
  mrow(r++, "Kepada", data.kepada, data.telepon ? ["No. Telepon", data.telepon, false, 0] : null, 1);
  ws.getRow(r).height = toko ? 10 : 18.5; r++;

  // --- tabel
  ws.getRow(r).height = toko ? 19 : 14;
  ["No", "Deskripsi", "Qty", "Satuan", "Harga Per Satuan", "Total", "Keterangan"].forEach((h, i) => {
    const c = ws.getCell(r, i + 1); c.value = h; c.font = F({ bold: true }); c.fill = fill(HEAD); c.border = box;
    c.alignment = { horizontal: "center", vertical: "middle" };
  });
  r++;
  let total = 0;
  data.baris.forEach((b, i) => {
    ws.getRow(r).height = toko ? 14.5 : 12.2;
    const jumlah = b.qty * b.harga; total += jumlah;
    const vals = [i + 1, b.desc, b.qty, b.unit, b.harga, jumlah, ""];
    vals.forEach((v, k) => {
      const c = ws.getCell(r, k + 1); c.value = v; c.font = F(); c.border = box;
      if (k === 0 || k === 2 || k === 3) c.alignment = { horizontal: "center", vertical: "middle" };
      else c.alignment = { vertical: "middle" };
      if (k === 2) c.numFmt = "#,##0.###";
      if (k === 4 || k === 5) {
        c.numFmt = toko ? '"Rp"#,##0' : '_("Rp"* #,##0_);_("Rp"* (#,##0);_("Rp"* 0_);_(@_)';
        c.alignment = { horizontal: toko ? "center" : undefined, vertical: "middle" };
      }
    });
    r++;
  });

  // --- ringkasan
  const diskon = data.diskon || 0, dp = data.uangMuka || 0;
  const kurang = total - diskon - dp;
  const label = (row, text) => {
    ws.mergeCells(row, 1, row, 2);
    const c = ws.getCell(row, 1); c.value = text; c.font = F({ size: 11, bold: true, color: { argb: GREY } }); c.alignment = { vertical: "middle" };
  };
  const sumRow = (text, value, { filled = true, blank = false } = {}) => {
    ws.getRow(r).height = toko ? 18 : 14.5;
    label(r, text);
    ws.mergeCells(r, 3, r, toko ? 6 : 5);
    const mid = ws.getCell(r, 3); if (filled) mid.fill = fill(TOT);
    if (!toko) ws.mergeCells(r, 6, r, 7);
    const g = ws.getCell(r, toko ? 7 : 6);
    if (!blank) { g.value = value; }
    g.font = F({ size: 11, bold: true });
    g.numFmt = toko ? '"Rp"#,##0' : '"Rp"  #,##0';
    g.alignment = { horizontal: "right", vertical: "middle" };
    if (filled) g.fill = fill(TOT);
    if (toko) {
      // tampilan toko: garis hitam tipis di atas dan bawah baris
      for (let c = 1; c <= 7; c++) { const cell = ws.getCell(r, c); cell.border = { top: thin, bottom: thin }; }
    }
    r++;
  };
  if (data.tampilTotal) sumRow("Total", total);
  sumRow("Total Pembelanjaan", data.tampilTotal ? total - diskon : total);
  if (!data.tampilTotal && data.diskon !== undefined) sumRow("Discount", diskon);
  sumRow("Uang Muka", dp, { filled: false, blank: !data.tampilTotal && !dp && !toko ? true : false });
  sumRow("Kekurangan", kurang);
  // terbilang
  ws.getRow(r).height = toko ? 15.2 : 14.5;
  label(r, "Terbilang");
  ws.mergeCells(r, 3, r, 7);
  const tb = ws.getCell(r, 3);
  if (toko) { /* contoh toko: kolom terbilang dibiarkan kosong */ }
  else { tb.value = terbilangRupiah(kurang); tb.font = F({ size: 8 }); tb.fill = fill("FFD9D9D9"); tb.alignment = { horizontal: "center", vertical: "middle" }; }
  if (toko) for (let k = 1; k <= 7; k++) ws.getCell(r, k).border = { top: thin, bottom: thin };
  r++;

  // --- rekening
  const rekRow = (parts, align) => {
    ws.getRow(r).height = toko ? 14 : 16.5;
    ws.mergeCells(r, 1, r, align === "right" ? 6 : 7);
    const c = ws.getCell(r, 1);
    c.value = { richText: parts.map((p) => ({ text: p[0], font: F({ size: 10, italic: true, bold: !!p[1], color: { argb: BLUE } }) })) };
    c.alignment = { horizontal: align === "right" ? "right" : "center", vertical: "middle" };
    r++;
  };
  if (toko && data.bankInfo) rekRow([["Pembayaran melalui transfer "], [data.bankInfo, true]], "center");
  else rekRow([["Pembayaran melalui transfer "], ["Bank Mandiri a/n. Harmoni Mitra Inovindo", true], [" 1290015674415"]], "center");
  if (!toko) rekRow([["Bank Rakyat Indonesia (BRI) a/n. Harmoni Mitra Inovindo", true], [" 117001000653562"]], "right");

  // --- jatuh tempo / note
  const note = (lbl, val, pad) => {
    ws.getRow(r).height = 12.5;
    ws.mergeCells(r, 1, r, 7);
    ws.getCell(r, 1).value = { richText: [{ text: lbl + sp(pad), font: F({ size: 10, color: { argb: BLUE } }) }, { text: ":  " + val, font: F({ size: 10 }) }] };
    r++;
  };
  if (toko) {
    ws.getRow(r).height = 12.5; ws.mergeCells(r, 1, r, 7);
    const c = ws.getCell(r, 1); c.value = "Jatuh Tempo : " + tglID(data.jatuhTempo); c.font = F({ size: 10, color: { argb: BLUE } }); r++;
  } else if (data.judul === "INVOICE") {
    note("Jatuh Tempo", tglDash(data.jatuhTempo), 14);
    note("Note", data.catatan || "", 29);
  } else {
    note("Note", data.catatan || "", 29);
  }
  ws.getRow(r).height = toko ? 24 : 10; r++;

  // --- tanda tangan
  const sigTop = r;
  ws.getRow(r).height = toko ? 47 : 45.5; r++;
  const ttdOk = data.tandaTangan !== false && (!data.penandatangan || data.penandatangan === "Ahmad Hunain");
  const sig = wb.addImage({ filename: path.join(ASSETS, toko ? "sig-hunain-toko.png" : "sig-hunain-inv.png"), extension: "png" });
  if (!ttdOk) { /* tanpa tanda tangan digital */ }
  else if (toko) ws.addImage(sig, { tl: { col: 0.95, row: sigTop - 1 + 0.1 }, ext: { width: 67, height: 41 } });
  else {
    ws.addImage(sig, { tl: { col: 0.2, row: sigTop - 1 + 0.15 }, ext: { width: 67, height: 36 } });
    if (data.judul === "INVOICE" || data.judul === "PROFORMA-INVOICE") {
      const lg = wb.addImage({ filename: path.join(ASSETS, "hmi-logo.png"), extension: "png" });
      ws.addImage(lg, { tl: { col: 1.15, row: sigTop - 1 + 0.0 }, ext: { width: 70, height: 47 } });
    }
  }
  const cap = (txt, borderTop) => {
    ws.getRow(r).height = r === sigTop + 1 ? 14 : 17;
    ws.mergeCells(r, 1, r, toko ? 3 : 3);
    const c = ws.getCell(r, 1); c.value = txt; c.font = F({ size: 10 }); c.alignment = { horizontal: "center" };
    if (borderTop) for (let k = 1; k <= 3; k++) ws.getCell(r, k).border = { top: thin };
    r++;
  };
  cap("Direktur Keuangan", false);
  cap(data.penandatangan || "Ahmad Hunain", true);
  // batang abu-abu bawah
  if (toko || data.judul === "PROFORMA-INVOICE") {
    ws.getRow(r).height = 5;
    for (let k = 1; k <= 7; k++) ws.getCell(r, k).fill = fill("FF999999");
  }
  ws.eachRow((row) => row.eachCell((c) => { c.alignment = { ...(c.alignment || {}), vertical: (c.alignment && c.alignment.vertical) || "middle" }; }));
  return wb;
}

export async function simpanInvoice(data, file) {
  const wb = await buatInvoiceXlsx(data);
  await wb.xlsx.writeFile(file);
}
