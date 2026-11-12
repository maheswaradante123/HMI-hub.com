// Urutan nomor dokumen menurut tahun, bulan, lalu nomor: INV-001-XI-26 (November 2026) di atas INV-007-VIII-26 (Agustus 2026).
// Pola: [AWALAN-]urut-bulanRomawi-tahun2angka[-akhiran], mis. RO-HBR-001-II-26, INV-006-X-26-2, PROD-HBR-001-II-26-R2.
const MONTH: Record<string, number> = { I: 1, II: 2, III: 3, IV: 4, V: 5, VI: 6, VII: 7, VIII: 8, IX: 9, X: 10, XI: 11, XII: 12 };
const RE = /^(.*?)-?(\d+)-(XII|XI|X|IX|VIII|VII|VI|V|IV|III|II|I)-(\d{2})(?:-R?(\d+))?$/;

export type DocNoKey = { prefix: string; seq: number; month: number; year: number; extra: number };

export function docNoKey(no: string): DocNoKey | null {
  const m = RE.exec(String(no ?? "").trim());
  if (!m) return null;
  return { prefix: m[1], seq: Number(m[2]), month: MONTH[m[3]], year: 2000 + Number(m[4]), extra: m[5] ? Number(m[5]) : 0 };
}

/** Naik: lama ke baru. Nomor yang tidak berpola diurutkan sebagai teks dan dianggap paling lama. */
export function compareDocNo(a: string, b: string): number {
  const x = docNoKey(a), y = docNoKey(b);
  if (!x || !y) return x ? 1 : y ? -1 : String(a).localeCompare(String(b), "id", { numeric: true });
  return x.year - y.year || x.month - y.month || x.seq - y.seq || x.prefix.localeCompare(y.prefix, "id") || x.extra - y.extra;
}

/** Terbaru di atas. */
export function sortDocNoDesc<T>(rows: T[], get: (r: T) => string): T[] {
  return [...rows].sort((a, b) => compareDocNo(get(b), get(a)));
}
