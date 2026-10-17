import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { CustomerPriceForm, VoidCustomerPrice } from "@/components/customer-price-forms";
import { fmtDate, fmtRupiah } from "@/lib/docs/format";
import { todayJakarta } from "@/lib/pricing/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type P = { id: string; product_id: string; price: number; effective_from: string; effective_to: string | null; note: string | null; voided_at: string | null; void_reason: string | null };

export default async function CustomerPriceDetail({ params, searchParams }: { params: Promise<{ customerId: string }>; searchParams: Promise<{ ok?: string }> }) {
  const { customerId } = await params;
  const sp = await searchParams;
  if (!UUID.test(customerId)) notFound();
  const session = await requireSession();
  if (!session.can("ro", "view")) return <Forbidden roleName={session.roleName} what="Harga Horeka" />;
  const canEdit = session.can("customer", "edit");

  const supabase = await createClient();
  const { data: customer } = await supabase.from("customers").select("id, name, type").eq("id", customerId).maybeSingle();
  if (!customer || customer.type !== "HOREKA") notFound();
  const [{ data: prices }, { data: products }] = await Promise.all([
    supabase.from("v_customer_prices").select("*").eq("customer_id", customerId).order("effective_from", { ascending: false }),
    supabase.from("products").select("id, code, name").eq("is_active", true).order("name"),
  ]);
  const pname = Object.fromEntries((products ?? []).map((p) => [p.id as string, `${p.code} - ${p.name}`]));
  const rows = (prices ?? []) as P[];
  const today = todayJakarta();
  const latest = new Map<string, string>();
  for (const r of rows) if (!r.voided_at && !latest.has(r.product_id)) latest.set(r.product_id, r.id);
  const state = (r: P) => r.voided_at ? "Dibatalkan" : r.effective_from > today ? "Akan berlaku" : r.effective_to && r.effective_to < today ? "Sudah berakhir" : "Berlaku";

  return (
    <div className="max-w-5xl">
      <Link href="/harga-customer" className="underline">&larr; Semua customer Horeka</Link>
      <h1 className="mt-3 text-3xl font-bold">Harga {customer.name}</h1>
      {sp.ok && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">{sp.ok === "dibatalkan" ? "Harga dibatalkan." : "Harga tersimpan."}</p>}
      {canEdit && (
        <section className="mt-6" aria-labelledby="baru">
          <h2 id="baru" className="mb-3 text-2xl font-bold">Tambah atau ubah harga</h2>
          <CustomerPriceForm customerId={customerId} products={(products ?? []).map((p) => ({ id: p.id as string, label: `${p.code} - ${p.name}` }))} today={today} />
        </section>
      )}
      <h2 className="mt-8 text-2xl font-bold">Riwayat harga</h2>
      <div className="mt-3 overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background"><tr>
            {["Produk", "Harga", "Mulai", "Sampai", "Status", "Catatan", ""].map((h, i) => <th key={i} scope="col" className="px-4 py-3">{h}</th>)}
          </tr></thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={7} className="px-4 py-6">Belum ada harga khusus.</td></tr>}
            {rows.map((r) => (
              <tr key={r.id} className={`border-b border-line last:border-0 ${r.voided_at ? "text-muted line-through" : ""}`}>
                <td className="px-4 py-3">{pname[r.product_id] ?? "-"}</td>
                <td className="px-4 py-3 tabular-nums">{fmtRupiah(Number(r.price))}</td>
                <td className="px-4 py-3">{fmtDate(r.effective_from)}</td>
                <td className="px-4 py-3">{r.effective_to ? fmtDate(r.effective_to) : "-"}</td>
                <td className="px-4 py-3 no-underline">{state(r)}</td>
                <td className="px-4 py-3">{r.voided_at ? `Dibatalkan: ${r.void_reason}` : r.note ?? ""}</td>
                <td className="px-4 py-3">{canEdit && latest.get(r.product_id) === r.id ? <VoidCustomerPrice customerId={customerId} priceId={r.id} /> : null}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
