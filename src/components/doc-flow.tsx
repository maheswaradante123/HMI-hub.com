import Link from "next/link";
import type { createClient } from "@/lib/supabase/server";
import { DocStatusBadge } from "@/components/doc-status-badge";

type Supa = Awaited<ReturnType<typeof createClient>>;
type D = { id: string; doc_number: string; status: string };

export type FlowKind = "ro" | "prod" | "pl" | "do" | "inv";
export type FlowAccess = Record<FlowKind, boolean>;

// Alur dokumen satu pesanan: RO -> Production Order -> Packing List -> (Invoice | Surat Jalan, berjalan paralel).
// Bisa dipasang di halaman dokumen mana pun dalam rantai; dokumen yang sedang dibuka diberi bingkai tebal.
export async function DocFlow({ supabase, kind, id, access }: { supabase: Supa; kind: FlowKind; id: string; access: FlowAccess }) {
  let roId: string | null = null;
  let poIds: string[] = [];
  let plIds: string[] = [];
  if (kind === "ro") roId = id;
  else if (kind === "prod") {
    poIds = [id];
    const { data } = await supabase.from("production_orders").select("ro_id").eq("id", id).maybeSingle();
    roId = (data?.ro_id as string | null) ?? null;
  } else {
    let plId: string | null = null;
    if (kind === "pl") plId = id;
    else if (kind === "do") {
      const { data } = await supabase.from("delivery_orders").select("pl_id").eq("id", id).maybeSingle();
      plId = (data?.pl_id as string | null) ?? null;
    } else {
      const { data } = await supabase.from("invoices").select("pl_id, ro_id").eq("id", id).maybeSingle();
      plId = (data?.pl_id as string | null) ?? null;
      roId = (data?.ro_id as string | null) ?? null;
    }
    if (plId) {
      plIds = [plId];
      const { data } = await supabase.from("packing_lists").select("ro_id, po_id").eq("id", plId).maybeSingle();
      roId = roId ?? (data?.ro_id as string | null) ?? null;
      if (data?.po_id) poIds = [data.po_id as string];
      if (!roId && data?.po_id) {
        const { data: po } = await supabase.from("production_orders").select("ro_id").eq("id", data.po_id as string).maybeSingle();
        roId = (po?.ro_id as string | null) ?? null;
      }
    }
  }

  const sel = "id, doc_number, status";
  const orIn = (col: string, ids: string[]) => (ids.length ? [`${col}.in.(${ids.join(",")})`] : []);
  const [{ data: ro }, { data: pos }] = await Promise.all([
    roId ? supabase.from("request_orders").select(sel).eq("id", roId).is("deleted_at", null).maybeSingle() : Promise.resolve({ data: null }),
    (() => {
      const conds = [...(roId ? [`ro_id.eq.${roId}`] : []), ...orIn("id", poIds)];
      return conds.length ? supabase.from("production_orders").select(sel).or(conds.join(",")).is("deleted_at", null).order("created_at") : Promise.resolve({ data: [] });
    })(),
  ]);
  const poAll = ((pos ?? []) as D[]).map((x) => x.id);
  const plConds = [...(roId ? [`ro_id.eq.${roId}`] : []), ...orIn("po_id", poAll), ...orIn("id", plIds)];
  const { data: pls } = plConds.length ? await supabase.from("packing_lists").select(sel).or(plConds.join(",")).is("deleted_at", null).order("created_at") : { data: [] };
  const plAll = ((pls ?? []) as D[]).map((x) => x.id);
  const [{ data: invs }, { data: dos }] = plAll.length || kind === "inv"
    ? await Promise.all([
        supabase.from("invoices").select(sel).or([...orIn("pl_id", plAll), ...(kind === "inv" ? [`id.eq.${id}`] : [])].join(",")).is("deleted_at", null).order("created_at"),
        plAll.length ? supabase.from("delivery_orders").select(sel).in("pl_id", plAll).is("deleted_at", null).order("created_at") : Promise.resolve({ data: [] }),
      ])
    : [{ data: [] }, { data: [] }];
  const keep = (list: unknown, k: FlowKind) => ((list ?? []) as D[]).filter((d) => d.status !== "VOID" || (kind === k && d.id === id));

  const chip = (label: string, href: string, d: D, here: boolean) => (
    <Link key={d.id} href={href} aria-current={here ? "page" : undefined} className={`flex flex-col gap-1 rounded-lg px-4 py-2 hover:bg-background ${here ? "border-2 border-brand bg-background" : "border border-line bg-surface"}`}>
      <span className="text-sm text-muted">{label}</span>
      <span className="font-semibold">{d.doc_number}</span>
      <DocStatusBadge status={d.status} />
    </Link>
  );
  const none = (label: string, k: FlowKind) => (
    <div key={`none-${k}`} className="flex flex-col gap-1 rounded-lg border border-dashed border-line px-4 py-2">
      <span className="text-sm text-muted">{label}</span>
      <span className="text-muted">{access[k] ? "Belum dibuat" : "Tidak ada akses"}</span>
    </div>
  );
  const column = (label: string, k: FlowKind, base: string, list: D[]) =>
    access[k] && list.length ? list.map((d) => chip(label, `${base}/${d.id}`, d, kind === k && d.id === id)) : [none(label, k)];
  const arrow = <span aria-hidden className="self-center text-xl text-muted">→</span>;
  return (
    <section className="no-print mt-6" aria-labelledby="alur">
      <h2 id="alur" className="mb-3 text-2xl font-bold">Alur dokumen</h2>
      <div className="flex flex-wrap items-stretch gap-2">
        <div className="flex flex-col gap-2">{column("Request Order", "ro", "/d/ro", ro ? [ro as D] : [])}</div>{arrow}
        <div className="flex flex-col gap-2">{column("Production Order", "prod", "/d/prod", (pos ?? []) as D[])}</div>{arrow}
        <div className="flex flex-col gap-2">{column("Packing List", "pl", "/d/pl", (pls ?? []) as D[])}</div>{arrow}
        <div className="flex flex-col gap-2">
          {column("Invoice", "inv", "/d/inv", keep(invs, "inv"))}
          {column("Surat Jalan", "do", "/d/do", keep(dos, "do"))}
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
