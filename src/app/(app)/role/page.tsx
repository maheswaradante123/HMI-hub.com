import Link from "next/link";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";

export default async function RolesPage() {
  const session = await requireSession();
  if (!session.can("role", "view")) return <Forbidden roleName={session.roleName} what="Role & Izin" />;
  const supabase = await createClient();
  const [{ data: roles }, { data: rp }] = await Promise.all([
    supabase.from("roles").select("id, code, name, description, is_superuser, is_active").order("name"),
    supabase.from("role_permissions").select("role_id"),
  ]);
  const count = new Map<string, number>();
  for (const r of rp ?? []) count.set(r.role_id as string, (count.get(r.role_id as string) ?? 0) + 1);
  return (
    <div className="max-w-3xl">
      <h1 className="text-3xl font-bold">Role & Izin</h1>
      <p className="mt-1 text-muted">Izin diperiksa di database, bukan hanya di tampilan menu.</p>
      <ul className="mt-6 space-y-2">
        {(roles ?? []).map((r) => (
          <li key={r.id as string}>
            <Link href={`/role/${r.id}`} className="block rounded-lg border border-line bg-surface px-5 py-4 hover:bg-background">
              <span className="text-lg font-semibold">{r.name}</span>{" "}
              <span className="text-muted">{r.is_superuser ? "Akses penuh" : `${count.get(r.id as string) ?? 0} izin`}{r.is_active ? "" : " (nonaktif)"}</span>
              {r.description ? <span className="block text-muted">{r.description}</span> : null}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
