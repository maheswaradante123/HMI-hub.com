import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { dateId, rupiah } from "@/lib/pr/constants";
import { TYPE_LABEL, todayJakarta } from "@/lib/pricing/data";

type Price = {
  product_id: string; sell_price: number | null; buy_price: number | null;
  supplier_id: string | null; effective_from: string; effective_to: string | null;
};

export default async function PricingListPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; jenis?: string }>;
}) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("pricing", "view")) return <Forbidden roleName={session.roleName} what="Pricing Toko" />;
  const showCost = session.can("pricing_cost", "view");
  const canSet = session.can("pricing", "create");

  const supabase = await createClient();
  let pq = supabase
    .from("products")
    .select("id, code, name, product_type, units(name)")
    .eq("is_active", true)
    .order("product_type")
    .order("name")
    .limit(500);
  const type = sp.jenis && sp.jenis in TYPE_LABEL ? sp.jenis : "";
  if (type) pq = pq.eq("product_type", type);
  const q = (sp.q ?? "").replace(/[,()%*\\]/g, " ").trim();
  if (q) pq = pq.or(`code.ilike.%${q}%,name.ilike.%${q}%`);

  const [{ data: products, error }, { data: current }, { data: upcoming }, { data: suppliers }] = await Promise.all([
    pq,
    supabase.from("v_current_prices").select("product_id, sell_price, buy_price, supplier_id, effective_from, effective_to"),
    supabase
      .from("v_product_prices")
      .select("product_id, sell_price, buy_price, supplier_id, effective_from, effective_to")
      .is("voided_at", null)
      .gt("effective_from", todayJakarta())
      .order("effective_from"),
    showCost ? supabase.from("suppliers").select("id, name") : Promise.resolve({ data: [] as { id: string; name: string }[] }),
  ]);
  const cur = new Map((current as Price[] | null ?? []).map((p) => [p.product_id, p]));
  const next = new Map<string, Price>();
  for (const p of (upcoming as Price[] | null) ?? []) if (!next.has(p.product_id)) next.set(p.product_id, p);
  const supName = Object.fromEntries((suppliers ?? []).map((s) => [s.id, s.name]));

  const heads = ["Kode", "Produk", "Jenis", "Harga jual", ...(showCost ? ["Harga beli", "Selisih", "Supplier"] : []), "Berlaku sejak", "Harga berikutnya", "Aksi"];

  return (
    <div>
      <h1 className="text-3xl font-bold">Pricing Toko</h1>
      <p className="mt-1 text-muted">
        Harga yang berlaku hari ini. Riwayat lengkap ada di halaman tiap produk.
        {showCost && " Selisih adalah harga jual dikurangi harga beli."}
      </p>

      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        <label htmlFor="q" className="sr-only">Cari</label>
        <input id="q" name="q" defaultValue={q} placeholder="Cari kode atau nama" className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg" />
        <label htmlFor="jenis" className="sr-only">Jenis produk</label>
        <select id="jenis" name="jenis" defaultValue={type} className="rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg">
          <option value="">Semua jenis</option>
          {Object.entries(TYPE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Cari</button>
      </form>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat. Muat ulang halaman.</p>
      ) : !products || products.length === 0 ? (
        <p className="mt-6 rounded-md border border-line bg-surface px-4 py-6">Tidak ada produk yang cocok.</p>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>{heads.map((h) => <th key={h} scope="col" className="px-4 py-3 font-semibold">{h}</th>)}</tr>
            </thead>
            <tbody>
              {products.map((p) => {
                const c = cur.get(p.id);
                const n = next.get(p.id);
                const unit = Array.isArray(p.units) ? p.units[0]?.name : (p.units as { name: string } | null)?.name;
                const diff = c && c.sell_price != null && c.buy_price != null ? Number(c.sell_price) - Number(c.buy_price) : null;
                return (
                  <tr key={p.id} className="border-b border-line align-top last:border-b-0">
                    <td className="px-4 py-3">{p.code}</td>
                    <td className="px-4 py-3">{p.name}{unit && <span className="block text-base text-muted">per {unit}</span>}</td>
                    <td className="px-4 py-3">{TYPE_LABEL[p.product_type]}</td>
                    <td className="whitespace-nowrap px-4 py-3 font-semibold">
                      {c?.sell_price != null ? rupiah(Number(c.sell_price)) : (
                        <span className="rounded bg-warn-bg px-2 py-1 text-base font-semibold">Belum ada harga</span>
                      )}
                    </td>
                    {showCost && (
                      <>
                        <td className="whitespace-nowrap px-4 py-3">{c?.buy_price != null ? rupiah(Number(c.buy_price)) : "-"}</td>
                        <td className="whitespace-nowrap px-4 py-3">{diff != null ? rupiah(diff) : "-"}</td>
                        <td className="px-4 py-3">{c?.supplier_id ? supName[c.supplier_id] ?? "-" : "-"}</td>
                      </>
                    )}
                    <td className="whitespace-nowrap px-4 py-3">{c ? dateId(c.effective_from) : "-"}</td>
                    <td className="whitespace-nowrap px-4 py-3">
                      {n ? `${n.sell_price != null ? rupiah(Number(n.sell_price)) : "-"} (mulai ${dateId(n.effective_from)})` : "-"}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link href={`/pricing-toko/${p.id}`} className="mr-4 font-semibold text-brand underline">Riwayat</Link>
                      {canSet && <Link href={`/pricing-toko/${p.id}/ubah`} className="font-semibold text-brand underline">Ubah harga</Link>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
