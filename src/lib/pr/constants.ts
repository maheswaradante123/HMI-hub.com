export type PrStatus =
  | "DRAFT" | "SUBMITTED" | "UNDER_REVIEW" | "APPROVED" | "REJECTED"
  | "ORDERED" | "RECEIVED" | "PAID" | "CLOSED";

export const STATUS_LABEL: Record<PrStatus, string> = {
  DRAFT: "Draf",
  SUBMITTED: "Diajukan",
  UNDER_REVIEW: "Sedang ditinjau",
  APPROVED: "Disetujui",
  REJECTED: "Ditolak",
  ORDERED: "Sudah dipesan",
  RECEIVED: "Barang diterima",
  PAID: "Sudah dibayar",
  CLOSED: "Selesai",
};

export const STATUS_STYLE: Record<PrStatus, string> = {
  DRAFT: "bg-neutral-200 text-neutral-800",
  SUBMITTED: "bg-amber-100 text-amber-900",
  UNDER_REVIEW: "bg-amber-100 text-amber-900",
  APPROVED: "bg-green-100 text-green-900",
  REJECTED: "bg-red-100 text-red-900",
  ORDERED: "bg-blue-100 text-blue-900",
  RECEIVED: "bg-blue-100 text-blue-900",
  PAID: "bg-emerald-200 text-emerald-950",
  CLOSED: "bg-emerald-200 text-emerald-950",
};

export const PRIORITY_LABEL: Record<string, string> = {
  LOW: "Rendah",
  NORMAL: "Normal",
  HIGH: "Tinggi",
};

export const rupiah = (n: number) =>
  new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 0 }).format(n);

export const dateId = (d: string | Date) =>
  new Date(d).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Jakarta" });

export const dateTimeId = (d: string | Date) =>
  new Date(d).toLocaleString("id-ID", {
    day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Asia/Jakarta",
  });
