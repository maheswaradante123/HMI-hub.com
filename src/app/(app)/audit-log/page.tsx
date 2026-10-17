import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { fmtDateTime } from "@/lib/docs/format";
import { loadNames } from "@/lib/pr/data";

const ACTION_LABEL: Record<string, string> = { INSERT: "Tambah", UPDATE: "Ubah", DELETE: "Hapus" };
type Log = { id: number; table_name: string; record_id: string; action: string; old_values: Record<string, unknown> | null; new_values: Record<string, unknown> | null; user_id: string | null; created_at: string };

function changes(l: Log): string[] {
  if (l.action === "UPDATE" && l.old_values && l.new_values) {
    return Object.keys(l.new_values).filter((k) => !["updated_at", "updated_by"].includes(k) && JSON.stringify(l.old_values![k]) !== JSON.stringify(l.new_values![k]))
      .map((k) => `${k}: ${JSON.stringify(l.old_values![k])} → ${JSON.stringify(l.new_values![k])}`);
  }
  const v = l.new_values ?? l.old_values ?? {};
  return Object.entries(v).filter(([k]) => !["created_at", "updated_at", "created_by", "updated_by"].includes(k)).map(([k, x]) => `${k}: ${JSON.stringify(x)}`);
}

export default async function AuditLogPage({ searchParams }: { searchParams: Promise<{ tabel?: string; aksi?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("audit_log", "view")) return <Forbidden roleName={session.roleName} what="Audit Log" />;
  const supabase = await createClient();
  const tabel = (sp.tabel ?? "").replace(/[^a-z_]/g, "");
  let q = supabase.from("audit_logs").select("*").order("id", { ascending: false }).limit(200);
  if (tabel) q = q.eq("table_name", tabel);
  if (sp.aksi && sp.aksi in ACTION_LABEL) q = q.eq("action", sp.aksi);
  const { data } = await q;
  const logs = (data ?? []) as Log[];
  const names = await loadNames(supabase, logs.map((l) => l.user_id));
  return (
    <div className="max-w-5xl">
      <h1 className="text-3xl font-bold">Audit Log</h1>
      <p className="mt-1 text-muted">Catatan siapa mengubah apa dan kapan. Catatan ini tidak bisa diubah atau dihapus.</p>
      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        <label htmlFor="tabel" className="sr-only">Nama tabel</label>
        <input id="tabel" name="tabel" defaultValue={tabel} placeholder="Nama tabel, mis. invoices" className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg" />
        <label htmlFor="aksi" className="sr-only">Aksi</label>
        <select id="aksi" name="aksi" defaultValue={sp.aksi ?? ""} className="rounded-md border-2 border-line bg-white px-3 py-2.5 text-lg">
          <option value="">Semua aksi</option>{Object.entries(ACTION_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">Cari</button>
      </form>
      <ul className="mt-6 space-y-2">
        {logs.length === 0 && <li className="rounded-md border border-line bg-surface px-4 py-6">Tidak ada catatan yang cocok.</li>}
        {logs.map((l) => (
          <li key={l.id} className="rounded-md border border-line bg-surface px-4 py-3">
            <details>
              <summary className="cursor-pointer text-lg">
                <b>{ACTION_LABEL[l.action] ?? l.action}</b> {l.table_name} · {l.user_id ? names[l.user_id] ?? "-" : "sistem"} · {fmtDateTime(l.created_at)}
              </summary>
              <p className="mt-2 text-sm text-muted">ID data: {l.record_id}</p>
              <ul className="mt-2 space-y-1 break-words font-mono text-sm">{changes(l).map((c, i) => <li key={i}>{c}</li>)}</ul>
            </details>
          </li>
        ))}
      </ul>
    </div>
  );
}
