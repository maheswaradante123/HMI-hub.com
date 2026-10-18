// Purchase Request per barang: status, A/C, kode biaya, dan pilihan Pembelian (sesuai lembar PR mingguan).
export type LineStatus = "DRAFT" | "SUBMITTED" | "APPROVED" | "REJECTED" | "ORDERED" | "RECEIVED" | "CLOSED" | "CANCELLED";

export const LINE_STATUSES: LineStatus[] = ["DRAFT", "SUBMITTED", "APPROVED", "REJECTED", "ORDERED", "RECEIVED", "CLOSED", "CANCELLED"];
export const LINE_LABEL: Record<LineStatus, string> = {
  DRAFT: "Draft", SUBMITTED: "Diajukan", APPROVED: "Approved", REJECTED: "Ditolak", ORDERED: "Order", RECEIVED: "Received", CLOSED: "Closed", CANCELLED: "Cancel",
};
export const LINE_STYLE: Record<LineStatus, string> = {
  DRAFT: "bg-red-700 text-red-100",
  SUBMITTED: "bg-amber-100 text-amber-900",
  APPROVED: "bg-red-100 text-red-800",
  REJECTED: "bg-red-900 text-red-100",
  ORDERED: "bg-emerald-700 text-emerald-50",
  RECEIVED: "bg-yellow-200 text-yellow-950",
  CLOSED: "bg-purple-800 text-purple-100",
  CANCELLED: "bg-neutral-700 text-neutral-100",
};
/** Barang yang sudah tidak berjalan (tidak dijumlahkan di Total). */
export const isDead = (s: string) => s === "CANCELLED" || s === "REJECTED";

export const PR_AC = [
  { value: "OPR", label: "OPR — Operasional (Kandang)" },
  { value: "RT", label: "RT — Rumah Tangga / Kantor / GA" },
  { value: "MKT", label: "MKT — Marketing" },
  { value: "TOKO", label: "TOKO — Toko Daging" },
] as const;
export const PR_AC_VALUES: string[] = PR_AC.map((a) => a.value);
export const PR_CODES = ["BP", "BO", "BU", "BA", "BM", "BJ", "ASET"];
export const PR_PAY = ["tf", "cash", "keranjang", "KOPRA", "offline"];
/** A/C awal sesuai nama peran pemohon (dapat diganti di form). */
export const defaultAc = (roleName: string) => (/marketing/i.test(roleName) ? "MKT" : /kasir|produksi/i.test(roleName) ? "TOKO" : "OPR");

/** Aksi pindah status yang tersedia untuk barang terpilih. */
export const MOVE_FROM: Record<string, LineStatus[]> = {
  SUBMITTED: ["DRAFT"], APPROVED: ["SUBMITTED"], REJECTED: ["SUBMITTED"], ORDERED: ["APPROVED"], RECEIVED: ["APPROVED", "ORDERED"],
  CANCELLED: ["DRAFT", "SUBMITTED", "APPROVED", "ORDERED", "RECEIVED", "REJECTED"],
};
export const MOVE_LABEL: Record<string, string> = {
  SUBMITTED: "Ajukan ke Owner", APPROVED: "Setujui", REJECTED: "Tolak", ORDERED: "Tandai Order", RECEIVED: "Tandai Diterima", CANCELLED: "Batalkan",
};

const MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
/** Minggu ke-n dalam bulan (minggu pertama mulai tanggal 1, awal minggu Senin) — sama dengan cpj_week_of di database. */
export function weekOfMonth(iso: string): number {
  const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
  const dow = new Date(Date.UTC(y, m - 1, 1)).getUTCDay();
  return Math.floor((d - 1 + ((dow + 6) % 7)) / 7) + 1;
}
export const weekLabel = (iso: string) => `Minggu ke-${weekOfMonth(iso)} ${MONTHS[Number(iso.slice(5, 7)) - 1]} ${iso.slice(0, 4)}`;
