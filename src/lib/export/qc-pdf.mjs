// Pembuat PDF QC Report. Ukuran dan posisi diukur dari PDF contoh QC-002-IX-26 (Letter, satuan pt).
import { PDFDocument, PDFName, rgb, degrees, pushGraphicsState, popGraphicsState, setGraphicsState } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { tglID, tglDash } from "./invoice-xlsx.mjs";
import { hitungJurnal } from "./qc-xlsx.mjs";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 612, H = 792, BASE = 0.4284;
const X = [88.2, 130.8, 200.5, 270.0, 354.7, 439.3, 524.0];
const PURPLE = rgb(0.851, 0.8235, 0.9137), BLUE = rgb(0.8118, 0.8863, 0.9529), GREEN = rgb(0.851, 0.9176, 0.8275);
const BLACK = rgb(0, 0, 0), GRAYBAR = rgb(0.6, 0.6, 0.6);
const ROW = 13.43, BLOCK = ROW * 3;
const LIMIT = 700; // batas bawah tabel pada halaman yang masih akan diberi tanda tangan

export async function buatQcPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "adhimitra-logo.png"));
  const sPpic = await pdf.embedPng(await read("assets", "qc-sig-ppic.png"));
  const sQc = await pdf.embedPng(await read("assets", "qc-sig-qc.png"));
  const sDir = await pdf.embedPng(await read("assets", "qc-sig-dir-stempel.png"));
  const gs = pdf.context.register(pdf.context.obj({ Type: "ExtGState", BM: "Multiply" }));

  let page;
  const T = (s, x, top, size, font = reg) => page.drawText(s, { x, y: H - top - BASE * size, size, font, color: BLACK });
  const wd = (s, size, font = reg) => font.widthOfTextAtSize(s, size);
  const mid = (s, x0, x1, top, size, font = reg) => T(s, (x0 + x1) / 2 - wd(s, size, font) / 2, top, size, font);
  const rect = (x0, x1, top, bot, color) => page.drawRectangle({ x: x0, y: H - bot, width: x1 - x0, height: bot - top, color });
  const line = (x0, y0, x1, y1) => page.drawLine({ start: { x: x0, y: H - y0 }, end: { x: x1, y: H - y1 }, thickness: 0.72, color: BLACK });
  const img = (im, x0, x1, top, bot) => {
    page.node.setExtGState(PDFName.of("GSM"), gs);
    page.pushOperators(pushGraphicsState(), setGraphicsState(PDFName.of("GSM")));
    page.drawImage(im, { x: x0, y: H - bot, width: x1 - x0, height: bot - top });
    page.pushOperators(popGraphicsState());
  };

  // blok penimbangan per sapi
  const cows = d.sapi.map((s, i) => ({ s, i, jur: hitungJurnal(s) }));
  const segs = []; // {cow, rows:[jur...], first}
  cows.forEach((c) => { if (c.jur.length === 0) segs.push({ c, rows: [], first: true }); else c.jur.forEach((j, k) => segs.push({ c, rows: [j], first: k === 0 })); });

  const header = (top) => {
    rect(X[0], X[6], top, top + 27.6, PURPLE);
    ["No.", "Nomor Sapi", "Bobot Awal"].forEach((h, i) => mid(h, X[i], X[i + 1], top + 13.2, 10.6, bold));
    mid("Jurnal Penimbangan", X[3], X[6], top + 13.2, 10.6, bold);
    line(X[0], top + 0.4, X[6], top + 0.4); line(X[0], top + 27.2, X[6], top + 27.2);
  };

  const newPage = (first) => {
    page = pdf.addPage([W, H]);
    if (first) {
      T("Quality Control Report", 90.7, 82.7, 31.35, bold);
      img(logo, 432.5, 522.8, 60.6, 113.9);
      [["No.", d.nomor, 136.1], ["Publish", tglDash(d.publish), 149.8], ["Kepada", d.kepada, 163.5]].forEach(([l, v, top]) => {
        T(l, 90.7, top, 9.4, bold); T(":", 133.6, top, 9.4, bold); T(v, 141, top, 9.4);
      });
      T("sekretariat@adhimitrafarm.com", 357, 138.7, 8.5); T("085-123-123-918", 357, 152.2, 8.5);
      return 184.1;
    }
    return 60;
  };

  let y = newPage(true);
  header(y);
  let tableTop = y; y += 27.6 - 0.5;
  let cowStart = y, curCow = null, tint = 0, pageTop = tableTop;

  const closeCow = (endY) => {
    if (curCow === null) return;
    const c = cows[curCow];
    const midY = (cowStart + endY) / 2;
    mid(String(c.i + 1), X[0], X[1], midY - 2.5, 10.6); mid(c.s.nomor, X[1], X[2], midY - 2.5, 10.6); mid(`${c.s.bobotAwal}Kg`, X[2], X[3], midY - 2.5, 10.6);
    line(X[0], endY, X[6], endY);
  };
  const closePageTable = (endY) => { // garis tegak tabel pada halaman ini
    [88.6, 130.8, 200.5, 270.4, 523.8].forEach((x) => line(x, pageTop, x, endY));
  };

  const emptyH = ROW * 2;
  for (const sg of segs) {
    const h = sg.rows.length ? BLOCK : emptyH;
    if (y + h > LIMIT) {
      closeCow(y); closePageTable(y);
      y = newPage(false); header(y); pageTop = y; y += 27.6 - 0.5; cowStart = y;
      curCow = sg.c.i; // lanjutan sapi yang sama: nomor ditulis ulang
    }
    if (curCow !== sg.c.i) { closeCow(y); curCow = sg.c.i; cowStart = y; tint = sg.c.i % 2; }
    if (!sg.rows.length) {
      rect(X[3], X[6], y, y + emptyH, tint ? GREEN : BLUE);
      mid("Belum ada penimbangan lanjutan", X[3], X[6], y + 8, 10.6);
      line(X[3], y + emptyH, X[6], y + emptyH); y += emptyH; continue;
    }
    const j = sg.rows[0], col = sg.c.i % 2 ? GREEN : BLUE;
    rect(X[3], X[6], y, y + ROW * 2, col);
    mid(`Penimbangan ${tglID(j.tgl)}`, X[3], X[6], y + 5.5, 11.2, bold);
    ["Bobot", "Perkembangan", "ADG"].forEach((h, i) => mid(h, X[3 + i], X[4 + i], y + ROW + 5.5, 10.6, bold));
    const vals = [`${j.bobot}Kg`, `${j.gain}Kg`, j.adg.toFixed(2)];
    vals.forEach((v, i) => mid(v, X[3 + i], X[4 + i], y + ROW * 2 + 5.5, 10.6));
    for (let k = 1; k <= 3; k++) line(X[3], y + ROW * k, X[6], y + ROW * k);
    line(X[4], y + ROW, X[4], y + BLOCK); line(X[5], y + ROW, X[5], y + BLOCK);
    y += BLOCK;
  }
  closeCow(y); closePageTable(y);

  // catatan, tanda tangan
  if (y + 215 > H - 40) { newPage(false); y = 60; }
  let n = y + 20.5;
  T("Catatan :", 90.7, n, 11.9, bold); T(d.catatan || "Sapi dalam keadaan sehat.", 141, n, 11.1);
  T("Laporan ini disusun oleh", 92.9, n + 24.4, 9.8); T("Mengetahui", 336, n + 24.4, 9.8);
  img(sPpic, 88.8, 200.3, n + 46.6, n + 114.3);
  img(sQc, 201.5, 353.9, n + 33.6, n + 127.1);
  img(sDir, 403.7, 490.8, n + 44.0, n + 131.0);
  const ry = n + 131.5;
  [[d.ppic, "PPIC", X[0], X[2]], [d.qc, "Quality Control", X[2], X[4]], [d.direktur, "Dir. Operasional", X[4], X[6]]].forEach(([nm, role, a, b]) => {
    mid(role, a, b, ry + 2.6, 9.8); mid(nm, a, b, ry + 16, 9.8);
  });
  line(X[0], ry + 9.2, X[6], ry + 9.2);
  rect(X[0], X[6], ry + 36.3, ry + 41.5, GRAYBAR);
  return pdf.save();
}
