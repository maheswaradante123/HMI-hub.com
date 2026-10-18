// Penimbangan Karkas: item diketik bebas lalu diberi kategori. Perhitungan ini dipakai form, daftar dan halaman detail.
export const CW_CATS = ["Daging", "Tulang", "Jeroan", "Non-Karkas"] as const;
export type CwCat = (typeof CW_CATS)[number];
export type CwRow = { name: string; cat: CwCat; weight: string };

const n = (v: unknown) => { const x = Number(v); return Number.isFinite(x) ? x : 0; };

/** Kode kategori produk di master (DAGING/TULANG/JEROHAN) menjadi nama kategori di form. Kategori lain dianggap Daging. */
export function cwCatFromCode(code: string | null | undefined): CwCat {
  return code === "TULANG" ? "Tulang" : code === "JEROHAN" ? "Jeroan" : "Daging";
}

export type CwTotals = { total: number; byCat: Record<CwCat, number>; meatPct: number | null; over: boolean };

export function cwTotals(rows: { cat: CwCat; weight: number }[], carcass: number): CwTotals {
  const byCat: Record<CwCat, number> = { Daging: 0, Tulang: 0, Jeroan: 0, "Non-Karkas": 0 };
  for (const r of rows) byCat[r.cat] += n(r.weight);
  const total = CW_CATS.reduce((s, k) => s + byCat[k], 0);
  const car = n(carcass);
  return { total, byCat, meatPct: car > 0 ? (byCat.Daging / car) * 100 : null, over: car > 0 && total > car + 1e-9 };
}

export type CwItemInput = { name: string; cat: string; weight: string };
export type CwItemsResult = { ok: true; items: { name: string; cat: CwCat; weight: number }[] } | { ok: false; error: string };

/** Baris kosong dilewati; baris terisi sebagian ditolak. Nama dibandingkan tanpa melihat huruf besar/kecil. */
export function cleanCwItems(rows: CwItemInput[], parseQty: (raw: string) => number | null | "invalid"): CwItemsResult {
  const out: { name: string; cat: CwCat; weight: number }[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < rows.length; i++) {
    const name = String(rows[i].name ?? "").replace(/\s+/g, " ").trim();
    const raw = String(rows[i].weight ?? "").trim();
    if (name === "" && raw === "") continue;
    const where = `Item baris ${i + 1}: `;
    if (name === "") return { ok: false, error: `${where}nama item wajib diisi.` };
    if (name.length > 100) return { ok: false, error: `${where}nama item terlalu panjang (maksimal 100 huruf).` };
    const cat = CW_CATS.find((k) => k === rows[i].cat);
    if (!cat) return { ok: false, error: `${where}pilih kategori.` };
    const w = parseQty(raw);
    if (w === null) return { ok: false, error: `${where}berat wajib diisi.` };
    if (w === "invalid") return { ok: false, error: `${where}berat harus berupa angka (contoh 12,5), maksimal 3 angka di belakang koma.` };
    if (w <= 0) return { ok: false, error: `${where}berat harus lebih dari 0.` };
    const key = name.toLowerCase();
    if (seen.has(key)) return { ok: false, error: `${where}item "${name}" sudah ada di baris lain. Gabungkan beratnya jadi satu baris.` };
    seen.add(key);
    out.push({ name, cat, weight: w });
  }
  if (out.length === 0) return { ok: false, error: "Isi minimal satu item hasil potong." };
  return { ok: true, items: out };
}

const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
/** Pratinjau nomor: CW-urut-KODE SAPI-BULAN ROMAWI-TAHUN. Urutan resmi diberikan database saat disimpan. */
export function cwNumberPreview(seq: string, cow: string, date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return "";
  const code = cow.toUpperCase().replace(/[^A-Z0-9]/g, "") || "KODE";
  return `CW-${seq || "NNN"}-${code}-${ROMAN[Number(date.slice(5, 7)) - 1]}-${date.slice(2, 4)}`;
}
