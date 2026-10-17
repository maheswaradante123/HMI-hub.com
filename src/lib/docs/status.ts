export const DOC_STATUS_LABEL: Record<string, string> = {
  DRAFT: "Draf", CONFIRMED: "Dikonfirmasi", COMPLETED: "Selesai", CANCELLED: "Dibatalkan",
  SUBMITTED: "Diajukan", APPROVED: "Disetujui", REJECTED: "Ditolak", DONE: "Selesai",
  PACKED: "Sudah dikemas", DELIVERED: "Terkirim", FINAL: "Final", VOID: "Dibatalkan",
  ISSUED: "Terbit", PARTIAL: "Dibayar sebagian", PAID: "Lunas", POSTED: "Terposting",
};

export const DOC_STATUS_STYLE: Record<string, string> = {
  DRAFT: "bg-neutral-200 text-neutral-800",
  SUBMITTED: "bg-amber-100 text-amber-900",
  CONFIRMED: "bg-blue-100 text-blue-900",
  PACKED: "bg-blue-100 text-blue-900",
  ISSUED: "bg-blue-100 text-blue-900",
  PARTIAL: "bg-amber-100 text-amber-900",
  APPROVED: "bg-green-100 text-green-900",
  FINAL: "bg-green-100 text-green-900",
  POSTED: "bg-green-100 text-green-900",
  DELIVERED: "bg-emerald-200 text-emerald-950",
  COMPLETED: "bg-emerald-200 text-emerald-950",
  DONE: "bg-emerald-200 text-emerald-950",
  PAID: "bg-emerald-200 text-emerald-950",
  REJECTED: "bg-red-100 text-red-900",
  CANCELLED: "bg-neutral-300 text-neutral-700",
  VOID: "bg-neutral-300 text-neutral-700",
};
