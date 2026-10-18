import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { PdfPreview } from "@/components/qurban/pdf-preview";
import { PrSheet, type SheetItem } from "@/components/pr-sheet";
import { LINE_LABEL, weekLabel, type LineStatus } from "@/lib/pr/lines";
import { dateTimeId } from "@/lib/pr/constants";
import { loadNames } from "@/lib/pr/data";
import { todayJakarta } from "@/lib/pricing/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function PrSheetPage({
  params, searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ok?: string }>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  if (!UUID.test(id)) notFound();
  const session = await requireSession();
  const supabase = await createClient();
  const { data: sheet } = await supabase
    .from("purchase_requests")
    .select("id, doc_number, request_date, status, deleted_at, pr_items(id, line_no, item_date, ac, code, item_name, estimated_price, qty, unit, status, pay_method, proof, requester_id, units(name))")
    .eq("id", id).maybeSingle();
  if (!sheet || sheet.deleted_at) notFound();

  type Raw = { id: string; line_no: number; item_date: string; ac: string; code: string; item_name: string; estimated_price: number | null; qty: number; unit: string | null; status: string; pay_method: string; proof: string | null; requester_id: string; units: { name: string } | null };
  const raw = [...((sheet.pr_items as unknown as Raw[]) ?? [])].sort((a, b) => a.line_no - b.line_no);
  const ids = raw.map((r) => r.id);
  const [names, journals, history] = await Promise.all([
    loadNames(supabase, raw.map((r) => r.requester_id)),
    ids.length ? supabase.rpc("pr_item_journals", { p_ids: ids }) : Promise.resolve({ data: [] }),
    supabase.from("pr_status_history").select("id, item_id, from_status, to_status, note, changed_by, changed_at").eq("pr_id", id).order("id", { ascending: false }).limit(60),
  ]);
  const jmap = new Map<string, string>(((journals.data ?? []) as { pr_item_id: string; journal_number: string }[]).map((j) => [j.pr_item_id, j.journal_number]));
  const items: SheetItem[] = raw.map((r) => ({
    id: r.id, ac: r.ac, code: r.code, desc: r.item_name, price: Number(r.estimated_price ?? 0), qty: Number(r.qty), unit: r.unit ?? r.units?.name ?? "",
    status: r.status, requester: (names[r.requester_id] ?? "-").split(" ")[0], requesterId: r.requester_id, pay: r.pay_method, proof: r.proof ?? "", cpj: jmap.get(r.id) ?? "", date: r.item_date,
  }));
  const hnames = await loadNames(supabase, (history.data ?? []).map((h) => h.changed_by as string));
  const itemName = new Map(raw.map((r) => [r.id, r.item_name]));
  const canExport = session.can("purchase_request", "export");
  const canAdd = session.can("purchase_request", "create") && sheet.status === "OPEN" && sheet.doc_number === (await supabase.rpc("pr_sheet_number", { p_date: todayJakarta() })).data;
  const label = (s: string | null) => (s ? (LINE_LABEL[s as LineStatus] ?? s) : "dibuat");
  const OK: Record<string, string> = {};
  if (sp.ok?.startsWith("ditambah-")) OK[sp.ok] = `${sp.ok.slice(9)} barang masuk ke ${sheet.doc_number} (Draft).`;

  return (
    <div>
      <Link href="/purchase-request" className="underline">&larr; Semua Purchase Request</Link>
      <div className="mt-3 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold">{sheet.doc_number}</h1>
          <p className="text-muted">{weekLabel(String(sheet.request_date))} · {items.length} barang</p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          {canExport && (<>
            <PdfPreview href={`/purchase-request/${id}/export`} title={`Purchase Request ${sheet.doc_number}`} xlsx={`/purchase-request/${id}/export`} />
            <a href={`/purchase-request/${id}/export?format=pdf`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">PDF</a>
            <a href={`/purchase-request/${id}/export`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">Excel</a>
          </>)}
          {canAdd && <Link href="/purchase-request/baru" className="rounded-md bg-brand px-5 py-2.5 font-semibold text-white hover:bg-brand-dark">+ Tambah barang</Link>}
        </div>
      </div>
      {sp.ok && OK[sp.ok] && <p role="status" className="mt-4 rounded-md bg-ok-bg px-4 py-3 text-ok">{OK[sp.ok]}</p>}

      <div className="mt-5">
        <PrSheet sheetId={id} items={items} flags={{
          canEdit: session.can("purchase_request", "edit"), canApprove: session.can("purchase_request", "approve"), canDelete: session.can("purchase_request", "delete"),
          canCreateJournal: session.can("cpj_journal", "create"), userId: session.userId, legacy: sheet.status !== "OPEN",
        }} />
      </div>
      <p className="mt-3 text-sm text-muted">
        Alur: Draft → Diajukan (Purchasing) → Approved / Ditolak (Owner) → Order → Received → dibayar lewat Cash Payment Journal → Closed.
        Barang yang nasibnya berbeda tetap dalam satu lembar. Lembar PR dibuat per minggu (001 = minggu pertama bulan itu).
      </p>

      {(history.data ?? []).length > 0 && (
        <details className="mt-6 rounded-lg border border-line bg-surface p-4">
          <summary className="cursor-pointer text-lg font-semibold">Riwayat status ({(history.data ?? []).length} terakhir)</summary>
          <ul className="mt-3 space-y-1">
            {(history.data ?? []).map((h) => (
              <li key={h.id as number} className="text-base">
                <span className="text-muted">{dateTimeId(h.changed_at as string)}</span> · {itemName.get(h.item_id as string) ?? "Lembar"}: {label(h.from_status as string | null)} → <b>{label(h.to_status as string)}</b>
                {" "}oleh {hnames[h.changed_by as string] ?? "-"}{h.note ? ` — ${h.note}` : ""}
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}
