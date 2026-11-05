// CRJ rekap per periode: sumber baris dan penjumlahan. Murni data, dipakai server dan klien.
export const CRJ_SOURCES = [
  { value: "QURBAN_CLOSING", label: "Closing lunas Qurban Cerdas", short: "Closing Qurban" },
  { value: "QURBAN_CARE", label: "Pemeliharaan Qurban Cerdas", short: "Pemeliharaan Qurban" },
  { value: "QRIS", label: "QRIS toko", short: "QRIS toko" },
  { value: "DEBIT", label: "Debit toko", short: "Debit toko" },
  { value: "TF", label: "Transfer ke rekening HMI (toko)", short: "Transfer toko" },
  { value: "CASH_DEPOSIT", label: "Penyetoran cash toko", short: "Setoran cash" },
  { value: "HOREKA", label: "Tempo Horeka (invoice)", short: "Tempo Horeka" },
  { value: "NONKARKAS", label: "Penjualan non-karkas", short: "Non-karkas" },
  { value: "OTHER", label: "Lainnya", short: "Lainnya" },
] as const;
export type CrjSource = (typeof CRJ_SOURCES)[number]["value"];
export const CRJ_SOURCE_LABEL: Record<string, string> = Object.fromEntries(CRJ_SOURCES.map((s) => [s.value, s.label]));
// Sumber yang bisa ditarik otomatis (OTHER diketik manual).
export const CRJ_PULLABLE = CRJ_SOURCES.filter((s) => s.value !== "OTHER");

export type CrjPullRow = { source: string; ref_id: string; src_ref: string; trans_date: string; description: string; amount: number; account_id: string };

/** Senin dan Minggu pada minggu tanggal ini (format YYYY-MM-DD). */
export function weekRange(iso: string): { from: string; to: string } {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const back = (dt.getUTCDay() + 6) % 7;
  const mon = new Date(dt.getTime() - back * 86400000);
  const sun = new Date(mon.getTime() + 6 * 86400000);
  const f = (x: Date) => x.toISOString().slice(0, 10);
  return { from: f(mon), to: f(sun) };
}

/** Jumlah per kunci (sumber atau rekening). */
export function sumBy<T>(rows: T[], key: (r: T) => string, amount: (r: T) => number): [string, number][] {
  const m = new Map<string, number>();
  for (const r of rows) m.set(key(r), (m.get(key(r)) ?? 0) + amount(r));
  return [...m.entries()];
}
