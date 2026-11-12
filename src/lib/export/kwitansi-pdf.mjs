// PDF Kwitansi (Receipt) PT Harmoni Mitra Inovindo. A5 lanskap, mengikuti contoh KW-002-XI-26 (satuan pt).
import { PDFDocument, rgb } from "pdf-lib";
import fontkit from "@pdf-lib/fontkit";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const read = (...p) => fs.readFile(path.join(DIR, ...p));
const W = 595.28, H = 419.53, M = 40, BASE = 0.4284;
const BLACK = rgb(0, 0, 0), GREY = rgb(0.35, 0.35, 0.35), LINE = rgb(0.6, 0.6, 0.6);
const BULAN = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
export const tglKw = (iso) => { const [y, m, d] = String(iso).slice(0, 10).split("-").map(Number); return `${d} ${BULAN[m - 1]} ${y}`; };
export const rpKw = (n) => "Rp " + Math.round(Number(n)).toLocaleString("en-US");

/** d: {nomor, tanggal(iso), dari, terbilang, untuk, jumlah, penandatangan, jabatan, catatan?} */
export async function buatKwitansiPdf(d) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const reg = await pdf.embedFont(await read("fonts", "Cairo-400.ttf"), { subset: true });
  const bold = await pdf.embedFont(await read("fonts", "Cairo-700.ttf"), { subset: true });
  const logo = await pdf.embedPng(await read("assets", "hmi-logo.png"));
  const page = pdf.addPage([W, H]);
  const T = (t, x, top, size, font = reg, color = BLACK) => t && page.drawText(String(t), { x, y: H - top - BASE * size, size, font, color });
  const wd = (t, size, font = reg) => font.widthOfTextAtSize(String(t), size);
  const hline = (x0, x1, top, th = 0.5) => page.drawLine({ start: { x: x0, y: H - top }, end: { x: x1, y: H - top }, thickness: th, color: LINE });
  // Pecah teks menjadi baris selebar maxW (kata demi kata; kata yang terlalu panjang dipotong).
  const wrap = (text, maxW, size, font = reg) => {
    const lines = []; let cur = "";
    for (const w of String(text ?? "").split(/\s+/).filter(Boolean)) {
      const next = cur ? `${cur} ${w}` : w;
      if (wd(next, size, font) <= maxW) cur = next;
      else { if (cur) lines.push(cur); cur = w; }
    }
    if (cur) lines.push(cur);
    return lines.length ? lines : [""];
  };

  // kop
  page.drawImage(logo, { x: M, y: H - 30 - 38, width: 56, height: 38 });
  T("PT HARMONI MITRA INOVINDO", M + 66, 28, 10.5, bold);
  const addr = ["Green Lake Cibubur No A5 Peternakan Raya, RT.1/RW.2, Pd. Ranggon,", "Kec. Cipayung, Kota Jakarta Timur, DKI Jakarta 13860", "Tel. : (021) 48676147", "Email : harmonimitrainovindo@gmail.com"];
  addr.forEach((l, i) => T(l, M + 66, 43 + i * 9.5, 7.2, reg, GREY));
  const RX = W - M;
  const title = "KWITANSI";
  T(title, RX - wd(title, 20, bold), 26, 20, bold);
  T("RECEIPT", RX - wd("RECEIPT", 8), 49, 8, reg, GREY);
  T(`No : ${d.nomor}`, RX - wd(`No : ${d.nomor}`, 9.5, bold), 63, 9.5, bold);
  T("Number", RX - wd("Number", 7.5), 76, 7.5, reg, GREY);
  hline(M, RX, 92, 0.8);

  // isi
  const LX = M, CX = 168, VX = 178, VW = RX - VX;
  let top = 106;
  const row = (id, en, value, bolded = false) => {
    T(id, LX, top, 9.5, bold); T(en, LX, top + 11, 7.5, reg, GREY); T(":", CX, top, 9.5, bold);
    const lines = wrap(value, VW, 9.5, bolded ? bold : reg);
    lines.forEach((l, i) => T(l, VX, top + i * 12.5, 9.5, bolded ? bold : reg));
    top += Math.max(30, lines.length * 12.5 + 10);
  };
  row("Sudah Terima Dari", "Received From", d.dari, true);
  row("Banyaknya Uang", "Amount Received", d.terbilang, true);
  row("Untuk Pembayaran", "In Payment Of", d.untuk);
  T(`Note: ${d.catatan || "Kwitansi tersebut hanya untuk keperluan administrasi pembayaran."}`, LX, top + 2, 7.5, reg, GREY);

  // jumlah dan tanda tangan, dijaga di bawah isi
  const by = Math.max(top + 30, 300);
  const amt = rpKw(d.jumlah);
  page.drawRectangle({ x: LX, y: H - by - 30, width: wd(amt, 17, bold) + 24, height: 30, borderColor: BLACK, borderWidth: 1 });
  T(amt, LX + 12, by + 6, 17, bold);
  const sx = RX - 170;
  T(`Jakarta, ${tglKw(d.tanggal)}`, sx, by - 6, 9.5);
  const ny = by + 52;
  T(d.penandatangan, sx, ny, 9.5, bold);
  hline(sx, sx + Math.max(wd(d.penandatangan, 9.5, bold), 90), ny + 14, 0.6);
  T(d.jabatan, sx, ny + 17, 8.5);
  return Buffer.from(await pdf.save());
}
