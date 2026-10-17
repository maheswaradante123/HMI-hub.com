import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { RoCustomer, RoProduct } from "@/components/ro-form";

export async function loadRoLists(supabase: Awaited<ReturnType<typeof createClient>>): Promise<{ customers: RoCustomer[]; products: RoProduct[]; units: { id: string; name: string }[]; categories: { id: string; name: string }[] }> {
  const [c, p, u, k] = await Promise.all([
    supabase.from("customers").select("id, code, name, phone, address, payment_term_days").eq("is_active", true).order("name"),
    supabase.from("products").select("id, code, name, units(name)").eq("is_active", true).order("name"),
    supabase.from("units").select("id, name").eq("is_active", true).order("name"),
    supabase.from("product_categories").select("id, name").eq("is_active", true).order("name"),
  ]);
  return {
    units: (u.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    categories: (k.data ?? []).map((r) => ({ id: r.id, name: r.name })),
    customers: (c.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name, phone: r.phone ?? "", address: r.address ?? "", term: r.payment_term_days ?? 0 })),
    products: (p.data ?? []).map((r) => ({ id: r.id, code: r.code, name: r.name, unit: (r.units as unknown as { name: string } | null)?.name ?? "" })),
  };
}
