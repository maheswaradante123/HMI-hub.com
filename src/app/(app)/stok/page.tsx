import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { fmtQty, fmtRupiah } from "@/lib/docs/format";

export default async function StockPage({ searchParams }: { searchParams: Promise<{ q?: string; hanya?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("stock", "view")) return <Forbidden roleName={session.roleName} what="Stok" />;
  const showValue = session.can("pricing_cost", "view");

  const supabase = await createClient();
  let q = supabase.from("v_stock_summary").select("product_id, code, name, qty, min_stock, is_low, product_type").order("name").limit(500);
  const term = (sp.q ?? "").replace(/[,()%*\\]/g, " ").trim();
  if (term) q = q.or(`code.ilike.%${term}%,name.ilike.%${term}%`);
  if (sp.hanya === "menipis") q = q.eq("is_low", true);
  const [{ data: rows, error }, { data: values }, { data: units }] = await Promise.all([
    q,
    showValue ? supabase.from("v_stock_value").select("product_id, last_cost, value") : Promise.resolve({ data: [] }),
    supabase.from("products").select("id, units(name)").eq("is_active", true),
  ]);
  const val = new Map((values ?? []).map((v) => [v.product_id as string, v]));
  const unit = new Map((units ?? []).map((u) => [u.id as string, (Array.isArray(u.units) ? u.units[0]?.name : (u.units as { name: string } | null)?.name) ?? ""]));
  const totalValue = (values ?? []).reduce((s, v) => s + Number(v.value ?? 0), 0);

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">Stok</h1>
        {session.can("stock", "create") && (
          <Link href="/stok/catat" className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">+ Catat stok</Link>
        )}
      </div>
      <p className="mt-1 max-w-3xl text-muted">Saldo per item. Baris ditandai Menipis jika stok di bawah batas minimum yang diatur di data produk.</p>

      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        <label htmlFor="q" className="sr-only">Cari</label>
        <input id="q" name="q" defaultValue={term} placeholder="Cari kode atau nama" className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg" />
        <label className="flex items-center gap-2 text-lg"><input type="checkbox" name="hanya" value="menipis" defaultChecked={sp.hanya === "menipis"} className="h-5 w-5" /> Hanya yang menipis</label>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Cari</button>
      </form>

      {error ? <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat.</p> : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>
                <th scope="col" className="px-4 py-3">Kode</th><th scope="col" className="px-4 py-3">Produk</th>
                <th scope="col" className="px-4 py-3 text-right">Stok</th><th scope="col" className="px-4 py-3">Satuan</th>
                <th scope="col" className="px-4 py-3 text-right">Minimum</th><th scope="col" className="px-4 py-3">Keterangan</th>
                {showValue && <><th scope="col" className="px-4 py-3 text-right">Harga beli terakhir</th><th scope="col" className="px-4 py-3 text-right">Nilai</th></>}
              </tr>
            </thead>
            <tbody>
              {(rows ?? []).map((r) => {
                const v = val.get(r.product_id as string);
                return (
                  <tr key={r.product_id as string} className={`border-b border-line last:border-0 ${r.is_low ? "bg-warn-bg" : ""}`}>
                    <td className="px-4 py-3">{r.code}</td>
                    <td className="px-4 py-3"><Link href={`/stok/${r.product_id}`} className="font-semibold text-brand underline">{r.name}</Link></td>
                    <td className="px-4 py-3 text-right tabular-nums">{fmtQty(Number(r.qty))}</td>
                    <td className="px-4 py-3">{unit.get(r.product_id as string)}</td>
                    <td className="px-4 py-3 text-right tabular-nums">{fmtQty(Number(r.min_stock))}</td>
                    <td className="px-4 py-3">{r.is_low ? <span className="rounded bg-amber-200 px-2.5 py-1 font-semibold text-amber-950">Menipis</span> : ""}</td>
                    {showValue && <>
                      <td className="px-4 py-3 text-right tabular-nums">{v?.last_cost != null ? fmtRupiah(Number(v.last_cost)) : "-"}</td>
                      <td className="px-4 py-3 text-right tabular-nums">{v?.value != null ? fmtRupiah(Number(v.value)) : "-"}</td>
                    </>}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {showValue && <p className="mt-3 text-right text-lg font-semibold">Total nilai stok (harga beli terakhir): {fmtRupiah(totalValue)}</p>}
      {showValue && <p className="text-right text-sm text-muted">Item tanpa catatan pembelian masuk belum dihitung nilainya.</p>}
    </div>
  );
}
