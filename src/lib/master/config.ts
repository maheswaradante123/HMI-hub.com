// Definisi semua master data. Satu pola layar dipakai untuk semuanya.
// Berisi data biasa saja, supaya aman dikirim ke komponen client.

export type Option = { value: string; label: string };

export type Field = {
  name: string;
  label: string;
  type: "text" | "textarea" | "number" | "select" | "ref";
  required?: boolean;
  upper?: boolean; // diubah ke huruf besar
  options?: Option[]; // untuk type "select"
  ref?: string; // nama tabel, untuk type "ref"
  help?: string;
  integer?: boolean;
  step?: string;
  fixedOnEdit?: boolean; // tidak boleh diubah setelah dibuat
};

export type Resource = {
  key: string; // dipakai di alamat: /data/<key>
  table: string;
  label: string; // judul halaman
  singular: string;
  module: string; // modul izin
  columns: string[]; // kolom di daftar
  fields: Field[];
  group: "utama" | "lain";
};

const code = (help = "Huruf besar tanpa spasi, mis. KG"): Field => ({
  name: "code",
  label: "Kode",
  type: "text",
  required: true,
  upper: true,
  help,
});
const name = (label = "Nama"): Field => ({ name: "name", label, type: "text", required: true });

const simple = (
  key: string,
  table: string,
  label: string,
  singular: string,
  codeHelp?: string,
): Resource => ({
  key,
  table,
  label,
  singular,
  module: "master_data",
  columns: ["code", "name"],
  fields: [code(codeHelp), name()],
  group: "lain",
});

export const RESOURCES: Record<string, Resource> = {
  produk: {
    key: "produk",
    table: "products",
    label: "Produk",
    singular: "Produk",
    module: "product",
    group: "utama",
    columns: ["code", "name", "product_type", "category_id", "unit_id", "min_stock"],
    fields: [
      code("Huruf besar tanpa spasi, mis. MF-TOPSIDE"),
      name("Nama produk"),
      {
        name: "product_type",
        label: "Jenis produk",
        type: "select",
        required: true,
        options: [
          { value: "MANUFACTURE", label: "Manufacture (hasil potong sendiri)" },
          { value: "RESELLER", label: "Reseller (dibeli lalu dijual lagi)" },
          { value: "SUPPORTING", label: "Supporting (barang penunjang)" },
        ],
      },
      { name: "category_id", label: "Kategori", type: "ref", ref: "product_categories" },
      { name: "unit_id", label: "Satuan", type: "ref", ref: "units", required: true },
      {
        name: "min_stock",
        label: "Batas stok minimum",
        type: "number",
        step: "0.001",
        help: "Jika stok di bawah angka ini, produk akan ditandai menipis. Isi 0 bila tidak dipakai.",
      },
      { name: "notes", label: "Catatan", type: "textarea" },
    ],
  },
  customer: {
    key: "customer",
    table: "customers",
    label: "Customer",
    singular: "Customer",
    module: "customer",
    group: "utama",
    columns: ["code", "name", "type", "phone", "payment_term_days"],
    fields: [
      code("Huruf besar tanpa spasi, mis. HOTEL-A"),
      name("Nama customer"),
      {
        name: "type",
        label: "Jenis customer",
        type: "select",
        required: true,
        options: [
          { value: "HOREKA", label: "Horeka (hotel, restoran, katering)" },
          { value: "NON_CARCASS_BUYER", label: "Pembeli non-karkas" },
          { value: "OTHER", label: "Lainnya" },
        ],
      },
      { name: "address", label: "Alamat", type: "textarea" },
      { name: "contact_name", label: "Nama kontak", type: "text" },
      { name: "phone", label: "Telepon", type: "text" },
      {
        name: "payment_term_days",
        label: "Jangka waktu bayar (hari)",
        type: "number",
        integer: true,
        step: "1",
        help: "Jumlah hari dari tanggal invoice sampai jatuh tempo. Isi 0 untuk bayar langsung.",
      },
    ],
  },
  supplier: {
    key: "supplier",
    table: "suppliers",
    label: "Supplier",
    singular: "Supplier",
    module: "supplier",
    group: "utama",
    columns: ["code", "name", "type", "phone"],
    fields: [
      code("Huruf besar tanpa spasi, mis. SUP-SAPI-A"),
      name("Nama supplier"),
      {
        name: "type",
        label: "Jenis supplier",
        type: "select",
        required: true,
        options: [
          { value: "COW", label: "Sapi" },
          { value: "RESELLER", label: "Barang reseller" },
          { value: "SUPPORTING", label: "Barang penunjang" },
          { value: "OTHER", label: "Lainnya" },
        ],
      },
      { name: "address", label: "Alamat", type: "textarea" },
      { name: "contact_name", label: "Nama kontak", type: "text" },
      { name: "phone", label: "Telepon", type: "text" },
      { name: "bank_info", label: "Info rekening", type: "textarea", help: "Bank, nomor rekening, atas nama." },
    ],
  },
  kategori: simple("kategori", "product_categories", "Kategori Produk", "Kategori", "mis. DAGING"),
  satuan: simple("satuan", "units", "Satuan", "Satuan", "mis. KG"),
  "jenis-sapi": simple("jenis-sapi", "cow_types", "Jenis Sapi", "Jenis sapi", "mis. BX"),
  "jenis-non-karkas": simple(
    "jenis-non-karkas",
    "non_carcass_types",
    "Jenis Non-Karkas",
    "Jenis non-karkas",
    "mis. BUNTUT",
  ),
  "jenis-biaya": simple("jenis-biaya", "cost_types", "Jenis Biaya Operasional", "Jenis biaya", "mis. TRANSPORT"),
  "metode-bayar": simple("metode-bayar", "payment_methods", "Metode Pembayaran", "Metode pembayaran", "mis. TRANSFER"),
  gudang: simple("gudang", "warehouses", "Gudang", "Gudang", "mis. GD-TOKO"),
  lokasi: {
    key: "lokasi",
    table: "locations",
    label: "Lokasi",
    singular: "Lokasi",
    module: "master_data",
    group: "lain",
    columns: ["code", "name", "warehouse_id"],
    fields: [
      code("mis. CHILLER"),
      name(),
      { name: "warehouse_id", label: "Gudang", type: "ref", ref: "warehouses" },
    ],
  },
  rekening: {
    key: "rekening",
    table: "accounts",
    label: "Rekening / Kas",
    singular: "Rekening atau kas",
    module: "master_data",
    group: "lain",
    columns: ["code", "name", "type", "account_ref"],
    fields: [
      code("mis. KAS-TOKO"),
      name(),
      {
        name: "type",
        label: "Jenis",
        type: "select",
        required: true,
        options: [
          { value: "BANK", label: "Rekening bank" },
          { value: "CASH", label: "Kas tunai" },
        ],
      },
      { name: "account_ref", label: "Keterangan rekening", type: "text", help: "Mis. nama bank dan empat angka terakhir." },
    ],
  },
};

export const COLUMN_LABELS: Record<string, string> = {
  code: "Kode",
  name: "Nama",
  product_type: "Jenis",
  category_id: "Kategori",
  unit_id: "Satuan",
  min_stock: "Stok minimum",
  type: "Jenis",
  phone: "Telepon",
  payment_term_days: "Bayar (hari)",
  warehouse_id: "Gudang",
  account_ref: "Keterangan",
};

export const LOOKUP_RESOURCES = Object.values(RESOURCES).filter((r) => r.group === "lain");
