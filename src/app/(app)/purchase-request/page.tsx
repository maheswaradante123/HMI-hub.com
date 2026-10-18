import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { LINE_LABEL, LINE_STATUSES, LINE_STYLE, isDead, weekLabel, type LineStatus } from "@/lib/pr/lines";

type Item = { id: string; pr_id: string; line_no: number; ac: string; code: string; item_name: string; estimated_price: number | null; qty: number; status: string; pay_method: string };
type Sheet = { id: string; doc_number: string; request_date: string; status: string; pr_items: Item[] };
const rp = (n: number) => "Rp " + Math.round(n).toLocaleString("id-ID");
const pill = (s: string) => <span className={`inline-block whitespace-nowrap rounded-full px-3 py-0.5 text-sm font-semibold ${LINE_STYLE[s as LineStatus] ?? ""}`}>{LINE_LABEL[s as LineStatus] ?? s}</span>;

export default async function PrListPage({ searchParams }: { searchParams: Promise<{ tab?: string; status?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("purchase_request", "view")) return <Forbidden roleName={session.roleName} what="Purchase Request" />;
  const seeAll = session.can("purchase_request_all", "view");
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("purchase_requests")
    .select("id, doc_number, request_date, status, pr_items(id, pr_id, line_no, ac, code, item_name, estimated_price, qty, status, pay_method)")
    .is("deleted_at", null)
    .order("request_date", { ascending: false }).order("doc_number", { ascending: false })
    .limit(60);
  const sheets = ((data ?? []) as unknown as Sheet[]).filter((s) => s.pr_items.length > 0);
  const all = sheets.flatMap((s) => s.pr_items.map((i) => ({ ...i, sheet: s })));
  const tab = sp.tab === "item" || (sp.status && !sp.tab) ? "item" : "sheet";
  const filter = sp.status && LINE_STATUSES.includes(sp.status as LineStatus) ? sp.status : "";
  const waiting = all.filter((i) => i.status === "SUBMITTED").length;
  const list = all.filter((i) => !filter || i.status === filter);
  const count = (rows: Item[], s: string) => rows.filter((i) => i.status === s).length;
  const tabCls = (on: boolean) => `rounded-full px-4 py-1.5 font-semibold ${on ? "bg-white text-black" : "border border-line hover:bg-background"}`;

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold">Purchase Request</h1>
          <p className="mt-1 text-muted">Satu lembar PR per minggu. User meminta barang, Purchasing mengajukan ke Owner. Status dicatat per barang.</p>
        </div>
        {session.can("purchase_request", "create") && (
          <Link href="/purchase-request/baru" className="rounded-md bg-brand px-5 py-3 text-lg font-semibold text-white hover:bg-brand-dark">+ Tambah Barang ke PR Minggu Ini</Link>
        )}
      </div>
      {!seeAll && <p className="mt-2 text-muted">Hanya barang yang Anda minta yang ditampilkan.</p>}
      {session.can("purchase_request", "approve") && waiting > 0 && (
        <p className="mt-4 rounded-md bg-warn-bg px-4 py-3"><b>{waiting} barang menunggu persetujuan Owner.</b> Buka lembar PR, centang barangnya, lalu pilih Setujui atau Tolak.</p>
      )}

      <div className="mt-5 flex flex-wrap gap-2" role="tablist">
        <Link href="/purchase-request" className={tabCls(tab === "sheet")} role="tab" aria-selected={tab === "sheet"}>Lembar PR <span className="opacity-70">{sheets.length}</span></Link>
        <Link href="/purchase-request?tab=item" className={tabCls(tab === "item")} role="tab" aria-selected={tab === "item"}>Semua Barang <span className="opacity-70">{all.length}</span></Link>
      </div>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat. Muat ulang halaman.</p>
      ) : tab === "sheet" ? (
        sheets.length === 0 ? (
          <p className="mt-6 rounded-md border border-line bg-surface px-4 py-6">Belum ada Purchase Request.{session.can("purchase_request", "create") && " Klik tombol Tambah Barang untuk memulai."}</p>
        ) : (
          <div className="mt-5 overflow-x-auto rounded-lg border border-line bg-surface">
            <table className="w-full min-w-[900px] text-left text-lg">
              <thead className="border-b border-line bg-background"><tr>
                {["Nomor PR", "Periode", "Barang", "Draft", "Diajukan", "Approved", "Order / Received", "Closed", "Total"].map((h) => <th key={h} scope="col" className={`px-4 py-3 text-sm font-semibold uppercase tracking-wide text-muted ${h === "Total" || h === "Barang" ? "text-right" : ""}`}>{h}</th>)}
              </tr></thead>
              <tbody>
                {sheets.map((s) => {
                  const rows = s.pr_items;
                  const total = rows.reduce((a, i) => a + (isDead(i.status) ? 0 : Number(i.qty) * Number(i.estimated_price ?? 0)), 0);
                  const dash = (n: number) => (n ? n : "-");
                  return (
                    <tr key={s.id} className="border-b border-line last:border-b-0">
                      <td className="px-4 py-3"><Link href={`/purchase-request/${s.id}`} className="font-semibold text-brand underline">{s.doc_number}</Link></td>
                      <td className="px-4 py-3">{weekLabel(s.request_date)}</td>
                      <td className="px-4 py-3 text-right">{rows.length}</td>
                      <td className="px-4 py-3">{dash(count(rows, "DRAFT"))}</td>
                      <td className="px-4 py-3">{dash(count(rows, "SUBMITTED"))}</td>
                      <td className="px-4 py-3">{dash(count(rows, "APPROVED"))}</td>
                      <td className="px-4 py-3">{dash(count(rows, "ORDERED") + count(rows, "RECEIVED"))}</td>
                      <td className="px-4 py-3">{dash(count(rows, "CLOSED"))}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right tabular-nums">{rp(total)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )
      ) : (
        <div className="mt-5">
          <div className="mb-4 flex flex-wrap gap-2">
            <Link href="/purchase-request?tab=item" className={tabCls(!filter)}>Semua <span className="opacity-70">{all.length}</span></Link>
            {LINE_STATUSES.map((s) => (
              <Link key={s} href={`/purchase-request?tab=item&status=${s}`} className={tabCls(filter === s)}>{LINE_LABEL[s]} <span className="opacity-70">{all.filter((i) => i.status === s).length}</span></Link>
            ))}
          </div>
          {list.length === 0 ? <p className="rounded-md border border-line bg-surface px-4 py-6">Tidak ada barang dengan status ini.</p> : (
            <div className="overflow-x-auto rounded-lg border border-line bg-surface">
              <table className="w-full min-w-[900px] text-left">
                <thead className="border-b border-line bg-background"><tr>
                  {["A/C", "Kode", "Description", "Amount", "Nomor PR", "Status", "Pembelian"].map((h) => <th key={h} scope="col" className={`px-4 py-3 text-sm font-semibold uppercase tracking-wide text-muted ${h === "Amount" ? "text-right" : ""}`}>{h}</th>)}
                </tr></thead>
                <tbody>
                  {list.map((i) => (
                    <tr key={i.id} className={`border-b border-line last:border-b-0 ${isDead(i.status) ? "opacity-60" : ""}`}>
                      <td className="px-4 py-3 font-semibold italic">{i.ac}</td>
                      <td className="px-4 py-3 font-semibold">{i.code}</td>
                      <td className="px-4 py-3">{i.item_name}</td>
                      <td className="whitespace-nowrap px-4 py-3 text-right tabular-nums">{rp(Number(i.qty) * Number(i.estimated_price ?? 0))}</td>
                      <td className="px-4 py-3"><Link href={`/purchase-request/${i.sheet.id}`} className="text-brand underline">{i.sheet.doc_number}</Link></td>
                      <td className="px-4 py-3">{pill(i.status)}</td>
                      <td className="px-4 py-3">{i.pay_method}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
      <p className="mt-4 text-sm text-muted">Menampilkan sampai 60 lembar terbaru.</p>
    </div>
  );
}
