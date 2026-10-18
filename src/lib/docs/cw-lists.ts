import "server-only";
import type { createClient } from "@/lib/supabase/server";
import { cwCatFromCode, type CwCat } from "./cw";

type Supa = Awaited<ReturnType<typeof createClient>>;

export type CwLists = {
  suppliers: { id: string; name: string }[];
  warehouses: { id: string; name: string }[];
  cowTypes: { id: string; code: string; name: string }[];
  masterItems: { name: string; cat: CwCat }[];   // nama yang sudah ada di master: kategorinya terkunci di form
  nextNumber: string;                             // pratinjau urutan, mis. "012"
};

type Rel<T> = T | T[] | null;
const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

export async function loadCwLists(supabase: Supa): Promise<CwLists> {
  const [sup, wh, cow, prod, non, cnt] = await Promise.all([
    supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
    supabase.from("warehouses").select("id, name").eq("is_active", true).order("name"),
    supabase.from("cow_types").select("id, code, name").eq("is_active", true).order("code"),
    supabase.from("products").select("name, product_categories(code)").eq("is_active", true).order("name"),
    supabase.from("non_carcass_types").select("name").eq("is_active", true).order("name"),
    supabase.rpc("cw_next_seq"),
  ]);
  const meat = new Set(["DAGING", "TULANG", "JEROHAN"]);
  const masterItems: CwLists["masterItems"] = [];
  for (const p of prod.data ?? []) {
    const code = one(p.product_categories as Rel<{ code: string }>)?.code ?? null;
    if (code && meat.has(code)) masterItems.push({ name: p.name, cat: cwCatFromCode(code) });
  }
  for (const r of non.data ?? []) masterItems.push({ name: r.name, cat: "Non-Karkas" });
  return {
    suppliers: (sup.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    warehouses: (wh.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    cowTypes: (cow.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name })),
    masterItems,
    nextNumber: typeof cnt.data === "number" ? String(cnt.data).padStart(3, "0") : "",
  };
}
