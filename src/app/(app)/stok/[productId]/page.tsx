import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { fmtDate, fmtQty, fmtRupiah } from "@/lib/docs/format";
import { sortLots, withBalances } from "@/lib/docs/stock";
import { loadNames } from "@/lib/pr/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TYPE_LABEL: Record<string, string> = {
  OPENING: "Stok awal", IN_PURCHASE: "Pembelian masuk", IN_PRODUCTION: "Hasil penimbangan karkas", OUT_SALE: "Keluar (packing list)",
  ADJUST_IN: "Penyesuaian tambah", ADJUST_OUT: "Penyesuaian kurang", OPNAME_IN: "Opname tambah", OPNAME_OUT: "Opname kurang",
  REVERSAL_IN: "Pembatalan (masuk)", REVERSAL_OUT: "Pembatalan (keluar)",
};
// Dokumen sumber mutasi: tabel dan alamat halaman detailnya.
const REF: Record<string, { table: string; path: string }> = {
  CW: { table: "carcass_weighings", path: "/d/cw" }, PL: { table: "packing_lists", path: "/d/pl" }, SO: { table: "stock_opnames", path: "/d/so" },
};
type Rel<T> = T | T[] | null;
const one = <T,>(v: Rel<T>): T | null => (Array.isArray(v) ? (v[0] ?? null) : v);
const SHOWN = 200;

