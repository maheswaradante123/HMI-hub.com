import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { Field, RefName } from "./types";
import type { RefOption } from "@/lib/master/refs";
import { fmtRupiah, getPath } from "./format";

type Supa = Awaited<ReturnType<typeof createClient>>;
type Row = Record<string, unknown>;

type Spec = { table: string; select: string; label: (r: Row) => string; order: string; active?: boolean; docs?: boolean };

const name = (r: Row) => String(r.name);
const master = (table: string): Spec => ({ table, select: "id, name, is_active", label: name, order: "name", active: true });

export const REFS: Record<RefName, Spec> = {
  products: { table: "products", select: "id, code, name, is_active", label: (r) => `${r.code} - ${r.name}`, order: "name", active: true },
  customers: master("customers"), suppliers: master("suppliers"), warehouses: master("warehouses"),
  cow_types: master("cow_types"), non_carcass_types: master("non_carcass_types"), cost_types: master("cost_types"),
  payment_methods: master("payment_methods"), accounts: master("accounts"),
  request_orders: { table: "request_orders", select: "id, doc_number, status, customers(name)", label: (r) => `${r.doc_number} - ${getPath(r, "customers.name") ?? ""}`, order: "doc_number", docs: true },
  production_orders: { table: "production_orders", select: "id, doc_number, status", label: (r) => String(r.doc_number), order: "doc_number", docs: true },
  packing_lists: { table: "packing_lists", select: "id, doc_number, status, customers(name)", label: (r) => `${r.doc_number} - ${getPath(r, "customers.name") ?? ""}`, order: "doc_number", docs: true },
  carcass_weighings: { table: "carcass_weighings", select: "id, doc_number, status, cow_number", label: (r) => `${r.cow_number} (${r.doc_number})`, order: "doc_number", docs: true },
  invoices: { table: "invoices", select: "id, doc_number, status, total, paid_amount, customers(name)", label: (r) => `${r.doc_number} - ${getPath(r, "customers.name") ?? ""} - sisa ${fmtRupiah(Number(r.total) - Number(r.paid_amount))}`, order: "doc_number", docs: true },
  noncarcass_sales: { table: "noncarcass_sales", select: "id, doc_number, status, total_amount, paid_amount, customers(name)", label: (r) => `${r.doc_number} - ${getPath(r, "customers.name") ?? ""} - sisa ${fmtRupiah(Number(r.total_amount) - Number(r.paid_amount))}`, order: "doc_number", docs: true },
  purchase_requests: { table: "purchase_requests", select: "id, doc_number, status", label: (r) => String(r.doc_number), order: "doc_number", docs: true },
};

import { refKey as rk } from "./ref-key";
export const refKey = rk;

// Mengambil pilihan untuk semua field bertipe ref. Nilai yang sudah tersimpan tetap
// ikut ditampilkan walau statusnya sudah berubah.
export async function loadDocRefs(supabase: Supa, fields: Field[], keep: string[] = []): Promise<Record<string, RefOption[]>> {
  const out: Record<string, RefOption[]> = {};
  const wanted = new Map<string, Field>();
  for (const f of fields) if (f.kind === "ref" && f.ref) wanted.set(refKey(f), f);

  await Promise.all([...wanted.entries()].map(async ([key, f]) => {
    const spec = REFS[f.ref!];
    let q = supabase.from(spec.table).select(spec.select).order(spec.order, { ascending: spec.docs ? false : true }).limit(500);
    if (spec.docs) {
      q = q.is("deleted_at", null);
      if (f.refStatus?.length) q = q.in("status", f.refStatus);
    }
    const { data } = await q;
    const rows = (data ?? []) as unknown as Row[];
    const have = new Set(rows.map((r) => String(r.id)));
    const missing = keep.filter((id) => id && !have.has(id));
    let extra: Row[] = [];
    if (missing.length) {
      const { data: more } = await supabase.from(spec.table).select(spec.select).in("id", missing);
      extra = (more ?? []) as unknown as Row[];
    }
    out[key] = [...rows, ...extra].map((r) => ({
      value: String(r.id),
      label: spec.label(r),
      active: spec.active ? r.is_active !== false : true,
    }));
  }));
  return out;
}
