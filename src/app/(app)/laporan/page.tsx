import { requireSession } from "@/lib/auth";
import { Forbidden } from "@/components/forbidden";
import { REPORTS } from "@/lib/reports";

export default async function ReportsPage() {
  const session = await requireSession();
  if (!session.can("report", "view")) return <Forbidden roleName={session.roleName} what="Laporan" />;
  const canExport = session.can("report", "export");
  const list = REPORTS.filter((r) => session.can(r.module, "view") && (!r.needs || session.can(...r.needs)));
  return (
    <div className="max-w-4xl">
      <h1 className="text-3xl font-bold">Laporan</h1>
      <p className="mt-1 text-muted">Unduh sebagai file CSV yang bisa dibuka di Excel. Isi laporan mengikuti izin akses Anda.</p>
      {!canExport && <p className="mt-4 rounded-md bg-warn-bg px-4 py-3">Role Anda belum memiliki izin mengunduh laporan.</p>}
      <div className="mt-6 space-y-4">
        {list.map((r) => (
          <form key={r.key} method="get" action={`/laporan/export/${r.key}`} className="rounded-lg border border-line bg-surface p-5">
            <h2 className="text-xl font-bold">{r.label}</h2>
            <p className="text-muted">{r.desc}</p>
            <div className="mt-3 flex flex-wrap items-end gap-3">
              {r.dateCol && (<>
                <div><label htmlFor={`d-${r.key}`} className="mb-1 block font-semibold">Dari tanggal</label><input id={`d-${r.key}`} type="date" name="dari" className="rounded-md border-2 border-line bg-white px-3 py-2 text-lg" /></div>
                <div><label htmlFor={`s-${r.key}`} className="mb-1 block font-semibold">Sampai tanggal</label><input id={`s-${r.key}`} type="date" name="sampai" className="rounded-md border-2 border-line bg-white px-3 py-2 text-lg" /></div>
              </>)}
              {canExport && <button type="submit" className="rounded-md bg-brand px-6 py-2.5 text-lg font-semibold text-white hover:bg-brand-dark">Unduh CSV</button>}
            </div>
          </form>
        ))}
        {list.length === 0 && <p className="rounded-md border border-line bg-surface px-4 py-6">Belum ada laporan yang tersedia untuk role Anda.</p>}
      </div>
    </div>
  );
}