export default async function StockDetailPage({ params, searchParams }: { params: Promise<{ productId: string }>; searchParams: Promise<{ ok?: string; tab?: string }> }) {
  const { productId } = await params;
  const sp = await searchParams;
  if (!UUID.test(productId)) notFound();
  const session = await requireSession();
  if (!session.can("stock", "view")) return <Forbidden roleName={session.roleName} what="Stok" />;
  const showCost = session.can("pricing_cost", "view");
  const tab = sp.tab === "riwayat" ? "riwayat" : "sapi";

  const supabase = await createClient();
  const { data: product } = await supabase.from("products").select("id, code, name, min_stock, units(name), product_categories(name)").eq("id", productId).maybeSingle();
  if (!product) notFound();
  const [{ data: balances }, { data: moves }, { data: whs }, { data: lots }] = await Promise.all([
    supabase.from("v_stock_balance").select("warehouse_id, qty").eq("product_id", productId),
    supabase.from("v_stock_ledger").select("*").eq("product_id", productId).order("movement_date", { ascending: false }).order("created_at", { ascending: false }).limit(3000),
    supabase.from("warehouses").select("id, name"),
    supabase.from("v_stock_lots").select("lot, first_in, qty_in, qty_out, qty_rest").eq("product_id", productId),
  ]);
  const wh = Object.fromEntries((whs ?? []).map((w) => [w.id as string, w.name as string]));
  const unit = one(product.units as Rel<{ name: string }>)?.name ?? "";
  const catName = one(product.product_categories as Rel<{ name: string }>)?.name ?? "";
  const total = (balances ?? []).reduce((s, b) => s + Number(b.qty), 0);
  const lotRows = sortLots((lots ?? []).map((l) => ({ lot: l.lot as string | null, first_in: l.first_in as string | null, qty_in: Number(l.qty_in), qty_out: Number(l.qty_out), qty_rest: Number(l.qty_rest) })));
  const loaded = (moves ?? []).map((m) => ({ ...m, id: String(m.id), movement_date: String(m.movement_date), created_at: String(m.created_at), qty: Number(m.qty) }));
  const ledger = withBalances(loaded, Math.round((total - loaded.reduce((t, m) => t + m.qty, 0)) * 1000) / 1000); // bila riwayat lebih dari yang dimuat, saldo awal tetap benar
  const shown = ledger.slice(0, SHOWN);

  let names: Record<string, string> = {};
  const refDocs = new Map<string, { no: string; href: string }>();
  if (tab === "riwayat") {
    names = await loadNames(supabase, shown.map((m) => m.created_by as string));
    await Promise.all(Object.entries(REF).map(async ([type, r]) => {
      const ids = [...new Set(shown.filter((m) => m.ref_type === type && m.ref_id).map((m) => m.ref_id as string))];
      if (!ids.length) return;
      const { data } = await supabase.from(r.table).select("id, doc_number").in("id", ids);
      for (const d of data ?? []) refDocs.set(d.id as string, { no: String(d.doc_number), href: `${r.path}/${d.id}` });
    }));
  }
  const tabLink = (key: string, label: string, n?: number) => (
    <Link key={key} href={`/stok/${productId}${key === "sapi" ? "" : `?tab=${key}`}`} aria-current={tab === key ? "page" : undefined}
      className={`rounded-full px-5 py-2 text-lg font-semibold ${tab === key ? "bg-brand text-white" : "border-2 border-line hover:bg-background"}`}>{label}{n !== undefined ? ` (${n})` : ""}</Link>
  );
  const sum = (f: (r: (typeof lotRows)[number]) => number) => lotRows.reduce((s, r) => s + f(r), 0);

  return (
    <div className="max-w-6xl">
      <Link href="/stok" className="underline">&larr; Semua stok</Link>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">{product.name} <span className="text-muted">({product.code})</span></h1>
          <p className="mt-1 text-lg text-muted">{catName ? `${catName} · ` : ""}Stok total <b className="text-foreground tabular-nums">{fmtQty(total)} {unit}</b> (minimum {fmtQty(Number(product.min_stock))})</p>
        </div>
        {session.can("stock", "create") && <Link href={`/stok/catat?produk=${product.id}`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">+ Catat transaksi</Link>}
      </div>
      {sp.ok && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">Pencatatan stok tersimpan.</p>}
      {(balances ?? []).length > 1 && (
        <ul className="mt-3 flex flex-wrap gap-3">
          {(balances ?? []).map((b) => <li key={b.warehouse_id as string} className="rounded-md border border-line bg-surface px-4 py-2">{wh[b.warehouse_id as string] ?? "-"}: <b className="tabular-nums">{fmtQty(Number(b.qty))}</b></li>)}
        </ul>
      )}

      <nav aria-label="Bagian stok" className="mt-6 flex flex-wrap gap-2">{[tabLink("sapi", "Asal Sapi", lotRows.length), tabLink("riwayat", "Riwayat Transaksi")]}</nav>

      {tab === "sapi" ? (
        <div className="mt-4 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full min-w-[760px] text-left text-lg">
            <thead className="border-b border-line bg-background"><tr>
              <th scope="col" className="px-4 py-3">Kode sapi</th><th scope="col" className="px-4 py-3">Masuk</th>
              <th scope="col" className="px-4 py-3 text-right">Masuk ({unit})</th><th scope="col" className="px-4 py-3 text-right">Keluar ({unit})</th>
              <th scope="col" className="px-4 py-3 text-right">Sisa ({unit})</th><th scope="col" className="px-4 py-3">Porsi dari total</th>
            </tr></thead>
            <tbody>
              {lotRows.map((r) => {
                const gone = r.qty_rest <= 1e-9;
                return (
                  <tr key={r.lot ?? "-"} className={`border-b border-line ${gone ? "text-muted" : ""}`}>
                    <td className="px-4 py-3 font-semibold">{r.lot ?? "Tanpa kode sapi"}{gone && <span className="ml-2 rounded bg-background px-2 py-0.5 text-sm font-normal">Habis</span>}</td>
                    <td className="px-4 py-3">{r.first_in ? fmtDate(r.first_in) : "-"}</td>
                    <td className="px-4 py-3 text-right tabular-nums">{fmtQty(r.qty_in)}</td>
                    <td className="px-4 py-3 text-right tabular-nums">{fmtQty(r.qty_out)}</td>
                    <td className="px-4 py-3 text-right tabular-nums"><b>{fmtQty(r.qty_rest)}</b></td>
                    <td className="px-4 py-3"><div className="h-2.5 w-36 rounded bg-line" role="img" aria-label={`${total > 0 ? Math.round((Math.max(0, r.qty_rest) / total) * 100) : 0} persen dari total`}><div className="h-2.5 rounded bg-brand" style={{ width: `${total > 0 ? Math.min(100, Math.max(0, (r.qty_rest / total) * 100)) : 0}%` }} /></div></td>
                  </tr>
                );
              })}
              {lotRows.length === 0 && <tr><td colSpan={6} className="px-4 py-6 text-center text-muted">Belum ada pergerakan stok untuk item ini.</td></tr>}
              {lotRows.length > 0 && <tr className="bg-background font-semibold"><td className="px-4 py-3" colSpan={2}>Total</td><td className="px-4 py-3 text-right tabular-nums">{fmtQty(sum((r) => r.qty_in))}</td><td className="px-4 py-3 text-right tabular-nums">{fmtQty(sum((r) => r.qty_out))}</td><td className="px-4 py-3 text-right tabular-nums">{fmtQty(sum((r) => r.qty_rest))}</td><td /></tr>}
            </tbody>
          </table>
          <p className="border-t border-line px-4 py-3 text-sm text-muted">Barang keluar yang dicatat tanpa kode sapi (mis. dari Packing List) dihitung dari sapi yang masuk lebih dulu.</p>
        </div>
      ) : (
        <>
          <div className="mt-4 overflow-x-auto rounded-lg border border-line bg-surface">
            <table className="w-full min-w-[980px] text-left text-lg">
              <thead className="border-b border-line bg-background"><tr>
                <th scope="col" className="px-4 py-3">Tanggal</th><th scope="col" className="px-4 py-3">Tipe</th>
                {(whs ?? []).length > 1 && <th scope="col" className="px-4 py-3">Gudang</th>}
                <th scope="col" className="px-4 py-3">Kode sapi</th><th scope="col" className="px-4 py-3 text-right">Jumlah</th>
                <th scope="col" className="px-4 py-3 text-right">Stok sebelum</th><th scope="col" className="px-4 py-3 text-right">Stok sesudah</th>
                {showCost && <th scope="col" className="px-4 py-3 text-right">Harga beli</th>}
                <th scope="col" className="px-4 py-3">Referensi</th><th scope="col" className="px-4 py-3">Catatan</th><th scope="col" className="px-4 py-3">Oleh</th>
              </tr></thead>
              <tbody>
                {shown.map((m) => {
                  const ref = m.ref_id ? refDocs.get(String(m.ref_id)) : undefined;
                  return (
                    <tr key={m.id} className="border-b border-line last:border-0">
                      <td className="whitespace-nowrap px-4 py-3">{fmtDate(m.movement_date)}</td>
                      <td className="px-4 py-3"><span className={`rounded px-2 py-0.5 text-sm font-semibold ${m.qty > 0 ? "bg-green-100 text-green-900" : "bg-danger-bg text-danger"}`}>Stok {m.qty > 0 ? "IN" : "OUT"}</span><div className="text-sm text-muted">{TYPE_LABEL[m.movement_type as string] ?? String(m.movement_type)}</div></td>
                      {(whs ?? []).length > 1 && <td className="px-4 py-3">{wh[m.warehouse_id as string] ?? "-"}</td>}
                      <td className="px-4 py-3">{(m.lot as string | null) ?? "-"}</td>
                      <td className={`px-4 py-3 text-right tabular-nums ${m.qty < 0 ? "text-danger" : "text-green-800"}`}>{m.qty > 0 ? "+" : "−"}{fmtQty(Math.abs(m.qty))}</td>
                      <td className="px-4 py-3 text-right tabular-nums">{fmtQty(m.before)}</td>
                      <td className="px-4 py-3 text-right tabular-nums">{fmtQty(m.after)}</td>
                      {showCost && <td className="px-4 py-3 text-right tabular-nums">{m.unit_cost != null ? fmtRupiah(Number(m.unit_cost)) : "-"}</td>}
                      <td className="px-4 py-3">{ref ? <Link href={ref.href} className="text-brand underline">{ref.no}</Link> : "-"}</td>
                      <td className="px-4 py-3">{(m.note as string) ?? ""}</td>
                      <td className="px-4 py-3">{names[m.created_by as string] ?? "-"}</td>
                    </tr>
                  );
                })}
                {shown.length === 0 && <tr><td colSpan={11} className="px-4 py-6 text-center text-muted">Belum ada transaksi.</td></tr>}
              </tbody>
            </table>
          </div>
          {ledger.length > SHOWN && <p className="mt-3 text-muted">Menampilkan {SHOWN} transaksi terbaru dari {ledger.length}.</p>}
        </>
      )}
    </div>
  );
}
