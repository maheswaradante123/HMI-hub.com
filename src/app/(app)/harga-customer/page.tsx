import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";

export default async function CustomerPricesPage() {
  const session = await requireSession();
  if (!session.can("ro", "view")) return <Forbidden roleName={session.roleName} what="Harga Horeka" />;
  const supabase = await createClient();
  const [{ data: customers }, { data: prices }] = await Promise.all([
    supabase.from("customers").select("id, code, name").eq("type", "HOREKA").eq("is_active", true).order("name"),
    supabase.from("v_customer_prices").select("customer_id").is("voided_at", null),
  ]);
  const count = new Map<string, number>();
  for (const p of prices ?? []) count.set(p.customer_id as string, (count.get(p.customer_id as string) ?? 0) + 1);
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold">Harga Horeka</h1>
      <p className="mt-1 text-muted">Harga khusus per customer Horeka. Produk tanpa harga khusus memakai harga toko yang sama untuk semua customer.</p>
      <ul className="mt-6 space-y-2">
        {(customers ?? []).map((c) => (
          <li key={c.id as string}>
            <Link href={`/harga-customer/${c.id}`} className="flex items-center justify-between rounded-lg border border-line bg-surface px-5 py-4 text-lg hover:bg-background">
              <span className="font-semibold">{c.name}</span>
              <span className="text-muted">{count.get(c.id as string) ?? 0} harga khusus</span>
            </Link>
          </li>
        ))}
        {(customers ?? []).length === 0 && <li className="rounded-md border border-line bg-surface px-4 py-6">Belum ada customer bertipe Horeka.</li>}
      </ul>
    </div>
  );
}
