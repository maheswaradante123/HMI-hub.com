import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { PdfPreview } from "@/components/qurban/pdf-preview";
import { DocStatusBadge } from "@/components/doc-status-badge";
import { DocActions, PrintButton } from "@/components/doc-actions";
import { CONFIGS } from "@/lib/docs/config";
import { cellText, fmtQty, fmtRupiah, isNumericKind, fmtDateTime } from "@/lib/docs/format";
import type { Rule } from "@/lib/docs/rules";
import { pmtTotals, PMT_COLS } from "@/lib/docs/pmt";
import { loadNames } from "@/lib/pr/data";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTICES: Record<string, string> = { disimpan: "Draf tersimpan.", status: "Status dokumen diperbarui." };

const NEXT: Record<string, { when: string[]; label: string; href: (id: string) => string; module: string }[]> = {
  ro: [
    { when: ["CONFIRMED"], label: "Buat Production Order", href: (id) => `/d/prod/baru?ro=${id}`, module: "production_order" },
    { when: ["CONFIRMED"], label: "Buat Packing List", href: (id) => `/d/pl/baru?ro=${id}`, module: "packing_list" },
  ],
  prod: [{ when: ["APPROVED"], label: "Buat Packing List", href: (id) => `/d/pl/baru?po=${id}`, module: "packing_list" }],
  pl: [{ when: ["PACKED", "DELIVERED"], label: "Buat Invoice", href: (id) => `/d/inv/baru?pl=${id}`, module: "invoice" }],
  cw: [
    { when: ["FINAL"], label: "Buat Analisa Pembelian", href: (id) => `/d/ap/baru?cw=${id}`, module: "purchase_analysis" },
    { when: ["FINAL"], label: "Jual non-karkas", href: (id) => `/d/ncs/baru?cw=${id}`, module: "noncarcass_sale" },
  ],
  inv: [{ when: ["ISSUED", "PARTIAL"], label: "Catat pembayaran (CRJ)", href: (id) => `/d/crj/baru?inv=${id}`, module: "crj" }],
  ncs: [{ when: ["CONFIRMED"], label: "Catat pembayaran (CRJ)", href: (id) => `/d/crj/baru?ncs=${id}`, module: "crj" }],
};

