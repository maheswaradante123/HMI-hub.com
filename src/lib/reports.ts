import { getPath } from "./docs/format.ts";

export type ReportCol = { h: string; path: string; kind?: "num" | "text" | "bool" };
export type Report = {
  key: string; label: string; desc: string; module: string; needs?: [string, string];
  table: string; select: string; order: string; dateCol?: string;
  filter?: { column: string; op: "eq" | "neq" | "in"; value: string | string[] };
  cols: ReportCol[];
};

const t = (h: string, path: string): ReportCol => ({ h, path });
const n = (h: string, path: string): ReportCol => ({ h, path, kind: "num" });

export const REPORTS: Report[] = [
  { key: "stok", label: "Stok per item", desc: "Saldo stok setiap produk dan tanda menipis.", module: "stock", table: "v_stock_summary", select: "code, name, qty, min_stock, is_low", order: "name",
    cols: [t("Kode", "code"), t("Produk", "name"), n("Stok", "qty"), n("Minimum", "min_stock"), { h: "Menipis", path: "is_low", kind: "bool" }] },
  { key: "nilai-stok", label: "Nilai stok", desc: "Stok dikali harga beli terakhir. Hanya untuk pemegang izin harga beli.", module: "stock", needs: ["pricing_cost", "view"], table: "v_stock_value", select: "code, name, qty, last_cost, value", order: "name",
    cols: [t("Kode", "code"), t("Produk", "name"), n("Stok", "qty"), n("Harga beli terakhir", "last_cost"), n("Nilai", "value")] },
  { key: "mutasi-stok", label: "Mutasi stok", desc: "Semua pergerakan stok pada rentang tanggal.", module: "stock", table: "stock_movements", select: "movement_date, movement_type, qty, note, products(code, name), warehouses(name)", order: "movement_date", dateCol: "movement_date",
    cols: [t("Tanggal", "movement_date"), t("Kode", "products.code"), t("Produk", "products.name"), t("Gudang", "warehouses.name"), t("Jenis", "movement_type"), n("Jumlah", "qty"), t("Catatan", "note")] },
  { key: "penjualan", label: "Penjualan (invoice)", desc: "Daftar invoice, tidak termasuk yang dibatalkan.", module: "invoice", table: "invoices", select: "doc_number, invoice_date, due_date, status, subtotal, tax_amount, total, paid_amount, customers(name)", order: "invoice_date", dateCol: "invoice_date",
    filter: { column: "status", op: "neq", value: "VOID" },
    cols: [t("Nomor", "doc_number"), t("Tanggal", "invoice_date"), t("Customer", "customers.name"), t("Jatuh tempo", "due_date"), t("Status", "status"), n("Subtotal", "subtotal"), n("Pajak", "tax_amount"), n("Total", "total"), n("Terbayar", "paid_amount")] },
  { key: "piutang", label: "Piutang berjalan", desc: "Invoice terbit yang belum lunas.", module: "invoice", table: "invoices", select: "doc_number, invoice_date, due_date, status, total, paid_amount, customers(name)", order: "due_date",
    filter: { column: "status", op: "in", value: ["ISSUED", "PARTIAL"] },
    cols: [t("Nomor", "doc_number"), t("Customer", "customers.name"), t("Tanggal", "invoice_date"), t("Jatuh tempo", "due_date"), n("Total", "total"), n("Terbayar", "paid_amount")] },
  { key: "kas-masuk", label: "Kas masuk (CRJ)", desc: "Penerimaan yang sudah diposting.", module: "crj", table: "cash_receipts", select: "doc_number, receipt_date, amount, reference, customers(name), accounts(name), payment_methods(name)", order: "receipt_date", dateCol: "receipt_date",
    filter: { column: "status", op: "eq", value: "POSTED" },
    cols: [t("Nomor", "doc_number"), t("Tanggal", "receipt_date"), t("Customer", "customers.name"), t("Rekening/Kas", "accounts.name"), t("Metode", "payment_methods.name"), n("Jumlah", "amount"), t("Referensi", "reference")] },
  { key: "kas-keluar", label: "Kas keluar (CPJ)", desc: "Pengeluaran yang sudah diposting, tanpa gaji.", module: "cpj", table: "cash_payments", select: "doc_number, pay_date, amount, reference, cost_types(name), suppliers(name), accounts(name), payment_methods(name)", order: "pay_date", dateCol: "pay_date",
    filter: { column: "status", op: "eq", value: "POSTED" },
    cols: [t("Nomor", "doc_number"), t("Tanggal", "pay_date"), t("Jenis biaya", "cost_types.name"), t("Supplier", "suppliers.name"), t("Rekening/Kas", "accounts.name"), t("Metode", "payment_methods.name"), n("Jumlah", "amount"), t("Referensi", "reference")] },
  { key: "analisa", label: "Analisa pembelian", desc: "Ringkasan analisa per sapi.", module: "purchase_analysis", table: "v_purchase_analysis", select: "doc_number, analysis_date, cow_number, live_weight, carcass_weight, carcass_pct, meat_weight, meat_pct, total_purchase, carcass_price_per_kg, revenue, noncarcass_amount, cost_total, profit, status", order: "analysis_date", dateCol: "analysis_date",
    cols: [t("Nomor", "doc_number"), t("Tanggal", "analysis_date"), t("No. sapi", "cow_number"), n("Berat hidup", "live_weight"), n("Berat karkas", "carcass_weight"), n("Karkas %", "carcass_pct"), n("Berat daging", "meat_weight"), n("Daging %", "meat_pct"), n("Total pembelian", "total_purchase"), n("Harga karkas/kg", "carcass_price_per_kg"), n("Hasil penjualan", "revenue"), n("Non-karkas", "noncarcass_amount"), n("Biaya", "cost_total"), n("Laba", "profit"), t("Status", "status")] },
];

// Sel yang diawali = + - @ bisa dibaca sebagai rumus oleh Excel; diberi tanda petik agar tampil sebagai teks.
export function csvCell(v: unknown, kind?: ReportCol["kind"]): string {
  if (v === null || v === undefined) return "";
  if (kind === "bool") return v ? "Ya" : "Tidak";
  let s = String(v);
  if (kind !== "num" && /^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\n\r;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function toCsv(rows: unknown[], cols: ReportCol[]): string {
  const head = cols.map((c) => csvCell(c.h)).join(",");
  const body = rows.map((r) => cols.map((c) => csvCell(getPath(r, c.path), c.kind)).join(","));
  return "﻿" + [head, ...body].join("\r\n") + "\r\n";
}
