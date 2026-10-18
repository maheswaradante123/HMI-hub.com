// Cash Payment Journal (CPJ mingguan): jenis baris, warna cetak, dan penjumlahan ringkasan.
// Semua rumus hanya penjumlahan per jenis baris (sesuai catatan Owner: rumus Excel hanya SUM).
export const JCP_FLAGS = [
  { value: "NONE", label: "Normal" },
  { value: "NON_CPJ", label: "Terbayarkan oleh non rekening CPJ" },
  { value: "OVER", label: "Over Budget CPJ Sebelumnya" },
  { value: "REJECTED", label: "Permintaan ditolak" },
  { value: "INCOMING", label: "Uang Masuk" },
] as const;
export type JcpFlag = (typeof JCP_FLAGS)[number]["value"];
// Warna latar baris di cetakan/Excel (hex tanpa #): kuning, oranye, merah, biru muda — sesuai legenda contoh.
export const JCP_FLAG_COLOR: Record<string, string | null> = { NONE: null, NON_CPJ: "FFFF00", OVER: "FF9900", REJECTED: "FF0000", INCOMING: "00FFFF" };
export const JCP_FLAG_BG: Record<string, string> = { NONE: "", NON_CPJ: "bg-yellow-200", OVER: "bg-orange-200", REJECTED: "bg-red-200", INCOMING: "bg-cyan-200" };
export const JCP_AC = ["OPR", "RT", "MKT", "GR", "TOKO"];
export const JCP_CODES = ["BP", "BO", "BU", "BA", "BL", "BM", "ASET", "P"];
export const JCP_DEFAULTS = {
  initiator_title: "Operator", approver_name: "Ahmad Hunain", approver_title: "Finance Director",
  pay_note: "Tf Mandiri 1290015674415 HARMONI MITRA INOVINDO",
};

export type JcpLineNum = { price: number; qty: number; flag: string; real_price?: number | null; real_qty?: number | null };
const n = (v: unknown) => (v === null || v === undefined || v === "" ? 0 : Number(v));
const has = (v: unknown) => v !== null && v !== undefined && v !== "";

export const planAmount = (l: JcpLineNum) => n(l.price) * n(l.qty);
/** Jumlah realisasi baris, atau null bila belum ada realisasi. `done`: jurnal sudah REALIZED (kolom kosong dianggap sama dengan rencana). */
export function realAmount(l: JcpLineNum, done: boolean): number | null {
  if (l.flag === "REJECTED" || l.flag === "INCOMING") return done ? 0 : null;
  if (!has(l.real_price) && !has(l.real_qty)) return done ? planAmount(l) : null;
  return (has(l.real_price) ? n(l.real_price) : n(l.price)) * (has(l.real_qty) ? n(l.real_qty) : n(l.qty));
}

export type JcpTotals = { requested: number; approved: number; cashIn: number; mustPay: number; toSpend: number; spent: number; remaining: number };
export function jcpTotals(lines: JcpLineNum[], done = false): JcpTotals {
  const t = { requested: 0, approved: 0, cashIn: 0, mustPay: 0, toSpend: 0, spent: 0, remaining: 0 };
  for (const l of lines) {
    const p = planAmount(l);
    if (l.flag === "INCOMING") { t.cashIn += p; continue; }
    t.requested += p;
    if (l.flag === "REJECTED") continue;
    t.approved += p;
    if (l.flag === "NON_CPJ") continue;
    t.mustPay += p;
    const r = realAmount(l, done);
    if (r === null) t.toSpend += p; else t.spent += r;
  }
  t.remaining = t.cashIn - t.spent;
  return t;
}

// Cetak: nomor realisasi diberi awalan R- setelah direalisasi.
export const jcpPrintNumber = (docNumber: string, status: string) => (status === "REALIZED" ? `R-${docNumber}` : docNumber);

export const JCP_SUMMARY_LABELS: [keyof JcpTotals, string][] = [
  ["requested", "Total Permintaan"], ["approved", "Total Yang Disetujui"], ["cashIn", "Uang Saat ini"], ["mustPay", "Yang harus dibayarkan"],
  ["toSpend", "Yang perlu dibelanjakan"], ["spent", "Realisasi Uang Keluar"], ["remaining", "Sisa Uang"],
];
