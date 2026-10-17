import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ ok?: string }> }) {
  const sp = await searchParams;
  const session = await requireSession();
  if (!session.can("user", "view")) return <Forbidden roleName={session.roleName} what="User" />;
  const supabase = await createClient();
  const { data } = await supabase.from("user_profiles").select("id, full_name, is_active, roles(name), departments(name)").order("full_name");
  const rows = (data ?? []) as unknown as { id: string; full_name: string; is_active: boolean; roles: { name: string } | { name: string }[] | null; departments: { name: string } | { name: string }[] | null }[];
  const one = <T,>(v: T | T[] | null) => (Array.isArray(v) ? v[0] : v);
  const canEdit = session.can("user", "edit");
  return (
    <div className="max-w-4xl">
      <h1 className="text-3xl font-bold">User</h1>
      <p className="mt-1 text-muted">Akun baru dibuat lewat Supabase Auth (lihat README), lalu role dan departemennya diatur di sini.</p>
      {sp.ok && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">Perubahan tersimpan.</p>}
      <div className="mt-6 overflow-x-auto rounded-lg border border-line bg-surface">
        <table className="w-full text-left text-lg">
          <thead className="border-b border-line bg-background"><tr>{["Nama", "Role", "Departemen", "Status", ""].map((h, i) => <th key={i} scope="col" className="px-4 py-3">{h}</th>)}</tr></thead>
          <tbody>
            {rows.map((u) => (
              <tr key={u.id} className="border-b border-line last:border-0">
                <td className="px-4 py-3 font-semibold">{u.full_name}</td>
                <td className="px-4 py-3">{one(u.roles)?.name ?? "-"}</td>
                <td className="px-4 py-3">{one(u.departments)?.name ?? "-"}</td>
                <td className="px-4 py-3">{u.is_active ? "Aktif" : "Nonaktif"}</td>
                <td className="px-4 py-3">{canEdit && u.id !== session.userId && <Link href={`/user/${u.id}`} className="font-semibold text-brand underline">Ubah</Link>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
