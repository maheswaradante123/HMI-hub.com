// Mengisi Surat Perjanjian (SP-JB & SP-PL) dengan mengganti bagian yang di-highlight kuning pada file Word asli Owner.
// Format, huruf, dan susunan dokumen tidak diubah; hanya teks kuning diganti dan highlight dihapus.
import JSZip from "jszip";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { terbilang } from "./invoice-xlsx.mjs";

const TPL = path.join(path.dirname(fileURLToPath(import.meta.url)), "templates");
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const HARI = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
const BLN = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
const ROMAWI = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
export const rp = (n) => Math.round(n).toLocaleString("id-ID");
const cap = (s) => s.replace(/\b\p{L}/gu, (c) => c.toUpperCase());
export const kata = (n) => cap(terbilang(n));
export const hariDari = (iso) => HARI[new Date(iso + "T00:00:00Z").getUTCDay()];
export const tglPanjang = (iso) => { const [y, m, d] = iso.split("-").map(Number); return `${d} ${BLN[m - 1]} ${y}`; };
export const romawiBulan = (iso) => ROMAWI[Number(iso.split("-")[1]) - 1];
export const seq3 = (n) => String(n).padStart(3, "0");

// Tahap 1: ganti tiap kelompok run kuning (berurutan dalam satu paragraf) dengan token «n»; hapus highlight.
function tokenisasi(xml) {
  let n = 0;
  xml = xml.replace(/<w:p[ >][\s\S]*?<\/w:p>/g, (p) => {
    let prevY = false;
    return p.replace(/<w:r[ >][\s\S]*?<\/w:r>/g, (r) => {
      const y = r.includes('w:highlight w:val="yellow"');
      let out = r;
      if (y) {
        out = out.replace(/<w:highlight w:val="yellow"\/>/g, "");
        if (!prevY) { const id = n++; let first = true; out = out.replace(/<w:t(?: [^>]*)?>[\s\S]*?<\/w:t>/g, () => (first ? ((first = false), `<w:t xml:space="preserve">«${id}»</w:t>`) : "")); }
        else out = out.replace(/<w:t(?: [^>]*)?>[\s\S]*?<\/w:t>/g, "");
      }
      prevY = y; return out;
    });
  });
  return { xml, n };
}

// Gandakan baris tabel yang memuat token pertama..terakhir sebanyak jumlah sapi.
function gandakanBaris(xml, tokens, jumlah) {
  const [t0] = tokens;
  const re = /<w:tr[ >][\s\S]*?<\/w:tr>/g;
  return xml.replace(re, (tr) => {
    if (!tr.includes(`«${t0}»`)) return tr;
    let all = "";
    for (let i = 0; i < jumlah; i++) {
      let c = tr;
      for (const t of tokens) c = c.replace(`«${t}»`, `«${t}#${i}»`);
      c = c.replace(/(<w:t(?: [^>]*)?>)1(<\/w:t>)/, `$1${i + 1}$2`);
      all += c;
    }
    return all;
  });
}

