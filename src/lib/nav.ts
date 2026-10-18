// Menu sidebar. Setiap menu terikat ke satu modul izin; menu hanya tampil
// jika user punya izin "view" pada modul tersebut.
export type NavItem = { slug: string; label: string; module: string; href?: string };
export type NavGroup = { title: string; items: NavItem[] };

export const NAV: NavGroup[] = [
  {
    title: "Operasional",
    items: [
      { slug: "ro", label: "Order / RO", module: "ro", href: "/d/ro" },
      { slug: "production-order", label: "Production Order", module: "production_order", href: "/d/prod" },
      { slug: "packing-list", label: "Packing List", module: "packing_list", href: "/d/pl" },
      { slug: "delivery-order", label: "Delivery Order", module: "delivery_order", href: "/d/do" },
      { slug: "stok", label: "Stok", module: "stock", href: "/stok" },
      { slug: "stock-opname", label: "Stock Opname", module: "stock_opname", href: "/d/so" },
      { slug: "penimbangan-karkas", label: "Penimbangan Karkas", module: "carcass_weighing", href: "/d/cw" },
    ],
  },
  {
    title: "Purchasing",
    items: [
      { slug: "purchase-request", label: "Purchase Request", module: "purchase_request" },
      { slug: "supplier", label: "Supplier", module: "supplier", href: "/data/supplier" },
      { slug: "pricing-toko", label: "Pricing Toko", module: "pricing" },
      { slug: "analisa-pembelian", label: "Analisa Pembelian", module: "purchase_analysis", href: "/d/ap" },
    ],
  },
  {
    title: "Sales",
    items: [
      { slug: "customer", label: "Customer", module: "customer", href: "/data/customer" },
      { slug: "harga-customer", label: "Harga Horeka", module: "ro", href: "/harga-customer" },
      { slug: "penjualan-non-karkas", label: "Penjualan Non-Karkas", module: "noncarcass_sale", href: "/d/ncs" },
    ],
  },
  {
    title: "Accounting",
    items: [
      { slug: "invoice", label: "Invoice", module: "invoice", href: "/d/inv" },
      { slug: "crj", label: "CRJ (Penerimaan)", module: "crj", href: "/d/crj" },
      { slug: "pemasukan-toko", label: "Pemasukan Toko", module: "store_income", href: "/d/pmt" },
      { slug: "jcp", label: "Cash Payment Journal", module: "cpj_journal", href: "/d/jcp" },
      { slug: "cpj", label: "Bayar per PR (CPJ lama)", module: "cpj", href: "/d/cpj" },
      { slug: "gaji", label: "Gaji", module: "salary", href: "/d/sal" },
    ],
  },
  {
    title: "Qurban Cerdas",
    items: [
      { slug: "qurban-pesanan", label: "Master Pesanan", module: "qurban", href: "/qurban" },
      { slug: "qurban-proforma", label: "Proforma", module: "qurban", href: "/qurban/proforma" },
      { slug: "qurban-invoice", label: "Invoice dan Tagihan", module: "qurban", href: "/qurban/invoice" },
      { slug: "qurban-qc", label: "QC Report", module: "qc_report", href: "/qurban/qc" },
      { slug: "qurban-sp", label: "Surat Perjanjian", module: "qurban", href: "/qurban/sp" },
      { slug: "qurban-pilihan", label: "Pilihan Pemilik", module: "qurban", href: "/qurban/pilihan" },
    ],
  },
  {
    title: "Master Data",
    items: [
      { slug: "produk", label: "Produk", module: "product", href: "/data/produk" },
      { slug: "master-data", label: "Data Master Lain", module: "master_data", href: "/data" },
      { slug: "pengaturan-pajak", label: "Pengaturan Pajak", module: "master_data", href: "/pengaturan-pajak" },
    ],
  },
  {
    title: "Laporan",
    items: [{ slug: "laporan", label: "Laporan", module: "report", href: "/laporan" }],
  },
  {
    title: "Admin",
    items: [
      { slug: "user", label: "User", module: "user", href: "/user" },
      { slug: "role", label: "Hak Akses", module: "role", href: "/role" },
      { slug: "audit-log", label: "Audit Log", module: "audit_log", href: "/audit-log" },
    ],
  },
];

export const ALL_ITEMS = NAV.flatMap((g) => g.items);
