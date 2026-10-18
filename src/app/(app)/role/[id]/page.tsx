import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { RoleForm } from "@/components/role-form";
import { ACTIONS, ACTION_LABEL, MODULE_LABEL } from "@/lib/modules";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function RoleDetailPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ ok?: string }> }) {
  const { id } = await params;
  const sp = await searchParams;
  if (!UUID.test(id)) notFound();
  const session = await requireSession();
  if (!session.can("role", "view")) return <Forbidden roleName={session.roleName} what="Hak Akses" />;
  const supabase = await createClient();
  const { data: role } = await supabase.from("roles").select("id, name, description, is_superuser").eq("id", id).maybeSingle();
  if (!role) notFound();
  const [{ data: perms }, { data: rp }] = await Promise.all([
    supabase.from("permissions").select("id, module, action"),
    supabase.from("role_permissions").select("permission_id").eq("role_id", id),
  ]);
  const byModule = new Map<string, Record<string, string>>();
  for (const p of perms ?? []) {
    const m = byModule.get(p.module as string) ?? {};
    m[p.action as string] = p.id as string;
    byModule.set(p.module as string, m);
  }
  const modules = [...byModule.entries()].map(([module, p]) => ({ module, label: MODULE_LABEL[module] ?? module, perms: p })).sort((a, b) => a.label.localeCompare(b.label, "id"));
  const granted = (rp ?? []).map((r) => r.permission_id as string);
  const canEdit = session.can("role", "edit") && !role.is_superuser;

  return (
    <div className="max-w-5xl">
      <Link href="/role" className="underline">&larr; Hak Akses</Link>
      <h1 className="mt-3 text-3xl font-bold">{role.name}</h1>
      {role.description && <p className="mt-1 text-muted">{role.description}</p>}
      {sp.ok && <p role="status" className="mt-4 rounded-md bg-warn-bg px-4 py-3">Izin tersimpan. Perubahan berlaku pada halaman berikutnya yang dibuka user.</p>}
      <div className="mt-6">
        {role.is_superuser ? (
          <p className="rounded-md border border-line bg-surface px-4 py-4 text-lg">Role ini memiliki akses penuh ke semua modul dan tidak bisa diubah.</p>
        ) : canEdit ? (
          <RoleForm roleId={id} modules={modules} granted={granted} />
        ) : (
          <div className="overflow-x-auto rounded-lg border border-line bg-surface">
            <table className="w-full text-left text-lg">
              <thead className="border-b border-line bg-background"><tr><th scope="col" className="px-4 py-3">Modul</th>{ACTIONS.map((a) => <th key={a} scope="col" className="px-3 py-3 text-center">{ACTION_LABEL[a]}</th>)}</tr></thead>
              <tbody>{modules.map((m) => (
                <tr key={m.module} className="border-b border-line last:border-0"><th scope="row" className="px-4 py-3 font-normal">{m.label}</th>
                  {ACTIONS.map((a) => <td key={a} className="px-3 py-3 text-center">{m.perms[a] && granted.includes(m.perms[a]) ? "✓" : ""}</td>)}</tr>
              ))}</tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