function isi(xml, nilai) {
  return xml.replace(/«([\d#]+)»/g, (m, k) => {
    if (!(k in nilai)) throw new Error("Isian tidak ada: " + k);
    return esc(nilai[k]);
  });
}

// Paksa semua teks memakai Arial (font surat perjanjian pemeliharaan).
function paksaArial(xml) {
  return xml.replace(/<w:rFonts\b[^>]*\/>/g, '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/>');
}

async function proses(file, tokensBaris, bangunNilai, data, arial = false) {
  const zip = await JSZip.loadAsync(await fs.readFile(path.join(TPL, file)));
  let { xml } = tokenisasi(await zip.file("word/document.xml").async("string"));
  xml = gandakanBaris(xml, tokensBaris, data.sapi.length);
  zip.file("word/document.xml", isi(arial ? paksaArial(xml) : xml, bangunNilai(data)));
  if (arial) {
    let st = await zip.file("word/styles.xml").async("string");
    st = paksaArial(st);
    if (!/<w:docDefaults>[\s\S]*<w:rFonts/.test(st)) st = st.replace(/<w:rPrDefault>\s*<w:rPr>/, '<w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/>');
    zip.file("word/styles.xml", st);
  }
  return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
}

/**
 * Data SP-JB: { seq, tanggal(iso), pembeli, nik, alamat, sapi:[{jenis, nomor, bobotAwal, nilaiAwal}] }
 * (nilaiAwal = bobot awal x harga beli per kg)
 */
export function nilaiJB(d) {
  const total = d.sapi.reduce((a, s) => a + s.nilaiAwal, 0);
  const v = {
    0: seq3(d.seq), 1: romawiBulan(d.tanggal), 2: d.pembeli, 3: hariDari(d.tanggal), 4: tglPanjang(d.tanggal),
    5: d.pembeli, 6: d.nik, 7: d.alamat, 8: kata(d.sapi.length).toLowerCase(), 9: rp(total), 10: kata(total) + " Rupiah",
    11: d.pembeli, 12: d.pembeli, 17: rp(total),
  };
  d.sapi.forEach((s, i) => { v[`13#${i}`] = s.jenis; v[`14#${i}`] = s.nomor; v[`15#${i}`] = s.bobotAwal; v[`16#${i}`] = rp(s.nilaiAwal); });
  return v;
}
export const buatSpJb = (d) => proses("SP-JB.docx", [13, 14, 15, 16], nilaiJB, d);

/**
 * Data SP-PL: { seq, tanggal, pemilik, nik, alamat, telepon, jb:{seq, tanggal}, hariPemeliharaan,
 *               tarifPerHari, sapi:[{jenis, nomor, bobotAwal, nilaiAwal}] }
 * Satu perjanjian dibuat per pemilik; tarif/hari memakai sapi pertama (satu kelas) bila tarif sama.
 */
export function nilaiPL(d) {
  const total = d.sapi.reduce((a, s) => a + s.nilaiAwal, 0);
  const s0 = d.sapi[0];
  const nomorTeks = d.sapi.map((s) => s.nomor).join(", ");
  const kataNomor = d.sapi.map((s) => (/^\d+$/.test(String(s.nomor)) ? terbilang(Number(s.nomor)) : String(s.nomor))).join(", ");
  const v = {
    0: seq3(d.seq), 1: romawiBulan(d.tanggal), 2: d.pemilik, 3: hariDari(d.tanggal), 4: tglPanjang(d.tanggal),
    5: d.pemilik, 6: d.nik, 7: d.alamat, 8: kata(d.sapi.length).toLowerCase(),
    9: seq3(d.jb.seq), 10: romawiBulan(d.jb.tanggal), 11: tglPanjang(d.jb.tanggal),
    12: seq3(d.jb.seq), 13: romawiBulan(d.jb.tanggal), 14: tglPanjang(d.jb.tanggal), 15: d.pemilik,
    16: d.hariPemeliharaan, 17: terbilang(d.hariPemeliharaan),
    18: nomorTeks, 19: kataNomor, 20: nomorTeks, 21: kataNomor,
    22: rp(d.tarifPerHari), 23: kata(d.tarifPerHari) + " Rupiah",
    24: d.sapi.map((s) => s.bobotAwal).join(", "), 25: d.sapi.map((s) => terbilang(s.bobotAwal)).join(", "),
    26: d.pemilik, 27: d.alamat, 28: d.telepon, 29: d.pemilik, 30: d.pemilik, 35: rp(total),
  };
  d.sapi.forEach((s, i) => { v[`31#${i}`] = s.jenis; v[`32#${i}`] = s.nomor; v[`33#${i}`] = s.bobotAwal; v[`34#${i}`] = rp(s.nilaiAwal); });
  return v;
}
export const buatSpPl = (d) => proses("SP-PL.docx", [31, 32, 33, 34], nilaiPL, d, true);
