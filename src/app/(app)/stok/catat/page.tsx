import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { StockForm } from "@/components/stock-form";
import { todayJakarta } from "@/lib/pricing/data";

export default async function RecordStockPage({ searchParams }: { searchParams: Promise<{ produk?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("stock", "create")) return <Forbidden roleName={session.roleName} what="pencatatan stok" />;
  const supabase = await createClient();
  const [{ data: products }, { data: warehouses }] = await Promise.all([
    supabase.from("products").select("id, code, name").eq("is_active", true).order("name"),
    supabase.from("warehouses").select("id, name").eq("is_active", true).order("name"),
  ]);
  return (
    <div>
      <h1 className="mb-6 text-3xl font-bold">Catat stok</h1>
      <StockForm
        products={(products ?? []).map((p) => ({ id: p.id as string, label: `${p.code} - ${p.name}` }))}
        warehouses={(warehouses ?? []) as { id: string; name: string }[]}
        canCost={session.can("pricing_cost", "view")}
        today={todayJakarta()}
        initialProduct={sp.produk ?? ""}
      />
    </div>
  );
}
