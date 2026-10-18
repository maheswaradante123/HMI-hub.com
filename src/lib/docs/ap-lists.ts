import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { ApCow, ApProduct } from "./ap";

type Supa = Awaited<ReturnType<typeof createClient>>;

export type ApLists = {
  suppliers: { id: string; name: string }[];
  cowTypes: { id: string; code: string; name: string }[];
  cows: ApCow[];
  products: ApProduct[];
  nonkNames: string[];
  costTypes: { id: string; name: string }[];
  nextSeq: number | null;
  seqYear: string;
};

type Rel<T> = T | T[] | null;
const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

// Pilihan untuk form Analisa Pembelian: sapi yang sudah final dan belum dipakai analisa lain (ditambah sapi analisa ini sendiri).
export async function loadApLists(supabase: Supa, apId: string | null, today: string): Promise<ApLists> {
  const yy = today.slice(2, 4);
  const [sup, cow, cws, used, prod, price, non, cost, seq] = await Promise.all([
    supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
    supabase.from("cow_types").select("id, code, name").eq("is_active", true).order("code"),
    supabase.from("carcass_weighings").select("id, cow_number, doc_number, live_weight, carcass_weight, supplier_id, cow_type_id, cw_items(product_id, weight, line_no)")
      .eq("status", "FINAL").is("deleted_at", null).order("doc_number", { ascending: false }).limit(300),
    supabase.from("ap_cows").select("cw_id, ap_id, purchase_analyses!inner(status, deleted_at)").neq("purchase_analyses.status", "VOID").is("purchase_analyses.deleted_at", null),
    supabase.from("products").select("id, code, name, product_categories(code)").eq("is_active", true).order("name"),
    supabase.from("v_current_prices").select("product_id, sell_price"),
    supabase.from("non_carcass_types").select("name").eq("is_active", true).order("name"),
    supabase.from("cost_types").select("id, name").eq("is_active", true).order("created_at"),
    supabase.rpc("ap_next_seq", { p_yy: yy }),
  ]);
  const taken = new Set((used.data ?? []).filter((u) => u.ap_id !== apId).map((u) => u.cw_id as string));
  const priceOf = new Map((price.data ?? []).map((p) => [p.product_id as string, p.sell_price as number | null]));
  return {
    suppliers: (sup.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    cowTypes: (cow.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name })),
    cows: (cws.data ?? []).filter((w) => !taken.has(w.id)).map((w) => ({
      id: w.id, cow_number: w.cow_number, doc_number: w.doc_number, live: Number(w.live_weight), carcass: Number(w.carcass_weight),
      supplier_id: w.supplier_id ?? "", cow_type_id: w.cow_type_id,
      items: [...(w.cw_items ?? [])].filter((i) => i.product_id).sort((a, b) => a.line_no - b.line_no).map((i) => ({ product_id: i.product_id as string, weight: Number(i.weight) })),
    })),
    products: (prod.data ?? []).map((p) => ({ id: p.id, code: p.code, name: p.name, meat: one(p.product_categories as Rel<{ code: string }>)?.code === "DAGING", price: priceOf.get(p.id) ?? null })),
    nonkNames: (non.data ?? []).map((r) => r.name),
    costTypes: (cost.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    nextSeq: typeof seq.data === "number" ? seq.data : null,
    seqYear: yy,
  };
}
