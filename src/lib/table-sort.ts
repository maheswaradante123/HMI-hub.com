// Membaca isi sel tabel untuk pengurutan: tanggal ("5 Mei 2026", "1 Apr 2026", "12 Jun 2026"), angka ("Rp 2.359.665", "30 hari"), atau teks.
const MONTHS = ["jan", "feb", "mar", "apr", "mei", "jun", "jul", "agu", "sep", "okt", "nov", "des"];

export function cellValue(text: string): { n?: number; s?: string } {
  const t = text.trim();
  const d = t.match(/^(\d{1,2}) ([A-Za-z]+) (\d{4})$/);
  if (d) {
    // aplikasi menampilkan bulan singkat (Apr, Des, Okt); nama lengkap juga dikenali lewat tiga huruf pertamanya
    const k = d[2].toLowerCase().slice(0, 3);
    const i = k === "agt" ? 7 : MONTHS.indexOf(k);
    if (i >= 0) return { n: Date.UTC(+d[3], i, +d[1]) };
  }
  const x = t.replace(/^Rp\s*/i, "").replace(/\s*(Kg|hari|Hari)$/, "").trim();
  if (/^-?[\d.,]+$/.test(x) && /\d/.test(x)) {
    const n = parseFloat(x.replace(/\./g, "").replace(",", "."));
    if (!isNaN(n)) return { n };
  }
  return { s: t.toLowerCase() };
}
