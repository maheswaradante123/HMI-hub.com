import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { fmtQty, fmtRupiah } from "@/lib/docs/format";
import { emptyLast } from "@/lib/docs/stock";

type Rel<T> = T | T[] | null;
const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);

export default async function StockPage({ searchParams }: { searchParams: Promise<{ q?: string; hanya?: string; kat?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("stock", "view")) return <Forbidden roleName={session.roleName} what="Stok" />;
  const showValue = session.can("pricing_cost", "view");

  const supabase = await createClient();
  let q = supabase.from("v_stock_summary").select("product_id, code, name, qty, min_stock, is_low, product_type").order("name").limit(500);
  const term = (sp.q ?? "").replace(/[,()%*\\]/g, " ").trim();
  if (term) q = q.or(`code.ilike.%${term}%,name.ilike.%${term}%`);
  if (sp.hanya === "menipis") q = q.eq("is_low", true);
  const [{ data: rows, error }, { data: values }, { data: prods }, { data: lots }] = await Promise.all([
    q,
    showValue ? supabase.from("v_stock_value").select("product_id, last_cost, value") : Promise.resolve({ data: [] }),
    supabase.from("products").select("id, units(name), product_categories(code, name)").eq("is_active", true),
    supabase.from("v_stock_lots").select("product_id").not("lot", "is", null).gt("qty_rest", 0).limit(5000),
  ]);
  const val = new Map((values ?? []).map((v) => [v.product_id as string, v]));
  const info = new Map((prods ?? []).map((p) => [p.id as string, { unit: one(p.units as Rel<{ name: string }>)?.name ?? "", cat: one(p.product_categories as Rel<{ code: string; name: string }>) }]));
  const cows = new Map<string, number>();
  for (const l of lots ?? []) cows.set(l.product_id as string, (cows.get(l.product_id as string) ?? 0) + 1);
  const totalValue = (values ?? []).reduce((s, v) => s + Number(v.value ?? 0), 0);

  const cats = [...new Map((rows ?? []).map((r) => info.get(r.product_id as string)?.cat).filter((c): c is { code: string; name: string } => !!c).map((c) => [c.code, c.name])).entries()].sort((a, b) => a[1].localeCompare(b[1], "id"));
  const kat = cats.some(([code]) => code === sp.kat) ? sp.kat! : "";
  const list = emptyLast((rows ?? []).filter((r) => !kat || info.get(r.product_id as string)?.cat?.code === kat).map((r) => ({ ...r, qty: Number(r.qty), name: String(r.name) })));
  const pill = (code: string, label: string) => {
    const qs = new URLSearchParams();
    if (code) qs.set("kat", code);
    if (term) qs.set("q", term);
    if (sp.hanya === "menipis") qs.set("hanya", "menipis");
    const on = kat === code;
    return <Link key={code || "semua"} href={`/stok${qs.size ? `?${qs}` : ""}`} aria-current={on ? "true" : undefined} className={`rounded-full px-5 py-2 text-lg font-semibold ${on ? "bg-brand text-white" : "border-2 border-line hover:bg-background"}`}>{label}</Link>;
  };

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">Stok</h1>
        <div className="flex flex-wrap gap-3">
          {session.can("stock", "create") && <Link href="/stok/catat" className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">+ Catat transaksi stok</Link>}
          {session.can("product", "create") && <Link href="/data/produk/baru" className="rounded-md border-2 border-brand px-6 py-3 text-lg font-semibold text-brand hover:bg-background">+ Tambah item</Link>}
        </div>
      </div>
      <p className="mt-1 max-w-3xl text-muted">Stok per item. Klik item untuk melihat asal sapinya. Item di bawah batas minimum ditandai Low stock!.</p>

      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        {kat && <input type="hidden" name="kat" value={kat} />}
        <label htmlFor="q" className="sr-only">Cari</label>
        <input id="q" name="q" defaultValue={term} placeholder="Cari kode atau nama" className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg" />
        <label className="flex items-center gap-2 text-lg"><input type="checkbox" name="hanya" value="menipis" defaultChecked={sp.hanya === "menipis"} className="h-5 w-5" /> Hanya yang menipis</label>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Cari</button>
      </form>
      {cats.length > 1 && <nav aria-label="Kategori" className="mt-4 flex flex-wrap gap-2">{[pill("", "Semua"), ...cats.map(([code, name]) => pill(code, name))]}</nav>}

      {error ? <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat.</p> : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>
                <th scope="col" className="px-4 py-3">Kode</th><th scope="col" className="px-4 py-3">Item</th><th scope="col" className="px-4 py-3">Kategori</th>
                <th scope="col" className="px-4 py-3 text-right">Stok</th><th scope="col" className="px-4 py-3">Satuan</th>
                <th scope="col" className="px-4 py-3 text-right">Minimum</th><th scope="col" className="px-4 py-3 text-right">Asal Sapi</th>
                {showValue && <><th scope="col" className="px-4 py-3 text-right">Harga beli terakhir</th><th scope="col" className="px-4 py-3 text-right">Nilai</th></>}
              </tr>
            </thead>
            <tbody>
              {list.map((r) => {
                const id = r.product_id as string;
                const v = val.get(id);
                const empty = r.qty <= 1e-9;
                const n = cows.get(id) ?? 0;
                return (
                  <tr key={id} className={`border-b border-line last:border-0 ${r.is_low && !empty ? "bg-warn-bg" : ""} ${empty ? "text-muted" : ""}`}>
                    <td className="px-4 py-3">{r.code}</td>
                    <td className="px-4 py-3"><Link href={`/stok/${id}`} className="font-semibold text-brand underline">{r.name}</Link></td>
                    <td className="px-4 py-3">{info.get(id)?.cat?.name ?? "-"}</td>
                    <td className="px-4 py-3 text-right tabular-nums"><b className={r.is_low && !empty ? "text-danger" : ""}>{fmtQty(r.qty)}</b>
                      {r.is_low && !empty && <div className="text-sm font-semibold text-danger">Low stock!</div>}
                      {empty && <div className="text-sm">Habis</div>}</td>
                    <td className="px-4 py-3">{info.get(id)?.unit}</td>
                    <td className="px-4 py-3 text-right tabular-nums">{Number(r.min_stock) ? fmtQty(Number(r.min_stock)) : "-"}</td>
                    <td className="px-4 py-3 text-right">{n ? `${n} sapi` : "-"}</td>
                    {showValue && <>
                      <td className="px-4 py-3 text-right tabular-nums">{v?.last_cost != null ? fmtRupiah(Number(v.last_cost)) : "-"}</td>
                      <td className="px-4 py-3 text-right tabular-nums">{v?.value != null ? fmtRupiah(Number(v.value)) : "-"}</td>
                    </>}
                  </tr>
                );
              })}
              {list.length === 0 && <tr><td colSpan={showValue ? 9 : 7} className="px-4 py-6 text-center text-muted">Tidak ada item yang cocok.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      {showValue && <p className="mt-3 text-right text-lg font-semibold">Total nilai stok (harga beli terakhir): {fmtRupiah(totalValue)}</p>}
      {showValue && <p className="text-right text-sm text-muted">Item tanpa catatan pembelian masuk belum dihitung nilainya.</p>}
    </div>
  );
}
