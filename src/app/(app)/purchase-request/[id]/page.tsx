import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { StatusBadge } from "@/components/status-badge";
import { PrActions, SupplierPicker } from "@/components/pr-actions";
import { ClosePrButton } from "@/components/doc-actions";
import { PRIORITY_LABEL, STATUS_LABEL, dateId, dateTimeId, rupiah, type PrStatus } from "@/lib/pr/constants";
import { loadNames } from "@/lib/pr/data";
import { discardPr } from "../actions";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTICES: Record<string, string> = {
  diajukan: "PR berhasil diajukan dan menunggu persetujuan Owner.",
  "draf-tersimpan": "Draf tersimpan. PR ini belum diajukan.",
  ditutup: "PR ditutup. Seluruh proses pembelian selesai.",
};

export default async function PrDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string; e?: string }>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  if (!UUID.test(id)) notFound();

  const session = await requireSession();
  const supabase = await createClient();
  const { data: pr } = await supabase
    .from("purchase_requests")
    .select("*, pr_items(*)")
    .eq("id", id)
    .maybeSingle();
  if (!pr || pr.deleted_at) notFound();

  const [{ data: history }, { data: units }, { data: suppliers }, { data: departments }] = await Promise.all([
    supabase.from("pr_status_history").select("*").eq("pr_id", id).order("id"),
    supabase.from("units").select("id, name"),
    supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
    supabase.from("departments").select("id, name"),
  ]);
  const names = await loadNames(supabase, [
    pr.requester_id, pr.decided_by, ...(history ?? []).map((h) => h.changed_by as string),
  ]);
  const unitName = Object.fromEntries((units ?? []).map((u) => [u.id, u.name]));
  const deptName = departments?.find((d) => d.id === pr.department_id)?.name ?? "-";
  const supplierName = Object.fromEntries((suppliers ?? []).map((s) => [s.id, s.name]));

  const items = [...(pr.pr_items ?? [])].sort((a, b) => a.line_no - b.line_no);
  const total = items.reduce((s, i) => s + Number(i.qty) * Number(i.estimated_price ?? 0), 0);

  const status = pr.status as PrStatus;
  const isMine = pr.requester_id === session.userId;
  const canApprove = session.can("purchase_request", "approve");
  const canProcess = session.can("purchase_request", "edit");
  const canPickSupplier = canProcess && (status === "APPROVED" || status === "ORDERED") && suppliers && suppliers.length > 0;
  const decisionLabel = status === "REJECTED" ? "Ditolak oleh" : "Disetujui oleh";
  const hasDecision = pr.decided_by && (status !== "SUBMITTED" && status !== "UNDER_REVIEW");

  return (
    <div className="max-w-5xl">
      <Link href="/purchase-request" className="underline">&larr; Semua Purchase Request</Link>
      <div className="mt-3 flex flex-wrap items-center gap-4">
        <h1 className="text-3xl font-bold">{pr.doc_number}</h1>
        <StatusBadge status={pr.status} />
      </div>

      {sp.ok && NOTICES[sp.ok] && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">{NOTICES[sp.ok]}</p>}
      {sp.e === "gagal" && <p role="alert" className="mt-4 rounded-md bg-danger-bg px-4 py-3 text-danger">Aksi gagal. Silakan coba lagi.</p>}

      <dl className="mt-6 grid gap-x-8 gap-y-3 rounded-lg border border-line bg-surface p-5 md:grid-cols-2">
        <div><dt className="text-muted">Tanggal</dt><dd className="text-lg">{dateId(pr.request_date)}</dd></div>
        <div><dt className="text-muted">Pemohon</dt><dd className="text-lg">{names[pr.requester_id] ?? "-"} ({deptName})</dd></div>
        <div><dt className="text-muted">Prioritas</dt><dd className="text-lg">{PRIORITY_LABEL[pr.priority] ?? pr.priority}</dd></div>
        {hasDecision && (
          <div>
            <dt className="text-muted">{decisionLabel}</dt>
            <dd className="text-lg">{names[pr.decided_by] ?? "-"}{pr.decided_at ? `, ${dateTimeId(pr.decided_at)}` : ""}</dd>
          </div>
        )}
        <div className="md:col-span-2"><dt className="text-muted">Alasan pembelian</dt><dd className="whitespace-pre-line text-lg">{pr.reason}</dd></div>
        {status === "REJECTED" && pr.review_note && (
          <div className="md:col-span-2 rounded-md bg-danger-bg px-4 py-3">
            <dt className="font-semibold text-danger">Alasan penolakan</dt>
            <dd className="whitespace-pre-line text-lg text-danger">{pr.review_note}</dd>
          </div>
        )}
      </dl>

      <h2 className="mb-3 mt-8 text-xl font-bold">Barang yang diminta</h2>
      <div className="overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background">
            <tr>
              {["No", "Barang", "Jumlah", "Estimasi harga", "Subtotal", "Supplier"].map((h) => (
                <th key={h} scope="col" className="px-4 py-3 font-semibold">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {items.map((i) => (
              <tr key={i.id} className="border-b border-line align-top last:border-b-0">
                <td className="px-4 py-3">{i.line_no}</td>
                <td className="px-4 py-3">
                  {i.item_name}
                  {i.notes && <p className="text-base text-muted">{i.notes}</p>}
                </td>
                <td className="whitespace-nowrap px-4 py-3">{Number(i.qty).toLocaleString("id-ID", { maximumFractionDigits: 3 })} {unitName[i.unit_id] ?? ""}</td>
                <td className="whitespace-nowrap px-4 py-3">{i.estimated_price == null ? "-" : rupiah(Number(i.estimated_price))}</td>
                <td className="whitespace-nowrap px-4 py-3">{i.estimated_price == null ? "-" : rupiah(Number(i.qty) * Number(i.estimated_price))}</td>
                <td className="px-4 py-3">
                  {canPickSupplier ? (
                    <SupplierPicker prId={id} itemId={i.id} current={i.supplier_id} suppliers={suppliers!} />
                  ) : (
                    supplierName[i.supplier_id] ?? "-"
                  )}
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t border-line bg-background">
              <td colSpan={4} className="px-4 py-3 text-right font-semibold">Estimasi total</td>
              <td colSpan={2} className="px-4 py-3 text-lg font-bold">{total > 0 ? rupiah(total) : "-"}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      {(status === "DRAFT" && isMine) && (
        <div className="mt-8 flex flex-wrap gap-3">
          <Link href={`/purchase-request/${id}/ubah`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">
            Ubah draf / ajukan
          </Link>
          <form action={discardPr.bind(null, id)}>
            <button type="submit" className="rounded-md border-2 border-danger px-6 py-3 text-lg font-semibold text-danger hover:bg-danger-bg">
              Hapus draf
            </button>
          </form>
        </div>
      )}

      {(canApprove || canProcess) && (
        <div className="mt-8">
          <PrActions prId={id} status={pr.status} canApprove={canApprove} canProcess={canProcess} />
        </div>
      )}

      {(status === "RECEIVED" || status === "PAID") && session.can("cpj", "create") && (
        <div className="mt-8">
          <Link href={`/d/cpj/baru?pr=${id}`} className="inline-block rounded-md border-2 border-brand px-6 py-3 text-lg font-semibold text-brand hover:bg-background">
            Catat pembayaran PR ini (CPJ)
          </Link>
        </div>
      )}
      {status === "PAID" && session.can("cpj", "edit") && (
        <div className="mt-6"><ClosePrButton prId={id} /></div>
      )}

      <h2 className="mb-3 mt-10 text-xl font-bold">Riwayat status</h2>
      <ol className="space-y-2 rounded-lg border border-line bg-surface p-5">
        {(history ?? []).map((h) => (
          <li key={h.id} className="text-lg">
            <span className="font-semibold">{STATUS_LABEL[h.to_status as PrStatus] ?? h.to_status}</span>
            {" "}oleh {names[h.changed_by] ?? "-"}, {dateTimeId(h.changed_at)}
            {h.note && <span className="block text-base text-muted">Catatan: {h.note}</span>}
          </li>
        ))}
      </ol>
    </div>
  );
}
