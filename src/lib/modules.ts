import { ALL_ITEMS } from "./nav";

// Nama modul untuk tampilan matriks izin.
export const MODULE_LABEL: Record<string, string> = {
  dashboard: "Dashboard", purchase_request_all: "Lihat semua PR (bukan hanya milik sendiri)",
  pricing_cost: "Harga beli dan supplier di Pricing", product: "Produk", master_data: "Data master lain",
  ...Object.fromEntries(ALL_ITEMS.map((i) => [i.module, i.label])),
};
export const ACTION_LABEL: Record<string, string> = {
  view: "Lihat", create: "Buat", edit: "Ubah", delete: "Hapus/Batal", approve: "Setujui", export: "Ekspor",
};
export const ACTIONS = ["view", "create", "edit", "delete", "approve", "export"] as const;
