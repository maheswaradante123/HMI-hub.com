// Tampilan Stok: saldo berjalan pada riwayat mutasi dan urutan baris Asal Sapi. Murni data, aman di server maupun klien.
export type LedgerRow = { movement_date: string; created_at: string; id: string; qty: number };

/** Saldo sebelum dan sesudah tiap mutasi (urut tanggal lalu waktu catat), dikembalikan dari yang terbaru. `start` = saldo sebelum mutasi paling awal yang dimuat. */
export function withBalances<T extends LedgerRow>(moves: T[], start = 0): (T & { before: number; after: number })[] {
  const asc = [...moves].sort((a, b) => a.movement_date.localeCompare(b.movement_date) || a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
  let bal = start;
  const out = asc.map((m) => {
    const before = bal;
    bal = Math.round((bal + Number(m.qty)) * 1000) / 1000;
    return { ...m, before, after: bal };
  });
  return out.reverse();
}

export type LotRow = { lot: string | null; first_in: string | null; qty_in: number; qty_out: number; qty_rest: number };

/** Sapi yang masih punya sisa di atas, lalu yang sudah habis; di tiap kelompok yang masuk lebih dulu lebih dulu. Baris tanpa kode sapi di bawah. */
export function sortLots<T extends LotRow>(rows: T[]): T[] {
  const rank = (r: T) => (r.lot === null ? 2 : r.qty_rest > 1e-9 ? 0 : 1);
  return [...rows].sort((a, b) => rank(a) - rank(b) || (a.first_in ?? "9999").localeCompare(b.first_in ?? "9999") || String(a.lot).localeCompare(String(b.lot)));
}

/** Item yang habis di bawah, selebihnya urut nama. */
export const emptyLast = <T extends { qty: number; name: string }>(rows: T[]): T[] =>
  [...rows].sort((a, b) => Number(a.qty <= 1e-9) - Number(b.qty <= 1e-9) || a.name.localeCompare(b.name, "id"));
