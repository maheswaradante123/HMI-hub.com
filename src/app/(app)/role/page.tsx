import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { PermMatrix, type MatrixGroup } from "@/components/perm-matrix";
import { NAV } from "@/lib/nav";
import { MODULE_LABEL } from "@/lib/modules";

export default async function RolesPage() {
  const session = await requireSession();
  if (!session.can("role", "view")) return <Forbidden roleName={session.roleName} what="Hak Akses" />;
  const supabase = await createClient();
  const [{ data: roles }, { data: perms }, { data: rp }] = await Promise.all([
    supabase.from("roles").select("id, name, is_superuser").eq("is_active", true).order("name"),
    supabase.from("permissions").select("id, module, action"),
    supabase.from("role_permissions").select("role_id, permission_id"),
  ]);
  const byModule = new Map<string, Record<string, string>>();
  for (const p of perms ?? []) byModule.set(p.module as string, { ...(byModule.get(p.module as string) ?? {}), [p.action as string]: p.id as string });

  // Baris dikelompokkan seperti menu samping; modul tanpa menu (mis. dashboard, harga beli) masuk "Lainnya".
  const placed = new Set<string>();
  const groups: MatrixGroup[] = [];
  for (const g of NAV) {
    const rows: MatrixGroup["rows"] = [];
    for (const item of g.items) {
      const pm = byModule.get(item.module);
      if (!pm || placed.has(item.module)) continue;
      placed.add(item.module);
      rows.push({ module: item.module, label: item.module === "qurban" ? "Qurban Cerdas" : item.label, perms: pm });
    }
    if (rows.length) groups.push({ title: g.title, rows });
  }
  const rest = [...byModule.entries()].filter(([m]) => !placed.has(m)).map(([module, pm]) => ({ module, label: MODULE_LABEL[module] ?? module, perms: pm })).sort((a, b) => a.label.localeCompare(b.label, "id"));
  if (rest.length) groups.push({ title: "Lainnya", rows: rest });

  const ordered = [...(roles ?? [])].sort((a, b) => Number(b.is_superuser) - Number(a.is_superuser) || String(a.name).localeCompare(String(b.name), "id"));
  return (
    <div className="max-w-7xl">
      <h1 className="text-3xl font-bold">Hak Akses</h1>
      <p className="mb-6 mt-1 text-muted">Siapa yang boleh melihat, membuat, mengubah, membatalkan, menyetujui dan mengekspor. Dijaga di database, bukan hanya di tampilan menu.</p>
      <PermMatrix
        roles={ordered.map((r) => ({ id: r.id as string, name: r.name as string, superuser: !!r.is_superuser }))}
        groups={groups}
        granted={(rp ?? []).map((r) => `${r.role_id}:${r.permission_id}`)}
        canEdit={session.can("role", "edit")}
      />
    </div>
  );
}
