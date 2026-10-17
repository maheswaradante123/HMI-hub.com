import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { COLUMN_LABELS, RESOURCES } from "@/lib/master/config";
import { loadRefs } from "@/lib/master/refs";
import { Forbidden } from "@/components/forbidden";
import { setActive } from "../actions";

const NOTICES: Record<string, { text: string; error?: boolean }> = {
  ditambah: { text: "Data berhasil ditambahkan." },
  diubah: { text: "Perubahan berhasil disimpan." },
  diaktifkan: { text: "Data diaktifkan kembali." },
  dinonaktifkan: { text: "Data dinonaktifkan. Riwayatnya tetap tersimpan." },
  izin: { text: "Anda tidak memiliki izin untuk melakukan ini.", error: true },
  gagal: { text: "Perubahan gagal disimpan. Silakan coba lagi.", error: true },
};

export default async function ResourceListPage({
  params,
  searchParams,
}: {
  params: Promise<{ resource: string }>;
  searchParams: Promise<{ q?: string; semua?: string; ok?: string; error?: string }>;
}) {
  const { resource: key } = await params;
  const sp = await searchParams;
  const resource = RESOURCES[key];
  if (!resource) notFound();

  const session = await requireSession();
  if (!session.can(resource.module, "view")) {
    return <Forbidden roleName={session.roleName} what={resource.label} />;
  }
  const canCreate = session.can(resource.module, "create");
  const canEdit = session.can(resource.module, "edit");

  const supabase = await createClient();
  let query = supabase.from(resource.table).select("*").order("name").limit(500);
  if (!sp.semua) query = query.eq("is_active", true);
  const q = (sp.q ?? "").replace(/[,()%*\\]/g, " ").trim();
  if (q) query = query.or(`code.ilike.%${q}%,name.ilike.%${q}%`);
  const { data: rows, error } = await query;
  const refs = await loadRefs(supabase, resource);

  const cell = (row: Record<string, unknown>, col: string) => {
    const field = resource.fields.find((f) => f.name === col);
    const v = row[col];
    if (v === null || v === undefined || v === "") return "-";
    if (field?.type === "ref") return refs[field.ref!]?.find((o) => o.value === v)?.label ?? "-";
    if (field?.type === "select") return field.options!.find((o) => o.value === v)?.label.split(" (")[0] ?? String(v);
    if (field?.type === "number") return Number(v).toLocaleString("id-ID", { maximumFractionDigits: 3 });
    return String(v);
  };

  const notice = NOTICES[sp.ok ?? sp.error ?? ""];
  const listUrl = (extra: Record<string, string>) => {
    const p = new URLSearchParams({ ...(q ? { q } : {}), ...extra });
    return `/data/${key}${p.size ? `?${p}` : ""}`;
  };

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-3xl font-bold">{resource.label}</h1>
        {canCreate && (
          <Link
            href={`/data/${key}/baru`}
            className="rounded-md bg-brand px-5 py-3 text-lg font-semibold text-white hover:bg-brand-dark"
          >
            + Tambah {resource.singular.toLowerCase()}
          </Link>
        )}
      </div>

      {notice && (
        <p
          role="status"
          className={`mt-4 rounded-md px-4 py-3 ${notice.error ? "bg-danger-bg text-danger" : "bg-warn-bg"}`}
        >
          {notice.text}
        </p>
      )}

      <form className="mt-5 flex flex-wrap items-center gap-3" role="search">
        <label htmlFor="q" className="sr-only">
          Cari
        </label>
        <input
          id="q"
          name="q"
          defaultValue={q}
          placeholder="Cari kode atau nama"
          className="w-72 rounded-md border-2 border-line bg-white px-4 py-2.5 text-lg"
        />
        {sp.semua && <input type="hidden" name="semua" value="1" />}
        <button type="submit" className="rounded-md border-2 border-line px-5 py-2.5 text-lg font-semibold hover:bg-background">
          Cari
        </button>
        <Link href={listUrl(sp.semua ? {} : { semua: "1" })} className="text-lg underline">
          {sp.semua ? "Sembunyikan yang nonaktif" : "Tampilkan yang nonaktif"}
        </Link>
      </form>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-danger-bg px-4 py-3 text-danger">
          Data tidak dapat dimuat. Muat ulang halaman, atau hubungi Owner jika masih gagal.
        </p>
      ) : !rows || rows.length === 0 ? (
        <p className="mt-6 rounded-md border border-line bg-surface px-4 py-6">
          {q ? "Tidak ada data yang cocok dengan pencarian." : "Belum ada data."}
          {canCreate && !q && " Klik tombol Tambah untuk memulai."}
        </p>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
          <table className="w-full text-left text-lg">
            <thead className="border-b border-line bg-background">
              <tr>
                {resource.columns.map((c) => (
                  <th key={c} scope="col" className="px-4 py-3 font-semibold">
                    {COLUMN_LABELS[c] ?? c}
                  </th>
                ))}
                <th scope="col" className="px-4 py-3 font-semibold">Status</th>
                {canEdit && <th scope="col" className="px-4 py-3 font-semibold">Aksi</th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-b border-line last:border-b-0">
                  {resource.columns.map((c) => (
                    <td key={c} className="px-4 py-3">
                      {cell(row, c)}
                    </td>
                  ))}
                  <td className="px-4 py-3">
                    <span
                      className={`rounded px-2 py-1 text-base font-semibold ${
                        row.is_active ? "bg-green-100 text-green-900" : "bg-neutral-200 text-neutral-700"
                      }`}
                    >
                      {row.is_active ? "Aktif" : "Nonaktif"}
                    </span>
                  </td>
                  {canEdit && (
                    <td className="whitespace-nowrap px-4 py-3">
                      <Link href={`/data/${key}/${row.id}`} className="mr-4 font-semibold text-brand underline">
                        Ubah
                      </Link>
                      <form action={setActive.bind(null, key, row.id, !row.is_active)} className="inline">
                        <button type="submit" className="underline">
                          {row.is_active ? "Nonaktifkan" : "Aktifkan"}
                        </button>
                      </form>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
