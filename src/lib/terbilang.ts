// Angka menjadi kata dalam bahasa Indonesia untuk kwitansi: 14466325 -> "Empat Belas Juta Empat Ratus Enam Puluh Enam Ribu Tiga Ratus Dua Puluh Lima".
const SATUAN = ["", "Satu", "Dua", "Tiga", "Empat", "Lima", "Enam", "Tujuh", "Delapan", "Sembilan", "Sepuluh", "Sebelas"];
const SKALA = ["", "Ribu", "Juta", "Miliar", "Triliun"];

function ratusan(n: number): string {
  if (n < 12) return SATUAN[n];
  if (n < 20) return `${SATUAN[n - 10]} Belas`;
  if (n < 100) return `${SATUAN[Math.floor(n / 10)]} Puluh${n % 10 ? ` ${SATUAN[n % 10]}` : ""}`;
  const h = Math.floor(n / 100), r = n % 100;
  return `${h === 1 ? "Seratus" : `${SATUAN[h]} Ratus`}${r ? ` ${ratusan(r)}` : ""}`;
}

export function terbilang(value: number): string {
  const n = Math.round(Math.abs(Number(value)));
  if (!Number.isFinite(n)) return "";
  if (n === 0) return "Nol";
  if (n >= 1e15) return "";
  const parts: string[] = [];
  const groups: number[] = [];
  for (let x = n; x > 0; x = Math.floor(x / 1000)) groups.push(x % 1000);
  for (let i = groups.length - 1; i >= 0; i--) {
    const g = groups[i];
    if (!g) continue;
    parts.push(i === 1 && g === 1 ? "Seribu" : `${ratusan(g)}${SKALA[i] ? ` ${SKALA[i]}` : ""}`);
  }
  return (value < 0 ? "Minus " : "") + parts.join(" ");
}

export const terbilangRupiah = (value: number) => `${terbilang(value)} Rupiah`;
