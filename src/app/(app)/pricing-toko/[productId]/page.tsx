import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { VoidForm } from "@/components/price-form";
import { dateId, dateTimeId, rupiah } from "@/lib/pr/constants";
import { loadNames } from "@/lib/pr/data";
import { TYPE_LABEL, todayJakarta } from "@/lib/pricing/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTICES: Record<string, string> = {
  disimpan: "Harga baru tersimpan. Harga lama tetap ada di riwayat.",
  dibatalkan: "Harga dibatalkan. Barisnya tetap tercatat di riwayat.",
};

type Row = {
  id: string; sell_price: number | null; buy_price: number | null; supplier_id: string | null;
  effective_from: string; effective_to: string | null; note: string | null;
  voided_at: string | null; void_reason: string | null; created_at: string; created_by: string | null;
};

export default async function PriceHistoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ productId: string }>;
  searchParams: Promise<{ ok?: string }>;
}) {
  const { productId } = await params;
  const sp = await searchParams;
  if (!UUID.test(productId)) notFound();
  const session = await requireSession();
  if (!session.can("pricing", "view")) return <Forbidden roleName={session.roleName} what="Pricing Toko" />;
  const showCost = session.can("pricing_cost", "view");
  const canSet = session.can("pricing", "create");
  const canVoid = session.can("pricing", "edit");

  const supabase = await createClient();
  const { data: product } = await supabase
    .from("products").select("id, code, name, product_type, units(name)").eq("id", productId).maybeSingle();
  if (!product) notFound();

  const [{ data: rows }, { data: suppliers }] = await Promise.all([
    supabase
      .from("v_product_prices")
      .select("id, sell_price, buy_price, supplier_id, effective_from, effective_to, note, voided_at, void_reason, created_at, created_by")
      .eq("product_id", productId)
      .order("effective_from", { ascending: false })
      .order("created_at", { ascending: false }),
    showCost ? supabase.from("suppliers").select("id, name") : Promise.resolve({ data: [] as { id: string; name: string }[] }),
  ]);
  const history = (rows ?? []) as Row[];
  const names = await loadNames(supabase, history.map((r) => r.created_by));
  const supName = Object.fromEntries((suppliers ?? []).map((s) => [s.id, s.name]));
  const today = todayJakarta();
  const unit = Array.isArray(product.units) ? product.units[0]?.name : (product.units as { name: string } | null)?.name;

  const lastActive = history.find((r) => !r.voided_at);
  const statusOf = (r: Row) => {
    if (r.voided_at) return { label: "Dibatalkan", cls: "bg-neutral-200 text-neutral-800" };
    if (r.effective_from > today) return { label: "Akan berlaku", cls: "bg-amber-100 text-amber-900" };
    if (!r.effective_to || r.effective_to >= today) return { label: "Berlaku", cls: "bg-green-100 text-green-900" };
    return { label: "Sudah berakhir", cls: "bg-blue-100 text-blue-900" };
  };

  return (
    <div className="max-w-6xl">
      <Link href="/pricing-toko" className="underline">&larr; Semua harga</Link>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold">{product.name}</h1>
          <p className="text-muted">{product.code} · {TYPE_LABEL[product.product_type]}{unit ? ` · per ${unit}` : ""}</p>
        </div>
        {canSet && (
          <Link href={`/pricing-toko/${productId}/ubah`} className="rounded-md bg-brand px-5 py-3 text-lg font-semibold text-white hover:bg-brand-dark">
            Ubah harga
          </Link>
        )}
      </div>

      {sp.ok && NOTICES[sp.ok] && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">{NOTICES[sp.ok]}</p>}

      <h2 className="mb-3 mt-8 text-xl font-bold">Riwayat harga</h2>
      {history.length === 0 ? (
        <p className="rounded-md border border-line bg-surface px-4 py-6">
          Belum ada harga untuk produk ini.{canSet && " Klik Ubah harga untuk mengisi harga pertama."}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>
                {["Berlaku dari", "Sampai", "Harga jual", ...(showCost ? ["Harga beli", "Selisih", "Supplier"] : []), "Status", "Dicatat"].map((h) => (
                  <th key={h} scope="col" className="px-4 py-3 font-semibold">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {history.map((r) => {
                const st = statusOf(r);
                const diff = r.sell_price != null && r.buy_price != null ? Number(r.sell_price) - Number(r.buy_price) : null;
                return (
                  <tr key={r.id} className={`border-b border-line align-top last:border-b-0 ${r.voided_at ? "text-muted" : ""}`}>
                    <td className="whitespace-nowrap px-4 py-3">{dateId(r.effective_from)}</td>
                    <td className="whitespace-nowrap px-4 py-3">{r.effective_to ? dateId(r.effective_to) : "Sekarang"}</td>
                    <td className={`whitespace-nowrap px-4 py-3 ${r.voided_at ? "line-through" : "font-semibold"}`}>{r.sell_price != null ? rupiah(Number(r.sell_price)) : "-"}</td>
                    {showCost && (
                      <>
                        <td className={`whitespace-nowrap px-4 py-3 ${r.voided_at ? "line-through" : ""}`}>{r.buy_price != null ? rupiah(Number(r.buy_price)) : "-"}</td>
                        <td className="whitespace-nowrap px-4 py-3">{diff != null ? rupiah(diff) : "-"}</td>
                        <td className="px-4 py-3">{r.supplier_id ? supName[r.supplier_id] ?? "-" : "-"}</td>
                      </>
                    )}
                    <td className="px-4 py-3">
                      <span className={`inline-block rounded-full px-3 py-0.5 text-sm font-semibold ${st.cls}`}>{st.label}</span>
                      {r.voided_at && r.void_reason && <p className="mt-1 text-base">Alasan: {r.void_reason}</p>}
                    </td>
                    <td className="px-4 py-3">
                      {names[r.created_by ?? ""] ?? "-"}
                      <span className="block text-base text-muted">{dateTimeId(r.created_at)}</span>
                      {r.note && <span className="block text-base text-muted">{r.note}</span>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {canVoid && lastActive && (
        <section className="mt-8 rounded-lg border border-line bg-surface p-5">
          <h2 className="text-xl font-bold">Salah memasukkan harga?</h2>
          <p className="mt-1 text-muted">
            Harga terakhir ({lastActive.sell_price != null ? rupiah(Number(lastActive.sell_price)) : "tanpa harga jual"}, berlaku dari {dateId(lastActive.effective_from)})
            bisa dibatalkan. Harga sebelumnya akan berlaku lagi, dan harga yang benar bisa dimasukkan setelahnya.
          </p>
          <VoidForm productId={productId} priceId={lastActive.id} />
        </section>
      )}
    </div>
  );
}
