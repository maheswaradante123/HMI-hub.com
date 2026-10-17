import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { Resource } from "./config";

export type RefOption = { value: string; label: string; active: boolean };
export type RefMap = Record<string, RefOption[]>;

// Mengambil pilihan untuk field bertipe "ref" (kategori, satuan, gudang).
export async function loadRefs(
  supabase: Awaited<ReturnType<typeof createClient>>,
  resource: Resource,
): Promise<RefMap> {
  const tables = [...new Set(resource.fields.filter((f) => f.type === "ref" && f.ref).map((f) => f.ref!))];
  const out: RefMap = {};
  for (const table of tables) {
    const { data } = await supabase.from(table).select("id, code, name, is_active").order("name");
    out[table] = (data ?? []).map((r) => ({
      value: r.id as string,
      label: `${r.name}`,
      active: r.is_active as boolean,
    }));
  }
  return out;
}
