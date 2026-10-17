import Link from "next/link";
import { notFound } from "next/navigation";
import { requireSession } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { Forbidden } from "@/components/forbidden";
import { UserForm } from "@/components/user-form";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export default async function EditUserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const session = await requireSession();
  if (!session.can("user", "edit")) return <Forbidden roleName={session.roleName} what="perubahan user" />;
  const supabase = await createClient();
  const [{ data: u }, { data: roles }, { data: depts }] = await Promise.all([
    supabase.from("user_profiles").select("id, full_name, role_id, department_id, is_active").eq("id", id).maybeSingle(),
    supabase.from("roles").select("id, name").eq("is_active", true).order("name"),
    supabase.from("departments").select("id, name").order("name"),
  ]);
  if (!u) notFound();
  return (
    <div>
      <Link href="/user" className="underline">&larr; Semua user</Link>
      <h1 className="mb-6 mt-3 text-3xl font-bold">Ubah {u.full_name}</h1>
      <UserForm userId={id} fullName={u.full_name} roleId={u.role_id} deptId={u.department_id ?? ""} active={u.is_active} roles={(roles ?? []) as { id: string; name: string }[]} depts={(depts ?? []) as { id: string; name: string }[]} />
    </div>
  );
}
