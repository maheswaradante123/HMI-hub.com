// Perhitungan Analisa Pembelian (dipakai form, halaman detail, dan unduhan). Database menghitung hal yang sama di v_purchase_analysis.
export const AP_UNIT = "Kg";
export const AP_COST_UNIT = "Lamsam"; // tulisan satuan pada contoh ANALISA_PEMBELIAN

const n = (v: unknown) => { const x = Number(v); return Number.isFinite(x) ? x : 0; };

export type ApInput = {
  items: { qty: number; price: number; meat: boolean }[];        // hasil potongan dan harga jual per Kg
  nonk: { qty: number | null; price: number }[];                  // penjualan non-karkas
  costs: number[];                                                // biaya operasional
  cowPrice: number;                                               // harga sapi
  manualTotal: number | null;                                     // Total Biaya diisi manual (kosong = otomatis)
  carcass: number;                                                // total berat karkas semua sapi
  lower?: number | null;
  upper?: number | null;
};
export type ApResult = {
  sell: number; non: number; all: number; ops: number; totalCost: number; profit: number;
  meat: number; carcass: number; meatPct: number | null; hargaKarkas: number | null;
  lowerRatio: number | null; upperRatio: number | null;
};

export function apTotals(i: ApInput): ApResult {
  const sell = i.items.reduce((s, r) => s + n(r.qty) * n(r.price), 0);
  const non = i.nonk.reduce((s, r) => s + n(r.qty) * n(r.price), 0);
  const ops = i.costs.reduce((s, c) => s + n(c), 0);
  const totalCost = i.manualTotal !== null ? n(i.manualTotal) : n(i.cowPrice) + ops;
  const meat = i.items.reduce((s, r) => s + (r.meat ? n(r.qty) : 0), 0);
  const car = n(i.carcass);
  return {
    sell, non, all: sell + non, ops, totalCost, profit: sell + non - totalCost, meat, carcass: car,
    meatPct: car > 0 ? (meat / car) * 100 : null,
    hargaKarkas: car > 0 ? n(i.cowPrice) / car : null,
    lowerRatio: i.lower != null && meat > 0 ? n(i.lower) / meat : null,
    upperRatio: i.upper != null && meat > 0 ? n(i.upper) / meat : null,
  };
}

const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"];
const code = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");
/** Pratinjau nomor: urut-SUPPLIER-JENIS-BULAN ROMAWI-TAHUN. Urutan resmi diberikan database saat disimpan. */
export function apNumberPreview(seq: number | null, supplier: string, cowType: string, date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return "";
  const s = seq === null ? "NNN" : String(seq).padStart(3, "0");
  return `${s}-${code(supplier) || "SUPPLIER"}-${code(cowType) || "SAPI"}-${ROMAN[Number(date.slice(5, 7)) - 1]}-${date.slice(2, 4)}`;
}

// ---- Pilihan form (bentuk data dari ap-lists.ts) dan penarikan jumlah dari penimbangan karkas ----
export type ApCow = {
  id: string; cow_number: string; doc_number: string; live: number; carcass: number;
  supplier_id: string; cow_type_id: string; items: { product_id: string; weight: number }[];
};
export type ApProduct = { id: string; code: string; name: string; meat: boolean; price: number | null };
export type ApItemRow = { product_id: string; weight: string; unit_price: string; price_source: string; linked: boolean };

const fmtIn = (v: number) => v.toLocaleString("id-ID");
const fmtQ = (v: number) => String(Math.round(v * 1000) / 1000).replace(".", ",");

/** Jumlah item = penjumlahan hasil potongan sapi yang dipilih. Harga yang sudah diketik dipertahankan; harga awal dari Pricing Toko. */
export function syncApItems(cowIds: string[], cows: ApCow[], products: ApProduct[], prev: ApItemRow[]): ApItemRow[] {
  const agg = new Map<string, number>();
  for (const id of cowIds) for (const it of cows.find((c) => c.id === id)?.items ?? []) agg.set(it.product_id, Math.round(((agg.get(it.product_id) ?? 0) + it.weight) * 1000) / 1000);
  const old = new Map(prev.map((r) => [r.product_id, r]));
  const linked = [...agg.entries()].map(([pid, w]) => {
    const o = old.get(pid);
    const p = products.find((x) => x.id === pid)?.price ?? null;
    return { product_id: pid, weight: fmtQ(w), unit_price: o?.unit_price ?? (p !== null ? fmtIn(p) : ""), price_source: o?.price_source ?? (p !== null ? "PRICING" : "TYPED"), linked: true };
  });
  return [...linked, ...prev.filter((r) => !r.linked && !agg.has(r.product_id))];
}
