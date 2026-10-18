import Link from "next/link";
import type { createClient } from "@/lib/supabase/server";
import { DocStatusBadge } from "@/components/doc-status-badge";

type Supa = Awaited<ReturnType<typeof createClient>>;
type D = { id: string; doc_number: string; status: string };
const one = <T,>(v: T | T[] | null | undefined): T | null => (Array.isArray(v) ? v[0] ?? null : v ?? null);

// Alur dokumen satu pesanan: RO -> Production Order -> Packing List -> (Invoice | Surat Jalan, berjalan paralel).
export async function DocFlow({ supabase, plId, current }: { supabase: Supa; plId: string; current: "pl" | "do" }) {
  const { data: pl } = await supabase
    .from("packing_lists")
    .select("id, doc_number, status, request_orders(id, doc_number, status), production_orders(id, doc_number, status)")
    .eq("id", plId).is("deleted_at", null).maybeSingle();
  if (!pl) return null;
  const [{ data: invs }, { data: dos }] = await Promise.all([
    supabase.from("invoices").select("id, doc_number, status").eq("pl_id", plId).is("deleted_at", null).neq("status", "VOID").order("created_at"),
    supabase.from("delivery_orders").select("id, doc_number, status").eq("pl_id", plId).is("deleted_at", null).neq("status", "VOID").order("created_at"),
  ]);
  const ro = one(pl.request_orders as unknown as D | D[] | null);
  const po = one(pl.production_orders as unknown as D | D[] | null);
  const chip = (label: string, href: string, d: D, here = false) => (
    <Link key={d.id} href={href} className={`flex flex-col gap-1 rounded-lg border px-4 py-2 ${here ? "border-brand bg-background" : "border-line bg-surface"} hover:bg-background`}>
      <span className="text-sm text-muted">{label}</span>
      <span className="font-semibold">{d.doc_number}</span>
      <DocStatusBadge status={d.status} />
    </Link>
  );
  const none = (label: string) => (
    <div className="flex flex-col gap-1 rounded-lg border border-dashed border-line px-4 py-2"><span className="text-sm text-muted">{label}</span><span className="text-muted">Belum dibuat</span></div>
  );
  const arrow = <span aria-hidden className="self-center text-xl text-muted">→</span>;
  return (
    <section className="no-print mt-6" aria-labelledby="alur">
      <h2 id="alur" className="mb-3 text-2xl font-bold">Alur dokumen</h2>
      <div className="flex flex-wrap items-stretch gap-2">
        {ro ? chip("Request Order", `/d/ro/${ro.id}`, ro) : none("Request Order")}{arrow}
        {po ? chip("Production Order", `/d/prod/${po.id}`, po) : none("Production Order")}{arrow}
        {chip("Packing List", `/d/pl/${pl.id}`, pl as unknown as D, current === "pl")}{arrow}
        <div className="flex flex-col gap-2">
          {(invs ?? []).length ? (invs as D[]).map((i) => chip("Invoice", `/d/inv/${i.id}`, i)) : none("Invoice")}
          {(dos ?? []).length ? (dos as D[]).map((d) => chip("Surat Jalan", `/d/do/${d.id}`, d, current === "do")) : none("Surat Jalan")}
        </div>
      </div>
    </section>
  );
}

const STEPS: [string, string][] = [["DRAFT", "Draf"], ["SENT", "Diterbitkan"], ["RECEIVED", "Barang diterima"], ["ARCHIVED", "Scan di Google Drive"]];
export function DoSteps({ status }: { status: string }) {
  if (status === "VOID") return null;
  const at = STEPS.findIndex(([s]) => s === status);
  return (
    <ol className="no-print mt-6 grid gap-2 md:grid-cols-4" aria-label="Tahap surat jalan">
      {STEPS.map(([s, label], i) => (
        <li key={s} className={`rounded-lg border px-4 py-3 ${i < at ? "border-line bg-surface" : i === at ? "border-brand bg-surface font-semibold" : "border-dashed border-line text-muted"}`}>
          <span className="text-sm text-muted">Tahap {i + 1}</span>
          <div>{i < at ? "✓ " : ""}{label}</div>
        </li>
      ))}
    </ol>
  );
}
