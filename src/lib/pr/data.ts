import "server-only";
import type { createClient } from "@/lib/supabase/server";

type Supa = Awaited<ReturnType<typeof createClient>>;

// Nama staff dari user_directory (view yang hanya membuka id dan nama).
export async function loadNames(supabase: Supa, ids: (string | null | undefined)[]) {
  const unique = [...new Set(ids.filter((x): x is string => !!x))];
  if (unique.length === 0) return {} as Record<string, string>;
  const { data } = await supabase.from("user_directory").select("id, full_name").in("id", unique);
  return Object.fromEntries((data ?? []).map((u) => [u.id as string, u.full_name as string]));
}

export async function loadFormOptions(supabase: Supa) {
  const [{ data: products }, { data: units }] = await Promise.all([
    supabase.from("products").select("id, name, unit_id").eq("is_active", true).order("name"),
    supabase.from("units").select("id, name").eq("is_active", true).order("name"),
  ]);
  return { products: products ?? [], units: units ?? [] };
}
