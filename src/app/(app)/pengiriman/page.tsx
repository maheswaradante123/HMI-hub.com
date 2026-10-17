import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { DocStatusBadge } from "@/components/doc-status-badge";
import { fmtDate, fmtDateTime } from "@/lib/docs/format";

export default async function DeliveryPage() {
  const session = await requireSession();
  if (!session.can("delivery", "view") || !session.can("packing_list", "view")) return <Forbidden roleName={session.roleName} what="Pengiriman" />;
  const supabase = await createClient();
  const { data } = await supabase.from("packing_lists").select("id, doc_number, pack_date, status, driver_name, vehicle_plate, delivered_at, customers(name)")
    .in("status", ["PACKED", "DELIVERED"]).is("deleted_at", null).order("created_at", { ascending: false }).limit(200);
  const rows = (data ?? []) as unknown as { id: string; doc_number: string; pack_date: string; status: string; driver_name: string | null; vehicle_plate: string | null; delivered_at: string | null; customers: { name: string } | { name: string }[] | null }[];
  return (
    <div>
      <h1 className="text-3xl font-bold">Pengiriman</h1>
      <p className="mt-1 max-w-3xl text-muted">Packing list yang sudah dikemas. Tandai terkirim dari halaman packing list setelah barang diterima customer.</p>
      <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background"><tr>
            {["Packing list", "Tanggal", "Customer", "Sopir", "Plat", "Status", "Terkirim"].map((h) => <th key={h} scope="col" className="px-4 py-3">{h}</th>)}
          </tr></thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={7} className="px-4 py-6">Belum ada pengiriman.</td></tr>}
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-line last:border-0">
                <td className="px-4 py-3"><Link href={`/d/pl/${r.id}`} className="font-semibold text-brand underline">{r.doc_number}</Link></td>
                <td className="px-4 py-3">{fmtDate(r.pack_date)}</td>
                <td className="px-4 py-3">{(Array.isArray(r.customers) ? r.customers[0] : r.customers)?.name}</td>
                <td className="px-4 py-3">{r.driver_name ?? "-"}</td><td className="px-4 py-3">{r.vehicle_plate ?? "-"}</td>
                <td className="px-4 py-3"><DocStatusBadge status={r.status} /></td>
                <td className="px-4 py-3">{r.delivered_at ? fmtDateTime(r.delivered_at) : "-"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
