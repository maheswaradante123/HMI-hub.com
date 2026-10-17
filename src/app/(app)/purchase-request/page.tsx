import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { StatusBadge } from "@/components/status-badge";
import { PRIORITY_LABEL, STATUS_LABEL, dateId, rupiah } from "@/lib/pr/constants";
import { loadNames } from "@/lib/pr/data";

export default async function PrListPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; ok?: string }>;
}) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("purchase_request", "view")) {
    return <Forbidden roleName={session.roleName} what="Purchase Request" />;
  }
  const seeAll = session.can("purchase_request_all", "view");
  const supabase = await createClient();

  let query = supabase
    .from("purchase_requests")
    .select("id, doc_number, request_date, requester_id, priority, status, pr_items(qty, estimated_price)")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(200);
  const filter = sp.status && sp.status in STATUS_LABEL ? sp.status : "";
  if (filter) query = query.eq("status", filter);
  const { data: rows, error } = await query;
  const names = await loadNames(supabase, (rows ?? []).map((r) => r.requester_id));

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-bold">Purchase Request</h1>
        {session.can("purchase_request", "create") && (
          <Link href="/purchase-request/baru" className="rounded-md bg-brand px-5 py-3 text-lg font-semibold text-white hover:bg-brand-dark">
            + Buat Purchase Request
          </Link>
        )}
      </div>
      {!seeAll && <p className="mt-1 text-muted">Hanya PR yang Anda buat yang ditampilkan.</p>}

      {sp.ok === "dihapus" && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">Draf berhasil dihapus.</p>}

      <form className="mt-5 flex flex-wrap items-center gap-3">
        <label htmlFor="status" className="text-lg font-semibold">Status</label>
        <select id="status" name="status" defaultValue={filter} className="rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg">
          <option value="">Semua</option>
          {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Tampilkan</button>
      </form>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat. Muat ulang halaman.</p>
      ) : !rows || rows.length === 0 ? (
        <p className="mt-6 rounded-md border border-line bg-surface px-4 py-6">
          Belum ada Purchase Request{filter ? " dengan status ini" : ""}.
          {session.can("purchase_request", "create") && !filter && " Klik tombol Buat Purchase Request untuk memulai."}
        </p>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>
                {["No. PR", "Tanggal", "Pemohon", "Prioritas", "Estimasi total", "Status"].map((h) => (
                  <th key={h} scope="col" className="px-4 py-3 font-semibold">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const items = (r.pr_items ?? []) as { qty: number; estimated_price: number | null }[];
                const total = items.reduce((s, i) => s + Number(i.qty) * Number(i.estimated_price ?? 0), 0);
                const hasUnpriced = items.some((i) => i.estimated_price == null);
                return (
                  <tr key={r.id} className="border-b border-line last:border-b-0">
                    <td className="px-4 py-3">
                      <Link href={`/purchase-request/${r.id}`} className="font-semibold text-brand underline">{r.doc_number}</Link>
                    </td>
                    <td className="px-4 py-3">{dateId(r.request_date)}</td>
                    <td className="px-4 py-3">{names[r.requester_id] ?? "-"}</td>
                    <td className="px-4 py-3">{PRIORITY_LABEL[r.priority] ?? r.priority}</td>
                    <td className="px-4 py-3">{total > 0 ? rupiah(total) : "-"}{total > 0 && hasUnpriced ? " *" : ""}</td>
                    <td className="px-4 py-3"><StatusBadge status={r.status} /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          <p className="px-4 py-2 text-sm text-muted">* Sebagian barang belum memiliki estimasi harga.</p>
        </div>
      )}
    </div>
  );
}
