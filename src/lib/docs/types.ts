// Definisi bentuk konfigurasi dokumen. Murni data, aman dipakai di server maupun klien.
export type RefName =
  | "products" | "customers" | "suppliers" | "warehouses" | "cow_types" | "non_carcass_types"
  | "cost_types" | "payment_methods" | "accounts" | "request_orders" | "production_orders"
  | "packing_lists" | "carcass_weighings" | "invoices" | "noncarcass_sales" | "purchase_requests";

export type Kind = "text" | "textarea" | "date" | "qty" | "money" | "smoney" | "select" | "ref";

export type Field = {
  name: string;
  label: string;
  kind: Kind;
  required?: boolean;
  ref?: RefName;
  refStatus?: string[];       // hanya tampilkan dokumen berstatus ini
  refWhere?: { column: string; value: string }; // hanya tampilkan master dengan kolom bernilai ini (mis. type pengepul)
  options?: { value: string; label: string }[];
  help?: string;
  today?: boolean;            // isi awal = hari ini (WIB)
  blankAs0?: boolean;         // kosong dianggap 0 (mis. harga otomatis)
  upper?: boolean;
};

export type ColKind = "text" | "date" | "money" | "qty" | "status" | "pct" | "datetime";
export type Col = { label: string; path: string; kind?: ColKind };

export type Child = {
  key: string;
  title: string;
  table: string;
  fk: string;
  select: string;             // kolom + relasi untuk tampilan detail
  fields: Field[];
  columns: Col[];
  required?: boolean;
  hint?: string;
  total?: { qty: string; price: string; label: string }; // total berjalan di form
  sum?: { field: string; label: string };
  exclusive?: [string, string]; // tepat satu dari dua kolom harus terisi
};

export type DocConfig = {
  type: string;               // jenis dokumen di doc_registry
  slug: string;
  module: string;
  title: string;
  singular: string;
  intro: string;
  table: string;
  select: string;
  columns: Col[];
  filter?: { column: string; op: "eq" | "neq"; value: string };
  header: Field[];
  summary: Col[];
  children: Child[];
  statuses: string[];
  prefill?: string[];         // parameter query yang didukung di /baru
  extra?: "analysis";
  listSelect?: string;        // select khusus halaman daftar (bila butuh relasi tambahan untuk kolom turunan)
  derive?: (row: Record<string, unknown>) => Record<string, unknown>; // kolom turunan untuk daftar (dibaca lewat path "_nama")
};
