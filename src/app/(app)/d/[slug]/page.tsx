import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { DocStatusBadge } from "@/components/doc-status-badge";
import { CONFIGS } from "@/lib/docs/config";
import { cellText, getPath, isNumericKind } from "@/lib/docs/format";
import { DOC_STATUS_LABEL } from "@/lib/docs/status";

export default async function DocListPage({
  params, searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ q?: string; status?: string }>;
}) {
  const { slug } = await params;
  const sp = await searchParams;
  const cfg = CONFIGS[slug];
  if (!cfg) notFound();

  const session = await requireSession();
  if (!session.can(cfg.module, "view")) return <Forbidden roleName={session.roleName} what={cfg.title} />;
  const canCreate = session.can(cfg.module, "create");

  const supabase = await createClient();
  let q = supabase.from(cfg.table).select(cfg.select).is("deleted_at", null).order("created_at", { ascending: false }).limit(200);
  if (cfg.filter) q = cfg.filter.op === "eq" ? q.eq(cfg.filter.column, cfg.filter.value) : q.neq(cfg.filter.column, cfg.filter.value);
  const status = sp.status && cfg.statuses.includes(sp.status) ? sp.status : "";
  if (status) q = q.eq("status", status);
  const term = (sp.q ?? "").replace(/[,()%*\\]/g, " ").trim();
  if (term) q = q.ilike("doc_number", `%${term}%`);
  const { data, error } = await q;
  const rows = (data ?? []) as unknown as Record<string, unknown>[];

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-3xl font-bold">{cfg.title}</h1>
        {canCreate && (
          <Link href={`/d/${slug}/baru`} className="rounded-md bg-brand px-6 py-3 text-lg font-semibold text-white hover:bg-brand-dark">
            + {cfg.singular} baru
          </Link>
        )}
      </div>
      <p className="mt-1 max-w-3xl text-muted">{cfg.intro}</p>

      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        <label htmlFor="q" className="sr-only">Cari nomor</label>
        <input id="q" name="q" defaultValue={term} placeholder="Cari nomor dokumen" className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg" />
        <label htmlFor="status" className="sr-only">Status</label>
        <select id="status" name="status" defaultValue={status} className="rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg">
          <option value="">Semua status</option>
          {cfg.statuses.map((s) => <option key={s} value={s}>{DOC_STATUS_LABEL[s] ?? s}</option>)}
        </select>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Cari</button>
      </form>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">Data tidak dapat dimuat. Muat ulang halaman.</p>
      ) : rows.length === 0 ? (
        <p className="mt-6 rounded-md border border-line bg-surface px-4 py-6">Belum ada {cfg.singular} yang cocok.</p>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>{cfg.columns.map((c) => <th key={c.path} scope="col" className={`px-4 py-3 font-semibold ${isNumericKind(c.kind) ? "text-right" : ""}`}>{c.label}</th>)}</tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={String(r.id)} className="border-b border-line last:border-0 hover:bg-background">
                  {cfg.columns.map((c, i) => (
                    <td key={c.path} className={`px-4 py-3 ${isNumericKind(c.kind) ? "text-right tabular-nums" : ""}`}>
                      {c.kind === "status" ? <DocStatusBadge status={String(getPath(r, c.path))} />
                        : i === 0 ? <Link href={`/d/${slug}/${r.id}`} className="font-semibold text-brand underline">{cellText(c, r)}</Link>
                        : cellText(c, r)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {rows.length === 200 && <p className="mt-3 text-muted">Menampilkan 200 dokumen terbaru. Persempit dengan pencarian atau filter status.</p>}
    </div>
  );
}