export default async function DocDetailPage({
  params, searchParams,
}: {
  params: Promise<{ slug: string; id: string }>;
  searchParams: Promise<{ ok?: string }>;
}) {
  const { slug, id } = await params;
  const sp = await searchParams;
  const cfg = CONFIGS[slug];
  if (!cfg || !UUID.test(id)) notFound();
  const session = await requireSession();
  if (!session.can(cfg.module, "view")) return <Forbidden roleName={session.roleName} what={cfg.title} />;

  const supabase = await createClient();
  const childSel = cfg.children.map((c) => `${c.table}(${c.select})`).join(", ");
  const { data } = await supabase.from(cfg.table).select(`${cfg.select}${childSel ? ", " + childSel : ""}`).eq("id", id).is("deleted_at", null).maybeSingle();
  const doc = data as unknown as Record<string, unknown> | null;
  if (!doc) notFound();
  const status = String(doc.status);

  const [{ data: rules }, { data: history }, analysis] = await Promise.all([
    supabase.from("doc_rules").select("*").eq("doc_type", cfg.type).eq("from_status", status),
    supabase.from("doc_status_history").select("*").eq("doc_type", cfg.type).eq("doc_id", id).order("id"),
    cfg.extra === "analysis" ? supabase.from("v_purchase_analysis").select("*").eq("id", id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const allowed = ((rules ?? []) as Rule[]).filter((r) => session.can(r.module, r.action));
  const names = await loadNames(supabase, (history ?? []).map((h) => h.changed_by as string));
  const canEdit = status === "DRAFT" && session.can(cfg.module, "edit");
  const next = (NEXT[slug] ?? []).filter((n) => n.when.includes(status) && session.can(n.module, "create"));
  const a = analysis.data as Record<string, number | string> | null;

  return (
    <div className="max-w-5xl">
      <Link href={`/d/${slug}`} className="no-print underline">&larr; Semua {cfg.title}</Link>
      <div className="mt-3 flex flex-wrap items-center gap-4">
        <h1 className="text-3xl font-bold">{String(doc.doc_number)}</h1>
        <DocStatusBadge status={status} />
      </div>
      {slug === "inv" && session.can("invoice", "export") && status !== "DRAFT" && (
        <p className="no-print mt-4 flex flex-wrap items-center gap-3">
          <PdfPreview href={`/d/inv/${id}/export`} title={`Invoice ${String(doc.doc_number)}`} xlsx={`/d/inv/${id}/export`} />
          <a href={`/d/inv/${id}/export?format=pdf`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">PDF</a>
          <a href={`/d/inv/${id}/export`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">Excel</a>
        </p>
      )}
      {(slug === "ro" || slug === "prod") && session.can(slug === "ro" ? "ro" : "production_order", "export") && (
        <p className="no-print mt-4 flex flex-wrap items-center gap-3">
          <PdfPreview href={`/d/${slug}/${id}/export`} title={`${slug === "ro" ? "Realisasi Order" : "Production Order"} ${String(doc.doc_number)}`} xlsx={`/d/${slug}/${id}/export`} />
          <a href={`/d/${slug}/${id}/export?format=pdf`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">PDF</a>
          <a href={`/d/${slug}/${id}/export`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">Excel</a>
        </p>
      )}
      {slug === "pmt" && session.can("store_income", "export") && (
        <p className="no-print mt-4 flex flex-wrap items-center gap-3">
          <PdfPreview href={`/d/pmt/${id}/export`} title={`Pemasukan Toko ${String(doc.doc_number)}`} xlsx={`/d/pmt/${id}/export`} />
          <a href={`/d/pmt/${id}/export?format=pdf`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">PDF</a>
          <a href={`/d/pmt/${id}/export`} className="rounded-full border border-line bg-surface px-4 py-1.5 font-semibold hover:bg-background">Excel</a>
        </p>
      )}
      {sp.ok && NOTICES[sp.ok] && <p role="status" className="no-print mt-4 rounded-md bg-warn-bg px-4 py-3">{NOTICES[sp.ok]}</p>}

      <dl className="mt-6 grid gap-x-8 gap-y-3 rounded-lg border border-line bg-surface p-5 md:grid-cols-2">
        {cfg.summary.map((c) => (
          <div key={c.path}><dt className="text-muted">{c.label}</dt><dd className="text-lg">{cellText(c, doc)}</dd></div>
        ))}
      </dl>

      {slug === "pmt" && (() => {
        const t = pmtTotals((doc.store_income_lines as Record<string, number>[]) ?? [], (doc.store_income_receivables as { amount: number }[]) ?? []);
        const L: Record<string, string> = { cash: "Cash", qris: "QRIS", debit: "Debit", grab: "Grab", tf: "TF Rek HMI", deposited: "Disetor" };
        return (
          <section className="mt-6 rounded-lg border border-line bg-surface p-5" aria-labelledby="tot-pmt">
            <h2 id="tot-pmt" className="text-2xl font-bold">Total</h2>
            <dl className="mt-3 grid gap-x-8 gap-y-2 md:grid-cols-3">
              {PMT_COLS.map((c) => <div key={c}><dt className="text-muted">{L[c]}</dt><dd className="text-lg font-semibold">{fmtRupiah(t[c])}</dd></div>)}
              <div><dt className="text-muted">Uang cash yang harus disetor</dt><dd className="text-lg font-semibold">{fmtRupiah(t.mustDeposit)}</dd></div>
              <div><dt className="text-muted">Total piutang</dt><dd className="text-lg font-semibold">{fmtRupiah(t.receivables)}</dd></div>
              <div><dt className="text-muted">Total Pendapatan</dt><dd className="text-xl font-bold">{fmtRupiah(t.income)}</dd></div>
            </dl>
          </section>
        );
      })()}

      {a && (
        <section className="mt-6" aria-labelledby="hasil">
          <h2 id="hasil" className="text-2xl font-bold">Hasil analisa</h2>
          <dl className="mt-3 grid gap-3 md:grid-cols-3">
            {[
              ["Berat hidup", `${fmtQty(Number(a.live_weight))} kg`], ["Berat karkas", `${fmtQty(Number(a.carcass_weight))} kg`], ["Karkas dari berat hidup", `${fmtQty(Number(a.carcass_pct))}%`],
              ["Berat daging", `${fmtQty(Number(a.meat_weight))} kg`], ["Daging dari karkas", `${fmtQty(Number(a.meat_pct))}%`], ["Harga karkas per kg", fmtRupiah(Number(a.carcass_price_per_kg))],
              ["Hasil penjualan item", fmtRupiah(Number(a.revenue))], ["Penjualan non-karkas", fmtRupiah(Number(a.noncarcass_amount))], ["Total biaya", fmtRupiah(Number(a.cost_total))],
            ].map(([k, v]) => (
              <div key={k} className="rounded-lg border border-line bg-surface p-4"><dt className="text-muted">{k}</dt><dd className="text-xl font-semibold tabular-nums">{v}</dd></div>
            ))}
            <div className={`rounded-lg border-2 p-4 md:col-span-3 ${Number(a.profit) < 0 ? "border-danger bg-danger-bg" : "border-brand bg-surface"}`}>
              <dt className="text-muted">Laba (hasil item + non-karkas − pembelian − biaya)</dt>
              <dd className="text-2xl font-bold tabular-nums">{fmtRupiah(Number(a.profit))}</dd>
            </div>
          </dl>
        </section>
      )}

      {cfg.children.map((c) => {
        const rows = ((doc[c.table] as Record<string, unknown>[] | undefined) ?? []).slice().sort((x, y) => Number(x.line_no) - Number(y.line_no));
        if (rows.length === 0 && !c.required) return null;
        const totalVal = c.total ? rows.reduce((s, r) => s + Number(r[c.total!.qty]) * Number(r[c.total!.price]), 0) : null;
        const sumVal = c.sum ? rows.reduce((s, r) => s + Number(r[c.sum!.field]), 0) : null;
        return (
          <section key={c.key} className="mt-8" aria-labelledby={`t-${c.key}`}>
            <h2 id={`t-${c.key}`} className="text-2xl font-bold">{c.title}</h2>
            <div className="mt-3 overflow-x-auto rounded-lg border border-line bg-surface">
              <table className="w-full text-left text-lg">
                <thead className="border-b border-line bg-background">
                  <tr>{c.columns.map((col) => <th key={col.path} scope="col" className={`px-4 py-3 font-semibold ${isNumericKind(col.kind) ? "text-right" : ""}`}>{col.label}</th>)}</tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={String(r.id)} className="border-b border-line last:border-0">
                      {c.columns.map((col) => <td key={col.path} className={`px-4 py-3 ${isNumericKind(col.kind) ? "text-right tabular-nums" : ""}`}>{cellText(col, r)}</td>)}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {totalVal !== null && <p className="mt-2 text-right text-lg font-semibold">{c.total!.label}: {fmtRupiah(totalVal)}</p>}
            {sumVal !== null && <p className="mt-2 text-right text-lg font-semibold">{c.sum!.label}: {c.columns.find((x) => x.path === c.sum!.field)?.kind === "money" ? fmtRupiah(sumVal) : `${fmtQty(sumVal)} kg`}</p>}
          </section>
        );
      })}

      <div className="no-print mt-8 flex flex-wrap gap-3">
        {canEdit && <Link href={`/d/${slug}/${id}/ubah`} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">Ubah draf</Link>}
        {next.map((n) => <Link key={n.label} href={n.href(id)} className="rounded-md border-2 border-brand px-5 py-2.5 text-lg font-semibold text-brand hover:bg-background">{n.label}</Link>)}
        <PrintButton />
      </div>

      {allowed.length > 0 && (
        <section className="no-print mt-8" aria-labelledby="aksi">
          <h2 id="aksi" className="mb-3 text-2xl font-bold">Tindakan</h2>
          <DocActions slug={slug} id={id} rules={allowed.map((r) => ({ to: r.to_status, label: r.label, needsNote: r.needs_note }))} />
        </section>
      )}

      <section className="mt-10" aria-labelledby="riwayat">
        <h2 id="riwayat" className="text-2xl font-bold">Riwayat status</h2>
        <ol className="mt-3 space-y-2">
          {(history ?? []).map((h) => (
            <li key={String(h.id)} className="rounded-md border border-line bg-surface px-4 py-3">
              <div className="flex flex-wrap items-center gap-3">
                <DocStatusBadge status={String(h.to_status)} />
                <span>{names[h.changed_by as string] ?? "-"}, {fmtDateTime(String(h.changed_at))}</span>
              </div>
              {h.note ? <p className="mt-1 text-muted">Catatan: {String(h.note)}</p> : null}
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
