import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { fmtDate, fmtQty, fmtRupiah } from "@/lib/docs/format";
import { loadNames } from "@/lib/pr/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TYPE_LABEL: Record<string, string> = {
  OPENING: "Stok awal", IN_PURCHASE: "Pembelian masuk", IN_PRODUCTION: "Hasil produksi", OUT_SALE: "Keluar (packing list)",
  ADJUST_IN: "Penyesuaian tambah", ADJUST_OUT: "Penyesuaian kurang", OPNAME_IN: "Opname tambah", OPNAME_OUT: "Opname kurang",
  REVERSAL_IN: "Pembatalan (masuk)", REVERSAL_OUT: "Pembatalan (keluar)",
};

export default async function StockDetailPage({ params, searchParams }: { params: Promise<{ productId: string }>; searchParams: Promise<{ ok?: string }> }) {
  const { productId } = await params;
  const sp = await searchParams;
  if (!UUID.test(productId)) notFound();
  const session = await requireSession();
  if (!session.can("stock", "view")) return <Forbidden roleName={session.roleName} what="Stok" />;
  const showCost = session.can("pricing_cost", "view");

  const supabase = await createClient();
  const { data: product } = await supabase.from("products").select("id, code, name, min_stock, units(name)").eq("id", productId).maybeSingle();
  if (!product) notFound();
  const [{ data: balances }, { data: moves }, { data: whs }] = await Promise.all([
    supabase.from("v_stock_balance").select("warehouse_id, qty").eq("product_id", productId),
    supabase.from("stock_movements").select("*").eq("product_id", productId).order("created_at", { ascending: false }).limit(100),
    supabase.from("warehouses").select("id, name"),
  ]);
  const wh = Object.fromEntries((whs ?? []).map((w) => [w.id as string, w.name as string]));
  const names = await loadNames(supabase, (moves ?? []).map((m) => m.created_by as string));
  const unit = (Array.isArray(product.units) ? product.units[0]?.name : (product.units as { name: string } | null)?.name) ?? "";
  const total = (balances ?? []).reduce((s, b) => s + Number(b.qty), 0);

  return (
    <div className="max-w-5xl">
      <Link href="/stok" className="underline">&larr; Semua stok</Link>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">{product.name} <span className="text-muted">({product.code})</span></h1>
        {session.can("stock", "create") && <Link href={`/stok/catat?produk=${product.id}`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">+ Catat stok</Link>}
      </div>
      {sp.ok && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">Pencatatan stok tersimpan.</p>}
      <p className="mt-4 text-2xl font-semibold tabular-nums">Total stok: {fmtQty(total)} {unit} <span className="text-base font-normal text-muted">(minimum {fmtQty(Number(product.min_stock))})</span></p>
      <ul className="mt-2 flex flex-wrap gap-3">
        {(balances ?? []).map((b) => <li key={b.warehouse_id as string} className="rounded-md border border-line bg-surface px-4 py-2">{wh[b.warehouse_id as string] ?? "-"}: <b className="tabular-nums">{fmtQty(Number(b.qty))}</b></li>)}
      </ul>

      <h2 className="mt-8 text-2xl font-bold">Riwayat mutasi</h2>
      <div className="mt-3 overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background"><tr>
            <th scope="col" className="px-4 py-3">Tanggal</th><th scope="col" className="px-4 py-3">Jenis</th><th scope="col" className="px-4 py-3">Gudang</th>
            <th scope="col" className="px-4 py-3 text-right">Jumlah</th>{showCost && <th scope="col" className="px-4 py-3 text-right">Harga beli</th>}
            <th scope="col" className="px-4 py-3">Catatan</th><th scope="col" className="px-4 py-3">Oleh</th>
          </tr></thead>
          <tbody>
            {(moves ?? []).map((m) => (
              <tr key={m.id as string} className="border-b border-line last:border-0">
                <td className="px-4 py-3">{fmtDate(String(m.movement_date))}</td>
                <td className="px-4 py-3">{TYPE_LABEL[m.movement_type as string] ?? m.movement_type}</td>
                <td className="px-4 py-3">{wh[m.warehouse_id as string] ?? "-"}</td>
                <td className={`px-4 py-3 text-right tabular-nums ${Number(m.qty) < 0 ? "text-danger" : ""}`}>{Number(m.qty) > 0 ? "+" : ""}{fmtQty(Number(m.qty))}</td>
                {showCost && <td className="px-4 py-3 text-right tabular-nums">{m.unit_cost != null ? fmtRupiah(Number(m.unit_cost)) : "-"}</td>}
                <td className="px-4 py-3">{(m.note as string) ?? ""}</td>
                <td className="px-4 py-3">{names[m.created_by as string] ?? "-"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
