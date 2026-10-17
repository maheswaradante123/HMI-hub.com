import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { PriceForm } from "@/components/price-form";
import { dateId, rupiah } from "@/lib/pr/constants";
import { TYPE_LABEL, todayJakarta } from "@/lib/pricing/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function SetPricePage({ params }: { params: Promise<{ productId: string }> }) {
  const { productId } = await params;
  if (!UUID.test(productId)) notFound();
  const session = await requireSession();
  if (!session.can("pricing", "create")) return <Forbidden roleName={session.roleName} what="form ubah harga" />;
  const canCost = session.can("pricing_cost", "view");

  const supabase = await createClient();
  const { data: product } = await supabase
    .from("products").select("id, code, name, product_type, is_active").eq("id", productId).maybeSingle();
  if (!product) notFound();
  if (!product.is_active) {
    return (
      <div className="max-w-2xl">
        <h1 className="text-3xl font-bold">Produk nonaktif</h1>
        <p className="mt-3 rounded-md bg-warn-bg px-4 py-3">Harga produk yang nonaktif tidak bisa diubah. Aktifkan produknya lebih dulu di Master Data.</p>
        <Link href="/pricing-toko" className="mt-4 inline-block underline">Kembali</Link>
      </div>
    );
  }

  const showCost = canCost && product.product_type !== "MANUFACTURE";
  const [{ data: last }, { data: suppliers }] = await Promise.all([
    supabase
      .from("v_product_prices")
      .select("sell_price, buy_price, supplier_id, effective_from")
      .eq("product_id", productId)
      .is("voided_at", null)
      .order("effective_from", { ascending: false })
      .limit(1)
      .maybeSingle(),
    showCost ? supabase.from("suppliers").select("id, name").eq("is_active", true).order("name") : Promise.resolve({ data: [] }),
  ]);

  const today = todayJakarta();
  return (
    <div>
      <h1 className="text-3xl font-bold">Ubah harga: {product.name}</h1>
      <p className="mb-6 mt-1 text-muted">
        {product.code} · {TYPE_LABEL[product.product_type]}
        {last && (
          <>
            {" "}· Harga terakhir {last.sell_price != null ? rupiah(Number(last.sell_price)) : "-"}
            {showCost && last.buy_price != null ? ` (beli ${rupiah(Number(last.buy_price))})` : ""}, berlaku dari {dateId(last.effective_from)}
          </>
        )}
      </p>
      <PriceForm
        productId={productId}
        showCost={showCost}
        suppliers={(suppliers ?? []) as { id: string; name: string }[]}
        initial={{ sell: "", buy: "", supplier: last?.supplier_id ?? "", from: today, note: "" }}
        minDate={last ? last.effective_from : null}
      />
    </div>
  );
}
